import { test } from "node:test";
import assert from "node:assert/strict";
import { PlaygroundRooms, validatePacket, ROOM_LIMITS } from "../lib/playground-rooms.ts";
import { validatePlaygroundDocument, newPlaygroundDocument } from "../lib/playground-document.ts";
import { limitedJSON, guardPlaygroundOrigin } from "../lib/playground-api.ts";

const packet = () => ({ iv: Buffer.alloc(12, 7).toString("base64url"), data: Buffer.alloc(32, 8).toString("base64url") });

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
