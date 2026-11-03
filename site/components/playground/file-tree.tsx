"use client";

import { useEffect, useMemo, useRef, useState, type KeyboardEvent } from "react";
import { ancestors, buildFileTree, fileIconKind, flattenTree, matchingPaths, type FileIconKind, type TreeNode } from "@/lib/playground-file-ops";

export type TreeAction = "new-file" | "new-folder" | "rename" | "move" | "duplicate" | "delete" | "copy-path" | "set-entry";

const glyphs: Record<FileIconKind | "folder" | "folder-open", React.ReactNode> = {
  folder: <path d="M2 4.5h4l1.5 1.5H14v7H2z" />,
  "folder-open": <path d="M2 13V4.5h4L7.5 6H13v1.5M2 13l1.6-5.5H15L13.4 13z" />,
  rust: <><circle cx="8" cy="8" r="5.5" /><path d="M5.5 11V5.5h3a1.5 1.5 0 0 1 0 3h-3m3 0 2 2.5" /></>,
  config: <><circle cx="8" cy="8" r="2" /><path d="M8 2v2m0 8v2M2 8h2m8 0h2M3.8 3.8l1.4 1.4m5.6 5.6 1.4 1.4m0-8.4-1.4 1.4m-5.6 5.6-1.4 1.4" /></>,
  lock: <><rect x="3.5" y="7" width="9" height="6.5" rx="1" /><path d="M5.5 7V5a2.5 2.5 0 0 1 5 0v2" /></>,
  markdown: <><rect x="1.5" y="3.5" width="13" height="9" rx="1" /><path d="M4 10V6l2 2 2-2v4m3-4v4m-1.5-1.5L11 10l1.5-1.5" /></>,
  text: <path d="M4 2h5.5L12 4.5V14H4zM6 7h4M6 9.5h4M6 12h2.5" />,
  license: <><path d="M4 2h8v8.5H4z" /><path d="M6 5h4M6 7.5h4M6.5 10.5V14L8 13l1.5 1v-3.5" /></>,
  notice: <><circle cx="8" cy="8" r="5.5" /><path d="M8 7.5V11M8 5v.5" /></>,
  generic: <path d="M4 2h5.5L12 4.5V14H4z" />,
};

export function FileIcon({ kind }: { kind: keyof typeof glyphs }) {
  return <svg className="pg-file-icon" viewBox="0 0 16 16" width="16" height="16" fill="none" stroke="currentColor" strokeWidth="1.25" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">{glyphs[kind]}</svg>;
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
  /** Keeps a room's open folders apart from every other room's. */
  storageKey: string;
  onOpen: (path: string) => void;
  onAction: (action: TreeAction, node: TreeNode) => void;
};

export function FileTree({ paths, selected, entryFile, readOnly, shared, conflicts, storageKey, onOpen, onAction }: Props) {
  const [expanded, setExpanded] = useState(() => loadExpanded(storageKey));
  const [query, setQuery] = useState(""), [focused, setFocused] = useState(selected), [menu, setMenu] = useState<string | null>(null);
  const container = useRef<HTMLDivElement>(null), restoreFocus = useRef(false);
  const tree = useMemo(() => buildFileTree(paths), [paths]);

  useEffect(() => { try { sessionStorage.setItem(storageKey, JSON.stringify(Array.from(expanded))); } catch { /* Open folders only last for this view. */ } }, [expanded, storageKey]);
  // Opening a file from anywhere, such as a compiler message, reveals its folder.
  useEffect(() => { setFocused(selected); setExpanded(previous => { const missing = ancestors(selected).filter(item => !previous.has(item)); return missing.length ? new Set([...previous, ...missing]) : previous; }); }, [selected]);

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
      case "Escape": if (menu) { handled(); setMenu(null); } break;
    }
  };

  const items = (node: TreeNode): [TreeAction, string, boolean][] => {
    const destructive = readOnly || shared;
    const shared_ = node.kind === "folder"
      ? [["new-file", "New file inside", readOnly], ["new-folder", "New folder and file inside", readOnly], ["rename", "Rename folder", destructive], ["move", "Move folder", destructive], ["delete", "Delete contents", destructive]] as [TreeAction, string, boolean][]
      : [...(node.path.endsWith(".rs") && node.path !== entryFile ? [["set-entry", "Set as entry", readOnly] as [TreeAction, string, boolean]] : []), ["rename", "Rename", destructive], ["move", "Move", destructive], ["duplicate", "Duplicate", readOnly], ["delete", "Delete", destructive]] as [TreeAction, string, boolean][];
    return [...shared_, ["copy-path", "Copy relative path", false]];
  };

  return <div className="pg-tree-wrap" ref={container}>
    <label className="pg-tree-search"><span className="visually-hidden">Find a file by name or path</span>
      <input type="search" value={query} placeholder="Find file" onChange={event => setQuery(event.target.value)} onKeyDown={event => { if (event.key === "Escape") { event.stopPropagation(); setQuery(""); } if (event.key === "ArrowDown") { event.preventDefault(); moveTo(rows[0]?.node.path); } }} />
    </label>
    <div className="pg-file-list" role="tree" aria-label="Project files">
      {rows.map(({ node, depth, parent }, index) => {
        const open = node.kind === "folder" && shownExpanded.has(node.path), isSelected = node.kind === "file" && node.path === selected;
        return <div key={node.path} className={`pg-tree-row${isSelected ? " pg-file-active" : ""}`} role="treeitem" aria-level={depth + 1} aria-selected={isSelected} aria-expanded={node.kind === "folder" ? open : undefined} tabIndex={node.path === active ? 0 : -1} title={node.path} style={{ "--pg-depth": depth } as React.CSSProperties}
          onFocus={event => { if (event.target === event.currentTarget) setFocused(node.path); }} onKeyDown={event => { if (event.target === event.currentTarget) keyDown(event, node, index, parent); }}>
          <button type="button" tabIndex={-1} className="pg-tree-open" onClick={() => { setFocused(node.path); if (node.kind === "file") onOpen(node.path); else if (!matches) setOpen(node.path, !open); }}>
            <FileIcon kind={node.kind === "folder" ? open ? "folder-open" : "folder" : fileIconKind(node.path)} />
            <span className="pg-tree-name">{node.name}</span>
            {node.path === entryFile ? <span className="pg-entry-badge">Entry</span> : null}
            {conflicts?.has(node.path) ? <span className="pg-entry-badge pg-conflict-badge" title="Another file has the path this file asked for. Rename one of them.">Conflict</span> : null}
          </button>
          <button type="button" tabIndex={node.path === active ? 0 : -1} className="pg-tree-menu-button" aria-label={`Actions for ${node.path}`} aria-haspopup="menu" aria-expanded={menu === node.path} onClick={() => setMenu(menu === node.path ? null : node.path)} onKeyDown={event => { if (event.key === "Escape") { event.stopPropagation(); setMenu(null); } }}>⋯</button>
          {menu === node.path ? <div className="pg-tree-menu" role="menu" onKeyDown={event => { event.stopPropagation(); if (event.key === "Escape") { setMenu(null); moveTo(node.path); } }}>
            {items(node).map(([action, label, disabled]) => <button key={action} role="menuitem" type="button" disabled={disabled} autoFocus={action === items(node)[0][0]} onClick={() => { setMenu(null); onAction(action, node); }}>{label}</button>)}
            {shared ? <p>Rename, move and delete need a local copy in a shared room, so nobody's unsent edit is lost.</p> : null}
          </div> : null}
        </div>;
      })}
      {!rows.length ? <p className="pg-tree-empty">{query ? "No file matches this search." : "No files yet."}</p> : null}
    </div>
  </div>;
}
