import { Router } from "express";
import { randomUUID } from "node:crypto";
import { db } from "../db.js";
import { requireUser } from "../identity.js";

export const eventsRouter = Router();

const listEvents = db.prepare(`
  SELECT e.*, u.display_name AS owner_name
  FROM events e
  JOIN users u ON u.id = e.owner_id
  WHERE e.start_at >= ? AND e.start_at <= ?
  ORDER BY e.start_at ASC
`);

const insertEvent = db.prepare(`
  INSERT INTO events (id, owner_id, title, description, location, start_at, end_at)
  VALUES (?, ?, ?, ?, ?, ?, ?)
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
  WHERE r.status IS NULL AND (e.owner_id != ? OR ? = 'admin')
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

// POST /events/:id/response — swipe accept/reject
eventsRouter.post("/:id/response", requireUser, (req, res) => {
  const { status } = req.body;
  if (!["accepted", "rejected"].includes(status)) {
    return res.status(400).json({ error: "status must be 'accepted' or 'rejected'" });
  }

  const event = getEvent.get(req.params.id);
  if (!event) {
    return res.status(404).json({ error: "event not found" });
  }

  upsertResponse.run(req.user.id, event.id, status);
  res.json({ event_id: event.id, status });
});
