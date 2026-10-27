"use client";
import { useCallback, useEffect, useRef, useState } from "react";
import type { PlaygroundDocument } from "@/lib/playground-document";

export type CompilerReply = {
  compilation: { exitCode: number; stdout: string; stderr: string; trap?: string };
  execution?: { exitCode: number; stdout: string; stderr: string; trap?: string };
  compileMs: number; durationMs: number;
};

export function useRustCompiler() {
  const current = useRef<Worker | null>(null), busy = useRef(false), timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const [ready, setReady] = useState(false), [activity, setActivity] = useState<"idle" | "loading" | "checking" | "running">("idle");
  const [stage, setStage] = useState("Rust runs locally in your browser."), [result, setResult] = useState<CompilerReply | null>(null), [error, setError] = useState("");
  const pending = useRef<(() => void) | undefined>(undefined);

  const stop = useCallback(() => {
    current.current?.terminate(); current.current = null; pending.current = undefined;
    if (timer.current) clearTimeout(timer.current);
    busy.current = false; setReady(false); setActivity("idle"); setStage("Stopped. Source remains in the editor.");
  }, []);
  useEffect(() => () => { current.current?.terminate(); if (timer.current) clearTimeout(timer.current); }, []);

  const start = useCallback((mode: "check" | "run", source: PlaygroundDocument, stdin: string) => {
    if (busy.current) return;
    busy.current = true; setError(""); setResult(null);
    const armTimeout = (milliseconds: number, message: string) => {
      if (timer.current) clearTimeout(timer.current);
      timer.current = setTimeout(() => { stop(); setError(message); }, milliseconds);
    };
    const perform = () => {
      setActivity(mode === "check" ? "checking" : "running");
      armTimeout(45_000, "Compilation stopped at the 45-second browser limit. Download the source to continue in Crabrix.");
      current.current?.postMessage({ type: mode, document: source, stdin });
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
        else if (data.type === "executing") armTimeout(30_000, "Program stopped at the 30-second execution limit.");
        else if (data.type === "result") {
          if (timer.current) clearTimeout(timer.current);
          busy.current = false; setActivity("idle"); setResult(data); setStage(data.execution ? "Local execution finished." : "Local check finished.");
        } else if (data.type === "error") { stop(); setError(data.error); }
      };
      worker.onerror = () => { if (current.current === worker) { stop(); setError("The local compiler worker stopped unexpectedly. Your source is still in the editor."); } };
      armTimeout(180_000, "Toolchain download timed out. Check the connection and retry; source was not uploaded.");
      worker.postMessage({ type: "initialize" });
    } else perform();
  }, [stop]);

  return { ready, activity, stage, result, error, start, stop, clearError: () => setError("") };
}
