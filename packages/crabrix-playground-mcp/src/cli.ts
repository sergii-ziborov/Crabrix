#!/usr/bin/env node
import { serveStdio } from "@modelcontextprotocol/server/stdio";
import { makeServer } from "./server";
import { PlaygroundRoom } from "./room";

if (process.argv.includes("--help")) {
  const color = process.stdout.isTTY ? { crab: "\x1b[38;2;255;95;65m", cyan: "\x1b[38;2;77;216;235m", off: "\x1b[0m" } : { crab: "", cyan: "", off: "" };
  process.stdout.write(`${color.crab}🦀 Crabrix Playground MCP${color.off} · 0.1.1\n${color.cyan}Claude on your computer. Your code on your phone.${color.off}\n\nRun without arguments as an MCP stdio server.\nSetup: https://crabrix.com/playground/mcp/\nNode.js 22 or newer. No account. One-hour rooms by default.\nSource edits and selections only; Run/Debug stays in Crabrix or your browser.\n`);
} else if (process.argv.includes("--version")) {
  process.stdout.write("0.1.1\n");
} else if (process.argv.length > 2) {
  process.stderr.write("Crabrix MCP: use --help or start without arguments.\n"); process.exitCode = 1;
} else {
  const room = new PlaygroundRoom();
  const handle = serveStdio(() => makeServer(room), { onerror: () => { process.stderr.write("Crabrix MCP protocol error. No source or private link was logged.\n"); } });
  let closing = false;
  const close = async () => { if (closing) return; closing = true; room.dispose(); await handle.close(); };
  process.stdin.once("end", () => { void close(); });
  process.once("SIGINT", () => { void close(); });
  process.once("SIGTERM", () => { void close(); });
}
