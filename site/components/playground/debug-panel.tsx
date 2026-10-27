"use client";
import { useState } from "react";
import type { DebugPause, DebugCommand } from "@/lib/rust-debug-session";
export function DebugPanel({ paused, active, command, pause, breakpoints, remove }: {
  paused: DebugPause | null; active: boolean; command: (command: DebugCommand) => void; pause: () => void;
  breakpoints: Record<string, number[]>; remove: (file: string, line: number) => void;
}) {
  const [frameIndex, setFrameIndex] = useState(0);
  const frames = [...(paused?.frames ?? [])].reverse();
  const frame = frames[Math.min(frameIndex, Math.max(0, frames.length - 1))];
  return <div className="pg-debug-panel">
    <div className="pg-debug-controls" aria-label="Debugger controls">
      {paused ? <><button className="pg-button pg-save" onClick={() => command("continue")}>▶ Continue</button><button className="pg-button" onClick={() => command("into")}>Step into</button><button className="pg-button" onClick={() => command("over")}>Step over</button><button className="pg-button" onClick={() => command("out")}>Step out</button></> : active ? <button className="pg-button" onClick={pause}>Ⅱ Pause</button> : null}
    </div>
    <p className="pg-debug-location">{paused ? `${paused.reason === "breakpoint" ? "Breakpoint" : "Paused"} · ${paused.site.file}:${paused.site.line} · ${paused.site.function}` : active ? "Running locally. Source changes stop this immutable debug snapshot." : "Choose Debug to pause at the first statement. Click the gutter beside a line number to set a breakpoint."}</p>
    <div className="pg-debug-columns"><section><h3>Call stack</h3>{frames.map((frame, index) => <button className={index === frameIndex ? "pg-frame pg-frame-selected" : "pg-frame"} key={index} onClick={() => setFrameIndex(index)}>{frame.site.function}<small>{frame.site.file}:{frame.site.line}</small></button>)}{!frames.length ? <p>No paused frames</p> : null}</section>
      <section><h3>Locals</h3>{frame?.locals.length ? <table><thead><tr><th>Name</th><th>Type</th><th>Value</th></tr></thead><tbody>{frame.locals.map(variable => <tr key={variable.name}><td>{variable.name}</td><td>{variable.type}</td><td>{variable.value}</td></tr>)}</tbody></table> : <p>No inspectable locals at this statement.</p>}<p>String, Vec and concrete local structs have bounded previews. Borrowed, moved or captured values may be omitted. Async frames show active polls; const bodies and macro expansions are not stepped internally.</p></section></div>
    <details><summary>Breakpoints</summary>{Object.entries(breakpoints).flatMap(([file, lines]) => lines.map(line => <button className="pg-breakpoint-item" key={`${file}:${line}`} onClick={() => remove(file, line)}>● {file}:{line} ×</button>))}</details>
  </div>;
}
