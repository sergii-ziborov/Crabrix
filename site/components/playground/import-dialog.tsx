"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { buildImportPlan, canTransition, checkImportPlan, IMPORT_BUDGET, ImportOperations, joinTargetPath, type ConflictChoice, type Edition, type ImportInspection, type ImportPlan, type ImportState } from "@/lib/playground-import-plan";
import { inspectLocalFiles, inspectProjectJSON, inspectPublicSource, inspectZip, loadSelectedText } from "@/lib/playground-import-sources";
import type { PlaygroundDocument } from "@/lib/playground-document";

const kiB = (bytes: number) => `${(bytes / 1024).toFixed(1)} KiB`;
const message = (error: unknown) => error instanceof Error ? error.message : String(error);

type Props = {
  dropped?: { inspection: Promise<ImportInspection>; targetFolder: string };
  /** Reads the live project, never a copy from an earlier render. */
  current: () => PlaygroundDocument;
  shared: boolean;
  onApply: (plan: ImportPlan, document: PlaygroundDocument) => void;
  onCopyToLocal: () => void;
  onClose: () => void;
};

export function ImportDialog({ current, shared, onApply, onCopyToLocal, onClose, dropped }: Props) {
  const [state, setStateRaw] = useState<ImportState>("idle"), [problem, setProblem] = useState("");
  const [url, setURL] = useState(""), [ref, setRef] = useState(""), [folder, setFolder] = useState(""), [json, setJSON] = useState("");
  const [inspection, setInspection] = useState<ImportInspection | null>(null);
  const [selected, setSelected] = useState<Set<string>>(new Set()), [mode, setMode] = useState<"add" | "replace">("add");
  const [target, setTarget] = useState(""), [conflicts, setConflicts] = useState<Record<string, ConflictChoice>>({});
  const [entry, setEntry] = useState(""), [edition, setEdition] = useState<Edition | "">("");
  const [base, setBase] = useState(current);
  const operations = useRef(new ImportOperations());

  const setState = (next: ImportState) => setStateRaw(previous => canTransition(previous, next) || previous === next ? next : previous);
  useEffect(() => { const running = operations.current; return () => running.cancel(); }, []);

  const inspect = async (work: (signal: AbortSignal) => Promise<ImportInspection> | ImportInspection) => {
    const { id, signal } = operations.current.begin();
    setProblem(""); setState("inspecting");
    try {
      const value = await work(signal);
      if (!operations.current.isCurrent(id)) return;
      const usable = value.candidates.filter(item => !item.excluded).map(item => item.path);
      setInspection(value); setBase(current()); setConflicts({}); setEntry(""); setEdition(""); setMode("add");
      // A source larger than the budget starts empty, so nothing is chosen by accident.
      setSelected(new Set(usable.length <= IMPORT_BUDGET.files ? usable : []));
      setStateRaw("selecting");
    } catch (error) {
      if (!operations.current.isCurrent(id)) return;
      setProblem(message(error)); setStateRaw("error");
    }
  };

  const readFiles = async (list: FileList | null, kind: "files" | "folder") => {
    if (!list?.length) return;
    const files = Array.from(list);
    await inspect(async () => inspectLocalFiles(await Promise.all(files.map(async file => {
      if (file.size > 16 * 1024 * 1024) return { path: file.webkitRelativePath || file.name, bytes: new Uint8Array(IMPORT_BUDGET.fileBytes + 1) };
      return { path: file.webkitRelativePath || file.name, bytes: new Uint8Array(await file.arrayBuffer()) };
    })), kind, kind === "folder" ? "Local folder" : "Local files"));
  };

  useEffect(() => {
    if (!dropped) return;
    setTarget(dropped.targetFolder);
    void inspect(() => dropped.inspection);
  }, [dropped]); // The drop is immutable; inspect reads current() before its review.

  const choices = useMemo(() => ({ selected, mode, targetFolder: target, conflicts, entryFile: entry || undefined, edition: edition || undefined }), [selected, mode, target, conflicts, entry, edition]);
  const plan = useMemo(() => inspection ? buildImportPlan(base, inspection, choices) : null, [inspection, base, choices]);

  // GitHub blobs are read here, only for the files chosen, and from the pinned tree.
  const review = async () => {
    if (!inspection) return;
    const { id, signal } = operations.current.begin();
    setProblem(""); setState("inspecting");
    try {
      const value = await loadSelectedText(inspection, selected, { signal });
      if (!operations.current.isCurrent(id)) return;
      setInspection(value); setBase(current()); setStateRaw("ready");
    } catch (error) {
      if (!operations.current.isCurrent(id)) return;
      setProblem(message(error)); setStateRaw("selecting");
    }
  };

  const apply = () => {
    if (!plan) return;
    const outcome = checkImportPlan(plan, current(), shared);
    if (outcome.status === "needs_refresh") { setBase(current()); setStateRaw("needs_refresh"); return; }
    if (outcome.status === "blocked") { setProblem(outcome.reason); return; }
    setState("applying");
    onApply(plan, outcome.document);
    setStateRaw("complete");
    onClose();
  };

  const cancel = () => { operations.current.cancel(); onClose(); };
  const back = () => { operations.current.cancel(); setStateRaw("selecting"); };
  const restart = () => { operations.current.cancel(); setInspection(null); setProblem(""); setStateRaw("idle"); };
  const toggle = (path: string) => setSelected(previous => { const next = new Set(previous); if (next.has(path)) next.delete(path); else next.add(path); return next; });

  const busy = state === "inspecting";
  if (!inspection || state === "idle" || state === "error" || (state === "inspecting" && !inspection)) return <div className="pg-dialog-body pg-import">
    <p>Nothing changes until you review the result and choose Apply. GitHub requests go directly from this browser to GitHub. Imported source never starts automatically.</p>
    {problem ? <p className="pg-field-problem" role="alert">{problem}</p> : null}
    <fieldset disabled={busy}><legend>Public GitHub or gist</legend>
      <label>Repository, folder, file, gist or Rust Playground link<input type="url" value={url} spellCheck={false} onChange={event => setURL(event.target.value)} placeholder="https://github.com/owner/repository" /></label>
      <div className="pg-import-row"><label>Ref (optional)<input value={ref} spellCheck={false} onChange={event => setRef(event.target.value)} placeholder="feature/parser" /></label><label>Folder (optional)<input value={folder} spellCheck={false} onChange={event => setFolder(event.target.value)} placeholder="examples/hello" /></label></div>
      <button className="pg-button pg-primary" type="button" disabled={!url.trim()} onClick={() => void inspect(signal => inspectPublicSource(url, { signal, ref, folder }))}>{busy ? "Reading…" : "List files"}</button>
    </fieldset>
    <fieldset disabled={busy}><legend>From this device</legend>
      <div className="pg-import-row">
        <label className="pg-file-pick">Files<input type="file" multiple onChange={event => void readFiles(event.target.files, "files")} /></label>
        <label className="pg-file-pick">Folder<input type="file" {...{ webkitdirectory: "", directory: "" }} onChange={event => void readFiles(event.target.files, "folder")} /></label>
        <label className="pg-file-pick">Source ZIP<input type="file" accept=".zip,application/zip" onChange={event => { const file = event.target.files?.[0]; if (file) void inspect(async () => { if (file.size > 16 * 1024 * 1024) throw new Error("This archive is larger than 16 MiB. Extract the part you need and import that folder."); return inspectZip(new Uint8Array(await file.arrayBuffer()), file.name); }); }} /></label>
      </div>
      <p className="pg-field-note">Local files are read in this browser and are not uploaded.</p>
    </fieldset>
    <fieldset disabled={busy}><legend>Project JSON</legend>
      <textarea className="pg-import-text" aria-label="Project JSON" value={json} onChange={event => { if (event.target.value.length < 200_000) setJSON(event.target.value); }} />
      <button className="pg-button" type="button" disabled={!json.trim()} onClick={() => void inspect(() => inspectProjectJSON(json))}>Read JSON</button>
    </fieldset>
    <div className="pg-dialog-actions"><button type="button" className="pg-button" onClick={cancel}>{busy ? "Cancel" : "Close"}</button></div>
  </div>;

  const usable = inspection.candidates.filter(item => !item.excluded);
  const excluded = inspection.candidates.filter(item => item.excluded);
  const selectedBytes = usable.filter(item => selected.has(item.path)).reduce((sum, item) => sum + item.bytes, 0);
  const entryChoices = Array.from(new Set([...(mode === "add" ? Object.keys(base.files) : []), ...usable.filter(item => selected.has(item.path)).map(item => joinTargetPath(target, item.path))])).filter(path => path.endsWith(".rs")).sort();
  const declared = plan?.declaredEdition;

  return <div className="pg-dialog-body pg-import">
    <dl className="pg-import-source"><div><dt>Source</dt><dd>{inspection.label}</dd></div>{inspection.ref ? <div><dt>Ref</dt><dd>{inspection.ref}</dd></div> : null}{inspection.folder ? <div><dt>Folder</dt><dd>{inspection.folder}</dd></div> : null}{inspection.origin?.commit ? <div><dt>Commit</dt><dd><code>{inspection.origin.commit.slice(0, 12)}</code></dd></div> : null}</dl>
    {inspection.notes.map(note => <p key={note} className="pg-field-note">{note}</p>)}
    {problem ? <p className="pg-field-problem" role="alert">{problem}</p> : null}
    {state === "needs_refresh" ? <p className="pg-field-problem" role="alert">The project changed while this preview was open. Review the updated result below before applying.</p> : null}

    {state === "selecting" || state === "inspecting" ? <>
      <fieldset disabled={busy}><legend>Files · {selected.size} chosen · {kiB(selectedBytes)}</legend>
        <div className="pg-import-row"><button type="button" className="pg-button" disabled={usable.length > IMPORT_BUDGET.files} onClick={() => setSelected(new Set(usable.map(item => item.path)))}>Choose all</button><button type="button" className="pg-button" onClick={() => setSelected(new Set())}>Clear</button></div>
        <ul className="pg-import-list">{usable.map(item => <li key={item.path}><label className="pg-checkbox"><input type="checkbox" checked={selected.has(item.path)} onChange={() => toggle(item.path)} /><span>{item.path}</span><small>{item.bytes ? kiB(item.bytes) : ""}</small></label></li>)}</ul>
        {excluded.length ? <details><summary>{excluded.length} not available</summary><ul className="pg-import-list-plain">{excluded.map(item => <li key={item.path}>{item.path} — {item.excluded}</li>)}</ul></details> : null}
      </fieldset>
      <fieldset disabled={busy}><legend>Result</legend>
        <label>How to apply<select value={mode} onChange={event => setMode(event.target.value as "add" | "replace")}><option value="add">Add to this project</option><option value="replace" disabled={shared}>Replace this project</option></select></label>
        {shared ? <p className="pg-field-note">Replacing is not available in a shared room, because it could lose a participant&rsquo;s unsent edit. <button type="button" className="pg-link-button" onClick={onCopyToLocal}>Copy to a local draft</button> to replace there.</p> : null}
        <label>Into folder (optional)<input value={target} spellCheck={false} onChange={event => setTarget(event.target.value)} placeholder="src/imported" /></label>
      </fieldset>
      <div className="pg-dialog-actions"><button type="button" className="pg-button" onClick={restart}>Other source</button><button type="button" className="pg-button" onClick={cancel}>Cancel</button><button type="button" className="pg-button pg-primary" disabled={busy || !selected.size} onClick={() => void review()}>{busy ? "Reading files…" : "Review"}</button></div>
    </> : <>
      <p>{plan?.added.length ?? 0} added · {plan?.replaced.length ?? 0} replaced · {plan?.removed.length ?? 0} removed · {plan?.skipped.length ?? 0} skipped</p>
      <p>{plan?.fileCount ?? 0}/{IMPORT_BUDGET.files} files · {kiB(plan?.bytes ?? 0)}/128 KiB</p>
      {plan?.removed.length ? <details open><summary>Removed from the project</summary><ul className="pg-import-list-plain">{plan.removed.map(item => <li key={item}>{item}</li>)}</ul></details> : null}
      {plan?.conflicts.length ? <fieldset><legend>Already in the project</legend><ul className="pg-import-list-plain">{plan.conflicts.map(path => <li key={path}><label>{joinTargetPath(target, path)}<select value={conflicts[path] ?? ""} onChange={event => setConflicts(previous => ({ ...previous, [path]: event.target.value as ConflictChoice }))}><option value="" disabled>Choose…</option><option value="skip">Keep the existing file</option><option value="replace">Replace with the imported file</option><option value="rename">Keep both, rename the imported file</option></select></label></li>)}</ul></fieldset> : null}
      <div className="pg-import-row">
        <label>Entry file<select value={entry || plan?.entryFile || ""} onChange={event => setEntry(event.target.value)}>{!plan?.entryFile ? <option value="">Choose…</option> : null}{entryChoices.map(path => <option key={path}>{path}</option>)}</select></label>
        <label>Edition for this runner<select value={edition || plan?.edition || ""} onChange={event => setEdition(event.target.value as Edition)}>{!plan?.edition ? <option value="">Choose…</option> : null}<option value="2021">2021</option><option value="2024">2024</option></select></label>
      </div>
      {declared?.kind === "unsupported" ? <p className="pg-field-note">Cargo.toml declares edition {declared.value}. It stays as written; the runner uses the edition chosen above.</p> : null}
      {declared?.kind === "workspace" ? <p className="pg-field-note">Cargo.toml inherits its edition from a workspace that is not resolved here. It stays as written.</p> : null}
      {plan?.document && base.origin && !plan.document.origin ? <p className="pg-field-note">This project will contain files from more than one source, so it no longer records a single origin.</p> : null}
      <p className={plan?.error ? "pg-field-problem" : "pg-field-note"} role="status">{plan?.error ?? plan?.readiness.message}</p>
      <div className="pg-dialog-actions"><button type="button" className="pg-button" onClick={back}>Back</button><button type="button" className="pg-button" onClick={cancel}>Cancel</button><button type="button" className="pg-button pg-primary" disabled={!plan?.document} onClick={apply}>Apply</button></div>
    </>}
  </div>;
}
