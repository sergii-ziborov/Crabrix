/**
 * The only events "Learn Rust with Your AI Agent" counts (docs/ai-learning/PLAN.md, Phase 7).
 * Each one is a fixed name and an optional fixed detail; nothing else is ever sent or stored.
 */
const clients = ["claude", "claude-code", "codex", "cursor", "other"] as const;
export const ACADEMY_EVENTS = {
  with_ai_opened: [],
  client_selected: clients,
  instructions_copied: clients,
  prompt_copied: ["beginner", "nodejs", "c", "continue", "lesson"],
  lesson_opened_from_ai: [],
  playground_opened_from_ai: ["lesson-project", "practice-copy", "algorithm-trace", "example-copy"],
  first_run_from_ai: [],
  returned_to_learning: [],
  feedback_answered: ["yes", "partly", "not-working"],
} as const satisfies Record<string, readonly string[]>;

export type AcademyEvent = keyof typeof ACADEMY_EVENTS;

/** The (event, detail) pair to count, or undefined for anything not on the list. */
export function academyEventKey(event: unknown, detail: unknown): { event: AcademyEvent; detail: string } | undefined {
  if (typeof event !== "string" || !Object.hasOwn(ACADEMY_EVENTS, event)) return undefined;
  const details: readonly string[] = ACADEMY_EVENTS[event as AcademyEvent];
  if (details.length === 0) return detail === undefined || detail === null || detail === "" ? { event: event as AcademyEvent, detail: "" } : undefined;
  return typeof detail === "string" && details.includes(detail) ? { event: event as AcademyEvent, detail } : undefined;
}
