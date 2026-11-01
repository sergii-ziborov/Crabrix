import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
process.env.AUTH_DB_PATH = join(mkdtempSync(join(tmpdir(), 'crabrix-auth-')), 'test.sqlite');
const auth = await import('../lib/auth-store.ts');

test('account lifecycle protects credentials, revokes sessions and rotates recovery', async () => {
  const password = 'correct horse battery crab';
  const registered = await auth.registerAccount('Learner_qa', password);
  const viewer = auth.viewerForToken(registered.token);
  assert.equal(viewer.username, 'learner_qa');
  assert.equal(auth.viewerForToken(registered.token + 'x'), null);
  await assert.rejects(auth.registerAccount('LEARNER_QA', password), /unavailable/);
  await assert.rejects(auth.loginAccount('learner_qa', 'incorrect long password'), /incorrect/);
  await assert.rejects(auth.loginAccount('unknown_user', password), /incorrect/);
  const session = await auth.loginAccount('learner_qa', password);
  const sql = new DatabaseSync(process.env.AUTH_DB_PATH);
  const stored = sql.prepare('SELECT * FROM users').get();
  assert.ok(stored.password_hash.startsWith('scrypt-v1$'));
  assert.notEqual(stored.password_hash, password);
  assert.notEqual(stored.recovery_hash, registered.recoveryCode);
  assert.notEqual(sql.prepare('SELECT token_hash FROM sessions LIMIT 1').get().token_hash, registered.token);
  const nextPassword = 'another safe long crab phrase';
  const recovered = await auth.recoverAccount('learner_qa', registered.recoveryCode, nextPassword);
  assert.equal(auth.viewerForToken(registered.token), null);
  assert.equal(auth.viewerForToken(session.token), null);
  await assert.rejects(auth.recoverAccount('learner_qa', registered.recoveryCode, nextPassword), /incorrect/);
  await assert.rejects(auth.loginAccount('learner_qa', password), /incorrect/);
  assert.ok(auth.viewerForToken(recovered.token));
  const changed = await auth.changeAccountPassword(viewer.id, nextPassword, password);
  assert.equal(auth.viewerForToken(recovered.token), null);
  await assert.rejects(auth.deleteAccount(viewer.id, nextPassword), /incorrect/);
  await auth.deleteAccount(viewer.id, password);
  assert.equal(auth.viewerForToken(changed.token), null);
  assert.equal(sql.prepare('SELECT count(*) AS n FROM sessions').get().n, 0);
  sql.close();
});

test('logout, expiry and persistent rate limits', async () => {
  const account = await auth.registerAccount('session_qa', 'a very long safe password');
  const sql = new DatabaseSync(process.env.AUTH_DB_PATH);
  sql.prepare('UPDATE sessions SET expires_at=0').run();
  assert.equal(auth.viewerForToken(account.token), null);
  const login = await auth.loginAccount('session_qa', 'a very long safe password');
  auth.endSession(login.token);
  assert.equal(auth.viewerForToken(login.token), null);
  auth.consumeLimit('test-key', 2);
  auth.consumeLimit('test-key', 2);
  assert.throws(() => auth.consumeLimit('test-key', 2), /Too many/);
  assert.ok(!JSON.stringify(sql.prepare('SELECT * FROM rate_limits').all()).includes('test-key'));
  sql.close();
});

const wrong = 'not the right password at all';
const rejected = () => { throw new auth.CredentialFailure('The username or password is incorrect.'); };

test('a stranger on one address cannot lock the owner out, and is stopped without hashing', async () => {
  const password = 'the owners long safe password';
  await auth.registerAccount('owner_qa', password);
  const attempt = ip => auth.withAttemptLimits('login', 'Owner_QA ', ip, () => auth.loginAccount('owner_qa', wrong));
  for (let i = 0; i < auth.ATTEMPT_LIMITS.userAtIpFailures; i++) await assert.rejects(attempt('203.0.113.1'), /incorrect/);
  await assert.rejects(attempt('203.0.113.1'), /Too many/);
  assert.ok(await auth.withAttemptLimits('login', 'owner_qa', '198.51.100.7', () => auth.loginAccount('owner_qa', password)));
});

test('the per-username ceiling needs many addresses, and one address cannot reach it', async () => {
  const fail = (user, ip) => auth.withAttemptLimits('login', user, ip, rejected);
  const needed = Math.ceil(auth.ATTEMPT_LIMITS.userFailures / auth.ATTEMPT_LIMITS.userAtIpFailures);
  assert.ok(needed >= 13);
  for (let host = 0; host < needed - 1; host++) for (let i = 0; i < auth.ATTEMPT_LIMITS.userAtIpFailures; i++) await assert.rejects(fail('ceiling_qa', `192.0.2.${host}`), /incorrect/);
  assert.equal(await auth.withAttemptLimits('login', 'ceiling_qa', '192.0.2.200', async () => 'still allowed'), 'still allowed');
  for (let i = 0; i < auth.ATTEMPT_LIMITS.userAtIpFailures; i++) await assert.rejects(fail('ceiling_qa', '192.0.2.201'), /incorrect|Too many/);
  await assert.rejects(fail('ceiling_qa', '192.0.2.202'), /Too many/);
  for (let i = 0; i < auth.ATTEMPT_LIMITS.ipFailures + 5; i++) await assert.rejects(fail(`spread_${i}`, '192.0.2.250'), /incorrect|Too many/);
  assert.equal(auth.limitCount('ip:login:192.0.2.250'), auth.ATTEMPT_LIMITS.ipFailures);
});

test('malformed forms and busy rejections are not failures, and success clears the address counter', async () => {
  const password = 'another long safe password';
  await auth.registerAccount('busy_qa', password);
  for (let i = 0; i < 30; i++) await assert.rejects(auth.withAttemptLimits('login', 'busy_qa', '198.51.100.20', () => auth.loginAccount('busy_qa', 'short')), /Use a password/);
  assert.equal(auth.limitCount('user-ip:login:busy_qa:198.51.100.20'), 0);
  const results = await Promise.allSettled(Array.from({ length: 3 }, () => auth.withAttemptLimits('login', 'busy_qa', '198.51.100.21', () => auth.loginAccount('busy_qa', wrong))));
  assert.equal(results.filter(result => /busy/.test(result.reason?.message)).length, 1);
  assert.equal(auth.limitCount('user-ip:login:busy_qa:198.51.100.21'), 2);
  assert.equal(auth.limitCount('ip:login:198.51.100.21'), 2);
  await auth.withAttemptLimits('login', 'busy_qa', '198.51.100.21', () => auth.loginAccount('busy_qa', password));
  assert.equal(auth.limitCount('user-ip:login:busy_qa:198.51.100.21'), 0);
  assert.equal(auth.limitCount('user:login:busy_qa'), 2);
});

test('invalid registrations do not spend global sign-ups, and taken names cost only the address', async () => {
  const global = () => auth.limitCount('register:global');
  const password = 'a registration long password';
  const before = global();
  for (let host = 0; host < 12; host++) for (let i = 0; i < 8; i++) await assert.rejects(auth.withAttemptLimits('register', '', `198.51.100.${100 + host}`, () => auth.registerAccount('1 invalid name', password)), /Use 3/);
  assert.equal(global(), before);
  assert.equal(auth.limitCount('ip:register:198.51.100.100'), 0);
  await auth.withAttemptLimits('register', '', '198.51.100.30', () => auth.registerAccount('signup_qa', password));
  assert.equal(global(), before + 1);
  await assert.rejects(auth.withAttemptLimits('register', '', '198.51.100.31', () => auth.registerAccount('signup_qa', password)), /unavailable/);
  assert.equal(global(), before + 1);
  assert.equal(auth.limitCount('ip:register:198.51.100.31'), 1);
  for (let i = 1; i < auth.ATTEMPT_LIMITS.registerIp; i++) await assert.rejects(auth.withAttemptLimits('register', '', '198.51.100.31', rejected), /incorrect/);
  await assert.rejects(auth.withAttemptLimits('register', '', '198.51.100.31', rejected), /Too many/);
});
