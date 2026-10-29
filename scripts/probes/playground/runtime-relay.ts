// Loopback-only fixture around the production encrypted room store. No compiler,
// source decryption, account database or persisted files are used by this server.
import { createServer } from "node:http";
import { PlaygroundRooms } from "../../../site/lib/playground-rooms";

const rooms = new PlaygroundRooms();
const server = createServer(async (request, response) => {
  try {
    const url = new URL(request.url!, "http://127.0.0.1:3398");
    const id = url.pathname.split("/")[4], access = (request.headers.authorization ?? "").slice(7);
    response.setHeader("Cache-Control", "no-store");
    if (url.pathname === "/health") { response.end("runtime-relay-ready"); return; }
    if (!url.pathname.startsWith("/api/playground/rooms/")) { response.statusCode = 404; response.end(); return; }
    if (url.pathname.endsWith("/events/")) {
      response.setHeader("Content-Type", "text/event-stream");
      const send = (kind: string, data: unknown) => response.write(`event: ${kind}\ndata: ${JSON.stringify(data)}\n\n`);
      const state = rooms.state(id, access);
      const release = rooms.subscribe(id, access, url.searchParams.get("peer")!, event => typeof event === "string" ? (send(event, {}), response.end()) : send("kind" in event ? "presence" : "update", event));
      request.on("close", release); send("state", state); return;
    }
    response.setHeader("Content-Type", "application/json");
    if (request.method === "DELETE") { rooms.close(id, access); response.statusCode = 204; response.end(); return; }
    if (request.method === "GET") { response.end(JSON.stringify(rooms.state(id, access))); return; }
    let size = 0; const chunks: Buffer[] = [];
    for await (const chunk of request) { size += chunk.length; if (size > 500_000) throw new Error("Fixture body budget exceeded"); chunks.push(chunk); }
    const body = JSON.parse(Buffer.concat(chunks).toString("utf8"));
    if (url.pathname === "/api/playground/rooms/") { response.end(JSON.stringify(rooms.create(body.snapshot, body.lifetimeSeconds))); return; }
    if (body.type === "presence") { rooms.publishPresence(id, access, body.peer, body.packet); response.statusCode = 204; response.end(); return; }
    if (body.type === "snapshot") { response.end(JSON.stringify(rooms.compact(id, access, body.sequence, body.packet))); return; }
    response.end(JSON.stringify(rooms.append(id, access, body.peer, body.messageID, body.packet, body.expectedSequence)));
  } catch (error) {
    response.statusCode = typeof (error as { status?: unknown }).status === "number" ? (error as { status: number }).status : 500;
    response.end(JSON.stringify({ error: error instanceof Error ? error.message : "Fixture failed" }));
  }
});
server.listen(3398, "127.0.0.1", () => process.stdout.write("runtime-relay-ready\n"));
process.on("SIGTERM", () => { server.closeAllConnections(); server.close(() => process.exit(0)); });
