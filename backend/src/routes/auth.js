import { Router } from "express";
import { randomUUID } from "node:crypto";
import { db } from "../db.js";
import { verifyAppleIdentityToken } from "../apple.js";
import { requireUser } from "../identity.js";

export const authRouter = Router();

const findByAppleId = db.prepare("SELECT * FROM users WHERE apple_user_id = ?");
const insertUser = db.prepare(
  "INSERT INTO users (id, apple_user_id, display_name, role) VALUES (?, ?, ?, 'basic')"
);
const setDisplayName = db.prepare(
  "UPDATE users SET display_name = ? WHERE id = ? AND display_name IS NULL"
);
const SESSION_TTL_DAYS = 90;
const insertSession = db.prepare(
  `INSERT INTO sessions (token, user_id, expires_at) VALUES (?, ?, datetime('now', '+${SESSION_TTL_DAYS} days'))`
);

// POST /auth/apple — exchange a Sign in with Apple identity token for a
// session token. fullName is only ever sent by Apple on the very first
// authorization for a given Apple ID + app, so we only use it to fill in
// a still-empty display_name, never to overwrite one.
authRouter.post("/apple", async (req, res) => {
  const { identityToken, fullName, nonce } = req.body;
  if (!identityToken) {
    return res.status(400).json({ error: "identityToken is required" });
  }
  if (!nonce) {
    return res.status(400).json({ error: "nonce is required" });
  }

  let payload;
  try {
    payload = await verifyAppleIdentityToken(identityToken, nonce);
  } catch (err) {
    return res.status(401).json({ error: "invalid identity token", detail: err.message });
  }

  const appleUserId = payload.sub;
  let user = findByAppleId.get(appleUserId);
  if (!user) {
    const id = randomUUID();
    insertUser.run(id, appleUserId, fullName ?? null);
    user = findByAppleId.get(appleUserId);
  } else if (fullName) {
    setDisplayName.run(fullName, user.id);
    user = findByAppleId.get(appleUserId);
  }

  const token = randomUUID();
  insertSession.run(token, user.id);
  res.json({ token, user });
});

const deleteSession = db.prepare("DELETE FROM sessions WHERE token = ?");

// DELETE /auth/session — revoke the token used to make this request, so
// signing out actually invalidates it server-side instead of just
// forgetting it locally (it would otherwise keep working forever).
authRouter.delete("/session", requireUser, (req, res) => {
  deleteSession.run(req.sessionToken);
  res.status(204).end();
});
