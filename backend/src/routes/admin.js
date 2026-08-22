import { Router } from "express";
import { db } from "../db.js";
import { requireUser } from "../identity.js";

export const adminRouter = Router();

const setRole = db.prepare("UPDATE users SET role = ? WHERE id = ?");

// POST /admin/bootstrap — one-time self-promotion to admin, gated by a
// secret only you know (set via ADMIN_BOOTSTRAP_SECRET). Meant for
// initial setup/testing before a real admin-management UI exists.
adminRouter.post("/bootstrap", requireUser, (req, res) => {
  const expected = process.env.ADMIN_BOOTSTRAP_SECRET;
  if (!expected) {
    return res.status(503).json({ error: "ADMIN_BOOTSTRAP_SECRET is not configured" });
  }
  if (req.header("X-Bootstrap-Secret") !== expected) {
    return res.status(403).json({ error: "invalid bootstrap secret" });
  }

  setRole.run("admin", req.user.id);
  res.json({ id: req.user.id, role: "admin" });
});
