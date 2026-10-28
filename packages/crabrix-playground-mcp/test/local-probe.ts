// Qualification-only entry. Not in the downloadable files or production CLI.
import { serveStdio } from "@modelcontextprotocol/server/stdio";
import { makeServer } from "../src/server";
import { PlaygroundRoom } from "../src/room";
const room = new PlaygroundRoom("http://127.0.0.1:3224");
const transport = serveStdio(() => makeServer(room));
process.stdin.once("end", () => { room.dispose(); void transport.close(); });
process.once("SIGTERM", () => { room.dispose(); void transport.close(); });
