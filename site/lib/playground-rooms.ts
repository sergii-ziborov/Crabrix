// Temporary encrypted relay state. Intentionally no fs/database/account imports.
import { createHash, createHmac, randomBytes, timingSafeEqual } from "node:crypto";

export type EncryptedPacket = { iv: string; data: string };
export type RoomEvent = { sequence: number; peer: string; packet: EncryptedPacket };
export type PresenceEvent = { kind: "presence"; peer: string; packet: EncryptedPacket };
type Capability = "edit" | "view" | "owner";
// The document format inside the ciphertext. The relay cannot read it, so the
// room records it at creation and only admits clients that declared they read it.
export type RoomCodec = 1 | 2;
type Room = {
  id: string; codec: RoomCodec; createdAt: number; expiresAt: number; sequence: number;
  // Changes with every append and every snapshot replacement. A snapshot leaves
  // `sequence` alone, so only this proves a conditional write saw the latest state.
  generation: number;
  tokens: Record<Capability, Buffer>; snapshot: EncryptedPacket; snapshotSequence: number;
  events: RoomEvent[]; presence: Map<string, { packet: EncryptedPacket; at: number }>; listeners: Map<string, (event: RoomEvent | PresenceEvent | "expired" | "closed") => void>;
  recentMessages: Map<string, number>; creator?: string;
};
export class PlaygroundError extends Error {
  status: number;
  constructor(message: string, status = 400) { super(message); this.status = status; }
}
const hash = (value: string) => createHash("sha256").update(value).digest();
// The per-IP room cap needs a value that survives for a room's lifetime. The key
// never leaves this process, so stored values cannot be matched to an address.
const creatorKey = randomBytes(32);
const creatorID = (ip: string) => createHmac("sha256", creatorKey).update(ip).digest("hex");
const token = () => randomBytes(32).toString("base64url");
const packetBytes = (packet: EncryptedPacket) => packet.data.length + packet.iv.length;
const roomBytes = (room: Room) => packetBytes(room.snapshot) + room.events.reduce((n, event) => n + packetBytes(event.packet), 0);
// Each client publishes at most one snapshot every 5 seconds, so snapshotsPerMinute
// leaves room for all four participants. roomsPerIP allows a shared office or carrier
// address; creatorBytes keeps it from holding more than 12 of the 32 MiB resident bytes.
// roomBytes keeps the joined state inside the 2,000,000 character message that the
// website and shipped native clients accept; a larger room could not be opened.
// A v2 room keeps deleted text for recovery, so its snapshot may be twice as large.
// requestCharacters is the JSON body a relay request of that codec may carry.
export const ROOM_LIMITS = Object.freeze({ rooms: 64, roomsPerIP: 16, peers: 4, snapshotBytes: 256 * 1024, snapshotBytesV2: 512 * 1024, updateBytes: 192 * 1024, presenceBytes: 4096, events: 256, roomBytes: 1_900_000, creatorBytes: 12 * 1024 * 1024, residentBytes: 32 * 1024 * 1024, snapshotsPerMinute: 60, requestCharacters: 400_000, requestCharactersV2: 720_000 });
export const snapshotLimit = (codec: RoomCodec) => codec === 2 ? ROOM_LIMITS.snapshotBytesV2 : ROOM_LIMITS.snapshotBytes;
export const requestLimit = (codec: RoomCodec) => codec === 2 ? ROOM_LIMITS.requestCharactersV2 : ROOM_LIMITS.requestCharacters;

export function roomCodec(value: unknown): RoomCodec {
  if (value === undefined || value === 1) return 1;
  if (value === 2) return 2;
  throw new PlaygroundError("Unsupported Playground format.");
}

export function validatePacket(input: unknown, maximumBytes: number): EncryptedPacket {
  if (!input || typeof input !== "object" || Array.isArray(input)) throw new PlaygroundError("Invalid encrypted packet.");
  const value = input as Record<string, unknown>;
  if (typeof value.iv !== "string" || !/^[A-Za-z0-9_-]{16}$/.test(value.iv) ||
      typeof value.data !== "string" || !/^[A-Za-z0-9_-]+$/.test(value.data) || value.data.length > maximumBytes * 4 / 3 + 4 ||
      Buffer.from(value.data, "base64url").byteLength < 16 || Buffer.from(value.data, "base64url").byteLength > maximumBytes) throw new PlaygroundError("Invalid or oversized encrypted packet.", 413);
  return { iv: value.iv, data: value.data };
}

export class PlaygroundRooms {
  rooms = new Map<string, Room>();
  buckets = new Map<string, { start: number; count: number }>();
  // Separate, so rotating addresses can only exhaust room creation, never edits or reads.
  createBuckets = new Map<string, { start: number; count: number }>();
  now: () => number;
  constructor(now: () => number = Date.now) { this.now = now; }

  prune() {
    const now = this.now();
    for (const room of this.rooms.values()) for (const [peer, value] of room.presence) if (now - value.at > 30_000) room.presence.delete(peer);
    for (const [id, room] of this.rooms) if (room.expiresAt <= now) {
      this.rooms.delete(id);
      for (const notify of room.listeners.values()) { try { notify("expired"); } catch {} }
      room.listeners.clear(); room.presence.clear(); room.events = []; room.snapshot = { iv: "", data: "" };
    }
    for (const buckets of [this.buckets, this.createBuckets]) for (const [key, bucket] of buckets) if (now - bucket.start > 60_000) buckets.delete(key);
  }

  limit(identity: string, maximum: number, buckets = this.buckets) {
    this.prune();
    const key = hash(identity).toString("hex");
    const now = this.now();
    const bucket = buckets.get(key);
    if (bucket && now - bucket.start < 60_000) {
      if (++bucket.count > maximum) throw new PlaygroundError("Too many requests. Please wait a minute.", 429);
    } else {
      if (buckets.size >= 10_000) throw new PlaygroundError("Playground traffic is busy. Please retry shortly.", 503);
      buckets.set(key, { start: now, count: 1 });
    }
  }

  creatorBytes(creator: string | undefined): number {
    if (!creator) return 0;
    return Array.from(this.rooms.values()).reduce((n, room) => room.creator === creator ? n + roomBytes(room) : n, 0);
  }

  residentBytes(): number {
    return Array.from(this.rooms.values()).reduce((n, room) => n + roomBytes(room), 0);
  }

  // Runs before the body is read. The global bucket is spent only by create().
  admitCreate(ip: string) {
    this.limit("create:ip:" + ip, 12, this.createBuckets);
  }

  create(snapshot: EncryptedPacket, lifetimeSeconds: number, ip?: string, codec: RoomCodec = 1) {
    this.prune();
    codec = roomCodec(codec);
    snapshot = validatePacket(snapshot, snapshotLimit(codec));
    if (!Number.isInteger(lifetimeSeconds) || lifetimeSeconds < 60 || lifetimeSeconds > 86_400) throw new PlaygroundError("Lifetime must be between one minute and 24 hours.");
    const creator = ip === undefined ? undefined : creatorID(ip);
    if (creator && (Array.from(this.rooms.values()).filter(room => room.creator === creator).length >= ROOM_LIMITS.roomsPerIP || this.creatorBytes(creator) + packetBytes(snapshot) > ROOM_LIMITS.creatorBytes)) throw new PlaygroundError("This network already has the maximum number of live temporary rooms. End one or wait for it to expire.", 429);
    if (this.rooms.size >= ROOM_LIMITS.rooms || this.residentBytes() + packetBytes(snapshot) > ROOM_LIMITS.residentBytes) throw new PlaygroundError("Temporary rooms are at capacity. Please retry later.", 503);
    this.limit("create:global", 120);
    const id = randomBytes(18).toString("base64url");
    const owner = token(), edit = token(), view = token();
    const createdAt = this.now(), expiresAt = createdAt + lifetimeSeconds * 1000;
    this.rooms.set(id, { id, codec, createdAt, expiresAt, sequence: 0, generation: 0, tokens: { owner: hash(owner), edit: hash(edit), view: hash(view) }, snapshot,
      snapshotSequence: 0, events: [], presence: new Map(), listeners: new Map(), recentMessages: new Map(), creator });
    return { id, codec, createdAt, expiresAt, owner, edit, view };
  }

  // Runs right after the capability check and before any rate limit, participant
  // slot or ciphertext, so a client that cannot read this format is told why.
  admit(id: string, supplied: string, codecs: readonly number[]): RoomCodec {
    const room = this.access(id, supplied);
    if (!codecs.includes(room.codec)) throw new PlaygroundError("This Playground uses a newer format. Update Crabrix to open it.", 426);
    return room.codec;
  }

  access(id: string, supplied: string, write = false, owner = false): Room {
    this.prune();
    if (!/^[A-Za-z0-9_-]{24}$/.test(id) || !/^[A-Za-z0-9_-]{43}$/.test(supplied)) throw new PlaygroundError("This temporary Playground is unavailable or expired.", 410);
    const room = this.rooms.get(id);
    if (!room) throw new PlaygroundError("This temporary Playground is unavailable or expired.", 410);
    const digest = hash(supplied);
    const capabilities: Capability[] = owner ? ["owner"] : write ? ["edit", "owner"] : ["view", "edit", "owner"];
    if (!capabilities.some(kind => timingSafeEqual(digest, room.tokens[kind]))) throw new PlaygroundError("This Playground link is not authorized.", 403);
    return room;
  }

  // The capability is verified first, so junk tokens cannot allocate rate buckets.
  read(id: string, supplied: string) {
    this.access(id, supplied);
    this.limit("read:" + id + ":" + supplied, 120);
    return this.state(id, supplied);
  }

  state(id: string, supplied: string) {
    const room = this.access(id, supplied);
    return { id, codec: room.codec, createdAt: room.createdAt, expiresAt: room.expiresAt, sequence: room.sequence, generation: room.generation,
      protocol: { conditionalUpdates: 1, stateGeneration: 1 },
      snapshotSequence: room.snapshotSequence, snapshot: room.snapshot, events: room.events, presence: Array.from(room.presence, ([peer, value]) => ({ peer, packet: value.packet })) };
  }

  subscribe(id: string, supplied: string, peer: string, notify: (event: RoomEvent | PresenceEvent | "expired" | "closed") => void) {
    const room = this.access(id, supplied);
    if (!/^[A-Za-z0-9_-]{16,64}$/.test(peer)) throw new PlaygroundError("Invalid participant identifier.");
    if (room.listeners.has(peer)) throw new PlaygroundError("This participant already has an active connection.", 409);
    if (room.listeners.size >= ROOM_LIMITS.peers) throw new PlaygroundError("This room already has four participants.", 409);
    room.listeners.set(peer, notify);
    return () => { room.listeners.delete(peer); room.presence.delete(peer); };
  }

  append(id: string, supplied: string, peer: string, messageID: string, packet: EncryptedPacket, expectedSequence?: number, expectedGeneration?: number) {
    const room = this.access(id, supplied, true);
    packet = validatePacket(packet, ROOM_LIMITS.updateBytes);
    if (!room.listeners.has(peer) || !/^[A-Za-z0-9_-]{16,64}$/.test(messageID)) throw new PlaygroundError("Join the interview before sending changes.", 409);
    this.limit(`updates:${id}:${peer}`, 180);
    const previous = room.recentMessages.get(messageID);
    if (previous !== undefined) return { sequence: previous, generation: room.generation };
    if ((expectedSequence !== undefined && (!Number.isSafeInteger(expectedSequence) || expectedSequence < 0 || expectedSequence !== room.sequence)) ||
        (expectedGeneration !== undefined && (!Number.isSafeInteger(expectedGeneration) || expectedGeneration < 0 || expectedGeneration !== room.generation))) {
      throw new PlaygroundError("The shared project changed. Read its latest revision before applying changes.", 409);
    }
    if (room.events.length >= ROOM_LIMITS.events || roomBytes(room) + packetBytes(packet) > ROOM_LIMITS.roomBytes || (room.creator && this.creatorBytes(room.creator) + packetBytes(packet) > ROOM_LIMITS.creatorBytes) || this.residentBytes() + packetBytes(packet) > ROOM_LIMITS.residentBytes) throw new PlaygroundError("Waiting for a fresh encrypted snapshot; retry your update.", 409);
    const event = { sequence: ++room.sequence, peer, packet };
    room.generation++;
    room.events.push(event); room.recentMessages.set(messageID, event.sequence);
    if (room.recentMessages.size > 512) room.recentMessages.delete(room.recentMessages.keys().next().value!);
    for (const notify of room.listeners.values()) { try { notify(event); } catch {} }
    return { sequence: event.sequence, generation: room.generation };
  }

  publishPresence(id: string, supplied: string, peer: string, packet: EncryptedPacket) {
    const room = this.access(id, supplied);
    if (!room.listeners.has(peer)) throw new PlaygroundError("Join the interview before sending presence.", 409);
    packet = validatePacket(packet, ROOM_LIMITS.presenceBytes);
    this.limit(`presence:${id}:${peer}`, 300);
    room.presence.set(peer, { packet, at: this.now() });
    for (const notify of room.listeners.values()) { try { notify({ kind: "presence", peer, packet }); } catch {} }
  }

  compact(id: string, supplied: string, sequence: number, snapshot: EncryptedPacket, expectedGeneration?: number) {
    const room = this.access(id, supplied, true);
    snapshot = validatePacket(snapshot, snapshotLimit(room.codec));
    this.limit("snapshot:" + id, ROOM_LIMITS.snapshotsPerMinute);
    if (sequence !== room.sequence || (expectedGeneration !== undefined && expectedGeneration !== room.generation)) throw new PlaygroundError("Receive the latest changes before publishing a snapshot.", 409);
    const delta = packetBytes(snapshot) - roomBytes(room);
    if (this.residentBytes() + delta > ROOM_LIMITS.residentBytes) throw new PlaygroundError("Temporary room memory is full.", 503);
    room.snapshot = snapshot; room.snapshotSequence = sequence; room.events = []; room.generation++;
    return { sequence, generation: room.generation };
  }

  close(id: string, supplied: string) {
    const room = this.access(id, supplied, false, true);
    this.rooms.delete(id);
    for (const notify of room.listeners.values()) { try { notify("closed"); } catch {} }
    room.listeners.clear(); room.presence.clear(); room.events = []; room.snapshot = { iv: "", data: "" };
  }
}

const registry = globalThis as typeof globalThis & { __crabrixTemporaryRooms?: PlaygroundRooms };
export const playgroundRooms = registry.__crabrixTemporaryRooms ??= new PlaygroundRooms();

// Expired ciphertext is released even when a room has no active readers.
const sweepRegistry = globalThis as typeof globalThis & { __crabrixRoomSweep?: ReturnType<typeof setInterval> };
sweepRegistry.__crabrixRoomSweep ??= setInterval(() => playgroundRooms.prune(), 1000);
sweepRegistry.__crabrixRoomSweep.unref?.();
