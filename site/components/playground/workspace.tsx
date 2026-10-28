"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { DebugPanel } from "./debug-panel";
import * as Y from "yjs";
import { createPresence } from "@/lib/playground-presence";
import { zipSync, strToU8 } from "fflate";
import { documentFromY, updateYDocument } from "@/lib/playground-collab";
import { newPlaygroundDocument, sourceBytes, validatePlaygroundDocument, type PlaygroundDocument } from "@/lib/playground-document";
import { createPlayground, parsePlaygroundLink, playgroundLink, PlaygroundSession, type PlaygroundLink, type CreatedPlayground } from "@/lib/playground-session";
import { PlaygroundCodeEditor, type EditorPreferences } from "./code-editor";
import { useRustCompiler } from "./use-rust-compiler";
import { importPublicSource } from "@/lib/playground-import";
import toolchain from "@/lib/playground-toolchain.json";

type Theme = "system" | "light" | "dark" | "amber" | "cyberpunk";
type Modal = "share" | "settings" | "import" | null;
const themes: [Theme, string][] = [["system", "Auto"], ["light", "Light"], ["dark", "Dark"], ["amber", "Amber Circuit"], ["cyberpunk", "Cyberpunk"]];
const defaultPreferences: EditorPreferences = { fontSize: 15, wrap: false, pairs: true, tabSize: 4 };

function download(name: string, bytes: Uint8Array, type: string) {
  const blob = new Blob([new Uint8Array(bytes)], { type });
  const url = URL.createObjectURL(blob), anchor = document.createElement("a");
  anchor.href = url; anchor.download = name; anchor.click(); setTimeout(() => URL.revokeObjectURL(url), 60_000);
}

export default function PlaygroundWorkspace() {
  const [doc] = useState(() => new Y.Doc()), [awareness] = useState(() => createPresence(doc)), [source, setSource] = useState<PlaygroundDocument | null>(null);
  const [selected, setSelected] = useState("main.rs"), [theme, setTheme] = useState<Theme>("system");
  const [preferences, setPreferences] = useState(defaultPreferences), [layout, setLayout] = useState("auto");
  const [modal, setModal] = useState<Modal>(null), dialog = useRef<HTMLDialogElement>(null);
  const [link, setLink] = useState<PlaygroundLink | null>(null), [created, setCreated] = useState<CreatedPlayground | null>(null);
  const session = useRef<PlaygroundSession | null>(null), [connection, setConnection] = useState("Local editor · no source upload");
  const [expiresAt, setExpiresAt] = useState<number | null>(null), [now, setNow] = useState<number | null>(null), createdAt = useRef(0);
  const [lifetime, setLifetime] = useState(3600), [expired, setExpired] = useState(false), [sharing, setSharing] = useState(false);
  const [notice, setNotice] = useState(""), [stdin, setStdin] = useState(""), [dock, setDock] = useState("output");
  const [filePane, setFilePane] = useState(false), [importText, setImportText] = useState("");
  const disposal = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const compiler = useRustCompiler();
  const [breakpoints, setBreakpoints] = useState<Record<string, number[]>>({});
  const debugStatus = useRef({ active: false, stop: compiler.stop }); debugStatus.current = { active: compiler.debugging, stop: compiler.stop };
  const toggleBreakpoint = useCallback((file: string, line: number) => setBreakpoints(previous => ({ ...previous, [file]: previous[file]?.includes(line) ? previous[file].filter(value => value !== line) : [...(previous[file] ?? []), line].sort((a, b) => a - b) })), []);
  useEffect(() => { compiler.updateBreakpoints(breakpoints); }, [breakpoints, compiler.updateBreakpoints]);
  useEffect(() => { if (compiler.debugPause) { setSelected(compiler.debugPause.site.file); setDock("debug"); } }, [compiler.debugPause]);
  const [importURL, setImportURL] = useState(""), [importFolder, setImportFolder] = useState(""), [importing, setImporting] = useState(false);

  useEffect(() => {
    if (disposal.current) clearTimeout(disposal.current);
    createdAt.current = Date.now(); setNow(Date.now());
    try {
      const saved = JSON.parse(localStorage.getItem("crabrix.playground.preferences.v1") ?? "null");
      if (saved && themes.some(([key]) => key === saved.theme)) setTheme(saved.theme);
      if (saved?.fontSize >= 12 && saved.fontSize <= 24) setPreferences({ fontSize: saved.fontSize, wrap: saved.wrap === true, pairs: saved.pairs !== false, tabSize: saved.tabSize === 2 ? 2 : 4 });
    } catch {}
    const update = (transaction: Y.Transaction) => {
      try {
        if (debugStatus.current.active && transaction.changed.size > 0) { debugStatus.current.stop(); setNotice("Debug stopped because shared source changed. Start Debug again for the new snapshot."); }
        const value = documentFromY(doc); setSource(value);
        setSelected(previous => previous in value.files ? previous : value.entryFile);
      } catch { /* Joining an empty document waits for its authenticated snapshot. */ }
    };
    doc.on("afterTransaction", update);
    try {
      const initial = parsePlaygroundLink(new URL(location.href));
      if (initial) {
        setLink(initial); setExpiresAt(initial.expiresAt); setConnection("Decrypting the temporary Playground…");
        const connection = new PlaygroundSession(doc, initial, setConnection, () => setExpired(true), awareness);
        session.current = connection; void connection.start();
      } else {
        updateYDocument(doc, newPlaygroundDocument(), "initial");
        setExpiresAt(createdAt.current + 3600_000);
      }
    } catch (error) { setNotice(String(error)); }
    return () => { session.current?.stop(); doc.off("afterTransaction", update); disposal.current = setTimeout(() => { awareness.destroy(); doc.destroy(); }, 0); };
  }, [doc, awareness]);

  useEffect(() => {
    const viewport = window.visualViewport;
    const resize = () => { document.body.style.setProperty("--pg-window-height", `${viewport?.height ?? window.innerHeight}px`); };
    resize(); viewport?.addEventListener("resize", resize); window.addEventListener("resize", resize);
    return () => { viewport?.removeEventListener("resize", resize); window.removeEventListener("resize", resize); document.body.style.removeProperty("--pg-window-height"); };
  }, []);
  useEffect(() => {
    try { localStorage.setItem("crabrix.playground.preferences.v1", JSON.stringify({ theme, ...preferences })); } catch {}
  }, [theme, preferences]);
  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(timer);
  }, []);
  useEffect(() => {
    if (now !== null && expiresAt !== null && now >= expiresAt && !expired) {
      setExpired(true); session.current?.stop(); compiler.stop();
    }
  }, [now, expiresAt, expired, compiler.stop]);
  useEffect(() => {
    if (modal && !dialog.current?.open) dialog.current?.showModal();
    if (!modal && dialog.current?.open) dialog.current.close();
  }, [modal]);

  const share = useCallback(async (): Promise<PlaygroundLink> => {
    if (link) return link;
    if (expired) throw new Error("This session expired. Download your code and create a new Playground.");
    setSharing(true); setNotice("");
    try {
      const result = await createPlayground(doc, lifetime);
      setCreated(result); setLink(result); setExpiresAt(result.expiresAt);
      const connection = new PlaygroundSession(doc, result, setConnection, () => setExpired(true), awareness);
      session.current = connection; void connection.start();
      history.replaceState(null, "", playgroundLink(result));
      return result;
    } finally { setSharing(false); }
  }, [doc, link, lifetime, expired, awareness]);

  const openInApp = async () => {
    try {
      const shared = await share();
      const url = new URL(playgroundLink(shared));
      location.href = "crabrix://playground/room/" + shared.id + "/" + url.hash;
      setTimeout(() => { if (document.visibilityState === "visible") setNotice("If Crabrix did not open, install or update it, or download the source ZIP to open from Files."); }, 1800);
    } catch (error) { setNotice(error instanceof Error ? error.message : String(error)); }
  };
  const save = () => {
    if (!source) return;
    try {
      const value = validatePlaygroundDocument(source);
      const files = Object.fromEntries(Object.entries(value.files).map(([path, content]) => [path, strToU8(content)]));
      download(value.name.replace(/[^a-z0-9_-]/gi, "-") + ".zip", zipSync(files), "application/zip");
      setNotice("Downloaded source only. Open the ZIP in Crabrix or save it in Files.");
    } catch (error) { setNotice(String(error)); }
  };
  const addFile = () => {
    if (!source) return;
    const path = prompt("Rust source path, for example src/helpers.rs"); if (!path) return;
    try {
      const next = validatePlaygroundDocument({ ...source, files: { ...source.files, [path]: "" } });
      if (path in source.files) throw new Error("That file already exists.");
      updateYDocument(doc, next); setSelected(path);
    } catch (error) { setNotice(error instanceof Error ? error.message : String(error)); }
  };
  const removeFile = () => {
    if (!source || selected === source.entryFile || !confirm(`Remove ${selected} from this temporary source set?`)) return;
    doc.getMap("files").delete(selected);
  };
  const run = (mode: "check" | "run" | "debug") => {
    if (!source || expired) return;
    try { compiler.start(mode, validatePlaygroundDocument(documentFromY(doc)), stdin); setDock(mode === "check" ? "problems" : mode === "debug" ? "debug" : "output"); }
    catch (error) { setNotice(String(error)); }
  };
  const sourceText = source?.files[selected] ?? "";
  const text = doc.getMap<Y.Text>("files").get(selected);
  const diagnostics = (compiler.result?.compilation.stderr ?? "").split("\n").flatMap(line => {
    try { const value = JSON.parse(line); return value.$message_type === "diagnostic" ? [value] : []; } catch { return []; }
  });
  const isBusy = compiler.activity !== "idle", readOnly = expired || link?.mode === "view" || compiler.debugging;
  const secondsLeft = now !== null && expiresAt !== null ? Math.max(0, Math.ceil((expiresAt - now) / 1000)) : null;
  const lifetimeLabel = secondsLeft === null ? "Preparing session…" : expired ? "Session expired" : `Expires in ${Math.floor(secondsLeft / 3600)}h ${Math.floor(secondsLeft % 3600 / 60)}m ${secondsLeft % 60}s`;
  const output = compiler.result?.execution;
  const transferMiB = ((toolchain.compiler.bytes + toolchain.sysroot.bytes) / 1024**2).toFixed(1);

  return <div className="pg-workspace site-shell" data-pg-theme={theme} data-pg-layout={layout} data-pg-debugging={compiler.debugging ? "true" : "false"}>
    <header className="pg-toolbar">
      <div className="pg-heading"><h1>Playground</h1><p>Guest · Rust runs on your device</p></div>
      <div className="pg-actions">
        <button className="pg-button pg-check" onClick={() => run("check")} disabled={!source || isBusy || expired}>✓ Check</button>
        <button className="pg-button" onClick={() => run("debug")} disabled={!source || isBusy || expired} aria-label="Debug Rust">◇ Debug</button>
        {isBusy ? <button className="pg-button pg-primary" onClick={compiler.stop}>■ Stop</button> : <button className="pg-button pg-primary" onClick={() => run("run")} disabled={!source || expired}>▶ Run</button>}
        <button className="pg-button" onClick={() => setModal("share")} disabled={!source || expired} aria-label="Share Playground">↗ Share<span className="pg-wide-label"> Playground</span></button>
        <button className="pg-button pg-save" onClick={save} disabled={!source} aria-label="Save to device">↓ Save<span className="pg-wide-label"> to device</span></button>
        <button className="pg-icon-button" aria-label="Editor settings" title="Editor settings" onClick={() => setModal("settings")}>⚙</button>
      </div>
    </header>
    <div className="pg-session-bar"><span className={expired ? "pg-expired" : ""}>{lifetimeLabel}</span><span>{expiresAt && now ? `Until ${new Date(expiresAt).toLocaleString()}` : ""}</span><span className="pg-connection" role="status">{connection}</span></div>
    {notice || compiler.error ? <div className="pg-notice" role="alert"><span>{notice || compiler.error}</span><button className="pg-icon-button" aria-label="Dismiss notice" onClick={() => { setNotice(""); compiler.clearError(); }}>×</button></div> : null}
    <div className="pg-main-layout">
      <aside className={`pg-files ${filePane ? "pg-files-visible" : ""}`}>
        <div className="pg-sidebar-heading"><strong>PROJECT FILES</strong><button className="pg-icon-button" aria-label="Add source file" onClick={addFile} disabled={readOnly}>＋</button></div>
        <label className="pg-project-name"><span>Project name</span><input value={source?.name ?? ""} maxLength={80} disabled={!source || readOnly} onChange={event => { const name = event.target.value; if (name.trim()) doc.getMap("meta").set("name", name); }} /></label>
        <div className="pg-file-list">{Object.keys(source?.files ?? {}).sort().map(path => <button key={path} className={path === selected ? "pg-file pg-file-active" : "pg-file"} onClick={() => { setSelected(path); setFilePane(false); }}><span aria-hidden="true">{path.endsWith(".rs") ? "🦀" : path.endsWith(".toml") ? "▣" : "≡"}</span><span>{path}</span></button>)}</div>
        {source && selected !== source.entryFile ? <div className="pg-file-tools"><button onClick={() => { if (!readOnly && selected.endsWith(".rs")) doc.getMap("meta").set("entryFile", selected); }} disabled={readOnly || !selected.endsWith(".rs")}>Set as entry</button><button onClick={removeFile} disabled={readOnly}>Remove file</button></div> : null}
        <div className="pg-sidebar-bottom"><button className="pg-button" onClick={() => setModal("import")} disabled={readOnly}>Import source</button><button className="pg-button" onClick={() => void openInApp()} disabled={!source || sharing || expired}>Open in Crabrix ↗</button><a href="https://apps.apple.com/app/id6809502653">Get Crabrix for iPhone / iPad</a><p>Source only · 16 files · 128 KiB total. No account or permanent website storage.</p></div>
      </aside>
      <div className="pg-editor-stack">
        <div className="pg-file-bar"><button className="pg-files-toggle pg-button" onClick={() => setFilePane(!filePane)}>☷ Files</button><strong>{selected}</strong><span>{source?.entryFile === selected ? "Entry" : "Source"}</span><span className="pg-toolchain">rustc {toolchain.rustVersion} · {toolchain.target}</span></div>
        <section className="pg-editor-area" aria-label="Code">{text && text instanceof Y.Text ? <PlaygroundCodeEditor filePath={selected} awareness={awareness} maximumBytes={Math.min(65536, 131072 - sourceBytes(source?.files ?? {}) + new TextEncoder().encode(sourceText).length)} text={text} readOnly={readOnly} preferences={preferences} breakpoints={breakpoints[selected] ?? []} currentLine={compiler.debugPause?.site.file === selected ? compiler.debugPause.site.line : undefined} onBreakpoint={line => toggleBreakpoint(selected, line)} onLimit={() => setNotice("Source limit: 64 KiB per file and 128 KiB for the complete project.")} /> : <div className="pg-empty-state">{link ? "Waiting for the encrypted source…" : "Preparing the editor…"}</div>}</section>
        <div className="pg-source-budget"><span>{source ? `${Object.keys(source.files).length}/16 files · ${(sourceBytes(source.files) / 1024).toFixed(1)}/128 KiB` : ""}</span><span>{sourceText ? `${new TextEncoder().encode(sourceText).length} bytes` : ""}</span></div>
        <div className="pg-dock-tabs" role="tablist" aria-label="Build panels">{[["output", "Output"], ["problems", `Problems ${diagnostics.filter(item => item.level === "error").length}`], ["debug", "Debug"], ["stdin", "Input"], ["details", "Session"]].map(([key, label]) => <button key={key} role="tab" aria-selected={dock === key} className={dock === key ? "pg-tab pg-tab-active" : "pg-tab"} onClick={() => setDock(key)}>{label}</button>)}</div>
        <section className="pg-output" aria-live="polite">
          {dock === "debug" ? <>{!compiler.debugPause ? <div className="pg-stage">{compiler.stage}</div> : null}<DebugPanel key={compiler.debugPause?.runningMs ?? "running"} paused={compiler.debugPause} active={compiler.debugging} command={compiler.command} pause={compiler.pauseDebug} breakpoints={breakpoints} remove={toggleBreakpoint} /></> : null}
          {dock === "output" ? <><div className="pg-stage">{compiler.stage}</div>{output ? <><pre>{output.stdout || "(No stdout)"}</pre>{output.stderr || output.trap ? <pre className="pg-error-text">{output.stderr}{output.trap}</pre> : null}<p className="pg-build-time">Exit {output.exitCode} · {(compiler.result!.durationMs / 1000).toFixed(2)}s total · compiled locally</p></> : <p>{compiler.ready ? "Use Run to execute the current Rust source." : `First Run downloads the verified Rust toolchain (${transferMiB} MiB). It is cached on this device when browser storage allows. Source is never sent for compilation.`}</p>}</> : null}
          {dock === "problems" ? diagnostics.length ? diagnostics.map((item, index) => <article className="pg-diagnostic" key={index}><strong>{item.level}{item.code?.code ? ` · ${item.code.code}` : ""}: {item.message}</strong>{item.spans?.filter((span: { is_primary: boolean }) => span.is_primary).map((span: { file_name: string; line_start: number; column_start: number }, i: number) => <button key={i} className="pg-diagnostic-location" onClick={() => setSelected(span.file_name.replace(/^\/work\//, ""))}>{span.file_name}:{span.line_start}:{span.column_start}</button>)}<pre>{item.rendered}</pre></article>) : <p>{compiler.result?.compilation.exitCode === 0 ? "Rust accepted the current build snapshot." : compiler.result?.compilation.stderr || compiler.result?.compilation.trap || "Compiler diagnostics appear here after Check or Run."}</p> : null}
          {dock === "stdin" ? <label className="pg-stdin"><span>Standard input · supplied to the next Run · maximum 32 KiB</span><textarea value={stdin} onChange={event => { if (new TextEncoder().encode(event.target.value).length <= 32768) setStdin(event.target.value); }} spellCheck={false} placeholder="Input for the program…" /></label> : null}
          {dock === "details" ? <><h2>Temporary by design</h2><p>{lifetimeLabel}. Copy/download source before the session ends. A saved native Crabrix project remains available on your device.</p><p>Shared rooms use AES-256-GCM. The key is in the link fragment. The relay keeps encrypted data in memory until expiry; server restart can end a session earlier.</p><p>The compiler runs standard-library Rust, including multiple local modules. Cargo dependencies, native libraries and server networking are not supplied by this browser path.</p><p>Debug builds insert local checkpoints into source functions, including async bodies. Stepping, active poll stacks and bounded String, Vec and concrete local struct previews run on this device. Normal Run is unchanged. Macro expansions, const bodies and dependency internals are not stepped. Browser Debug uses std/local modules; Cargo/Tokio is available only through the app’s supported offline dependencies.</p><p><a href="/guide/#playground" target="_blank" rel="noreferrer">Playground guide</a> · <a href="/licenses/PlaygroundThirdPartyNotices.txt" target="_blank" rel="noreferrer">Editor and runtime licenses</a></p></> : null}
        </section>
      </div>
    </div>
    <dialog ref={dialog} className="pg-dialog" onCancel={() => setModal(null)}>
      <div className="pg-dialog-heading"><h2>{modal === "share" ? "Share this Playground" : modal === "settings" ? "Editor settings" : "Import source"}</h2><button className="pg-icon-button" aria-label="Close" onClick={() => setModal(null)}>×</button></div>
      {notice ? <p className="pg-notice" role="status">{notice}</p> : null}
      {modal === "share" ? <div className="pg-dialog-body pg-share-body">
        <div className="pg-share-summary"><strong>Code together. Run on your device.</strong><p>No account needed. Your link contains the decryption key. Share it only with your participants.</p></div>
        {!link ? <><fieldset className="pg-lifetime"><legend>Link lifetime</legend><div className="pg-lifetime-options">{[[3600,"1 hour"],[14400,"4 hours"],[43200,"12 hours"],[86400,"24 hours"]].map(([seconds,label]) => <button key={seconds} type="button" aria-pressed={lifetime === seconds} onClick={() => { setLifetime(Number(seconds)); setExpiresAt(createdAt.current + Number(seconds) * 1000); }}>{label}</button>)}</div><p>The timer starts when you create the link.</p></fieldset><button className="pg-button pg-save pg-share-create" disabled={sharing} onClick={() => void share().catch(error => setNotice(String(error)))}>{sharing ? "Encrypting source…" : "Create share link"}<span aria-hidden="true">↗</span></button></> : <>
          <label>{link.mode === "view" ? "View-only Playground link" : "Interview link · shared editing"}<textarea readOnly value={playgroundLink(link)} onFocus={event => event.target.select()} /></label>
          <button className="pg-button" onClick={() => void navigator.clipboard.writeText(playgroundLink(link)).then(() => setNotice("Playground link copied."), () => setNotice("Select and copy the link above."))}>Copy Playground link</button>
          {created ? <label>View-only link<textarea readOnly value={playgroundLink({ ...created, access: created.view, mode: "view" })} onFocus={event => event.target.select()} /></label> : null}
          <p><strong>{lifetimeLabel}</strong> · {expiresAt ? new Date(expiresAt).toLocaleString() : ""}. Opening a link does not renew it.</p>
          <button className="pg-button" onClick={() => void openInApp()}>Open / save a local copy in Crabrix</button>
          {created ? <button className="pg-button" onClick={async () => { if (!confirm("End this temporary room for every participant? Saved device copies remain.")) return; try { const response = await fetch(`/api/playground/rooms/${created.id}/`, { method: "DELETE", headers: { Authorization: "Bearer " + created.owner }, credentials: "omit" }); if (!response.ok) throw new Error("Could not end this room."); session.current?.stop(); setExpired(true); } catch (error) { setNotice(String(error)); } }}>End room for everyone</button> : null}
        </>}
        <div className="pg-share-download"><span>Keep a permanent copy on this device</span><button className="pg-button" onClick={save}>Download source ZIP ↓</button></div>
        <div className="pg-share-summary"><strong>Bring Claude into this editor</strong><p>The Crabrix MCP bridge joins your temporary room as a named participant. Give its MCP host/model the complete link only when you want it to read or edit your source.</p><a className="pg-button" href="/playground/mcp/" target="_blank" rel="noreferrer">Set up Claude · Download MCP ↗</a></div>
      </div> : null}
      {modal === "settings" ? <div className="pg-dialog-body"><h3>Appearance</h3><div className="pg-theme-grid">{themes.map(([value, label]) => <button key={value} aria-pressed={theme === value} className={theme === value ? "pg-theme pg-selected" : "pg-theme"} onClick={() => setTheme(value)}>{label}<span>{theme === value ? "●" : "○"}</span></button>)}</div><h3>Editor</h3><label>Font size<input type="range" min={12} max={24} value={preferences.fontSize} onChange={event => setPreferences({ ...preferences, fontSize: Number(event.target.value) })} /></label><label>Tab width<select value={preferences.tabSize} onChange={event => setPreferences({ ...preferences, tabSize: Number(event.target.value) })}><option value={2}>2 spaces</option><option value={4}>4 spaces</option></select></label><label className="pg-checkbox"><input type="checkbox" checked={preferences.pairs} onChange={event => setPreferences({ ...preferences, pairs: event.target.checked })} />Pair brackets and quotes</label><label className="pg-checkbox"><input type="checkbox" checked={preferences.wrap} onChange={event => setPreferences({ ...preferences, wrap: event.target.checked })} />Wrap long lines</label><label>Panels<select value={layout} onChange={event => setLayout(event.target.value)}><option value="auto">Automatic</option><option value="vertical">Output below code</option><option value="horizontal">Output beside code</option></select></label><button className="pg-button" onClick={() => { setPreferences(defaultPreferences); setTheme("system"); setLayout("auto"); }}>Reset editor preferences</button></div> : null}
      {modal === "import" ? <div className="pg-dialog-body"><p>Paste a text-only Playground project JSON, or use the source-file import below. GitHub requests go directly from this browser to GitHub. Imported source never starts automatically.</p><label>GitHub repository, gist or Rust Playground link<input type="url" value={importURL} onChange={event => setImportURL(event.target.value)} placeholder="https://github.com/owner/repository" /></label><label>Source folder (optional)<input value={importFolder} onChange={event => setImportFolder(event.target.value)} placeholder="examples/hello" /></label><button className="pg-button pg-primary" disabled={importing || !importURL} onClick={async () => {
          if (!confirm("Replace this Playground’s source? Download a copy first if you need it.")) return;
          setImporting(true); setNotice("");
          try { const value = await importPublicSource(importURL, importFolder); updateYDocument(doc, value); setSelected(value.entryFile); setModal(null); }
          catch (error) { setNotice(error instanceof Error ? error.message : String(error)); }
          finally { setImporting(false); }
        }}>{importing ? "Reading GitHub source…" : "Import public source"}</button><hr /><textarea className="pg-import-text" aria-label="Project JSON" value={importText} onChange={event => { if (event.target.value.length < 200000) setImportText(event.target.value); }} /><button className="pg-button pg-primary" onClick={() => { try { if (!confirm("Replace this Playground source? Download a copy first if needed.")) return; const value = validatePlaygroundDocument(JSON.parse(importText)); updateYDocument(doc, value); setSelected(value.entryFile); setModal(null); } catch (error) { setNotice(String(error)); } }}>Import text project</button><label>Open a Rust file<input type="file" accept=".rs,text/plain" onChange={async event => { const file = event.target.files?.[0]; if (!file) return; try { if (file.size > 65536) throw new Error("Each file must be at most 64 KiB."); const value = validatePlaygroundDocument({ ...newPlaygroundDocument(), name: file.name.replace(/\.rs$/, ""), entryFile: file.name, files: { [file.name]: await file.text() } }); updateYDocument(doc, value); setSelected(value.entryFile); setModal(null); } catch (error) { setNotice(String(error)); } }} /></label></div> : null}
    </dialog>
  </div>;
}
