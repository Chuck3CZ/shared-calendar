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
`);
