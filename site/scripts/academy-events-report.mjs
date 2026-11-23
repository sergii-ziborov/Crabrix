#!/usr/bin/env node
// Prints the anonymous "Learn with AI" daily counters (docs/ai-learning/PLAN.md, Phase 7).
// Usage inside the site container: node scripts/academy-events-report.mjs [days=14]
import { DatabaseSync } from "node:sqlite";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";

const path = process.env.ACADEMY_EVENTS_DB_PATH
  || join(process.env.AUTH_DB_PATH ? dirname(process.env.AUTH_DB_PATH) : join(process.cwd(), "auth-data"), "academy-events.sqlite");
if (!existsSync(path)) { console.log(`No counters yet (${path}).`); process.exit(0); }
const days = Math.max(1, Math.min(400, Number(process.argv[2] ?? 14) || 14));
const since = new Date(Date.now() - (days - 1) * 86_400_000).toISOString().slice(0, 10);
const database = new DatabaseSync(path, { readOnly: true });
const rows = database.prepare(`SELECT event, detail, SUM(count) AS total FROM academy_events WHERE day >= ?
  GROUP BY event, detail ORDER BY event, total DESC`).all(since);
console.log(`Learn with AI counters since ${since} (${path})`);
for (const row of rows) console.log(`${String(row.total).padStart(7)}  ${row.event}${row.detail ? ` · ${row.detail}` : ""}`);
