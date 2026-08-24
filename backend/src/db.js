import Database from "better-sqlite3";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";

const DB_PATH = process.env.DB_PATH || "./data/calendar.db";
mkdirSync(dirname(DB_PATH), { recursive: true });

export const db = new Database(DB_PATH);
db.pragma("journal_mode = WAL");

db.exec(`
  CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    apple_user_id TEXT UNIQUE,
    client_id TEXT UNIQUE,
    display_name TEXT,
    role TEXT NOT NULL DEFAULT 'basic',
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  );

  CREATE TABLE IF NOT EXISTS events (
    id TEXT PRIMARY KEY,
    owner_id TEXT NOT NULL REFERENCES users(id),
    title TEXT NOT NULL,
    description TEXT,
    location TEXT,
    start_at TEXT NOT NULL,
    end_at TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  );

  CREATE TABLE IF NOT EXISTS event_responses (
    user_id TEXT NOT NULL REFERENCES users(id),
    event_id TEXT NOT NULL REFERENCES events(id),
    status TEXT NOT NULL DEFAULT 'pending',
    responded_at TEXT,
    notified_at TEXT,
    PRIMARY KEY (user_id, event_id)
  );

  CREATE TABLE IF NOT EXISTS verification_requests (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id),
    reason TEXT,
    status TEXT NOT NULL DEFAULT 'pending',
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  );

  CREATE TABLE IF NOT EXISTS device_tokens (
    user_id TEXT NOT NULL REFERENCES users(id),
    apns_token TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (user_id, apns_token)
  );

  CREATE TABLE IF NOT EXISTS sessions (
    token TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id),
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    expires_at TEXT
  );

  -- Replaces event_responses.notified_at: lets each attendee pick their own
  -- reminder offset(s) per event (e.g. 2h before AND 10m before), mirroring
  -- iOS Calendar's first/second alert.
  CREATE TABLE IF NOT EXISTS reminder_settings (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id),
    event_id TEXT NOT NULL REFERENCES events(id),
    minutes_before INTEGER NOT NULL,
    notified_at TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE (user_id, event_id, minutes_before)
  );

  -- One row per logical notification handed to notifyUser(), independent of
  -- how many devices it actually reached — lets the app show a history even
  -- for a user who hasn't granted push permission.
  CREATE TABLE IF NOT EXISTS notifications (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id),
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    event_id TEXT REFERENCES events(id),
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    read_at TEXT
  );

  -- reporter_id is nullable: if the reporter later deletes their account,
  -- the report stays (an admin still needs to see it) but is anonymized.
  CREATE TABLE IF NOT EXISTS event_reports (
    id TEXT PRIMARY KEY,
    event_id TEXT NOT NULL REFERENCES events(id),
    reporter_id TEXT REFERENCES users(id),
    reason TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  );

  -- user_id is nullable: shake-to-report should work even for a signed-out
  -- visitor hitting a bug before they've ever authenticated.
  CREATE TABLE IF NOT EXISTS bug_reports (
    id TEXT PRIMARY KEY,
    user_id TEXT REFERENCES users(id),
    description TEXT NOT NULL,
    app_version TEXT,
    os_version TEXT,
    device_model TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    github_issue_number INTEGER,
    github_issue_url TEXT
  );
`);

try {
  db.exec("ALTER TABLE events ADD COLUMN deleted_at TEXT");
} catch {
  // column already exists
}

try {
  db.exec("ALTER TABLE events ADD COLUMN latitude REAL");
} catch {
  // column already exists
}

try {
  db.exec("ALTER TABLE events ADD COLUMN longitude REAL");
} catch {
  // column already exists
}

try {
  db.exec("ALTER TABLE bug_reports ADD COLUMN github_issue_number INTEGER");
} catch {
  // column already exists
}

try {
  db.exec("ALTER TABLE bug_reports ADD COLUMN github_issue_url TEXT");
} catch {
  // column already exists
}

// Nullable on purpose: existing sessions from before this column existed
// keep working (NULL = never expires) rather than force-logging everyone
// out the moment this deploys. Every new session gets a real expiry.
try {
  db.exec("ALTER TABLE sessions ADD COLUMN expires_at TEXT");
} catch {
  // column already exists
}
