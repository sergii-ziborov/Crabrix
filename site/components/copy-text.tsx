"use client";

import { useState } from "react";
import { markAIUse, sendAcademyEvent } from "@/lib/academy-events-client";
import type { AcademyEvent } from "@/lib/academy-event-names";

/**
 * Copies fixed public text. The text is also visible on the page, so nothing depends on this
 * working. With `event`, a successful copy adds one to that anonymous daily counter.
 */
export function CopyText({ text, label = "Copy", className = "btn ghost", event, detail }:
  { text: string; label?: string; className?: string; event?: AcademyEvent; detail?: string }) {
  const [state, setState] = useState<"idle" | "copied" | "failed">("idle");
  async function copy() {
    try {
      await navigator.clipboard.writeText(text);
      setState("copied");
      if (event) { markAIUse(); sendAcademyEvent(event, detail); }
    } catch {
      setState("failed");
    }
    window.setTimeout(() => setState("idle"), 2400);
  }
  return <button type="button" className={className} onClick={copy} aria-live="polite">
    {state === "copied" ? "Copied" : state === "failed" ? "Select the text to copy" : label}
  </button>;
}
