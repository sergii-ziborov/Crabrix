import { PLAYGROUND_LIMITS, sourceBytes, validatePlaygroundDocument, type PlaygroundDocument } from "./playground-document.ts";
import { readCargoRoot } from "./browser-cargo-manifest.ts";

export type ImportKind = "github" | "gist" | "files" | "folder" | "zip" | "native-archive" | "json";
export type Edition = PlaygroundDocument["edition"];
/** What Cargo.toml says, kept apart from the edition the runner will use. */
export type DeclaredEdition = { kind: "none" } | { kind: "supported"; edition: Edition } | { kind: "unsupported"; value: string } | { kind: "workspace" };

export type ImportCandidate = {
  path: string;
  bytes: number;
  /** Absent until the file is read. GitHub blobs are only read once chosen. */
  text?: string;
  /** Why the file cannot be imported. It is listed, never dropped silently. */
  excluded?: string;
  blobSha?: string;
};

export type ImportReceipt = { kind: ImportKind; label: string; url?: string; commit?: string; ref?: string; folder?: string; paths: Record<string, string> };

export type ImportInspection = {
  kind: ImportKind;
  label: string;
  name?: string;
  entryFile?: string;
  /** Set only when a project JSON states one exactly. */
  edition?: Edition;
  origin?: PlaygroundDocument["origin"];
  ref?: string;
  folder?: string;
  candidates: ImportCandidate[];
  notes: string[];
};

export type ConflictChoice = "skip" | "replace" | "rename";
export type ImportChoices = {
  selected: ReadonlySet<string>;
  mode: "add" | "replace";
  targetFolder: string;
  conflicts: Readonly<Record<string, ConflictChoice>>;
  entryFile?: string;
  edition?: Edition;
};

export type Readiness = { kind: "editable" | "runner" | "other-build" | "needs-choice"; message: string };

export type ImportPlan = {
  baseRevision: string;
  document?: PlaygroundDocument;
  error?: string;
  added: string[];
  replaced: string[];
  removed: string[];
  skipped: string[];
  conflicts: string[];
  fileCount: number;
  bytes: number;
  entryFile?: string;
  edition?: Edition;
  declaredEdition: DeclaredEdition;
  needsEdition: boolean;
  readiness: Readiness;
  receipt: ImportReceipt;
};

/** Identifies the exact project a plan was computed against. */
export function documentRevision(document: PlaygroundDocument): string {
  const files = Object.keys(document.files).sort().map(path => [path, document.files[path]]);
  return JSON.stringify([document.name, document.entryFile, document.edition, document.origin ?? null, files]);
}

/** Reads `[package] edition` without pretending to evaluate the manifest. */
export function declaredCargoEdition(manifest: string | undefined): DeclaredEdition {
  if (manifest === undefined) return { kind: "none" };
  let section = "", multiline: string | null = null;
  for (const raw of manifest.split(/\r?\n/)) {
    if (multiline) { if (raw.includes(multiline)) multiline = null; continue; }
    const line = raw.trim();
    if (!line || line.startsWith("#")) continue;
    const header = line.match(/^\[\[?\s*([^\]]+?)\s*\]\]?/);
    if (header) { section = header[1]; continue; }
    const quotes = line.match(/("""|''')/);
    if (quotes && line.split(quotes[1]).length === 2) { multiline = quotes[1]; continue; }
    if (section === "package.edition" && /^workspace\s*=\s*true\b/.test(line)) return { kind: "workspace" };
    if (section !== "package") continue;
    if (/^edition\.workspace\s*=\s*true\b/.test(line) || /^edition\s*=\s*\{[^}]*workspace\s*=\s*true/.test(line)) return { kind: "workspace" };
    const value = line.match(/^edition\s*=\s*["']([^"']*)["']/)?.[1];
    if (value === undefined) continue;
    return value === "2021" || value === "2024" ? { kind: "supported", edition: value } : { kind: "unsupported", value };
  }
  return { kind: "none" };
}

export function projectReadiness(document: PlaygroundDocument): Readiness {
  let cargo;
  try { cargo = readCargoRoot(document); }
  catch (error) { return { kind: "other-build", message: `Editable here. ${error instanceof Error ? error.message : String(error)}` }; }
  const entry = document.files[document.entryFile] ?? "";
  if (!/\bfn\s+main\s*\(/.test(entry)) return { kind: "other-build", message: `Editable here. ${document.entryFile} has no main function, so this runner cannot start it. Choose another entry file or use a different build path.` };
  if (cargo?.dependencies.length) return { kind: "editable", message: "Cargo dependencies are declared. Use Packages → Prepare in this browser before Check, Run or Debug; unsupported build requirements are reported." };
  return { kind: "runner", message: "Fits the std and local-modules runner so far. Check or Run gives the real result." };
}

const entryGuess = (paths: string[]) => ["src/main.rs", "main.rs", "src/lib.rs", "lib.rs"].find(path => paths.includes(path)) ?? paths.find(path => path.endsWith(".rs"));

export function joinTargetPath(folder: string, path: string): string {
  const target = folder.trim().replace(/^\/+|\/+$/g, "");
  return target ? `${target}/${path}` : path;
}

const renamedPath = (path: string, taken: (candidate: string) => boolean) => {
  const slash = path.lastIndexOf("/"), dir = path.slice(0, slash + 1), base = path.slice(slash + 1), dot = base.lastIndexOf(".");
  const stem = dot > 0 ? base.slice(0, dot) : base, extension = dot > 0 ? base.slice(dot) : "";
  for (let n = 1; n < 100; n++) { const candidate = `${dir}${stem}-imported${n > 1 ? `-${n}` : ""}${extension}`; if (!taken(candidate)) return candidate; }
  return path;
};

/** Computes the complete result of an import. It never touches the live document. */
export function buildImportPlan(current: PlaygroundDocument, inspection: ImportInspection, choices: ImportChoices): ImportPlan {
  const receipt: ImportReceipt = { kind: inspection.kind, label: inspection.label, url: inspection.origin?.url, commit: inspection.origin?.commit, ref: inspection.ref, folder: inspection.folder, paths: {} };
  const plan: ImportPlan = { baseRevision: documentRevision(current), added: [], replaced: [], removed: [], skipped: [], conflicts: [], fileCount: 0, bytes: 0, declaredEdition: { kind: "none" }, needsEdition: false, readiness: { kind: "editable", message: "" }, receipt };
  const files: Record<string, string> = Object.create(null);
  if (choices.mode === "add") for (const [path, text] of Object.entries(current.files)) files[path] = text;
  const folded = (path: string) => path.normalize("NFC").toLowerCase();
  const taken = new Map(Object.keys(files).map(path => [folded(path), path]));
  const chosen = inspection.candidates.filter(item => choices.selected.has(item.path) && !item.excluded);

  for (const item of chosen) {
    let target = joinTargetPath(choices.targetFolder, item.path);
    const existing = taken.get(folded(target));
    if (existing !== undefined) {
      plan.conflicts.push(item.path);
      const choice = choices.conflicts[item.path];
      if (!choice) { plan.error ??= `Choose what to do with ${target}.`; continue; }
      if (choice === "skip") { plan.skipped.push(item.path); continue; }
      if (choice === "rename") target = renamedPath(target, candidate => taken.has(folded(candidate)));
      else { delete files[existing]; taken.delete(folded(existing)); plan.replaced.push(target); }
    }
    if (item.text === undefined) { plan.error ??= `${item.path} has not been read yet.`; continue; }
    if (!plan.replaced.includes(target)) plan.added.push(target);
    files[target] = item.text; taken.set(folded(target), target); receipt.paths[item.path] = target;
  }
  if (choices.mode === "replace") plan.removed = Object.keys(current.files).filter(path => !(path in files));

  const paths = Object.keys(files);
  plan.fileCount = paths.length; plan.bytes = sourceBytes(files);
  const manifest = paths.includes("Cargo.toml") ? "Cargo.toml" : paths.find(path => path.endsWith("/Cargo.toml"));
  plan.declaredEdition = declaredCargoEdition(manifest ? files[manifest] : undefined);
  const inferred = plan.declaredEdition.kind === "supported" ? plan.declaredEdition.edition : undefined;
  const known = inspection.edition ?? inferred ?? (choices.mode === "add" && plan.declaredEdition.kind === "none" ? current.edition : undefined);
  plan.edition = choices.edition ?? known;
  plan.needsEdition = !plan.edition;
  const mapped = inspection.entryFile ? receipt.paths[inspection.entryFile] : undefined;
  const keptEntry = choices.mode === "add" && current.entryFile in files ? current.entryFile : undefined;
  plan.entryFile = choices.entryFile && choices.entryFile in files ? choices.entryFile : keptEntry ?? mapped ?? entryGuess(paths);
  if (!chosen.length && !plan.error && !plan.skipped.length) plan.error = "Choose at least one file to import.";
  if (plan.needsEdition) {
    plan.readiness = { kind: "needs-choice", message: plan.declaredEdition.kind === "unsupported" ? `Cargo.toml declares edition ${plan.declaredEdition.value}. Choose 2021 or 2024 for this runner; Cargo.toml itself stays as it is.` : plan.declaredEdition.kind === "workspace" ? "Cargo.toml inherits its edition from a workspace that is not resolved here. Choose 2021 or 2024 for this runner." : "Choose 2021 or 2024 for this runner." };
    plan.error ??= plan.readiness.message;
  }
  if (plan.error || plan.needsEdition) return plan;
  // Files from a second source make the first origin untrue for the whole project.
  const sameOrigin = choices.mode === "replace" || !current.origin || (inspection.origin?.url === current.origin.url && inspection.origin?.commit === current.origin.commit);
  const origin = choices.mode === "replace" ? inspection.origin : sameOrigin ? current.origin ?? (Object.keys(current.files).length ? undefined : inspection.origin) : undefined;
  const name = choices.mode === "replace" ? inspection.name ?? current.name : current.name;
  try {
    plan.document = validatePlaygroundDocument({ schemaVersion: 1, name, entryFile: plan.entryFile, edition: plan.edition, files, ...(origin ? { origin } : {}) });
    plan.readiness = projectReadiness(plan.document);
  } catch (error) {
    plan.error = error instanceof Error ? error.message : String(error);
    plan.readiness = { kind: "needs-choice", message: plan.error };
  }
  return plan;
}

export const IMPORT_BUDGET = PLAYGROUND_LIMITS;

export type ImportState = "idle" | "inspecting" | "selecting" | "ready" | "applying" | "complete" | "cancelled" | "error" | "needs_refresh";

/** The edges a prepared import may take. A late result can never reach `applying`. */
const transitions: Record<ImportState, readonly ImportState[]> = {
  idle: ["inspecting", "selecting"], inspecting: ["selecting", "error", "cancelled"], selecting: ["inspecting", "ready", "cancelled", "error"],
  ready: ["selecting", "applying", "needs_refresh", "cancelled", "error"], applying: ["complete", "needs_refresh", "error"], complete: ["idle"], cancelled: ["idle", "inspecting", "selecting"], error: ["idle", "inspecting", "selecting"], needs_refresh: ["ready", "selecting", "cancelled", "error"],
};
export const canTransition = (from: ImportState, to: ImportState) => transitions[from].includes(to);

/** Tells apart a current preparation from one the user has abandoned. */
export class ImportOperations {
  private current = 0;
  private controller: AbortController | null = null;
  begin(): { id: number; signal: AbortSignal } {
    this.controller?.abort();
    this.controller = new AbortController();
    return { id: ++this.current, signal: this.controller.signal };
  }
  cancel() { this.current++; this.controller?.abort(); this.controller = null; }
  isCurrent(id: number) { return id === this.current; }
}

export type ApplyOutcome = { status: "applied"; document: PlaygroundDocument } | { status: "needs_refresh" } | { status: "blocked"; reason: string };

/** Decides whether a plan may be applied to the project as it is right now. */
export function checkImportPlan(plan: ImportPlan, live: PlaygroundDocument, shared: boolean): ApplyOutcome {
  if (!plan.document) return { status: "blocked", reason: plan.error ?? "This import is not ready." };
  if (shared && plan.removed.length) return { status: "blocked", reason: "Replacing a shared project could lose a participant's unsent edit. Copy it to a local draft first, then publish the copy as a new room." };
  if (documentRevision(live) !== plan.baseRevision) return { status: "needs_refresh" };
  return { status: "applied", document: plan.document };
}
