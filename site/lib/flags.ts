/**
 * Switches for "Learn Rust with Your AI Agent" (docs/ai-learning/PLAN.md, "Phase 7").
 * Each one turns off only the new feature; lessons, the Playground and existing MCP rooms
 * do not read them. Static pages read them at build time, route handlers at request time.
 */
const off = (name: string) => /^(off|0|false|no|paused)$/i.test((process.env[name] ?? "").trim());

/** /learn/with-ai/, the /learn/ block, lesson AI prompts, the feedback card and the sitemap entry. */
export const aiLearningEnabled = () => !off("CRABRIX_AI_LEARNING");
/** /api/academy/v1/* (status.json always answers). */
export const academyApiEnabled = () => !off("CRABRIX_ACADEMY_API");
/** /api/academy/v1/events: when off, events are accepted and discarded. */
export const academyEventsEnabled = () => !off("CRABRIX_ACADEMY_EVENTS");
/** What status.json reports for https://crabrix.com/mcp/academy (served by the SDK container). */
export const academyMcpState = (): "on" | "paused" => off("CRABRIX_ACADEMY_MCP_STATE") ? "paused" : "on";
