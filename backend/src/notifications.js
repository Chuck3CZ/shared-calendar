import { db } from "./db.js";
import { sendPush } from "./apns.js";

const CHECK_INTERVAL_MS = 60 * 1000;
const REMINDER_WINDOW_HOURS = 2;

// start_at is stored exactly as the client sends it — ISO 8601 with a "T"
// and "Z" (e.g. "2026-08-23T13:41:00Z") — which is NOT the format SQLite's
// own datetime('now') produces ("2026-08-23 13:41:00", space, no Z). SQLite
// has no native datetime type, so comparing the two directly is a plain
// string comparison: "T" (0x54) sorts after " " (0x20), so start_at almost
// never compares correctly against datetime('now'). Comparing against
// bounds formatted in start_at's own shape (below, in JS) sidesteps that.
const findDueReminders = db.prepare(`
  SELECT r.user_id, e.id AS event_id, e.title, e.location, e.start_at
  FROM event_responses r
  JOIN events e ON e.id = r.event_id
  WHERE r.status = 'accepted'
    AND r.notified_at IS NULL
    AND e.deleted_at IS NULL
    AND e.start_at > ?
    AND e.start_at <= ?
`);

function isoNoMillis(date) {
  return date.toISOString().replace(/\.\d{3}Z$/, "Z");
}

const markNotified = db.prepare(`
  UPDATE event_responses SET notified_at = datetime('now') WHERE user_id = ? AND event_id = ?
`);

const listDeviceTokensForUser = db.prepare("SELECT apns_token FROM device_tokens WHERE user_id = ?");
const deleteDeviceToken = db.prepare("DELETE FROM device_tokens WHERE apns_token = ?");

export async function checkAndSendReminders() {
  const now = new Date();
  const windowEnd = new Date(now.getTime() + REMINDER_WINDOW_HOURS * 60 * 60 * 1000);
  const due = findDueReminders.all(isoNoMillis(now), isoNoMillis(windowEnd));
  for (const reminder of due) {
    const tokens = listDeviceTokensForUser.all(reminder.user_id);
    for (const { apns_token } of tokens) {
      const result = await sendPush(apns_token, {
        title: "Za 2 hodiny",
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
    markNotified.run(reminder.user_id, reminder.event_id);
  }
}

export function startNotificationScheduler() {
  setInterval(() => {
    checkAndSendReminders().catch((error) => console.error("notification check failed:", error));
  }, CHECK_INTERVAL_MS);
}
