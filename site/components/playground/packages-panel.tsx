"use client";

import { useEffect, useState, type FormEvent } from "react";

export type BrowserPackageRow = {
  name: string;
  requirement: string;
  version?: string;
  state: "declared" | "prepared" | "building" | "blocked";
};

type Props = {
  packages: BrowserPackageRow[];
  manifestPath?: string;
  preparing: boolean;
  disabled: boolean;
  readOnly: boolean;
  error?: string;
  progress?: string;
  onPrepare: () => void;
  onCancel: () => void;
  onAdd: (name: string, version: string) => boolean;
  onOpenManifest: () => void;
};

const stateLabel: Record<BrowserPackageRow["state"], string> = {
  declared: "Declared",
  prepared: "Source ready",
  building: "Building",
  blocked: "Blocked",
};

export function PackagesPanel({
  packages, manifestPath, preparing, disabled, readOnly, error, progress,
  onPrepare, onCancel, onAdd, onOpenManifest,
}: Props) {
  const [adding, setAdding] = useState(false);
  const [name, setName] = useState("");
  const [version, setVersion] = useState("1");
  const [open, setOpen] = useState(true);
  useEffect(() => { if (error) setOpen(true); }, [error]);
  const canSubmit = !disabled && !readOnly && !preparing && !!name.trim() && !!version.trim();
  const needsPreparation = packages.some(row => row.state !== "prepared");
  const showAdd = adding && !readOnly;

  const submit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (canSubmit && onAdd(name.trim(), version.trim())) { setName(""); setAdding(false); }
  };

  return <details className="pg-packages" open={open} onToggle={event => setOpen(event.currentTarget.open)}>
    <summary className="pg-packages-summary">
      <span className="pg-packages-chevron" aria-hidden="true">▸</span>
      <strong>Packages</strong>
      <span className="pg-packages-count" aria-label={packages.length + (packages.length === 1 ? " dependency" : " dependencies")}>{packages.length}</span>
    </summary>
    <div className="pg-packages-body">
      <p className="pg-packages-std">Rust std <span>with compiler</span></p>
      <p className="pg-packages-profile">Registry Rust libraries; unsupported build requirements are reported.</p>

      {packages.length ? <ul className="pg-packages-list">
        {packages.map(row => <li key={row.name} className="pg-package-row">
          <div className="pg-package-name-line">
            <strong title={row.name}>{row.name}</strong>
            <span title={row.version ? "Resolved " + row.version + "; requested " + row.requirement : "Requested " + row.requirement}>
              {row.version ?? row.requirement}
            </span>
          </div>
          <small className={"pg-package-state pg-package-state-" + row.state}
            aria-label={row.state === "prepared" ? "Source ready in this browser; compilation is not yet verified" : stateLabel[row.state]}>
            {stateLabel[row.state]}
          </small>
        </li>)}
      </ul> : <p className="pg-packages-empty">{error ? "Open Cargo.toml to resolve its requirements." : "No dependencies yet. Prepared sources stay in this browser."}</p>}

      {error ? <p className="pg-packages-error" role="alert">{error}</p> : null}
      {progress ? <p className="pg-packages-progress" role="status">{progress}</p> : null}
      <div className="pg-packages-actions">
        <button type="button" className="pg-button" onClick={() => setAdding(value => !value)}
          disabled={disabled || readOnly || preparing} aria-expanded={showAdd}
          aria-controls={showAdd ? "pg-package-add-fields" : undefined}>
          {showAdd ? "Close" : "+ Add crate"}
        </button>
        {preparing
          ? <button type="button" className="pg-button" onClick={onCancel}>Cancel</button>
          : <button type="button" className="pg-button pg-packages-prepare" onClick={onPrepare}
              disabled={disabled || !needsPreparation} title="Download and prepare crate sources in this browser"
              aria-label="Download and prepare crate sources">↓ Prepare</button>}
      </div>

      {showAdd ? <form id="pg-package-add-fields" className="pg-packages-add" onSubmit={submit}>
        <label>Crate name
          <input value={name} onChange={event => setName(event.target.value)}
            placeholder="itoa" autoCapitalize="off" autoComplete="off" spellCheck={false}
            disabled={disabled || preparing} />
        </label>
        <label>Version requirement
          <input value={version} onChange={event => setVersion(event.target.value)}
            placeholder="1" autoCapitalize="off" autoComplete="off" spellCheck={false}
            disabled={disabled || preparing} />
        </label>
        <button type="submit" className="pg-button pg-packages-prepare" disabled={!canSubmit}>Add to Cargo.toml</button>
      </form> : null}

      {manifestPath ? <button type="button" className="pg-packages-manifest" onClick={onOpenManifest}
        title={manifestPath}>Open Cargo.toml</button> : null}
    </div>
  </details>;
}
