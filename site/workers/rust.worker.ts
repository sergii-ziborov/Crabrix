/// <reference lib="webworker" />
import { runtimeSourceRevision } from '../lib/playground-runtime-source';
import { WASI, File, Directory, OpenFile, PreopenDirectory, ConsoleStdout } from "@bjorn3/browser_wasi_shim";
import { gunzipSync, unzipSync } from "fflate";
import manifest from "../lib/playground-toolchain.json";
import { validatePlaygroundDocument } from "../lib/playground-document";
import { limitProgramMemory } from "../lib/wasm-resource-limits";
import { instrumentRust, debugImport } from "../lib/rust-debug-instrumentation";
import { RustDebugSession } from "../lib/rust-debug-session";
import { loadPreparedCargo, type PreparedCargo } from "../lib/browser-cargo";
import { readCargoRoot } from "../lib/browser-cargo-manifest";
import { buildScriptDirectives } from "../lib/browser-cargo-build-script";
import { boundBuildScript } from "../lib/browser-cargo-build-sandbox";
import { cargoTargetEnvironment } from "../lib/browser-cargo-target";

const worker = self as unknown as DedicatedWorkerGlobalScope;
const encoder = new TextEncoder();
let compiler: WebAssembly.Module | undefined;
let sysroot: Map<string, File | Directory> | undefined;
let builtCargo: { identity: string; files: Map<string, File | Directory> } | undefined;
type Asset = { url: string; sha256: string; bytes: number };

function stage(label: string, downloadProgress = false) { worker.postMessage({ type: "stage", label, downloadProgress }); }
const transferred = new Map<string, number>();
let lastProgressAt = 0;
function downloadProgress(item: Asset, received: number) {
  transferred.set(item.url, received);
  const now = performance.now();
  if (now - lastProgressAt < 250 && received !== item.bytes) return;
  lastProgressAt = now;
  const total = manifest.compiler.bytes + manifest.sysroot.bytes;
  const loaded = [...transferred.values()].reduce((sum, bytes) => sum + bytes, 0);
  stage(`Loading verified Rust toolchain · ${(loaded / 1048576).toFixed(1)} / ${(total / 1048576).toFixed(1)} MiB`, true);
}
async function sha(bytes: Uint8Array): Promise<string> {
  return Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", new Uint8Array(bytes))), byte => byte.toString(16).padStart(2, "0")).join("");
}

async function asset(item: Asset): Promise<Uint8Array<ArrayBuffer>> {
  const url = new URL(item.url, worker.location.origin).href;
  let cache: Cache | undefined;
  try { cache = await caches.open("crabrix-rust-toolchain-" + manifest.compiler.expandedSHA256); } catch {}
  let response = await cache?.match(url);
  let cached = !!response;
  if (response) {
    const bytes = new Uint8Array(await response.arrayBuffer());
    if (bytes.byteLength === item.bytes && await sha(bytes) === item.sha256) { downloadProgress(item, bytes.byteLength); return bytes; }
    await cache?.delete(url); response = undefined; cached = false;
  }
  response = await fetch(url, { credentials: "omit", cache: "no-store", redirect: "error" });
  if (!response.ok || !response.body) throw new Error("Compiler asset unavailable. Load the verified toolchain while connected, then retry.");
  const chunks: Uint8Array[] = []; const reader = response.body.getReader(); let size = 0;
  while (true) {
    const { done, value } = await reader.read(); if (done) break;
    size += value.byteLength;
    if (size > item.bytes) { await reader.cancel(); throw new Error("Oversized compiler asset."); }
    chunks.push(value);
    downloadProgress(item, size);
  }
  const bytes = new Uint8Array(size); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  if (bytes.byteLength !== item.bytes || await sha(bytes) !== item.sha256) throw new Error("Compiler asset failed SHA-256 verification.");
  if (!cached) try { await cache?.put(url, new Response(bytes, { headers: { "Content-Type": "application/octet-stream" } })); } catch {}
  return bytes;
}

function insert(root: Map<string, File | Directory>, path: string, file: File) {
  const parts = path.split("/"); const name = parts.pop()!;
  let directory = root;
  for (const part of parts) {
    let node = directory.get(part);
    if (!node) { node = new Directory(new Map()); directory.set(part, node); }
    if (!(node instanceof Directory)) throw new Error("Conflicting source paths.");
    directory = node.contents as Map<string, File | Directory>;
  }
  directory.set(name, file);
}

async function initialize() {
  if (compiler && sysroot) return;
  stage("Loading verified Rust compiler and standard library");
  const [compressed, archive] = await Promise.all([asset(manifest.compiler), asset(manifest.sysroot)]);
  stage("Preparing the local compiler");
  const bytes = gunzipSync(compressed);
  if (bytes.byteLength !== manifest.compiler.expandedBytes || await sha(bytes) !== manifest.compiler.expandedSHA256) throw new Error("Expanded compiler integrity mismatch.");
  compiler = await WebAssembly.compile(bytes);
  const root = new Map<string, File | Directory>();
  const files = unzipSync(archive); let expanded = 0;
  for (const [name, contents] of Object.entries(files)) {
    expanded += contents.byteLength;
    if (expanded > 80 * 1024 * 1024) throw new Error("Sysroot expansion limit.");
    if (name.endsWith("/") || name.endsWith("manifest.json")) continue;
    if (!name.startsWith("sysroot-wasip1/") || name.includes("..") || name.includes("\\")) throw new Error("Invalid sysroot path.");
    insert(root, name.slice("sysroot-wasip1/".length), new File(contents, { readonly: true }));
  }
  sysroot = root;
  stage("Local Rust compiler ready");
}

type DebugHost = { control: Int32Array; session: RustDebugSession; runningMs: number; resumedAt: number };
async function invoke(module: WebAssembly.Module, args: string[], input: string, mounts: PreopenDirectory[], isCompiler = false, debugging?: DebugHost, compileDebug = false, cargoEnv: string[] = [], buildOutputs?: Map<string, File | Directory>[]) {
  let stdout = "", stderr = "", capturedBytes = 0;
  const decoders = [new TextDecoder(), new TextDecoder()];
  const capture = (index: number) => new ConsoleStdout(bytes => {
    capturedBytes += bytes.length;
    if (capturedBytes > 1024 * 1024) throw new Error("Program stopped at the 1 MiB output limit.");
    const text = decoders[index].decode(bytes, { stream: true });
    if (index === 0) stdout += text; else stderr += text;
  });
  const wasi = new WASI(args, ["PWD=/work", "TMPDIR=/tmp", ...cargoEnv, ...(isCompiler ? ["CLIF2WASM_OBJECT=1", ...(compileDebug ? [`CLIF2WASM_IMPORTS=${debugImport}`] : [])] : [])], [
    new OpenFile(new File(encoder.encode(input))), capture(0), capture(1), ...mounts,
  ]);
  if (buildOutputs) boundBuildScript(wasi, [3, 5], buildOutputs);
  const instance = await WebAssembly.instantiate(module, { wasi_snapshot_preview1: wasi.wasiImport, ...(debugging ? { env: {
    [debugImport]: (kind: number, site: number, pointer: number, length: number) => {
      const memory = instance.exports.memory as WebAssembly.Memory;
      pointer >>>= 0; length >>>= 0;
      if (length > 65536 || pointer > memory.buffer.byteLength || length > memory.buffer.byteLength - pointer) throw new Error("Invalid debugger memory range.");
      if (debugging.runningMs + performance.now() - debugging.resumedAt > 30_000) throw new Error("Debug reached its 30-second running-time limit. Paused time is excluded.");
      debugging.session.event(kind, site, new Uint8Array(memory.buffer, pointer, length));
    },
  } } : {}) });
  let exitCode = 1, trap: string | undefined;
  try { exitCode = wasi.start(instance as Parameters<WASI["start"]>[0]); }
  catch (error) { trap = String(error); }
  stdout += decoders[0].decode(); stderr += decoders[1].decode();
  return { exitCode, stdout, stderr, ...(trap ? { trap } : {}) };
}

const crateOutput = (graph: PreparedCargo, name: string) => {
  const node = graph.packages.find(item => item.name === name);
  if (!node) throw new Error("Prepared dependency graph is incomplete.");
  // Distinct registry packages can deliberately declare the same [lib] name.
  return `/deps/lib${node.archive.libName}-${node.name}-${node.version}.rlib`;
};
const externs = (graph: PreparedCargo, edges: Record<string, string>) => Object.entries(edges).flatMap(([alias, name]) => ["--extern", `${alias.replaceAll("-", "_")}=${crateOutput(graph, name)}`]);

async function compileDependencies(graph: PreparedCargo) {
  if (builtCargo?.identity === graph.identity) return { files: builtCargo.files };
  const files = new Map<string, File | Directory>(), crates = new Map<string, File | Directory>();
  for (const node of graph.packages) for (const [path, bytes] of node.archive.files) insert(crates, `${node.name}-${node.version}/${path}`, new File(bytes, { readonly: true }));
  const mounts = [new PreopenDirectory("/crates", crates), new PreopenDirectory("/deps", files), new PreopenDirectory("/sysroot", sysroot!), new PreopenDirectory("/tmp", new Map())];
  const artifactBytes = (entries: Map<string, File | Directory>): number => [...entries.values()].reduce((sum, entry) => sum + (entry instanceof Directory ? artifactBytes(entry.contents as Map<string, File | Directory>) : entry.data.length), 0);
  for (const node of graph.packages) {
    stage(`Building ${node.name} ${node.version} locally`);
    const cfg = node.features.flatMap(feature => ["--cfg", `feature="${feature}"`]);
    // RUSTC names the compiler for Cargo-compatible probes. WASI has no
    // subprocess import: build scripts must handle an unavailable probe.
    const environment = [...node.archive.env, ...cargoTargetEnvironment, 'RUSTC=rustc', 'HOST=wasm32-wasip1', 'TARGET=wasm32-wasip1', 'OPT_LEVEL=0', 'PROFILE=debug', 'DEBUG=true', 'NUM_JOBS=1'];
    let build = { args: [] as string[], env: [] as string[] };
    if (node.archive.buildScript) {
      const scriptOutput = `/deps/build-${node.name}-${node.version}.wasm`;
      const checked = await invoke(compiler!, ['rustc', `/crates/${node.name}-${node.version}/${node.archive.buildScript}`, '--crate-name', 'build_script_build', '--edition', node.archive.edition, '--target', 'wasm32-wasip1', '--sysroot', '/sysroot', '--error-format=json', '--cap-lints=allow', '-Copt-level=0', '-Cpanic=abort', ...cfg, '-o', scriptOutput], '', mounts, true, undefined, false, environment);
      if (checked.exitCode !== 0 || checked.trap) return { files, compilation: checked };
      const script = files.get(scriptOutput.slice('/deps/'.length));
      if (!(script instanceof File) || script.data.length > 8 * 1024 * 1024) throw new Error('Build script artifact limit.');
      const out = new Map<string, File | Directory>(), tmp = new Map<string, File | Directory>();
      const source = crates.get(`${node.name}-${node.version}`);
      if (!(source instanceof Directory)) throw new Error('Build script source missing.');
      // No user's sources, other packages, compiler, host environment or sysroot
      // are visible to build.rs. Only its own source and two bounded guest dirs.
      const execution = await invoke(await WebAssembly.compile(limitProgramMemory(script.data)), ['build-script'], '', [new PreopenDirectory('/out', out), new PreopenDirectory(`/crates/${node.name}-${node.version}`, source.contents), new PreopenDirectory('/tmp', tmp)], false, undefined, false, [...environment, 'OUT_DIR=/out', ...node.features.map(feature => 'CARGO_FEATURE_' + feature.toUpperCase().replaceAll('-', '_') + '=1')], [out, tmp]);
      files.delete(scriptOutput.slice('/deps/'.length));
      if (execution.exitCode !== 0 || execution.trap) return { files, compilation: execution };
      build = buildScriptDirectives(execution.stdout);
      // OUT_DIR is specific to this package. It is mounted only for compilation.
      const outPath = `out-${node.name}-${node.version}`;
      files.set(outPath, new Directory(out));
      environment.push(`OUT_DIR=/deps/${outPath}`);
    }
    const args = ["rustc", `/crates/${node.name}-${node.version}/${node.archive.libPath}`, "--crate-type", "rlib", "--crate-name", node.archive.libName, "--edition", node.archive.edition, "--target", "wasm32-wasip1", "--sysroot", "/sysroot", "--error-format=json", "--cap-lints=allow", "-Copt-level=0", "-Cpanic=abort", "-Cdebuginfo=0", `-Cmetadata=crabrix_${graph.identity}_${node.name.replaceAll("-", "_")}`, "-L", "dependency=/deps", ...externs(graph, node.dependencies), ...cfg, ...build.args, "-o", crateOutput(graph, node.name)];
    const compilation = await invoke(compiler!, args, "", mounts, true, undefined, false, [...environment, ...build.env]);
    if (compilation.exitCode !== 0 || compilation.trap) return { files, compilation };
    const output = files.get(crateOutput(graph, node.name).slice("/deps/".length));
    if (!(output instanceof File)) throw new Error(`${node.name}: rustc did not produce a library.`);
    if (artifactBytes(files) > 64 * 1024 * 1024) throw new Error("Compiled Cargo libraries exceed this browser's 64 MiB artifact budget.");
  }
  builtCargo = { identity: graph.identity, files };
  return { files };
}

worker.onmessage = async ({ data }) => {
  const started = performance.now();
  try {
    if (data.type === "initialize") { await initialize(); worker.postMessage({ type: "ready" }); return; }
    if (!compiler || !sysroot) throw new Error("Load the local Rust toolchain first.");
    const source = validatePlaygroundDocument(data.document);
    const sourceRevision=await runtimeSourceRevision(source);
    const cargo = readCargoRoot(source);
    if (data.allowCargo === false && cargo) throw new Error("Agent-controlled execution stays in the manifest-free shared-std-v1 profile. Use ordinary local Run for Cargo.");
    const prepared = cargo?.dependencies.length ? await loadPreparedCargo(source) : null;
    const isDebug = data.type === "debug";
    if (isDebug && (!(data.control instanceof SharedArrayBuffer) || data.control.byteLength !== (8192 + 5) * 4)) throw new Error("Debug requires an isolated browser context with shared control memory.");
    if (typeof data.stdin !== "string" || encoder.encode(data.stdin).length > 32 * 1024) throw new Error("stdin must be at most 32 KiB.");
    const work = new Map<string, File | Directory>();
    for (const [path, text] of Object.entries(source.files)) insert(work, path, new File(encoder.encode(text)));
    const check = data.type === "check";
    stage(check ? "Checking Rust source locally" : "Compiling and linking Rust locally");
    const args = ["rustc", "/work/" + source.entryFile, "--crate-name", cargo?.name.replaceAll("-", "_") ?? "playground", "--sysroot", "/sysroot", "--target", "wasm32-wasip1", "--edition", cargo?.edition ?? source.edition,
      "--error-format=json", "-Copt-level=0", "-Cpanic=abort", "-Cdebuginfo=0", ...(cargo ? [...cargo.enabled.flatMap(feature => ["--cfg", `feature="${feature}"`]), "--check-cfg=cfg(feature,values(any()))"] : []), ...(prepared ? ["-L", "dependency=/deps", ...externs(prepared, prepared.dependencies)] : []), ...(check ? ["--emit", "metadata"] : []), "-o", "/work/" + (check ? "program.rmeta" : "program.wasm")];
    const mounts = [new PreopenDirectory("/work", work), new PreopenDirectory("/sysroot", sysroot), new PreopenDirectory("/tmp", new Map())];
    const cargoEnv = cargo ? [`CARGO_MANIFEST_DIR=/work/${cargo.prefix}`, `CARGO_PKG_NAME=${cargo.name}`, `CARGO_PKG_VERSION=${cargo.version}`, ...cargo.version.split(/[.+-]/).slice(0, 3).map((value, index) => `CARGO_PKG_VERSION_${["MAJOR", "MINOR", "PATCH"][index]}=${value}`), `CARGO_PKG_VERSION_PRE=${cargo.version.split("-")[1]?.split("+")[0] ?? ""}`] : [];
    if (prepared) {
      worker.postMessage({ type: "cargo-build" });
      const built = await compileDependencies(prepared);
      if (built.compilation) { const compileMs = performance.now() - started; worker.postMessage({ type: "result", sourceRevision, compilation: built.compilation, compileMs, durationMs: compileMs }); return; }
      mounts.push(new PreopenDirectory("/deps", built.files));
    }
    let debugging: DebugHost | undefined;
    if (isDebug) {
      const checked = await invoke(compiler, [...args.slice(0, -2), "--emit", "metadata", "-o", "/work/debug-check.rmeta"], "", mounts, true, undefined, false, cargoEnv);
      if (checked.exitCode !== 0) { worker.postMessage({ type: "result", sourceRevision, compilation: checked, compileMs: performance.now() - started, durationMs: performance.now() - started }); return; }
      const plan = instrumentRust(source.files, source.entryFile);
      for (const [path, text] of Object.entries(plan.files)) insert(work, path, new File(encoder.encode(text)));
      const control = new Int32Array(data.control);
      worker.postMessage({ type: "debug-plan", sites: plan.sites, notes: plan.notes });
      debugging = { control, runningMs: 0, resumedAt: 0, session: undefined as unknown as RustDebugSession };
      const host = debugging;
      host.session = new RustDebugSession(plan.sites, control, state => {
        host.runningMs += performance.now() - host.resumedAt;
        Atomics.store(control, 0, 0);
        worker.postMessage({ type: "paused", ...state, runningMs: host.runningMs });
        const waited = Atomics.wait(control, 0, 0, 30 * 60_000);
        const command = Atomics.load(control, 0);
        if (waited === "timed-out" || command === 5) throw new Error(waited === "timed-out" ? "Debug pause expired after 30 minutes." : "Debug stopped.");
        host.resumedAt = performance.now();
        return command;
      });
    }
    const compilation = await invoke(compiler, args, "", mounts, true, undefined, isDebug, cargoEnv);
    const compileMs = performance.now() - started;
    if (compilation.exitCode !== 0 || check || data.type === "build") { worker.postMessage({ type: "result", sourceRevision, compilation, compileMs, durationMs: compileMs }); return; }
    const output = work.get("program.wasm");
    if (!(output instanceof File)) throw new Error("The compiler did not emit a runnable program.");
    const bounded = limitProgramMemory(output.data);
    stage("Running the Wasm program on your device");
    worker.postMessage({ type: "executing" });
    if (debugging) debugging.resumedAt = performance.now();
    const execution = await invoke(await WebAssembly.compile(bounded), [source.name], data.stdin, [], false, debugging);
    worker.postMessage({ type: "result", sourceRevision, compilation, execution, compileMs, durationMs: performance.now() - started });
  } catch (error) { worker.postMessage({ type: "error", error: error instanceof Error ? error.message : String(error) }); }
};
