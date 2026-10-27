// Temporary encrypted relay state. Intentionally no fs/database/account imports.
import { createHash, randomBytes, timingSafeEqual } from "node:crypto";

export type EncryptedPacket = { iv: string; data: string };
export type RoomEvent = { sequence: number; peer: string; packet: EncryptedPacket };
export type PresenceEvent = { kind: "presence"; peer: string; packet: EncryptedPacket };
type Capability = "edit" | "view" | "owner";
type Room = {
  id: string; createdAt: number; expiresAt: number; sequence: number;
  tokens: Record<Capability, Buffer>; snapshot: EncryptedPacket; snapshotSequence: number;
  events: RoomEvent[]; presence: Map<string, { packet: EncryptedPacket; at: number }>; listeners: Map<string, (event: RoomEvent | PresenceEvent | "expired" | "closed") => void>;
  recentMessages: Map<string, number>;
};
export class PlaygroundError extends Error {
  status: number;
  constructor(message: string, status = 400) { super(message); this.status = status; }
}
const hash = (value: string) => createHash("sha256").update(value).digest();
const token = () => randomBytes(32).toString("base64url");
const packetBytes = (packet: EncryptedPacket) => packet.data.length + packet.iv.length;
export const ROOM_LIMITS = Object.freeze({ rooms: 64, peers: 4, snapshotBytes: 256 * 1024, updateBytes: 192 * 1024, presenceBytes: 4096, events: 256, residentBytes: 32 * 1024 * 1024 });

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
    for (const [key, bucket] of this.buckets) if (now - bucket.start > 60_000) this.buckets.delete(key);
  }

  limit(identity: string, maximum: number) {
    this.prune();
    const key = hash(identity).toString("hex");
    const now = this.now();
    const bucket = this.buckets.get(key);
    if (bucket && now - bucket.start < 60_000) {
      if (++bucket.count > maximum) throw new PlaygroundError("Too many requests. Please wait a minute.", 429);
    } else {
      if (this.buckets.size >= 10_000) throw new PlaygroundError("Playground traffic is busy. Please retry shortly.", 503);
      this.buckets.set(key, { start: now, count: 1 });
    }
  }

  residentBytes(): number {
    return Array.from(this.rooms.values()).reduce((n, room) => n + packetBytes(room.snapshot) + room.events.reduce((a, event) => a + packetBytes(event.packet), 0), 0);
  }

  create(snapshot: EncryptedPacket, lifetimeSeconds: number) {
    this.prune();
    snapshot = validatePacket(snapshot, ROOM_LIMITS.snapshotBytes);
    if (!Number.isInteger(lifetimeSeconds) || lifetimeSeconds < 60 || lifetimeSeconds > 86_400) throw new PlaygroundError("Lifetime must be between one minute and 24 hours.");
    if (this.rooms.size >= ROOM_LIMITS.rooms || this.residentBytes() + packetBytes(snapshot) > ROOM_LIMITS.residentBytes) throw new PlaygroundError("Temporary rooms are at capacity. Please retry later.", 503);
    const id = randomBytes(18).toString("base64url");
    const owner = token(), edit = token(), view = token();
    const createdAt = this.now(), expiresAt = createdAt + lifetimeSeconds * 1000;
    this.rooms.set(id, { id, createdAt, expiresAt, sequence: 0, tokens: { owner: hash(owner), edit: hash(edit), view: hash(view) }, snapshot,
      snapshotSequence: 0, events: [], presence: new Map(), listeners: new Map(), recentMessages: new Map() });
    return { id, createdAt, expiresAt, owner, edit, view };
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

  state(id: string, supplied: string) {
    const room = this.access(id, supplied);
    return { id, createdAt: room.createdAt, expiresAt: room.expiresAt, sequence: room.sequence,
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

  append(id: string, supplied: string, peer: string, messageID: string, packet: EncryptedPacket) {
    const room = this.access(id, supplied, true);
    packet = validatePacket(packet, ROOM_LIMITS.updateBytes);
    if (!room.listeners.has(peer) || !/^[A-Za-z0-9_-]{16,64}$/.test(messageID)) throw new PlaygroundError("Join the interview before sending changes.", 409);
    this.limit(`updates:${id}:${peer}`, 180);
    const previous = room.recentMessages.get(messageID);
    if (previous !== undefined) return { sequence: previous };
    if (room.events.length >= ROOM_LIMITS.events || this.residentBytes() + packetBytes(packet) > ROOM_LIMITS.residentBytes) throw new PlaygroundError("Waiting for a fresh encrypted snapshot; retry your update.", 409);
    const event = { sequence: ++room.sequence, peer, packet };
    room.events.push(event); room.recentMessages.set(messageID, event.sequence);
    if (room.recentMessages.size > 512) room.recentMessages.delete(room.recentMessages.keys().next().value!);
    for (const notify of room.listeners.values()) { try { notify(event); } catch {} }
    return { sequence: event.sequence };
  }

  publishPresence(id: string, supplied: string, peer: string, packet: EncryptedPacket) {
    const room = this.access(id, supplied);
    if (!room.listeners.has(peer)) throw new PlaygroundError("Join the interview before sending presence.", 409);
    packet = validatePacket(packet, ROOM_LIMITS.presenceBytes);
    this.limit(`presence:${id}:${peer}`, 300);
    room.presence.set(peer, { packet, at: this.now() });
    for (const notify of room.listeners.values()) { try { notify({ kind: "presence", peer, packet }); } catch {} }
  }

  compact(id: string, supplied: string, sequence: number, snapshot: EncryptedPacket) {
    const room = this.access(id, supplied, true);
    snapshot = validatePacket(snapshot, ROOM_LIMITS.snapshotBytes);
    if (sequence !== room.sequence) throw new PlaygroundError("Receive the latest changes before publishing a snapshot.", 409);
    const delta = packetBytes(snapshot) - packetBytes(room.snapshot) - room.events.reduce((n, event) => n + packetBytes(event.packet), 0);
    if (this.residentBytes() + delta > ROOM_LIMITS.residentBytes) throw new PlaygroundError("Temporary room memory is full.", 503);
    room.snapshot = snapshot; room.snapshotSequence = sequence; room.events = [];
    return { sequence };
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
