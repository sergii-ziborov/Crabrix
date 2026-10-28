"use client";

import { useEffect, useId, useMemo, useRef, useState } from "react";
import type { AlgorithmTrace, AtlasValue } from "@/lib/algorithm-trace-types";
import { valueText } from "@/lib/algorithm-trace-types";
import { highlightedCode } from "./SyntaxCode";
import { AlgorithmState } from "./algorithm-state";
import "./algorithm-visualizer.css";

function operationTitle(statement: string) {
  const line = statement.trim();
  if (line === "}") return "Leave this block";
  if (/^let\b/.test(line)) return "Initialize a local value";
  if (/^if\b|^match\b/.test(line)) return "Choose a branch";
  if (/^for\b/.test(line)) return "Enter the iteration";
  if (/^while\b|^loop\b/.test(line)) return "Check the loop";
  if (/^return\b/.test(line)) return "Return from this call";
  if (/^continue\b/.test(line)) return "Continue with the next iteration";
  if (/^break\b/.test(line)) return "Leave the loop";
  if (/^(?:debug_)?assert/.test(line)) return "Check an invariant";
  if (/^print/.test(line)) return "Write the result";
  if (/\.(?:push|push_back|push_front|insert)\(/.test(line)) return "Add to the collection";
  if (/\.(?:pop|pop_back|pop_front|remove)\(/.test(line)) return "Take from the collection";
  if (/\.(?:swap|reverse|sort)/.test(line)) return "Rearrange the values";
  if (/(?:[^=!<>]=[^=]|\+=|-=|\^=)/.test(line)) return "Update the current state";
  return "Evaluate the expression";
}

export function AlgorithmVisualizer({ trace, demo = false }: { trace: AlgorithmTrace; demo?: boolean }) {
  const [step, setStep] = useState(0), [playing, setPlaying] = useState(false), [speed, setSpeed] = useState(850);
  const [selected, setSelected] = useState("");
  const id = useId(), codeRef = useRef<HTMLDivElement>(null);
  const complete = step === trace.frames.length;
  const frame = trace.frames[Math.min(step, trace.frames.length - 1)];
  const site = trace.sites[frame.site];
  const values = useMemo(() => Object.fromEntries(frame.locals.map(([name, ref]) => [name, trace.values[ref].data])), [frame, trace]);
  const previous = useMemo(() => {
    const invocation = frame.stack.at(-1)?.[1];
    for (let i = Math.min(step, trace.frames.length - 1) - 1; i >= 0; i--) {
      const candidate = trace.frames[i];
      if (candidate.stack.at(-1)?.[1] === invocation) return Object.fromEntries(candidate.locals.map(([name, ref]) => [name, trace.values[ref].data]));
    }
    return {} as Record<string, AtlasValue>;
  }, [frame, step, trace]);
  const collections = Object.entries(values).filter(([, v]) => v.kind !== "scalar");
  const preferred = ["dp", "graph", "g", "adj", "grid", "matrix", "root", "head", "tree", "bit", "values", "a", "nums", "data", "text"].map(name => collections.find(([n]) => n === name)).find(Boolean);
  const focus = collections.find(([name]) => name === selected) ?? preferred ?? collections[0];
  const pointers: [string, number][] = Object.entries(values).flatMap(([name, v]) => (new RegExp(`\\[\\s*${name}\\s*\\]`).test(trace.source) || new RegExp(`for\\s*\\(\\s*${name}\\s*,[^\\n]*\\.enumerate\\(\\)`).test(trace.source)) && v.kind === "scalar" && /^\d+$/.test(v.text) && Number.isSafeInteger(Number(v.text)) ? [[name, Number(v.text)] as [string, number]] : []);
  const changes = Object.entries(values).filter(([name, value]) => previous[name] && valueText(previous[name]) !== valueText(value));
  const lines = useMemo(() => trace.source.trimEnd().split("\n").map(line => highlightedCode(line, "rust")), [trace.source]);

  useEffect(() => {
    if (!playing) return;
    const timer = window.setInterval(() => setStep(current => {
      if (current >= trace.frames.length) return current;
      return current + 1;
    }), speed);
    return () => window.clearInterval(timer);
  }, [playing, speed, trace.frames.length]);
  useEffect(() => { if (complete) setPlaying(false); }, [complete]);
  useEffect(() => {
    const pane = codeRef.current, line = pane?.querySelector<HTMLElement>(".is-executing");
    if (pane && line) pane.scrollTop = Math.max(0, line.offsetTop - pane.clientHeight / 2);
  }, [site.line]);
  const seek = (index: number) => { setPlaying(false); setStep(Math.max(0, Math.min(trace.frames.length, index))); };

  return <section className="algorithm-atlas" id={demo ? "visualization" : "algorithm-walkthrough"} aria-labelledby={`${id}-title`}>
    <header className="atlas-heading"><img src="/course-icons/algorithms.webp" width="48" height="48" alt="" /><div><p className="atlas-kicker">{demo ? "Try it · no sign-in needed" : "Algorithm Atlas · worked example"}</p><h2 id={`${id}-title`}>{demo ? trace.title : "See the algorithm, step by step"}</h2></div><span className="atlas-local">On your device</span></header>
    <p className="atlas-idea">{trace.idea}</p>
    <div className="atlas-meta"><span>{trace.complexity}</span><span>{trace.frames.length} execution steps</span></div>
    <div className="atlas-controls" role="group" aria-label="Playback controls">
      <button type="button" onClick={() => seek(0)} disabled={step === 0} aria-label="Restart walkthrough">↺</button>
      <button type="button" onClick={() => seek(step - 1)} disabled={step === 0}>← Back</button>
      <button className="atlas-play" type="button" onClick={() => { if (complete) setStep(0); setPlaying(p => !p); }} aria-pressed={playing}>{playing ? "Ⅱ Pause" : "▶ Play"}</button>
      <button type="button" onClick={() => seek(step + 1)} disabled={complete}>Next →</button>
      <label className="atlas-speed">Speed<select value={speed} onChange={e => setSpeed(Number(e.target.value))} aria-label="Playback speed"><option value="1600">Slow</option><option value="850">Normal</option><option value="300">Fast</option></select></label>
    </div>
    <div className="atlas-progress"><label htmlFor={`${id}-step`}>{complete ? "Finished" : `Step ${step + 1}`}<span>{complete ? trace.frames.length : step + 1} / {trace.frames.length}</span></label><input id={`${id}-step`} aria-label="Execution step" type="range" min="0" max={trace.frames.length} value={step} onChange={e => seek(Number(e.target.value))} /></div>
    <div className="atlas-operation" aria-live={playing ? "off" : "polite"} aria-atomic="true"><span className="atlas-operation-label">{complete ? "✓ Result" : `${site.function} · before line ${site.line}`}</span><strong>{complete ? "Execution finished" : operationTitle(site.statement)}</strong><p>{complete ? `Standard output: ${trace.stdout.trim()}` : changes.length ? `Changed since the previous step in this call: ${changes.map(([name, v]) => `${name}${v.kind === "scalar" ? `: ${valueText(previous[name])} → ${valueText(v)}` : ""}`).join(" · ")}` : frame.locals.length ? "Inspect the current state, then take the next step." : "This call is starting. Local values appear as they are initialized."}</p></div>
    <div className="atlas-workspace">
      <div className="atlas-state-pane"><div className="atlas-pane-title"><h3>Data & variables</h3><span className="atlas-legend"><i /> Changed <b /> Index</span></div>
        {trace.input && <details className="atlas-input"><summary>Example input</summary><code>{trace.input}</code></details>}
        <div className="atlas-state-stage">
          {focus ? <><div className="atlas-collection-tabs" role="group" aria-label="Inspect a collection">{collections.map(([name]) => <button type="button" aria-pressed={name === focus[0]} key={name} onClick={() => setSelected(name)}>{name}{changes.some(([n]) => n === name) ? " •" : ""}</button>)}</div><AlgorithmState name={focus[0]} value={focus[1]} previous={previous[focus[0]]} pointers={pointers} category={trace.category} edge={site.edge} state={values} /></> : <div className="atlas-state-empty"><span aria-hidden="true">🦀</span><p>{complete ? "The example has finished." : "Follow the code. Data appears here when it enters scope."}</p></div>}
        </div>
        {focus && <details className="atlas-exact-value"><summary>Exact value · {focus[0]}</summary><pre>{valueText(focus[1])}</pre></details>}
        <dl className="atlas-locals">{frame.locals.map(([name, ref]) => {
          const value = trace.values[ref];
          if (value.data.kind !== "scalar") return null;
          return <div className={changes.some(([n]) => n === name) ? "is-changed" : undefined} key={name}><dt title={value.type}>{name}</dt><dd title={valueText(value.data)}>{valueText(value.data)}</dd></div>;
        })}</dl>
        <details className="atlas-call-stack"><summary>Call stack · {frame.stack.length} {frame.stack.length === 1 ? "frame" : "frames"}</summary><ol>{frame.stack.map(([name, serial]) => <li key={serial}><code>{name}</code><small>call {serial}</small></li>)}</ol></details>
      </div>
      <div className="atlas-code-pane"><div className="atlas-pane-title"><h3>Rust source</h3><span>{complete ? "Completed" : `Line ${site.line}`}</span></div><div className="atlas-code-scroll" ref={codeRef} tabIndex={0} aria-label="Rust source with current execution line"><pre><code>{lines.map((line, index) => <span className={`atlas-code-line ${!complete && site.line === index + 1 ? "is-executing" : ""}`} key={index} aria-current={!complete && site.line === index + 1 ? "step" : undefined}><span className="atlas-line-number" aria-hidden="true">{index + 1}</span><span>{line.length ? line : " "}</span>{"\n"}</span>)}</code></pre></div></div>
    </div>
    {complete && <div className="atlas-output"><strong>Standard output</strong><pre>{trace.stdout}</pre><button type="button" onClick={() => seek(0)}>Replay example ↺</button></div>}
    <footer className="atlas-footnote">Recorded from this Rust example and checked against its original output. Playback runs locally in your browser. Values show the state before the highlighted line.{trace.verification.omittedCaptures > 0 && " Borrowed or moved values are hidden when they cannot be inspected safely."}</footer>
  </section>;
}
