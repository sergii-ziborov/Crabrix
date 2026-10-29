import { test } from "node:test";
import assert from "node:assert/strict";
import { createRuntimeSigner, verifyRuntimeEnvelope, RuntimeReplayWindow, RUNTIME_LIMITS, type RuntimeEnvelope, type RuntimeFields } from "../../../site/lib/playground-runtime-protocol";
import { newEncryptionSecret } from "../../../site/lib/playground-crypto";

const now = 1_000_000;
const room = "a".repeat(24), target = "b".repeat(64), revision = "c".repeat(64);
const fields: RuntimeFields = { kind: "command", room, target, requestID: "runtime-request-0001", operation: "check", revision };
const copy = (value: RuntimeEnvelope) => JSON.parse(JSON.stringify(value));

test("P-256 raw signatures and edit-capability MAC authenticate owned Unicode data", async () => {
  const signer = await createRuntimeSigner(), capability = newEncryptionSecret();
  const envelope = await signer.sign(fields, { text: "🦀 Привет", file: 0 }, { now, editCapability: capability });
  assert.equal(Buffer.from(envelope.key, "base64url").length, 65);
  assert.equal(Buffer.from(envelope.signature, "base64url").length, 64);
  assert.equal(Buffer.from(envelope.editProof!, "base64url").length, 32);
  const frame = await verifyRuntimeEnvelope(envelope, { room, target, sender: signer.fingerprint, editCapability: capability, requireEditProof: true, clock: () => now });
  assert.equal(frame.sender, signer.fingerprint);
  assert.equal(frame.editAccessProved, true);
  assert.deepEqual(frame.payload, { text: "🦀 Привет", file: 0 });
  assert(Object.isFrozen(frame)); assert(Object.isFrozen(frame.header)); assert(Object.isFrozen(frame.payload));
  const noProof = await signer.sign(fields, {}, { now });
  assert.equal((await verifyRuntimeEnvelope(noProof, { room, clock: () => now })).editAccessProved, false);
  signer.destroy();
});

test("wrong room, target, key, payload, header, MAC and unknown fields are refused", async () => {
  const signer = await createRuntimeSigner(), capability = newEncryptionSecret();
  const good = await signer.sign(fields, { message: "actual data" }, { now, editCapability: capability });
  const context = { room, target, editCapability: capability, requireEditProof: true, clock: () => now };
  await assert.rejects(verifyRuntimeEnvelope(good, { ...context, room: "d".repeat(24) }), /match/);
  await assert.rejects(verifyRuntimeEnvelope(good, { ...context, target: "d".repeat(64) }), /match/);
  await assert.rejects(verifyRuntimeEnvelope(good, { ...context, editCapability: newEncryptionSecret() }), /edit access/);
  const noProof = { ...good }; delete (noProof as { editProof?: string }).editProof;
  await assert.rejects(verifyRuntimeEnvelope(noProof, context), /edit access/);
  const other = await createRuntimeSigner();
  const badKey = copy(good); badKey.key = other.key;
  await assert.rejects(verifyRuntimeEnvelope(badKey, context), /identity/);
  const badPayload = copy(good); badPayload.payload = Buffer.from('{"message":"changed"}').toString("base64url");
  await assert.rejects(verifyRuntimeEnvelope(badPayload, context), /digest/);
  const badHeader = copy(good); badHeader.header[6] = "run";
  await assert.rejects(verifyRuntimeEnvelope(badHeader, context), /signature/);
  await assert.rejects(verifyRuntimeEnvelope({ ...good, arbitrary: true }, context), /fields/);
  await assert.rejects(verifyRuntimeEnvelope({ ...good, key: 123 }, context), /fields/);
  signer.destroy(); other.destroy();
});

test("mutation during asynchronous verification cannot change the authenticated command", async () => {
  const signer = await createRuntimeSigner();
  const input = copy(await signer.sign(fields, { nested: { approved: false } }, { now }));
  const pending = verifyRuntimeEnvelope(input, { room, target, clock: () => now });
  input.header[6] = "run"; input.payload = Buffer.from('{}').toString("base64url");
  const result = await pending;
  assert.equal(result.header[6], "check");
  assert.deepEqual(result.payload, { nested: { approved: false } });
  assert.throws(() => { (result.payload as any).nested.approved = true; }, TypeError);
  signer.destroy();
});

test("mutable verification options cannot remove the edit proof requirement during crypto", async () => {
  const signer = await createRuntimeSigner();
  const noProof = await signer.sign(fields, {}, { now });
  const context = { room, target, requireEditProof: true, editCapability: newEncryptionSecret(), clock: () => now };
  const pending = verifyRuntimeEnvelope(noProof, context);
  context.requireEditProof = false;
  await assert.rejects(pending, /edit access/);
  const capability = newEncryptionSecret();
  const options = { now, editCapability: capability };
  const signing = signer.sign(fields, {}, options);
  options.editCapability = newEncryptionSecret();
  await verifyRuntimeEnvelope(await signing, { room, target, requireEditProof: true, editCapability: capability, clock: () => now });
  signer.destroy();
});

test("time windows are rechecked after crypto work and bounded before signing", async () => {
  const signer = await createRuntimeSigner();
  const short = await signer.sign(fields, {}, { now, lifetimeMs: 100 });
  await assert.rejects(verifyRuntimeEnvelope(short, { room, clock: () => now + 100 }), /expired/);
  await assert.rejects(verifyRuntimeEnvelope(short, { room, clock: () => now + 101 }), /expired/);
  let calls = 0;
  await assert.rejects(verifyRuntimeEnvelope(short, { room, clock: () => calls++ === 0 ? now : now + 101 }), /expired/);
  const future = await signer.sign(fields, {}, { now: now + 6000 });
  await assert.rejects(verifyRuntimeEnvelope(future, { room, clock: () => now }), /clocks/);
  await assert.rejects(signer.sign(fields, {}, { now, lifetimeMs: RUNTIME_LIMITS.lifetimeMs + 1 }), /header/);
  signer.destroy();
});

test("retransmission is identifiable without treating deserialized input as verified", async () => {
  const signer = await createRuntimeSigner(), replay = new RuntimeReplayWindow();
  const frame = await verifyRuntimeEnvelope(await signer.sign(fields, {}, { now }), { room, clock: () => now });
  assert.equal(replay.consume(frame, now), "new"); assert.equal(replay.consume(frame, now), "duplicate");
  assert.throws(() => replay.consume(JSON.parse(JSON.stringify(frame)), now), /not been authenticated/);
  assert.throws(() => replay.consume(frame, now + RUNTIME_LIMITS.lifetimeMs + 1), /expired/);
  signer.destroy();
});

test("oversized payloads and closed or in-flight destroyed signers fail explicitly", async () => {
  const signer = await createRuntimeSigner();
  await assert.rejects(signer.sign(fields, { text: "🦀".repeat(768) }, { now }), /page budget/);
  const pending = signer.sign(fields, {}, { now }); signer.destroy();
  await assert.rejects(pending, /closed/);
  await assert.rejects(signer.sign(fields, {}, { now }), /closed/);
});

test("payload strings and keys must have portable Unicode before signing", async () => {
  const signer = await createRuntimeSigner();
  try {
    await assert.rejects(signer.sign(fields, { name: "bad\ud800" }, { now }), /payload Unicode/);
    await assert.rejects(signer.sign(fields, { ["bad\udfff"]: true }, { now }), /payload Unicode/);
  } finally { signer.destroy(); }
});

test("flooding cannot evict an unexpired nonce and re-enable an earlier request", async () => {
  const signer = await createRuntimeSigner(), replay = new RuntimeReplayWindow();
  const frames = [];
  for (let i = 0; i <= RUNTIME_LIMITS.replayEntries; i++) {
    const frame = await verifyRuntimeEnvelope(await signer.sign({ ...fields, requestID: "replay-request-" + String(i).padStart(4, "0") }, {}, { now }), { room, clock: () => now });
    if (i < RUNTIME_LIMITS.replayEntries) assert.equal(replay.consume(frame, now), "new");
    else assert.throws(() => replay.consume(frame, now), /window is full/);
    if (i === 0) frames.push(frame);
  }
  assert.equal(replay.consume(frames[0], now), "duplicate");
  const later = now + RUNTIME_LIMITS.lifetimeMs + 1;
  const next = await verifyRuntimeEnvelope(await signer.sign(fields, {}, { now: later }), { room, clock: () => later });
  assert.equal(replay.consume(next, later), "new");
  signer.destroy();
});
