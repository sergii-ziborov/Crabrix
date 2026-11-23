"use client";
import type { AcademyEvent } from "./academy-event-names";

/** Sends nothing when Global Privacy Control or Do Not Track is on. */
function allowed(): boolean {
  const navigatorWithSignals = navigator as Navigator & { globalPrivacyControl?: boolean; msDoNotTrack?: string };
  return !(navigatorWithSignals.globalPrivacyControl === true || navigator.doNotTrack === "1" || navigatorWithSignals.msDoNotTrack === "1");
}

/** Fire-and-forget: counting never blocks or breaks a page. */
export function sendAcademyEvent(event: AcademyEvent, detail?: string): void {
  try {
    if (typeof window === "undefined" || !allowed()) return;
    const body = JSON.stringify(detail ? { event, detail } : { event });
    // fetch rather than sendBeacon: credentials "omit" keeps even same-site cookies off the request.
    void fetch("/api/academy/v1/events/", { method: "POST", body, keepalive: true, credentials: "omit", cache: "no-store",
      headers: { "Content-Type": "text/plain" } }).catch(() => undefined);
  } catch { /* counting is optional */ }
}

/** Local markers for the feedback card and "returned to learning"; never sent anywhere. */
export const AI_FIRST_USE_KEY = "crabrix.ai.firstUse.v1";
export const AI_FEEDBACK_KEY = "crabrix.ai.feedback.v1";
export const AI_RETURN_DAY_KEY = "crabrix.ai.returnedDay.v1";
export const AI_SESSION_KEY = "crabrix.ai.via.v1";

export function markAIUse(): void {
  try { if (!localStorage.getItem(AI_FIRST_USE_KEY)) localStorage.setItem(AI_FIRST_USE_KEY, String(Date.now())); } catch { /* storage off */ }
}

/** The first Run or Debug in a Playground opened from an AI agent's link, once per tab. */
export function noteAIRun(): void {
  try {
    if (sessionStorage.getItem(AI_SESSION_KEY) !== "1") return;
    sessionStorage.setItem(AI_SESSION_KEY, "ran");
    sendAcademyEvent("first_run_from_ai");
  } catch { /* storage off */ }
}
