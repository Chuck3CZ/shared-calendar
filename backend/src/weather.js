import { readFileSync } from "node:fs";
import jwt from "jsonwebtoken";
import { db } from "./db.js";

// Same App ID/team as the app itself — it already has WeatherKit access for
// on-device use; this is a separate server-side key (Keys → WeatherKit) so
// the backend can call the WeatherKit REST API directly instead of every
// device calling WeatherKit itself.
function isConfigured() {
  return Boolean(
    process.env.WEATHERKIT_KEY_PATH && process.env.WEATHERKIT_KEY_ID && process.env.APNS_TEAM_ID && process.env.APPLE_BUNDLE_ID
  );
}

let cachedToken = null;
let cachedTokenIssuedAt = 0;
const TOKEN_TTL_MS = 50 * 60 * 1000; // WeatherKit tokens are valid up to 1h; refresh at 50m

function getToken() {
  const now = Date.now();
  if (cachedToken && now - cachedTokenIssuedAt < TOKEN_TTL_MS) {
    return cachedToken;
  }
  const privateKey = readFileSync(process.env.WEATHERKIT_KEY_PATH, "utf8");
  const teamId = process.env.APNS_TEAM_ID;
  const appId = process.env.APPLE_BUNDLE_ID;
  cachedToken = jwt.sign({}, privateKey, {
    algorithm: "ES256",
    // WeatherKit's one deviation from a normal Apple auth JWT: this "id"
    // header claim (team + app id, dot-joined) is required alongside kid.
    header: { kid: process.env.WEATHERKIT_KEY_ID, id: `${teamId}.${appId}` },
    issuer: teamId,
    subject: appId,
    expiresIn: "55m",
  });
  cachedTokenIssuedAt = now;
  return cachedToken;
}

// "2026-08-25" in Europe/Prague, regardless of the Date's own timezone —
// matches how a Czech user would read "which day is this event on".
function localDateKey(date) {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Prague" }).format(date);
}

/**
 * Closest hourly forecast within 90 minutes of the event, falling back to
 * that calendar day's high/low if the event is too far out for hourly data
 * but still within the ~10-day daily forecast range. Returns null if
 * neither is available (event too far in the future) or WeatherKit isn't
 * configured/reachable.
 */
export async function fetchWeatherForEvent(latitude, longitude, date) {
  if (!isConfigured()) return null;

  const url = `https://weatherkit.apple.com/api/v1/weather/en/${latitude}/${longitude}?dataSets=forecastHourly,forecastDaily&timezone=Europe/Prague`;
  let response;
  try {
    response = await fetch(url, { headers: { Authorization: `Bearer ${getToken()}` } });
  } catch (error) {
    console.error("weatherkit fetch failed:", error.message);
    return null;
  }
  if (!response.ok) {
    console.error(`weatherkit request failed: ${response.status}`);
    return null;
  }

  const body = await response.json();
  const target = date.getTime();

  let closestHour = null;
  let closestDiff = Infinity;
  for (const hour of body.forecastHourly?.hours ?? []) {
    const diff = Math.abs(new Date(hour.forecastStart).getTime() - target);
    if (diff < closestDiff) {
      closestDiff = diff;
      closestHour = hour;
    }
  }
  if (closestHour && closestDiff < 90 * 60 * 1000) {
    return {
      condition: closestHour.conditionCode,
      temperature: closestHour.temperature,
      temperatureMin: null,
      temperatureMax: null,
      isHourly: true,
    };
  }

  const targetKey = localDateKey(date);
  const matchingDay = (body.forecastDaily?.days ?? []).find((day) => localDateKey(new Date(day.forecastStart)) === targetKey);
  if (matchingDay) {
    return {
      condition: matchingDay.conditionCode,
      temperature: null,
      temperatureMin: matchingDay.temperatureMin,
      temperatureMax: matchingDay.temperatureMax,
      isHourly: false,
    };
  }

  return null;
}

const updateEventWeather = db.prepare(`
  UPDATE events SET
    weather_condition = ?, weather_temperature = ?, weather_temperature_min = ?, weather_temperature_max = ?,
    weather_is_hourly = ?, weather_updated_at = datetime('now')
  WHERE id = ?
`);

// Fire-and-forget from routes right after an event with a location is
// created or edited, so it doesn't have to wait for the next scheduled
// sweep to show a first forecast.
export async function refreshWeatherForEvent(eventId, latitude, longitude, startAt) {
  const weather = await fetchWeatherForEvent(latitude, longitude, new Date(startAt));
  if (!weather) return;
  updateEventWeather.run(
    weather.condition, weather.temperature, weather.temperatureMin, weather.temperatureMax,
    weather.isHourly ? 1 : 0, eventId
  );
}

// WeatherKit's forecasts don't reach much past ~10 days out anyway (matches
// the "not available yet" fallback events further out than that already
// showed) — no point refreshing further ahead than that.
const REFRESH_HORIZON_DAYS = 10;
const DAILY_INTERVAL_MS = 24 * 60 * 60 * 1000;

// start_at is ISO 8601 with a "T"/"Z" — comparing it against SQLite's own
// datetime('now') format directly in SQL is an unreliable string
// comparison (see the same lesson already documented in notifications.js),
// so the date-range filter happens here in JS instead.
const listEventsWithCoordinates = db.prepare(`
  SELECT id, latitude, longitude, start_at FROM events
  WHERE deleted_at IS NULL AND latitude IS NOT NULL AND longitude IS NOT NULL
`);

export async function refreshWeatherForUpcomingEvents() {
  const now = Date.now();
  const horizonMs = REFRESH_HORIZON_DAYS * 24 * 60 * 60 * 1000;
  const events = listEventsWithCoordinates.all().filter((event) => {
    const startMs = new Date(event.start_at).getTime();
    return startMs > now && startMs < now + horizonMs;
  });

  if (events.length > 0) {
    console.log(`[weather] refreshing ${events.length} upcoming event(s)`);
  }
  for (const event of events) {
    await refreshWeatherForEvent(event.id, event.latitude, event.longitude, event.start_at);
  }
}

export function startWeatherScheduler() {
  refreshWeatherForUpcomingEvents().catch((error) => console.error("weather refresh failed:", error));
  setInterval(() => {
    refreshWeatherForUpcomingEvents().catch((error) => console.error("weather refresh failed:", error));
  }, DAILY_INTERVAL_MS);
}
