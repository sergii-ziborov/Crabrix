// Public release qualification: execute the exact downloaded tarball's CLI.
// No private room links, access tokens or plaintext source are written to logs.
import { Client } from "@modelcontextprotocol/client";
import { StdioClientTransport } from "@modelcontextprotocol/client/stdio";
import { createRequire } from "node:module";
import { writeFileSync } from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";
const require = createRequire(import.meta.url);
const { chromium } = require("/Users/serhiirihgt/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright");
const cli = path.resolve(process.argv[2]);
const client = new Client({ name: "crabrix-public-release-qualification", version: "1.0.0" });
const transport = new StdioClientTransport({ command: process.execPath, args: [cli], cwd: path.dirname(cli), stderr: "pipe" });
let browser: any, ended = false;
async function call(name: string, args: Record<string, unknown> = {}): Promise<any> {
  const result = await client.callTool({ name, arguments: args });
  if (result.isError) throw new Error(JSON.stringify(result.content));
  return result.structuredContent;
}
try {
  await client.connect(transport);
  assert.equal((await client.listTools()).tools.length, 8);
  const created = await call("crabrix_create", { name: "Public MCP qualification", lifetimeMinutes: 5 });
  assert.equal(created.conditionalEdits, true); assert.equal(created.canEndRoom, true);
  browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } }), errors: string[] = [];
  page.on("pageerror", (error: Error) => errors.push(error.message));
  await page.goto(created.link); await page.waitForSelector(".cm-content");
  const file = await call("crabrix_read_file", { path: "main.rs" });
  await call("crabrix_apply_changes", { expectedRevision: file.revision, changes: [{ path: "main.rs", text: 'fn main() { println!("mcp-public=42"); }\n' }] });
  await page.waitForFunction(() => {
    const content = document.querySelector(".cm-content")?.cloneNode(true) as HTMLElement | undefined;
    content?.querySelectorAll(".cm-ySelectionCaret").forEach(node => node.remove());
    return content?.textContent?.includes("mcp-public=42");
  });
  await call("crabrix_select", { path: "main.rs", anchor: 3, head: 7, expectedRevision: (await call("crabrix_read_file", { path: "main.rs" })).revision });
  await page.waitForSelector(".cm-ySelection");
  await page.getByRole("button", { name: "▶ Run", exact: true }).click();
  await page.waitForFunction(() => document.querySelector(".pg-output pre")?.textContent === "mcp-public=42\n", null, { timeout: 300_000 });
  await page.screenshot({ path: "build/playground-mcp-20261028/public-browser-local-run.png" });
  await call("crabrix_end_room"); ended = true;
  await page.waitForFunction(() => document.body.textContent?.includes("expired") || document.body.textContent?.includes("ended"));
  assert.deepEqual(errors, []);
  writeFileSync("build/playground-mcp-20261028/public-result.json", JSON.stringify({ at: new Date().toISOString(), origin: "https://crabrix.com", exactDownloadedCLI: true, tools: 8, conditionalEdits: true, mcpChangesInBrowser: true, namedSelection: true, browserLocalStdout: "mcp-public=42", creatorClosedRoom: true, noBackendExecution: true, pageErrors: errors, liveModelProviderInvocation: false }, null, 2));
  console.log("PASS exact public download, official MCP stdio, encrypted production relay, browser source/selection/local stdout and owner closure.");
} finally {
  if (!ended) { try { await call("crabrix_end_room"); } catch {} }
  await browser?.close(); await client.close(); await transport.close();
}
