import { Router } from "express";
import { randomUUID } from "node:crypto";
import { db } from "../db.js";
import { requireUser } from "../identity.js";

export const meRouter = Router();

const findLatestVerificationRequest = db.prepare(`
  SELECT * FROM verification_requests WHERE user_id = ? ORDER BY created_at DESC LIMIT 1
`);
const insertVerificationRequest = db.prepare(`
  INSERT INTO verification_requests (id, user_id, reason) VALUES (?, ?, ?)
`);

const upsertDeviceToken = db.prepare(`
  INSERT INTO device_tokens (user_id, apns_token) VALUES (?, ?)
  ON CONFLICT (user_id, apns_token) DO NOTHING
`);
const deleteDeviceToken = db.prepare(
  "DELETE FROM device_tokens WHERE user_id = ? AND apns_token = ?"
);

const listCreatedByUser = db.prepare(`
  SELECT e.*
  FROM events e
  WHERE e.owner_id = ? AND e.deleted_at IS NULL
  ORDER BY e.start_at ASC
`);

const listResponsesForUser = db.prepare(`
  SELECT e.*, u.display_name AS owner_name, r.status, r.responded_at
  FROM event_responses r
  JOIN events e ON e.id = r.event_id
  JOIN users u ON u.id = e.owner_id
  WHERE r.user_id = ? AND r.status IN ('accepted', 'rejected') AND e.deleted_at IS NULL
  ORDER BY e.start_at ASC
`);

const listNotifications = db.prepare(`
  SELECT * FROM notifications WHERE user_id = ? ORDER BY created_at DESC LIMIT 100
`);
const markAllNotificationsRead = db.prepare(`
  UPDATE notifications SET read_at = datetime('now') WHERE user_id = ? AND read_at IS NULL
`);

meRouter.get("/", requireUser, (req, res) => {
  res.json(req.user);
});

// POST /me/device-token — register this device for push notifications.
meRouter.post("/device-token", requireUser, (req, res) => {
  const token = req.body?.token;
  if (!token) {
    return res.status(400).json({ error: "token is required" });
  }
  upsertDeviceToken.run(req.user.id, token);
  res.status(204).end();
});

// DELETE /me/device-token — stop notifying this device (e.g. on sign out).
meRouter.delete("/device-token", requireUser, (req, res) => {
  const token = req.body?.token;
  if (!token) {
    return res.status(400).json({ error: "token is required" });
  }
  deleteDeviceToken.run(req.user.id, token);
  res.status(204).end();
});

meRouter.get("/created", requireUser, (req, res) => {
  res.json(listCreatedByUser.all(req.user.id));
});

meRouter.get("/responses", requireUser, (req, res) => {
  res.json(listResponsesForUser.all(req.user.id));
});

// GET /me/verification-request — latest request (or null) so the UI can
// show its current status across app relaunches.
meRouter.get("/verification-request", requireUser, (req, res) => {
  res.json(findLatestVerificationRequest.get(req.user.id) ?? null);
});

// POST /me/verification-request — ask an admin to lift the creation limit.
meRouter.post("/verification-request", requireUser, (req, res) => {
  if (req.user.role !== "basic") {
    return res.status(400).json({ error: "only basic accounts can request verification" });
  }
  const existing = findLatestVerificationRequest.get(req.user.id);
  if (existing?.status === "pending") {
    return res.status(409).json(existing);
  }

  const id = randomUUID();
  insertVerificationRequest.run(id, req.user.id, req.body?.reason ?? null);
  res.status(201).json(findLatestVerificationRequest.get(req.user.id));
});

// GET /me/notifications — history of pushes sent to this user (the bell icon).
meRouter.get("/notifications", requireUser, (req, res) => {
  res.json(listNotifications.all(req.user.id));
});

// POST /me/notifications/read — marks everything currently unread as read.
meRouter.post("/notifications/read", requireUser, (req, res) => {
  markAllNotificationsRead.run(req.user.id);
  res.status(204).end();
});
