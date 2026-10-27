"use client";
import { useCallback, useEffect, useRef, useState } from "react";
import type { PlaygroundDocument } from "@/lib/playground-document";
import type { DebugSite } from "@/lib/rust-debug-instrumentation";
import { debugCommands, debugControlOffset, resolveDebugBreakpoints, type DebugCommand, type DebugPause } from "@/lib/rust-debug-session";

export type CompilerReply = {
  compilation: { exitCode: number; stdout: string; stderr: string; trap?: string };
  execution?: { exitCode: number; stdout: string; stderr: string; trap?: string };
  compileMs: number; durationMs: number;
};

export function useRustCompiler() {
  const current = useRef<Worker | null>(null), busy = useRef(false), timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const [ready, setReady] = useState(false), [activity, setActivity] = useState<"idle" | "loading" | "checking" | "running" | "paused">("idle");
  const [stage, setStage] = useState("Rust runs locally in your browser."), [result, setResult] = useState<CompilerReply | null>(null), [error, setError] = useState("");
  const pending = useRef<(() => void) | undefined>(undefined);
  const debugControl = useRef<Int32Array | null>(null), debugRunningMs = useRef(0);
  const [debugging, setDebugging] = useState(false), [debugPause, setDebugPause] = useState<DebugPause | null>(null), [debugSites, setDebugSites] = useState<DebugSite[]>([]);
  const breakpointRef = useRef<Record<string, number[]>>({});
  const updateBreakpoints = useCallback((breakpoints: Record<string, number[]>) => {
    breakpointRef.current = breakpoints;
    const control = debugControl.current;
    const bound = resolveDebugBreakpoints(debugSites, breakpoints);
    if (control) for (const site of debugSites) Atomics.store(control, debugControlOffset + site.id, bound.has(site.id) ? 1 : 0);
  }, [debugSites]);

  const stop = useCallback(() => {
    if (debugControl.current) { Atomics.store(debugControl.current, 0, 5); Atomics.notify(debugControl.current, 0); }
    current.current?.terminate(); current.current = null; pending.current = undefined;
    debugControl.current = null; setDebugPause(null); setDebugging(false);
    if (timer.current) clearTimeout(timer.current);
    busy.current = false; setReady(false); setActivity("idle"); setStage("Stopped. Source remains in the editor.");
  }, []);
  useEffect(() => () => { current.current?.terminate(); if (timer.current) clearTimeout(timer.current); }, []);

  const command = useCallback((command: DebugCommand) => {
    const control = debugControl.current; if (!control) return;
    setDebugPause(null); setActivity("running"); setStage("Debug running locally");
    if (timer.current) clearTimeout(timer.current);
    timer.current = setTimeout(() => { stop(); setError("Debug reached its 30-second running-time limit. Paused time is excluded."); }, Math.max(1, 30_000 - debugRunningMs.current));
    Atomics.store(control, 0, debugCommands[command]); Atomics.notify(control, 0);
  }, [stop]);
  const pauseDebug = useCallback(() => { if (debugControl.current) Atomics.store(debugControl.current, 1, 1); }, []);
  const start = useCallback((mode: "check" | "run" | "debug", source: PlaygroundDocument, stdin: string) => {
    if (busy.current) return;
    if (mode === "debug" && (!globalThis.crossOriginIsolated || typeof SharedArrayBuffer === "undefined")) { setError("This browser does not expose isolated shared memory for local Debug. Use Run or open this Playground in Crabrix."); return; }
    debugControl.current = mode === "debug" ? new Int32Array(new SharedArrayBuffer((8192 + 5) * 4)) : null;
    debugRunningMs.current = 0; setDebugging(mode === "debug"); setDebugPause(null); setDebugSites([]);
    busy.current = true; setError(""); setResult(null);
    const armTimeout = (milliseconds: number, message: string) => {
      if (timer.current) clearTimeout(timer.current);
      timer.current = setTimeout(() => { stop(); setError(message); }, milliseconds);
    };
    const perform = () => {
      setActivity(mode === "check" ? "checking" : "running");
      armTimeout(45_000, "Compilation stopped at the 45-second browser limit. Download the source to continue in Crabrix.");
      current.current?.postMessage({ type: mode, document: source, stdin, ...(debugControl.current ? { control: debugControl.current.buffer } : {}) });
    };
    if (!current.current) {
      setActivity("loading");
      const worker = new Worker(new URL("../../workers/rust.worker.ts", import.meta.url), { type: "module" });
      current.current = worker; pending.current = perform;
      worker.onmessage = ({ data }) => {
        if (current.current !== worker) return;
        if (data.type === "stage") {
          setStage(data.label);
          // Initial assets can take longer on a slow connection. Received bytes
          // extend only initialization's inactivity deadline, never Run/Check.
          if (data.downloadProgress === true && pending.current) armTimeout(180_000, "Toolchain download stopped making progress. Check the connection and retry; source was not uploaded.");
        }
        else if (data.type === "ready") { setReady(true); const action = pending.current; pending.current = undefined; action?.(); }
        else if (data.type === "debug-plan") {
          const sites = data.sites as DebugSite[]; setDebugSites(sites);
          const control = debugControl.current;
          const bound = resolveDebugBreakpoints(sites, breakpointRef.current);
          if (control) for (const site of sites) Atomics.store(control, debugControlOffset + site.id, bound.has(site.id) ? 1 : 0);
        }
        else if (data.type === "paused") {
          if (timer.current) clearTimeout(timer.current);
          debugRunningMs.current = data.runningMs; setDebugPause(data); setActivity("paused"); setStage(`Paused at ${data.site.file}:${data.site.line}`);
          timer.current = setTimeout(() => { stop(); setError("Debug pause expired after 30 minutes."); }, 30 * 60_000);
        }
        else if (data.type === "executing") armTimeout(30_000, "Program stopped at the 30-second execution limit.");
        else if (data.type === "result") {
          if (timer.current) clearTimeout(timer.current);
          busy.current = false; debugControl.current = null; setDebugging(false); setDebugPause(null); setActivity("idle"); setResult(data); setStage(data.execution ? "Local execution finished." : "Local check finished.");
        } else if (data.type === "error") { stop(); setError(data.error); }
      };
      worker.onerror = () => { if (current.current === worker) { stop(); setError("The local compiler worker stopped unexpectedly. Your source is still in the editor."); } };
      armTimeout(180_000, "Toolchain download timed out. Check the connection and retry; source was not uploaded.");
      worker.postMessage({ type: "initialize" });
    } else perform();
  }, [stop]);

  return { ready, activity, stage, result, error, start, stop, debugging, debugPause, debugSites, command, pauseDebug, updateBreakpoints, clearError: () => setError("") };
}
