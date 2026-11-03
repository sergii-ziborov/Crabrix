"use client";

import type { RecoveryRow } from "@/lib/playground-codec-v2";

/** Deleted files keep their text until someone clears them, so a late edit is never lost. */
export function RecoveryPanel({ rows, readOnly, onRestore, onClear, onDownload }: {
  rows: RecoveryRow[]; readOnly: boolean;
  onRestore: (row: RecoveryRow) => void; onClear: (row: RecoveryRow) => void; onDownload: (row: RecoveryRow) => void;
}) {
  if (!rows.length) return null;
  return <section className="pg-recovery" aria-label="Recovery">
    <div className="pg-sidebar-heading"><strong>RECOVERY</strong><span className="pg-recovery-count">{rows.length}</span></div>
    <p className="pg-field-note">Deleted files keep their text here until someone clears them.</p>
    <ul>
      {rows.map(row => <li key={row.id}>
        <span className="pg-recovery-name" title={row.path}>{row.path.slice(row.path.lastIndexOf("/") + 1)}</span>
        <small>{row.bytes < 1024 ? `${row.bytes} B` : `${(row.bytes / 1024).toFixed(1)} KiB`}{row.conflict ? " · edited after delete" : ""}{row.orphan ? " · no file record" : ""}</small>
        <span className="pg-recovery-actions">
          <button type="button" className="pg-link-button" disabled={readOnly} onClick={() => onRestore(row)}>Restore</button>
          <button type="button" className="pg-link-button" onClick={() => onDownload(row)}>Download</button>
          <button type="button" className="pg-link-button" disabled={readOnly} onClick={() => onClear(row)}>Clear</button>
        </span>
      </li>)}
    </ul>
  </section>;
}
