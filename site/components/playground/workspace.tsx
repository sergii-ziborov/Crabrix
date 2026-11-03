"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { DebugPanel } from "./debug-panel";
import * as Y from "yjs";
import { createPresence } from "@/lib/playground-presence";
import { strToU8 } from "fflate";
import { documentFromY, updateYDocument } from "@/lib/playground-collab";
import { applyOperations, createProjectDoc, operationsFromReplace, planOperations, PlanError, readProject, type ProjectOperation, type RecoveryRow } from "@/lib/playground-codec-v2";
import { blockedSummary, exportArchive, fileText, purgedFileIds, readView, runnableDocument, treeOperations, type ProjectCodec, type ProjectView } from "@/lib/playground-project";
import { committedProjectName, newPlaygroundDocument, sourceBytes, validatePlaygroundDocument, type PlaygroundDocument } from "@/lib/playground-document";
import { newEncryptionSecret } from "@/lib/playground-crypto";
import { createPlayground, parsePlaygroundLink, playgroundLink, PlaygroundSession, type PlaygroundLink, type CreatedPlayground } from "@/lib/playground-session";
import { forgetOwnerCapabilities, rememberOwnerCapabilities, restoreOwnerCapabilities } from "@/lib/playground-client";
import { createFileEditorState, PlaygroundCodeEditor, type EditorPreferences, type FileEditorState } from "./code-editor";
import { useRustCompiler } from "./use-rust-compiler";
import { useRuntimeHost } from "./use-runtime-host";
import { RuntimePermissions } from "./runtime-permissions";
import { documentRevision, type ImportPlan, type ImportReceipt } from "@/lib/playground-import-plan";
import { isDestructiveInSharedRoom, planFileOperation, remapBreakpoints, type FileOperation, type TreeNode } from "@/lib/playground-file-ops";
import { deleteDraft, KEEP_DRAFTS_KEY, listDrafts, saveDraft, type StoredDraft } from "@/lib/playground-drafts";
import { useThemePreference } from "@/components/theme-provider";
import { themeOptions } from "@/lib/theme";
import { FileTree, type TreeAction } from "./file-tree";
import { FileDialog, fileDialogTitle, type FileRequest } from "./file-dialog";
import { RecoveryPanel } from "./recovery-panel";
import { ImportDialog } from "./import-dialog";
import { ConnectAIDialog } from "./connect-ai-dialog";
import toolchain from "@/lib/playground-toolchain.json";

type Modal = "share" | "settings" | "import" | "connect" | "file" | "leave" | null;
const defaultPreferences: EditorPreferences = { fontSize: 15, wrap: false, pairs: true, tabSize: 4 };

function download(name: string, bytes: Uint8Array, type: string) {
  const blob = new Blob([new Uint8Array(bytes)], { type });
  const url = URL.createObjectURL(blob), anchor = document.createElement("a");
  anchor.href = url; anchor.download = name; anchor.click(); setTimeout(() => URL.revokeObjectURL(url), 60_000);
}

// Survives a move to another page within this visit, so an unsaved draft is not lost
// even when the browser's back button leaves without any chance to ask first.
let unmountedDraft: { document: PlaygroundDocument; draftId: string } | null = null;

type LocalCopy = { key: number; seed?: PlaygroundDocument; notice?: string; draftId?: string; unsaved?: boolean; modal?: Modal };

// Internal until new rooms default to stable file IDs (docs/playground-r2-design.md, step 7).
const stableFileRooms = () => { try { return localStorage.getItem("crabrix.playground.format") === "2"; } catch { return false; } };

/** Remounts with a fresh document, so a copy cannot keep any of a room's session state. */
export default function PlaygroundWorkspace() {
  const [instance, setInstance] = useState<LocalCopy>({ key: 0 });
  const openLocal = useCallback((seed: PlaygroundDocument, options: { notice: string; draftId?: string; unsaved: boolean }) => {
    // Removes the room's secret fragment, so a reload cannot rejoin the room.
    history.replaceState(null, "", "/playground/");
    setInstance(previous => ({ key: previous.key + 1, seed, ...options }));
  }, []);
  // A format v2 room is published from a new document, so this page joins it like a participant.
  const joinRoom = useCallback((room: PlaygroundLink, modal: Modal) => {
    history.replaceState(null, "", playgroundLink(room));
    setInstance(previous => ({ key: previous.key + 1, modal }));
  }, []);
  return <Workspace key={instance.key} seed={instance.seed} seedNotice={instance.notice} seedDraftId={instance.draftId} seedUnsaved={instance.unsaved} seedModal={instance.modal ?? null} onOpenLocal={openLocal} onJoinRoom={joinRoom} />;
}

function Workspace({ seed, seedNotice, seedDraftId, seedUnsaved, seedModal, onOpenLocal, onJoinRoom }: { seed?: PlaygroundDocument; seedNotice?: string; seedDraftId?: string; seedUnsaved?: boolean; seedModal: Modal; onOpenLocal: (seed: PlaygroundDocument, options: { notice: string; draftId?: string; unsaved: boolean }) => void; onJoinRoom: (room: PlaygroundLink, modal: Modal) => void }) {
  const [doc] = useState(() => new Y.Doc()), [awareness] = useState(() => createPresence(doc)), [source, setSource] = useState<PlaygroundDocument | null>(null);
  const [selected, setSelected] = useState("main.rs"), [theme, setTheme] = useThemePreference();
  const [preferences, setPreferences] = useState(defaultPreferences), [layout, setLayout] = useState("auto");
  const [modal, setModal] = useState<Modal>(seedModal), dialog = useRef<HTMLDialogElement>(null);
  const [view, setView] = useState<ProjectView | null>(null), viewRef = useRef<ProjectView | null>(null);
  const [link, setLink] = useState<PlaygroundLink | null>(null), [created, setCreated] = useState<CreatedPlayground | null>(null);
  const session = useRef<PlaygroundSession | null>(null), [connection, setConnection] = useState("Local editor · no source upload");
  const [expiresAt, setExpiresAt] = useState<number | null>(null), [now, setNow] = useState<number | null>(null);
  const [lifetime, setLifetime] = useState(3600), [expired, setExpired] = useState(false), [sharing, setSharing] = useState(false);
  const [notice, setNotice] = useState(""), [stdin, setStdin] = useState(""), [dock, setDock] = useState("output");
  const [filePane, setFilePane] = useState(false), [nameDraft, setNameDraft] = useState<string | null>(null);
  const [fileRequest, setFileRequest] = useState<FileRequest | null>(null), [leaveTo, setLeaveTo] = useState<string | null>(null);
  const [receipts, setReceipts] = useState<ImportReceipt[]>([]), [resultRevision, setResultRevision] = useState<string | null>(null);
  const [keepDrafts, setKeepDrafts] = useState(false), [drafts, setDrafts] = useState<StoredDraft[]>([]), [draftStatus, setDraftStatus] = useState("");
  const editorStates = useRef(new Map<string, FileEditorState>()), [draftId] = useState(() => seedDraftId ?? newEncryptionSecret());
  // Local work that exists nowhere else, and the live values a page-leave check needs.
  const unsaved = useRef(!!seedUnsaved), guard = useRef({ link: false, expired: false });
  const disposal = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const compiler = useRustCompiler();
  const [liveSession,setLiveSession] = useState<PlaygroundSession|null>(null);
  // The room's format; a local draft stays format v1 until step 7 of the R2 rollout.
  const codecOf = useCallback((): ProjectCodec => session.current?.codec === 2 ? 2 : 1, []);
  const runtime = useRuntimeHost(liveSession,awareness,()=>runnableDocument(doc,codecOf()),compiler);
  const [breakpoints, setBreakpoints] = useState<Record<string, number[]>>({});
  const debugStatus = useRef({ active: false, stop: compiler.stop }); debugStatus.current = { active: compiler.debugging, stop: compiler.stop };
  // Breakpoints follow the file key; the debugger receives them by path.
  const pathMap = view?.codec === 2 ? JSON.stringify(view.files.map(file => [file.key, file.path])) : "";
  const pathBreakpoints = useMemo(() => {
    if (!pathMap) return breakpoints;
    const paths = new Map<string, string>(JSON.parse(pathMap));
    return Object.fromEntries(Object.entries(breakpoints).flatMap(([key, lines]) => paths.has(key) ? [[paths.get(key)!, lines]] : []));
  }, [breakpoints, pathMap]);
  const keyOfPath = useCallback((path: string) => viewRef.current?.files.find(file => file.path === path)?.key ?? path, []);
  const toggleBreakpoint = useCallback((file: string, line: number) => setBreakpoints(previous => ({ ...previous, [file]: previous[file]?.includes(line) ? previous[file].filter(value => value !== line) : [...(previous[file] ?? []), line].sort((a, b) => a - b) })), []);
  useEffect(() => { compiler.updateBreakpoints(pathBreakpoints); }, [pathBreakpoints, compiler.updateBreakpoints]);
  useEffect(() => { if (compiler.debugPause) { setSelected(keyOfPath(compiler.debugPause.site.file)); setDock("debug"); } }, [compiler.debugPause, keyOfPath]);

  useEffect(() => {
    if (disposal.current) clearTimeout(disposal.current);
    setNow(Date.now());
    try {
      const saved = JSON.parse(localStorage.getItem("crabrix.playground.preferences.v1") ?? "null");
      setKeepDrafts(localStorage.getItem(KEEP_DRAFTS_KEY) === "true");
      if (saved?.fontSize >= 12 && saved.fontSize <= 24) setPreferences({ fontSize: saved.fontSize, wrap: saved.wrap === true, pairs: saved.pairs !== false, tabSize: saved.tabSize === 2 ? 2 : 4 });
    } catch {}
    const update = (transaction: Y.Transaction) => {
      try {
        if (transaction.changed.size > 0 && transaction.origin !== "initial" && !guard.current.link) unsaved.current = true;
        if (debugStatus.current.active && transaction.changed.size > 0) { debugStatus.current.stop(); setNotice("Debug stopped because shared source changed. Start Debug again for the new snapshot."); }
        const value = readView(doc, codecOf()); viewRef.current = value; setView(value); setSource(value.document);
        setSelected(previous => value.files.some(file => file.key === previous) ? previous : value.entryKey ?? value.files[0]?.key ?? previous);
        if (value.codec === 2) for (const id of purgedFileIds(doc, transaction)) editorStates.current.get(id)?.undo.clear();
      } catch { /* Joining an empty document waits for its authenticated snapshot. */ }
    };
    doc.on("afterTransaction", update);
    try {
      const initial = parsePlaygroundLink(new URL(location.href));
      if (initial) {
        setLink(initial); setCreated(restoreOwnerCapabilities(initial)); setExpiresAt(initial.expiresAt); setConnection("Decrypting the temporary Playground…");
        const connection = new PlaygroundSession(doc, initial, setConnection, () => setExpired(true), awareness);
        session.current = connection; setLiveSession(connection); void connection.start();
      } else {
        const restored = seed ? null : unmountedDraft;
        unmountedDraft = null;
        updateYDocument(doc, seed ?? restored?.document ?? newPlaygroundDocument(), "initial");
        if (seedNotice) setNotice(seedNotice);
        else if (restored) { unsaved.current = true; setNotice("Your unsaved draft from this visit is back."); }
      }
    } catch (error) { setNotice(String(error)); }
    return () => {
      session.current?.stop(); doc.off("afterTransaction", update);
      if (unsaved.current && !guard.current.link) { try { unmountedDraft = { document: documentFromY(doc), draftId }; } catch { /* Nothing valid to keep. */ } }
      disposal.current = setTimeout(() => { awareness.destroy(); doc.destroy(); }, 0);
    };
  }, [doc, awareness]); // eslint-disable-line react-hooks/exhaustive-deps

  guard.current = { link: !!link, expired };
  const hasUnsavedWork = useCallback(() => guard.current.link ? guard.current.expired || (session.current?.pending.length ?? 0) > 0 : unsaved.current, []);
  // Reloading or closing asks the browser. Links inside the site ask in this page.
  useEffect(() => {
    const beforeUnload = (event: BeforeUnloadEvent) => { if (hasUnsavedWork()) event.preventDefault(); };
    const click = (event: MouseEvent) => {
      if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || !hasUnsavedWork()) return;
      const anchor = (event.target as Element | null)?.closest?.("a[href]") as HTMLAnchorElement | null;
      if (!anchor || anchor.target === "_blank" || anchor.hasAttribute("download") || anchor.origin !== location.origin || anchor.pathname === location.pathname) return;
      event.preventDefault(); event.stopPropagation();
      setLeaveTo(anchor.href); setModal("leave");
    };
    window.addEventListener("beforeunload", beforeUnload); document.addEventListener("click", click, true);
    return () => { window.removeEventListener("beforeunload", beforeUnload); document.removeEventListener("click", click, true); };
  }, [hasUnsavedWork]);

  useEffect(() => {
    if (!keepDrafts || link || !source) return;
    const timer = setTimeout(() => {
      saveDraft(draftId, source).then(() => { unsaved.current = false; setDraftStatus("Draft saved on this device"); }, error => setDraftStatus("Draft not saved: " + (error instanceof Error ? error.message : String(error))));
    }, 800);
    return () => clearTimeout(timer);
  }, [keepDrafts, link, source, draftId]);
  useEffect(() => { if (modal === "settings" && keepDrafts) listDrafts().then(setDrafts, () => setDraftStatus("Browser storage is unavailable.")); }, [modal, keepDrafts]);

  useEffect(() => {
    const viewport = window.visualViewport;
    const resize = () => { document.body.style.setProperty("--pg-window-height", `${viewport?.height ?? window.innerHeight}px`); };
    resize(); viewport?.addEventListener("resize", resize); window.addEventListener("resize", resize);
    return () => { viewport?.removeEventListener("resize", resize); window.removeEventListener("resize", resize); document.body.style.removeProperty("--pg-window-height"); };
  }, []);
  useEffect(() => {
    try { localStorage.setItem("crabrix.playground.preferences.v1", JSON.stringify(preferences)); } catch {}
  }, [preferences]);
  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(timer);
  }, []);
  useEffect(() => {
    // A draft that is not shared has no room to expire. Only a room has a lifetime.
    if (link && now !== null && expiresAt !== null && now >= expiresAt && !expired) {
      setExpired(true); session.current?.stop(); compiler.stop();
    }
  }, [link, now, expiresAt, expired, compiler.stop]);
  useEffect(() => { if (expired && link) forgetOwnerCapabilities(link.id); }, [expired, link]);
  useEffect(() => {
    if (modal && !dialog.current?.open) dialog.current?.showModal();
    if (!modal && dialog.current?.open) dialog.current.close();
  }, [modal]);

  /** Starts a separate local project from the text in this one. The room itself is left alone. */
  const copyToLocal = useCallback((notice = "This is your own local copy. The room is unchanged, and edits here stay on this device until you share them.") => {
    try {
      const codec = codecOf(), value = runnableDocument(doc, codec);
      // Recovery rows stay in the room; the local copy takes only the live files.
      const recovered = codec === 2 ? readProject(doc).recovery.length : 0;
      session.current?.stop(); compiler.stop();
      onOpenLocal(value, { notice: recovered ? `${notice} ${recovered} file${recovered === 1 ? "" : "s"} in Recovery stayed in the room.` : notice, unsaved: true });
    } catch (error) { setNotice((error instanceof Error ? error.message : String(error)) + (codecOf() === 2 ? " Save to device exports every file, including Recovery." : "")); }
  }, [doc, compiler.stop, onOpenLocal, codecOf]);

  const share = useCallback(async (): Promise<PlaygroundLink> => {
    if (link) return link;
    if (expired) throw new Error("This session expired. Download your code and create a new Playground.");
    setSharing(true); setNotice("");
    if (stableFileRooms()) {
      const project = createProjectDoc(documentFromY(doc));
      try {
        const result = await createPlayground(project, lifetime, 2);
        rememberOwnerCapabilities(result); unsaved.current = false;
        onJoinRoom(result, modal === "connect" ? "connect" : "share");
        return result;
      } finally { project.destroy(); setSharing(false); }
    }
    try {
      const result = await createPlayground(doc, lifetime);
      setCreated(result); setLink(result); setExpiresAt(result.expiresAt); rememberOwnerCapabilities(result);
      unsaved.current = false;
      const connection = new PlaygroundSession(doc, result, setConnection, () => setExpired(true), awareness);
      session.current = connection; setLiveSession(connection); void connection.start();
      history.replaceState(null, "", playgroundLink(result));
      return result;
    } finally { setSharing(false); }
  }, [doc, link, lifetime, expired, awareness, modal, onJoinRoom]);

  const openInApp = async () => {
    try {
      const shared = await share();
      const url = new URL(playgroundLink(shared));
      location.href = "crabrix://playground/room/" + shared.id + "/" + url.hash;
      setTimeout(() => { if (document.visibilityState === "visible") setNotice(codecOf() === 2 || stableFileRooms() ? "If Crabrix did not open, install or update it: this room needs Crabrix 1.1.5 or newer. You can also download the source ZIP to open from Files." : "If Crabrix did not open, install or update it, or download the source ZIP to open from Files."); }, 1800);
    } catch (error) { setNotice(error instanceof Error ? error.message : String(error)); }
  };
  const save = () => {
    if (!view) return;
    try {
      // A blocked v2 room still exports, with recovered text in crabrix-recovery/.
      const name = view.codec === 1 ? validatePlaygroundDocument(view.document).name : view.document.name;
      download(name.replace(/[^a-z0-9_-]/gi, "-") + ".zip", exportArchive(view), "application/zip");
      setNotice(view.recovery.length ? `Downloaded source only, with ${view.recovery.length} recovered file${view.recovery.length === 1 ? "" : "s"} in crabrix-recovery/.` : "Downloaded source only. Open the ZIP in Crabrix or save it in Files.");
      unsaved.current = false;
    } catch (error) { setNotice(String(error)); }
  };
  /** v2 changes go through planned operations; one refused check leaves the project unchanged. */
  const operate = (operations: ProjectOperation[], origin = "structure") => applyOperations(doc, operations, { origin });
  const restoreRow = (row: RecoveryRow) => {
    try {
      try { operate([{ kind: "restore", id: row.id }]); }
      catch (error) {
        if (!(error instanceof PlanError && error.code === "path-taken")) throw error;
        const dot = row.path.lastIndexOf("."), suggested = dot > row.path.lastIndexOf("/") + 1 ? `${row.path.slice(0, dot)}-restored${row.path.slice(dot)}` : `${row.path}-restored`;
        const path = window.prompt(error.message, suggested)?.trim();
        if (!path) return;
        operate([{ kind: "restore", id: row.id, path }]);
      }
      setSelected(row.id);
    } catch (error) { setNotice(error instanceof Error ? error.message : String(error)); }
  };
  const clearRow = (row: RecoveryRow) => {
    if (!window.confirm(`Clear ${row.path} from Recovery for everyone in this room? Its text cannot be restored afterwards.`)) return;
    try { operate([{ kind: "purge", id: row.id }]); editorStates.current.get(row.id)?.undo.clear(); }
    catch (error) { setNotice(error instanceof Error ? error.message : String(error)); }
  };
  const treeAction = (action: TreeAction, node: TreeNode) => {
    if (action === "copy-path") { void navigator.clipboard.writeText(node.path).then(() => setNotice(`Copied ${node.path}`), () => setNotice(node.path)); return; }
    if (action === "set-entry") {
      if (readOnly || !node.path.endsWith(".rs")) return;
      if (codecOf() === 1) doc.getMap("meta").set("entryFile", node.path);
      else try { operate([{ kind: "setEntry", file: { path: node.path } }]); } catch (error) { setNotice(error instanceof Error ? error.message : String(error)); }
      return;
    }
    // Stable file IDs keep a rename, move or delete from losing another participant's edit.
    if (link && codecOf() === 1 && (action === "rename" || action === "move" || action === "delete")) { setNotice("Rename, move and delete need a local copy in a shared room, so nobody's unsent edit is lost. Use Copy to local."); return; }
    setFileRequest({ action, folder: node.kind === "folder", path: node.path }); setModal("file");
  };
  const checkFile = useCallback((operation: FileOperation) => codecOf() === 2 ? { movesRustSource: planOperations(doc, treeOperations(operation)).checkSuggested } : planFileOperation(documentFromY(doc), operation), [doc, codecOf]);
  const applyFilePlan = (operation: FileOperation) => {
    try {
      if (codecOf() === 2) {
        const result = operate(treeOperations(operation));
        if (!result.alreadyApplied && result.plan.created.length) { setSelected(result.plan.created[0]); setFilePane(false); }
        if (!result.alreadyApplied && result.plan.checkSuggested) setNotice("Moved. Rust mod and #[path] references are not rewritten, so run Check.");
        setModal(null); setFileRequest(null);
        return;
      }
      // Computed again from the live document: another participant may have typed since the dialog opened.
      const plan = planFileOperation(documentFromY(doc), operation);
      if (link && isDestructiveInSharedRoom(operation)) throw new Error("This needs a local copy in a shared room.");
      // Queued first: the document update below otherwise falls back to the entry file.
      setSelected(previous => plan.added[0] ?? plan.moved[previous] ?? (plan.removed.includes(previous) ? plan.document.entryFile : previous));
      updateYDocument(doc, plan.document, "structure");
      for (const path of [...plan.removed, ...Object.keys(plan.moved)]) { editorStates.current.get(path)?.undo.destroy(); editorStates.current.delete(path); }
      setBreakpoints(previous => remapBreakpoints(previous, plan));
      if (plan.added.length) setFilePane(false);
      if (plan.movesRustSource) setNotice("Moved. Rust mod and #[path] references are not rewritten, so run Check.");
      setModal(null); setFileRequest(null);
    } catch (error) { setNotice(error instanceof Error ? error.message : String(error)); setModal(null); setFileRequest(null); }
  };
  const applyImport = (plan: ImportPlan, value: PlaygroundDocument) => {
    try {
      if (codecOf() === 2) {
        // The plan was checked against the live revision, so the difference is exactly the chosen paths.
        const state = readProject(doc), baseline = Object.fromEntries(state.files.map(file => [file.path, file.id]));
        const operations = operationsFromReplace(state, baseline, value);
        if (operations.length) operate(operations, "import");
        for (const path of plan.replaced) if (baseline[path]) editorStates.current.get(baseline[path])?.undo.clear();
      } else {
        updateYDocument(doc, value, "import");
        for (const path of plan.replaced) { editorStates.current.get(path)?.undo.clear(); }
        setSelected(previous => plan.removed.includes(previous) || !(previous in value.files) ? value.entryFile : previous);
      }
      setReceipts(previous => [...previous, plan.receipt]);
    } catch (error) { setNotice(error instanceof Error ? error.message : String(error)); }
    setModal(null);
  };
  const setDraftKeeping = (value: boolean) => {
    setKeepDrafts(value);
    try { localStorage.setItem(KEEP_DRAFTS_KEY, String(value)); } catch { setDraftStatus("Browser storage is unavailable."); }
    if (!value) setDraftStatus("");
  };
  const run = (mode: "check" | "run" | "debug") => {
    if (!source || expired) return;
    try { const value = validatePlaygroundDocument(runnableDocument(doc, codecOf())); compiler.start(mode, value, stdin); setResultRevision(documentRevision(value)); setDock(mode === "check" ? "problems" : mode === "debug" ? "debug" : "output"); }
    catch (error) { setNotice(String(error)); }
  };
  const current = view?.files.find(file => file.key === selected), selectedPath = current?.path ?? selected;
  const sourceText = current?.text ?? "";
  const text = view ? fileText(doc, view, selected) : null;
  let fileState: FileEditorState | null = null;
  if (text) {
    fileState = editorStates.current.get(selected) ?? null;
    if (fileState?.text !== text) { fileState?.undo.destroy(); fileState = createFileEditorState(text); editorStates.current.set(selected, fileState); }
  }
  const staleResult = !!compiler.result && !!source && !!resultRevision && documentRevision(source) !== resultRevision;
  const diagnostics = (compiler.result?.compilation.stderr ?? "").split("\n").flatMap(line => {
    try { const value = JSON.parse(line); return value.$message_type === "diagnostic" ? [value] : []; } catch { return []; }
  });
  const blocked = !!view?.blocked.length;
  const isBusy = compiler.activity !== "idle", readOnly = expired || link?.mode === "view" || compiler.debugging || !!liveSession?.formatMismatch;
  const commitName = () => {
    if (nameDraft === null) return;
    setNameDraft(null);
    if (!source || readOnly) return;
    try { const name = committedProjectName(nameDraft, source.name); if (name) { if (codecOf() === 2) operate([{ kind: "setName", name }]); else doc.getMap("meta").set("name", name); } }
    catch (error) { setNotice(error instanceof Error ? error.message : String(error)); }
  };
  const secondsLeft = now !== null && expiresAt !== null ? Math.max(0, Math.ceil((expiresAt - now) / 1000)) : null;
  const lifetimeLabel = !link ? "Local draft · no time limit" : secondsLeft === null ? "Preparing session…" : expired ? "Room expired · your text is still here" : `Expires in ${Math.floor(secondsLeft / 3600)}h ${Math.floor(secondsLeft % 3600 / 60)}m ${secondsLeft % 60}s`;
  const output = compiler.result?.execution;
  const transferMiB = ((toolchain.compiler.bytes + toolchain.sysroot.bytes) / 1024**2).toFixed(1);

  return <div className="pg-workspace site-shell" data-pg-layout={layout} data-pg-debugging={compiler.debugging ? "true" : "false"}>
    <header className="pg-toolbar">
      <div className="pg-heading"><h1>Playground</h1><p>Guest · Rust runs on your device</p></div>
      <div className="pg-actions">
        <button className="pg-button pg-check" onClick={() => run("check")} disabled={!source || isBusy || expired || blocked}>✓ Check</button>
        <button className="pg-button" onClick={() => run("debug")} disabled={!source || isBusy || expired || blocked} aria-label="Debug Rust">◇ Debug</button>
        {isBusy ? <button className="pg-button pg-primary" onClick={compiler.stop}>■ Stop</button> : <button className="pg-button pg-primary" onClick={() => run("run")} disabled={!source || expired || blocked}>▶ Run</button>}
        <button className="pg-button" onClick={() => setModal("import")} disabled={!source || readOnly}>Import</button>
        <button className="pg-button" onClick={() => setModal("share")} disabled={!source || expired} aria-label="Share Playground">↗ Share<span className="pg-wide-label"> Playground</span></button>
        <button className="pg-button" onClick={() => setModal("connect")} disabled={!source || expired} aria-label="Connect AI">✦ Connect AI</button>
        <button className="pg-button pg-save" onClick={save} disabled={!source} aria-label="Save to device">↓ Save<span className="pg-wide-label"> to device</span></button>
        <button className="pg-icon-button" aria-label="Editor settings" title="Editor settings" onClick={() => setModal("settings")}>⚙</button>
      </div>
    </header>
    <div className="pg-session-bar"><span className={expired ? "pg-expired" : ""}>{lifetimeLabel}</span><span>{link && expiresAt && now ? `Until ${new Date(expiresAt).toLocaleString()}` : draftStatus}</span><span className="pg-connection" role="status">{connection}</span>{link ? <button className="pg-link-button" onClick={() => copyToLocal()} disabled={!source || blocked} title={blocked ? "A blocked project cannot become a local draft. Save to device exports every file." : undefined}>Copy to local</button> : null}</div>
    {blocked && view ? <div className="pg-notice pg-blocked" role="status"><span>Run is paused: {view.blocked.map(reason => blockedSummary[reason]).join(" ")} Editing, recovery and Save to device still work.</span></div> : null}
    {notice || compiler.error ? <div className="pg-notice" role="alert"><span>{notice || compiler.error}</span><button className="pg-icon-button" aria-label="Dismiss notice" onClick={() => { setNotice(""); compiler.clearError(); }}>×</button></div> : null}
    <div className="pg-main-layout">
      <aside className={`pg-files ${filePane ? "pg-files-visible" : ""}`}>
        <div className="pg-sidebar-heading"><strong>PROJECT FILES</strong><span className="pg-sidebar-tools"><button className="pg-icon-button" aria-label="Add source file" title="New file" onClick={() => { setFileRequest({ action: "new-file", folder: false, path: "" }); setModal("file"); }} disabled={readOnly}>＋</button><button className="pg-icon-button" aria-label="Add folder and file" title="New folder and file" onClick={() => { setFileRequest({ action: "new-folder", folder: true, path: "" }); setModal("file"); }} disabled={readOnly}>▤</button></span></div>
        <label className="pg-project-name"><span>Project name</span><input value={nameDraft ?? source?.name ?? ""} maxLength={80} disabled={!source || readOnly} onChange={event => setNameDraft(event.target.value)} onBlur={commitName} onKeyDown={event => { if (event.key === "Enter") event.currentTarget.blur(); }} /></label>
        <FileTree paths={view?.files.map(file => file.path) ?? []} selected={selectedPath} entryFile={source?.entryFile} readOnly={readOnly} shared={!!link && view?.codec !== 2} conflicts={new Set(view?.files.filter(file => file.conflict).map(file => file.path))} storageKey={`crabrix.playground.tree.${link?.id ?? draftId}`} onOpen={path => { setSelected(keyOfPath(path)); setFilePane(false); }} onAction={treeAction} />
        {view?.codec === 2 ? <RecoveryPanel rows={view.recovery} readOnly={readOnly} onRestore={restoreRow} onClear={clearRow} onDownload={row => download(row.path.slice(row.path.lastIndexOf("/") + 1), strToU8(row.text), "text/plain")} /> : null}
        <div className="pg-sidebar-bottom"><button className="pg-button" onClick={() => void openInApp()} disabled={!source || sharing || expired}>Open in Crabrix ↗</button><a href="https://apps.apple.com/app/id6809502653">Get Crabrix for iPhone / iPad</a><p>Source only · 16 files · 128 KiB total. No account or website storage.</p></div>
      </aside>
      <div className="pg-editor-stack">
        <div className="pg-file-bar"><button className="pg-files-toggle pg-button" onClick={() => setFilePane(!filePane)}>☷ Files</button><strong title={selectedPath}><span className="pg-breadcrumb">{selectedPath.includes("/") ? selectedPath.slice(0, selectedPath.lastIndexOf("/") + 1) : ""}</span>{selectedPath.slice(selectedPath.lastIndexOf("/") + 1)}</strong><span>{view?.entryKey === selected ? "Entry" : "Source"}</span><span className="pg-toolchain">rustc {toolchain.rustVersion} · {toolchain.target}</span></div>
        <section className="pg-editor-area" aria-label="Code">{fileState ? <PlaygroundCodeEditor filePath={selectedPath} awareness={awareness} maximumBytes={Math.min(65536, 131072 - sourceBytes(source?.files ?? {}) + new TextEncoder().encode(sourceText).length)} fileState={fileState} readOnly={readOnly} preferences={preferences} breakpoints={breakpoints[selected] ?? []} currentLine={compiler.debugPause?.site.file === selectedPath ? compiler.debugPause.site.line : undefined} onBreakpoint={line => toggleBreakpoint(selected, line)} onLimit={() => setNotice("Source limit: 64 KiB per file and 128 KiB for the complete project.")} /> : <div className="pg-empty-state">{link ? "Waiting for the encrypted source…" : "Preparing the editor…"}</div>}</section>
        <div className="pg-source-budget"><span>{source ? `${Object.keys(source.files).length}/16 files · ${(sourceBytes(source.files) / 1024).toFixed(1)}/128 KiB` : ""}</span><span>{sourceText ? `${new TextEncoder().encode(sourceText).length} bytes` : ""}</span></div>
        <div className="pg-dock-tabs" role="tablist" aria-label="Build panels">{[["output", "Output"], ["problems", `Problems ${diagnostics.filter(item => item.level === "error").length}`], ["debug", "Debug"], ["stdin", "Input"], ["details", "Session"]].map(([key, label]) => <button key={key} role="tab" aria-selected={dock === key} className={dock === key ? "pg-tab pg-tab-active" : "pg-tab"} onClick={() => setDock(key)}>{label}</button>)}</div>
        <section className="pg-output" aria-live="polite">
          {staleResult && (dock === "output" || dock === "problems") ? <p className="pg-stale-result" role="status">The source changed after this result. Check or Run again to test the current files.</p> : null}
          {dock === "debug" ? <>{!compiler.debugPause ? <div className="pg-stage">{compiler.stage}</div> : null}<DebugPanel key={compiler.debugPause?.runningMs ?? "running"} paused={compiler.debugPause} active={compiler.debugging} command={compiler.command} pause={compiler.pauseDebug} breakpoints={breakpoints} remove={toggleBreakpoint} /></> : null}
          {dock === "output" ? <>{runtime.status?.sharedOutput && compiler.activity==='idle' ? <article aria-label="Shared output"><strong>Shared output from {runtime.status.sharedOutput.name}</strong><p>Reported by that participant · no code ran on this client{runtime.status.sharedOutput.truncated ? ' · preview truncated; full output stays on the executing client' : ''}</p><pre>{runtime.status.sharedOutput.stdout || '(No stdout)'}</pre>{runtime.status.sharedOutput.stderr ? <pre className="pg-error-text">{runtime.status.sharedOutput.stderr}</pre> : null}</article> : null}<div className="pg-stage">{compiler.stage}</div>{output ? <><pre>{output.stdout || "(No stdout)"}</pre>{output.stderr || output.trap ? <pre className="pg-error-text">{output.stderr}{output.trap}</pre> : null}<p className="pg-build-time">Exit {output.exitCode} · {(compiler.result!.durationMs / 1000).toFixed(2)}s total · compiled locally</p></> : <p>{compiler.ready ? "Use Run to execute the current Rust source." : `First Run downloads the verified Rust toolchain (${transferMiB} MiB). It is cached on this device when browser storage allows. Source is never sent for compilation.`}</p>}</> : null}
          {dock === "problems" ? diagnostics.length ? diagnostics.map((item, index) => <article className="pg-diagnostic" key={index}><strong>{item.level}{item.code?.code ? ` · ${item.code.code}` : ""}: {item.message}</strong>{item.spans?.filter((span: { is_primary: boolean }) => span.is_primary).map((span: { file_name: string; line_start: number; column_start: number }, i: number) => <button key={i} className="pg-diagnostic-location" onClick={() => setSelected(keyOfPath(span.file_name.replace(/^\/work\//, "")))}>{span.file_name}:{span.line_start}:{span.column_start}</button>)}<pre>{item.rendered}</pre></article>) : <p>{compiler.result?.compilation.exitCode === 0 ? "Rust accepted the current build snapshot." : compiler.result?.compilation.stderr || compiler.result?.compilation.trap || "Compiler diagnostics appear here after Check or Run."}</p> : null}
          {dock === "stdin" ? <label className="pg-stdin"><span>Standard input · supplied to the next Run · maximum 32 KiB</span><textarea value={stdin} onChange={event => { if (new TextEncoder().encode(event.target.value).length <= 32768) setStdin(event.target.value); }} spellCheck={false} placeholder="Input for the program…" /></label> : null}
          {dock === "details" ? <><h2>{link ? "A temporary room" : "A local draft"}</h2><p>{lifetimeLabel}. {link ? "When the room ends, your text stays open here: use Copy to local or download it." : "A shared room gets its own lifetime when you create it. Until then this draft is on this device only."} A saved native Crabrix project remains available on your device.</p>{receipts.length ? <><h3>Imported in this visit</h3><ul>{receipts.map((receipt, index) => <li key={index}>{receipt.label}{receipt.ref ? ` · ${receipt.ref}` : ""}{receipt.commit ? ` · ${receipt.commit.slice(0, 12)}` : ""}{receipt.folder ? ` · ${receipt.folder}` : ""} · {Object.keys(receipt.paths).length} files</li>)}{receipts.length > 1 ? <li>This project has files from several sources.</li> : null}</ul></> : null}<p>Shared rooms use AES-256-GCM. The key is in the link fragment. The relay keeps encrypted data in memory until expiry; server restart can end a session earlier.</p><p>The compiler runs standard-library Rust, including multiple local modules. Cargo dependencies, native libraries and server networking are not supplied by this browser path.</p><p>Debug builds insert local checkpoints into source functions, including async bodies. Stepping, active poll stacks and bounded String, Vec and concrete local struct previews run on this device. Normal Run is unchanged. Macro expansions, const bodies and dependency internals are not stepped. Browser Debug uses std/local modules; Cargo/Tokio is available only through the app’s supported offline dependencies.</p><p><a href="/guide/#playground" target="_blank" rel="noreferrer">Playground guide</a> · <a href="/licenses/PlaygroundThirdPartyNotices.txt" target="_blank" rel="noreferrer">Editor and runtime licenses</a></p></> : null}
        </section>
      </div>
    </div>
    <dialog ref={dialog} className="pg-dialog" onCancel={() => { setModal(null); setFileRequest(null); }}>
      <div className="pg-dialog-heading"><h2>{modal === "share" ? "Share this Playground" : modal === "settings" ? "Editor settings" : modal === "connect" ? "Connect AI" : modal === "file" && fileRequest ? fileDialogTitle(fileRequest) : modal === "leave" ? "Leave this page?" : "Import source"}</h2><button className="pg-icon-button" aria-label="Close" onClick={() => { setModal(null); setFileRequest(null); }}>×</button></div>
      {notice ? <p className="pg-notice" role="status">{notice}</p> : null}
      {modal === "share" ? <div className="pg-dialog-body pg-share-body">
        <div className="pg-share-summary"><strong>Code together. Run on your device.</strong><p>No account needed. Your link contains the decryption key. Share it only with your participants.</p>{view?.codec === 2 || (!link && stableFileRooms()) ? <p>This room keeps stable file IDs, so anyone can rename, move or delete files. The Crabrix app needs version 1.1.5 or newer to open it.</p> : null}</div>
        {!link ? <><fieldset className="pg-lifetime"><legend>Link lifetime</legend><div className="pg-lifetime-options">{[[3600,"1 hour"],[14400,"4 hours"],[43200,"12 hours"],[86400,"24 hours"]].map(([seconds,label]) => <button key={seconds} type="button" aria-pressed={lifetime === seconds} onClick={() => setLifetime(Number(seconds))}>{label}</button>)}</div><p>The timer starts when you create the link. This draft has no time limit until then.</p></fieldset><button className="pg-button pg-save pg-share-create" disabled={sharing} onClick={() => void share().catch(error => setNotice(String(error)))}>{sharing ? "Encrypting source…" : "Create share link"}<span aria-hidden="true">↗</span></button></> : <>
          <label>{link.mode === "view" ? "View-only Playground link" : "Interview link · shared editing"}<textarea readOnly value={playgroundLink(link)} onFocus={event => event.target.select()} /></label>
          <button className="pg-button" onClick={() => void navigator.clipboard.writeText(playgroundLink(link)).then(() => setNotice("Playground link copied."), () => setNotice("Select and copy the link above."))}>Copy Playground link</button>
          {created ? <label>View-only link<textarea readOnly value={playgroundLink({ ...created, access: created.view, mode: "view" })} onFocus={event => event.target.select()} /></label> : null}
          <p><strong>{lifetimeLabel}</strong> · {expiresAt ? new Date(expiresAt).toLocaleString() : ""}. Opening a link does not renew it.</p>
          <button className="pg-button" onClick={() => void openInApp()}>Open / save a local copy in Crabrix</button>
          <button className="pg-button" onClick={() => { setModal(null); copyToLocal(); }}>Copy to a local draft</button>
          {created ? <button className="pg-button" onClick={async () => { if (!window.confirm("End this temporary room for every participant? Saved device copies remain.")) return; try { const response = await fetch(`/api/playground/rooms/${created.id}/`, { method: "DELETE", headers: { Authorization: "Bearer " + created.owner }, credentials: "omit" }); if (!response.ok) throw new Error("Could not end this room."); session.current?.stop(); setExpired(true); } catch (error) { setNotice(String(error)); } }}>End room for everyone</button> : null}
        </>}
        {link ? <RuntimePermissions runtime={runtime} /> : null}
        <div className="pg-share-download"><span>Keep a permanent copy on this device</span><button className="pg-button" onClick={save}>Download source ZIP ↓</button></div>
        <div className="pg-share-summary"><strong>Bring an AI agent into this editor</strong><p>The Crabrix MCP bridge joins your room as a named participant. Give it the link only when you want it to read or edit your source.</p><button className="pg-button" onClick={() => setModal("connect")}>Connect AI</button></div>
      </div> : null}
      {modal === "settings" ? <div className="pg-dialog-body"><h3>Appearance</h3><div className="pg-theme-grid">{themeOptions.map(([value, label]) => <button key={value} aria-pressed={theme === value} className={theme === value ? "pg-theme pg-selected" : "pg-theme"} onClick={() => setTheme(value)}>{label}<span>{theme === value ? "●" : "○"}</span></button>)}</div><h3>Editor</h3><label>Font size<input type="range" min={12} max={24} value={preferences.fontSize} onChange={event => setPreferences({ ...preferences, fontSize: Number(event.target.value) })} /></label><label>Tab width<select value={preferences.tabSize} onChange={event => setPreferences({ ...preferences, tabSize: Number(event.target.value) })}><option value={2}>2 spaces</option><option value={4}>4 spaces</option></select></label><label className="pg-checkbox"><input type="checkbox" checked={preferences.pairs} onChange={event => setPreferences({ ...preferences, pairs: event.target.checked })} />Pair brackets and quotes</label><label className="pg-checkbox"><input type="checkbox" checked={preferences.wrap} onChange={event => setPreferences({ ...preferences, wrap: event.target.checked })} />Wrap long lines</label><label>Panels<select value={layout} onChange={event => setLayout(event.target.value)}><option value="auto">Automatic</option><option value="vertical">Output below code</option><option value="horizontal">Output beside code</option></select></label><button className="pg-button" onClick={() => { setPreferences(defaultPreferences); setLayout("auto"); }}>Reset editor preferences</button><h3>Drafts on this device</h3><label className="pg-checkbox"><input type="checkbox" checked={keepDrafts} onChange={event => setDraftKeeping(event.target.checked)} />Keep drafts in this browser</label><p className="pg-field-note">Source only, with no room links or permissions. Without this, a draft lasts until you leave and Save to device is your copy.</p>{draftStatus ? <p className="pg-field-note" role="status">{draftStatus}</p> : null}{keepDrafts && drafts.length ? <ul className="pg-import-list-plain">{drafts.map(draft => <li key={draft.id} className="pg-draft-row"><span>{draft.name} · {new Date(draft.updatedAt).toLocaleString()}</span><span><button className="pg-link-button" disabled={draft.id === draftId} onClick={() => { setModal(null); onOpenLocal(draft.document, { notice: `Opened your draft ${draft.name}.`, draftId: draft.id, unsaved: false }); }}>Open</button> <button className="pg-link-button" onClick={() => void deleteDraft(draft.id).then(() => listDrafts()).then(setDrafts, () => setDraftStatus("Browser storage is unavailable."))}>Delete</button></span></li>)}</ul> : null}</div> : null}
      {modal === "import" && source ? <ImportDialog current={() => readView(doc, codecOf()).document} shared={!!link && codecOf() === 1} onApply={applyImport} onCopyToLocal={() => { setModal(null); copyToLocal(); }} onClose={() => setModal(null)} /> : null}
      {modal === "connect" ? <ConnectAIDialog link={link} created={created} awareness={awareness} sharing={sharing} share={share} lifetime={lifetime} setLifetime={setLifetime}>{link ? <RuntimePermissions runtime={runtime} /> : null}</ConnectAIDialog> : null}
      {modal === "file" && fileRequest && source ? <FileDialog key={`${fileRequest.action}:${fileRequest.path}`} request={fileRequest} source={source} check={checkFile} recoverable={view?.codec === 2} onSubmit={applyFilePlan} onCancel={() => { setModal(null); setFileRequest(null); }} /> : null}
      {modal === "leave" ? <div className="pg-dialog-body"><p>{link ? "This room's source has not all reached the relay, or the room has ended. Leaving now can lose it." : "This draft is only in this page. Download it to keep a copy."}</p><div className="pg-dialog-actions"><button className="pg-button" onClick={() => setModal(null)}>Stay</button><button className="pg-button" onClick={() => { const target = leaveTo; unsaved.current = false; if (guard.current.link) guard.current = { link: false, expired: false }; if (target) location.assign(target); }}>Leave without saving</button><button className="pg-button pg-save" onClick={() => { const target = leaveTo; save(); guard.current = { link: false, expired: false }; if (target) location.assign(target); }}>Download and leave</button></div></div> : null}
    </dialog>
  </div>;
}
