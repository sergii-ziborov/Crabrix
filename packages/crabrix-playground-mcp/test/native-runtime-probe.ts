// Explicit integration probe, not part of the fast test runner. The native
// processes use the application's actual URLSession/JavaScriptCore/CryptoKit.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createInterface } from "node:readline";
import path from "node:path";
import { Y, yDocument, documentFromY } from "../../../site/lib/playground-collab";
import { newPlaygroundDocument } from "../../../site/lib/playground-document";
import { encryptPlayground, newEncryptionSecret } from "../../../site/lib/playground-crypto";
import { createPresence, publishRuntimePresence, remoteSelections } from "../../../site/lib/playground-presence";
import { PlaygroundSession } from "../../../site/lib/playground-session";
import { createRuntimeSigner, verifyRuntimeEnvelope } from "../../../site/lib/playground-runtime-protocol";
import { runtimeSourceRevision } from "../../../site/lib/playground-runtime-source";

const root = path.resolve(process.env.CRABRIX_REPOSITORY_ROOT ?? process.cwd()), origin = "http://127.0.0.1:3398";
async function until(predicate: () => boolean, label: string) {
  const limit = Date.now() + 20_000;
  while (!predicate()) { if (Date.now() > limit) throw new Error("Native runtime probe timed out: " + label); await new Promise(resolve => setTimeout(resolve, 30)); }
}
function native() {
  const child = spawn(path.join(root, "build/playground-crossclient/native-peer"), [path.join(root, "Crabrix/Resources/PlaygroundCodec.js"), origin], { stdio: ["pipe", "pipe", "pipe"] });
  const events: Record<string, any>[] = []; let failed = false;
  const reader = createInterface({ input: child.stdout });
  reader.on("line", line => { if (line.length <= 20_000) events.push(JSON.parse(line)); });
  child.on("error", () => { failed = true; }); child.stderr.resume();
  function send(value: Record<string, unknown>) { child.stdin.write(JSON.stringify(value) + "\n"); }
  async function next(event: string) {
    await until(() => failed || events.some(value => value.event === event), event);
    assert.equal(failed, false, "Native process failed");
    return events.splice(events.findIndex(value => value.event === event), 1)[0];
  }
  async function stop() {
    send({ type: "exit" }); child.stdin.end();
    await Promise.race([new Promise(resolve => child.once("exit", resolve)), new Promise(resolve => setTimeout(resolve, 2000))]);
    if (child.exitCode === null) child.kill("SIGTERM"); reader.close();
  }
  return { events, send, next, stop };
}

const source = newPlaygroundDocument(); source.files["main.rs"] = 'fn main(){println!("private-runtime-sentinel 🦀");}\n';
const original = yDocument(source), key = newEncryptionSecret(), doc = new Y.Doc(), awareness = createPresence(doc, "Node runtime probe");
let session: PlaygroundSession | undefined, room: any;
const peers: ReturnType<typeof native>[] = [];
const signer = await createRuntimeSigner();
try {
  const snapshot = await encryptPlayground(key, Y.encodeStateAsUpdate(original));
  const response = await fetch(origin + "/api/playground/rooms/", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ snapshot, lifetimeSeconds: 120 }) });
  assert(response.ok); room = await response.json();
  const link = { id: room.id, key, access: room.edit, expiresAt: room.expiresAt, mode: "edit" as const };
  session = new PlaygroundSession(doc, link, () => {}, () => {}, awareness, origin); void session.start();
  await until(() => session!.receivedState, "Node encrypted source");
  const owner = native(), viewer = native(); peers.push(owner, viewer);
  owner.send({ type: "join", link }); viewer.send({ type: "join", link: { ...link, access: room.view } });
  for (const peer of peers) {
    await peer.next("ready");
    await until(() => peer.events.some(value => value.event === "status" && value.status.startsWith("Connected")), "native connection");
  }
  const revision = await runtimeSourceRevision(documentFromY(doc));
  owner.send({ type: "runtime-source" }); assert.equal((await owner.next("runtime-source")).revision, revision);
  owner.send({ type: "confirm-runtime" }); assert.equal((await owner.next("runtime-role")).confirmed, true);
  viewer.send({ type: "confirm-runtime" }); assert.match((await viewer.next("error")).error, /not authorized/i);
  assert(!viewer.events.some(value => value.event === "runtime-role" && value.confirmed), "View-mode tampering must never confirm edit access");
  owner.send({ type: "runtime-source" }); assert.equal((await owner.next("runtime-source")).revision, revision);
  const envelope = await signer.sign({ kind: "capabilities", room: room.id, target: "", requestID: "native-transport-probe-01", operation: "discover", revision }, { role: "controller", name: "Node runtime probe" }, { editCapability: room.edit });
  publishRuntimePresence(awareness, envelope);
  await until(() => owner.events.some(value => value.event === "runtime-frames" && value.frames.length), "Node signature into native transport");
  const entry = owner.events.find(value => value.event === "runtime-frames" && value.frames.length)!.frames[0];
  const verified = await verifyRuntimeEnvelope(JSON.parse(entry.envelope), { room: room.id, editCapability: room.edit, requireEditProof: true });
  assert.equal(verified.sender, signer.fingerprint);
  const anchor = source.files["main.rs"].indexOf("🦀");
  owner.send({ type: "selection", file: "main.rs", anchor, length: 2 });
  await until(() => remoteSelections(doc, awareness).some(selection => selection.anchor === anchor && selection.head === anchor + 2), "native Unicode selection");
  owner.send({ type: "runtime-source" }); assert.equal((await owner.next("runtime-source")).revision, revision);
  assert.equal(await runtimeSourceRevision(documentFromY(doc)), revision);
  process.stdout.write("PASS actual native URLSession edit-role acknowledgement, refused view tampering, signed transient transport, canonical source and Unicode selection; no execution or UI claim\n");
} finally {
  await Promise.all(peers.map(peer => peer.stop()));
  session?.stop(); signer.destroy(); awareness.destroy(); doc.destroy(); original.destroy();
  if (room) await fetch(origin + "/api/playground/rooms/" + room.id + "/", { method: "DELETE", headers: { authorization: "Bearer " + room.owner } });
}
