import { Router } from "express";
import { randomUUID } from "node:crypto";
import { db } from "../db.js";
import { requireUser } from "../identity.js";

export const eventsRouter = Router();

const listEvents = db.prepare(`
  SELECT e.*, u.display_name AS owner_name
  FROM events e
  JOIN users u ON u.id = e.owner_id
  WHERE e.deleted_at IS NULL AND e.start_at >= ? AND e.start_at <= ?
  ORDER BY e.start_at ASC
`);

const insertEvent = db.prepare(`
  INSERT INTO events (id, owner_id, title, description, location, start_at, end_at)
  VALUES (?, ?, ?, ?, ?, ?, ?)
`);

const updateEvent = db.prepare(`
  UPDATE events SET title = ?, description = ?, location = ?, start_at = ?, end_at = ?
  WHERE id = ? AND owner_id = ?
`);

const softDeleteEvent = db.prepare(`
  UPDATE events SET deleted_at = datetime('now') WHERE id = ? AND owner_id = ?
`);

const getEvent = db.prepare("SELECT * FROM events WHERE id = ?");

const upsertResponse = db.prepare(`
  INSERT INTO event_responses (user_id, event_id, status, responded_at)
  VALUES (?, ?, ?, datetime('now'))
  ON CONFLICT (user_id, event_id)
  DO UPDATE SET status = excluded.status, responded_at = excluded.responded_at
`);

const listPendingForUser = db.prepare(`
  SELECT e.*, u.display_name AS owner_name
  FROM events e
  JOIN users u ON u.id = e.owner_id
  LEFT JOIN event_responses r ON r.event_id = e.id AND r.user_id = ?
  WHERE e.deleted_at IS NULL AND r.status IS NULL AND (e.owner_id != ? OR ? = 'admin')
  ORDER BY e.start_at ASC
`);

// Same visibility rule as pending, but ignores prior responses so a user
// can revisit and overwrite a decision they already made.
const listReviewForUser = db.prepare(`
  SELECT e.*, u.display_name AS owner_name
  FROM events e
  JOIN users u ON u.id = e.owner_id
  WHERE e.deleted_at IS NULL AND (e.owner_id != ? OR ? = 'admin')
  ORDER BY e.start_at ASC
`);

// GET /events?from=ISO&to=ISO — public, no auth required
eventsRouter.get("/", (req, res) => {
  const from = req.query.from || "0000-01-01";
  const to = req.query.to || "9999-12-31";
  res.json(listEvents.all(from, to));
});

// GET /events/pending — cards not yet swiped by the current user
eventsRouter.get("/pending", requireUser, (req, res) => {
  // Admins can temporarily test the app as a regular member without a
  // second account — the client sends this header, nothing is persisted.
  const viewAsMember = req.header("X-View-As") === "member";
  const effectiveRole = viewAsMember ? "basic" : req.user.role;
  res.json(listPendingForUser.all(req.user.id, req.user.id, effectiveRole));
});

// POST /events — create an event (requires identity)
eventsRouter.post("/", requireUser, (req, res) => {
  const { title, description, location, start_at, end_at } = req.body;
  if (!title || !start_at) {
    return res.status(400).json({ error: "title and start_at are required" });
  }

  const id = randomUUID();
  insertEvent.run(id, req.user.id, title, description ?? null, location ?? null, start_at, end_at ?? null);
  res.status(201).json(getEvent.get(id));
});

// GET /events/review — every visible event regardless of prior response,
// so the user can swipe again and overwrite an earlier decision.
eventsRouter.get("/review", requireUser, (req, res) => {
  const viewAsMember = req.header("X-View-As") === "member";
  const effectiveRole = viewAsMember ? "basic" : req.user.role;
  res.json(listReviewForUser.all(req.user.id, effectiveRole));
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
  res.json({ event_id: event.id, status });
});

// PATCH /events/:id — edit an event you own
eventsRouter.patch("/:id", requireUser, (req, res) => {
  const event = getEvent.get(req.params.id);
  if (!event || event.deleted_at) {
    return res.status(404).json({ error: "event not found" });
  }
  if (event.owner_id !== req.user.id) {
    return res.status(403).json({ error: "you can only edit your own events" });
  }

  const { title, description, location, start_at, end_at } = req.body;
  if (!title || !start_at) {
    return res.status(400).json({ error: "title and start_at are required" });
  }

  updateEvent.run(title, description ?? null, location ?? null, start_at, end_at ?? null, event.id, req.user.id);
  res.json(getEvent.get(event.id));
});

// DELETE /events/:id — move an event you own to the trash (soft delete)
eventsRouter.delete("/:id", requireUser, (req, res) => {
  const event = getEvent.get(req.params.id);
  if (!event || event.deleted_at) {
    return res.status(404).json({ error: "event not found" });
  }
  if (event.owner_id !== req.user.id) {
    return res.status(403).json({ error: "you can only delete your own events" });
  }

  softDeleteEvent.run(event.id, req.user.id);
  res.json({ event_id: event.id, deleted: true });
});
