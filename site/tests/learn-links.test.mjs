import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createDecipheriv, hkdfSync, randomBytes } from 'node:crypto';
import { mkdtempSync, readFileSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';

process.env.ACADEMY_LEARN_LINKS_DB_PATH = join(mkdtempSync(join(tmpdir(), 'crabrix-learn-links-')), 'learn-links.sqlite');
delete process.env.CRABRIX_LEARN_LINKS;
const links = await import('../lib/learn-links.ts');
const flags = await import('../lib/flags.ts');
const vectors = JSON.parse(readFileSync(new URL('../../docs/ai-learning/learning-link-vectors.json', import.meta.url)));
const libSource = readFileSync(new URL('../lib/learn-links.ts', import.meta.url), 'utf8');
const routeSource = readFileSync(new URL('../app/api/learn-links/v1/[[...path]]/route.ts', import.meta.url), 'utf8');
const statusSource = readFileSync(new URL('../app/api/academy/v1/[...path]/route.ts', import.meta.url), 'utf8');

const DAY = 86_400_000;
const T0 = Date.UTC(2026, 10, 24, 10, 0, 0);
const sha = links.learnLinkTokenSha256;
const random = bytes => randomBytes(bytes).toString('base64url');
const envelope = (ctBytes = 64) => ({ v: 1, nonce: random(12), ct: random(ctBytes) });
let addressCounter = 0;
const freshAddress = () => `198.51.100.${++addressCounter}`;

/** A link with random tokens, created from its own address so creation limits never interfere. */
function newLink(now = Date.now()) {
  const link = { linkId: random(18), write: random(32), read: random(32) };
  links.createLearnLink({ linkId: link.linkId, writeTokenSha256: sha(link.write), readTokenSha256: sha(link.read) }, freshAddress(), now);
  return link;
}
const code = (fn, status, errorCode) => assert.throws(fn, error => {
  assert.ok(error instanceof links.LearnLinkError, String(error));
  assert.equal(error.status, status);
  if (errorCode) assert.equal(error.code, errorCode);
  return true;
});
const sql = () => new DatabaseSync(process.env.ACADEMY_LEARN_LINKS_DB_PATH);

test('the shared vectors: token hashes, HKDF keys and the snapshot envelope', () => {
  assert.equal(sha(vectors.writeToken), vectors.writeTokenSha256);
  assert.equal(sha(vectors.readToken), vectors.readTokenSha256);
  assert.match(vectors.linkId, /^[A-Za-z0-9_-]{24}$/);
  assert.match(vectors.secret, /^[A-Za-z0-9_-]{43}$/);
  assert.equal(vectors.url, `https://crabrix.com/mcp/learn/${vectors.linkId}/${vectors.secret}`);
  const secret = Buffer.from(vectors.secret, 'base64url');
  const derive = info => Buffer.from(hkdfSync('sha256', secret, Buffer.from('crabrix-learning-link-v1'), Buffer.from(info), 32)).toString('base64url');
  assert.equal(derive('encryption'), vectors.encryptionKey);
  assert.equal(derive('app-write'), vectors.writeToken);
  assert.equal(derive('agent-read'), vectors.readToken);
  // The website never decrypts; this only proves the vector envelope passes its validation unchanged.
  assert.deepEqual(links.validateEnvelope(vectors.envelope, links.LEARN_LINK_LIMITS.snapshotBytes), vectors.envelope);
  const sealed = Buffer.from(vectors.envelope.ct, 'base64url');
  const decipher = createDecipheriv('aes-256-gcm', Buffer.from(vectors.encryptionKey, 'base64url'), Buffer.from(vectors.envelope.nonce, 'base64url'));
  decipher.setAAD(Buffer.from(vectors.aad));
  decipher.setAuthTag(sealed.subarray(-16));
  assert.equal(Buffer.concat([decipher.update(sealed.subarray(0, -16)), decipher.final()]).toString('utf8'), vectors.snapshotPlaintext);
});

test('create stores only token hashes in a private WAL database, and a duplicate id is 409', () => {
  const link = newLink();
  code(() => links.createLearnLink({ linkId: link.linkId, writeTokenSha256: sha(random(32)), readTokenSha256: sha(random(32)) }, freshAddress()), 409, 'CONFLICT');
  assert.equal(statSync(process.env.ACADEMY_LEARN_LINKS_DB_PATH).mode & 0o777, 0o600);
  const db = sql();
  assert.equal(db.prepare('PRAGMA journal_mode').get().journal_mode, 'wal');
  const row = db.prepare('SELECT * FROM links WHERE link_id=?').get(link.linkId);
  assert.equal(row.write_token_sha256, sha(link.write));
  assert.equal(row.read_token_sha256, sha(link.read));
  assert.ok(!JSON.stringify(db.prepare('SELECT * FROM links').all()).includes(link.write));
  db.close();
  assert.deepEqual(links.learnLinkStatus(link.linkId, link.write), { updatedAt: null, lastAgentReadAt: null, pendingInbox: 0 });
  // Uppercase hex is accepted and stored lowercase.
  const upper = { linkId: random(18), writeTokenSha256: sha(random(32)).toUpperCase(), readTokenSha256: sha(random(32)) };
  assert.equal(links.createLearnLink(upper, freshAddress()).linkId, upper.linkId);
});

test('snapshot: the app writes with its token, the agent reads with its own, anything else is 404', () => {
  const link = newLink(T0);
  const other = newLink(T0);
  code(() => links.getLearnLinkSnapshot(link.linkId, link.read, T0), 404, 'NOT_FOUND'); // no snapshot yet
  const first = envelope();
  code(() => links.putLearnLinkSnapshot(link.linkId, link.read, first, T0), 404, 'NOT_FOUND');
  code(() => links.putLearnLinkSnapshot(link.linkId, other.write, first, T0), 404, 'NOT_FOUND');
  code(() => links.putLearnLinkSnapshot(random(18), link.write, first, T0), 404, 'NOT_FOUND');
  code(() => links.putLearnLinkSnapshot(link.linkId, null, first, T0), 404, 'NOT_FOUND');
  code(() => links.putLearnLinkSnapshot(link.linkId, 'short', first, T0), 404, 'NOT_FOUND');
  code(() => links.putLearnLinkSnapshot('not-a-link', link.write, first, T0), 400, 'BAD_REQUEST');
  links.putLearnLinkSnapshot(link.linkId, link.write, first, T0 + 1000);
  code(() => links.getLearnLinkSnapshot(link.linkId, link.write, T0), 404, 'NOT_FOUND');
  code(() => links.getLearnLinkSnapshot(other.linkId, link.read, T0), 404, 'NOT_FOUND');
  assert.deepEqual(links.getLearnLinkSnapshot(link.linkId, link.read, T0 + 2000), { envelope: first, updatedAt: '2026-11-24T10:00:01Z' });
  const second = envelope(200);
  links.putLearnLinkSnapshot(link.linkId, link.write, second, T0 + 3000);
  assert.deepEqual(links.getLearnLinkSnapshot(link.linkId, link.read, T0 + 4000).envelope, second);
  assert.deepEqual(links.learnLinkStatus(link.linkId, link.write, T0 + 5000),
    { updatedAt: '2026-11-24T10:00:03Z', lastAgentReadAt: '2026-11-24T10:00:04Z', pendingInbox: 0 });
  code(() => links.learnLinkStatus(link.linkId, link.read, T0), 404, 'NOT_FOUND');
  const db = sql();
  assert.equal(db.prepare('SELECT count(*) AS n FROM snapshots WHERE link_id=?').get(link.linkId).n, 1);
  db.close();
});

test('inbox: the agent posts, the app lists oldest first and acknowledges; 50 pending at most', () => {
  const link = newLink(T0);
  const sent = [];
  for (let i = 0; i < 55; i++) {
    const message = envelope(32);
    const result = links.postLearnLinkInbox(link.linkId, link.read, message, T0 + i * 1000);
    assert.match(result.id, /^[A-Za-z0-9_-]{22}$/);
    sent.push({ id: result.id, createdAt: result.createdAt, envelope: message });
  }
  code(() => links.postLearnLinkInbox(link.linkId, link.write, envelope(), T0), 404, 'NOT_FOUND');
  code(() => links.listLearnLinkInbox(link.linkId, link.read, T0), 404, 'NOT_FOUND');
  const { items } = links.listLearnLinkInbox(link.linkId, link.write, T0 + 60_000);
  assert.equal(items.length, 50);
  assert.deepEqual(items, sent.slice(5));
  assert.equal(items[0].createdAt, '2026-11-24T10:00:05Z');
  code(() => links.ackLearnLinkInbox(link.linkId, link.read, items[0].id, T0), 404, 'NOT_FOUND');
  code(() => links.ackLearnLinkInbox(link.linkId, link.write, 'bad id', T0), 400, 'BAD_REQUEST');
  links.ackLearnLinkInbox(link.linkId, link.write, items[0].id, T0 + 61_000);
  links.ackLearnLinkInbox(link.linkId, link.write, items[0].id, T0 + 62_000); // already acknowledged: still fine
  links.ackLearnLinkInbox(link.linkId, link.write, sent[0].id, T0 + 63_000); // dropped earlier: still fine
  const after = links.listLearnLinkInbox(link.linkId, link.write, T0 + 64_000).items;
  assert.deepEqual(after.map(item => item.id), sent.slice(6).map(item => item.id));
  assert.equal(links.learnLinkStatus(link.linkId, link.write, T0 + 65_000).pendingInbox, 49);
  // Another link's message id cannot be acknowledged through this link.
  const other = newLink(T0);
  const foreign = links.postLearnLinkInbox(other.linkId, other.read, envelope(), T0);
  links.ackLearnLinkInbox(link.linkId, link.write, foreign.id, T0 + 66_000);
  assert.equal(links.listLearnLinkInbox(other.linkId, other.write, T0 + 67_000).items.length, 1);
});

test('Disconnect deletes the link, its snapshot, its inbox and its counters at once', () => {
  const link = newLink();
  const keep = newLink();
  links.putLearnLinkSnapshot(link.linkId, link.write, envelope());
  links.postLearnLinkInbox(link.linkId, link.read, envelope());
  links.postLearnLinkInbox(keep.linkId, keep.read, envelope());
  code(() => links.deleteLearnLink(link.linkId, link.read), 404, 'NOT_FOUND');
  links.deleteLearnLink(link.linkId, link.write);
  const db = sql();
  assert.equal(db.prepare('SELECT count(*) AS n FROM links WHERE link_id=?').get(link.linkId).n, 0);
  assert.equal(db.prepare('SELECT count(*) AS n FROM snapshots WHERE link_id=?').get(link.linkId).n, 0);
  assert.equal(db.prepare('SELECT count(*) AS n FROM inbox WHERE link_id=?').get(link.linkId).n, 0);
  assert.equal(db.prepare('SELECT count(*) AS n FROM rate_limits WHERE key IN (?, ?)').get(sha(`snapshot:${link.linkId}`), sha(`inbox:${link.linkId}`)).n, 0);
  assert.equal(db.prepare('SELECT count(*) AS n FROM inbox WHERE link_id=?').get(keep.linkId).n, 1);
  db.close();
  code(() => links.learnLinkStatus(link.linkId, link.write), 404, 'NOT_FOUND');
  code(() => links.getLearnLinkSnapshot(link.linkId, link.read), 404, 'NOT_FOUND');
  code(() => links.deleteLearnLink(link.linkId, link.write), 404, 'NOT_FOUND');
});

test('envelope shape and size are validated before anything is stored', () => {
  const max = links.LEARN_LINK_LIMITS.snapshotBytes;
  const good = envelope();
  for (const value of [null, 'text', [], 1, {}, { ...good, extra: 1 }, { v: 1, nonce: good.nonce }, { ...good, v: 2 }, { ...good, v: '1' },
    { ...good, nonce: random(16) }, { ...good, nonce: good.nonce + '=' }, { ...good, ct: 'a'.repeat(21) }, { ...good, ct: good.ct + '=' },
    { ...good, ct: 'a'.repeat(25) }, { ...good, ct: 'ab+/'.repeat(8) }, { ...good, ct: 7 }, { ...good, nonce: null }]) {
    code(() => links.validateEnvelope(value, max), 400, 'BAD_REQUEST');
  }
  // The JSON {"v":1,"nonce":"…16…","ct":"…"} has 42 bytes around the ciphertext.
  const overhead = Buffer.byteLength(JSON.stringify({ v: 1, nonce: good.nonce, ct: '' }));
  assert.equal(overhead, 42);
  const fits = { v: 1, nonce: good.nonce, ct: 'A'.repeat(max - overhead) };
  assert.equal(Buffer.byteLength(JSON.stringify(fits)), max);
  assert.deepEqual(links.validateEnvelope(fits, max), fits);
  code(() => links.validateEnvelope({ ...fits, ct: fits.ct + 'AAAA' }, max), 400, 'TOO_LARGE');
  code(() => links.validateEnvelope({ ...good, ct: 'A'.repeat(max + 4) }, max), 400, 'TOO_LARGE');
  const link = newLink();
  code(() => links.postLearnLinkInbox(link.linkId, link.read, { v: 1, nonce: good.nonce, ct: 'A'.repeat(links.LEARN_LINK_LIMITS.inboxBytes) }), 400, 'TOO_LARGE');
  links.postLearnLinkInbox(link.linkId, link.read, { v: 1, nonce: good.nonce, ct: 'A'.repeat(links.LEARN_LINK_LIMITS.inboxBytes - overhead) });
  code(() => links.putLearnLinkSnapshot(link.linkId, link.write, { ...good, nonce: 'x' }), 400, 'BAD_REQUEST');
  code(() => links.putLearnLinkSnapshot(link.linkId, link.write, { ...fits, ct: fits.ct + 'AAAA' }), 400, 'TOO_LARGE');
  links.putLearnLinkSnapshot(link.linkId, link.write, fits);
  // Creation requests.
  const hash = sha(random(32));
  for (const value of [null, [], {}, { linkId: random(18), writeTokenSha256: hash }, { linkId: random(18), writeTokenSha256: hash, readTokenSha256: hash },
    { linkId: random(17), writeTokenSha256: hash, readTokenSha256: sha('x') }, { linkId: random(18) + '=', writeTokenSha256: hash, readTokenSha256: sha('x') },
    { linkId: random(18), writeTokenSha256: hash.slice(1), readTokenSha256: sha('x') }, { linkId: random(18), writeTokenSha256: 'g'.repeat(64), readTokenSha256: sha('x') },
    { linkId: random(18), writeTokenSha256: hash, readTokenSha256: sha('x'), extra: true }, { linkId: 5, writeTokenSha256: hash, readTokenSha256: sha('x') }]) {
    code(() => links.createLearnLink(value, freshAddress()), 400, 'BAD_REQUEST');
  }
});

test('rate limits: 20 links per address-hash per day, 120 snapshots and 60 inbox posts per link per hour', () => {
  const address = '203.0.113.77';
  const create = (now, ip = address) => links.createLearnLink({ linkId: random(18), writeTokenSha256: sha(random(32)), readTokenSha256: sha(random(32)) }, ip, now);
  for (let i = 0; i < 20; i++) create(T0 + i);
  assert.throws(() => create(T0 + 30), error => {
    assert.equal(error.status, 429);
    assert.equal(error.code, 'RATE_LIMITED');
    assert.equal(error.headers['Retry-After'], String(Math.ceil((Date.UTC(2026, 10, 25) - (T0 + 30)) / 1000)));
    return true;
  });
  create(T0 + 31, '203.0.113.78');
  create(T0 + 32, '2001:db8:1:2::1');
  code(() => { for (let i = 0; i < 20; i++) create(T0 + 40 + i, `2001:db8:1:2::${i + 2}`); }, 429, 'RATE_LIMITED'); // one IPv6 /64
  create(Date.UTC(2026, 10, 25, 0, 0, 1)); // a new day, a new salt
  const db = sql();
  const stored = JSON.stringify(db.prepare('SELECT * FROM rate_limits').all());
  assert.ok(!stored.includes(address) && !stored.includes('2001:db8'));
  db.close();

  const link = newLink(T0);
  for (let i = 0; i < 120; i++) links.putLearnLinkSnapshot(link.linkId, link.write, envelope(16), T0 + i);
  code(() => links.putLearnLinkSnapshot(link.linkId, link.write, envelope(16), T0 + 200), 429, 'RATE_LIMITED');
  links.putLearnLinkSnapshot(link.linkId, link.write, envelope(16), T0 + 3_600_000);
  for (let i = 0; i < 60; i++) links.postLearnLinkInbox(link.linkId, link.read, envelope(16), T0 + i);
  code(() => links.postLearnLinkInbox(link.linkId, link.read, envelope(16), T0 + 100), 429, 'RATE_LIMITED');
  const other = newLink(T0);
  links.postLearnLinkInbox(other.linkId, other.read, envelope(16), T0 + 100); // limits are per link
  links.postLearnLinkInbox(link.linkId, link.read, envelope(16), T0 + 3_600_001);
});

test('at most 500 links a day from all addresses together', () => {
  const day = Date.UTC(2026, 11, 1, 12);
  const create = (now, ip) => links.createLearnLink({ linkId: random(18), writeTokenSha256: sha(random(32)), readTokenSha256: sha(random(32)) }, ip, now);
  for (let i = 0; i < 500; i++) create(day + i, `198.51.${Math.floor(i / 250)}.${i % 250}`);
  code(() => create(day + 600, '192.0.2.200'), 429, 'RATE_LIMITED');
  create(Date.UTC(2026, 11, 2, 0, 0, 1), '192.0.2.200'); // the next day
});

test('a link with no snapshot write and no agent read for 90 days is deleted', () => {
  const idle = newLink(T0);
  const written = newLink(T0);
  const read = newLink(T0);
  links.putLearnLinkSnapshot(written.linkId, written.write, envelope(), T0 + 30 * DAY);
  links.putLearnLinkSnapshot(read.linkId, read.write, envelope(), T0);
  links.getLearnLinkSnapshot(read.linkId, read.read, T0 + 60 * DAY);
  links.postLearnLinkInbox(idle.linkId, idle.read, envelope(), T0 + 10 * DAY); // tutor messages alone do not keep a link alive
  // Status checks and inbox polls by the app do not count as use either.
  links.learnLinkStatus(idle.linkId, idle.write, T0 + 89 * DAY);
  links.listLearnLinkInbox(idle.linkId, idle.write, T0 + 89 * DAY);
  assert.ok(links.sweepLearnLinks(T0 + 90 * DAY) >= 1);
  code(() => links.learnLinkStatus(idle.linkId, idle.write, T0 + 90 * DAY), 404, 'NOT_FOUND');
  assert.equal(links.learnLinkStatus(written.linkId, written.write, T0 + 119 * DAY).pendingInbox, 0);
  assert.equal(links.learnLinkStatus(read.linkId, read.write, T0 + 149 * DAY).lastAgentReadAt, '2027-01-23T10:00:00Z');
  // A request after the deadline finds nothing even before the next sweep.
  code(() => links.learnLinkStatus(written.linkId, written.write, T0 + 120 * DAY), 404, 'NOT_FOUND');
  const db = sql();
  assert.equal(db.prepare('SELECT count(*) AS n FROM links WHERE link_id IN (?, ?)').get(idle.linkId, written.linkId).n, 0);
  assert.equal(db.prepare('SELECT count(*) AS n FROM inbox WHERE link_id=?').get(idle.linkId).n, 0);
  db.close();
  // Writes sweep on their own (at most once a minute).
  const late = newLink(T0 + 200 * DAY);
  links.putLearnLinkSnapshot(late.linkId, late.write, envelope(), T0 + 200 * DAY + 61_000);
  const after = sql();
  assert.equal(after.prepare('SELECT count(*) AS n FROM links WHERE link_id=?').get(read.linkId).n, 0);
  after.close();
});

// --- HTTP ---------------------------------------------------------------------------------------

const base = 'https://crabrix.com/api/learn-links/v1/';
function call(method, path, { token, body, headers = {} } = {}) {
  const init = { method, headers: { ...headers } };
  if (token) init.headers.authorization = `Bearer ${token}`;
  if (body !== undefined) {
    init.body = typeof body === 'string' ? body : JSON.stringify(body);
    init.headers['content-type'] ??= 'application/json';
  }
  const segments = path.split('/').filter(Boolean);
  return links.learnLinksResponse(new Request(base + segments.map(part => part + '/').join(''), init), segments);
}
async function expectError(response, status, errorCode) {
  assert.equal(response.status, status);
  assert.equal(response.headers.get('cache-control'), 'no-store');
  assert.deepEqual(await response.json(), { error: { code: errorCode } });
}

test('HTTP round trip with the vector tokens, no-store everywhere and an Origin header tolerated', async () => {
  const id = vectors.linkId;
  const origin = { origin: 'https://example.com', 'x-real-ip': '192.0.2.10' };
  const created = await call('POST', '', { body: { linkId: id, writeTokenSha256: vectors.writeTokenSha256, readTokenSha256: vectors.readTokenSha256 }, headers: origin });
  assert.equal(created.status, 201);
  assert.equal(created.headers.get('cache-control'), 'no-store');
  assert.equal(created.headers.get('access-control-allow-origin'), null);
  assert.equal((await created.json()).linkId, id);
  await expectError(await call('POST', '', { body: { linkId: id, writeTokenSha256: vectors.writeTokenSha256, readTokenSha256: vectors.readTokenSha256 }, headers: origin }), 409, 'CONFLICT');
  const put = await call('PUT', `${id}/snapshot`, { token: vectors.writeToken, body: vectors.envelope, headers: origin });
  assert.equal(put.status, 204);
  assert.equal(put.headers.get('cache-control'), 'no-store');
  assert.equal(await put.text(), '');
  const got = await call('GET', `${id}/snapshot`, { token: vectors.readToken });
  assert.equal(got.status, 200);
  assert.equal(got.headers.get('cache-control'), 'no-store');
  const snapshot = await got.json();
  assert.deepEqual(snapshot.envelope, vectors.envelope);
  assert.match(snapshot.updatedAt, /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/);
  await expectError(await call('GET', `${id}/snapshot`, { token: vectors.writeToken }), 404, 'NOT_FOUND');
  await expectError(await call('GET', `${id}/snapshot`), 404, 'NOT_FOUND');
  await expectError(await call('GET', `${id}/snapshot`, { headers: { authorization: `Basic ${vectors.readToken}` } }), 404, 'NOT_FOUND');
  const message = { v: 1, nonce: random(12), ct: random(80) };
  const posted = await call('POST', `${id}/inbox`, { token: vectors.readToken, body: message });
  assert.equal(posted.status, 201);
  const { id: messageId, createdAt } = await posted.json();
  const inbox = await call('GET', `${id}/inbox`, { token: vectors.writeToken });
  assert.deepEqual(await inbox.json(), { items: [{ id: messageId, createdAt, envelope: message }] });
  const status = await (await call('GET', `${id}/status`, { token: vectors.writeToken })).json();
  assert.equal(status.pendingInbox, 1);
  assert.equal(status.updatedAt, snapshot.updatedAt);
  assert.match(status.lastAgentReadAt, /Z$/);
  assert.equal((await call('DELETE', `${id}/inbox/${messageId}`, { token: vectors.writeToken })).status, 204);
  assert.deepEqual(await (await call('GET', `${id}/inbox`, { token: vectors.writeToken })).json(), { items: [] });
  await expectError(await call('DELETE', id, { token: vectors.readToken }), 404, 'NOT_FOUND');
  assert.equal((await call('DELETE', id, { token: vectors.writeToken })).status, 204);
  await expectError(await call('GET', `${id}/status`, { token: vectors.writeToken }), 404, 'NOT_FOUND');
});

test('HTTP rejects bad bodies with 400, strangers with 404 before reading, and unknown routes', async () => {
  const link = newLink();
  await expectError(await call('PUT', `${link.linkId}/snapshot`, { token: link.write, body: '{"v":1', }), 400, 'BAD_REQUEST');
  await expectError(await call('PUT', `${link.linkId}/snapshot`, { token: link.write, body: envelope(), headers: { 'content-type': 'text/plain' } }), 400, 'BAD_REQUEST');
  await expectError(await call('PUT', `${link.linkId}/snapshot`, { token: link.write, body: envelope(), headers: { 'content-encoding': 'gzip' } }), 400, 'BAD_REQUEST');
  await expectError(await call('PUT', `${link.linkId}/snapshot`, { token: link.write, body: { ...envelope(), v: 2 } }), 400, 'BAD_REQUEST');
  const huge = JSON.stringify({ v: 1, nonce: random(12), ct: 'A'.repeat(300_000) });
  await expectError(await call('PUT', `${link.linkId}/snapshot`, { token: link.write, body: huge }), 400, 'TOO_LARGE');
  await expectError(await call('PUT', `${link.linkId}/snapshot`, { token: link.read, body: huge }), 404, 'NOT_FOUND');
  await expectError(await call('POST', `${link.linkId}/inbox`, { token: link.read, body: JSON.stringify({ v: 1, nonce: random(12), ct: 'A'.repeat(9000) }) }), 400, 'TOO_LARGE');
  await expectError(await call('POST', '', { body: 'x'.repeat(2000), headers: { 'x-real-ip': freshAddress() } }), 400, 'TOO_LARGE');
  await expectError(await call('POST', '', { body: { linkId: 'short' }, headers: { 'x-real-ip': freshAddress() } }), 400, 'BAD_REQUEST');
  await expectError(await call('GET', `bad*id/status`, { token: link.write }), 400, 'BAD_REQUEST');
  await expectError(await call('DELETE', `${link.linkId}/inbox/short`, { token: link.write }), 400, 'BAD_REQUEST');
  await expectError(await call('GET', `${link.linkId}/elsewhere`, { token: link.write }), 404, 'NOT_FOUND');
  await expectError(await call('GET', `${link.linkId}/inbox/a/b`, { token: link.write }), 404, 'NOT_FOUND');
  const wrongMethod = await call('GET', '');
  assert.equal(wrongMethod.headers.get('allow'), 'POST');
  await expectError(wrongMethod, 405, 'METHOD_NOT_ALLOWED');
  const patch = await call('PATCH', `${link.linkId}/snapshot`, { token: link.write });
  assert.equal(patch.headers.get('allow'), 'GET, PUT');
  await expectError(patch, 405, 'METHOD_NOT_ALLOWED');
});

test('the CRABRIX_LEARN_LINKS switch answers 503 on every route and status.json reports it', async () => {
  const link = newLink();
  process.env.CRABRIX_LEARN_LINKS = 'off';
  try {
    assert.equal(flags.learningLinksEnabled(), false);
    for (const [method, path, token] of [['POST', ''], ['GET', ''], ['PUT', `${link.linkId}/snapshot`, link.write], ['GET', `${link.linkId}/snapshot`, link.read],
      ['POST', `${link.linkId}/inbox`, link.read], ['GET', `${link.linkId}/inbox`, link.write], ['DELETE', `${link.linkId}/inbox/${random(16)}`, link.write],
      ['GET', `${link.linkId}/status`, link.write], ['DELETE', link.linkId, link.write], ['GET', 'nowhere/at/all/really']]) {
      await expectError(await call(method, path, { token, body: method === 'POST' || method === 'PUT' ? envelope() : undefined }), 503, 'UNAVAILABLE');
    }
  } finally { delete process.env.CRABRIX_LEARN_LINKS; }
  assert.equal(flags.learningLinksEnabled(), true);
  assert.equal(links.learnLinkStatus(link.linkId, link.write).pendingInbox, 0); // paused, not deleted
  assert.match(statusSource, /learningLinks: learningLinksEnabled\(\) \? "on" : "paused"/);
});

test('the routes read no cookies and keep logic out of the Next.js shim', () => {
  for (const source of [libSource, routeSource]) assert.doesNotMatch(source, /cookies\(|get\(["']cookie|server-only|console\.log/);
  assert.match(routeSource, /learnLinksResponse\(request, \(await params\)\.path \?\? \[\]\)/);
  assert.match(libSource, /timingSafeEqual\(given, stored\)/);
  assert.match(libSource, /clientKey\(address\)/);
});
