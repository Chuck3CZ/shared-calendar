import { db } from "./db.js";

// NULL expires_at is treated as "never expires" — grandfathers in sessions
// created before this column existed, rather than force-logging everyone
// out the moment this deploys.
const findByToken = db.prepare(`
  SELECT u.* FROM sessions s
  JOIN users u ON u.id = s.user_id
  WHERE s.token = ? AND (s.expires_at IS NULL OR s.expires_at > datetime('now'))
`);
const SESSION_TTL_DAYS = 90;
const slideExpiry = db.prepare(
  `UPDATE sessions SET expires_at = datetime('now', '+${SESSION_TTL_DAYS} days') WHERE token = ?`
);

/**
 * Resolves req.user from a Bearer session token (issued by POST
 * /auth/apple). No token, an unknown one, or an expired one all just leave
 * req.user null — routes that require identity reject that themselves via
 * requireUser, and the app already treats a 401 on an authenticated
 * request as "sign me out" (see APIClient's .sessionExpired notification).
 */
export function identify(req, res, next) {
  const header = req.header("Authorization") || "";
  const token = header.startsWith("Bearer ") ? header.slice("Bearer ".length) : null;
  req.sessionToken = token;
  req.user = token ? findByToken.get(token) ?? null : null;
  // Sliding expiry: every valid request pushes expiry another 90 days out,
  // so an actively-used app is never interrupted — only an abandoned or
  // stolen-but-unused token actually expires.
  if (req.user) {
    slideExpiry.run(token);
  }
  next();
}

export function requireUser(req, res, next) {
  if (!req.user) {
    return res.status(401).json({ error: "sign-in required" });
  }
  next();
}

export function requireAdmin(req, res, next) {
  if (!req.user || req.user.role !== "admin") {
    return res.status(403).json({ error: "admin only" });
  }
  next();
}
