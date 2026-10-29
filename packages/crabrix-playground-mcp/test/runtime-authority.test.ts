import { test } from "node:test";
import assert from "node:assert/strict";
import { RuntimeAuthority, type RuntimeAuthorityContext, type RuntimeOwnedJob, type RuntimeAction } from "../../../site/lib/playground-runtime-authority";
import { createRuntimeSigner, verifyRuntimeEnvelope, type RuntimeKind, type RuntimeOperation } from "../../../site/lib/playground-runtime-protocol";

async function fixture() {
  let now = 1_000_000;
  const controller = await createRuntimeSigner(), host = await createRuntimeSigner(), capability = "A".repeat(43), revoked: string[] = [];
  const jobs = new Map<string, RuntimeOwnedJob>();
  const context: RuntimeAuthorityContext = { room: "a".repeat(24), target: host.fingerprint, scope: "private-project-and-connection-1", expires: now + 3_600_000, revision: "c".repeat(64), foreground: true, connected: true, editConfirmed: true, ready: true, busy: false, job: id => jobs.get(id) };
  const gate = new RuntimeAuthority(() => context, id => revoked.push(id), () => now);
  async function frame(kind: RuntimeKind, operation: RuntimeOperation, payload: unknown, requestID = "authority-request-001", job = "", revision = context.revision, proof = true) {
    const envelope = await controller.sign({ kind, operation, room: context.room, target: kind === "capabilities" ? "" : host.fingerprint, requestID, revision, job }, payload, { now, ...(proof ? { editCapability: capability } : {}) });
    return verifyRuntimeEnvelope(envelope, { room: context.room, ...(proof ? { editCapability: capability, requireEditProof: true } : {}), clock: () => now });
  }
  async function request(operations: RuntimeAction[] = ["check"], id = "authority-permission-001") { const f = await frame("permission-request", "grant", { name: "Claude · MCP", operations }, id); gate.receiveRequest(f); return f; }
  async function grant(operations: RuntimeAction[] = ["check"]) { const req = await request(operations); return gate.allow(controller.fingerprint, req.header[5], operations); }
  return { gate, context, jobs, revoked, controller, host, frame, request, grant, time: (value: number) => { now = value; }, close: () => { controller.destroy(); host.destroy(); } };
}

test("authenticated permission requests do not grant anything until an explicit local action", async () => {
  const f = await fixture();
  try {
    const request = await f.request(["check", "run"]);
    assert.equal(f.gate.status().grant, null); assert.equal(f.gate.status().requests.length, 1);
    assert.equal(f.gate.admit(await f.frame("command", "run", { grant: "guessed-token" })).kind, "denied");
    const grant = f.gate.allow(f.controller.fingerprint, request.header[5], ["check"]);
    assert.deepEqual(grant.operations, ["check"]); assert.equal(grant.expires, 1_600_000);
    assert.throws(() => (grant.operations as RuntimeAction[]).push("run"), TypeError);
    assert.equal(f.gate.admit(await f.frame("command", "run", { grant: grant.id })).kind, "denied");
    const check = await f.frame("command", "check", { grant: grant.id }, "authority-check-0001");
    assert.equal(f.gate.admit(check).kind, "new"); assert.equal(f.gate.admit(check).kind, "duplicate");
    assert.equal(f.gate.admit(await f.frame("command", "check", { grant: grant.id }, "authority-check-0001")).kind, "duplicate");
  } finally { f.close(); }
});

test("a valid signature without edit proof, unconfirmed role, wrong scope or forged JS object cannot authorize", async () => {
  const f = await fixture();
  try {
    const valid = await f.frame("permission-request", "grant", { name: "Claude", operations: ["check"] });
    const unsignedRole = await f.frame("permission-request", "grant", { name: "Claude", operations: ["check"] }, "authority-noproof-01", "", f.context.revision, false);
    assert.equal(unsignedRole.editAccessProved, false); assert.throws(() => f.gate.receiveRequest(unsignedRole), /not authorized/);
    f.context.editConfirmed = false; assert.throws(() => f.gate.receiveRequest(valid), /not authorized/);
    f.context.editConfirmed = true;
    assert.throws(() => f.gate.receiveRequest(JSON.parse(JSON.stringify(valid))), /not been authenticated/);
    assert.equal(f.gate.status().requests.length, 0);
    const grant = await f.grant(); f.context.scope = "different-private-project";
    assert.equal(f.gate.admit(await f.frame("command", "check", { grant: grant.id })).kind, "denied");
    assert.deepEqual(f.revoked, [grant.id]);
  } finally { f.close(); }
});

test("replaying a signed controller heartbeat cannot extend its original deadline", async () => {
  const f = await fixture();
  try {
    const grant = await f.grant(), heartbeat = await f.frame("capabilities", "discover", { name: "Claude", role: "controller" });
    f.gate.observeController(heartbeat); f.time(1_014_900); f.gate.observeController(heartbeat);
    assert.equal(f.gate.status().grant?.id, grant.id);
    f.time(1_015_000); assert.equal(f.gate.status().grant, null); assert.deepEqual(f.revoked, [grant.id]);
  } finally { f.close(); }
});

test("busy, unprepared and stale commands are rejected immediately and never become deferred work", async () => {
  const f = await fixture();
  try {
    const grant = await f.grant(); f.context.ready = false;
    const before = await f.frame("command", "check", { grant: grant.id }, "authority-unready-01");
    assert.match(f.gate.admit(before).reason!, /not prepared/);
    f.context.ready = true; assert.equal(f.gate.admit(before).kind, "denied");
    assert.equal(f.gate.admit(await f.frame("command", "check", { grant: grant.id }, "authority-ready-0001")).kind, "new");
    f.context.busy = true; assert.match(f.gate.admit(await f.frame("command", "check", { grant: grant.id }, "authority-busy-00001")).reason!, /busy/);
    f.context.busy = false;
    const old = f.context.revision; f.context.revision = "d".repeat(64);
    assert.match(f.gate.admit(await f.frame("command", "check", { grant: grant.id }, "authority-stale-0001", "", old)).reason!, /source changed/);
  } finally { f.close(); }
});

test("job control is grant-bound; Debug needs a paused owned job and Stop can cancel only that job", async () => {
  const f = await fixture();
  try {
    const grant = await f.grant(["check", "build", "run", "debug"]);
    const job: RuntimeOwnedJob = { id: "owned-debug-job-001", grant: grant.id, revision: f.context.revision, operation: "debug", state: "paused" };
    f.jobs.set(job.id, job); f.jobs.set("ordinary-local-job-01", { ...job, id: "ordinary-local-job-01", grant: "ordinary-user-operation", operation: "run" });
    assert.equal(f.gate.admit(await f.frame("command", "step", { grant: grant.id }, "authority-step-00001", job.id)).kind, "new");
    assert.equal(f.gate.admit(await f.frame("command", "stop", { grant: grant.id }, "authority-local-0001", "ordinary-local-job-01")).kind, "denied");
    job.state = "working"; assert.match(f.gate.admit(await f.frame("command", "continue", { grant: grant.id }, "authority-step-00002", job.id)).reason!, /paused/);
    f.context.revision = "d".repeat(64);
    assert.equal(f.gate.admit(await f.frame("command", "stop", { grant: grant.id }, "authority-stop-00001", job.id, job.revision)).kind, "new");
    f.context.foreground = false; f.gate.tick(); assert.deepEqual(f.revoked, [grant.id]);
    assert.equal(f.jobs.get("ordinary-local-job-01")?.grant, "ordinary-user-operation");
  } finally { f.close(); }
});

test("regrant changes the capability and reused request IDs cannot change their operations", async () => {
  const f = await fixture();
  try {
    const first = await f.grant(["check", "run"]);
    const before = await f.frame("command", "check", { grant: first.id }, "authority-sameid-001"); assert.equal(f.gate.admit(before).kind, "new");
    assert.match(f.gate.admit(await f.frame("command", "run", { grant: first.id }, "authority-sameid-001")).reason!, /reused/);
    const second = await f.grant(["check"]); assert.notEqual(first.id, second.id);
    assert.equal(f.gate.admit(before).kind, "denied"); assert.deepEqual(f.revoked, [first.id]);
    const req = await f.request(["check"], "authority-permission-002");
    assert.throws(() => f.gate.allow(f.controller.fingerprint, req.header[5], ["run"]), /explicit requested/);
    const changed = await f.frame("permission-request", "grant", { name: "Claude · MCP", operations: ["run"] }, req.header[5]);
    assert.throws(() => f.gate.receiveRequest(changed), /changed its requested/);
  } finally { f.close(); }
});
