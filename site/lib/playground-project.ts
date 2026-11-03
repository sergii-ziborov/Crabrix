import * as Y from "yjs";
import { strToU8, zipSync } from "fflate";
import { documentFromY } from "./playground-collab.ts";
import { documentFromProject, readProject, type BlockedReason, type ProjectOperation, type ProjectState, type RecoveryRow } from "./playground-codec-v2.ts";
import type { PlaygroundDocument } from "./playground-document.ts";
import type { FileOperation } from "./playground-file-ops.ts";

// One view over both document formats, so the editor works with a file key:
// the path in format v1 and the stable file ID in format v2.
export type ProjectCodec = 1 | 2;
export type ProjectFileView = { key: string; path: string; text: string; conflict: boolean };
export type ProjectView = {
  codec: ProjectCodec;
  /** The files as a path map. Validated in v1; in v2 it may be blocked from running. */
  document: PlaygroundDocument;
  files: ProjectFileView[];
  entryKey: string | null;
  recovery: RecoveryRow[];
  blocked: BlockedReason[];
};

/** v1 throws while the document is invalid or still empty; v2 always reads. */
export function readView(doc: Y.Doc, codec: ProjectCodec): ProjectView {
  if (codec === 1) {
    const document = documentFromY(doc);
    return { codec, document, files: Object.entries(document.files).map(([path, text]) => ({ key: path, path, text, conflict: false })), entryKey: document.entryFile, recovery: [], blocked: [] };
  }
  return viewOfState(readProject(doc));
}

export function viewOfState(state: ProjectState): ProjectView {
  const files: Record<string, string> = Object.create(null);
  for (const file of state.files) files[file.path] = file.text;
  const entry = state.files.find(file => file.id === state.entryId);
  return {
    codec: 2, files: state.files.map(file => ({ key: file.id, path: file.path, text: file.text, conflict: file.path !== file.requestedPath })),
    document: { schemaVersion: 1, name: state.name, entryFile: entry?.path ?? "", edition: state.edition, files, ...(state.origin ? { origin: state.origin } : {}) },
    entryKey: state.entryId, recovery: state.recovery, blocked: state.blocked,
  };
}

/** Files whose text was cleared in this transaction; their Undo must not bring it back. */
export function purgedFileIds(doc: Y.Doc, transaction: Y.Transaction): string[] {
  if (!doc.share.has("entries")) return [];
  const entries = doc.getMap<unknown>("entries"), ids: string[] = [];
  transaction.changed.forEach((keys, type) => {
    const id = type._item?.parentSub;
    if (type instanceof Y.Map && type.parent === entries && keys.has("purged") && type.get("purged") === true && id) ids.push(id);
  });
  return ids;
}

/** The project the compiler and runtime receive. Throws while a v2 project is blocked. */
export function runnableDocument(doc: Y.Doc, codec: ProjectCodec): PlaygroundDocument {
  return codec === 1 ? documentFromY(doc) : documentFromProject(readProject(doc));
}

/** The editor's text for a file key, or null when that file is not in the project. */
export function fileText(doc: Y.Doc, view: ProjectView, key: string): Y.Text | null {
  if (!view.files.some(file => file.key === key)) return null;
  if (view.codec === 1) { const text = doc.getMap<Y.Text>("files").get(key); return text instanceof Y.Text ? text : null; }
  try { return doc.getText("t:" + key); } catch { return null; }
}

/** Live files, and recovered text in its own folder so nothing in recovery is lost on export. */
export function exportArchive(view: ProjectView): Uint8Array {
  const files: Record<string, Uint8Array> = {};
  for (const file of view.files) files[file.path] = strToU8(file.text);
  for (const row of view.recovery) files[`crabrix-recovery/${row.id.slice(0, 8)}-${row.path.replaceAll("/", "__")}`] = strToU8(row.text);
  return zipSync(files);
}

const clean = (path: string) => path.trim().replace(/^\/+|\/+$/g, "");

/** A tree or dialog action as v2 operations. Files are named by their shown path. */
export function treeOperations(operation: FileOperation): ProjectOperation[] {
  switch (operation.kind) {
    case "create": return [{ kind: "create", path: clean(operation.path), text: "" }];
    case "duplicate": return [{ kind: "copy", file: { path: operation.from }, path: clean(operation.to) }];
    case "rename": return [{ kind: "move", file: { path: operation.from }, path: clean(operation.to) }];
    case "rename-folder": return [{ kind: "moveFolder", from: clean(operation.from), to: clean(operation.to) }];
    // A chosen entry is set first; without a choice the plan picks the next Rust file.
    case "delete-file": return [...(operation.entryFile ? [{ kind: "setEntry", file: { path: operation.entryFile } } as const] : []), { kind: "delete", file: { path: operation.path } }];
    case "delete-folder": return [...(operation.entryFile ? [{ kind: "setEntry", file: { path: operation.entryFile } } as const] : []), { kind: "deleteFolder", path: clean(operation.path) }];
  }
}

export const blockedSummary: Record<BlockedReason, string> = {
  "no-files": "The project has no files.",
  "no-entry": "No Rust source file can be the entry.",
  files: "More than 16 files.",
  "file-bytes": "A file is larger than 64 KiB.",
  "source-bytes": "The project is larger than 128 KiB.",
  text: "A file has characters the compiler cannot read.",
};
