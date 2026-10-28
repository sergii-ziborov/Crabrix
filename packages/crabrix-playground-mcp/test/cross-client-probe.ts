import { Client } from "@modelcontextprotocol/client";
import { StdioClientTransport } from "@modelcontextprotocol/client/stdio";
import { createServer } from "node:http";
import { mkdirSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";
import assert from "node:assert/strict";
const require = createRequire(import.meta.url);
const { chromium } = require("/Users/serhiirihgt/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright");
const origin = "http://127.0.0.1:3224", output = "build/playground-mcp-20261028/cross-client";
mkdirSync(output, { recursive: true });
const reports: { role: string; event: string }[] = [], nonce = "mcp-interview-" + Date.now();
let phase = "joining", browser: any, fixtureServer: ReturnType<typeof createServer> | undefined;
const client = new Client({ name: "crabrix-mcp-real-clients-qualification", version: "1.0.0" });
const transport = new StdioClientTransport({ command: process.execPath, args: [path.resolve("build/playground-mcp-20261028/probes/local-probe.mjs")], stderr: "pipe" });
const sleep = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));
async function call(name: string, args: Record<string, unknown> = {}): Promise<any> {
  const result = await client.callTool({ name, arguments: args });
  if (result.isError) throw new Error(JSON.stringify(result.content));
  return result.structuredContent;
}
async function wait(check: () => boolean | Promise<boolean>, label: string, timeout = 240_000) {
  const end = Date.now() + timeout;
  while (!await check()) { if (Date.now() >= end) throw new Error("Timeout: " + label); await sleep(1500); }
}
try {
  await client.connect(transport);
  const created = await call("crabrix_create", { name: "MCP Rust interview", lifetimeMinutes: 15, files: { "main.rs": "// native-pair " + nonce + '\nfn main(){println!("join-only");}\n' } });
  const nativeURL = created.link.replace(origin, "https://crabrix.com");
  fixtureServer = createServer((req, res) => {
    res.setHeader("Cache-Control", "no-store"); res.setHeader("Content-Type", "application/json");
    if (req.url === "/fixture") res.end(JSON.stringify({ url: nativeURL, origin, nonce }));
    else if (req.url === "/phase") res.end(JSON.stringify({ phase }));
    else if (req.url === "/event" && req.method === "POST") { let body = ""; req.on("data", b => { body += b; }); req.on("end", () => { const value = JSON.parse(body); reports.push(value); console.log("APP", value.role, value.event); res.end("{}"); }); }
    else { res.statusCode = 404; res.end("{}"); }
  }).listen(3395, "127.0.0.1");
  browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } }), errors: string[] = [];
  page.on("pageerror", (error: Error) => errors.push(error.message));
  await page.goto(created.link); await page.waitForSelector(".cm-content");
  await page.waitForFunction((n: string) => document.querySelector(".cm-content")?.textContent?.includes(n), nonce);
  await page.getByRole("button", { name: "✓ Check", exact: true }).click();
  await page.waitForFunction(() => (document.querySelector(".pg-check") as HTMLButtonElement)?.disabled === false, null, { timeout: 300_000 });
  console.log("READY: MCP + web; launch phone and iPad UI gates");
  await wait(async () => { const file = await call("crabrix_read_file", { path: "main.rs" }); return file.text.includes("from-phone") && file.text.includes("from-pad"); }, "both native edits");
  await page.waitForFunction(() => {
    // Remote participant badges are inline decorations, not program source.
    const content = document.querySelector(".cm-content")?.cloneNode(true) as HTMLElement | undefined;
    content?.querySelectorAll(".cm-ySelectionCaret").forEach(node => node.remove());
    const s = content?.textContent ?? "";
    return s.includes("from-phone") && s.includes("from-pad");
  });
  await wait(async () => { const status = await call("crabrix_status"); return status.selections.filter((s: any) => s.anchor !== s.head).length >= 2; }, "both native selections reach MCP");
  const nativeSelectionStatus = await call("crabrix_status");
  const file = await call("crabrix_read_file", { path: "main.rs" });
  await call("crabrix_select", { path: "main.rs", anchor: 3, head: 14, expectedRevision: file.revision });
  await sleep(1500); await page.waitForSelector(".cm-ySelection");
  await page.screenshot({ path: output + "/mcp-selection-in-browser.png" });
  phase = "selection-ready";
  await wait(() => reports.filter(r => r.event === "selection-captured").length === 2, "native selection captures");
  const debugSource = 'fn main() {\n let message=String::from("shared-debug");\n let numbers=vec![2u32,40];\n println!("{} {}",message,numbers.iter().sum::<u32>());\n}\n';
  await call("crabrix_apply_changes", { expectedRevision: (await call("crabrix_read_file", { path: "main.rs" })).revision, changes: [{ path: "main.rs", text: debugSource }] });
  await wait(() => reports.filter(r => r.event === "debug-paused").length === 2, "both native local debuggers");
  await page.getByRole("button", { name: "Debug Rust", exact: true }).click();
  await page.getByRole("button", { name: "▶ Continue", exact: true }).waitFor({ timeout: 240_000 });
  await page.getByRole("button", { name: "Step over", exact: true }).click();
  await page.waitForFunction(() => document.querySelector(".pg-debug-location")?.textContent?.includes("main.rs:3"));
  assert.match(await page.locator(".pg-debug-panel table").innerText(), /shared-debug/);
  await page.getByRole("button", { name: "Step over", exact: true }).click();
  await page.waitForFunction(() => document.querySelector(".pg-debug-location")?.textContent?.includes("main.rs:4"));
  assert.match(await page.locator(".pg-debug-panel table").innerText(), /2, 40/);
  await call("crabrix_select", { path: "main.rs", anchor: 3, head: 14, expectedRevision: (await call("crabrix_read_file", { path: "main.rs" })).revision });
  await sleep(700); assert.equal(await page.getByRole("button", { name: "Step over", exact: true }).isVisible(), true);
  await page.screenshot({ path: output + "/mcp-source-local-browser-debug.png" });
  await call("crabrix_apply_changes", { expectedRevision: (await call("crabrix_read_file", { path: "main.rs" })).revision, changes: [{ path: "main.rs", text: 'fn main(){println!("shared-final=42");}\n' }] });
  await page.waitForFunction(() => document.querySelector(".pg-notice")?.textContent?.includes("Debug stopped because shared source changed"));
  await wait(() => reports.filter(r => r.event === "debug-stopped").length === 2, "stale native debugging canceled");
  await page.getByRole("button", { name: "▶ Run", exact: true }).click();
  await page.waitForFunction(() => document.querySelector(".pg-output pre")?.textContent === "shared-final=42\n", null, { timeout: 90_000 });
  await wait(() => reports.filter(r => r.event === "done").length === 2, "native Run and HTTPS reopening");
  assert.deepEqual(errors, []);
  writeFileSync(output + "/result.json", JSON.stringify({ at: new Date().toISOString(), participants: "MCP + browser + iPhone Simulator + iPad Simulator", reports,
    nativeSelectionParticipants: nativeSelectionStatus.selections.filter((s: any) => s.anchor !== s.head).length,
    passed: ["MCP creates room", "both actual app editors send source to MCP and web", "MCP receives human selections", "MCP selection reaches app and browser", "MCP edits reach all clients", "three independent local String/Vec debug sessions", "selection preserves paused Debug", "MCP edit cancels stale Debug", "all three clients execute actual final stdout", "native custom and HTTPS links"], backendExecution: false, physicalDevices: false }, null, 2));
  console.log("PASS: MCP, two actual apps, browser, selections and three local compilers/debuggers");
} finally { fixtureServer?.close(); await browser?.close(); await client.close(); await transport.close(); }
