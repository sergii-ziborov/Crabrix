"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { CrateCatalogDialog } from "./crate-catalog-dialog";

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
  const [open, setOpen] = useState(true);
  // The catalogue renders in the workspace root: on phones this sidebar can be
  // display:none, which would hide an open modal dialog with it.
  const [catalogHost, setCatalogHost] = useState<HTMLElement | null>(null);
  const [added, setAdded] = useState("");
  const addButton = useRef<HTMLButtonElement>(null), openingManifest = useRef(false);
  useEffect(() => { if (error) setOpen(true); }, [error]);
  useEffect(() => { if (preparing) setAdded(""); }, [preparing]);
  const canAdd = !disabled && !readOnly && !preparing;
  const needsPreparation = packages.some(row => row.state !== "prepared");
  const declared = useMemo(() => new Set(packages.filter(row => row.requirement !== "transitive").map(row => row.name)), [packages]);

  const openCatalog = () => {
    const button = addButton.current;
    setAdded("");
    setCatalogHost(button?.closest<HTMLElement>(".pg-workspace") ?? document.body);
  };
  const add = (name: string, requirement: string) => {
    if (!canAdd || !onAdd(name, requirement)) return false;
    setAdded(`Added ${name} = "${requirement}" to Cargo.toml. Prepare downloads it.`);
    return true;
  };

  return <>
    <details className="pg-packages" open={open} onToggle={event => setOpen(event.currentTarget.open)}>
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
        {added && !error ? <p className="pg-packages-progress" role="status">{added}</p> : null}
        <div className="pg-packages-actions">
          <button ref={addButton} type="button" className="pg-button" onClick={openCatalog}
            disabled={!canAdd} aria-haspopup="dialog" aria-expanded={!!catalogHost}
            title="Search crates.io and add a dependency to Cargo.toml">
            + Add crate
          </button>
          {preparing
            ? <button type="button" className="pg-button" onClick={onCancel}>Cancel</button>
            : <button type="button" className="pg-button pg-packages-prepare" onClick={onPrepare}
                disabled={disabled || !needsPreparation} title="Download and prepare crate sources in this browser"
                aria-label="Download and prepare crate sources">↓ Prepare</button>}
        </div>

        {manifestPath ? <button type="button" className="pg-packages-manifest" onClick={onOpenManifest}
          title={manifestPath}>Open Cargo.toml</button> : null}
      </div>
    </details>
    {catalogHost ? createPortal(<CrateCatalogDialog declared={declared} canAdd={canAdd} error={error} onAdd={add}
      blockedReason={readOnly ? "This Playground is read only." : preparing ? "Wait for package preparation to finish." : disabled ? "Cargo.toml cannot be changed while the Playground is busy." : undefined}
      onOpenManifest={manifestPath ? () => { openingManifest.current = true; onOpenManifest(); } : undefined}
      onClosed={() => {
        setCatalogHost(null);
        // Focus returns to Add crate, unless the dialog handed over to Cargo.toml in the editor.
        if (!openingManifest.current) requestAnimationFrame(() => addButton.current?.focus());
        openingManifest.current = false;
      }} />, catalogHost) : null}
  </>;
}
