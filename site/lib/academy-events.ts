import "server-only";
import { DatabaseSync } from "node:sqlite";
import { chmodSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { academyEventKey } from "./academy-event-names";

/**
 * Daily counters, nothing else: (day, event, detail) → count. No cookie, IP address, user
 * agent, lesson, code or text is read or stored. Rows older than 400 days are deleted.
 */
const DAILY_LIMIT = 50_000;
let database: DatabaseSync | undefined;
let today = "", todayCount = 0;

function db(): DatabaseSync {
  if (database) return database;
  const path = process.env.ACADEMY_EVENTS_DB_PATH
    || join(process.env.AUTH_DB_PATH ? dirname(process.env.AUTH_DB_PATH) : join(process.cwd(), "auth-data"), "academy-events.sqlite");
  mkdirSync(dirname(path), { recursive: true, mode: 0o700 });
  database = new DatabaseSync(path);
  chmodSync(path, 0o600);
  database.exec(`PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000;
    CREATE TABLE IF NOT EXISTS academy_events (
      day TEXT NOT NULL, event TEXT NOT NULL, detail TEXT NOT NULL, count INTEGER NOT NULL,
      PRIMARY KEY (day, event, detail));`);
  return database;
}

/** Adds one to the day's counter. Returns false when the event is not on the fixed list. */
export function countAcademyEvent(event: unknown, detail: unknown, now = new Date()): boolean {
  const key = academyEventKey(event, detail);
  if (!key) return false;
  const day = now.toISOString().slice(0, 10);
  if (day !== today) {
    today = day; todayCount = 0;
    const cutoff = new Date(now.getTime() - 400 * 86_400_000).toISOString().slice(0, 10);
    db().prepare("DELETE FROM academy_events WHERE day < ?").run(cutoff);
  }
  if (++todayCount > DAILY_LIMIT) return true;
  db().prepare(`INSERT INTO academy_events (day, event, detail, count) VALUES (?, ?, ?, 1)
    ON CONFLICT (day, event, detail) DO UPDATE SET count = count + 1`).run(day, key.event, key.detail);
  return true;
}

/** For the owner's report script; never exposed over HTTP. */
export function academyEventCounts(): { day: string; event: string; detail: string; count: number }[] {
  return db().prepare("SELECT day, event, detail, count FROM academy_events ORDER BY day, event, detail").all() as never;
}
