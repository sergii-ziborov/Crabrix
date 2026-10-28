/* Local text analysis only. The bundled module has no host imports. */
"use strict";
let module, library, core, graphKey, previous = new Map();
const encoder = new TextEncoder(), decoder = new TextDecoder("utf-8", { fatal: true });
const byteLimit = 28 * 1024 * 1024;

function call(request) {
  const bytes = encoder.encode(JSON.stringify(request));
  if (bytes.length > byteLimit) throw new Error("This analysis snapshot exceeds the source budget.");
  const ptr = core.crabrix_semantic_alloc(bytes.length);
  if (!ptr) throw new Error("The analysis input budget is exhausted.");
  try {
    new Uint8Array(core.memory.buffer, ptr, bytes.length).set(bytes);
    const output = core.crabrix_semantic_request(ptr, bytes.length);
    const length = core.crabrix_semantic_output_len();
    if (length > 2 * 1024 * 1024) throw new Error("Analysis response exceeds its budget.");
    const result = JSON.parse(decoder.decode(new Uint8Array(core.memory.buffer, output, length)));
    if (!result.ok) throw new Error(result.error || "Information is unavailable for this source.");
    return result.result;
  } finally {
    core.crabrix_semantic_free(ptr, bytes.length);
  }
}

function validate(workspace) {
  if (!workspace || !Array.isArray(workspace.files) || !Array.isArray(workspace.crates)
      || workspace.files.length > 2048 || workspace.crates.length > 253) {
    throw new Error("This workspace exceeds the semantic analysis profile.");
  }
  let total = 0;
  const paths = new Set();
  for (const file of workspace.files) {
    if (typeof file.path !== "string" || typeof file.text !== "string"
        || file.path.startsWith("__lib/") || paths.has(file.path)) throw new Error("Invalid analysis source.");
    paths.add(file.path);
    const bytes = encoder.encode(file.text).length;
    if (bytes > 1024 * 1024) throw new Error("An analysis file exceeds 1 MiB. Compiler Check remains available.");
    total += bytes;
  }
  if (total > 8 * 1024 * 1024) throw new Error("Project and dependency analysis exceeds 8 MiB. Compiler Check remains available.");
}

async function analyze(workspace, query) {
  validate(workspace);
  const paths = workspace.files.map(f => f.path).sort();
  const nextKey = JSON.stringify([workspace.crates, paths, workspace.dependencyIdentity || ""]);
  const dependencyChanged = workspace.files.some(f => f.path.startsWith("__dep/") && previous.get(f.path) !== f.text);
  if (!core || graphKey !== nextKey || dependencyChanged) {
    // A new graph gets a fresh heap. Never construct two analysis databases in
    // one bounded Wasm memory while replacing a large standard-library graph.
    core = undefined;
    previous.clear();
    core = (await WebAssembly.instantiate(module, {})).exports;
    const defaults = Object.fromEntries(library.crates.map(c => [c.name, c.root]));
    const crates = workspace.crates.map(c => ({ ...c, dependencies: { ...defaults, ...c.dependencies } }));
    call({ op: "configure", configuration: { files: [...library.files, ...workspace.files], crates: [...library.crates, ...crates] } });
    graphKey = nextKey;
    previous = new Map(workspace.files.map(f => [f.path, f.text]));
  } else {
    const changed = workspace.files.filter(f => previous.get(f.path) !== f.text);
    if (changed.length) {
      call({ op: "update", files: changed });
      for (const file of changed) previous.set(file.path, file.text);
    }
  }
  return call(query);
}

// Requests are serial even while compiling or replacing a module instance.
// The client applies results only to the exact requested workspace revision.
let queue = Promise.resolve();
self.onmessage = event => {
  const message = event.data;
  queue = queue.then(async () => {
    try {
      if (message.kind === "initialize") {
        module = await WebAssembly.compile(message.wasm);
        if (WebAssembly.Module.imports(module).length !== 0) throw new Error("Unexpected engine imports.");
        library = JSON.parse(decoder.decode(message.library));
        if (library.schemaVersion !== 1) throw new Error("Unsupported source library.");
        self.postMessage({ id: message.id, ok: true, result: { ready: true } });
      } else if (message.kind === "analyze" && module && library) {
        const result = await analyze(message.workspace, message.query);
        self.postMessage({ id: message.id, ok: true, result, memoryBytes: core.memory.buffer.byteLength });
      } else throw new Error("Analysis engine is not ready.");
    } catch (error) {
      core = undefined; graphKey = undefined; previous.clear();
      const messageText = error instanceof WebAssembly.RuntimeError
        ? "Analysis could not finish within this profile. Editing and compiler Check remain available."
        : error instanceof Error ? error.message.slice(0, 400) : "Analysis information is unavailable.";
      self.postMessage({ id: message.id, ok: false, error: messageText });
    }
  });
};
