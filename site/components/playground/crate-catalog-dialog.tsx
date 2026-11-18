"use client";

import { useEffect, useId, useRef, useState, type FormEvent, type KeyboardEvent, type RefObject } from "react";
import {
  CRATE_SEARCH_DEBOUNCE_MS, CRATE_SORTS, DEFAULT_CRATE_SORT, cachedCrateSearch, compactCount, cratePageURL, exactCount, isCrateSort,
  loadCrateDetails, loadCrateOwners, ownerName, preferredVersion, rustVersionSupported, safeExternalURL, searchCrates, versionRequirement,
  type CrateDetails, type CrateOwnerInfo, type CrateSearchPage, type CrateSort, type CrateSummary,
} from "@/lib/crates-io";
import toolchain from "@/lib/playground-toolchain.json";

type Props = {
  /** Direct dependency names already declared in Cargo.toml. */
  declared: ReadonlySet<string>;
  canAdd: boolean;
  /** Why adding is unavailable right now, when it is. */
  blockedReason?: string;
  /** The manifest error reported by the last failed add. */
  error?: string;
  onAdd: (name: string, requirement: string) => boolean;
  onOpenManifest?: () => void;
  /** Called after the dialog has closed, by any means. */
  onClosed: () => void;
};

type View = { kind: "search" } | { kind: "detail"; crate: CrateSummary } | { kind: "manual"; name: string };
const message = (error: unknown) => error instanceof Error ? error.message : String(error);
const VERSION_PREVIEW = 40;

/** The crates.io catalogue from the app's Cargo packages sheet, as a modal dialog. */
export function CrateCatalogDialog({ declared, canAdd, blockedReason, error, onAdd, onOpenManifest, onClosed }: Props) {
  const dialog = useRef<HTMLDialogElement>(null), titleId = useId();
  const [view, setView] = useState<View>({ kind: "search" });
  const returnFocus = useRef<HTMLElement | null>(null), searchInput = useRef<HTMLInputElement>(null);
  const [query, setQuery] = useState("");

  useEffect(() => {
    const node = dialog.current;
    if (node && !node.open) node.showModal();
    // showModal() focuses the first control (Close); start in the search field instead.
    searchInput.current?.focus();
    // No close() on cleanup: its queued close event would arrive after a StrictMode
    // re-run had reopened the dialog. Unmounting removes it from the top layer anyway.
  }, []);
  const close = () => dialog.current?.close();
  const back = () => {
    setView({ kind: "search" });
    const target = returnFocus.current;
    requestAnimationFrame(() => (target?.isConnected ? target : searchInput.current)?.focus());
  };
  const add = (name: string, requirement: string) => {
    if (!canAdd || !onAdd(name, requirement)) return false;
    close(); return true;
  };

  return <dialog ref={dialog} className="pg-dialog pg-crates" aria-labelledby={titleId} onClose={onClosed}>
    <div className="pg-dialog-heading"><h2 id={titleId}>Cargo packages</h2>
      <button type="button" className="pg-icon-button" aria-label="Close Cargo packages" onClick={close}>×</button></div>
    <CrateSearch hidden={view.kind !== "search"} declared={declared} query={query} setQuery={setQuery} inputRef={searchInput}
      onChoose={(crate, row) => { returnFocus.current = row; setView({ kind: "detail", crate }); }}
      onManual={(name, from) => { returnFocus.current = from; setView({ kind: "manual", name }); }} />
    {view.kind === "detail" ? <CrateDetail key={view.crate.name} crate={view.crate} added={declared.has(view.crate.name)} canAdd={canAdd}
      blockedReason={blockedReason} error={error} onBack={back} onAdd={add}
      onOpenManifest={onOpenManifest ? () => { close(); onOpenManifest(); } : undefined} /> : null}
    {view.kind === "manual" ? <ManualCrateEntry initialName={view.name} declared={declared} canAdd={canAdd} blockedReason={blockedReason}
      error={error} onBack={back} onAdd={add} /> : null}
  </dialog>;
}

function CrateSearch({ hidden, declared, query, setQuery, inputRef, onChoose, onManual }: {
  hidden: boolean; declared: ReadonlySet<string>; query: string; setQuery: (value: string) => void;
  inputRef: RefObject<HTMLInputElement | null>;
  onChoose: (crate: CrateSummary, row: HTMLElement) => void; onManual: (name: string, from: HTMLElement) => void;
}) {
  const [sort, setSort] = useState<CrateSort>(DEFAULT_CRATE_SORT);
  // The committed search; typing commits after the app's 350 ms pause.
  const [term, setTerm] = useState({ query: "", sort: DEFAULT_CRATE_SORT as CrateSort, attempt: 0 });
  const [page, setPage] = useState<(CrateSearchPage & { query: string; sort: CrateSort }) | null>(null);
  const [loading, setLoading] = useState(true), [problem, setProblem] = useState("");
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined), list = useRef<HTMLUListElement>(null);
  const ids = useId(), statusId = ids + "status";

  useEffect(() => () => clearTimeout(timer.current), []);
  useEffect(() => {
    const hit = cachedCrateSearch(term.query, term.sort);
    if (hit) { setPage({ ...hit, query: term.query, sort: term.sort }); setLoading(false); setProblem(""); return; }
    const controller = new AbortController();
    setLoading(true); setProblem("");
    searchCrates(term.query, term.sort, controller.signal).then(result => {
      if (controller.signal.aborted) return;
      setPage({ ...result, query: term.query, sort: term.sort }); setLoading(false);
    }, error => {
      if (controller.signal.aborted) return;
      // Earlier results stay only if they answer this same search (a failed retry);
      // another query's list under this error would look like its results.
      setPage(current => current?.query === term.query && current.sort === term.sort ? current : null);
      setProblem(message(error)); setLoading(false);
    });
    return () => controller.abort();
  }, [term]);

  const commit = (value: string, nextSort: CrateSort) => {
    clearTimeout(timer.current);
    const trimmed = value.trim();
    setTerm(current => current.query === trimmed && current.sort === nextSort ? current : { query: trimmed, sort: nextSort, attempt: 0 });
  };
  const changeQuery = (value: string) => {
    setQuery(value); clearTimeout(timer.current);
    timer.current = setTimeout(() => commit(value, sort), CRATE_SEARCH_DEBOUNCE_MS);
  };
  const submit = (event: FormEvent<HTMLFormElement>) => { event.preventDefault(); commit(query, sort); };
  const retry = () => { clearTimeout(timer.current); setTerm(current => ({ query: query.trim(), sort, attempt: current.attempt + 1 })); };

  const rows = () => Array.from(list.current?.querySelectorAll<HTMLButtonElement>("button[data-crate-row]") ?? []);
  const inputKey = (event: KeyboardEvent<HTMLInputElement>) => {
    if (event.key === "ArrowDown" && rows().length) { event.preventDefault(); rows()[0].focus(); }
  };
  const listKey = (event: KeyboardEvent<HTMLUListElement>) => {
    const all = rows(), index = all.indexOf(document.activeElement as HTMLButtonElement);
    if (index < 0) return;
    const next = event.key === "ArrowDown" ? index + 1 : event.key === "ArrowUp" ? index - 1 : event.key === "Home" ? 0 : event.key === "End" ? all.length - 1 : null;
    if (next === null) return;
    event.preventDefault();
    if (next < 0) inputRef.current?.focus(); else all[Math.min(next, all.length - 1)].focus();
  };

  const crates = page?.crates ?? [], shownQuery = page?.query ?? term.query;
  const typedName = query.trim().toLowerCase();
  const status = loading ? (term.query ? "Searching crates.io…" : "Loading popular crates…")
    : problem ? "" : !crates.length ? `No crates match “${shownQuery}”.`
      : `${crates.length === page!.total ? exactCount(crates.length) : `${exactCount(crates.length)} of ${exactCount(page!.total)}`} crates shown${shownQuery ? ` for “${shownQuery}”` : ""}.`;

  return <div className="pg-crates-view" hidden={hidden}>
    <form role="search" className="pg-crates-search" onSubmit={submit}>
      <label className="visually-hidden" htmlFor={ids + "query"}>Search crates.io</label>
      <input ref={inputRef} id={ids + "query"} type="search" value={query} onChange={event => changeQuery(event.target.value)} onKeyDown={inputKey}
        placeholder="Search crates.io" autoCapitalize="off" autoComplete="off" spellCheck={false} enterKeyHint="search"
        maxLength={100} aria-describedby={statusId} aria-controls={ids + "results"} />
      <label className="pg-crates-sort"><span>Sort</span>
        <select value={sort} onChange={event => { const value = isCrateSort(event.target.value) ? event.target.value : DEFAULT_CRATE_SORT; setSort(value); commit(query, value); }}>
          {CRATE_SORTS.map(option => <option key={option.value} value={option.value}>{option.title}</option>)}
        </select>
      </label>
    </form>
    <div className="pg-crates-summary" aria-hidden="true">
      <strong>{shownQuery ? "Search results" : "Explore crates"}</strong>
      {loading ? <span className="pg-crates-loading">Loading…</span> : null}
      {page ? <span>{exactCount(page.total)} packages</span> : null}
    </div>
    <p id={statusId} className="visually-hidden" role="status" aria-live="polite">{status}</p>

    <div className="pg-crates-scroll">
      {problem && !crates.length ? <div className="pg-crates-problem" role="alert">
        <strong>Could not load crates.io</strong>
        <p>{problem}</p>
        <div className="pg-dialog-actions">
          <button type="button" className="pg-button" onClick={event => onManual(typedName, event.currentTarget)}>Enter name manually</button>
          <button type="button" className="pg-button pg-primary" onClick={retry}>Try again</button>
        </div>
      </div> : null}
      {!problem && !loading && !crates.length ? <div className="pg-crates-problem">
        <strong>No results for “{shownQuery}”</strong>
        <p>Check the spelling, or add a crate by its exact name.</p>
        <div className="pg-dialog-actions">
          <button type="button" className="pg-button" onClick={event => onManual(typedName, event.currentTarget)}>Enter name manually</button>
        </div>
      </div> : null}
      {crates.length ? <ul ref={list} id={ids + "results"} className="pg-crates-list" aria-label={shownQuery ? `Crates matching ${shownQuery}` : "Popular crates"}
        aria-busy={loading} onKeyDown={listKey}>
        {crates.map(crate => {
          const added = declared.has(crate.name), descriptionId = `${ids}d-${crate.name}`;
          return <li key={crate.name}>
            <button type="button" className="pg-crate-row" data-crate-row onClick={event => onChoose(crate, event.currentTarget)}
              aria-label={`${crate.name} ${crate.maxVersion}${added ? ", already in Cargo.toml" : ""}`} aria-describedby={descriptionId}>
              <span className="pg-crate-title"><strong>{crate.name}</strong><span className="pg-crate-version">{crate.maxVersion}</span>
                {added ? <span className="pg-crate-added">In Cargo.toml</span> : null}<span className="pg-crate-chevron" aria-hidden="true">›</span></span>
              <span id={descriptionId} className="pg-crate-description-group">
                <span className="pg-crate-description">{crate.description ?? "No package description"}</span>
                <span className="pg-crate-stats">
                  <span aria-hidden="true">↓ {compactCount(crate.downloads)}</span><span className="visually-hidden">{exactCount(crate.downloads)} total downloads.</span>
                  {crate.recentDownloads !== undefined ? <><span aria-hidden="true">{compactCount(crate.recentDownloads)} recent</span><span className="visually-hidden">{exactCount(crate.recentDownloads)} recent downloads.</span></> : null}
                </span>
              </span>
            </button>
          </li>;
        })}
      </ul> : null}
      {problem && crates.length ? <p className="pg-crates-warning" role="alert">{problem} <button type="button" className="pg-link-button" onClick={retry}>Try again</button></p> : null}
    </div>

    <div className="pg-crates-footer">
      <p>Package discovery uses crates.io. Compiler runs stay in this browser.</p>
      <button type="button" className="pg-link-button" onClick={event => onManual(typedName, event.currentTarget)}>Enter name manually</button>
    </div>
  </div>;
}

function CrateDetail({ crate, added, canAdd, blockedReason, error, onBack, onAdd, onOpenManifest }: {
  crate: CrateSummary; added: boolean; canAdd: boolean; blockedReason?: string; error?: string;
  onBack: () => void; onAdd: (name: string, requirement: string) => boolean; onOpenManifest?: () => void;
}) {
  const [details, setDetails] = useState<CrateDetails | null>(null), [owners, setOwners] = useState<CrateOwnerInfo[] | null>(null);
  const [loading, setLoading] = useState(true), [problem, setProblem] = useState(""), [attempt, setAttempt] = useState(0);
  // Like the app, the search result's max_version is chosen before the list arrives.
  const [selected, setSelected] = useState<string | undefined>(crate.maxVersion), picked = useRef(false);
  const [showAll, setShowAll] = useState(false), [failed, setFailed] = useState(false);
  const heading = useRef<HTMLHeadingElement>(null), ids = useId();

  useEffect(() => { heading.current?.focus(); }, []);
  useEffect(() => {
    const controller = new AbortController();
    setLoading(true); setProblem("");
    loadCrateDetails(crate.name, controller.signal).then(value => {
      if (controller.signal.aborted) return;
      setDetails(value); setLoading(false);
      if (!picked.current) setSelected(preferredVersion(value.versions, value.crate.maxVersion || crate.maxVersion));
    }, error => {
      if (controller.signal.aborted) return;
      setProblem(message(error)); setLoading(false);
    });
    loadCrateOwners(crate.name, controller.signal).then(value => { if (!controller.signal.aborted) setOwners(value); },
      () => { if (!controller.signal.aborted) setOwners([]); });
    return () => controller.abort();
  }, [crate.name, crate.maxVersion, attempt]);

  const info = details?.crate ?? crate, versions = details?.versions ?? [];
  const available = versions.filter(version => !version.yanked).length;
  const selectedIndex = versions.findIndex(version => version.num === selected);
  const shown = showAll || selectedIndex >= VERSION_PREVIEW ? versions : versions.slice(0, VERSION_PREVIEW);
  const selectedInfo = selectedIndex >= 0 ? versions[selectedIndex] : undefined;
  const requirement = versionRequirement(selected);
  const repository = safeExternalURL(info.repository);
  const disabledReason = added ? `${crate.name} is already declared. Edit its existing Cargo.toml entry to change it.`
    : !canAdd ? blockedReason ?? "Cargo.toml cannot be changed right now." : "";
  const submit = () => {
    if (!requirement || loading || disabledReason) return;
    setFailed(!onAdd(crate.name, requirement));
  };

  return <div className="pg-crates-view pg-crate-detail">
    <div className="pg-crates-scroll">
      <button type="button" className="pg-link-button pg-crates-back" onClick={onBack}>‹ All crates</button>
      <header className="pg-crate-header">
        <h3 ref={heading} tabIndex={-1}>{info.name}</h3>
        <p>{info.description ?? "No package description"}</p>
        <p className="pg-crate-metrics">
          <span><strong>{compactCount(info.downloads)}</strong> total downloads<span className="visually-hidden"> ({exactCount(info.downloads)})</span></span>
          {info.recentDownloads !== undefined ? <span><strong>{compactCount(info.recentDownloads)}</strong> recent</span> : null}
        </p>
        <p className="pg-crate-links">
          <a href={cratePageURL(info.name)} target="_blank" rel="noopener noreferrer">crates.io ↗</a>
          {repository ? <a href={repository} target="_blank" rel="noopener noreferrer">Repository ↗</a> : null}
        </p>
        <p className="pg-crate-owners">{owners === null ? "Owners…" : owners.length ? `Owners: ${owners.slice(0, 3).map(ownerName).join(", ")}${owners.length > 3 ? ` and ${owners.length - 3} more` : ""}` : "Owner information is unavailable."}</p>
      </header>

      <fieldset className="pg-crate-versions" aria-describedby={ids + "versions-status"}>
        <legend>Choose a version</legend>
        <p id={ids + "versions-status"} className="pg-crate-versions-status" role="status">
          {loading ? "Loading versions…" : problem ? "" : `${available} available${versions.length > available ? ` · ${versions.length - available} yanked` : ""}`}
        </p>
        {problem ? <div className="pg-crates-warning" role="alert">{problem}{crate.maxVersion ? ` You can still add ${crate.maxVersion}.` : ""} <button type="button" className="pg-link-button" onClick={() => setAttempt(value => value + 1)}>Try again</button></div> : null}
        {shown.length ? <div className="pg-crate-version-list">
          {shown.map(version => {
            const supported = rustVersionSupported(version.rustVersion);
            return <label key={version.num} className={"pg-crate-version-row" + (version.num === selected ? " pg-crate-version-selected" : "") + (version.yanked ? " pg-crate-version-yanked" : "")}>
              <input type="radio" name={ids + "version"} value={version.num} checked={version.num === selected} disabled={version.yanked}
                onChange={() => { picked.current = true; setSelected(version.num); setFailed(false); }} />
              <span className="pg-crate-version-num">{version.num}</span>
              {version.yanked ? <span className="pg-crate-yanked">Yanked</span> : null}
              <span className="pg-crate-version-meta">
                {version.rustVersion ? <span className={supported ? "" : "pg-crate-msrv-high"} title={supported ? undefined : `Needs Rust ${version.rustVersion}; this browser compiles with ${toolchain.rustVersion}`}>
                  {supported ? `Rust ${version.rustVersion}` : `Needs Rust ${version.rustVersion}`}</span> : null}
                <span aria-hidden="true">↓ {compactCount(version.downloads)}</span><span className="visually-hidden">{exactCount(version.downloads)} downloads</span>
              </span>
            </label>;
          })}
        </div> : null}
        {shown.length < versions.length ? <button type="button" className="pg-link-button pg-crate-more" onClick={() => setShowAll(true)}>Show all {versions.length} versions</button> : null}
      </fieldset>
    </div>

    <div className="pg-crate-addbar">
      {requirement ? <p className="pg-crate-preview">Adds to <code>[dependencies]</code>: <code>{crate.name} = &quot;{requirement}&quot;</code></p> : null}
      {selectedInfo && !rustVersionSupported(selectedInfo.rustVersion) ? <p className="pg-crates-warning">This version needs Rust {selectedInfo.rustVersion}; the browser compiler is {toolchain.rustVersion}, so Prepare will not find a compatible version. Choose an earlier release.</p> : null}
      {selectedInfo?.hasLib === false ? <p className="pg-crates-warning">This version has no library target, so other code cannot depend on it.</p> : null}
      {disabledReason ? <p className="pg-field-note">{disabledReason}{added && onOpenManifest ? <> <button type="button" className="pg-link-button" onClick={onOpenManifest}>Open Cargo.toml</button></> : null}</p> : null}
      {failed ? <p className="pg-crates-error" role="alert">{error || "Could not update the active Cargo.toml."}</p> : null}
      <button type="button" className="pg-button pg-primary pg-crate-add" onClick={submit} disabled={!requirement || loading || !!disabledReason}>
        {added ? "Already in Cargo.toml" : requirement ? `Add ${crate.name} ${requirement}` : "Choose a version"}
      </button>
    </div>
  </div>;
}

function ManualCrateEntry({ initialName, declared, canAdd, blockedReason, error, onBack, onAdd }: {
  initialName: string; declared: ReadonlySet<string>; canAdd: boolean; blockedReason?: string; error?: string;
  onBack: () => void; onAdd: (name: string, requirement: string) => boolean;
}) {
  const [name, setName] = useState(initialName), [requirement, setRequirement] = useState("1"), [failed, setFailed] = useState(false);
  const nameInput = useRef<HTMLInputElement>(null), ids = useId();
  useEffect(() => { nameInput.current?.focus(); nameInput.current?.select(); }, []);
  const trimmed = name.trim(), added = declared.has(trimmed);
  const ready = canAdd && !!trimmed && !!requirement.trim() && !added;
  const submit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (ready) setFailed(!onAdd(trimmed, requirement.trim()));
  };
  return <div className="pg-crates-view">
    <form className="pg-crates-scroll pg-crates-manual" onSubmit={submit} aria-describedby={ids + "note"}>
      <button type="button" className="pg-link-button pg-crates-back" onClick={onBack}>‹ All crates</button>
      <h3>Enter a crate manually</h3>
      <p id={ids + "note"}>Use the exact crates.io name and a Cargo requirement such as <code>1</code>, <code>=1.0.15</code> or <code>&gt;=0.3, &lt;0.5</code>. This does not contact crates.io; Prepare checks the requirement.</p>
      <label>Crate name
        <input ref={nameInput} value={name} onChange={event => { setName(event.target.value); setFailed(false); }} placeholder="itoa"
          autoCapitalize="off" autoComplete="off" spellCheck={false} maxLength={64} />
      </label>
      <label>Version requirement
        <input value={requirement} onChange={event => { setRequirement(event.target.value); setFailed(false); }} placeholder="1"
          autoCapitalize="off" autoComplete="off" spellCheck={false} maxLength={128} />
      </label>
      {added ? <p className="pg-field-note">{trimmed} is already declared. Edit its existing Cargo.toml entry to change it.</p> : null}
      {!canAdd ? <p className="pg-field-note">{blockedReason ?? "Cargo.toml cannot be changed right now."}</p> : null}
      {failed ? <p className="pg-crates-error" role="alert">{error || "Could not update the active Cargo.toml."}</p> : null}
      <div className="pg-dialog-actions"><button type="submit" className="pg-button pg-primary" disabled={!ready}>Add to Cargo.toml</button></div>
    </form>
  </div>;
}
