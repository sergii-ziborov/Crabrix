// Unreleased protocol foundation. Authentication here never grants execution.
// A client-local permission/job governor must still authorize every operation.
import { base64url, unbase64url } from "./playground-crypto";

export const RUNTIME_PROTOCOL = "crabrix-runtime-v1";
export const RUNTIME_LIMITS = Object.freeze({ envelopeBytes: 2400, payloadBytes: 768, lifetimeMs: 15000, clockSkewMs: 5000, replayEntries: 512 });
export const runtimeOperations = ["discover", "grant", "check", "build", "run", "debug", "step", "continue", "stop", "status", "stdout", "stderr", "diagnostics", "locals", "breakpoints", "revoke"] as const;
export type RuntimeOperation = typeof runtimeOperations[number];
export type RuntimeKind = "capabilities" | "permission-request" | "command" | "response";
export type RuntimeHeader = readonly [typeof RUNTIME_PROTOCOL, RuntimeKind, string, string, string, string, RuntimeOperation, string, string, string, number, number, string];
export type RuntimeEnvelope = Readonly<{ v: 1; key: string; header: RuntimeHeader; payload: string; signature: string; editProof?: string }>;
export type RuntimeFields = { kind: RuntimeKind; room: string; target: string; requestID: string; operation: RuntimeOperation; revision?: string; job?: string };
export type VerifiedRuntimeFrame = Readonly<{ verified: true; editAccessProved: boolean; header: RuntimeHeader; sender: string; payload: unknown; canonicalHeader: string }>;

const encoder = new TextEncoder();
const decoder = new TextDecoder("utf-8", { fatal: true });
const hex = /^[a-f0-9]{64}$/;
const id = /^[A-Za-z0-9_-]{16,64}$/;
const curve = { name: "ECDSA", namedCurve: "P-256" };
const signatureAlgorithm = { name: "ECDSA", hash: "SHA-256" };
const verifiedFrames = new WeakSet<object>();

function freezePayload(value: unknown): unknown {
  if (value !== null && typeof value === "object") {
    Object.values(value).forEach(freezePayload);
    Object.freeze(value);
  }
  return value;
}

async function digest(bytes: Uint8Array<ArrayBuffer>): Promise<string> {
  return Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)), b => b.toString(16).padStart(2, "0")).join("");
}
function bytes(value: unknown, maximum: number, exact?: number): Uint8Array<ArrayBuffer> {
  if (typeof value !== "string") throw new Error("Invalid runtime encoding.");
  const result = unbase64url(value, maximum);
  if (base64url(result) !== value || exact !== undefined && result.length !== exact) throw new Error("Invalid runtime encoding.");
  return result;
}
function header(value: unknown): RuntimeHeader {
  if (!Array.isArray(value) || value.length !== 13) throw new Error("Invalid runtime header.");
  const [protocol, kind, room, from, to, requestID, operation, revision, job, nonce, issued, expires, payloadHash] = value;
  if (protocol !== RUNTIME_PROTOCOL || !["capabilities", "permission-request", "command", "response"].includes(kind) ||
      typeof room !== "string" || !/^[A-Za-z0-9_-]{24}$/.test(room) || typeof from !== "string" || !hex.test(from) ||
      typeof to !== "string" || !(hex.test(to) || kind === "capabilities" && to === "") ||
      typeof requestID !== "string" || !id.test(requestID) || !runtimeOperations.includes(operation) ||
      typeof revision !== "string" || !(revision === "" || hex.test(revision)) ||
      typeof job !== "string" || !(job === "" || id.test(job)) || typeof nonce !== "string" ||
      !Number.isSafeInteger(issued) || issued < 0 || !Number.isSafeInteger(expires) || expires <= issued || expires - issued > RUNTIME_LIMITS.lifetimeMs ||
      typeof payloadHash !== "string" || !hex.test(payloadHash)) throw new Error("Invalid runtime header.");
  if (kind === "capabilities" && operation !== "discover" || kind === "permission-request" && operation !== "grant" ||
      kind === "command" && ["discover", "grant"].includes(operation)) throw new Error("Invalid runtime message kind.");
  bytes(nonce, 32, 32);
  // Copy before the first asynchronous crypto call: awareness objects are mutable.
  return Object.freeze([...value]) as RuntimeHeader;
}
function fresh(value: RuntimeHeader, now: number) {
  if (!Number.isSafeInteger(now) || value[10] > now + RUNTIME_LIMITS.clockSkewMs || value[11] <= now) throw new Error("Runtime message expired or device clocks disagree.");
}
function proofInput(canonicalHeader: string, signature: string) {
  return encoder.encode("crabrix-runtime-edit-proof-v1\n" + canonicalHeader + "\n" + signature);
}
async function editKey(capability: string, usages: KeyUsage[]) {
  bytes(capability, 32, 32);
  // The opaque edit capability, not the AES room key, proves edit access.
  return crypto.subtle.importKey("raw", encoder.encode(capability), { name: "HMAC", hash: "SHA-256" }, false, usages);
}
function boundedEnvelope(value: RuntimeEnvelope): RuntimeEnvelope {
  if (encoder.encode(JSON.stringify(value)).length > RUNTIME_LIMITS.envelopeBytes) throw new Error("Runtime message exceeds the transient presence budget.");
  return Object.freeze(value);
}

export async function createRuntimeSigner() {
  let pair: CryptoKeyPair | null = await crypto.subtle.generateKey(curve, false, ["sign", "verify"]) as CryptoKeyPair;
  const raw = new Uint8Array(await crypto.subtle.exportKey("raw", pair.publicKey));
  const key = base64url(raw), fingerprint = await digest(raw);
  return Object.freeze({
    key, fingerprint,
    destroy() { pair = null; },
    async sign(fields: RuntimeFields, payload: unknown, options: { editCapability?: string; now?: number; lifetimeMs?: number } = {}): Promise<RuntimeEnvelope> {
      const active = pair;
      if (!active) throw new Error("Runtime signer is closed.");
      const editCapability = options.editCapability;
      const payloadJSON = JSON.stringify(payload);
      if (payloadJSON === undefined) throw new Error("Invalid runtime payload.");
      const data = encoder.encode(payloadJSON);
      if (data.length > RUNTIME_LIMITS.payloadBytes) throw new Error("Runtime payload exceeds its page budget.");
      const now = options.now ?? Date.now(), lifetime = options.lifetimeMs ?? RUNTIME_LIMITS.lifetimeMs;
      const body = header([RUNTIME_PROTOCOL, fields.kind, fields.room, fingerprint, fields.target, fields.requestID, fields.operation,
        fields.revision ?? "", fields.job ?? "", base64url(crypto.getRandomValues(new Uint8Array(32))), now, now + lifetime, await digest(data)]);
      const canonicalHeader = JSON.stringify(body);
      const signature = base64url(new Uint8Array(await crypto.subtle.sign(signatureAlgorithm, active.privateKey, encoder.encode(canonicalHeader))));
      const result: RuntimeEnvelope = { v: 1, key, header: body, payload: base64url(data), signature };
      const editProof = editCapability === undefined ? undefined : base64url(new Uint8Array(await crypto.subtle.sign("HMAC", await editKey(editCapability, ["sign"]), proofInput(canonicalHeader, signature))));
      if (pair !== active) throw new Error("Runtime signer is closed.");
      return boundedEnvelope(editProof === undefined ? result : { ...result, editProof });
    },
  });
}

export async function verifyRuntimeEnvelope(input: unknown, context: {
  room: string; target?: string; sender?: string; editCapability?: string; requireEditProof?: boolean; clock?: () => number;
}): Promise<VerifiedRuntimeFrame> {
  if (!input || typeof input !== "object" || Array.isArray(input)) throw new Error("Invalid runtime envelope.");
  const value = input as Record<string, unknown>;
  const keys = Object.keys(value).sort();
  const expected = ["v", "key", "header", "payload", "signature", ...(Object.hasOwn(value, "editProof") ? ["editProof"] : [])].sort();
  if (keys.join(",") !== expected.join(",") || value.v !== 1 || typeof value.key !== "string" || typeof value.payload !== "string" ||
      typeof value.signature !== "string" || Object.hasOwn(value, "editProof") && typeof value.editProof !== "string") throw new Error("Invalid runtime envelope fields.");
  // Own all checked data before await. Later mutations of a peer's object cannot
  // change which command/payload was actually authenticated.
  const body = header(value.header), key = value.key, payload = value.payload, signature = value.signature;
  const editProof = value.editProof as string | undefined;
  const { room, target, sender, editCapability, requireEditProof } = context;
  const envelope = boundedEnvelope({ v: 1, key, header: body, payload, signature, ...(editProof === undefined ? {} : { editProof }) });
  const clock = context.clock ?? Date.now;
  fresh(body, clock());
  if (body[2] !== room || target !== undefined && body[4] !== target || sender !== undefined && body[3] !== sender) throw new Error("Runtime room or participant does not match.");
  const rawKey = bytes(key, 65, 65), rawSignature = bytes(signature, 64, 64), data = bytes(payload, RUNTIME_LIMITS.payloadBytes);
  if (rawKey[0] !== 4 || await digest(rawKey) !== body[3] || await digest(data) !== body[12]) throw new Error("Runtime identity or payload digest does not match.");
  const canonicalHeader = JSON.stringify(body);
  const publicKey = await crypto.subtle.importKey("raw", rawKey, curve, false, ["verify"]);
  if (!await crypto.subtle.verify(signatureAlgorithm, publicKey, rawSignature, encoder.encode(canonicalHeader))) throw new Error("Invalid runtime signature.");
  if (requireEditProof || editProof !== undefined) {
    if (!editCapability || !editProof || !await crypto.subtle.verify("HMAC", await editKey(editCapability, ["verify"]), bytes(editProof, 32, 32), proofInput(canonicalHeader, envelope.signature))) throw new Error("Runtime edit access was not proved.");
  }
  let decoded: unknown;
  try { decoded = freezePayload(JSON.parse(decoder.decode(data))); }
  catch { throw new Error("Invalid runtime payload JSON."); }
  fresh(body, clock());
  const frame = Object.freeze({ verified: true as const, editAccessProved: editProof !== undefined, header: body, sender: body[3], payload: decoded, canonicalHeader });
  verifiedFrames.add(frame);
  return frame;
}

export class RuntimeReplayWindow {
  private seen = new Map<string, { header: string; expires: number }>();
  consume(frame: VerifiedRuntimeFrame, now = Date.now()): "new" | "duplicate" {
    if (!frame || !verifiedFrames.has(frame)) throw new Error("Runtime frame has not been authenticated.");
    fresh(frame.header, now);
    for (const [key, value] of this.seen) if (value.expires <= now) this.seen.delete(key);
    const key = frame.sender + ":" + frame.header[9], previous = this.seen.get(key);
    if (previous) {
      if (previous.header !== frame.canonicalHeader) throw new Error("Runtime nonce was reused for a different message.");
      return "duplicate";
    }
    // Never evict an unexpired nonce: doing so could permit replay after flooding.
    if (this.seen.size >= RUNTIME_LIMITS.replayEntries) throw new Error("Runtime replay window is full.");
    this.seen.set(key, { header: frame.canonicalHeader, expires: frame.header[11] });
    return "new";
  }
}
