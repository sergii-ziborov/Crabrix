"use client";

import { useEffect, useState } from "react";
import { AI_FEEDBACK_KEY, AI_FIRST_USE_KEY, AI_RETURN_DAY_KEY, AI_SESSION_KEY, markAIUse, sendAcademyEvent } from "@/lib/academy-events-client";

const day = (time: number) => new Date(time).toISOString().slice(0, 10);

/**
 * A lesson or Playground link that an AI agent handed out carries ?via=ai (the Crabrix MCP adds
 * it). Count the arrival once, then remove the parameter so the address stays the canonical one.
 */
export function AIArrival({ place, kind }: { place: "lesson" | "playground"; kind?: "lesson-project" | "practice-copy" | "algorithm-trace" | "example-copy" }) {
  useEffect(() => {
    const parts = window.location.search.slice(1).split("&").filter(Boolean);
    if (!parts.includes("via=ai")) return;
    // Remove only that parameter and keep the rest byte for byte (e.g. lesson=basics/variables).
    const rest = parts.filter(part => part !== "via=ai").join("&");
    window.history.replaceState(window.history.state, "", window.location.pathname + (rest ? `?${rest}` : "") + window.location.hash);
    markAIUse();
    if (place === "lesson") sendAcademyEvent("lesson_opened_from_ai");
    else {
      try { if (!sessionStorage.getItem(AI_SESSION_KEY)) sessionStorage.setItem(AI_SESSION_KEY, "1"); } catch { /* storage off */ }
      if (kind) sendAcademyEvent("playground_opened_from_ai", kind);
    }
  }, [place, kind]);
  return null;
}

/** /learn/with-ai/ opened, and on /learn/: a learner who set up AI earlier came back on a later day. */
export function AIPageView({ page }: { page: "with-ai" | "learn" }) {
  useEffect(() => {
    if (page === "with-ai") { sendAcademyEvent("with_ai_opened"); return; }
    try {
      const first = Number(localStorage.getItem(AI_FIRST_USE_KEY) || 0), today = day(Date.now());
      if (!first || day(first) === today || localStorage.getItem(AI_RETURN_DAY_KEY) === today) return;
      localStorage.setItem(AI_RETURN_DAY_KEY, today);
      sendAcademyEvent("returned_to_learning");
    } catch { /* storage off */ }
  }, [page]);
  return null;
}

const answers = [["yes", "Yes"], ["partly", "Partly"], ["not-working", "I couldn’t get it working"]] as const;

/**
 * "Did learning Rust with your AI agent help?" (spec §14.1). `prompted`: shown once, only after
 * the learner copied an AI setup or prompt at least 30 minutes earlier; answered or dismissed,
 * it never returns. `always`: the static section on /learn/with-ai/. The optional text is never
 * sent to the server: "Email it" opens a draft the learner sends themselves.
 */
export function AIFeedback({ mode, mail }: { mode: "prompted" | "always"; mail: string }) {
  const [visible, setVisible] = useState(mode === "always");
  const [answer, setAnswer] = useState<(typeof answers)[number] | null>(null);
  const [text, setText] = useState("");
  useEffect(() => {
    if (mode !== "prompted") return;
    try {
      const first = Number(localStorage.getItem(AI_FIRST_USE_KEY) || 0);
      // Read after hydration: the server never knows about the learner's browser storage.
      if (first && Date.now() - first > 30 * 60_000 && !localStorage.getItem(AI_FEEDBACK_KEY)) setVisible(true);
    } catch { /* storage off: never shown */ }
  }, [mode]);
  if (!visible) return null;
  const close = (state: "answered" | "dismissed") => {
    try { localStorage.setItem(AI_FEEDBACK_KEY, state); } catch { /* storage off */ }
    if (mode === "prompted") setVisible(false);
  };
  const choose = (item: (typeof answers)[number]) => {
    setAnswer(item);
    sendAcademyEvent("feedback_answered", item[0]);
    try { localStorage.setItem(AI_FEEDBACK_KEY, "answered"); } catch { /* storage off */ }
  };
  return <section className={mode === "prompted" ? "ai-feedback ai-feedback-prompted" : "unit-panel ai-feedback-static"} aria-labelledby={`ai-feedback-${mode}`}>
    <h2 id={`ai-feedback-${mode}`}>Did learning Rust with your AI agent help?</h2>
    {!answer ? <div className="cta-row">
      {answers.map(item => <button key={item[0]} type="button" className="btn ghost" onClick={() => choose(item)}>{item[1]}</button>)}
      {mode === "prompted" && <button type="button" className="btn ghost ai-feedback-dismiss" onClick={() => close("dismissed")} aria-label="Dismiss this question">Not now</button>}
    </div> : <div className="ai-feedback-more">
      <p>Thank you. Anything to add? Optional; it goes only into an email draft you send yourself.</p>
      <label className="visually-hidden" htmlFor={`ai-feedback-text-${mode}`}>Your comment</label>
      <textarea id={`ai-feedback-text-${mode}`} rows={3} maxLength={1000} value={text} onChange={event => setText(event.target.value)} />
      <div className="cta-row">
        <button type="button" className="btn" disabled={!text.trim()} onClick={() => {
          const query = new URLSearchParams({ subject: `Crabrix — Learning with AI: ${answer[1]}`, body: text.trim() });
          window.location.href = `mailto:${atob(mail)}?${query.toString()}`;
          close("answered");
        }}>Email it</button>
        <button type="button" className="btn ghost" onClick={() => close("answered")}>Done</button>
      </div>
    </div>}
  </section>;
}
