import { db } from "./db.js";

const findByToken = db.prepare(`
  SELECT u.* FROM sessions s
  JOIN users u ON u.id = s.user_id
  WHERE s.token = ?
`);

/**
 * Resolves req.user from a Bearer session token (issued by POST
 * /auth/apple). No token, or an unknown one, just leaves req.user null —
 * routes that require identity reject that themselves via requireUser.
 */
export function identify(req, res, next) {
  const header = req.header("Authorization") || "";
  const token = header.startsWith("Bearer ") ? header.slice("Bearer ".length) : null;
  req.sessionToken = token;
  req.user = token ? findByToken.get(token) ?? null : null;
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
