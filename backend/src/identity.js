import { randomUUID } from "node:crypto";
import { db } from "./db.js";

const findByClientId = db.prepare("SELECT * FROM users WHERE client_id = ?");
const insertUser = db.prepare(
  "INSERT INTO users (id, client_id, role) VALUES (?, ?, 'basic')"
);

/**
 * Phase 1 stand-in for real auth: the app generates a random client id
 * once and sends it as X-Client-Id. This will be replaced by Sign in
 * with Apple in phase 2 (client_id -> apple_user_id).
 */
export function identify(req, res, next) {
  const clientId = req.header("X-Client-Id");
  if (!clientId) {
    req.user = null;
    return next();
  }

  let user = findByClientId.get(clientId);
  if (!user) {
    const id = randomUUID();
    insertUser.run(id, clientId);
    user = findByClientId.get(clientId);
  }
  req.user = user;
  next();
}

export function requireUser(req, res, next) {
  if (!req.user) {
    return res.status(401).json({ error: "missing X-Client-Id header" });
  }
  next();
}
