import { test } from "node:test";
import assert from "node:assert/strict";
import { PlaygroundRooms, ROOM_LIMITS, roomCodec, snapshotLimit, requestLimit } from "../lib/playground-rooms.ts";
import { declaredCodecs, limitedJSON } from "../lib/playground-api.ts";

const packet = (bytes = 32) => ({ iv: Buffer.alloc(12, 7).toString("base64url"), data: Buffer.alloc(bytes, 8).toString("base64url") });
const url = "https://crabrix.com/api/playground/rooms/AAAAAAAAAAAAAAAAAAAAAAAA/";

test("rooms record their format and default to v1", () => {
  const rooms = new PlaygroundRooms();
  const v1 = rooms.create(packet(), 3600), v2 = rooms.create(packet(), 3600, undefined, 2);
  assert.equal(v1.codec, 1);
  assert.equal(v2.codec, 2);
  assert.equal(rooms.state(v1.id, v1.view).codec, 1);
  assert.equal(rooms.state(v2.id, v2.view).codec, 2);
  assert.equal(roomCodec(undefined), 1);
  assert.throws(() => roomCodec(3), /Unsupported Playground format/);
  assert.throws(() => roomCodec("2"), /Unsupported Playground format/);
});

test("clients declare formats by header or stream query; anything else reads as v1 only", () => {
  assert.deepEqual(declaredCodecs(new Request(url)), [1]);
  assert.deepEqual(declaredCodecs(new Request(url, { headers: { "X-Crabrix-Codecs": "1,2" } })), [1, 2]);
  assert.deepEqual(declaredCodecs(new Request(url + "events/?peer=abc&codecs=1,2")), [1, 2]);
  for (const junk of ["", "2,", ",2", "0", "1;2", "a", "1,2,3,4,5,6,7,8,9", "100"]) assert.deepEqual(declaredCodecs(new Request(url, { headers: { "X-Crabrix-Codecs": junk } })), [1], junk);
});

test("a client that did not declare v2 is refused with 426 before any rate limit or participant slot", () => {
  const rooms = new PlaygroundRooms(), room = rooms.create(packet(), 3600, undefined, 2);
  const buckets = [...rooms.buckets.keys()];
  for (let i = 0; i < 200; i++) assert.throws(() => rooms.admit(room.id, room.view, [1]), error => error.status === 426 && /Update Crabrix/.test(error.message));
  assert.deepEqual([...rooms.buckets.keys()], buckets);
  assert.equal(rooms.rooms.get(room.id).listeners.size, 0);
  assert.equal(rooms.admit(room.id, room.edit, [1, 2]), 2);
  // The capability is still checked first: a wrong token learns nothing about the format.
  assert.throws(() => rooms.admit(room.id, "A".repeat(43), [1]), error => error.status === 403);
  assert.throws(() => rooms.admit("B".repeat(24), room.view, [1]), error => error.status === 410);
});

test("v1 rooms keep admitting released clients and keep the 256 KiB snapshot", () => {
  const rooms = new PlaygroundRooms(), room = rooms.create(packet(), 3600), peer = "released_client_01";
  assert.equal(rooms.admit(room.id, room.view, [1]), 1);
  assert.equal(rooms.admit(room.id, room.view, [1, 2]), 1);
  rooms.subscribe(room.id, room.edit, peer, () => {});
  assert.equal(rooms.append(room.id, room.edit, peer, "message_000000001", packet()).sequence, 1);
  assert.throws(() => rooms.compact(room.id, room.edit, 1, packet(ROOM_LIMITS.snapshotBytes + 1)), /oversized/);
  assert.deepEqual(rooms.compact(room.id, room.edit, 1, packet(ROOM_LIMITS.snapshotBytes)), { sequence: 1, generation: 2 });
  assert.throws(() => rooms.create(packet(ROOM_LIMITS.snapshotBytes + 1), 3600), /oversized/);
  assert.equal(requestLimit(1), 400_000);
});

test("v2 rooms accept a 512 KiB snapshot and a request body that carries it", async () => {
  const rooms = new PlaygroundRooms(), room = rooms.create(packet(), 3600, undefined, 2);
  assert.equal(snapshotLimit(2), 512 * 1024);
  assert.deepEqual(rooms.compact(room.id, room.edit, 0, packet(512 * 1024)), { sequence: 0, generation: 1 });
  assert.throws(() => rooms.compact(room.id, room.edit, 0, packet(512 * 1024 + 1)), /oversized/);
  const body = JSON.stringify({ type: "snapshot", sequence: 0, packet: packet(512 * 1024) });
  const request = limit => limitedJSON(new Request(url, { method: "POST", headers: { "Content-Type": "application/json", "Content-Length": String(body.length) }, body }), limit);
  await assert.rejects(request(requestLimit(1)), /too large/);
  assert.equal((await request(requestLimit(2))).type, "snapshot");
});
