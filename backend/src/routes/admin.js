import { Router } from "express";
import { db } from "../db.js";
import { requireUser, requireAdmin } from "../identity.js";
import { notifyUser } from "../notifications.js";

export const adminRouter = Router();

const setRole = db.prepare("UPDATE users SET role = ? WHERE id = ?");
const getUser = db.prepare("SELECT * FROM users WHERE id = ?");
const countAdmins = db.prepare("SELECT COUNT(*) AS count FROM users WHERE role = 'admin'");
const VALID_ROLES = ["basic", "verified", "admin"];

// Every user, newest first, with their latest verification request status
// (if any) so an admin can see who's asked and what was decided — not just
// the ones still pending, which is all /verification-requests shows.
const listAllUsers = db.prepare(`
  SELECT u.*,
    (SELECT v.status FROM verification_requests v WHERE v.user_id = u.id ORDER BY v.created_at DESC LIMIT 1) AS latest_verification_status
  FROM users u
  ORDER BY u.created_at DESC
`);

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

const listDeviceTokens = db.prepare(`
  SELECT d.user_id, u.display_name, d.apns_token, d.created_at
  FROM device_tokens d
  JOIN users u ON u.id = d.user_id
  ORDER BY d.created_at DESC
`);

const listBugReports = db.prepare(`
  SELECT b.*, u.display_name AS user_display_name
  FROM bug_reports b
  LEFT JOIN users u ON u.id = b.user_id
  ORDER BY b.created_at DESC
  LIMIT 200
`);

const listEventReports = db.prepare(`
  SELECT er.*, e.title AS event_title, e.deleted_at AS event_deleted_at, u.display_name AS reporter_display_name
  FROM event_reports er
  JOIN events e ON e.id = er.event_id
  LEFT JOIN users u ON u.id = er.reporter_id
  ORDER BY er.created_at DESC
  LIMIT 200
`);

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

// GET /admin/users — everyone, with their role and latest verification
// request status, so an admin can see and change who has what without
// digging through the pending-requests queue.
adminRouter.get("/users", requireAdmin, (req, res) => {
  res.json(listAllUsers.all());
});

// PATCH /admin/users/:id/role — set a user's role directly.
adminRouter.patch("/users/:id/role", requireAdmin, (req, res) => {
  const { role } = req.body;
  if (!VALID_ROLES.includes(role)) {
    return res.status(400).json({ error: `role must be one of ${VALID_ROLES.join(", ")}` });
  }
  const user = getUser.get(req.params.id);
  if (!user) {
    return res.status(404).json({ error: "user not found" });
  }
  if (user.role === "admin" && role !== "admin" && countAdmins.get().count <= 1) {
    return res.status(400).json({ error: "can't remove the last admin" });
  }

  setRole.run(role, user.id);
  res.json(getUser.get(user.id));
});

// GET /admin/device-tokens — debug view for diagnosing push notification setup
adminRouter.get("/device-tokens", requireAdmin, (req, res) => {
  res.json(listDeviceTokens.all());
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
  notifyUser(request.user_id, {
    title: "Účet ověřen",
    body: "Tvůj účet byl ověřen — limit na vytváření akcí je pryč.",
    data: {},
  }).catch((error) => console.error("verification-approved push failed:", error));
  res.json({ id: request.id, status: "approved" });
});

// POST /admin/verification-requests/:id/reject
adminRouter.post("/verification-requests/:id/reject", requireAdmin, (req, res) => {
  const request = getVerificationRequest.get(req.params.id);
  if (!request) {
    return res.status(404).json({ error: "verification request not found" });
  }
  setVerificationRequestStatus.run("rejected", request.id);
  notifyUser(request.user_id, {
    title: "Žádost o ověření zamítnuta",
    body: "Zkus to prosím znovu později, nebo se zeptej admina.",
    data: {},
  }).catch((error) => console.error("verification-rejected push failed:", error));
  res.json({ id: request.id, status: "rejected" });
});

// GET /admin/bug-reports — everything filed via shake-to-report, newest first.
adminRouter.get("/bug-reports", requireAdmin, (req, res) => {
  res.json(listBugReports.all());
});

// GET /admin/event-reports — everything flagged via "Nahlásit akci", newest
// first. Removing the offending event itself reuses DELETE /events/:id
// (admins can already delete any event), no separate action needed here.
adminRouter.get("/event-reports", requireAdmin, (req, res) => {
  res.json(listEventReports.all());
});
