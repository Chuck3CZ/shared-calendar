import { db } from "./db.js";
import { sendPush } from "./apns.js";

const CHECK_INTERVAL_MS = 60 * 1000;
const REMINDER_WINDOW_HOURS = 2;

const findDueReminders = db.prepare(`
  SELECT r.user_id, e.id AS event_id, e.title, e.location, e.start_at
  FROM event_responses r
  JOIN events e ON e.id = r.event_id
  WHERE r.status = 'accepted'
    AND r.notified_at IS NULL
    AND e.deleted_at IS NULL
    AND e.start_at > datetime('now')
    AND e.start_at <= datetime('now', '+' || ? || ' hours')
`);

const markNotified = db.prepare(`
  UPDATE event_responses SET notified_at = datetime('now') WHERE user_id = ? AND event_id = ?
`);

const listDeviceTokensForUser = db.prepare("SELECT apns_token FROM device_tokens WHERE user_id = ?");
const deleteDeviceToken = db.prepare("DELETE FROM device_tokens WHERE apns_token = ?");

export async function checkAndSendReminders() {
  const due = findDueReminders.all(REMINDER_WINDOW_HOURS);
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
