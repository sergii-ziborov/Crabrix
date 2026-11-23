"use client";

import { useState } from "react";

/** Copies fixed public text. The text is also visible on the page, so nothing depends on this working. */
export function CopyText({ text, label = "Copy", className = "btn ghost" }: { text: string; label?: string; className?: string }) {
  const [state, setState] = useState<"idle" | "copied" | "failed">("idle");
  async function copy() {
    try {
      await navigator.clipboard.writeText(text);
      setState("copied");
    } catch {
      setState("failed");
    }
    window.setTimeout(() => setState("idle"), 2400);
  }
  return <button type="button" className={className} onClick={copy} aria-live="polite">
    {state === "copied" ? "Copied" : state === "failed" ? "Select the text to copy" : label}
  </button>;
}
