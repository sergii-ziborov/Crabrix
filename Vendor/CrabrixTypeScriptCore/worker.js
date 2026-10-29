"use strict";
// Runs after the pinned TypeScript compiler, in a dedicated disposable Worker.
// Project sources are virtual files, never evaluated as JavaScript.
(() => {
  const own = (value, key) => Object.prototype.hasOwnProperty.call(value, key);
  let library;
  const normalize = value => {
    if (typeof value !== "string" || /[\\\x00-\x1f\x7f]/.test(value)) throw Error("Unsafe virtual path.");
    const parts = [];
    for (const part of value.split("/")) {
      if (!part || part === ".") continue;
      if (part === "..") parts.pop(); else parts.push(part);
    }
    return "/" + parts.join("/");
  };
  const unsupported = message => { throw Error("Unsupported TypeScript checking profile: " + message); };
  function check(payload) {
    if (!library || ts.version !== "5.9.3") throw Error("The pinned TypeScript checker is unavailable.");
    const files = Object.create(null), keys = Object.keys(payload.files || {});
    if (keys.length > 2048) throw Error("TypeScript input exceeds 2,048 project files.");
    let total = 0;
    const encoder = new TextEncoder();
    for (const name of keys) {
      const source = payload.files[name];
      if (!name || name.startsWith("/") || name.split("/").some(p => !p || p === "." || p === "..") || typeof source !== "string") throw Error("Invalid TypeScript virtual file.");
      const bytes = encoder.encode(source).length;
      if (bytes > 2 * 1024 * 1024 || (total += bytes) > 16000000) throw Error("TypeScript input exceeds the editable project byte limits.");
      files[normalize("/project/" + name)] = source;
    }
    const root = normalize("/project/" + (payload.directory || ""));
    if (root !== "/project" && !root.startsWith("/project/")) throw Error("The checking root escapes the project.");
    const all = Object.assign(Object.create(null), library, files);
    const directories = new Map();
    for (const path of Object.keys(all)) {
      const parts = path.split("/").slice(1);
      for (let i = 0; i < parts.length; i++) {
        const directory = "/" + parts.slice(0, i).join("/");
        if (!directories.has(directory)) directories.set(directory, { files: new Set(), directories: new Set() });
        directories.get(directory)[i === parts.length - 1 ? "files" : "directories"].add(parts[i]);
      }
    }
    const fileExists = path => own(all, normalize(path));
    const readFile = path => all[normalize(path)];
    const directoryExists = path => directories.has(normalize(path));
    const entries = path => {
      const entry = directories.get(normalize(path));
      return { files: [...(entry?.files || [])].sort(), directories: [...(entry?.directories || [])].sort() };
    };
    const readDirectory = (path, extensions, excludes, includes, depth) =>
      ts.matchFiles(normalize(path), extensions, excludes, includes, true, root, depth, entries, normalize);
    const defaults = {
      target: ts.ScriptTarget.ES2024, module: ts.ModuleKind.ESNext, moduleResolution: ts.ModuleResolutionKind.Bundler,
      jsx: ts.JsxEmit.ReactJSX, strict: true, skipLibCheck: true, noEmit: true, libReplacement: false,
    };
    let roots, options, configDiagnostics = [], configPath;
    for (const candidate of [root + "/tsconfig.json", root + "/jsconfig.json"]) if (fileExists(candidate)) { configPath = candidate; break; }
    if (configPath) {
      const config = ts.readConfigFile(configPath, readFile);
      if (config.error) configDiagnostics.push(config.error);
      const host = { useCaseSensitiveFileNames: true, fileExists, readFile, readDirectory };
      // existingOptions is for command-line overrides and would silently win
      // over the user's jsx/strict/lib settings. Apply our defaults afterward.
      const parsed = ts.parseJsonConfigFileContent(config.config || {}, host, root, {}, configPath);
      configDiagnostics.push(...parsed.errors);
      if (parsed.projectReferences?.length) unsupported("project references require a separate build graph (" + configPath.slice(9) + ").");
      options = { ...defaults, ...parsed.options }; roots = parsed.fileNames;
    } else {
      options = defaults;
      roots = Object.keys(files).filter(path => path.startsWith(root + "/") && !path.includes("/node_modules/") && /\.(?:ts|tsx|mts|cts)$/.test(path));
    }
    if (options.noCheck) unsupported("noCheck would disable the requested type checking.");
    if (options.plugins?.length) unsupported("compiler/editor plugins cannot execute here.");
    if (options.composite || options.incremental) unsupported("composite and incremental build state is not part of this read-only checker.");
    if (![ts.ModuleKind.ESNext, ts.ModuleKind.ES2022, ts.ModuleKind.Preserve].includes(options.module)) unsupported("use an ES module browser configuration.");
    if (options.moduleResolution !== ts.ModuleResolutionKind.Bundler) unsupported("only browser Bundler module resolution is qualified.");
    if (options.disableSizeLimit) unsupported("disableSizeLimit cannot remove the checking limits.");
    if (options.libReplacement) unsupported("external standard-library replacement is outside the pinned library profile.");
    options = { ...options, noEmit: true, libReplacement: false };
    const host = {
      getSourceFile: (path, languageVersion) => {
        path = normalize(path); const source = readFile(path);
        return source === undefined ? undefined : ts.createSourceFile(path, source, languageVersion, true);
      },
      writeFile: () => { throw Error("TypeScript checking never emits or writes a project file."); },
      getDefaultLibFileName: opts => "/lib/" + ts.getDefaultLibFileName(opts),
      getCurrentDirectory: () => root, getDirectories: path => entries(path).directories,
      fileExists, readFile, directoryExists, realpath: normalize,
      getCanonicalFileName: normalize, useCaseSensitiveFileNames: () => true, getNewLine: () => "\n",
    };
    const program = ts.createProgram(roots, options, host);
    const diagnostics = ts.sortAndDeduplicateDiagnostics([...configDiagnostics, ...ts.getPreEmitDiagnostics(program)]);
    const bounded = diagnostics.slice(0, 200).map(diagnostic => {
      const position = diagnostic.file && diagnostic.start !== undefined ? diagnostic.file.getLineAndCharacterOfPosition(diagnostic.start) : undefined;
      return {
        code: "TS" + diagnostic.code,
        kind: [2307, 2688, 7016, 2875].includes(diagnostic.code) ? "missing-types" : "diagnostic",
        level: diagnostic.category === ts.DiagnosticCategory.Error ? "error" : "warning",
        message: ts.flattenDiagnosticMessageText(diagnostic.messageText, "\n").slice(0, 4096),
        file: diagnostic.file?.fileName.startsWith("/project/") ? diagnostic.file.fileName.slice(9) : "",
        line: (position?.line || 0) + 1, column: (position?.character || 0) + 1,
      };
    });
    return { version: ts.version, checked: roots.length > 0, roots: roots.length,
      config: configPath?.slice(9), sourceFiles: program.getSourceFiles().length,
      succeeded: !diagnostics.some(d => d.category === ts.DiagnosticCategory.Error),
      diagnostics: bounded, omittedDiagnostics: Math.max(0, diagnostics.length - bounded.length) };
  }
  self.onmessage = event => {
    const message = event.data;
    try {
      if (message.kind === "initialize") {
        library = JSON.parse(new TextDecoder().decode(message.library));
        self.postMessage({ id: message.id, initialized: ts.version === "5.9.3" });
      } else if (message.kind === "check") {
        self.postMessage({ id: message.id, result: check(message.payload) });
      } else { throw Error("Unknown checker operation."); }
    } catch (error) { self.postMessage({ id: message.id, error: String(error.message || error).slice(0, 4096) }); }
  };
})();
