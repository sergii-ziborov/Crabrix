"use client";

import { useEffect, useMemo, useRef, useState, type DragEvent, type KeyboardEvent } from "react";
import { ancestors, buildFileTree, fileIconKind, flattenTree, matchingPaths, type FileIconKind, type TreeNode } from "@/lib/playground-file-ops";

export type TreeAction = "new-file" | "new-folder" | "rename" | "move" | "duplicate" | "delete" | "copy-path" | "set-entry";

// The same symbols and tints as the app's project tree (ProjectFileIcon.swift).
const cut = "var(--pg-panel)";
const glyphs: Record<FileIconKind | "entry" | "folder" | "folder-open", React.ReactNode> = {
  folder: <path d="M1.8 4.2h4.3l1.5 1.6h6.6v7.4H1.8z" />,
  "folder-open": <path d="M1.8 4.2h4.3l1.5 1.6h6.6v7.4H1.8z" fill="currentColor" />,
  entry: <><rect x="1.8" y="1.8" width="12.4" height="12.4" rx="3" fill="currentColor" stroke="none" /><path d="M6.4 5v6L11 8z" fill={cut} stroke="none" /></>,
  rust: <path d="M5.3 4.5 1.8 8l3.5 3.5m5.4-7L14.2 8l-3.5 3.5M9.3 3 6.7 13" />,
  config: <><path d="M2 4h12M2 8h12M2 12h12" /><circle cx="10.5" cy="4" r="1.7" fill={cut} /><circle cx="5" cy="8" r="1.7" fill={cut} /><circle cx="9" cy="12" r="1.7" fill={cut} /></>,
  lock: <><rect x="3" y="7" width="10" height="7" rx="1.5" fill="currentColor" stroke="none" /><path d="M5.3 7V5.2a2.7 2.7 0 0 1 5.4 0V7" /></>,
  markdown: <><path d="M3.5 1.5h6l3 3v10h-9z" fill="currentColor" stroke="none" /><path d="M5.5 8h5m-5 2.5h5M5.5 13h3" stroke={cut} /></>,
  text: <path d="M3.5 1.5h6l3 3v10h-9zM5.5 8h5m-5 2.5h5M5.5 13h3" />,
  license: <><path d="m8 1.3 1.7 1.3 2.1-.2.6 2 1.8 1.1-.7 2 .7 2-1.8 1.1-.6 2-2.1-.2L8 14.7l-1.7-1.3-2.1.2-.6-2-1.8-1.1.7-2-.7-2 1.8-1.1.6-2 2.1.2z" fill="currentColor" stroke="none" /><path d="m5.6 8 1.6 1.6 3.2-3.2" stroke={cut} /></>,
  notice: <><circle cx="8" cy="8" r="5.8" /><path d="M8 7.3v3.9M8 4.8v.2" /></>,
  generic: <path d="M3.5 1.5h6l3 3v10h-9z" />,
};

export function FileIcon({ kind }: { kind: keyof typeof glyphs }) {
  return <svg className="pg-file-icon" viewBox="0 0 16 16" width="16" height="16" fill="none" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">{glyphs[kind]}</svg>;
}

const sidebarGlyphs = {
  project: <><path d="M8 1.5 14 4.6v6.8L8 14.5 2 11.4V4.6z" fill="currentColor" stroke="none" /><path d="M2.3 4.8 8 7.7l5.7-2.9M8 7.7v6.6" stroke={cut} /></>,
  more: <><circle cx="8" cy="8" r="6.3" /><path d="M5.2 8h.1m2.6 0h.1m2.6 0h.1" strokeWidth="2" /></>,
  add: <><circle cx="8" cy="8" r="6.8" fill="currentColor" stroke="none" /><path d="M8 4.8v6.4M4.8 8h6.4" stroke={cut} strokeWidth="1.6" /></>,
  "file-add": <><path d="M3 1.7h6l3 3v9.6H3z" /><path d="M9 1.8v3h3M7.5 7.2v4.2M5.4 9.3h4.2" /></>,
  "folder-add": <><path d="M1.5 5.5h4.1l1.4 1.4h7.5v6.4h-13z" /><path d="M10.9 1.5v4M8.9 3.5h4" /></>,
  search: <><circle cx="7" cy="7" r="4.3" /><path d="m10.3 10.3 3.4 3.4" /></>,
};

/** Project-level symbols from the app sidebar: the package, actions and new file. */
export function SidebarIcon({ name }: { name: keyof typeof sidebarGlyphs }) {
  return <svg viewBox="0 0 16 16" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">{sidebarGlyphs[name]}</svg>;
}

function loadExpanded(key: string): Set<string> {
  try { const saved = JSON.parse(sessionStorage.getItem(key) ?? "[]"); return new Set(Array.isArray(saved) ? saved.filter(item => typeof item === "string") : []); }
  catch { return new Set(); }
}

type Props = {
  paths: string[]; selected: string; entryFile?: string; readOnly: boolean;
  /** A shared format v1 room, where rename, move and delete need a local copy. */
  shared: boolean;
  /** Paths shown under a conflict name because another file holds the path they asked for. */
  conflicts?: ReadonlySet<string>;
  /** Stable room file identities, captured at drag start to refuse reused paths. */
  identities?: Readonly<Record<string, string>>;
  /** Keeps a room's open folders apart from every other room's. */
  storageKey: string;
  /** The find field shows only while the sidebar's search button is on, as in the app. */
  searching: boolean;
  onCloseSearch: () => void;
  onOpen: (path: string) => void;
  onAction: (action: TreeAction, node: TreeNode) => void;
  /** The caller validates and applies the complete path move atomically. */
  onMove: (node: TreeNode, targetFolder: string, expectedKeys: string[]) => void;
  /** Inspect DataTransfer synchronously, then present the existing import review. */
  onExternalDrop: (dataTransfer: DataTransfer, targetFolder: string) => void;
};

const internalDragType = "application/x-crabrix-file-tree";
const parentFolder = (path: string) => path.includes("/") ? path.slice(0, path.lastIndexOf("/")) : "";
const canMoveTo = (node: TreeNode, folder: string) => folder !== parentFolder(node.path)
  && folder !== node.path && !folder.startsWith(node.path + "/");
const hasFiles = (transfer: DataTransfer) => Array.from(transfer.types).includes("Files");

export function FileTree({ paths, selected, entryFile, readOnly, shared, conflicts, identities, storageKey, searching, onCloseSearch, onOpen, onAction, onMove, onExternalDrop }: Props) {
  const [expanded, setExpanded] = useState(() => loadExpanded(storageKey));
  const [query, setQuery] = useState(""), [focused, setFocused] = useState(selected), [menu, setMenu] = useState<string | null>(null);
  const [draggingPath, setDraggingPath] = useState<string | null>(null);
  const [externalOver, setExternalOver] = useState(false);
  const [dropTarget, setDropTarget] = useState<string | null>(null);
  const [dragStatus, setDragStatus] = useState("");
  const draggedNode = useRef<TreeNode | null>(null);
  const draggedKeys = useRef<string[]>([]);
  const container = useRef<HTMLDivElement>(null), restoreFocus = useRef(false);
  const tree = useMemo(() => buildFileTree(paths), [paths]);

  useEffect(() => { try { sessionStorage.setItem(storageKey, JSON.stringify(Array.from(expanded))); } catch { /* Open folders only last for this view. */ } }, [expanded, storageKey]);
  // Opening a file from anywhere, such as a compiler message, reveals its folder.
  useEffect(() => { setFocused(selected); setExpanded(previous => { const missing = ancestors(selected).filter(item => !previous.has(item)); return missing.length ? new Set([...previous, ...missing]) : previous; }); }, [selected]);

  useEffect(() => { if (!searching) setQuery(""); }, [searching]);
  useEffect(() => {
    const cancel = (event: globalThis.KeyboardEvent) => {
      if (event.key !== "Escape" || (!draggedNode.current && !externalOver)) return;
      draggedNode.current = null;
      draggedKeys.current = [];
      setDraggingPath(null); setDropTarget(null); setExternalOver(false);
      setDragStatus("Drag cancelled.");
    };
    window.addEventListener("keydown", cancel);
    return () => window.removeEventListener("keydown", cancel);
  }, [externalOver]);
  const matches = useMemo(() => query.trim() ? matchingPaths(paths, query) : null, [paths, query]);
  const shownTree = useMemo(() => matches ? buildFileTree(matches) : tree, [matches, tree]);
  const shownExpanded = useMemo(() => matches ? new Set(matches.flatMap(ancestors)) : expanded, [matches, expanded]);
  const rows = useMemo(() => flattenTree(shownTree, shownExpanded), [shownTree, shownExpanded]);
  const active = rows.some(row => row.node.path === focused) ? focused : rows[0]?.node.path;

  useEffect(() => {
    if (!restoreFocus.current) return;
    restoreFocus.current = false;
    container.current?.querySelector<HTMLElement>('[role="treeitem"][tabindex="0"]')?.focus();
  }, [active, rows]);

  const moveTo = (path: string | undefined) => { if (path) { restoreFocus.current = true; setFocused(path); } };
  const setOpen = (path: string, open: boolean) => setExpanded(previous => { const next = new Set(previous); if (open) next.add(path); else next.delete(path); return next; });

  const clearDrag = () => {
    draggedNode.current = null;
    draggedKeys.current = [];
    setDraggingPath(null); setDropTarget(null); setExternalOver(false);
  };
  const dragOver = (event: DragEvent<HTMLElement>, folder: string) => {
    const source = draggedNode.current;
    if (!source && !hasFiles(event.dataTransfer)) { event.preventDefault(); event.stopPropagation(); return; }
    event.preventDefault(); event.stopPropagation();
    const allowed = !readOnly && (source ? !shared && canMoveTo(source, folder) : true);
    event.dataTransfer.dropEffect = allowed ? source ? "move" : "copy" : "none";
    setDropTarget(allowed ? folder : null);
    if (!source) setExternalOver(true);
    if (allowed) setDragStatus(source
      ? `Drop ${source.name} into ${folder || "project root"}.`
      : `Drop files into ${folder || "project root"} to review the import.`);
  };
  const drop = (event: DragEvent<HTMLElement>, folder: string) => {
    const source = draggedNode.current;
    if (!source && !hasFiles(event.dataTransfer)) { event.preventDefault(); event.stopPropagation(); return; }
    event.preventDefault(); event.stopPropagation();
    const allowed = !readOnly && (source ? !shared && canMoveTo(source, folder) : true);
    if (allowed) {
      try {
        if (source) onMove(source, folder, draggedKeys.current);
        else onExternalDrop(event.dataTransfer, folder);
        setDragStatus(source ? `Move requested for ${source.name}.` : "Import review opened.");
      } finally {
        clearDrag();
      }
    } else {
      setDragStatus("This drop location is not available.");
      clearDrag();
    }
  };

  const keyDown = (event: KeyboardEvent, node: TreeNode, index: number, parent: string | null) => {
    const handled = () => { event.preventDefault(); event.stopPropagation(); };
    switch (event.key) {
      case "ArrowDown": handled(); moveTo(rows[index + 1]?.node.path); break;
      case "ArrowUp": handled(); moveTo(rows[index - 1]?.node.path); break;
      case "Home": handled(); moveTo(rows[0]?.node.path); break;
      case "End": handled(); moveTo(rows.at(-1)?.node.path); break;
      case "ArrowRight":
        handled();
        if (node.kind === "folder") { if (shownExpanded.has(node.path)) moveTo(rows[index + 1]?.node.path); else if (!matches) setOpen(node.path, true); }
        break;
      case "ArrowLeft":
        handled();
        if (node.kind === "folder" && shownExpanded.has(node.path) && !matches) setOpen(node.path, false);
        else if (parent) moveTo(parent);
        break;
      case "Enter": case " ":
        handled();
        if (node.kind === "file") onOpen(node.path); else if (!matches) setOpen(node.path, !expanded.has(node.path));
        break;
      case "F2": handled(); if (!readOnly) onAction("rename", node); break;
      case "Delete": handled(); if (!readOnly) onAction("delete", node); break;
      case "Escape": if (menu || draggedNode.current) { handled(); setMenu(null); clearDrag(); } break;
    }
  };

  const items = (node: TreeNode): [TreeAction, string, boolean][] => {
    const destructive = readOnly || shared;
    const shared_ = node.kind === "folder"
      ? [["new-file", "New file inside", readOnly], ["new-folder", "New folder and file inside", readOnly], ["rename", "Rename folder", destructive], ["move", "Move folder", destructive], ["delete", "Delete contents", destructive]] as [TreeAction, string, boolean][]
      : [...(node.path.endsWith(".rs") && node.path !== entryFile ? [["set-entry", "Set as entry", readOnly] as [TreeAction, string, boolean]] : []), ["rename", "Rename", destructive], ["move", "Move", destructive], ["duplicate", "Duplicate", readOnly], ["delete", "Delete", destructive]] as [TreeAction, string, boolean][];
    return [...shared_, ["copy-path", "Copy relative path", false]];
  };

  return <div className="pg-tree-wrap" ref={container}
    onDragEnter={event => { if (!readOnly && hasFiles(event.dataTransfer) && !draggedNode.current) setExternalOver(true); }}
    onDragLeave={event => { if (!event.currentTarget.contains(event.relatedTarget as Node | null)) { setDropTarget(null); setExternalOver(false); } }}
    onDragOver={event => dragOver(event, "")}
    onDrop={event => drop(event, "")}>
    <span className="visually-hidden" role="status" aria-live="polite">{dragStatus}</span>
    {searching ? <label className="pg-tree-search"><span className="visually-hidden">Find a file by name or path</span>
      <input type="search" autoFocus value={query} placeholder="Find file" onChange={event => setQuery(event.target.value)} onKeyDown={event => { if (event.key === "Escape") { event.stopPropagation(); onCloseSearch(); } if (event.key === "ArrowDown") { event.preventDefault(); moveTo(rows[0]?.node.path); } }} />
    </label> : null}
    <div className={`pg-tree-root-drop${readOnly ? " pg-tree-root-readonly" : ""}${dropTarget === "" ? " pg-tree-drop-target" : ""}${draggingPath || externalOver ? " pg-tree-root-visible" : ""}`}
      aria-hidden="true" onDragOver={event => dragOver(event, "")} onDrop={event => drop(event, "")}>Project root <span>Drop here</span></div>
    <div className="pg-file-list" role="tree" aria-label="Project files"
      onDragOver={event => { if (event.target === event.currentTarget) dragOver(event, ""); }}
      onDrop={event => { if (event.target === event.currentTarget) drop(event, ""); }}>
      {rows.map(({ node, depth, parent }, index) => {
        const open = node.kind === "folder" && shownExpanded.has(node.path), isSelected = node.kind === "file" && node.path === selected;
        const kind = node.kind === "folder" ? open ? "folder-open" : "folder" : node.path === entryFile ? "entry" : fileIconKind(node.path);
        return <div key={node.path} className={`pg-tree-row pg-kind-${kind}${isSelected ? " pg-file-active" : ""}${draggingPath === node.path ? " pg-tree-dragging" : ""}${dropTarget === node.path ? " pg-tree-drop-target" : ""}`} role="treeitem" aria-level={depth + 1} aria-selected={isSelected} aria-expanded={node.kind === "folder" ? open : undefined} tabIndex={node.path === active ? 0 : -1} title={node.path} style={{ "--pg-depth": depth } as React.CSSProperties}
          draggable={!readOnly && !shared}
          onDragStart={event => { if (readOnly || shared) { event.preventDefault(); return; } draggedNode.current = node; draggedKeys.current = Object.entries(identities ?? {}).filter(([path]) => node.kind === "file" ? path === node.path : path.startsWith(node.path + "/")).map(([, key]) => key).sort(); event.dataTransfer.effectAllowed = "move"; event.dataTransfer.setData(internalDragType, node.path); setDraggingPath(node.path); setDragStatus(`Moving ${node.name}. Drop on a folder or project root, or press Escape to cancel.`); }}
          onDragEnd={() => { if (draggedNode.current) setDragStatus("Drag cancelled."); clearDrag(); }}
          onDragOver={event => { if (node.kind === "folder") dragOver(event, node.path); else if (!draggedNode.current && hasFiles(event.dataTransfer)) dragOver(event, parentFolder(node.path)); else if (draggedNode.current) { event.preventDefault(); event.stopPropagation(); event.dataTransfer.dropEffect = "none"; setDropTarget(null); } }}
          onDrop={event => { if (node.kind === "folder") drop(event, node.path); else if (!draggedNode.current && hasFiles(event.dataTransfer)) drop(event, parentFolder(node.path)); else if (draggedNode.current) { event.preventDefault(); event.stopPropagation(); setDragStatus("Drop on a folder or project root."); clearDrag(); } }}
          onFocus={event => { if (event.target === event.currentTarget) setFocused(node.path); }} onKeyDown={event => { if (event.target === event.currentTarget) keyDown(event, node, index, parent); }}>
          <button type="button" tabIndex={-1} className="pg-tree-open" onClick={() => { setFocused(node.path); if (node.kind === "file") onOpen(node.path); else if (!matches) setOpen(node.path, !open); }}>
            <FileIcon kind={kind} />
            <span className="pg-tree-name">{node.name}</span>
            {node.path === entryFile ? <span className="visually-hidden">, entry file</span> : null}
            {conflicts?.has(node.path) ? <span className="pg-entry-badge pg-conflict-badge" title="Another file has the path this file asked for. Rename one of them.">Conflict</span> : null}
          </button>
          <button type="button" tabIndex={node.path === active ? 0 : -1} className="pg-tree-menu-button" aria-label={`Actions for ${node.path}`} aria-haspopup="menu" aria-expanded={menu === node.path} onClick={() => setMenu(menu === node.path ? null : node.path)} onKeyDown={event => { if (event.key === "Escape") { event.stopPropagation(); setMenu(null); } }}>⋯</button>
          {menu === node.path ? <div className="pg-tree-menu" role="menu" onKeyDown={event => { event.stopPropagation(); if (event.key === "Escape") { event.preventDefault(); event.currentTarget.parentElement?.querySelector<HTMLButtonElement>(".pg-tree-menu-button")?.focus(); setMenu(null); } }}>
            {items(node).map(([action, label, disabled]) => <button key={action} role="menuitem" type="button" disabled={disabled} autoFocus={action === items(node)[0][0]} onClick={() => { setMenu(null); onAction(action, node); }}>{label}</button>)}
            {shared ? <p>Rename, move and delete need a local copy in a shared room, so nobody's unsent edit is lost.</p> : null}
          </div> : null}
        </div>;
      })}
      {!rows.length ? <p className="pg-tree-empty">{query ? "No file matches this search." : "No files yet."}</p> : null}
    </div>
  </div>;
}
