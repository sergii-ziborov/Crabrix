"use client";

import { useState } from "react";
import { markAIUse, sendAcademyEvent } from "@/lib/academy-events-client";

/**
 * "Learn this lesson with AI": the prompt holds only this lesson's public details. Copy works
 * everywhere; the Open buttons copy first and then open the client, so nothing depends on a
 * client supporting a prefilled message.
 */
export function LessonAIHandoff({ prompt }: { prompt: string }) {
  const [state, setState] = useState<"idle" | "copied" | "failed">("idle");
  async function copy(open?: string) {
    let copied = false;
    try { await navigator.clipboard.writeText(prompt); copied = true; } catch { /* the prompt is visible on the page */ }
    setState(copied ? "copied" : "failed");
    window.setTimeout(() => setState("idle"), 2400);
    markAIUse();
    sendAcademyEvent("prompt_copied", "lesson");
    if (open) window.open(open, "_blank", "noopener,noreferrer");
  }
  const query = encodeURIComponent(prompt);
  return <>
    <div className="ai-lesson-actions">
      <button type="button" className="btn" onClick={() => copy()} aria-live="polite">{state === "copied" ? "Copied" : state === "failed" ? "Select the text to copy" : "Copy prompt"}</button>
      <button type="button" className="btn ghost" onClick={() => copy(`https://claude.ai/new?q=${query}`)}>Copy and open Claude ↗</button>
      <button type="button" className="btn ghost" onClick={() => copy(`https://chatgpt.com/?q=${query}`)}>Copy and open ChatGPT ↗</button>
    </div>
    <p className="card-meta">In Claude Code, Codex or Cursor, paste it into a chat with Crabrix Academy connected. On a phone, the Claude and ChatGPT apps open the same links.</p>
  </>;
}
