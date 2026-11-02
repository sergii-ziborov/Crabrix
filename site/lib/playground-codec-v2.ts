import * as Y from "yjs";
import { replaceText } from "./playground-collab.ts";
import { base64url } from "./playground-crypto.ts";
import { PLAYGROUND_LIMITS, isValidSourcePath, isValidSourceText, sourceOrigin, validProjectName, validatePlaygroundDocument, type PlaygroundDocument } from "./playground-document.ts";
import { insideFolder } from "./playground-file-ops.ts";

// Format v2 of a shared Playground (docs/playground-r2-design.md). Text lives in a
// root Y.Text per stable file ID, so a rename or a delete never moves or drops text:
//   meta        schemaVersion: 2, name, edition, origin?, entryFileId
//   entries     fileId -> Y.Map { path, deleted?, digest?, purged? }
//   t:<fileId>  the file's text
//   ops         operationId -> { hash, at }, for retried agent operations
// Reading never throws and never writes; concurrent edits that collide are shown
// as conflict names or recovery rows, and only running the project is blocked.

export const PROJECT_LIMITS = Object.freeze({
  recoveryRows: 16, recoveryBytes: 96 * 1024, records: 64, operationRecords: 64,
  /** Agent tools take up to 32 operations a call; the app's whole-project sync needs more. */
  operationsPerCall: 32, operationsPerPlan: 128,
});

export type ProjectFile = { id: string; path: string; requestedPath: string; text: string };
export type RecoveryRow = { id: string; path: string; text: string; bytes: number; conflict: boolean; orphan: boolean };
export type BlockedReason = "no-files" | "no-entry" | "files" | "file-bytes" | "source-bytes" | "text";
export type ProjectState = {
  name: string; edition: "2021" | "2024"; origin?: PlaygroundDocument["origin"];
  /** Unique, valid paths in code-unit order. `requestedPath` differs only for a conflict. */
  files: ProjectFile[];
  recovery: RecoveryRow[];
  entryId: string | null; entryFallback: boolean;
  /** Empty when the project can run. Editing and recovery stay available either way. */
  blocked: BlockedReason[];
  /** File records ever created in this room, including cleared ones. */
  records: number;
};

const encoder = new TextEncoder();
const byteLength = (text: string) => encoder.encode(text).byteLength;
const codeUnitOrder = (a: string, b: string) => a < b ? -1 : a > b ? 1 : 0;
const byId = <T extends { id: string }>(a: T, b: T) => codeUnitOrder(a.id, b.id);
const canonical = (path: string) => path.normalize("NFC").toLowerCase();
const own = (record: object, key: string) => Object.prototype.hasOwnProperty.call(record, key);

export const isFileId = (value: unknown): value is string => typeof value === "string" && /^[A-Za-z0-9_-]{22}$/.test(value);

/** 64-bit FNV-1a over UTF-8, in 16-bit limbs so JavaScriptCore needs no BigInt. Not a security boundary. */
export function fingerprint(text: string): string {
  let h0 = 0x2325, h1 = 0x8422, h2 = 0x9ce4, h3 = 0xcbf2;
  for (const byte of encoder.encode(text)) {
    h0 ^= byte;
    const t0 = h0 * 0x1b3, t1 = h1 * 0x1b3 + (t0 >>> 16), t2 = h2 * 0x1b3 + h0 * 0x100 + (t1 >>> 16), t3 = h3 * 0x1b3 + h1 * 0x100 + (t2 >>> 16);
    h0 = t0 & 0xffff; h1 = t1 & 0xffff; h2 = t2 & 0xffff; h3 = t3 & 0xffff;
  }
  return [h3, h2, h1, h0].map(limb => limb.toString(16).padStart(4, "0")).join("");
}

const longFingerprint = (text: string) => fingerprint("\u0001" + text) + fingerprint("\u0002" + text);

export type PlanErrorCode = "invalid-operation" | "not-found" | "invalid-path" | "path-taken" | "limit" | "recovery-budget" | "stale" | "plan-changed" | "operation-conflict";

export class PlanError extends Error {
  code: PlanErrorCode;
  constructor(code: PlanErrorCode, message: string) { super(message); this.code = code; }
}

// Reading

type Entry = { id: string; path: string; deleted: boolean; purged: boolean; digest: string | null; text: string };
type Model = { name: unknown; edition: unknown; origin: unknown; entryFileId: unknown; entries: Entry[]; orphans: { id: string; text: string }[] };

// Root types are looked up without creating them: a read must leave the document as it was.
function rootMap(doc: Y.Doc, name: string): Y.Map<unknown> | null {
  if (!doc.share.has(name)) return null;
  try { return doc.getMap<unknown>(name); } catch { return null; }
}

function rootText(doc: Y.Doc, name: string): string {
  if (!doc.share.has(name)) return "";
  try { return doc.getText(name).toString(); } catch { return ""; }
}

function readModel(doc: Y.Doc): Model {
  const meta = rootMap(doc, "meta"), entries: Entry[] = [], known = new Set<string>();
  for (const [id, value] of rootMap(doc, "entries") ?? []) {
    if (!isFileId(id) || !(value instanceof Y.Map)) continue;
    const path = value.get("path"), digest = value.get("digest");
    if (typeof path !== "string") continue;
    known.add(id);
    entries.push({ id, path, deleted: value.get("deleted") === true, purged: value.get("purged") === true, digest: typeof digest === "string" ? digest : null, text: rootText(doc, "t:" + id) });
  }
  const orphans: Model["orphans"] = [];
  for (const name of doc.share.keys()) {
    const id = name.slice(2);
    if (name.startsWith("t:") && isFileId(id) && !known.has(id)) orphans.push({ id, text: rootText(doc, name) });
  }
  return { name: meta?.get("name"), edition: meta?.get("edition"), origin: meta?.get("origin"), entryFileId: meta?.get("entryFileId"), entries, orphans };
}

/** Claims paths in order; a later path that collides with an earlier one is refused. */
function pathClaims() {
  const files = new Set<string>(), folders = new Map<string, string>();
  return (path: string): boolean => {
    const parts = path.split("/"), key = canonical(path);
    if (files.has(key) || folders.has(key)) return false;
    for (let depth = 1; depth < parts.length; depth++) {
      const parent = parts.slice(0, depth).join("/"), spelling = folders.get(canonical(parent));
      if (files.has(canonical(parent)) || spelling !== undefined && spelling !== parent.normalize("NFC")) return false;
    }
    files.add(key);
    for (let depth = 1; depth < parts.length; depth++) folders.set(canonical(parts.slice(0, depth).join("/")), parts.slice(0, depth).join("/").normalize("NFC"));
    return true;
  };
}

function fallbackPath(entry: Entry, take: (path: string) => boolean): string {
  const short = entry.id.slice(0, 8), name = entry.path.split("/").at(-1)!;
  const candidates = [...(isValidSourcePath(entry.path) ? [`conflict-${short}-${name}`] : []), `recovered-${short}.txt`, `recovered-${entry.id}.txt`];
  for (const path of candidates) if (isValidSourcePath(path) && take(path)) return path;
  for (let n = 2; ; n++) if (take(`recovered-${entry.id}-${n}.txt`)) return `recovered-${entry.id}-${n}.txt`;
}

function project(model: Model): ProjectState {
  // The lower file ID keeps a contested path; every client orders IDs the same way.
  const live = model.entries.filter(entry => !entry.deleted).sort(byId), take = pathClaims(), shown = new Map<string, string>(), contested: Entry[] = [];
  for (const entry of live) if (isValidSourcePath(entry.path) && take(entry.path)) shown.set(entry.id, entry.path); else contested.push(entry);
  for (const entry of contested) shown.set(entry.id, fallbackPath(entry, take));
  const files = live.map(entry => ({ id: entry.id, path: shown.get(entry.id)!, requestedPath: entry.path, text: entry.text })).sort((a, b) => codeUnitOrder(a.path, b.path));
  // A deleted file with no text has nothing to recover; `purged` only tells clients to drop Undo.
  const recovery: RecoveryRow[] = [
    ...model.entries.filter(entry => entry.deleted && entry.text).map(entry => ({
      id: entry.id, path: isValidSourcePath(entry.path) ? entry.path : `recovered-${entry.id.slice(0, 8)}.txt`, text: entry.text,
      bytes: byteLength(entry.text), conflict: entry.digest !== fingerprint(entry.text), orphan: false,
    })),
    // An empty root is not recoverable text: a presence cursor alone can create one on a single client.
    ...model.orphans.filter(orphan => orphan.text).map(orphan => ({ id: orphan.id, path: `recovered-${orphan.id.slice(0, 8)}.txt`, text: orphan.text, bytes: byteLength(orphan.text), conflict: false, orphan: true })),
  ].sort(byId);
  const rust = (file: ProjectFile) => file.path.endsWith(".rs");
  const chosen = files.find(file => file.id === model.entryFileId && rust(file)), entry = chosen ?? files.find(rust);
  const sizes = files.map(file => byteLength(file.text)), blocked: BlockedReason[] = [];
  if (!files.length) blocked.push("no-files");
  if (!entry) blocked.push("no-entry");
  if (files.length > PLAYGROUND_LIMITS.files) blocked.push("files");
  if (sizes.some(size => size > PLAYGROUND_LIMITS.fileBytes)) blocked.push("file-bytes");
  if (sizes.reduce((sum, size) => sum + size, 0) > PLAYGROUND_LIMITS.sourceBytes) blocked.push("source-bytes");
  if (files.some(file => !isValidSourceText(file.text))) blocked.push("text");
  let origin: PlaygroundDocument["origin"];
  try { origin = sourceOrigin(model.origin); } catch { origin = undefined; }
  return {
    name: typeof model.name === "string" && validProjectName(model.name) ? model.name.trim() : "playground",
    edition: model.edition === "2021" ? "2021" : "2024", ...(origin ? { origin } : {}),
    files, recovery, entryId: entry?.id ?? null, entryFallback: !chosen && !!entry, blocked, records: model.entries.length,
  };
}

/** Total: any state Yjs accepted reads as a project, with collisions and limits reported in it. */
export function readProject(doc: Y.Doc): ProjectState {
  return project(readModel(doc));
}

/** The format is bound when a room is created; a later write to meta does not change it. */
export const schemaVersionOf = (doc: Y.Doc) => rootMap(doc, "meta")?.get("schemaVersion");

const blockedMessages: Record<BlockedReason, string> = {
  "no-files": "The project has no files. Restore or create one to run it.",
  "no-entry": "Choose a Rust source entry file to run the project.",
  files: "A Playground supports 1–16 source files. Remove files to run it.",
  "file-bytes": "A file exceeds 64 KiB. Shorten it to run the project.",
  "source-bytes": "The source project exceeds 128 KiB. Remove text to run it.",
  text: "A file contains characters the compiler cannot read.",
};

/** Strict: the runnable document, or an error while the project is blocked. Export uses `readProject`. */
export function documentFromProject(state: ProjectState): PlaygroundDocument {
  if (state.blocked.length) throw new Error(blockedMessages[state.blocked[0]]);
  const files: Record<string, string> = Object.create(null);
  for (const file of state.files) files[file.path] = file.text;
  const entryFile = state.files.find(file => file.id === state.entryId)!.path;
  return validatePlaygroundDocument({ schemaVersion: 1, name: state.name, entryFile, edition: state.edition, files, ...(state.origin ? { origin: state.origin } : {}) });
}

/** Changes whenever the files, their IDs, paths or recovery rows change. */
export function projectRevision(state: ProjectState): string {
  return longFingerprint(JSON.stringify([state.name, state.edition, state.origin ?? null, state.entryId,
    state.files.map(file => [file.id, file.path, file.requestedPath, file.text]), state.recovery.map(row => [row.id, row.path, row.conflict, row.orphan, row.text])]));
}

const randomBytes = (length: number) => crypto.getRandomValues(new Uint8Array(length));

function newFileId(taken: (id: string) => boolean, random: (length: number) => Uint8Array): string {
  for (let attempt = 0; attempt < 8; attempt++) {
    const id = base64url(random(16));
    if (isFileId(id) && !taken(id)) return id;
  }
  throw new Error("Could not create a file ID.");
}

/** A new v2 document from a v1 projection, as a local project is published. */
export function createProjectDoc(source: PlaygroundDocument, random = randomBytes): Y.Doc {
  const value = validatePlaygroundDocument(source), doc = new Y.Doc(), ids = new Set<string>();
  doc.transact(() => {
    const meta = doc.getMap<unknown>("meta"), entries = doc.getMap<unknown>("entries");
    meta.set("schemaVersion", 2); meta.set("name", value.name); meta.set("edition", value.edition);
    if (value.origin) meta.set("origin", value.origin);
    for (const [path, text] of Object.entries(value.files)) {
      const id = newFileId(id => ids.has(id), random), record = new Y.Map<unknown>();
      ids.add(id); entries.set(id, record); record.set("path", path);
      if (text) doc.getText("t:" + id).insert(0, text);
      if (path === value.entryFile) meta.set("entryFileId", id);
    }
  }, "initial");
  return doc;
}

// Operations

export type FileRef = { id: string } | { path: string };
export type ProjectOperation =
  | { kind: "create"; path: string; text: string }
  | { kind: "copy"; file: FileRef; path: string }
  | { kind: "write"; file: FileRef; text: string }
  | { kind: "move"; file: FileRef; path: string }
  | { kind: "moveFolder"; from: string; to: string }
  | { kind: "delete"; file: FileRef }
  | { kind: "deleteFolder"; path: string }
  | { kind: "restore"; id: string; path?: string }
  | { kind: "purge"; id: string }
  | { kind: "setEntry"; file: FileRef }
  | { kind: "setEdition"; edition: "2021" | "2024" }
  | { kind: "setName"; name: string };

/** Only changed fields are written, so an unrelated concurrent rename or delete is never overwritten. */
export type EntryChange = { id: string; record: boolean; path?: string; deleted?: boolean; purged?: boolean; digest?: string; text?: string };

export type OperationPlan = {
  /** The revision the plan read, and a hash of that revision with the operations. */
  revision: string; planHash: string; operationsHash: string;
  changes: EntryChange[];
  meta: { name?: string; edition?: "2021" | "2024"; entryFileId?: string };
  created: string[]; written: string[]; moved: { id: string; from: string; to: string }[];
  deleted: string[]; restored: string[]; purged: string[];
  /** Files that keep a conflict name; only when collisions are allowed. */
  conflicts: string[];
  /** A Rust file moved: `mod`, `#[path]` and `include_str!` are not rewritten, so suggest Check. */
  checkSuggested: boolean;
  before: ProjectState; after: ProjectState;
};

export type PlanOptions = {
  /** "allow" keeps a contested path as a visible conflict instead of refusing, for the app's whole-project sync. */
  collisions?: "refuse" | "allow";
  random?: (length: number) => Uint8Array;
};

const field = (value: unknown, name: string): string => {
  if (typeof value !== "string") throw new PlanError("invalid-operation", `The operation needs ${name} as text.`);
  return value;
};

function fileRef(value: unknown): FileRef {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    const { id, path } = value as Record<string, unknown>;
    if (typeof id === "string" && path === undefined) return { id };
    if (typeof path === "string" && id === undefined) return { path };
  }
  throw new PlanError("invalid-operation", "Name a file by its id or by its path.");
}

/** Rebuilds each operation with a fixed shape, so equal operations hash equally. */
export function normalizeOperations(input: readonly unknown[], maximum: number = PROJECT_LIMITS.operationsPerPlan): ProjectOperation[] {
  if (!Array.isArray(input) || input.length < 1 || input.length > maximum) throw new PlanError("invalid-operation", `Send 1–${maximum} file operations.`);
  return input.map((item): ProjectOperation => {
    if (!item || typeof item !== "object" || Array.isArray(item)) throw new PlanError("invalid-operation", "Each file operation must be an object.");
    const value = item as Record<string, unknown>;
    switch (value.kind) {
      case "create": return { kind: "create", path: field(value.path, "path"), text: value.text === undefined ? "" : field(value.text, "text") };
      case "copy": return { kind: "copy", file: fileRef(value.file), path: field(value.path, "path") };
      case "write": return { kind: "write", file: fileRef(value.file), text: field(value.text, "text") };
      case "move": return { kind: "move", file: fileRef(value.file), path: field(value.path, "path") };
      case "moveFolder": return { kind: "moveFolder", from: field(value.from, "from"), to: field(value.to, "to") };
      case "delete": return { kind: "delete", file: fileRef(value.file) };
      case "deleteFolder": return { kind: "deleteFolder", path: field(value.path, "path") };
      case "restore": return { kind: "restore", id: field(value.id, "id"), ...(value.path === undefined ? {} : { path: field(value.path, "path") }) };
      case "purge": return { kind: "purge", id: field(value.id, "id") };
      case "setEntry": return { kind: "setEntry", file: fileRef(value.file) };
      case "setEdition":
        if (value.edition !== "2021" && value.edition !== "2024") throw new PlanError("invalid-operation", "Choose Rust edition 2021 or 2024.");
        return { kind: "setEdition", edition: value.edition };
      case "setName": return { kind: "setName", name: field(value.name, "name") };
      default: throw new PlanError("invalid-operation", "Unknown file operation.");
    }
  });
}

const totalBytes = (rows: readonly { text: string }[]) => rows.reduce((sum, row) => sum + byteLength(row.text), 0);

function planModel(model: Model, operations: ProjectOperation[], options: PlanOptions): OperationPlan {
  const before = project(model), random = options.random ?? randomBytes;
  const work: Model = { ...model, entries: model.entries.map(entry => ({ ...entry })), orphans: model.orphans.map(orphan => ({ ...orphan })) };
  const touched = new Set<string>(), created: string[] = [], written: string[] = [], deleted: string[] = [], restored: string[] = [], purged: string[] = [];
  const entryOf = (id: string) => work.entries.find(entry => entry.id === id);
  const shownPath = (state: ProjectState, id: string) => state.files.find(file => file.id === id)?.path;

  const live = (ref: FileRef, state: ProjectState): Entry => {
    let id: string | undefined;
    if ("id" in ref) id = ref.id;
    else {
      const requested = state.files.filter(file => file.requestedPath === ref.path);
      id = state.files.find(file => file.path === ref.path)?.id ?? (requested.length === 1 ? requested[0].id : undefined);
    }
    const entry = id === undefined ? undefined : entryOf(id);
    if (!entry || entry.deleted) throw new PlanError("not-found", "This file no longer exists.");
    return entry;
  };
  // Every other live file keeps its shown path; the targets must fit around them.
  const reserve = (state: ProjectState, moving: ReadonlySet<string>, paths: string[]) => {
    for (const path of paths) if (!isValidSourcePath(path)) throw new PlanError("invalid-path", `Unsupported source path: ${path.slice(0, 80)}`);
    if (options.collisions === "allow") return;
    const take = pathClaims();
    for (const file of state.files) if (!moving.has(file.id)) take(file.path);
    for (const path of paths) if (!take(path)) throw new PlanError("path-taken", paths.length > 1 ? `${path} already exists. No files were moved.` : "A file with this path already exists.");
  };
  const checkText = (text: string) => {
    if (!isValidSourceText(text)) throw new PlanError("invalid-operation", "Each file must contain well-formed UTF-8 text; binary/media files are not accepted.");
  };
  const newEntry = (path: string, text: string) => {
    const id = newFileId(id => !!entryOf(id) || work.orphans.some(orphan => orphan.id === id), random);
    work.entries.push({ id, path, deleted: false, purged: false, digest: null, text });
    touched.add(id); created.push(id);
  };
  const remove = (entry: Entry) => {
    entry.deleted = true; entry.digest = fingerprint(entry.text); deleted.push(entry.id);
  };

  for (const operation of operations) {
    const state = project(work);
    switch (operation.kind) {
      case "create":
      case "copy": {
        const text = operation.kind === "create" ? operation.text : live(operation.file, state).text;
        checkText(text); reserve(state, new Set(), [operation.path]); newEntry(operation.path, text);
        break;
      }
      case "write": {
        // By ID a write also reaches a recovery row, like late typing does; by path only a live file.
        const orphan = "id" in operation.file ? work.orphans.find(item => item.id === (operation.file as { id: string }).id) : undefined;
        const target = orphan ?? ("id" in operation.file && entryOf(operation.file.id) || live(operation.file, state));
        checkText(operation.text); target.text = operation.text; written.push(target.id);
        break;
      }
      case "move": {
        const entry = live(operation.file, state);
        if (operation.path === shownPath(state, entry.id)) throw new PlanError("invalid-operation", "Enter a different path.");
        reserve(state, new Set([entry.id]), [operation.path]);
        entry.path = operation.path; touched.add(entry.id);
        break;
      }
      case "moveFolder": {
        const { from, to } = operation;
        if (!from || !to) throw new PlanError("invalid-path", "Enter a folder path.");
        if (to === from) throw new PlanError("invalid-operation", "Enter a different path.");
        if (insideFolder(to, from)) throw new PlanError("invalid-operation", "A folder cannot move inside itself.");
        const inside = state.files.filter(file => insideFolder(file.path, from));
        if (!inside.length) throw new PlanError("not-found", "This folder no longer exists.");
        const targets = inside.map(file => to + file.path.slice(from.length));
        reserve(state, new Set(inside.map(file => file.id)), targets);
        inside.forEach((file, index) => { entryOf(file.id)!.path = targets[index]; touched.add(file.id); });
        break;
      }
      case "delete":
      case "deleteFolder": {
        const gone = operation.kind === "delete" ? [live(operation.file, state)] : state.files.filter(file => insideFolder(file.path, operation.path)).map(file => entryOf(file.id)!);
        if (!gone.length) throw new PlanError("not-found", "This no longer exists.");
        gone.forEach(remove);
        break;
      }
      case "restore": {
        const entry = entryOf(operation.id), orphan = work.orphans.find(item => item.id === operation.id && item.text);
        if (!(entry?.deleted && entry.text) && !orphan) throw new PlanError("not-found", "There is nothing to restore for this file.");
        const path = operation.path ?? entry?.path ?? `recovered-${operation.id.slice(0, 8)}.txt`;
        if (operation.path === undefined && !isValidSourcePath(path)) throw new PlanError("path-taken", "Choose a path to restore this file.");
        try { reserve(state, new Set(), [path]); }
        catch (error) { throw error instanceof PlanError && error.code === "path-taken" ? new PlanError("path-taken", "This path is taken. Choose a new path to restore the file.") : error; }
        if (orphan) { work.entries.push({ id: orphan.id, path, deleted: false, purged: false, digest: null, text: orphan.text }); work.orphans = work.orphans.filter(item => item !== orphan); }
        else Object.assign(entry!, { deleted: false, purged: false, path });
        touched.add(operation.id); restored.push(operation.id);
        break;
      }
      case "purge": {
        const entry = entryOf(operation.id), orphan = work.orphans.find(item => item.id === operation.id && item.text);
        if (orphan) orphan.text = "";
        else if (entry?.deleted && entry.text) Object.assign(entry, { purged: true, digest: fingerprint(""), text: "" });
        else throw new PlanError("not-found", "Only a file in recovery can be cleared.");
        purged.push(operation.id);
        break;
      }
      case "setEntry": {
        const entry = live(operation.file, state);
        if (!shownPath(state, entry.id)!.endsWith(".rs")) throw new PlanError("invalid-operation", "Choose a Rust source entry file.");
        work.entryFileId = entry.id;
        break;
      }
      case "setEdition": work.edition = operation.edition; break;
      case "setName": {
        const name = operation.name.trim();
        if (!validProjectName(name)) throw new PlanError("invalid-operation", "Use a project name of up to 80 characters without control characters.");
        work.name = name;
        break;
      }
    }
  }

  let after = project(work);
  // Deleting or renaming the entry picks the next Rust file on purpose, not as a fallback.
  if (after.entryFallback && after.entryId && !before.entryFallback) { work.entryFileId = after.entryId; after = project(work); }

  // One failed check refuses the whole plan. Limits only bind what the plan grows, so a
  // project that concurrent edits pushed over a limit can still be reduced.
  const grew = (reason: BlockedReason) => after.blocked.includes(reason) && !before.blocked.includes(reason);
  if (grew("no-files")) throw new PlanError("limit", "Keep at least one file in the project.");
  if (grew("no-entry")) throw new PlanError("limit", "Keep at least one Rust source file to run the project.");
  if (grew("text")) throw new PlanError("invalid-operation", "A file contains characters the compiler cannot read.");
  if (after.files.length > Math.max(PLAYGROUND_LIMITS.files, before.files.length)) throw new PlanError("limit", "A Playground supports 1–16 source files.");
  const sizeBefore = new Map(before.files.map(file => [file.id, byteLength(file.text)]));
  if (after.files.some(file => byteLength(file.text) > Math.max(PLAYGROUND_LIMITS.fileBytes, sizeBefore.get(file.id) ?? 0))) throw new PlanError("limit", "Each file must be up to 64 KiB.");
  if (totalBytes(after.files) > Math.max(PLAYGROUND_LIMITS.sourceBytes, totalBytes(before.files))) throw new PlanError("limit", "The source project exceeds 128 KiB.");
  if (after.records > Math.max(PROJECT_LIMITS.records, before.records)) throw new PlanError("limit", "This room has used its 64 file records. Start a new room to add more files.");
  if (deleted.length && (after.recovery.length > Math.max(PROJECT_LIMITS.recoveryRows, before.recovery.length) || totalBytes(after.recovery) > Math.max(PROJECT_LIMITS.recoveryBytes, totalBytes(before.recovery))))
    throw new PlanError("recovery-budget", "Recovery is full. Clear or download recovered files before deleting more.");
  const conflicted = (id: string) => after.files.some(file => file.id === id && file.path !== file.requestedPath);
  const conflicts = after.files.filter(file => conflicted(file.id) && (touched.has(file.id) || before.files.some(old => old.id === file.id && old.path === old.requestedPath))).map(file => file.id);
  if (conflicts.length && options.collisions !== "allow") throw new PlanError("path-taken", "A file with this path already exists.");

  const originalEntry = new Map(model.entries.map(entry => [entry.id, entry]));
  const originalText = new Map([...model.orphans.map(orphan => [orphan.id, orphan.text] as const), ...model.entries.map(entry => [entry.id, entry.text] as const)]);
  const changes: EntryChange[] = [];
  for (const entry of work.entries) {
    const old = originalEntry.get(entry.id), change: EntryChange = { id: entry.id, record: !old };
    if (old?.path !== entry.path) change.path = entry.path;
    if (old ? old.deleted !== entry.deleted : entry.deleted) change.deleted = entry.deleted;
    if (old ? old.purged !== entry.purged : entry.purged) change.purged = entry.purged;
    if (entry.digest !== null && old?.digest !== entry.digest) change.digest = entry.digest;
    if ((originalText.get(entry.id) ?? "") !== entry.text) change.text = entry.text;
    if (Object.keys(change).length > 2) changes.push(change);
  }
  for (const orphan of work.orphans) if (originalText.get(orphan.id) !== orphan.text) changes.push({ id: orphan.id, record: false, text: orphan.text });
  const meta: OperationPlan["meta"] = {};
  if (work.name !== model.name) meta.name = work.name as string;
  if (work.edition !== model.edition) meta.edition = work.edition as "2021" | "2024";
  if (work.entryFileId !== model.entryFileId) meta.entryFileId = work.entryFileId as string;

  const moved = after.files.flatMap(file => {
    const from = shownPath(before, file.id);
    return from !== undefined && from !== file.path && changes.some(change => change.id === file.id && change.path !== undefined) ? [{ id: file.id, from, to: file.path }] : [];
  });
  const revision = projectRevision(before), operationsHash = longFingerprint(JSON.stringify(operations));
  return {
    revision, planHash: longFingerprint(revision + "\n" + operationsHash), operationsHash, changes, meta,
    created, written, moved, deleted, restored, purged, conflicts,
    checkSuggested: moved.some(move => move.from.endsWith(".rs") || move.to.endsWith(".rs")), before, after,
  };
}

/** Plans without writing: the preview for a dialog or `crabrix_plan_changes`. */
export function planOperations(doc: Y.Doc, operations: readonly unknown[], options: PlanOptions = {}): OperationPlan {
  return planModel(readModel(doc), normalizeOperations(operations), options);
}

export type ApplyOptions = PlanOptions & {
  /** "structure", "import" or "mcp"; never the editor binding's origin, so Undo leaves operations alone. */
  origin: string;
  /** Agent mode: the plan must have read this revision, and match the reviewed plan. */
  expectedRevision?: string; planHash?: string;
  /** Agent mode: a retried operation is recognised from the record in the document. */
  operationId?: string; now?: number;
};

export type ApplyResult = { alreadyApplied: true; revision: string } | { alreadyApplied: false; plan: OperationPlan; revision: string };

const isOperationRecord = (value: unknown): value is { hash: string; at: number } =>
  !!value && typeof value === "object" && typeof (value as Record<string, unknown>).hash === "string" && typeof (value as Record<string, unknown>).at === "number";

/** Plans and applies in one transaction. A refused plan leaves the document unchanged. */
export function applyOperations(doc: Y.Doc, operations: readonly unknown[], options: ApplyOptions): ApplyResult {
  if (typeof options.origin !== "string" || !options.origin) throw new Error("File operations need a named transaction origin.");
  const normalized = normalizeOperations(operations);
  if (options.operationId !== undefined) {
    if (!/^[A-Za-z0-9_-]{8,64}$/.test(options.operationId)) throw new PlanError("invalid-operation", "Use an operation ID of 8–64 letters, digits, - or _.");
    const record = rootMap(doc, "ops")?.get(options.operationId);
    if (record !== undefined) {
      if (isOperationRecord(record) && record.hash === longFingerprint(JSON.stringify(normalized))) return { alreadyApplied: true, revision: projectRevision(readProject(doc)) };
      throw new PlanError("operation-conflict", "This operation ID was already used for different changes. Nothing was changed.");
    }
  }
  const plan = planModel(readModel(doc), normalized, options);
  if (options.expectedRevision !== undefined && plan.revision !== options.expectedRevision) throw new PlanError("stale", "The project changed after it was read. Read it again and plan the changes again; nothing was changed.");
  if (options.planHash !== undefined && plan.planHash !== options.planHash) throw new PlanError("plan-changed", "These operations differ from the reviewed plan. Plan them again; nothing was changed.");
  // Every lookup that can throw happens before the first write: Yjs keeps a partial transaction.
  const entries = doc.getMap<unknown>("entries"), meta = doc.getMap<unknown>("meta"), records = options.operationId === undefined ? null : doc.getMap<unknown>("ops");
  const texts = new Map(plan.changes.filter(change => change.text !== undefined).map(change => [change.id, doc.getText("t:" + change.id)]));
  doc.transact(() => {
    for (const change of plan.changes) {
      let record = entries.get(change.id);
      if (change.path !== undefined || change.deleted !== undefined || change.purged !== undefined || change.digest !== undefined) {
        if (change.record || !(record instanceof Y.Map)) { record = new Y.Map<unknown>(); entries.set(change.id, record); }
        for (const key of ["path", "deleted", "purged", "digest"] as const) if (change[key] !== undefined) (record as Y.Map<unknown>).set(key, change[key]);
      }
      if (change.text !== undefined) replaceText(texts.get(change.id)!, change.text);
    }
    for (const [key, value] of Object.entries(plan.meta)) meta.set(key, value);
    if (records) {
      records.set(options.operationId!, { hash: plan.operationsHash, at: options.now ?? Date.now() });
      const oldest = Array.from(records.entries(), ([key, value]) => ({ key, at: isOperationRecord(value) ? value.at : -Infinity }))
        .filter(({ key }) => key !== options.operationId).sort((a, b) => a.at - b.at || codeUnitOrder(a.key, b.key));
      for (const { key } of oldest.slice(0, Math.max(0, records.size - PROJECT_LIMITS.operationRecords))) records.delete(key);
    }
  }, options.origin);
  return { alreadyApplied: false, plan, revision: projectRevision(plan.after) };
}

// Adapters

/** `crabrix_apply_changes` on a v2 room: an existing path is a write, a new path a create, `text: null` a delete. */
export function operationsFromChanges(state: ProjectState, changes: readonly { path: string; text: string | null }[]): ProjectOperation[] {
  return changes.map(({ path, text }): ProjectOperation => {
    if (text === null) return { kind: "delete", file: { path } };
    const file = state.files.find(item => item.path === path);
    return file ? { kind: "write", file: { id: file.id }, text } : { kind: "create", path, text };
  });
}

/**
 * The app sends its whole project after every change. `baseline` is the path -> file ID map
 * the app last acknowledged: a path it kept still writes to the same file after another
 * participant renamed it, and a path it renamed keeps its file ID. Apply with collisions allowed.
 */
export function operationsFromReplace(state: ProjectState, baseline: Readonly<Record<string, string>>, next: PlaygroundDocument): ProjectOperation[] {
  const text = new Map<string, string>([...state.recovery.map(row => [row.id, row.text] as const), ...state.files.map(file => [file.id, file.text] as const)]);
  const liveIds = new Set(state.files.map(file => file.id)), placed = new Map<string, FileRef>();
  const writes: ProjectOperation[] = [], moves: ProjectOperation[] = [], creates: ProjectOperation[] = [], deletes: ProjectOperation[] = [];
  const added: string[] = [], gone = Object.keys(baseline).filter(path => !own(next.files, path)).sort(codeUnitOrder);
  for (const path of Object.keys(next.files).sort(codeUnitOrder)) {
    const id = own(baseline, path) ? baseline[path] : undefined;
    if (id === undefined || !text.has(id)) { added.push(path); continue; }
    if (text.get(id) !== next.files[path]) writes.push({ kind: "write", file: { id }, text: next.files[path] });
    placed.set(path, { id });
  }
  const used = new Set<string>();
  for (const path of added) {
    const old = gone.find(candidate => !used.has(candidate) && liveIds.has(baseline[candidate]) && text.get(baseline[candidate]) === next.files[path]);
    if (old === undefined) { creates.push({ kind: "create", path, text: next.files[path] }); placed.set(path, { path }); continue; }
    const id = baseline[old];
    used.add(old); placed.set(path, { id });
    if (state.files.find(file => file.id === id)!.path !== path) moves.push({ kind: "move", file: { id }, path });
  }
  for (const path of gone) if (!used.has(path) && liveIds.has(baseline[path])) deletes.push({ kind: "delete", file: { id: baseline[path] } });
  const meta: ProjectOperation[] = [];
  if (next.name !== state.name) meta.push({ kind: "setName", name: next.name });
  if (next.edition !== state.edition) meta.push({ kind: "setEdition", edition: next.edition });
  const entry = placed.get(next.entryFile);
  if (entry && ("path" in entry || liveIds.has(entry.id) && entry.id !== state.entryId)) meta.push({ kind: "setEntry", file: entry });
  return [...writes, ...deletes, ...moves, ...creates, ...meta];
}
