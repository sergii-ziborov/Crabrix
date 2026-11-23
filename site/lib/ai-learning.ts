import { siteOrigin } from "./seo.ts";

/** Remote, read-only Academy MCP (Streamable HTTP, no sign-in). Room links are a separate thing. */
export const ACADEMY_MCP_URL = `${siteOrigin}/mcp/academy`;
/** The first Crabrix MCP release that includes the crabrix_academy_* tools and the learn-rust skill. */
export const ACADEMY_SDK_VERSION = "0.6.0";
/** Feedback goes to an email draft the learner sends; the address is base64 like the other mail buttons. */
export const FEEDBACK_MAIL = "c2VyZ2lpLnppYm9yb3ZAZ21haWwuY29t";

export const learningPrompts = [
  { id: "beginner", title: "Beginner",
    text: "Teach me Rust through Crabrix Academy. Start from the basics, give me practical exercises, and help me understand each concept before moving on." },
  { id: "nodejs", title: "Node.js developer",
    text: "I am experienced with Node.js and TypeScript. Teach me Rust through Crabrix Academy using concepts familiar to backend developers. Give me practical exercises and use the Crabrix Playground when appropriate." },
  { id: "c", title: "C developer",
    text: "I have experience with C. Teach me Rust through memory management, ownership, borrowing, lifetimes and system programming. Use Crabrix Academy lessons and practical examples." },
  { id: "continue", title: "Continue learning",
    text: "Help me continue my Crabrix Rust learning using my available progress and previous exercises. Do not assume I have completed lessons unless the learning state confirms it." },
];

/** Public lesson context only: IDs, title, goal, URL and practice options. No learner data. */
export function lessonPrompt(lesson: { courseId: string; lessonId: string; title: string; goal: string; url: string; playgroundUrl?: string }): string {
  const practice = lesson.playgroundUrl
    ? `Practice: open the starter in the Crabrix Playground (${lesson.playgroundUrl}) and I will write the code there.`
    : "Practice: give me the lesson's exercise (crabrix_academy_get_exercise); I will write and run the code in Crabrix.";
  return [
    "I'm learning Rust with Crabrix Academy. Teach me this lesson with the Crabrix Academy tools.",
    `Lesson: ${lesson.title} (courseId "${lesson.courseId}", lessonId "${lesson.lessonId}")`,
    `Link: ${lesson.url}`,
    `Goal: ${lesson.goal.replace(/`/g, "")}`,
    practice,
    "Explain it step by step for my level, let me write the code myself, give hints before any solution, and do not mark anything as passed: only Crabrix checks do that.",
  ].join("\n");
}
