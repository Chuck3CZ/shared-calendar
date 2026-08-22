import { Router } from "express";
import { db } from "../db.js";
import { requireUser } from "../identity.js";

export const meRouter = Router();

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

meRouter.get("/", requireUser, (req, res) => {
  res.json(req.user);
});

meRouter.get("/created", requireUser, (req, res) => {
  res.json(listCreatedByUser.all(req.user.id));
});

meRouter.get("/responses", requireUser, (req, res) => {
  res.json(listResponsesForUser.all(req.user.id));
});
