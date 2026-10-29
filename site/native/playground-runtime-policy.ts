import { RuntimeAuthority, runtimeActions, type RuntimeAuthorityContext, type RuntimeOwnedJob } from "../lib/playground-runtime-authority";
import { verifyRuntimeEnvelope, type VerifiedRuntimeFrame } from "../lib/playground-runtime-protocol";

type Snapshot = Omit<RuntimeAuthorityContext, "job"> & { editCapability: string; jobs: RuntimeOwnedJob[] };
let snapshot: Snapshot | null = null, authority: RuntimeAuthority | null = null;
const revocations: { grant: string; reason: string }[] = [];
const hash = /^[a-f0-9]{64}$/, id = /^[A-Za-z0-9_-]{16,64}$/;
function context(input: unknown): Snapshot {
  if (!input || typeof input !== "object" || Array.isArray(input)) throw new Error("Invalid local runtime context.");
  const v = input as Snapshot;
  if (typeof v.room !== "string" || !/^[A-Za-z0-9_-]{24}$/.test(v.room) || typeof v.target !== "string" || !hash.test(v.target) || typeof v.scope !== "string" || !v.scope || v.scope.length > 200 || /[\u0000-\u001f\u007f]/.test(v.scope) ||
      !Number.isSafeInteger(v.expires) || typeof v.revision !== "string" || !hash.test(v.revision) || typeof v.editCapability !== "string" || !/^[A-Za-z0-9_-]{43}$/.test(v.editCapability) ||
      [v.foreground, v.connected, v.editConfirmed, v.ready, v.busy].some(x => typeof x !== "boolean") || !Array.isArray(v.jobs) || v.jobs.length > 4 ||
      v.jobs.some(j => !j || typeof j.id !== "string" || !id.test(j.id) || typeof j.grant !== "string" || !id.test(j.grant) || typeof j.revision !== "string" || !hash.test(j.revision) || !runtimeActions.includes(j.operation) || !["working", "paused", "finished"].includes(j.state))) throw new Error("Invalid local runtime context fields.");
  return { ...v, jobs: v.jobs.map(j => ({ ...j })) };
}
function status(error?: string) {
  return { ...(authority?.status() ?? { grant: null, requests: [] }), revoked: revocations.splice(0), ...(error ? { error } : {}) };
}
function projection(frame: VerifiedRuntimeFrame) {
  return { sender: frame.sender, requestID: frame.header[5], operation: frame.header[6], revision: frame.header[7], job: frame.header[8], payloadJSON: JSON.stringify(frame.payload) };
}
// Called only by the fixed native wrapper with locally constructed context.
// A room frame supplies an envelope, never the action, context or allow() call.
export async function runtimePolicyRequest(input: unknown) {
  if (!input || typeof input !== "object" || Array.isArray(input)) throw new Error("Invalid local runtime request.");
  const request = input as Record<string, unknown>, local = context(request.context); snapshot = local;
  if (request.action === "initialize") {
    authority?.revoke("Local runtime context replaced.");
    authority = new RuntimeAuthority(() => {
      if (!snapshot) throw new Error("Local runtime context released.");
      return { ...snapshot, job: id => snapshot!.jobs.find(job => job.id === id) };
    }, (grant, reason) => revocations.push({ grant, reason }));
    return status();
  }
  if (!authority) throw new Error("Local runtime permission is not initialized.");
  if (request.action === "status") return status();
  if (request.action === "revoke") { authority.revoke(); return status(); }
  if (request.action === "allow") {
    if (typeof request.controller !== "string" || typeof request.requestID !== "string" || !Array.isArray(request.operations)) throw new Error("Choose a pending local permission request.");
    authority.allow(request.controller, request.requestID, request.operations as never, request.lifetimeMs as number | undefined);
    return status();
  }
  if (!["request", "lease", "admit"].includes(String(request.action)) || typeof request.envelope !== "string" || new TextEncoder().encode(request.envelope).length > 2400) throw new Error("Invalid local runtime action.");
  const frame = await verifyRuntimeEnvelope(JSON.parse(request.envelope), { room: local.room, editCapability: local.editCapability, requireEditProof: true });
  if (snapshot?.scope !== local.scope || snapshot?.target !== local.target || snapshot?.room !== local.room) throw new Error("The local runtime context changed during authentication.");
  if (request.action === "request") authority.receiveRequest(frame);
  else if (request.action === "lease") authority.observeController(frame);
  else { const admission = authority.admit(frame); return { ...status(), admission, verified: projection(frame) }; }
  return { ...status(), verified: projection(frame) };
}

export function callRuntime(requestJSON: string, completion: (result: string) => void) {
  void (async () => {
    try { completion(JSON.stringify(await runtimePolicyRequest(JSON.parse(requestJSON)))); }
    catch (error) {
      const message = error instanceof Error ? error.message : "Local runtime authorization failed.";
      try { completion(JSON.stringify(status(message))); }
      catch { completion(JSON.stringify({ grant: null, requests: [], revoked: revocations.splice(0), error: message })); }
    }
  })();
}
