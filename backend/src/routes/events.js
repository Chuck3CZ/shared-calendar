import { Router } from "express";
import { randomUUID } from "node:crypto";
import { db } from "../db.js";
import { requireUser } from "../identity.js";
import { notifyUser, notifyOtherUsers, notifyAdmins } from "../notifications.js";
import { refreshWeatherForEvent } from "../weather.js";

export const eventsRouter = Router();

// Keep in sync with EventCategory in the iOS app (Models/EventCategory.swift).
const ALLOWED_CATEGORIES = ["jidlo", "zabava", "kultura", "konference", "ostatni"];
const DEFAULT_CATEGORY = "ostatni";

const listEvents = db.prepare(`
  SELECT e.*, u.display_name AS owner_name, u.role AS owner_role,
    (SELECT r.status FROM event_responses r WHERE r.event_id = e.id AND r.user_id = ?) AS my_status,
    (SELECT COUNT(*) FROM event_responses r WHERE r.event_id = e.id AND r.status = 'accepted') AS accepted_count
  FROM events e
  JOIN users u ON u.id = e.owner_id
  WHERE e.deleted_at IS NULL AND e.start_at >= ? AND e.start_at <= ?
  ORDER BY e.start_at ASC
`);

const insertEvent = db.prepare(`
  INSERT INTO events (id, owner_id, title, description, location, start_at, end_at, latitude, longitude, category)
  VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
`);

const updateEvent = db.prepare(`
  UPDATE events SET title = ?, description = ?, location = ?, start_at = ?, end_at = ?, latitude = ?, longitude = ?, category = ?
  WHERE id = ? AND owner_id = ?
`);

// Permission (owner or admin) is checked in the route handler; this just
// applies the delete once that's settled.
const softDeleteEvent = db.prepare(`
  UPDATE events SET deleted_at = datetime('now') WHERE id = ?
`);

const getEvent = db.prepare("SELECT * FROM events WHERE id = ?");

const getEventWithOwner = db.prepare(`
  SELECT e.*, u.display_name AS owner_name, u.role AS owner_role,
    (SELECT r.status FROM event_responses r WHERE r.event_id = e.id AND r.user_id = ?) AS my_status,
    (SELECT COUNT(*) FROM event_responses r WHERE r.event_id = e.id AND r.status = 'accepted') AS accepted_count
  FROM events e
  JOIN users u ON u.id = e.owner_id
  WHERE e.id = ? AND e.deleted_at IS NULL
`);

// Counts all events created in the window regardless of deleted_at, so
// deleting one and recreating it can't be used to dodge the rate limit.
const countRecentEventsByOwner = db.prepare(`
  SELECT COUNT(*) AS count FROM events
  WHERE owner_id = ? AND created_at >= datetime('now', '-14 days')
`);

const BASIC_RATE_LIMIT = 2;

const upsertResponse = db.prepare(`
  INSERT INTO event_responses (user_id, event_id, status, responded_at)
  VALUES (?, ?, ?, datetime('now'))
  ON CONFLICT (user_id, event_id)
  DO UPDATE SET status = excluded.status, responded_at = excluded.responded_at
`);

const DEFAULT_REMINDER_MINUTES = 120;
const ALLOWED_REMINDER_MINUTES = [0, 10, 30, 60, 120, 1440];
const MAX_REMINDERS_PER_RESPONSE = 2;

const countReminders = db.prepare(
  "SELECT COUNT(*) AS count FROM reminder_settings WHERE user_id = ? AND event_id = ?"
);
const insertReminder = db.prepare(
  "INSERT INTO reminder_settings (id, user_id, event_id, minutes_before) VALUES (?, ?, ?, ?)"
);
const deleteReminders = db.prepare(
  "DELETE FROM reminder_settings WHERE user_id = ? AND event_id = ?"
);
const listReminders = db.prepare(
  "SELECT minutes_before FROM reminder_settings WHERE user_id = ? AND event_id = ? ORDER BY minutes_before ASC"
);
const listAcceptedAttendees = db.prepare(
  "SELECT user_id FROM event_responses WHERE event_id = ? AND status = 'accepted' AND user_id != ?"
);

const insertEventReport = db.prepare(
  "INSERT INTO event_reports (id, event_id, reporter_id, reason) VALUES (?, ?, ?, ?)"
);

const listPendingForUser = db.prepare(`
  SELECT e.*, u.display_name AS owner_name,
    (SELECT COUNT(*) FROM event_responses r2 WHERE r2.event_id = e.id AND r2.status = 'accepted') AS accepted_count
  FROM events e
  JOIN users u ON u.id = e.owner_id
  LEFT JOIN event_responses r ON r.event_id = e.id AND r.user_id = ?
  WHERE e.deleted_at IS NULL AND r.status IS NULL AND (e.owner_id != ? OR ? = 'admin')
  ORDER BY e.start_at ASC
`);

// Same visibility rule as pending, but ignores prior responses so a user
// can revisit and overwrite a decision they already made.
const listReviewForUser = db.prepare(`
  SELECT e.*, u.display_name AS owner_name,
    (SELECT COUNT(*) FROM event_responses r WHERE r.event_id = e.id AND r.status = 'accepted') AS accepted_count
  FROM events e
  JOIN users u ON u.id = e.owner_id
  WHERE e.deleted_at IS NULL AND (e.owner_id != ? OR ? = 'admin')
  ORDER BY e.start_at ASC
`);

// GET /events?from=ISO&to=ISO — public, no auth required
eventsRouter.get("/", (req, res) => {
  const from = req.query.from || "0000-01-01";
  const to = req.query.to || "9999-12-31";
  res.json(listEvents.all(req.user?.id ?? null, from, to));
});

// GET /events/pending — cards not yet swiped by the current user
eventsRouter.get("/pending", requireUser, (req, res) => {
  // Admins can temporarily test the app as a regular member without a
  // second account — the client sends this header, nothing is persisted.
  const viewAsMember = req.header("X-View-As") === "member";
  const effectiveRole = viewAsMember ? "basic" : req.user.role;
  res.json(listPendingForUser.all(req.user.id, req.user.id, effectiveRole));
});

// A location is required, and must come from the map picker (which always
// attaches coordinates) rather than be freely typed — keeps addresses
// accurate enough to actually navigate to and to show weather for.
function locationIsMissingOrImprecise(location, latitude, longitude) {
  return !location || latitude == null || longitude == null;
}

// A malformed start_at would otherwise pass silently through as NaN and
// permanently wedge that reminder — checkAndSendReminders() compares
// against a NaN timestamp, which is never <= anything, so it's never
// marked notified and gets re-evaluated every minute forever.
function isValidISODate(value) {
  return typeof value === "string" && !Number.isNaN(new Date(value).getTime());
}

function eventTimesError(start_at, end_at) {
  if (!isValidISODate(start_at)) return "start_at must be a valid date";
  if (end_at != null && !isValidISODate(end_at)) return "end_at must be a valid date";
  if (end_at != null && new Date(end_at) <= new Date(start_at)) return "end_at must be after start_at";
  return null;
}

// POST /events — create an event (requires identity)
eventsRouter.post("/", requireUser, (req, res) => {
  const { title, description, location, start_at, end_at, latitude, longitude, category } = req.body;
  if (!title || !start_at) {
    return res.status(400).json({ error: "title and start_at are required" });
  }
  if (locationIsMissingOrImprecise(location, latitude, longitude)) {
    return res.status(400).json({ error: "location is required and must be picked from the map" });
  }
  const timesError = eventTimesError(start_at, end_at);
  if (timesError) {
    return res.status(400).json({ error: timesError });
  }
  if (category != null && !ALLOWED_CATEGORIES.includes(category)) {
    return res.status(400).json({ error: `category must be one of ${ALLOWED_CATEGORIES.join(", ")}` });
  }

  if (req.user.role === "basic") {
    const { count } = countRecentEventsByOwner.get(req.user.id);
    if (count >= BASIC_RATE_LIMIT) {
      return res.status(429).json({
        error: "rate_limited",
        message: `Základní účet může vytvořit nejvýš ${BASIC_RATE_LIMIT} akce za 14 dní. Požádej o ověření pro neomezené vytváření.`,
      });
    }
  }

  const id = randomUUID();
  insertEvent.run(
    id, req.user.id, title, description ?? null, location ?? null, start_at, end_at ?? null,
    latitude ?? null, longitude ?? null, category ?? DEFAULT_CATEGORY
  );

  notifyOtherUsers(req.user.id, {
    title: "Nová akce",
    body: location ? `${title} — ${location}` : title,
    data: { event_id: id },
  }).catch((error) => console.error("new-event push failed:", error));

  refreshWeatherForEvent(id, latitude, longitude, start_at).catch((error) =>
    console.error("weather refresh failed:", error)
  );

  res.status(201).json(getEvent.get(id));
});

// GET /events/review — every visible event regardless of prior response,
// so the user can swipe again and overwrite an earlier decision.
eventsRouter.get("/review", requireUser, (req, res) => {
  const viewAsMember = req.header("X-View-As") === "member";
  const effectiveRole = viewAsMember ? "basic" : req.user.role;
  res.json(listReviewForUser.all(req.user.id, effectiveRole));
});

// GET /events/:id — a single event (public, like the list) — used for
// deep links (universal links / share) so a specific event can be
// fetched without pulling the whole from/to range.
eventsRouter.get("/:id", (req, res) => {
  const event = getEventWithOwner.get(req.user?.id ?? null, req.params.id);
  if (!event) {
    return res.status(404).json({ error: "event not found" });
  }
  res.json(event);
});

// POST /events/:id/response — swipe accept/reject
eventsRouter.post("/:id/response", requireUser, (req, res) => {
  const { status } = req.body;
  if (!["accepted", "rejected"].includes(status)) {
    return res.status(400).json({ error: "status must be 'accepted' or 'rejected'" });
  }

  const event = getEvent.get(req.params.id);
  if (!event || event.deleted_at) {
    return res.status(404).json({ error: "event not found" });
  }

  upsertResponse.run(req.user.id, event.id, status);

  // Rejecting no longer wipes reminder_settings — the reminder scheduler
  // already only fires for status = 'accepted', so a leftover row for a
  // rejected event is inert. Deleting it here used to mean an accidental
  // reject-then-re-accept lost whatever custom offsets you'd picked,
  // silently replaced by the default on re-accept.
  if (status === "accepted" && countReminders.get(req.user.id, event.id).count === 0) {
    insertReminder.run(randomUUID(), req.user.id, event.id, DEFAULT_REMINDER_MINUTES);
  }

  res.json({ event_id: event.id, status });
});

// GET /events/:id/reminders — your reminder offsets for this event (empty if not attending)
eventsRouter.get("/:id/reminders", requireUser, (req, res) => {
  const minutes = listReminders.all(req.user.id, req.params.id).map((r) => r.minutes_before);
  res.json({ minutes });
});

// PUT /events/:id/reminders — replace your reminder offsets for this event.
// Mirrors iOS Calendar's first/second alert: up to two offsets, from a fixed
// set of options surfaced in the app.
eventsRouter.put("/:id/reminders", requireUser, (req, res) => {
  const event = getEvent.get(req.params.id);
  if (!event || event.deleted_at) {
    return res.status(404).json({ error: "event not found" });
  }

  const response = db
    .prepare("SELECT status FROM event_responses WHERE user_id = ? AND event_id = ?")
    .get(req.user.id, event.id);
  if (response?.status !== "accepted") {
    return res.status(400).json({ error: "you can only set reminders for events you're attending" });
  }

  const minutes = req.body?.minutes;
  if (!Array.isArray(minutes) || minutes.length > MAX_REMINDERS_PER_RESPONSE) {
    return res.status(400).json({ error: `minutes must be an array of at most ${MAX_REMINDERS_PER_RESPONSE} values` });
  }
  const unique = [...new Set(minutes)];
  if (unique.some((m) => !ALLOWED_REMINDER_MINUTES.includes(m))) {
    return res.status(400).json({ error: `minutes must be one of ${ALLOWED_REMINDER_MINUTES.join(", ")}` });
  }

  deleteReminders.run(req.user.id, event.id);
  for (const m of unique) {
    insertReminder.run(randomUUID(), req.user.id, event.id, m);
  }
  res.json({ minutes: unique.sort((a, b) => a - b) });
});

// PATCH /events/:id — edit an event you own
eventsRouter.patch("/:id", requireUser, (req, res) => {
  const event = getEvent.get(req.params.id);
  if (!event || event.deleted_at) {
    return res.status(404).json({ error: "event not found" });
  }
  if (event.owner_id !== req.user.id && req.user.role !== "admin") {
    return res.status(403).json({ error: "you can only edit your own events" });
  }

  const { title, description, location, start_at, end_at, latitude, longitude, category } = req.body;
  if (!title || !start_at) {
    return res.status(400).json({ error: "title and start_at are required" });
  }
  if (locationIsMissingOrImprecise(location, latitude, longitude)) {
    return res.status(400).json({ error: "location is required and must be picked from the map" });
  }
  const timesError = eventTimesError(start_at, end_at);
  if (timesError) {
    return res.status(400).json({ error: timesError });
  }
  if (category != null && !ALLOWED_CATEGORIES.includes(category)) {
    return res.status(400).json({ error: `category must be one of ${ALLOWED_CATEGORIES.join(", ")}` });
  }

  // Matched by the event's actual owner, not the requester — otherwise an
  // admin editing someone else's event would silently update zero rows.
  updateEvent.run(
    title, description ?? null, location ?? null, start_at, end_at ?? null,
    latitude ?? null, longitude ?? null, category ?? event.category ?? DEFAULT_CATEGORY,
    event.id, event.owner_id
  );

  for (const { user_id } of listAcceptedAttendees.all(event.id, req.user.id)) {
    notifyUser(user_id, {
      title: "Akce upravena",
      body: `${title} — zkontroluj si detaily`,
      data: { event_id: event.id },
    }).catch((error) => console.error("edit-event push failed:", error));
  }

  // Location and/or time may have changed — refetch rather than trust
  // whatever was cached for the old ones.
  refreshWeatherForEvent(event.id, latitude, longitude, start_at).catch((error) =>
    console.error("weather refresh failed:", error)
  );

  res.json(getEvent.get(event.id));
});

// POST /events/:id/report — flag an event for admin review (Guideline
// 1.2: user-generated content needs a way to report it). Anyone signed in
// can report, including the owner's own event isn't blocked — moderation
// is a judgment call for an admin to make, not enforced here.
eventsRouter.post("/:id/report", requireUser, (req, res) => {
  const event = getEvent.get(req.params.id);
  if (!event || event.deleted_at) {
    return res.status(404).json({ error: "event not found" });
  }
  const reason = req.body?.reason;
  if (!reason || !reason.trim()) {
    return res.status(400).json({ error: "reason is required" });
  }

  const id = randomUUID();
  insertEventReport.run(id, event.id, req.user.id, reason.trim());

  notifyAdmins({
    title: "Nahlášená akce",
    body: `${event.title}: ${reason.trim().slice(0, 100)}`,
    data: { event_id: event.id },
  }).catch((error) => console.error("event-report push failed:", error));

  res.status(201).json({ id });
});

// DELETE /events/:id — move an event to the trash (soft delete). Owners can
// delete their own; admins can moderate anyone's.
eventsRouter.delete("/:id", requireUser, (req, res) => {
  const event = getEvent.get(req.params.id);
  if (!event || event.deleted_at) {
    return res.status(404).json({ error: "event not found" });
  }
  if (event.owner_id !== req.user.id && req.user.role !== "admin") {
    return res.status(403).json({ error: "you can only delete your own events" });
  }

  softDeleteEvent.run(event.id);
  res.json({ event_id: event.id, deleted: true });
});
