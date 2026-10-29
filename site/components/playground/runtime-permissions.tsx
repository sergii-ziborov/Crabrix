"use client";
import { useState } from 'react';
import type { useRuntimeHost } from './use-runtime-host';
import { runtimeActions, type RuntimeAction } from '@/lib/playground-runtime-authority';
export function RuntimePermissions({runtime}:{runtime:ReturnType<typeof useRuntimeHost>}) {
  const [operations,setOperations]=useState<RuntimeAction[]>([...runtimeActions]);
  const status=runtime.status;
  return <section className="pg-share-summary pg-runtime-permissions" aria-label="MCP execution permissions">
    <h3>Run here with MCP</h3>
    <p>Permission starts off. Choose a controller below to allow execution on this browser for up to ten minutes. Shared std/local-module source only; Cargo manifests, packages, private files and native libraries require ordinary local Run in Crabrix. Every room participant can read shared output.</p>
    <p>Use Check once to prepare this browser’s verified compiler. MCP never starts a toolchain download. Shared jobs stop after two minutes, including pauses.</p>
    {runtime.notice ? <p role="status">{runtime.notice}</p> : null}
    {status ? <>
      <p className="pg-runtime-key">Device key: <code>{status.fingerprint}</code></p>
      {status.grant ? <><p>Allowed: {status.grant.name} · {status.grant.operations.join(', ')} · until {new Date(status.grant.expires).toLocaleTimeString()}</p><button className="pg-button" onClick={runtime.revoke}>Revoke execution permission</button></> : <p>Execution permission is off.</p>}
      {status.requests.map(request=><div key={request.controller} className="pg-runtime-request"><strong>{request.name}</strong><p className="pg-runtime-key"><code>{request.controller}</code></p>{request.operations.map(operation=><label key={operation} className="pg-checkbox"><input type="checkbox" checked={operations.includes(operation)} onChange={event=>setOperations(previous=>event.target.checked?[...previous,operation]:previous.filter(item=>item!==operation))}/>{operation}</label>)}<button className="pg-button pg-save" disabled={!request.operations.some(operation=>operations.includes(operation))} onClick={()=>void runtime.allow(request.controller,request.requestID,operations.filter(operation=>request.operations.includes(operation)))}>Allow selected operations · 10 min</button></div>)}
      {status.jobs.map(job=><p key={job.id}>Shared {job.operation}: {job.state} · {job.stage}</p>)}
    </> : <p>Waiting for the encrypted source and local connection…</p>}
  </section>;
}
