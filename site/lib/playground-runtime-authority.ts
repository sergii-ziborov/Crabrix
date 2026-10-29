// Unreleased client-local policy. No network, compiler, shell or account storage.
// Only an explicit local UI action may call allow(); receiving a packet cannot.
import { base64url } from "./playground-crypto";
import { RuntimeReplayWindow, type RuntimeOperation, type VerifiedRuntimeFrame } from "./playground-runtime-protocol";

export const runtimeActions = ["check", "build", "run", "debug"] as const;
export type RuntimeAction = typeof runtimeActions[number];
export type RuntimeOwnedJob = { id: string; grant: string; revision: string; operation: RuntimeAction; state: "working" | "paused" | "finished" };
export type RuntimeAuthorityContext = {
  room: string; target: string; scope: string; expires: number; revision: string;
  foreground: boolean; connected: boolean; editConfirmed: boolean; ready: boolean; busy: boolean;
  job: (id: string) => RuntimeOwnedJob | undefined;
};
export type RuntimeGrant = Readonly<{ id: string; controller: string; name: string; operations: readonly RuntimeAction[]; expires: number }>;
type Pending = { controller: string; requestID: string; hash: string; name: string; operations: RuntimeAction[]; expires: number; lease: number };
export type RuntimeAdmission = Readonly<{ kind: "new" | "duplicate" | "denied"; requestID: string; reason?: string }>;
type Receipt = { identity: string; admission: RuntimeAdmission };
const names = (value: unknown): value is string => typeof value === "string" && value.length > 0 && value.length <= 40 && !/[\u0000-\u001f\u007f]/.test(value);
const object = (value: unknown): value is Record<string, unknown> => !!value && typeof value === "object" && !Array.isArray(value);
const actions = (value: unknown): value is RuntimeAction[] => Array.isArray(value) && value.length > 0 && value.length <= 4 && new Set(value).size === value.length && value.every(v => runtimeActions.includes(v));

export class RuntimeAuthority {
  private readonly binding: Pick<RuntimeAuthorityContext, "room" | "target" | "scope">;
  private readonly replay = new RuntimeReplayWindow();
  private pending = new Map<string, Pending>();
  private grant: RuntimeGrant | null = null;
  private lease = 0;
  private receipts = new Map<string, Receipt>();
  constructor(private context: () => RuntimeAuthorityContext, private revoked: (grant: string, reason: string) => void, private clock = Date.now) {
    const { room, target, scope } = context(); this.binding = { room, target, scope };
  }
  private base(context: RuntimeAuthorityContext) {
    return context.room === this.binding.room && context.target === this.binding.target && context.scope === this.binding.scope &&
      context.foreground && context.connected && context.editConfirmed && context.expires > this.clock();
  }
  tick() {
    const context = this.context(), now = this.clock();
    if (!this.base(context)) { this.revoke("The local room, connection or foreground permission changed."); this.pending.clear(); return; }
    for (const [key, value] of this.pending) if (value.expires <= now || value.lease <= now) this.pending.delete(key);
    if (this.grant && (this.grant.expires <= now || this.lease <= now)) this.revoke("The runtime grant or controller lease expired.");
  }
  status() {
    this.tick();
    return Object.freeze({ grant: this.grant, requests: Object.freeze([...this.pending.values()].map(p => Object.freeze({ controller: p.controller, requestID: p.requestID, name: p.name, operations: Object.freeze([...p.operations]), expires: p.expires }))) });
  }
  revoke(reason = "Revoked on this device.") {
    const previous = this.grant; this.grant = null; this.lease = 0; this.receipts.clear();
    if (previous) this.revoked(previous.id, reason);
  }
  receiveRequest(frame: VerifiedRuntimeFrame) {
    this.tick(); const context = this.context(), payload = frame.payload;
    if (!this.base(context) || frame.header[1] !== "permission-request" || frame.header[6] !== "grant" || frame.header[2] !== context.room || frame.header[4] !== context.target || !frame.editAccessProved) throw new Error("This device has not authorized runtime requests for this editable connection.");
    if (!object(payload) || Object.keys(payload).sort().join(",") !== "name,operations" || !names(payload.name) || !actions(payload.operations)) throw new Error("Invalid runtime permission request.");
    this.replay.consume(frame, this.clock());
    const previous = this.pending.get(frame.sender);
    if (previous?.requestID === frame.header[5] && previous.hash !== frame.header[12]) throw new Error("The permission request changed its requested operations.");
    if (!previous && this.pending.size >= 4) throw new Error("The local permission request limit has been reached.");
    this.pending.set(frame.sender, { controller: frame.sender, requestID: frame.header[5], hash: frame.header[12], name: payload.name, operations: [...payload.operations],
      expires: previous?.requestID === frame.header[5] ? previous.expires : Math.min(this.clock() + 120_000, context.expires), lease: Math.min(frame.header[11], context.expires) });
  }
  observeController(frame: VerifiedRuntimeFrame) {
    this.tick(); const context = this.context(), payload = frame.payload;
    if (!this.base(context) || frame.header[1] !== "capabilities" || frame.header[6] !== "discover" || frame.header[2] !== context.room || frame.header[4] !== "" && frame.header[4] !== context.target || !frame.editAccessProved) return;
    if (!this.pending.has(frame.sender) && this.grant?.controller !== frame.sender) return;
    if (!object(payload) || Object.keys(payload).sort().join(",") !== "name,role" || payload.role !== "controller" || !names(payload.name)) return;
    this.replay.consume(frame, this.clock());
    const deadline = Math.min(frame.header[11], context.expires);
    const pending = this.pending.get(frame.sender); if (pending) pending.lease = Math.max(pending.lease, deadline);
    if (this.grant?.controller === frame.sender) this.lease = Math.max(this.lease, Math.min(deadline, this.grant.expires));
  }
  // A controller key/request ID and scopes selected by the human on THIS client.
  // Neither the requested scopes nor an edit link is an automatic grant.
  allow(controller: string, requestID: string, operations: RuntimeAction[], lifetimeMs = 600_000): RuntimeGrant {
    this.tick(); const context = this.context(), pending = this.pending.get(controller), now = this.clock();
    if (!this.base(context) || !pending || pending.requestID !== requestID) throw new Error("The local permission request expired or changed.");
    if (!actions(operations) || operations.some(op => !pending.operations.includes(op)) || !Number.isSafeInteger(lifetimeMs) || lifetimeMs < 1000 || lifetimeMs > 600_000) throw new Error("Choose explicit requested operations for up to ten minutes.");
    const expires = Math.min(now + lifetimeMs, context.expires);
    if (expires <= now) throw new Error("This room has expired.");
    this.revoke("Replaced by an explicit local grant.");
    this.grant = Object.freeze({ id: base64url(crypto.getRandomValues(new Uint8Array(24))), controller, name: pending.name, operations: Object.freeze(runtimeActions.filter(op => operations.includes(op))), expires });
    this.lease = Math.min(pending.lease, expires); this.pending.clear();
    return this.grant;
  }
  admit(frame: VerifiedRuntimeFrame): RuntimeAdmission {
    this.tick(); const context = this.context(), grant = this.grant, payload = frame.payload, requestID = frame.header[5];
    const denied = (reason: string): RuntimeAdmission => Object.freeze({ kind: "denied", requestID, reason });
    if (!grant || !this.base(context) || frame.header[1] !== "command" || frame.header[2] !== context.room || frame.header[4] !== context.target || frame.sender !== grant.controller || !frame.editAccessProved || !object(payload) || payload.grant !== grant.id) return denied("No matching explicit local grant.");
    // This call also rejects forged JS objects that did not pass crypto verification.
    this.replay.consume(frame, this.clock());
    const identity = JSON.stringify([frame.header[6], frame.header[7], frame.header[8], frame.header[12]]), previous = this.receipts.get(requestID);
    if (previous) {
      if (identity !== previous.identity) return denied("A request ID was reused for a different command.");
      return previous.admission.kind === "denied" ? previous.admission : Object.freeze({ kind: "duplicate", requestID });
    }
    if (this.receipts.size >= 2048) return denied("This grant reached its command receipt budget.");
    let reason: string | undefined;
    const operation: RuntimeOperation = frame.header[6], isStart = runtimeActions.includes(operation as RuntimeAction);
    if (isStart) {
      if (!grant.operations.includes(operation as RuntimeAction)) reason = "This operation was not granted on the device.";
      else if (frame.header[8] !== "") reason = "A start command cannot claim an existing job.";
      else if (!context.ready) reason = "The local compiler profile is not prepared; no download was started.";
      else if (context.busy) reason = "The local compiler is busy; this command was not queued.";
      else if (frame.header[7] !== context.revision) reason = "Shared source changed; read its current revision before retrying.";
    } else {
      const job = context.job(frame.header[8]);
      if (!job || job.grant !== grant.id || job.revision !== frame.header[7]) reason = "This command does not identify a job owned by this grant.";
      else if (!["stop", "status", "stdout", "stderr", "diagnostics", "locals", "step", "continue", "breakpoints"].includes(operation)) reason = "Unsupported runtime command.";
      else if (operation !== "stop" && context.revision !== job.revision) reason = "This job belongs to older shared source.";
      else if (["locals", "step", "continue", "breakpoints"].includes(operation) && (job.operation !== "debug" || !grant.operations.includes("debug") || job.state !== "paused")) reason = "Debug commands require this grant's matching paused Debug job.";
    }
    const admission: RuntimeAdmission = reason ? denied(reason) : Object.freeze({ kind: "new", requestID });
    this.receipts.set(requestID, { identity, admission });
    return admission;
  }
}
