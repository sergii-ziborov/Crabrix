// Feasibility probe, deliberately excluded from the production site and app.
// Serve alongside pinned @bjorn3/browser_wasi_shim 0.4.2 and verified toolchain assets.
import { WASI, File, Directory, OpenFile, PreopenDirectory, ConsoleStdout } from "/shim/dist/index.js";

let compiler;
let sysroot;
const encoder = new TextEncoder();
const maxOutput = 1_000_000;

async function verifiedAsset(asset) {
  const response = await fetch(asset.url);
  if (!response.ok) throw new Error(`Asset ${response.status}: ${asset.url}`);
  const bytes = await response.arrayBuffer();
  const digest = Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)), x => x.toString(16).padStart(2, "0")).join("");
  if (bytes.byteLength !== asset.bytes || digest !== asset.sha256) throw new Error(`Integrity mismatch: ${asset.url}`);
  return bytes;
}

function insert(root, path, file) {
  const parts = path.split("/");
  const name = parts.pop();
  let directory = root;
  for (const part of parts) {
    if (!directory.has(part)) directory.set(part, new Directory(new Map()));
    directory = directory.get(part).contents;
  }
  directory.set(name, file);
}

async function invoke(module, args, input, mounts) {
  let stdout = "", stderr = "";
  const append = (stream, text) => {
    if (stdout.length + stderr.length + text.length > maxOutput) throw new Error("Probe output limit");
    if (stream === "stdout") stdout += text + "\n"; else stderr += text + "\n";
  };
  const wasi = new WASI(args, ["PWD=/work", "TMPDIR=/tmp", "RUST_BACKTRACE=0",
    ...(args[0] === "rustc" ? ["CLIF2WASM_OBJECT=1"] : []),
  ], [
    new OpenFile(new File(encoder.encode(input))),
    ConsoleStdout.lineBuffered(text => append("stdout", text)),
    ConsoleStdout.lineBuffered(text => append("stderr", text)),
    ...mounts,
  ]);
  const instance = await WebAssembly.instantiate(module, { wasi_snapshot_preview1: wasi.wasiImport });
  let exitCode, trap;
  try { exitCode = wasi.start(instance); }
  catch (error) { exitCode = 1; trap = String(error); }
  return { exitCode, stdout, stderr, ...(trap ? { trap } : {}), linearMemoryBytes: instance.exports.memory.buffer.byteLength };
}

self.onmessage = async ({ data }) => {
  const started = performance.now();
  try {
    if (data.type === "initialize") {
      const assets = await (await fetch("/assets.json")).json();
      compiler = await WebAssembly.compile(await verifiedAsset(assets.compiler));
      sysroot = new Map();
      for (const file of assets.sysroot) insert(sysroot, file.path, new File(await verifiedAsset(file), { readonly: true }));
      self.postMessage({ id: data.id, type: "initialized", durationMs: performance.now() - started,
        compilerBytes: assets.compiler.bytes, sysrootBytes: assets.sysroot.reduce((n, f) => n + f.bytes, 0),
        crossOriginIsolated: self.crossOriginIsolated });
      return;
    }
    if (!compiler || !sysroot) throw new Error("Initialize the toolchain first");
    const debugLevel = data.debugInfo === "line-tables-only" ? "line-tables-only" : data.debugInfo ? "2" : "0";
    const work = new Map([["main.rs", new File(encoder.encode(data.source))]]);
    const compilation = await invoke(compiler, ["rustc", "/work/main.rs", "--sysroot", "/sysroot",
      "--target", "wasm32-wasip1", "--edition", "2024", "--error-format=json",
      "-Copt-level=0", "-Cpanic=abort", `-Cdebuginfo=${debugLevel}`, "-o", "/work/program.wasm"], "", [
      new PreopenDirectory("/work", work), new PreopenDirectory("/sysroot", sysroot),
      new PreopenDirectory("/tmp", new Map()),
    ]);
    const compileMs = performance.now() - started;
    const output = work.get("program.wasm");
    if (compilation.exitCode !== 0 || !(output instanceof File)) {
      self.postMessage({ id: data.id, type: "result", compilation, compileMs }); return;
    }
    const program = await WebAssembly.compile(output.data);
    if (data.reportStart) self.postMessage({ id: data.id, type: "executing" });
    const execution = await invoke(program, ["program"], data.stdin ?? "", []);
    const debugSections = [".debug_info", ".debug_line", ".debug_abbrev", ".debug_str"]
      .filter(name => WebAssembly.Module.customSections(program, name).length > 0);
    self.postMessage({ id: data.id, type: "result", compilation, execution, compileMs,
      durationMs: performance.now() - started, wasmBytes: output.data.byteLength, debugSections,
      ...(data.returnArtifact ? { artifact: output.data } : {}),
    });
  } catch (error) {
    self.postMessage({ id: data.id, type: "error", error: String(error), durationMs: performance.now() - started });
  }
};
