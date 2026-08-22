import jwt from "jsonwebtoken";
import jwksClient from "jwks-rsa";

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

/**
 * Verifies an Apple identity token (the JWT the app gets from
 * AuthenticationServices) and returns its payload. Throws if the
 * signature, issuer, audience, or expiry don't check out.
 */
export async function verifyAppleIdentityToken(identityToken) {
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
  return jwt.verify(identityToken, publicKey, {
    algorithms: ["RS256"],
    issuer: "https://appleid.apple.com",
    audience: bundleId,
  });
}
