import { DatabaseSync } from "node:sqlite";
import { chmodSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { createHash, randomBytes, timingSafeEqual } from "node:crypto";
import { clientKey } from "./client-key.ts";
import { learningLinksEnabled } from "./flags.ts";

/**
 * Learning links, website side (docs/ai-learning/learning-link.md, "Website API").
 *
 * A mailbox between the learner's Crabrix app and the remote MCP server: one encrypted snapshot
 * per link and at most 50 encrypted tutor messages. The website stores only those envelopes and
 * SHA-256 hashes of the two bearer tokens; the key exists only in the learner's link. No cookie is
 * read, no IP address is stored (the creation limit counts a daily-salted hash) and no body is
 * logged. Everything lives here, free of Next.js, so tests drive it directly; the route is a shim.
 */

export const LEARN_LINK_LIMITS = Object.freeze({
  /** Request body (the envelope JSON), UTF-8 bytes. */
  snapshotBytes: 256 * 1024,
  inboxBytes: 8 * 1024,
  createBytes: 1024,
  inboxPending: 50,
  createsPerDay: 20,
  /** All clients together: bounds the disk a flood of addresses could fill (about 128 MB a day). */
  createsPerDayTotal: 500,
  inboxPostsPerHour: 60,
  snapshotPutsPerHour: 120,
  idleMs: 90 * 86_400_000,
});

const LINK_ID = /^[A-Za-z0-9_-]{24}$/;
const TOKEN = /^[A-Za-z0-9_-]{43}$/;
const HASH = /^[0-9a-fA-F]{64}$/;
const NONCE = /^[A-Za-z0-9_-]{16}$/;
const BASE64URL = /^[A-Za-z0-9_-]+$/;
const MESSAGE_ID = /^[A-Za-z0-9_-]{22}$/;
const HOUR_MS = 3_600_000, DAY_MS = 86_400_000, SWEEP_EVERY_MS = 60_000, BODY_TIMEOUT_MS = 10_000;
/** The shortest ciphertext: a 16-byte GCM tag with an empty plaintext. */
const MIN_CT_CHARS = 22;

export type Envelope = { v: 1; nonce: string; ct: string };
export type LearnLinkErrorCode = "BAD_REQUEST" | "TOO_LARGE" | "NOT_FOUND" | "METHOD_NOT_ALLOWED" | "CONFLICT"
  | "RATE_LIMITED" | "UNAVAILABLE" | "INTERNAL";

export class LearnLinkError extends Error {
  status: number;
  code: LearnLinkErrorCode;
  headers: Record<string, string>;
  constructor(status: number, code: LearnLinkErrorCode, headers: Record<string, string> = {}) {
    super(code);
    this.status = status; this.code = code; this.headers = headers;
  }
}
const bad = () => new LearnLinkError(400, "BAD_REQUEST");
const tooLarge = () => new LearnLinkError(400, "TOO_LARGE");
// Unknown link, wrong token, revoked or expired: one answer, so nothing is revealed.
const notFound = () => new LearnLinkError(404, "NOT_FOUND");

/** Lowercase hex SHA-256 of a token's base64url text: what the app sends as `…TokenSha256`. */
export const learnLinkTokenSha256 = (token: string) => createHash("sha256").update(token).digest("hex");
/** ISO 8601 UTC without fractional seconds (`2026-11-24T10:00:00Z`), like the snapshot itself. */
const iso = (ms: number | null | undefined) => ms == null ? null : new Date(ms).toISOString().replace(/\.\d{3}Z$/, "Z");
const isRecord = (value: unknown): value is Record<string, unknown> => !!value && typeof value === "object" && !Array.isArray(value);

type LinkRow = {
  link_id: string; write_token_sha256: string; read_token_sha256: string;
  created_at: number; updated_at: number; last_agent_read_at: number | null; last_write_at: number | null;
};

let database: DatabaseSync | undefined;
let lastSweep = Number.NEGATIVE_INFINITY;
let dailySalt = { day: "", value: Buffer.alloc(0) };

export function learnLinksDatabasePath(): string {
  return process.env.ACADEMY_LEARN_LINKS_DB_PATH
    || join(process.env.AUTH_DB_PATH ? dirname(process.env.AUTH_DB_PATH) : join(process.cwd(), "auth-data"), "learn-links.sqlite");
}

function db(): DatabaseSync {
  if (database) return database;
  const path = learnLinksDatabasePath();
  mkdirSync(dirname(path), { recursive: true, mode: 0o700 });
  database = new DatabaseSync(path);
  // Before WAL mode: SQLite gives the -wal and -shm files the database file's permissions.
  chmodSync(path, 0o600);
  database.exec(`PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON; PRAGMA busy_timeout=5000; PRAGMA secure_delete=ON;
    CREATE TABLE IF NOT EXISTS links (
      link_id TEXT PRIMARY KEY, write_token_sha256 TEXT NOT NULL, read_token_sha256 TEXT NOT NULL,
      created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
      last_agent_read_at INTEGER, last_write_at INTEGER);
    CREATE TABLE IF NOT EXISTS snapshots (
      link_id TEXT PRIMARY KEY REFERENCES links(link_id) ON DELETE CASCADE,
      envelope TEXT NOT NULL, updated_at INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS inbox (
      id TEXT PRIMARY KEY, link_id TEXT NOT NULL REFERENCES links(link_id) ON DELETE CASCADE,
      created_at INTEGER NOT NULL, envelope TEXT NOT NULL);
    CREATE INDEX IF NOT EXISTS inbox_link ON inbox(link_id, created_at);
    CREATE TABLE IF NOT EXISTS rate_limits (key TEXT PRIMARY KEY, count INTEGER NOT NULL, expires_at INTEGER NOT NULL);`);
  return database;
}

function transaction<T>(work: (sql: DatabaseSync) => T): T {
  const sql = db();
  sql.exec("BEGIN IMMEDIATE");
  try {
    const result = work(sql);
    sql.exec("COMMIT");
    return result;
  } catch (error) { sql.exec("ROLLBACK"); throw error; }
}

// ---------------------------------------------------------------------------------------------
// Validation

/** `{v:1, nonce, ct}` and nothing else; its JSON must fit in `maxBytes`. The server cannot decrypt it. */
export function validateEnvelope(value: unknown, maxBytes: number): Envelope {
  if (!isRecord(value) || Object.keys(value).length !== 3) throw bad();
  const { v, nonce, ct } = value;
  if (v !== 1 || typeof nonce !== "string" || typeof ct !== "string") throw bad();
  if (ct.length > maxBytes) throw tooLarge();
  if (!NONCE.test(nonce) || ct.length < MIN_CT_CHARS || ct.length % 4 === 1 || !BASE64URL.test(ct)) throw bad();
  const envelope: Envelope = { v: 1, nonce, ct };
  if (Buffer.byteLength(JSON.stringify(envelope)) > maxBytes) throw tooLarge();
  return envelope;
}

function validateCreation(value: unknown) {
  if (!isRecord(value) || Object.keys(value).length !== 3) throw bad();
  const { linkId, writeTokenSha256, readTokenSha256 } = value;
  if (typeof linkId !== "string" || !LINK_ID.test(linkId)) throw bad();
  if (typeof writeTokenSha256 !== "string" || !HASH.test(writeTokenSha256)) throw bad();
  if (typeof readTokenSha256 !== "string" || !HASH.test(readTokenSha256)) throw bad();
  const write = writeTokenSha256.toLowerCase(), read = readTokenSha256.toLowerCase();
  if (write === read) throw bad(); // HKDF gives distinct tokens; equal hashes mean a broken client
  return { linkId, write, read };
}

// ---------------------------------------------------------------------------------------------
// Rate limits (the auth store's fixed-window `rate_limits` rows, keys hashed)

function admit(key: string, maximum: number, expiresAt: number, now: number) {
  const row = db().prepare(`INSERT INTO rate_limits (key, count, expires_at) VALUES (?, 1, ?)
    ON CONFLICT (key) DO UPDATE SET
      count = CASE WHEN expires_at <= ? THEN 1 ELSE count + 1 END,
      expires_at = CASE WHEN expires_at <= ? THEN excluded.expires_at ELSE expires_at END
    RETURNING count, expires_at`).get(learnLinkTokenSha256(key), expiresAt, now, now) as { count: number; expires_at: number };
  if (row.count > maximum) {
    throw new LearnLinkError(429, "RATE_LIMITED", { "Retry-After": String(Math.max(1, Math.ceil((row.expires_at - now) / 1000))) });
  }
}

/** sha256(daily salt ‖ client key). The salt lives only in memory and changes every UTC day. */
function creationKey(address: string | null | undefined, now: number): string {
  const day = new Date(now).toISOString().slice(0, 10);
  if (dailySalt.day !== day) dailySalt = { day, value: randomBytes(32) };
  return "create:" + createHash("sha256").update(dailySalt.value).update(clientKey(address)).digest("hex");
}

const linkLimitKeys = (linkId: string) => [`snapshot:${linkId}`, `inbox:${linkId}`];

// ---------------------------------------------------------------------------------------------
// Expiry

const lastActive = (row: LinkRow) => Math.max(row.created_at, row.last_write_at ?? 0, row.last_agent_read_at ?? 0);

/** Deletes links with no snapshot write and no agent read for 90 days (and stale counters). */
export function sweepLearnLinks(now = Date.now()): number {
  lastSweep = now;
  const sql = db();
  const removed = sql.prepare(`DELETE FROM links
    WHERE max(created_at, coalesce(last_write_at, 0), coalesce(last_agent_read_at, 0)) <= ?`).run(now - LEARN_LINK_LIMITS.idleMs).changes;
  sql.prepare("DELETE FROM rate_limits WHERE expires_at <= ?").run(now);
  return Number(removed);
}

function sweepAfterWrite(now: number) {
  if (now - lastSweep >= SWEEP_EVERY_MS || now < lastSweep) sweepLearnLinks(now);
}

// ---------------------------------------------------------------------------------------------
// Store

const NO_HASH = Buffer.alloc(32);

/** Returns the link when `token` is its write or read token. Constant-time; every failure is 404. */
export function authorizeLearnLink(linkId: string, token: string | null | undefined, role: "write" | "read", now = Date.now()): LinkRow {
  if (typeof linkId !== "string" || !LINK_ID.test(linkId)) throw bad();
  const row = db().prepare("SELECT * FROM links WHERE link_id=?").get(linkId) as LinkRow | undefined;
  const stored = row ? Buffer.from(role === "write" ? row.write_token_sha256 : row.read_token_sha256, "hex") : NO_HASH;
  const given = createHash("sha256").update(token ?? "").digest();
  const matches = timingSafeEqual(given, stored);
  if (!row || !token || !TOKEN.test(token) || !matches) throw notFound();
  if (lastActive(row) <= now - LEARN_LINK_LIMITS.idleMs) {
    db().prepare("DELETE FROM links WHERE link_id=?").run(linkId);
    throw notFound();
  }
  return row;
}

export function createLearnLink(input: unknown, clientAddress: string | null | undefined, now = Date.now()) {
  const link = validateCreation(input);
  const tomorrow = (Math.floor(now / DAY_MS) + 1) * DAY_MS;
  admit(creationKey(clientAddress, now), LEARN_LINK_LIMITS.createsPerDay, tomorrow, now);
  admit("create:all", LEARN_LINK_LIMITS.createsPerDayTotal, tomorrow, now);
  sweepAfterWrite(now);
  try {
    db().prepare(`INSERT INTO links (link_id, write_token_sha256, read_token_sha256, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?)`).run(link.linkId, link.write, link.read, now, now);
  } catch (error) {
    if (String(error).includes("UNIQUE constraint failed")) throw new LearnLinkError(409, "CONFLICT");
    throw error;
  }
  return { linkId: link.linkId, createdAt: iso(now) };
}

/** Write token. Replaces the one snapshot. */
export function putLearnLinkSnapshot(linkId: string, token: string | null | undefined, input: unknown, now = Date.now()): void {
  authorizeLearnLink(linkId, token, "write", now);
  const envelope = validateEnvelope(input, LEARN_LINK_LIMITS.snapshotBytes);
  admit(`snapshot:${linkId}`, LEARN_LINK_LIMITS.snapshotPutsPerHour, now + HOUR_MS, now);
  transaction(sql => {
    sql.prepare(`INSERT INTO snapshots (link_id, envelope, updated_at) VALUES (?, ?, ?)
      ON CONFLICT (link_id) DO UPDATE SET envelope=excluded.envelope, updated_at=excluded.updated_at`).run(linkId, JSON.stringify(envelope), now);
    sql.prepare("UPDATE links SET last_write_at=?, updated_at=? WHERE link_id=?").run(now, now, linkId);
  });
  sweepAfterWrite(now);
}

/** Read token (the MCP server). Records `lastAgentReadAt`. */
export function getLearnLinkSnapshot(linkId: string, token: string | null | undefined, now = Date.now()) {
  authorizeLearnLink(linkId, token, "read", now);
  const row = db().prepare("SELECT envelope, updated_at FROM snapshots WHERE link_id=?").get(linkId) as { envelope: string; updated_at: number } | undefined;
  if (!row) throw notFound();
  db().prepare("UPDATE links SET last_agent_read_at=? WHERE link_id=?").run(now, linkId);
  return { envelope: JSON.parse(row.envelope) as Envelope, updatedAt: iso(row.updated_at) };
}

/** Read token (the MCP server). Keeps the newest 50 messages. */
export function postLearnLinkInbox(linkId: string, token: string | null | undefined, input: unknown, now = Date.now()) {
  authorizeLearnLink(linkId, token, "read", now);
  const envelope = validateEnvelope(input, LEARN_LINK_LIMITS.inboxBytes);
  admit(`inbox:${linkId}`, LEARN_LINK_LIMITS.inboxPostsPerHour, now + HOUR_MS, now);
  const id = randomBytes(16).toString("base64url");
  transaction(sql => {
    sql.prepare(`DELETE FROM inbox WHERE id IN (SELECT id FROM inbox WHERE link_id=?
      ORDER BY created_at DESC, rowid DESC LIMIT -1 OFFSET ?)`).run(linkId, LEARN_LINK_LIMITS.inboxPending - 1);
    sql.prepare("INSERT INTO inbox (id, link_id, created_at, envelope) VALUES (?, ?, ?, ?)").run(id, linkId, now, JSON.stringify(envelope));
    sql.prepare("UPDATE links SET updated_at=? WHERE link_id=?").run(now, linkId);
  });
  sweepAfterWrite(now);
  return { id, createdAt: iso(now) };
}

/** Write token (the app). Oldest first. */
export function listLearnLinkInbox(linkId: string, token: string | null | undefined, now = Date.now()) {
  authorizeLearnLink(linkId, token, "write", now);
  const rows = db().prepare("SELECT id, created_at, envelope FROM inbox WHERE link_id=? ORDER BY created_at, rowid")
    .all(linkId) as { id: string; created_at: number; envelope: string }[];
  return { items: rows.map(row => ({ id: row.id, createdAt: iso(row.created_at), envelope: JSON.parse(row.envelope) as Envelope })) };
}

/** Write token (the app). Idempotent: an id that is already gone is also acknowledged. */
export function ackLearnLinkInbox(linkId: string, token: string | null | undefined, id: string, now = Date.now()): void {
  if (typeof id !== "string" || !MESSAGE_ID.test(id)) throw bad();
  authorizeLearnLink(linkId, token, "write", now);
  transaction(sql => {
    if (sql.prepare("DELETE FROM inbox WHERE link_id=? AND id=?").run(linkId, id).changes) {
      sql.prepare("UPDATE links SET updated_at=? WHERE link_id=?").run(now, linkId);
    }
  });
  sweepAfterWrite(now);
}

/** Write token (the app): `updatedAt` is the snapshot's, null before the first upload. */
export function learnLinkStatus(linkId: string, token: string | null | undefined, now = Date.now()) {
  const link = authorizeLearnLink(linkId, token, "write", now);
  const snapshot = db().prepare("SELECT updated_at FROM snapshots WHERE link_id=?").get(linkId) as { updated_at: number } | undefined;
  const pending = db().prepare("SELECT count(*) AS n FROM inbox WHERE link_id=?").get(linkId) as { n: number };
  return { updatedAt: iso(snapshot?.updated_at), lastAgentReadAt: iso(link.last_agent_read_at), pendingInbox: Number(pending.n) };
}

/** Write token (the app's Disconnect): the link, its snapshot, its inbox and its counters. */
export function deleteLearnLink(linkId: string, token: string | null | undefined, now = Date.now()): void {
  authorizeLearnLink(linkId, token, "write", now);
  transaction(sql => {
    sql.prepare("DELETE FROM links WHERE link_id=?").run(linkId);
    for (const key of linkLimitKeys(linkId)) sql.prepare("DELETE FROM rate_limits WHERE key=?").run(learnLinkTokenSha256(key));
  });
  sweepAfterWrite(now);
}

// ---------------------------------------------------------------------------------------------
// HTTP (app/api/learn-links/v1/[[...path]]/route.ts)

const HEADERS = { "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff", "Referrer-Policy": "no-referrer" };
const json = (status: number, body: unknown, headers: Record<string, string> = {}) =>
  Response.json(body, { status, headers: { ...HEADERS, ...headers } });
const empty = (status: number) => new Response(null, { status, headers: HEADERS });

function bearer(request: Request): string | null {
  const match = /^Bearer ([A-Za-z0-9_-]{43})$/.exec(request.headers.get("authorization") ?? "");
  return match ? match[1] : null;
}

/** JSON body of at most `maxBytes` (application/json, uncompressed, UTF-8, within 10 seconds). */
async function readJSON(request: Request, maxBytes: number): Promise<unknown> {
  if (!/^application\/json\s*(;|$)/i.test(request.headers.get("content-type") ?? "")) throw bad();
  const encoding = request.headers.get("content-encoding");
  if (encoding && encoding.toLowerCase() !== "identity") throw bad();
  const declared = request.headers.get("content-length");
  if (declared !== null && !(Number(declared) <= maxBytes)) throw tooLarge();
  const reader = request.body?.getReader();
  if (!reader) throw bad();
  const chunks: Uint8Array[] = [];
  const deadline = Date.now() + BODY_TIMEOUT_MS;
  let length = 0;
  try {
    for (;;) {
      let timer: ReturnType<typeof setTimeout> | undefined;
      const next = await Promise.race([reader.read(), new Promise<never>((_, reject) => {
        timer = setTimeout(() => reject(bad()), Math.max(0, deadline - Date.now()));
      })]).finally(() => clearTimeout(timer));
      if (next.done) break;
      length += next.value.byteLength;
      if (length > maxBytes) throw tooLarge();
      chunks.push(next.value);
    }
  } catch (error) {
    void reader.cancel().catch(() => {});
    throw error;
  }
  try { return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(Buffer.concat(chunks))); }
  catch { throw bad(); }
}

function failure(error: unknown): Response {
  if (error instanceof LearnLinkError) return json(error.status, { error: { code: error.code } }, error.headers);
  // The SQLite error text only: never the request, a body or a token.
  const detail = (error as { errstr?: string; code?: string } | null);
  console.error("learn-links: request failed:", detail?.errstr ?? detail?.code ?? "unknown error");
  return json(500, { error: { code: "INTERNAL" } });
}

/** One handler for every method under /api/learn-links/v1/; `path` is what follows `v1/`. */
export async function learnLinksResponse(request: Request, path: readonly string[] = []): Promise<Response> {
  try {
    if (!learningLinksEnabled()) throw new LearnLinkError(503, "UNAVAILABLE");
    const method = request.method.toUpperCase();
    const allow = (...methods: string[]) => {
      if (!methods.includes(method)) throw new LearnLinkError(405, "METHOD_NOT_ALLOWED", { Allow: methods.join(", ") });
    };
    const token = bearer(request);
    const [linkId, resource, messageId] = path;
    if (path.length === 0) {
      allow("POST");
      return json(201, createLearnLink(await readJSON(request, LEARN_LINK_LIMITS.createBytes), request.headers.get("x-real-ip")));
    }
    if (path.length === 1) {
      allow("DELETE");
      deleteLearnLink(linkId, token);
      return empty(204);
    }
    if (path.length === 2 && resource === "snapshot") {
      allow("GET", "PUT");
      if (method === "GET") return json(200, getLearnLinkSnapshot(linkId, token));
      authorizeLearnLink(linkId, token, "write"); // before reading a body from a stranger
      putLearnLinkSnapshot(linkId, token, await readJSON(request, LEARN_LINK_LIMITS.snapshotBytes));
      return empty(204);
    }
    if (path.length === 2 && resource === "inbox") {
      allow("GET", "POST");
      if (method === "GET") return json(200, listLearnLinkInbox(linkId, token));
      authorizeLearnLink(linkId, token, "read");
      return json(201, postLearnLinkInbox(linkId, token, await readJSON(request, LEARN_LINK_LIMITS.inboxBytes)));
    }
    if (path.length === 3 && resource === "inbox") {
      allow("DELETE");
      ackLearnLinkInbox(linkId, token, messageId);
      return empty(204);
    }
    if (path.length === 2 && resource === "status") {
      allow("GET");
      return json(200, learnLinkStatus(linkId, token));
    }
    throw notFound();
  } catch (error) {
    return failure(error);
  }
}
