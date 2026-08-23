import { Router } from "express";
import { db } from "../db.js";

export const universalLinksRouter = Router();

const getEvent = db.prepare(`
  SELECT e.*, u.display_name AS owner_name
  FROM events e
  JOIN users u ON u.id = e.owner_id
  WHERE e.id = ? AND e.deleted_at IS NULL
`);

// Lets Apple's CDN verify this domain may open links in the app. Must be
// served as plain JSON, no auth, no redirect — Apple fetches this directly.
universalLinksRouter.get("/.well-known/apple-app-site-association", (req, res) => {
  res.json({
    applinks: {
      apps: [],
      details: [
        {
          appID: `${process.env.APNS_TEAM_ID}.${process.env.APPLE_BUNDLE_ID}`,
          paths: ["/event/*"],
        },
      ],
    },
  });
});

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (c) => (
    { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]
  ));
}

// Fallback web page for the same URL the app opens via a universal link —
// what shows up if someone taps a shared event link without the app
// installed (or on a device where it can't be opened directly).
universalLinksRouter.get("/event/:id", (req, res) => {
  const event = getEvent.get(req.params.id);
  if (!event) {
    res.status(404).send("<!doctype html><title>Akce nenalezena</title><p>Tahle akce už neexistuje nebo byla smazána.</p>");
    return;
  }

  const when = new Date(event.start_at).toLocaleString("cs-CZ", {
    dateStyle: "full",
    timeStyle: "short",
    timeZone: "Europe/Prague",
  });

  res.send(`<!doctype html>
<html lang="cs">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(event.title)}</title>
<meta property="og:title" content="${escapeHtml(event.title)}">
<meta property="og:description" content="${escapeHtml(when)}${event.location ? " — " + escapeHtml(event.location) : ""}">
<style>
  body { font-family: -apple-system, sans-serif; max-width: 480px; margin: 48px auto; padding: 0 20px; color: #1a1a1a; }
  h1 { font-size: 1.4rem; }
  .meta { color: #666; margin: 4px 0; }
  .hint { margin-top: 32px; padding: 16px; background: #f2f2f2; border-radius: 12px; font-size: 0.9rem; color: #444; }
</style>
</head>
<body>
  <h1>${escapeHtml(event.title)}</h1>
  <p class="meta">${escapeHtml(when)}</p>
  ${event.location ? `<p class="meta">${escapeHtml(event.location)}</p>` : ""}
  ${event.description ? `<p>${escapeHtml(event.description)}</p>` : ""}
  <p class="meta">Vytvořil: ${escapeHtml(event.owner_name ?? "neznámý")}</p>
  <div class="hint">Otevři tenhle odkaz na iPhonu s appkou Objevuj, ať uvidíš celý detail a můžeš na akci zareagovat.</div>
</body>
</html>`);
});
