import * as Y from "yjs";
import type { Awareness } from "y-protocols/awareness";
import { localPresence, receivePresence } from "./playground-presence";
import { base64url, decryptPlayground, encryptPlayground, newEncryptionSecret } from "./playground-crypto";
import { documentFromY } from "./playground-collab";
import type { EncryptedPacket } from "./playground-rooms";

export type PlaygroundLink = { id: string; key: string; access: string; expiresAt: number; mode: "edit" | "view" };
export type CreatedPlayground = PlaygroundLink & { owner: string; view: string };
type State = { expiresAt: number; sequence: number; snapshotSequence: number; snapshot: EncryptedPacket; events: { sequence: number; packet: EncryptedPacket }[]; presence?: { packet: EncryptedPacket }[] };

export function parsePlaygroundLink(url: URL): PlaygroundLink | null {
  const match = url.pathname.match(/^\/playground\/room\/([A-Za-z0-9_-]{24})\/?$/);
  if (!match) { if (url.pathname.startsWith("/playground/room/")) throw new Error("This Playground link has an invalid room identifier."); return null; }
  const fragment = new URLSearchParams(url.hash.slice(1));
  const key = fragment.get("key") ?? "", access = fragment.get("access") ?? "", expiresAt = Number(fragment.get("expires")), mode = fragment.get("mode") === "view" ? "view" : "edit";
  if (!/^[A-Za-z0-9_-]{43}$/.test(key) || !/^[A-Za-z0-9_-]{43}$/.test(access) || !Number.isSafeInteger(expiresAt)) throw new Error("This Playground link is incomplete. Copy the entire link, including its # fragment.");
  return { id: match[1], key, access, expiresAt, mode };
}

export function playgroundLink(link: PlaygroundLink, origin = location.origin): string {
  const fragment = new URLSearchParams({ key: link.key, access: link.access, expires: String(link.expiresAt), mode: link.mode });
  return `${origin}/playground/room/${link.id}/#${fragment}`;
}

export async function createPlayground(doc: Y.Doc, lifetimeSeconds: number): Promise<CreatedPlayground> {
  documentFromY(doc);
  const key = newEncryptionSecret(), snapshot = await encryptPlayground(key, Y.encodeStateAsUpdate(doc));
  const response = await fetch("/api/playground/rooms/", { method: "POST", credentials: "omit", cache: "no-store", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ snapshot, lifetimeSeconds }) });
  const result = await response.json();
  if (!response.ok) throw new Error(result.error ?? "Could not create the temporary Playground.");
  return { id: result.id, key, access: result.edit, owner: result.owner, view: result.view, expiresAt: result.expiresAt, mode: "edit" };
}

export class PlaygroundSession {
  doc: Y.Doc; link: PlaygroundLink;
  peer = base64url(crypto.getRandomValues(new Uint8Array(16)));
  abort = new AbortController(); sequence = 0; pending: Uint8Array[] = [];
  sending = false; stopped = false; connected = false; receivedState = false;
  flushTimer?: ReturnType<typeof setTimeout>; snapshotTimer?: ReturnType<typeof setTimeout>;
  onStatus: (status: string) => void;
  onExpiry: () => void;
  awareness?: Awareness; presenceTimer?: ReturnType<typeof setTimeout>; heartbeat?: ReturnType<typeof setInterval>; presenceSending = false;
  private relayOrigin: string;
  private runtimeConnection = 0;
  private confirmedRuntimeBinding = "";
  onRuntimeReset?: () => void;

  private runtimeBinding() { return JSON.stringify([this.runtimeConnection, this.relayOrigin, this.link.id, this.link.key, this.link.access, this.link.expiresAt, this.link.mode]); }
  private resetRuntime() { this.runtimeConnection++; this.confirmedRuntimeBinding = ""; this.onRuntimeReset?.(); }
  get runtimeEditConfirmed() { return this.connected && !this.stopped && this.link.mode === "edit" && this.link.expiresAt > Date.now() && this.confirmedRuntimeBinding === this.runtimeBinding(); }
  async confirmRuntimeEditAccess(): Promise<void> {
    if (!this.connected || this.stopped || this.link.mode !== "edit" || this.link.expiresAt <= Date.now()) throw new Error("Runtime access requires a connected editable room.");
    if (this.runtimeEditConfirmed) return;
    const binding = this.runtimeBinding(), link = { ...this.link };
    // Yjs's empty update changes no source. Only the relay's edit capability can
    // obtain this acknowledgement; flipping a view URL's mode cannot prove it.
    const packet = await encryptPlayground(link.key, new Uint8Array([0, 0]));
    if (binding !== this.runtimeBinding() || !this.connected || this.stopped) throw new Error("Runtime connection changed before edit confirmation.");
    const response = await fetch(this.relayOrigin + "/api/playground/rooms/" + link.id + "/", { method: "POST", headers: { Authorization: "Bearer " + link.access, "Content-Type": "application/json" }, credentials: "omit", cache: "no-store", signal: this.abort.signal,
      body: JSON.stringify({ type: "update", peer: this.peer, messageID: newEncryptionSecret(), packet }) });
    if (!response.ok) throw new Error("The relay did not confirm edit access. A view link cannot authorize runtime control.");
    const result = await response.json();
    if (!Number.isSafeInteger(result.sequence) || result.sequence < 1 || binding !== this.runtimeBinding() || !this.connected || this.stopped || this.link.expiresAt <= Date.now()) throw new Error("Runtime connection changed during edit confirmation.");
    this.confirmedRuntimeBinding = binding;
  }

  constructor(doc: Y.Doc, link: PlaygroundLink, onStatus: (status: string) => void, onExpiry: () => void, awareness?: Awareness, relayOrigin = "") {
    this.doc = doc; this.link = link; this.onStatus = onStatus; this.onExpiry = onExpiry; this.awareness = awareness; this.relayOrigin = relayOrigin;
  }

  private headers() { return { Authorization: "Bearer " + this.link.access, "Content-Type": "application/json" }; }
  private endpoint() { return this.relayOrigin + "/api/playground/rooms/" + this.link.id + "/"; }
  private update = (bytes: Uint8Array, origin: unknown) => {
    if (origin === this || this.link.mode === "view" || this.stopped) return;
    this.pending.push(bytes);
    if (this.flushTimer) clearTimeout(this.flushTimer);
    this.flushTimer = setTimeout(() => { void this.flush(); }, 200);
  };

  private presenceUpdate = (_: unknown, origin: unknown) => {
    if (origin === this || this.stopped || !this.connected) return;
    if (this.presenceTimer) clearTimeout(this.presenceTimer);
    this.presenceTimer = setTimeout(() => { void this.sendPresence(); }, 150);
  };

  private async sendPresence() {
    if (!this.awareness || !this.connected || this.stopped || this.presenceSending) return;
    this.presenceSending = true;
    try {
      const packet = await encryptPlayground(this.link.key, localPresence(this.awareness));
      await fetch(this.endpoint(), { method: "POST", headers: this.headers(), credentials: "omit", cache: "no-store", signal: this.abort.signal,
        body: JSON.stringify({ type: "presence", peer: this.peer, packet }) });
    } catch { /* The source stream controls reconnection; presence is transient. */ }
    finally { this.presenceSending = false; }
  }

  async start() {
    this.awareness?.on("update", this.presenceUpdate);
    this.heartbeat = setInterval(() => { void this.sendPresence(); }, 10_000);
    this.doc.on("update", this.update);
    while (!this.stopped && Date.now() < this.link.expiresAt) {
      try {
        await this.stream();
      } catch (error) {
        if (this.stopped) return;
        this.connected = false;
        this.onStatus("Reconnecting — your local changes are retained. " + (error instanceof Error ? error.message : ""));
      }
      this.resetRuntime();
      this.connected = false;
      if (!this.stopped) await new Promise(resolve => setTimeout(resolve, 2000));
    }
    if (!this.stopped) this.expire();
  }

  private async stream() {
    const response = await fetch(this.endpoint() + "events/?peer=" + this.peer, { headers: this.headers(), signal: this.abort.signal, credentials: "omit", cache: "no-store" });
    if (response.status === 410) { this.expire(); return; }
    if (!response.ok || !response.body) { const error = await response.json(); throw new Error(error.error ?? "Interview connection unavailable."); }
    const reader = response.body.getReader(), decoder = new TextDecoder(); let buffer = "";
    try {
      while (!this.stopped) {
        const { done, value } = await reader.read(); if (done) return;
        buffer += decoder.decode(value, { stream: true });
        if (buffer.length > 2_000_000) throw new Error("Oversized interview message.");
        let end: number;
        while ((end = buffer.indexOf("\n\n")) >= 0) {
          const block = buffer.slice(0, end); buffer = buffer.slice(end + 2);
          const type = block.split("\n").find(line => line.startsWith("event: "))?.slice(7);
          const raw = block.split("\n").find(line => line.startsWith("data: "))?.slice(6);
          if (!raw || !type || type === "ping") continue;
          if (type === "expired" || type === "closed") { this.expire(); return; }
          const data = JSON.parse(raw);
          if (type === "state") await this.receiveState(data as State);
          else if (type === "presence" && this.awareness) {
            await this.receiveParticipant(data.packet);
          } else if (type === "update") {
            await this.receive(data.packet, Number(data.sequence));
            this.scheduleSnapshot();
          }
        }
      }
    } finally { await reader.cancel().catch(() => {}); }
  }

  private async receiveState(state: State) {
    this.resetRuntime();
    if (!Number.isSafeInteger(state.expiresAt) || state.expiresAt !== this.link.expiresAt) throw new Error("Playground lifetime does not match this link.");
    const bytes = await decryptPlayground(this.link.key, state.snapshot);
    const candidate = new Y.Doc();
    try {
      Y.applyUpdate(candidate, bytes);
      for (const event of state.events) Y.applyUpdate(candidate, await decryptPlayground(this.link.key, event.packet, 192 * 1024));
      documentFromY(candidate);
      // Capture edits made during initial creation or a disconnected interval.
      // A late join starts with an empty Doc, so this is the empty update there.
      if (this.link.mode !== "view") {
        const localDelta = Y.encodeStateAsUpdate(this.doc, Y.encodeStateVector(candidate));
        if (localDelta.length > 2) this.pending.push(localDelta);
      }
      Y.applyUpdate(this.doc, Y.encodeStateAsUpdate(candidate), this);
      this.sequence = state.sequence;
    } finally { candidate.destroy(); }
    if (this.awareness) for (const item of state.presence ?? []) await this.receiveParticipant(item.packet);
    this.receivedState = true; this.connected = true;
    void this.sendPresence();
    this.onStatus(this.link.mode === "view" ? "Connected · view only · end-to-end encrypted" : "Connected · shared editor · end-to-end encrypted");
    await this.flush();
  }

  private async receiveParticipant(packet: EncryptedPacket) {
    const awareness = this.awareness;
    if (!awareness || this.stopped) return;
    try {
      const bytes = await decryptPlayground(this.link.key, packet, 4000);
      if (!this.stopped && awareness === this.awareness) receivePresence(awareness, bytes, this);
    } catch { /* An invalid transient peer packet must not disconnect source or revoke another controller's grant. */ }
  }

  private async receive(packet: EncryptedPacket, sequence: number) {
    if (!Number.isSafeInteger(sequence) || sequence <= this.sequence) return;
    if (sequence !== this.sequence + 1) throw new Error("Resynchronizing a missing interview update.");
    const bytes = await decryptPlayground(this.link.key, packet, 192 * 1024);
    const candidate = new Y.Doc();
    try {
      Y.applyUpdate(candidate, Y.encodeStateAsUpdate(this.doc)); Y.applyUpdate(candidate, bytes);
      documentFromY(candidate);
      Y.applyUpdate(this.doc, bytes, this);
      this.sequence = sequence;
    } finally { candidate.destroy(); }
  }

  private async flush() {
    if (this.sending || !this.connected || this.stopped || !this.pending.length) return;
    this.sending = true;
    const changes = this.pending.splice(0), messageID = base64url(crypto.getRandomValues(new Uint8Array(16)));
    const bytes = Y.mergeUpdates(changes);
    try {
      documentFromY(this.doc);
      if (bytes.length > 192 * 1024 - 16) throw new Error("This edit is too large for a live update. Download the project before starting a new session.");
      const packet = await encryptPlayground(this.link.key, bytes);
      const response = await fetch(this.endpoint(), { method: "POST", headers: this.headers(), credentials: "omit", cache: "no-store", signal: this.abort.signal,
        body: JSON.stringify({ type: "update", peer: this.peer, messageID, packet }) });
      if (response.status === 410) { this.expire(); return; }
      const result = await response.json();
      if (!response.ok) throw new Error(result.error ?? "Changes were not relayed.");
      this.scheduleSnapshot();
    } catch (error) {
      if (!this.stopped) {
        this.pending.unshift(...changes);
        this.onStatus("Local changes pending. " + (error instanceof Error ? error.message : ""));
      }
    } finally {
      this.sending = false;
      if (this.pending.length && !this.stopped) this.flushTimer = setTimeout(() => { void this.flush(); }, 2000);
    }
  }

  private scheduleSnapshot() {
    if (this.link.mode === "view" || this.snapshotTimer || this.stopped) return;
    this.snapshotTimer = setTimeout(() => {
      this.snapshotTimer = undefined;
      void this.snapshot();
    }, 5000);
  }

  private async snapshot() {
    if (!this.connected || this.pending.length || this.stopped) return;
    try {
      const sequence = this.sequence;
      const packet = await encryptPlayground(this.link.key, Y.encodeStateAsUpdate(this.doc));
      const response = await fetch(this.endpoint(), { method: "POST", credentials: "omit", cache: "no-store", headers: this.headers(), signal: this.abort.signal,
        body: JSON.stringify({ type: "snapshot", sequence, packet }) });
      if (response.status === 409) this.scheduleSnapshot();
      else if (!response.ok) this.onStatus("Snapshot limit reached. Download a local copy to keep this project.");
    } catch { /* Source remains in the editor; stream reconnection reports connectivity. */ }
  }

  private expire() { this.onStatus("This temporary Playground has expired."); this.onExpiry(); this.stop(); }
  stop() {
    if (this.stopped) return;
    this.stopped = true; this.connected = false; this.resetRuntime(); this.abort.abort(); this.doc.off("update", this.update);
    this.awareness?.off("update", this.presenceUpdate);
    if (this.presenceTimer) clearTimeout(this.presenceTimer); if (this.heartbeat) clearInterval(this.heartbeat);
    if (this.flushTimer) clearTimeout(this.flushTimer); if (this.snapshotTimer) clearTimeout(this.snapshotTimer);
  }
}
