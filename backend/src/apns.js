import { readFileSync } from "node:fs";
import http2 from "node:http2";
import jwt from "jsonwebtoken";

const PRODUCTION_HOST = "https://api.push.apple.com";
const SANDBOX_HOST = "https://api.sandbox.push.apple.com";

let cachedProviderToken = null;
let cachedProviderTokenIssuedAt = 0;
const PROVIDER_TOKEN_TTL_MS = 50 * 60 * 1000; // Apple tokens are valid up to 1h; refresh at 50m

// One shared HTTP/2 session reused across pushes instead of a fresh
// connection (TLS handshake + all) per notification — matters once this is
// sending more than a handful of pushes at a time.
let cachedClient = null;
let cachedClientHost = null;

function getClient(host) {
  if (cachedClient && cachedClientHost === host && !cachedClient.closed && !cachedClient.destroyed) {
    return cachedClient;
  }
  const client = http2.connect(host);
  client.on("error", () => {
    if (cachedClient === client) cachedClient = null;
  });
  client.on("close", () => {
    if (cachedClient === client) cachedClient = null;
  });
  cachedClient = client;
  cachedClientHost = host;
  return client;
}

function isConfigured() {
  return Boolean(
    process.env.APNS_KEY_PATH &&
      process.env.APNS_KEY_ID &&
      process.env.APNS_TEAM_ID &&
      process.env.APPLE_BUNDLE_ID
  );
}

function getProviderToken() {
  const now = Date.now();
  if (cachedProviderToken && now - cachedProviderTokenIssuedAt < PROVIDER_TOKEN_TTL_MS) {
    return cachedProviderToken;
  }

  const privateKey = readFileSync(process.env.APNS_KEY_PATH, "utf8");
  cachedProviderToken = jwt.sign({ iss: process.env.APNS_TEAM_ID, iat: Math.floor(now / 1000) }, privateKey, {
    algorithm: "ES256",
    header: { alg: "ES256", kid: process.env.APNS_KEY_ID },
  });
  cachedProviderTokenIssuedAt = now;
  return cachedProviderToken;
}

/**
 * Sends one alert push to one device token. Resolves with { ok, status,
 * shouldRemoveToken } — the caller decides what to do with a dead token
 * (APNs returns 410 Gone / "Unregistered" once a token stops being valid).
 */
export function sendPush(deviceToken, { title, body, data, badge }) {
  return new Promise((resolve) => {
    if (!isConfigured()) {
      resolve({ ok: false, status: 0, shouldRemoveToken: false, error: "APNs not configured" });
      return;
    }

    const host = process.env.APNS_PRODUCTION === "true" ? PRODUCTION_HOST : SANDBOX_HOST;
    const payload = JSON.stringify({
      aps: { alert: { title, body }, sound: "default", badge },
      ...(data ?? {}),
    });

    const client = getClient(host);

    const req = client.request({
      ":method": "POST",
      ":path": `/3/device/${deviceToken}`,
      authorization: `bearer ${getProviderToken()}`,
      "apns-topic": process.env.APPLE_BUNDLE_ID,
      "apns-push-type": "alert",
      "content-type": "application/json",
    });

    let status = 0;
    req.on("response", (headers) => {
      status = headers[":status"];
    });

    let responseBody = "";
    req.on("data", (chunk) => {
      responseBody += chunk;
    });

    req.on("end", () => {
      const ok = status === 200;
      const reason = (() => {
        try {
          return JSON.parse(responseBody).reason;
        } catch {
          return null;
        }
      })();
      // Apple reports a dead token either way: 410 once it's expired, or
      // 400/BadDeviceToken if it was never valid to begin with.
      const shouldRemoveToken = status === 410 || (status === 400 && reason === "BadDeviceToken");
      resolve({ ok, status, shouldRemoveToken, error: ok ? null : reason ?? responseBody });
    });

    // A stream-level error doesn't necessarily mean the shared session is
    // dead — getClient()'s own error/close handlers already handle
    // discarding and reconnecting it when that's actually the case.
    req.on("error", (error) => {
      resolve({ ok: false, status, shouldRemoveToken: false, error: error.message });
    });

    req.write(payload);
    req.end();
  });
}
