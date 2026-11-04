'use client';

import { useEffect, useMemo, useRef, useState } from 'react';
import { findCargoManifest, readCargoRoot, addCargoDependency } from '@/lib/browser-cargo-manifest';
import { loadPreparedCargo, prepareBrowserCargo, type PreparedCargo } from '@/lib/browser-cargo';
import type { PlaygroundDocument } from '@/lib/playground-document';
import type { BrowserPackageRow } from './packages-panel';

const message = (error: unknown) => error instanceof Error ? error.message : String(error);
function manifestInputs(source: PlaygroundDocument | null) {
  const path = source ? findCargoManifest(source) : undefined;
  return { path, key: JSON.stringify([path, path ? source?.files[path] : undefined,
    path ? source?.files[path.slice(0, -'Cargo.toml'.length) + 'Cargo.lock'] : undefined]) };
}

export function useBrowserCargo(source: PlaygroundDocument | null, readOnly: boolean,
  current: () => PlaygroundDocument, apply: (files: Record<string, string>, baseline: PlaygroundDocument) => void) {
  const { path, key } = manifestInputs(source);
  const latest = useRef({ source, readOnly, current, apply });
  latest.current = { source, readOnly, current, apply };
  // Typing Rust does not reparse the unchanged manifest or re-read archive caches.
  const info = useMemo(() => {
    try { return { root: source ? readCargoRoot(source) : null, error: '' }; }
    catch (error) { return { root: null, error: message(error) }; }
  }, [key]);
  const [preparedState, setPrepared] = useState<{ key: string; graph: PreparedCargo } | null>(null);
  const [preparing, setPreparing] = useState(false), [error, setError] = useState(''), [progress, setProgress] = useState('');
  const controller = useRef<AbortController | null>(null);

  useEffect(() => {
    let active = true;
    controller.current?.abort(); setPrepared(null); setError(''); setProgress(''); setPreparing(false);
    const value = latest.current.source;
    if (value && !info.error) void loadPreparedCargo(value).then(graph => {
      if (active) setPrepared(graph ? { key, graph } : null);
    }, error => {
      if (active && !message(error).includes('not prepared')) setError(message(error));
    });
    return () => { active = false; controller.current?.abort(); };
  }, [key]);

  const prepare = async () => {
    if (preparing) return;
    controller.current?.abort();
    const operation = new AbortController(); controller.current = operation;
    setPreparing(true); setError('');
    try {
      const state = latest.current, baseline = state.current();
      const result = await prepareBrowserCargo(baseline, operation.signal, setProgress, !state.readOnly);
      if (operation.signal.aborted) return;
      if (!state.readOnly) latest.current.apply({ [result.lockPath]: result.lockText }, baseline);
      setPrepared({ key: manifestInputs(latest.current.current()).key, graph: result.graph });
    } catch (error) {
      if (!operation.signal.aborted) {
        setError(message(error)); setProgress('Package preparation stopped. Source is unchanged.');
      }
    } finally {
      if (controller.current === operation) { setPreparing(false); controller.current = null; }
    }
  };
  const add = (name: string, version: string) => {
    try {
      if (latest.current.readOnly) return false;
      const baseline = latest.current.current(), result = addCargoDependency(baseline, name, version);
      latest.current.apply({ [result.path]: result.text }, baseline);
      setError(''); return true;
    } catch (error) { setError(message(error)); return false; }
  };
  // A previous graph must never appear ready for even one render of a new manifest.
  const prepared = preparedState?.key === key ? preparedState.graph : null;
  const packages: BrowserPackageRow[] = (info.root?.dependencies ?? []).map(dep => {
    const pkg = prepared?.packages.find(p => p.name === dep.name);
    return { name: dep.alias, requirement: dep.requirement, version: pkg?.version, state: pkg ? 'prepared' : 'declared' };
  });
  for (const pkg of prepared?.packages ?? []) if (!info.root?.dependencies.some(dep => dep.name === pkg.name)) {
    packages.push({ name: pkg.name, requirement: 'transitive', version: pkg.version, state: 'prepared' });
  }
  return { packages, manifestPath: path, preparing, error: info.error || error, progress, prepare, add,
    cancel: () => { controller.current?.abort(); setPreparing(false); setProgress('Package preparation canceled. Source is unchanged.'); } };
}
