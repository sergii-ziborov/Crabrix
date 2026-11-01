import { DatabaseSync } from "node:sqlite";
import { appendFileSync, chmodSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { createHash, randomBytes, scrypt, timingSafeEqual } from "node:crypto";

export const TERMS_VERSION = "2026-10-10";
export const SESSION_SECONDS = 30 * 24 * 60 * 60;
export type Viewer = { id: number; username: string; createdAt: number };
type UserRow = { id: number; username: string; password_hash: string; recovery_hash: string; created_at: number };
let database: DatabaseSync | undefined;
let activeHashes = 0;
const digest = (text: string) => createHash("sha256").update(text).digest("hex");

// A credential the server actually checked and rejected. Malformed forms and a
// busy hasher are not guesses, so they never reach the attempt counters.
export class CredentialFailure extends Error {}

function db() {
  if (database) return database;
  const path = process.env.AUTH_DB_PATH || join(process.cwd(), "auth-data", "accounts.sqlite");
  mkdirSync(dirname(path), { recursive: true, mode: 0o700 });
  database = new DatabaseSync(path);
  chmodSync(path, 0o600);
  database.exec(`PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON; PRAGMA busy_timeout=5000;
    CREATE TABLE IF NOT EXISTS users (
      id INTEGER PRIMARY KEY, username TEXT NOT NULL UNIQUE,
      password_hash TEXT NOT NULL, recovery_hash TEXT NOT NULL,
      created_at INTEGER NOT NULL, terms_version TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS sessions (
      token_hash TEXT PRIMARY KEY, user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      expires_at INTEGER NOT NULL);
    CREATE INDEX IF NOT EXISTS sessions_user ON sessions(user_id);
    CREATE TABLE IF NOT EXISTS rate_limits (key TEXT PRIMARY KEY, count INTEGER NOT NULL, expires_at INTEGER NOT NULL);`);
  return database;
}

export function normalizeUsername(value: string): string {
  const username = value.trim().toLowerCase();
  if (!/^[a-z][a-z0-9_]{2,31}$/.test(username)) throw new Error("Use 3–32 letters, numbers or underscores. Start with a letter.");
  return username;
}

export function validatePassword(value: string) {
  if (value.length < 12 || value.length > 128 || Buffer.byteLength(value) > 512) throw new Error("Use a password between 12 and 128 characters. A long phrase works well.");
}

async function derive(password: string, salt: string): Promise<Buffer> {
  if (activeHashes >= 2) throw new Error("Sign-in is busy. Please try again in a moment.");
  activeHashes++;
  try {
    return await new Promise((resolve, reject) => {
      scrypt(password, salt, 64, { N: 131072, r: 8, p: 1, maxmem: 192 * 1024 * 1024 }, (error, key) => error ? reject(error) : resolve(key));
    });
  } finally { activeHashes--; }
}

async function hashPassword(password: string) {
  const salt = randomBytes(16).toString("hex");
  return `scrypt-v1$${salt}$${(await derive(password, salt)).toString("hex")}`;
}

async function matchesPassword(password: string, encoded: string) {
  const [version, salt, key] = encoded.split("$");
  if (version !== "scrypt-v1" || !/^[a-f0-9]{32}$/.test(salt) || !/^[a-f0-9]{128}$/.test(key)) return false;
  return timingSafeEqual(await derive(password, salt), Buffer.from(key, "hex"));
}

function recovery() {
  const raw = randomBytes(20).toString("hex");
  return { code: raw.match(/.{1,8}/g)!.join("-"), hash: digest(raw) };
}

function newSession(userId: number) {
  const token = randomBytes(32).toString("base64url");
  const expiresAt = Date.now() + SESSION_SECONDS * 1000;
  const sql = db();
  sql.prepare("DELETE FROM sessions WHERE expires_at < ?").run(Date.now());
  sql.prepare("INSERT INTO sessions VALUES (?, ?, ?)").run(digest(token), userId, expiresAt);
  return { token, expiresAt };
}

const LIMIT_WINDOW_MS = 15 * 60 * 1000;
const TOO_MANY_ATTEMPTS = "Too many attempts. Please try again in 15 minutes.";

export function limitCount(key: string): number {
  const sql = db();
  sql.prepare("DELETE FROM rate_limits WHERE expires_at < ?").run(Date.now());
  const row = sql.prepare("SELECT count FROM rate_limits WHERE key=?").get(digest(key)) as { count: number } | undefined;
  return row?.count ?? 0;
}

function chargeLimit(key: string, windowMs = LIMIT_WINDOW_MS) {
  db().prepare("INSERT INTO rate_limits VALUES (?, 1, ?) ON CONFLICT(key) DO UPDATE SET count=count+1").run(digest(key), Date.now() + windowMs);
}

export function consumeLimit(key: string, maximum = 12, windowMs = LIMIT_WINDOW_MS) {
  chargeLimit(key, windowMs);
  if (limitCount(key) > maximum) throw new Error(TOO_MANY_ATTEMPTS);
}

export type AttemptKind = "register" | "login" | "recover" | "password" | "delete";
type AttemptRule = { key: string; maximum: number; charge: "failure" | "success" | "both"; resetOnSuccess?: boolean };
// One address gets ipFailures failures in total and userAtIpFailures per username,
// so reaching userFailures for someone else's account takes at least 13 addresses.
export const ATTEMPT_LIMITS = Object.freeze({ ipFailures: 20, userAtIpFailures: 8, userFailures: 100, ipSuccesses: 60, registerIp: 6, registerGlobal: 50 });

function attemptRules(kind: AttemptKind, identity: string, ip: string): AttemptRule[] {
  if (kind === "register") return [
    { key: `ip:register:${ip}`, maximum: ATTEMPT_LIMITS.registerIp, charge: "both" },
    { key: "register:global", maximum: ATTEMPT_LIMITS.registerGlobal, charge: "success" },
  ];
  return [
    { key: `ip:${kind}:${ip}`, maximum: ATTEMPT_LIMITS.ipFailures, charge: "failure" },
    { key: `user-ip:${kind}:${identity}:${ip}`, maximum: ATTEMPT_LIMITS.userAtIpFailures, charge: "failure", resetOnSuccess: true },
    { key: `user:${kind}:${identity}`, maximum: ATTEMPT_LIMITS.userFailures, charge: "failure" },
    { key: `ok:${kind}:${ip}`, maximum: ATTEMPT_LIMITS.ipSuccesses, charge: "success" },
  ];
}

export async function withAttemptLimits<T>(kind: AttemptKind, identityInput: string, ip: string, attempt: () => Promise<T>): Promise<T> {
  const rules = attemptRules(kind, identityInput.trim().toLowerCase(), ip);
  if (rules.some(rule => limitCount(rule.key) >= rule.maximum)) throw new Error(TOO_MANY_ATTEMPTS);
  let result: T;
  try { result = await attempt(); }
  catch (error) {
    if (error instanceof CredentialFailure) for (const rule of rules) if (rule.charge !== "success") chargeLimit(rule.key);
    throw error;
  }
  for (const rule of rules) {
    if (rule.charge !== "failure") chargeLimit(rule.key);
    if (rule.resetOnSuccess) db().prepare("DELETE FROM rate_limits WHERE key=?").run(digest(rule.key));
  }
  return result;
}

export async function registerAccount(usernameInput: string, password: string) {
  const username = normalizeUsername(usernameInput);
  validatePassword(password);
  const passwordHash = await hashPassword(password), code = recovery();
  let userId: number;
  try {
    userId = Number(db().prepare("INSERT INTO users (username,password_hash,recovery_hash,created_at,terms_version) VALUES (?,?,?,?,?)")
      .run(username, passwordHash, code.hash, Date.now(), TERMS_VERSION).lastInsertRowid);
  } catch (error) {
    if (String(error).includes("UNIQUE")) throw new CredentialFailure("That username is unavailable. Please choose another.");
    throw error;
  }
  return { ...newSession(userId), recoveryCode: code.code };
}

export async function loginAccount(usernameInput: string, password: string) {
  const username = normalizeUsername(usernameInput);
  validatePassword(password);
  const user = db().prepare("SELECT * FROM users WHERE username=?").get(username) as UserRow | undefined;
  // Unknown users still incur the expensive password operation.
  const dummy = `scrypt-v1$${"0".repeat(32)}$${"0".repeat(128)}`;
  const valid = await matchesPassword(password, user?.password_hash || dummy);
  if (!user || !valid) throw new CredentialFailure("The username or password is incorrect.");
  return newSession(user.id);
}

export function viewerForToken(token?: string): Viewer | null {
  if (!token || !/^[\w-]{43}$/.test(token)) return null;
  const user = db().prepare(`SELECT users.id,users.username,users.created_at FROM sessions
    JOIN users ON sessions.user_id=users.id WHERE sessions.token_hash=? AND sessions.expires_at>?`)
    .get(digest(token), Date.now()) as UserRow | undefined;
  return user ? { id: user.id, username: user.username, createdAt: user.created_at } : null;
}

export function endSession(token?: string) {
  if (token) db().prepare("DELETE FROM sessions WHERE token_hash=?").run(digest(token));
}

export async function recoverAccount(usernameInput: string, codeInput: string, password: string) {
  const username = normalizeUsername(usernameInput);
  validatePassword(password);
  const code = codeInput.replaceAll("-", "").trim().toLowerCase();
  const user = db().prepare("SELECT * FROM users WHERE username=?").get(username) as UserRow | undefined;
  if (!/^[a-f0-9]{40}$/.test(code) || !user || !timingSafeEqual(Buffer.from(digest(code)), Buffer.from(user.recovery_hash))) throw new CredentialFailure("The username or recovery code is incorrect.");
  const passwordHash = await hashPassword(password), next = recovery(), sql = db();
  sql.exec("BEGIN IMMEDIATE");
  try {
    const change = sql.prepare("UPDATE users SET password_hash=?,recovery_hash=? WHERE id=? AND recovery_hash=?").run(passwordHash, next.hash, user.id, user.recovery_hash);
    if (change.changes !== 1) throw new Error("This recovery code has already been used.");
    sql.prepare("DELETE FROM sessions WHERE user_id=?").run(user.id);
    sql.exec("COMMIT");
  } catch (error) { sql.exec("ROLLBACK"); throw error; }
  return { ...newSession(user.id), recoveryCode: next.code };
}

export async function changeAccountPassword(userId: number, current: string, nextPassword: string) {
  validatePassword(current); validatePassword(nextPassword);
  const user = db().prepare("SELECT * FROM users WHERE id=?").get(userId) as UserRow | undefined;
  if (!user || !await matchesPassword(current, user.password_hash)) throw new CredentialFailure("The current password is incorrect.");
  const hash = await hashPassword(nextPassword), code = recovery(), sql = db();
  sql.exec("BEGIN IMMEDIATE");
  try {
    const result = sql.prepare("UPDATE users SET password_hash=?,recovery_hash=? WHERE id=? AND password_hash=?").run(hash, code.hash, userId, user.password_hash);
    if (result.changes !== 1) throw new Error("Your password changed in another session. Please sign in again.");
    sql.prepare("DELETE FROM sessions WHERE user_id=?").run(userId);
    sql.exec("COMMIT");
  } catch (error) { sql.exec("ROLLBACK"); throw error; }
  return { ...newSession(userId), recoveryCode: code.code };
}

export async function deleteAccount(userId: number, password: string) {
  validatePassword(password);
  const user = db().prepare("SELECT * FROM users WHERE id=?").get(userId) as UserRow | undefined;
  if (!user || !await matchesPassword(password, user.password_hash)) throw new CredentialFailure("The password is incorrect.");
  const sql = db();
  sql.exec("BEGIN IMMEDIATE");
  try {
    const result = sql.prepare("DELETE FROM users WHERE id=? AND password_hash=?").run(userId, user.password_hash);
    if (result.changes !== 1) throw new Error("Your password changed in another session. Please sign in again.");
    const path = process.env.AUTH_DB_PATH || join(process.cwd(), "auth-data", "accounts.sqlite");
    const ledgerFolder = join(dirname(path), "deletions");
    mkdirSync(ledgerFolder, { recursive: true, mode: 0o700 });
    appendFileSync(join(ledgerFolder, `${new Date().toISOString().slice(0, 10)}.jsonl`), JSON.stringify({
      identityHash: digest(`${user.username}:${user.created_at}`), deletedAt: Date.now(),
    }) + "\n", { mode: 0o600 });
    sql.exec("COMMIT");
  } catch (error) { sql.exec("ROLLBACK"); throw error; }
}
