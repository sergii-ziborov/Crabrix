import { validatePlaygroundDocument, type PlaygroundDocument } from "./playground-document.ts";

export type TreeNode = { kind: "folder"; name: string; path: string; children: TreeNode[] } | { kind: "file"; name: string; path: string };

// Plain code-unit order, so every client and locale lists the same tree.
const byName = (a: TreeNode, b: TreeNode) => {
  if (a.kind !== b.kind) return a.kind === "folder" ? -1 : 1;
  const left = a.name.toLowerCase(), right = b.name.toLowerCase();
  return left < right ? -1 : left > right ? 1 : a.name < b.name ? -1 : a.name > b.name ? 1 : 0;
};

/** The tree is derived from path prefixes; the document stores no folders. */
export function buildFileTree(paths: Iterable<string>): TreeNode[] {
  const root: TreeNode[] = [], folders = new Map<string, TreeNode[]>([["", root]]);
  for (const path of paths) {
    const parts = path.split("/");
    for (let depth = 0; depth < parts.length - 1; depth++) {
      const folder = parts.slice(0, depth + 1).join("/");
      if (!folders.has(folder)) {
        const children: TreeNode[] = [];
        folders.set(folder, children);
        folders.get(parts.slice(0, depth).join("/"))!.push({ kind: "folder", name: parts[depth], path: folder, children });
      }
    }
    folders.get(parts.slice(0, -1).join("/"))!.push({ kind: "file", name: parts.at(-1)!, path });
  }
  for (const children of folders.values()) children.sort(byName);
  return root;
}

export type FlatTreeItem = { node: TreeNode; depth: number; parent: string | null };

export function flattenTree(nodes: TreeNode[], expanded: ReadonlySet<string>, depth = 0, parent: string | null = null): FlatTreeItem[] {
  return nodes.flatMap(node => [{ node, depth, parent }, ...(node.kind === "folder" && expanded.has(node.path) ? flattenTree(node.children, expanded, depth + 1, node.path) : [])]);
}

/** Folders that must be open for a search result or the active file to show. */
export function ancestors(path: string): string[] {
  const parts = path.split("/");
  return parts.slice(0, -1).map((_, index) => parts.slice(0, index + 1).join("/"));
}

export function matchingPaths(paths: Iterable<string>, query: string): string[] {
  const needle = query.trim().toLowerCase();
  return Array.from(paths).filter(path => path.toLowerCase().includes(needle));
}

export type FileOperation =
  | { kind: "create"; path: string }
  | { kind: "rename"; from: string; to: string }
  | { kind: "duplicate"; from: string; to: string }
  | { kind: "delete-file"; path: string; entryFile?: string }
  | { kind: "rename-folder"; from: string; to: string }
  | { kind: "delete-folder"; path: string; entryFile?: string };

export type FilePlan = {
  document: PlaygroundDocument;
  /** Old path to new path, for the selection, breakpoints and editor history. */
  moved: Record<string, string>;
  removed: string[];
  added: string[];
  movesRustSource: boolean;
};

export const insideFolder = (path: string, folder: string) => path.startsWith(folder + "/");

/** Removing a file or moving a path loses another participant's unsent edit in format v1. */
export const isDestructiveInSharedRoom = (operation: FileOperation) => operation.kind === "rename" || operation.kind === "rename-folder" || operation.kind === "delete-file" || operation.kind === "delete-folder";

const clean = (path: string) => path.trim().replace(/^\/+|\/+$/g, "");

/** A tree drop moves into a directory; it never replaces a file or guesses a name. */
export function treeDropOperation(node: Pick<TreeNode, "kind" | "path" | "name">, targetFolder: string): FileOperation {
  const to = targetFolder ? `${targetFolder}/${node.name}` : node.name;
  if (node.path === to) throw new Error("This item is already in that folder.");
  if (node.kind === "folder" && (targetFolder === node.path || insideFolder(targetFolder, node.path))) throw new Error("A folder cannot move inside itself.");
  return { kind: node.kind === "folder" ? "rename-folder" : "rename", from: node.path, to };
}

/** A path can be reused during a live drag; move only the file identities grabbed. */
export function assertTreeDropSources(node: Pick<TreeNode, "kind" | "path">, expectedKeys: readonly string[], files: Iterable<{ key: string; path: string }>): void {
  const actual = Array.from(files).filter(file => node.kind === "file" ? file.path === node.path : insideFolder(file.path, node.path)).map(file => file.key).sort();
  const expected = [...expectedKeys].sort();
  if (!expected.length || expected.length !== actual.length || expected.some((key, index) => key !== actual[index])) throw new Error("These files changed location while this operation was pending. Nothing was changed; choose the current file and try again.");
}

/** Computes the complete document. Invalid results throw and change nothing. */
export function planFileOperation(source: PlaygroundDocument, operation: FileOperation): FilePlan {
  const files: Record<string, string> = Object.create(null);
  for (const [path, text] of Object.entries(source.files)) files[path] = text;
  const moved: Record<string, string> = {}, removed: string[] = [], added: string[] = [];
  let entryFile = source.entryFile;
  const taken = (path: string) => Object.keys(files).some(existing => existing.normalize("NFC").toLowerCase() === path.normalize("NFC").toLowerCase());
  const move = (from: string, to: string) => { files[to] = files[from]; delete files[from]; moved[from] = to; if (entryFile === from) entryFile = to; };

  switch (operation.kind) {
    case "create": {
      const path = clean(operation.path);
      if (!path) throw new Error("Enter a file path.");
      if (taken(path)) throw new Error("A file with this path already exists.");
      files[path] = ""; added.push(path);
      break;
    }
    case "duplicate": {
      const to = clean(operation.to);
      if (!(operation.from in files)) throw new Error("This file no longer exists.");
      if (!to) throw new Error("Enter a file path.");
      if (taken(to)) throw new Error("A file with this path already exists.");
      files[to] = files[operation.from]; added.push(to);
      break;
    }
    case "rename": {
      const to = clean(operation.to);
      if (!(operation.from in files)) throw new Error("This file no longer exists.");
      if (!to) throw new Error("Enter a file path.");
      if (to === operation.from) throw new Error("Enter a different path.");
      if (to.normalize("NFC").toLowerCase() !== operation.from.normalize("NFC").toLowerCase() && taken(to)) throw new Error("A file with this path already exists.");
      move(operation.from, to);
      break;
    }
    case "rename-folder": {
      const from = clean(operation.from), to = clean(operation.to);
      if (!to) throw new Error("Enter a folder path.");
      if (to === from) throw new Error("Enter a different path.");
      if (insideFolder(to, from)) throw new Error("A folder cannot move inside itself.");
      const inside = Object.keys(files).filter(path => insideFolder(path, from));
      if (!inside.length) throw new Error("This folder no longer exists.");
      for (const path of inside) {
        const target = to + path.slice(from.length);
        if (taken(target)) throw new Error(`${target} already exists. No files were moved.`);
      }
      for (const path of inside) move(path, to + path.slice(from.length));
      break;
    }
    case "delete-file":
    case "delete-folder": {
      const gone = operation.kind === "delete-file" ? [operation.path] : Object.keys(files).filter(path => insideFolder(path, operation.path));
      if (!gone.length || gone.some(path => !(path in files))) throw new Error("This no longer exists.");
      if (gone.includes(entryFile)) {
        if (!operation.entryFile || gone.includes(operation.entryFile) || !(operation.entryFile in files)) throw new Error("Choose a new entry file that stays in the project.");
        entryFile = operation.entryFile;
      }
      for (const path of gone) { delete files[path]; removed.push(path); }
      break;
    }
  }
  const document = validatePlaygroundDocument({ ...source, entryFile, files });
  return { document, moved, removed, added, movesRustSource: Object.keys(moved).some(path => path.endsWith(".rs")) };
}

export function remapBreakpoints(breakpoints: Record<string, number[]>, plan: FilePlan): Record<string, number[]> {
  const next: Record<string, number[]> = {};
  for (const [path, lines] of Object.entries(breakpoints)) if (!plan.removed.includes(path)) next[plan.moved[path] ?? path] = lines;
  return next;
}

export type FileIconKind = "rust" | "config" | "lock" | "markdown" | "text" | "license" | "notice" | "generic";

export function fileIconKind(path: string): FileIconKind {
  const name = path.split("/").at(-1)!, lower = name.toLowerCase();
  if (lower.endsWith(".rs")) return "rust";
  if (lower.endsWith(".toml")) return "config";
  if (lower.endsWith(".lock")) return "lock";
  if (lower.endsWith(".md")) return "markdown";
  if (lower.endsWith(".txt")) return "text";
  if (name === "LICENSE") return "license";
  if (name === "NOTICE") return "notice";
  return "generic";
}
