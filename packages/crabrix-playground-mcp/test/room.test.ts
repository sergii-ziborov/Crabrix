import { test } from "node:test";
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { PlaygroundRooms } from "../../../site/lib/playground-rooms";
import { PlaygroundRoom, authorizedLink } from "../src/room";
import { Y, yDocument, documentFromY, updateYDocument } from "../../../site/lib/playground-collab";
import { createPresence, remoteSelections } from "../../../site/lib/playground-presence";
import { PlaygroundSession } from "../../../site/lib/playground-session";
import { newPlaygroundDocument } from "../../../site/lib/playground-document";
import { encryptPlayground, newEncryptionSecret } from "../../../site/lib/playground-crypto";

const sleep = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));
async function wait(check: () => boolean) { const end = Date.now() + 10_000; while (!check()) { if (Date.now() >= end) throw new Error("Timed out"); await sleep(30); } }

test("private links refuse other origins, queries, expired and non-room URLs", () => {
  for (const input of ["https://example.com/", "file:///tmp/source", "https://crabrix.com/playground/", "https://user@crabrix.com/playground/", "http://127.0.0.1:1/"]) assert.throws(() => authorizedLink(input));
});

test("real encrypted relay: edits, conflicting revisions, read-only links, UTF-16 selection and expiry", async () => {
  const rooms = new PlaygroundRooms();
  let forceConflict = false, loseReply = false, plaintextOnRelay = false;
  const server = createServer(async (req, res) => {
    try {
      const url = new URL(req.url!, "http://local"), id = url.pathname.split("/")[4], access = (req.headers.authorization ?? "").slice(7);
      res.setHeader("Content-Type", "application/json");
      if (url.pathname.endsWith("/events/")) {
        const peer = url.searchParams.get("peer")!;
        res.setHeader("Content-Type", "text/event-stream");
        const send = (type: string, data: unknown) => res.write(`event: ${type}\ndata: ${JSON.stringify(data)}\n\n`);
        const release = rooms.subscribe(id, access, peer, e => typeof e === "string" ? (send(e, {}), res.end()) : send("kind" in e ? "presence" : "update", e));
        req.on("close", release); send("state", rooms.state(id, access)); return;
      }
      if (req.method === "GET") { res.end(JSON.stringify(rooms.state(id, access))); return; }
      if (req.method === "DELETE") { rooms.close(id, access); res.statusCode = 204; res.end(); return; }
      const chunks: Buffer[] = []; for await (const b of req) chunks.push(b);
      const raw = Buffer.concat(chunks).toString();
      if (raw.includes("private-sentinel")) plaintextOnRelay = true;
      const body = JSON.parse(raw);
      if (url.pathname === "/api/playground/rooms/") { res.end(JSON.stringify(rooms.create(body.snapshot, body.lifetimeSeconds))); return; }
      if (body.type === "presence") { rooms.publishPresence(id, access, body.peer, body.packet); res.statusCode = 204; res.end(); return; }
      if (body.type === "snapshot") { res.end(JSON.stringify(rooms.compact(id, access, body.sequence, body.packet))); return; }
      if (forceConflict) { forceConflict = false; body.expectedSequence--; }
      const result = rooms.append(id, access, body.peer, body.messageID, body.packet, body.expectedSequence);
      if (loseReply) { loseReply = false; res.destroy(); return; }
      res.end(JSON.stringify(result));
    } catch (e: any) { res.statusCode = e.status ?? 500; res.end(JSON.stringify({ error: e.message })); }
  });
  await new Promise<void>(resolve => server.listen(0, "127.0.0.1", resolve));
  const origin = `http://127.0.0.1:${(server.address() as any).port}`;
  const mcp = new PlaygroundRoom(origin), viewer = new PlaygroundRoom(origin);
  const browserDoc = new Y.Doc(), presence = createPresence(browserDoc, "Browser human");
  let browser: PlaygroundSession | undefined;
  try {
    const created = await mcp.create("Interview", { "main.rs": 'fn main(){println!("private-sentinel 🦀");}\n' });
    assert.equal(created.linkType, "temporary editable Playground");
    const link = authorizedLink(created.link, origin);
    assert.equal(Math.round((link.expiresAt - Date.now()) / 60_000), 60);
    browser = new PlaygroundSession(browserDoc, link, () => {}, () => {}, presence, origin); void browser.start();
    await wait(() => browser!.receivedState);
    let file = await mcp.read("main.rs");
    const next = file.text.replace("private-sentinel", "private-sentinel changed");
    await mcp.apply(file.revision, [{ path: "main.rs", text: next }]);
    await wait(() => documentFromY(browserDoc).files["main.rs"] === next);
    await assert.rejects(() => mcp.apply(file.revision, [{ path: "main.rs", text: "wrong" }]), /Revision conflict/);
    assert.equal((await mcp.read("main.rs")).text, next);
    file = await mcp.read("main.rs");
    forceConflict = true;
    await assert.rejects(() => mcp.apply(file.revision, [{ path: "main.rs", text: "must not apply" }]), /conflict/);
    assert.equal((await mcp.read("main.rs")).text, next);
    loseReply = true;
    await mcp.apply(file.revision, [{ path: "main.rs", text: next + "// acknowledged once\n" }]);
    assert.equal(rooms.state(link.id, link.access).sequence, 2);
    file = await mcp.read("main.rs");
    const crab = file.text.indexOf("🦀");
    await mcp.select("main.rs", crab, crab + 2, file.revision);
    await wait(() => remoteSelections(browserDoc, presence).some(s => s.name === "Claude · MCP" && s.anchor === crab && s.head === crab + 2));
    await assert.rejects(() => mcp.select("main.rs", crab + 1, crab + 2, file.revision), /surrogate/);
    const value = { ...documentFromY(browserDoc), files: { "main.rs": file.text + "// human edit\n" } };
    updateYDocument(browserDoc, value);
    await wait(() => rooms.state(link.id, link.access).sequence === 3);
    assert.match((await mcp.read("main.rs")).text, /human edit/);
    await assert.rejects(async () => mcp.apply((await mcp.read("main.rs")).revision, [{ path: "../evil.rs", text: "" }]), /path/);
    const nonOwner = new PlaygroundRoom(origin);
    await nonOwner.connect(created.link);
    await assert.rejects(() => nonOwner.endRoom(), /only a room it created/);
    nonOwner.disconnect();
    await mcp.endRoom();
    assert.throws(() => rooms.state(link.id, link.access), /expired/);
    // Obtain the test room's independently generated view capability without
    // ever returning an owner token from the MCP API.
    const key = newEncryptionSecret(), seeded = yDocument(newPlaygroundDocument());
    const second = rooms.create(await encryptPlayground(key, Y.encodeStateAsUpdate(seeded)), 60); seeded.destroy();
    const viewURL = origin + "/playground/room/" + second.id + "/#" + new URLSearchParams({ key, access: second.view, expires: String(second.expiresAt), mode: "view" });
    await viewer.connect(viewURL);
    await assert.rejects(async () => viewer.apply((await viewer.read("main.rs")).revision, [{ path: "main.rs", text: "no" }]), /view-only/);
    rooms.now = () => second.expiresAt + 1; rooms.prune();
    await assert.rejects(() => viewer.read("main.rs"), /expired|Connect/);
    assert.equal(plaintextOnRelay, false);
  } finally {
    mcp.disconnect(); viewer.disconnect(); browser?.stop(); presence.destroy(); browserDoc.destroy();
    server.closeAllConnections(); await new Promise<void>(resolve => server.close(() => resolve()));
  }
});
