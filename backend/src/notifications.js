import { db } from "./db.js";
import { sendPush } from "./apns.js";

const CHECK_INTERVAL_MS = 60 * 1000;

// start_at is stored exactly as the client sends it — ISO 8601 with a "T"
// and "Z" (e.g. "2026-08-23T13:41:00Z") — which is NOT the format SQLite's
// own datetime('now') produces ("2026-08-23 13:41:00", space, no Z). SQLite
// has no native datetime type, so comparing the two directly is a plain
// string comparison that silently gives wrong answers (see git history).
// Every reminder now has its own offset, so the due-check needs real
// per-row arithmetic anyway — done here in JS with Date, not in SQL at all.
const findCandidateReminders = db.prepare(`
  SELECT rs.id, rs.user_id, rs.minutes_before, e.id AS event_id, e.title, e.location, e.start_at
  FROM reminder_settings rs
  JOIN events e ON e.id = rs.event_id
  JOIN event_responses r ON r.event_id = e.id AND r.user_id = rs.user_id
  WHERE rs.notified_at IS NULL
    AND r.status = 'accepted'
    AND e.deleted_at IS NULL
    AND e.start_at > ?
`);

function isoNoMillis(date) {
  return date.toISOString().replace(/\.\d{3}Z$/, "Z");
}

const markNotified = db.prepare("UPDATE reminder_settings SET notified_at = datetime('now') WHERE id = ?");

const listDeviceTokensForUser = db.prepare("SELECT apns_token FROM device_tokens WHERE user_id = ?");
const deleteDeviceToken = db.prepare("DELETE FROM device_tokens WHERE apns_token = ?");

function titleFor(minutesBefore) {
  if (minutesBefore === 0) return "Právě teď";
  if (minutesBefore < 60) return `Za ${minutesBefore} minut`;
  if (minutesBefore === 60) return "Za hodinu";
  if (minutesBefore < 1440) return `Za ${minutesBefore / 60} hodiny`;
  return "Za den";
}

export async function checkAndSendReminders() {
  const now = new Date();
  const candidates = findCandidateReminders.all(isoNoMillis(now));
  const due = candidates.filter((r) => {
    const reminderAt = new Date(r.start_at).getTime() - r.minutes_before * 60 * 1000;
    return reminderAt <= now.getTime();
  });

  for (const reminder of due) {
    const tokens = listDeviceTokensForUser.all(reminder.user_id);
    for (const { apns_token } of tokens) {
      const result = await sendPush(apns_token, {
        title: titleFor(reminder.minutes_before),
        body: reminder.location ? `${reminder.title} — ${reminder.location}` : reminder.title,
        data: { event_id: reminder.event_id },
      });
      if (result.shouldRemoveToken) {
        deleteDeviceToken.run(apns_token);
      } else if (!result.ok) {
        console.error(`push to user ${reminder.user_id} failed:`, result.error);
      }
    }
    // Marked even with zero registered devices — otherwise a user who
    // never enabled notifications would get re-checked every minute forever.
    markNotified.run(reminder.id);
  }
}

export function startNotificationScheduler() {
  setInterval(() => {
    checkAndSendReminders().catch((error) => console.error("notification check failed:", error));
  }, CHECK_INTERVAL_MS);
}
