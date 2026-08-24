import jwt from "jsonwebtoken";
import jwksClient from "jwks-rsa";
import { createHash } from "node:crypto";

const client = jwksClient({
  jwksUri: "https://appleid.apple.com/auth/keys",
  cache: true,
  cacheMaxAge: 12 * 60 * 60 * 1000, // 12h, keys rotate rarely
});

function getSigningKey(kid) {
  return new Promise((resolve, reject) => {
    client.getSigningKey(kid, (err, key) => {
      if (err) return reject(err);
      resolve(key.getPublicKey());
    });
  });
}

// Tracks raw nonces already consumed by a successful sign-in, briefly —
// closes the gap plain nonce-echo verification leaves open on its own
// (an attacker who captured a whole POST /auth/apple request, identityToken
// and nonce together, could otherwise just replay it verbatim). Nonces are
// single-use app-generated randoms with no other purpose, so an in-memory
// map is fine — nothing meaningful is lost on a server restart.
const consumedNonces = new Map();
const NONCE_TTL_MS = 5 * 60 * 1000;

function markNonceConsumed(nonce) {
  const now = Date.now();
  for (const [n, expiresAt] of consumedNonces) {
    if (expiresAt < now) consumedNonces.delete(n);
  }
  if (consumedNonces.has(nonce)) {
    return false;
  }
  consumedNonces.set(nonce, now + NONCE_TTL_MS);
  return true;
}

/**
 * Verifies an Apple identity token (the JWT the app gets from
 * AuthenticationServices) and returns its payload. Throws if the
 * signature, issuer, audience, expiry, or nonce don't check out.
 *
 * expectedNonce is the raw (unhashed) nonce the app generated for this
 * sign-in attempt — Apple echoes its SHA-256 back as the token's "nonce"
 * claim, per Apple's documented flow.
 */
export async function verifyAppleIdentityToken(identityToken, expectedNonce) {
  const bundleId = process.env.APPLE_BUNDLE_ID;
  if (!bundleId) {
    throw new Error("APPLE_BUNDLE_ID is not configured");
  }

  const decodedHeader = jwt.decode(identityToken, { complete: true });
  const kid = decodedHeader?.header?.kid;
  if (!kid) {
    throw new Error("identity token has no key id");
  }

  const publicKey = await getSigningKey(kid);
  const payload = jwt.verify(identityToken, publicKey, {
    algorithms: ["RS256"],
    issuer: "https://appleid.apple.com",
    audience: bundleId,
  });

  const hashedNonce = createHash("sha256").update(expectedNonce).digest("hex");
  if (payload.nonce !== hashedNonce) {
    throw new Error("nonce mismatch");
  }
  if (!markNonceConsumed(expectedNonce)) {
    throw new Error("nonce already used");
  }

  return payload;
}
