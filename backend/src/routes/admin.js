import { Router } from "express";
import { db } from "../db.js";
import { requireUser, requireAdmin } from "../identity.js";

export const adminRouter = Router();

const setRole = db.prepare("UPDATE users SET role = ? WHERE id = ?");

const listPendingVerificationRequests = db.prepare(`
  SELECT v.*, u.display_name AS user_display_name
  FROM verification_requests v
  JOIN users u ON u.id = v.user_id
  WHERE v.status = 'pending'
  ORDER BY v.created_at ASC
`);
const getVerificationRequest = db.prepare("SELECT * FROM verification_requests WHERE id = ?");
const setVerificationRequestStatus = db.prepare(
  "UPDATE verification_requests SET status = ? WHERE id = ?"
);

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

// GET /admin/verification-requests — pending requests waiting on a decision
adminRouter.get("/verification-requests", requireAdmin, (req, res) => {
  res.json(listPendingVerificationRequests.all());
});

// POST /admin/verification-requests/:id/approve — lifts the requester to 'verified'
adminRouter.post("/verification-requests/:id/approve", requireAdmin, (req, res) => {
  const request = getVerificationRequest.get(req.params.id);
  if (!request) {
    return res.status(404).json({ error: "verification request not found" });
  }
  setVerificationRequestStatus.run("approved", request.id);
  setRole.run("verified", request.user_id);
  res.json({ id: request.id, status: "approved" });
});

// POST /admin/verification-requests/:id/reject
adminRouter.post("/verification-requests/:id/reject", requireAdmin, (req, res) => {
  const request = getVerificationRequest.get(req.params.id);
  if (!request) {
    return res.status(404).json({ error: "verification request not found" });
  }
  setVerificationRequestStatus.run("rejected", request.id);
  res.json({ id: request.id, status: "rejected" });
});
