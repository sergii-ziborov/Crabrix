// Run with a local-only static server from prepare.py. No application API is used.
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || "playwright");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const output = process.argv[2] || "build/browser-rust-feasibility-20261027";
const base = process.env.PROBE_URL || "http://127.0.0.1:3392";
const rust = `fn doubled(n: i32) -> i32 {
    let result = n * 2;
    result
}
fn main() {
    let answer = doubled(21);
    println!("answer={answer}");
}`;

(async () => {
  const browser = await chromium.launch({ headless: true });
  try {
    const context = await browser.newContext();
    const requests = [], unexpectedRequests = [];
    context.on("request", request => {
      requests.push({ method: request.method(), url: request.url() });
      if (request.method() !== "GET" || !request.url().startsWith(base + "/")) unexpectedRequests.push(request.url());
    });
    const page = await context.newPage();
    page.setDefaultTimeout(120_000);
    await page.goto(base);
    await page.waitForFunction(() => typeof window.probe === "function");
    const initialized = await page.evaluate(() => window.probe({ type: "initialize" }));
    await context.route("**/*", route => {
      unexpectedRequests.push(route.request().url());
      return route.abort();
    });
    await page.evaluate(() => { window.heartbeats = 0; window.heartbeatTimer = setInterval(() => window.heartbeats++, 10); });
    const result = await page.evaluate(async source => {
      const reply = await window.probe({ type: "compile-run", source, returnArtifact: true });
      return { ...reply, artifact: reply.artifact ? Array.from(reply.artifact) : undefined };
    }, rust);
    assert.equal(result.compilation.exitCode, 0, result.compilation.stderr);
    assert.equal(result.execution.stdout, "answer=42\n");
    fs.writeFileSync(path.join(output, "program.wasm"), Buffer.from(result.artifact));
    fs.writeFileSync(path.join(output, "main.rs"), rust);
    delete result.artifact;
    const borrow = await page.evaluate(() => window.probe({ type: "compile-run", source: 'fn main() { let mut v = vec![1]; let first = &v[0]; v.push(2); println!("{first}"); }' }));
    assert.notEqual(borrow.compilation.exitCode, 0);
    assert.match(borrow.compilation.stderr, /E0502/);
    assert.equal(borrow.execution, undefined);
    const stdin = await page.evaluate(() => window.probe({ type: "compile-run", source: 'use std::io::{self, Read}; fn main() { let mut s = String::new(); io::stdin().read_to_string(&mut s).unwrap(); let total: i32 = s.split_whitespace().map(|x| x.parse::<i32>().unwrap()).sum(); println!("sum={total}"); }', stdin: "3 7 11" }));
    assert.equal(stdin.compilation.exitCode, 0, stdin.compilation.stderr);
    assert.equal(stdin.execution.stdout, "sum=21\n");
    const heartbeats = await page.evaluate(() => window.heartbeats);
    assert.ok(heartbeats > 5, "Worker must not block the page event loop");
    assert.deepEqual(unexpectedRequests, []);
    const debug = await page.evaluate(source => window.probe({ type: "compile-run", source, debugInfo: true }), rust);
    const debugInfo = { exitCode: debug.compilation.exitCode, stderr: debug.compilation.stderr, trap: debug.compilation.trap, compileMs: debug.compileMs };
    const lineTables = await page.evaluate(source => window.probe({ type: "compile-run", source, debugInfo: "line-tables-only" }), rust);
    const lineTablesInfo = { ...lineTables, compilation: { ...lineTables.compilation } };
    // Debug-info generation is independently qualified; normal Run does not enable it.
    if (debug.compilation.exitCode !== 0) assert.match(debug.compilation.stderr, /rustc_codegen_cranelift\/src\/debuginfo\/line_info\.rs/);
    // Termination is the browser Stop mechanism; it needs no guest cooperation.
    await page.evaluate(() => {
      window.infiniteProgramStarted = false;
      window.probeWorker.addEventListener("message", ({ data }) => {
        if (data.id === 999 && data.type === "executing") window.infiniteProgramStarted = true;
      });
      window.probeWorker.postMessage({ id: 999, type: "compile-run", reportStart: true, source: "fn main() { loop { std::hint::spin_loop(); } }" });
    });
    await page.waitForFunction(() => window.infiniteProgramStarted);
    const stoppedAt = Date.now();
    await page.evaluate(() => { window.probeWorker.terminate(); clearInterval(window.heartbeatTimer); });
    const receipt = { browser: await browser.version(), initialized, result, borrow: { exitCode: borrow.compilation.exitCode, E0502: true },
      stdin: { ...stdin, source: undefined }, debugInfo, lineTablesInfo, heartbeats, stoppedWorkerMs: Date.now() - stoppedAt,
      requests, unexpectedRequests, scope: "Chromium on the Mac; not Safari or an iPhone performance measurement" };
    fs.writeFileSync(path.join(output, "verification.json"), JSON.stringify(receipt, null, 2) + "\n");
    console.log(JSON.stringify({ initialized, run: result, stdin: stdin.execution, debugInfo, lineTablesInfo, E0502: true, heartbeats,
      stoppedWorkerMs: receipt.stoppedWorkerMs, staticAssetRequests: requests.length, sourceUploadRequests: 0 }, null, 2));
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
