import { test } from "node:test";
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { createPresence, localPresence, receivePresence, remoteSelections, publishRuntimePresence, remoteRuntimePresence } from "../../../site/lib/playground-presence";
import { PlaygroundRooms } from "../../../site/lib/playground-rooms";
import { PlaygroundSession } from "../../../site/lib/playground-session";
import { Y, yDocument, documentFromY } from "../../../site/lib/playground-collab";
import { newPlaygroundDocument } from "../../../site/lib/playground-document";
import { encryptPlayground, newEncryptionSecret } from "../../../site/lib/playground-crypto";
import { createRuntimeSigner, verifyRuntimeEnvelope } from "../../../site/lib/playground-runtime-protocol";
import { runtimeSourceRevision } from "../../../site/lib/playground-runtime-source";

async function until(predicate: () => boolean) { const end = Date.now() + 10_000; while (!predicate()) { if (Date.now() >= end) throw new Error("Timed out waiting for the encrypted room"); await new Promise(r => setTimeout(r, 20)); } }

test("runtime envelopes preserve Unicode selections and never enter source snapshots", async () => {
  const source = newPlaygroundDocument(); source.files["main.rs"] = 'fn main(){println!("🦀");}\n';
  const doc = yDocument(source), other = new Y.Doc(), a = createPresence(doc, "MCP"), b = createPresence(other, "Human");
  const signer = await createRuntimeSigner();
  try {
    Y.applyUpdate(other, Y.encodeStateAsUpdate(doc));
    const text = doc.getMap<Y.Text>("files").get("main.rs")!, offset = text.toString().indexOf("🦀");
    a.setLocalStateField("cursor", { anchor: Y.createRelativePositionFromTypeIndex(text, offset), head: Y.createRelativePositionFromTypeIndex(text, offset + 2) });
    const before = Y.encodeStateAsUpdate(doc), revision = await runtimeSourceRevision(documentFromY(doc));
    const envelope = await signer.sign({ kind: "capabilities", room: "a".repeat(24), target: "", requestID: "presence-request-001", operation: "discover", revision }, { name: "MCP", permissions: "off" });
    publishRuntimePresence(a, envelope); assert(localPresence(a).length <= 4000);
    receivePresence(b, localPresence(a), "test");
    const frames = remoteRuntimePresence(b); assert.equal(frames.length, 1);
    const frame = await verifyRuntimeEnvelope(JSON.parse(frames[0].envelope), { room: "a".repeat(24) });
    assert.deepEqual(frame.payload, { name: "MCP", permissions: "off" });
    assert(remoteSelections(other, b).some(s => s.anchor === offset && s.head === offset + 2));
    assert.deepEqual(Y.encodeStateAsUpdate(doc), before); assert.equal(await runtimeSourceRevision(documentFromY(doc)), revision);
    publishRuntimePresence(a, envelope); receivePresence(b, localPresence(a), "retry");
    const retry = remoteRuntimePresence(b)[0];
    assert.equal(retry.envelope, frames[0].envelope); assert(retry.clock > frames[0].clock, "Retransmission must remain observable so a lost acknowledgement can be resent without re-execution");
    publishRuntimePresence(a, null); receivePresence(b, localPresence(a), "test"); assert.deepEqual(remoteRuntimePresence(b), []);
    assert(remoteSelections(other, b).some(s => s.anchor === offset && s.head === offset + 2));
  } finally { signer.destroy(); a.destroy(); b.destroy(); doc.destroy(); other.destroy(); }
});

test("presence budget failure leaves the existing selection and runtime envelope unchanged", async () => {
  const doc = yDocument(newPlaygroundDocument()), awareness = createPresence(doc, "Human"), signer = await createRuntimeSigner();
  try {
    const text = doc.getMap<Y.Text>("files").get("main.rs")!;
    const cursor = { anchor: Y.createRelativePositionFromTypeIndex(text, 0), head: Y.createRelativePositionFromTypeIndex(text, 3) };
    awareness.setLocalStateField("cursor", cursor);
    const envelope = await signer.sign({ kind: "capabilities", room: "a".repeat(24), target: "", requestID: "presence-request-001", operation: "discover" }, {});
    publishRuntimePresence(awareness, envelope);
    const state = awareness.getLocalState();
    assert.throws(() => publishRuntimePresence(awareness, { ...envelope, payload: "A".repeat(2400) }), /budget/);
    assert.strictEqual(awareness.getLocalState(), state);
    awareness.setLocalStateField("futureExtension", "a".repeat(3500));
    const large = awareness.getLocalState();
    assert.throws(() => publishRuntimePresence(awareness, envelope), /selection.*budget/);
    assert.strictEqual(awareness.getLocalState(), large); assert.deepEqual(awareness.getLocalState()!.cursor, cursor);
  } finally { signer.destroy(); awareness.destroy(); doc.destroy(); }
});

test("a forged local awareness ID cannot overwrite this client's cursor or runtime identity", () => {
  const doc = yDocument(newPlaygroundDocument()), local = createPresence(doc, "Real host"), attackerDoc = new Y.Doc();
  attackerDoc.clientID = doc.clientID;
  const attacker = createPresence(attackerDoc, "Attacker");
  try {
    const text = doc.getMap<Y.Text>("files").get("main.rs")!;
    local.setLocalStateField("cursor", { anchor: Y.createRelativePositionFromTypeIndex(text, 0), head: Y.createRelativePositionFromTypeIndex(text, 3) });
    const before = local.getLocalState(), serialized = JSON.stringify(before);
    attacker.setLocalState({ user: { name: "spoofed\u0000", color: "invalid" }, cursor: { anchor: null, head: null }, runtime: { forged: true } });
    attacker.meta.get(doc.clientID)!.clock = 1_000_000;
    assert.doesNotThrow(() => receivePresence(local, localPresence(attacker), "untrusted peer"));
    assert.strictEqual(local.getLocalState(), before); assert.equal(JSON.stringify(local.getLocalState()), serialized);
    assert(remoteSelections(doc, local, true).some(s => s.anchor === 0 && s.head === 3));
  } finally { local.destroy(); attacker.destroy(); doc.destroy(); attackerDoc.destroy(); }
});

test("an invalid Unicode peer name is refused before it can poison native result decoding", () => {
  const doc = yDocument(newPlaygroundDocument()), local = createPresence(doc, "Real host"), attackerDoc = new Y.Doc(), attacker = createPresence(attackerDoc, "Attacker");
  try {
    const before = structuredClone([...local.getStates()]);
    attacker.setLocalState({ user: { name: "bad\ud800", color: "#2876bd" }, cursor: null });
    assert.throws(() => receivePresence(local, localPresence(attacker), "untrusted peer"), /identity/);
    assert.deepEqual([...local.getStates()], before);
  } finally { local.destroy(); attacker.destroy(); doc.destroy(); attackerDoc.destroy(); }
});

test("actual relay edit acknowledgement rejects a mode-tampered viewer and carries only encrypted presence", async () => {
  const rooms = new PlaygroundRooms(); let sawPlaintext = false;
  const server = createServer(async (req, res) => {
    try {
      const url = new URL(req.url!, "http://local"), id = url.pathname.split("/")[4], access = (req.headers.authorization ?? "").slice(7);
      if (url.pathname.endsWith("/events/")) {
        res.setHeader("Content-Type", "text/event-stream");
        const send = (type: string, data: unknown) => res.write(`event: ${type}\ndata: ${JSON.stringify(data)}\n\n`);
        const release = rooms.subscribe(id, access, url.searchParams.get("peer")!, e => typeof e === "string" ? (send(e, {}), res.end()) : send("kind" in e ? "presence" : "update", e));
        req.on("close", release); send("state", rooms.state(id, access)); return;
      }
      const chunks: Buffer[] = []; for await (const chunk of req) chunks.push(chunk);
      const raw = Buffer.concat(chunks).toString(); if (raw.includes("crabrix-runtime-v1") || raw.includes("private-runtime-sentinel")) sawPlaintext = true;
      const body = JSON.parse(raw); res.setHeader("Content-Type", "application/json");
      if (body.type === "presence") { rooms.publishPresence(id, access, body.peer, body.packet); res.statusCode = 204; res.end(); return; }
      if (body.type === "snapshot") { res.end(JSON.stringify(rooms.compact(id, access, body.sequence, body.packet))); return; }
      res.end(JSON.stringify(rooms.append(id, access, body.peer, body.messageID, body.packet)));
    } catch (error: any) { res.statusCode = error.status ?? 500; res.end(JSON.stringify({ error: error.message })); }
  });
  await new Promise<void>(resolve => server.listen(0, "127.0.0.1", resolve));
  const origin = `http://127.0.0.1:${(server.address() as any).port}`, source = yDocument(newPlaygroundDocument()), key = newEncryptionSecret();
  const created = rooms.create(await encryptPlayground(key, Y.encodeStateAsUpdate(source)), 3600);
  const doc = new Y.Doc(), viewDoc = new Y.Doc(), awareness = createPresence(doc, "Host"), viewer = createPresence(viewDoc, "Viewer");
  const link = { id: created.id, key, access: created.edit, expiresAt: created.expiresAt, mode: "edit" as const };
  const edit = new PlaygroundSession(doc, link, () => {}, () => {}, awareness, origin);
  const fake = new PlaygroundSession(viewDoc, { ...link, access: created.view }, () => {}, () => {}, viewer, origin);
  const signer = await createRuntimeSigner(); let resets = 0; edit.onRuntimeReset = () => resets++;
  try {
    assert.equal(edit.runtimeEditConfirmed, false); await assert.rejects(edit.confirmRuntimeEditAccess(), /connected editable/);
    void edit.start(); void fake.start(); await until(() => edit.receivedState && fake.receivedState);
    const revision = await runtimeSourceRevision(documentFromY(doc));
    await edit.confirmRuntimeEditAccess(); assert.equal(edit.runtimeEditConfirmed, true);
    await until(() => edit.sequence === 1); assert.equal(await runtimeSourceRevision(documentFromY(doc)), revision);
    await edit.confirmRuntimeEditAccess(); assert.equal(rooms.state(link.id, link.access).sequence, 1, "Cached confirmation must not consume another room update");
    await assert.rejects(fake.confirmRuntimeEditAccess(), /did not confirm edit access/); assert.equal(fake.runtimeEditConfirmed, false);
    fake.link.mode = "view"; await assert.rejects(fake.confirmRuntimeEditAccess(), /connected editable/);
    publishRuntimePresence(awareness, await signer.sign({ kind: "capabilities", room: link.id, target: "", requestID: "presence-request-001", operation: "discover", revision }, { name: "private-runtime-sentinel", permissions: "off" }));
    await until(() => remoteRuntimePresence(viewer).length === 1);
    assert.equal(rooms.state(link.id, link.access).sequence, 1, "Presence stays outside source update history");
    assert.equal(await runtimeSourceRevision(documentFromY(viewDoc)), revision); assert.equal(sawPlaintext, false);
    const invalid = await encryptPlayground(key, new Uint8Array([255, 255, 255]));
    rooms.publishPresence(link.id, created.view, fake.peer, invalid);
    await new Promise(r => setTimeout(r, 100));
    assert.equal(edit.connected, true); assert.equal(edit.runtimeEditConfirmed, true, "Malformed presence cannot revoke another controller's connection");
    const lateDoc = new Y.Doc(), lateAwareness = createPresence(lateDoc, "Late guest");
    const late = new PlaygroundSession(lateDoc, link, () => {}, () => {}, lateAwareness, origin);
    try {
      void late.start(); await until(() => late.receivedState);
      assert.equal(await runtimeSourceRevision(documentFromY(lateDoc)), revision, "An invalid presence in initial relay state cannot prevent opening source");
      assert.equal(late.connected, true);
    } finally { late.stop(); lateAwareness.destroy(); lateDoc.destroy(); }
    edit.stop(); assert.equal(edit.runtimeEditConfirmed, false); assert(resets >= 2);
  } finally { signer.destroy(); edit.stop(); fake.stop(); awareness.destroy(); viewer.destroy(); doc.destroy(); viewDoc.destroy(); source.destroy(); server.closeAllConnections(); await new Promise<void>(resolve => server.close(() => resolve())); }
});
