import { test } from "node:test";
import assert from "node:assert/strict";
import { PlaygroundRooms, validatePacket, ROOM_LIMITS } from "../lib/playground-rooms.ts";
import { committedProjectName, validatePlaygroundDocument, newPlaygroundDocument } from "../lib/playground-document.ts";
import { forgetOwnerCapabilities, isTransientSnapshotStatus, rememberOwnerCapabilities, restoreOwnerCapabilities } from "../lib/playground-client.ts";
import { limitedJSON, guardPlaygroundOrigin } from "../lib/playground-api.ts";

const packet = () => ({ iv: Buffer.alloc(12, 7).toString("base64url"), data: Buffer.alloc(32, 8).toString("base64url") });

test("conditional MCP edits reject stale source before mutation and retry one acknowledged message once", () => {
  const rooms = new PlaygroundRooms(), room = rooms.create(packet(), 3600), peer = "mcp_peer_00000001";
  rooms.subscribe(room.id, room.edit, peer, () => {});
  assert.equal(rooms.state(room.id, room.view).protocol.conditionalUpdates, 1);
  const first = rooms.append(room.id, room.edit, peer, "conditional_0001", packet(), 0);
  assert.equal(first.sequence, 1);
  assert.throws(() => rooms.append(room.id, room.edit, peer, "conditional_0002", packet(), 0), /project changed/);
  assert.equal(rooms.state(room.id, room.edit).sequence, 1);
  assert.equal(rooms.append(room.id, room.edit, peer, "conditional_0001", packet(), 0).sequence, 1);
  assert.throws(() => rooms.append(room.id, room.view, peer, "conditional_0003", packet(), 1), /authorized/);
});

test("encrypted rooms expire without extending on reads; no source or account is needed", () => {
  let time = 1000;
  const rooms = new PlaygroundRooms(() => time);
  const room = rooms.create(packet(), 60);
  assert.equal(rooms.state(room.id, room.view).expiresAt, 61000);
  assert.throws(() => rooms.create(packet(), 86401), /Lifetime/);
  assert.throws(() => rooms.state(room.id, "A".repeat(43)), /authorized/);
  assert.equal(JSON.stringify(rooms.state(room.id, room.edit)).includes(room.edit), false);
  let end;
  rooms.subscribe(room.id, room.view, "a".repeat(16), event => { end = event; });
  time = 60999; rooms.state(room.id, room.edit);
  time = 61000;
  assert.throws(() => rooms.state(room.id, room.edit), /expired/);
  assert.equal(end, "expired");
  assert.equal(rooms.rooms.size, 0);
  assert.equal(rooms.residentBytes(), 0);
});

test("view links cannot change or close a room; other-room capabilities fail", () => {
  const rooms = new PlaygroundRooms();
  const first = rooms.create(packet(), 3600), second = rooms.create(packet(), 3600);
  assert.throws(() => rooms.access(first.id, second.edit), /authorized/);
  assert.throws(() => rooms.append(first.id, first.view, "peer".repeat(4), "message".repeat(3), packet()), /authorized/);
  assert.throws(() => rooms.close(first.id, first.edit), /authorized/);
  rooms.close(first.id, first.owner);
  assert.throws(() => rooms.state(first.id, first.edit), /expired/);
});

test("interview participants, update idempotency and snapshot compaction protect current state", () => {
  const rooms = new PlaygroundRooms();
  const room = rooms.create(packet(), 3600), received = [];
  const peers = Array.from({ length: 5 }, (_, i) => `participant_${i}_______`);
  for (const peer of peers.slice(0, 4)) rooms.subscribe(room.id, room.edit, peer, event => received.push(event));
  assert.throws(() => rooms.subscribe(room.id, room.edit, peers[4], () => {}), /four/);
  const first = rooms.append(room.id, room.edit, peers[0], "message_000000001", packet());
  assert.equal(first.sequence, 1);
  assert.equal(received.length, 4);
  assert.equal(rooms.append(room.id, room.edit, peers[0], "message_000000001", packet()).sequence, 1);
  assert.equal(received.length, 4);
  assert.throws(() => rooms.compact(room.id, room.edit, 0, packet()), /latest changes/);
  rooms.compact(room.id, room.edit, 1, packet());
  assert.equal(rooms.state(room.id, room.edit).events.length, 0);
  assert.equal(rooms.state(room.id, room.edit).snapshotSequence, 1);
});

test("relay validates bounded authenticated ciphertext and blocks resource exhaustion", () => {
  assert.deepEqual(validatePacket(packet(), 32), packet());
  assert.throws(() => validatePacket({ ...packet(), iv: "bad" }, 32), /Invalid/);
  assert.throws(() => validatePacket(packet(), 16), /oversized/);
  const rooms = new PlaygroundRooms();
  for (let i = 0; i < ROOM_LIMITS.rooms; i++) rooms.create(packet(), 3600);
  assert.throws(() => rooms.create(packet(), 3600), /capacity/);
  rooms.limit("same client", 1);
  assert.throws(() => rooms.limit("same client", 1), /Too many/);
  assert.equal(JSON.stringify(Array.from(rooms.buckets.keys())).includes("same client"), false);
});

test("text-only source documents enforce byte and path limits independently of the editor", () => {
  const source = newPlaygroundDocument();
  assert.equal(validatePlaygroundDocument(source).entryFile, "main.rs");
  for (const path of ["../secret.rs", "/main.rs", "src/../main.rs", "src\\main.rs", "target/main.rs", "image.png", "node_modules/main.rs", "src/__proto__/main.rs"]) {
    assert.throws(() => validatePlaygroundDocument({ ...source, entryFile: path, files: { [path]: "fn main() {}" } }), /source path/);
  }
  assert.throws(() => validatePlaygroundDocument({ ...source, files: { "main.rs": "🦀".repeat(17_000) } }), /64 KiB/);
  assert.throws(() => validatePlaygroundDocument({ ...source, files: { "main.rs": "\0binary" } }), /binary/);
  assert.throws(() => validatePlaygroundDocument({ ...source, files: Object.fromEntries(Array.from({ length: 17 }, (_, i) => [`f${i}.rs`, ""])) }), /1–16/);
});

test("API request limits apply to streamed bodies and reject cross-site origins", async () => {
  const request = new Request("https://crabrix.com/api/playground/rooms/", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ value: "x".repeat(80) }) });
  await assert.rejects(limitedJSON(request, 32), /too large/);
  assert.throws(() => guardPlaygroundOrigin(new Request("https://crabrix.com/api/playground/rooms/", { headers: { Origin: "https://attacker.example" } })), /Crabrix/);
  assert.doesNotThrow(() => guardPlaygroundOrigin(new Request("https://crabrix.com/api/playground/rooms/", { headers: { Origin: "https://crabrix.com" } })));
});

test("presence is transient and cannot modify source or bypass read-only access", () => {
  let time = 1000;
  const rooms = new PlaygroundRooms(() => time), room = rooms.create(packet(), 60);
  const peer = "presence_peer_0001", events = [];
  const leave = rooms.subscribe(room.id, room.view, peer, event => events.push(event));
  rooms.publishPresence(room.id, room.view, peer, packet());
  assert.equal(events[0].kind, "presence");
  assert.equal(rooms.state(room.id, room.edit).sequence, 0);
  assert.equal(rooms.state(room.id, room.edit).presence.length, 1);
  assert.throws(() => rooms.append(room.id, room.view, peer, "message_000000001", packet()), /authorized/);
  time += 30001; rooms.prune();
  assert.equal(rooms.state(room.id, room.edit).presence.length, 0);
  leave(); assert.throws(() => rooms.publishPresence(room.id, room.edit, peer, packet()), /Join/);
});


test("stalled upload bodies release their reader at an absolute deadline", async () => {
  let cancelled = false;
  const body = new ReadableStream({ cancel() { cancelled = true; } });
  const request = new Request("https://crabrix.com/api/playground/rooms/", { method: "POST", headers: { "Content-Type": "application/json" }, body, duplex: "half" });
  await assert.rejects(limitedJSON(request, 400000, 10), /timed out/);
  assert.equal(cancelled, true);
});

test("one address has a bounded number of live rooms; closing or expiry frees them", () => {
  let time = 1000;
  const rooms = new PlaygroundRooms(() => time), held = [];
  for (let i = 0; i < ROOM_LIMITS.roomsPerIP; i++) held.push(rooms.create(packet(), i === 0 ? 60 : 3600, "203.0.113.1"));
  assert.throws(() => rooms.create(packet(), 3600, "203.0.113.1"), error => error.status === 429);
  assert.ok(rooms.create(packet(), 3600, "198.51.100.1"));
  rooms.close(held[1].id, held[1].owner);
  rooms.create(packet(), 3600, "203.0.113.1");
  assert.throws(() => rooms.create(packet(), 3600, "203.0.113.1"), error => error.status === 429);
  time += 60_000;
  assert.ok(rooms.create(packet(), 3600, "203.0.113.1"));
});

test("one room cannot spend the resident budget that other rooms need", () => {
  const rooms = new PlaygroundRooms(), attacker = rooms.create(packet(), 3600), victim = rooms.create(packet(), 3600);
  const large = () => ({ iv: packet().iv, data: Buffer.alloc(ROOM_LIMITS.updateBytes, 1).toString("base64url") });
  rooms.subscribe(attacker.id, attacker.edit, "attacker_peer_001", () => {});
  rooms.subscribe(victim.id, victim.edit, "victim_peer_00001", () => {});
  let accepted = 0;
  assert.throws(() => { for (;;) rooms.append(attacker.id, attacker.edit, "attacker_peer_001", `attacker_message_${accepted++}`, large()); }, error => error.status === 409 && /fresh encrypted snapshot/.test(error.message));
  assert.ok(accepted > 1);
  assert.ok(rooms.residentBytes() <= ROOM_LIMITS.roomBytes + 256);
  assert.equal(rooms.append(victim.id, victim.edit, "victim_peer_00001", "victim_message_0001", packet()).sequence, 1);
  rooms.compact(attacker.id, attacker.edit, rooms.state(attacker.id, attacker.edit).sequence, packet());
  assert.ok(rooms.append(attacker.id, attacker.edit, "attacker_peer_001", "attacker_after_compact", large()));
});

test("unverified capabilities allocate no rate buckets and cannot block other clients", () => {
  const rooms = new PlaygroundRooms(), room = rooms.create(packet(), 3600);
  const before = rooms.buckets.size;
  for (let i = 0; i < 200; i++) assert.throws(() => rooms.read(room.id, `${String(i).padStart(3, "0")}${"A".repeat(40)}`), /authorized/);
  assert.throws(() => rooms.read("x".repeat(24), "A".repeat(43)), /expired/);
  assert.equal(rooms.buckets.size, before);
  assert.throws(() => rooms.compact(room.id, room.view, 0, packet()), /authorized/);
  assert.equal(rooms.buckets.size, before);
  for (let i = 0; i < 120; i++) assert.equal(rooms.read(room.id, room.view).id, room.id);
  assert.throws(() => rooms.read(room.id, room.view), error => error.status === 429);
});

test("one address cannot hold more than its share of relay memory", () => {
  const rooms = new PlaygroundRooms();
  const large = () => ({ iv: packet().iv, data: Buffer.alloc(ROOM_LIMITS.updateBytes, 1).toString("base64url") });
  const held = [];
  for (let i = 0; i < ROOM_LIMITS.roomsPerIP; i++) {
    const room = rooms.create(packet(), 3600, "203.0.113.2");
    rooms.subscribe(room.id, room.edit, "creator_peer_00001", () => {});
    held.push(room);
  }
  let refused = false, message = 0;
  for (const room of held) {
    try { for (;;) rooms.append(room.id, room.edit, "creator_peer_00001", `creator_message_${message++}`, large()); }
    catch (error) { assert.equal(error.status, 409); refused = rooms.creatorBytes(held[0] && rooms.rooms.get(room.id).creator) + 256 * 1024 >= ROOM_LIMITS.creatorBytes; if (refused) break; }
  }
  assert.ok(refused);
  assert.ok(rooms.residentBytes() <= ROOM_LIMITS.creatorBytes + 256 * 1024);
  const other = rooms.create(packet(), 3600, "198.51.100.2");
  rooms.subscribe(other.id, other.edit, "other_peer_000001", () => {});
  assert.equal(rooms.append(other.id, other.edit, "other_peer_000001", "other_message_0001", large()).sequence, 1);
});

test("a full room still fits the message size that shipped clients accept", () => {
  const rooms = new PlaygroundRooms();
  const room = rooms.create(packet(), 3600, "203.0.113.4");
  rooms.subscribe(room.id, room.edit, "full_room_peer_01", () => {});
  const large = { iv: packet().iv, data: Buffer.alloc(ROOM_LIMITS.updateBytes, 1).toString("base64url") };
  let message = 0;
  assert.throws(() => { for (;;) rooms.append(room.id, room.edit, "full_room_peer_01", `full_room_message_${message++}`, large); }, error => error.status === 409);
  for (let i = 0; i < ROOM_LIMITS.events; i++) { try { rooms.append(room.id, room.edit, "full_room_peer_01", `small_message_${String(i).padStart(4, "0")}`, packet()); } catch { break; } }
  assert.ok(`data: ${JSON.stringify(rooms.read(room.id, room.edit))}`.length < 2_000_000);
});

test("rotating addresses can exhaust room creation only, never edits", () => {
  const rooms = new PlaygroundRooms();
  const room = rooms.create(packet(), 3600, "203.0.113.3");
  rooms.subscribe(room.id, room.edit, "steady_peer_00001", () => {});
  for (let i = 0; i < 10_000; i++) rooms.admitCreate(`10.${i >> 16}.${(i >> 8) & 255}.${i & 255}`);
  assert.throws(() => rooms.admitCreate("198.51.100.3"), error => error.status === 503);
  assert.equal(rooms.append(room.id, room.edit, "steady_peer_00001", "steady_message_01", packet()).sequence, 1);
});

test("rejected create requests do not spend the global create quota", () => {
  const rooms = new PlaygroundRooms();
  let refused = 0;
  for (let i = 0; i < 300; i++) { try { rooms.admitCreate("203.0.113.9"); } catch (error) { assert.equal(error.status, 429); refused++; } }
  assert.equal(refused, 288);
  for (let i = 0; i < ROOM_LIMITS.roomsPerIP; i++) rooms.create(packet(), 3600, "203.0.113.9");
  for (let i = 0; i < 150; i++) assert.throws(() => rooms.create(packet(), 3600, "203.0.113.9"), /maximum number of live/);
  rooms.admitCreate("198.51.100.9");
  assert.ok(rooms.create(packet(), 3600, "198.51.100.9"));
  assert.equal(rooms.rooms.size, ROOM_LIMITS.roomsPerIP + 1);
});

test("three active editors stay under the snapshot limit, and a transient refusal is not a data warning", () => {
  const rooms = new PlaygroundRooms(), room = rooms.create(packet(), 3600);
  // Each client publishes at most once per 5 seconds.
  for (let i = 0; i < ROOM_LIMITS.peers * 12; i++) rooms.compact(room.id, room.edit, 0, packet());
  assert.ok(ROOM_LIMITS.snapshotsPerMinute >= ROOM_LIMITS.peers * 12);
  for (const status of [409, 429, 503]) assert.equal(isTransientSnapshotStatus(status), true);
  for (const status of [400, 403, 413, 500]) assert.equal(isTransientSnapshotStatus(status), false);
});

test("project names keep spaces while typing and are trimmed and validated when committed", () => {
  assert.equal(committedProjectName("my project ", "hello"), "my project");
  assert.equal(committedProjectName("   ", "hello"), null);
  assert.equal(committedProjectName(" hello ", "hello"), null);
  assert.throws(() => committedProjectName("a\tb", "hello"), /control/);
  assert.throws(() => committedProjectName("x".repeat(81), "hello"), /80/);
  assert.equal(validatePlaygroundDocument({ ...newPlaygroundDocument(), name: " my project " }).name, "my project");
});

test("owner capabilities survive a reload in tab storage and only for an edit link", () => {
  const values = new Map(), store = { getItem: key => values.get(key) ?? null, setItem: (key, value) => values.set(key, value), removeItem: key => values.delete(key) }, storage = () => store;
  const token = c => c.repeat(43);
  const link = { id: "r".repeat(24), key: token("k"), access: token("e"), expiresAt: 9e12, mode: "edit" };
  assert.equal(restoreOwnerCapabilities(link, storage), null);
  rememberOwnerCapabilities({ ...link, owner: token("o"), view: token("v") }, storage);
  const stored = [...values.values()].join();
  assert.ok(!stored.includes(link.key) && !stored.includes(link.access));
  const restored = restoreOwnerCapabilities(link, storage);
  assert.deepEqual([restored.owner, restored.view, restored.id, restored.access], [token("o"), token("v"), link.id, link.access]);
  assert.equal(restoreOwnerCapabilities({ ...link, mode: "view" }, storage), null);
  assert.equal(restoreOwnerCapabilities({ ...link, id: "s".repeat(24) }, storage), null);
  values.set([...values.keys()][0], JSON.stringify({ owner: "short", view: token("v") }));
  assert.equal(restoreOwnerCapabilities(link, storage), null);
  forgetOwnerCapabilities(link.id, storage);
  assert.equal(values.size, 0);
  const broken = () => { throw new Error("storage blocked"); };
  assert.equal(restoreOwnerCapabilities(link, broken), null);
  assert.doesNotThrow(() => rememberOwnerCapabilities({ ...link, owner: token("o"), view: token("v") }, broken));
});
