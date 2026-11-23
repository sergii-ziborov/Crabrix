import { createHash } from "node:crypto";
import type { PlaygroundDocument } from "./playground-document.ts";

/**
 * Playground practice copies (docs/ai-learning/PLAN.md, "Phase 4"). crabrix-courses
 * tools/practice_starters.py lists lessons whose own code compiles for the Playground's
 * target; a copy is served only while the lesson text still has the hash that was checked.
 */
export type PracticeStarter = {
  courseId: string; lessonId: string; edition: "2021" | "2024";
  source: "practiceCode" | "exampleCode"; wrap: null | "main-added" | "in-main";
  sha256: string; programSha256: string; check: "compiles" | "fails-by-design";
};

const sha256 = (text: string) => createHash("sha256").update(text, "utf8").digest("hex");

/** Same transform as practice_starters.program(): the lesson text unchanged, placed in a program. */
export function practiceProgram(code: string, wrap: PracticeStarter["wrap"]): string {
  if (wrap === null) return code;
  const body = code.replace(/\s+$/u, "");
  if (wrap === "main-added") return `${body}\n\nfn main() {}\n`;
  return `fn main() {\n${body.split("\n").map(line => line ? `    ${line}` : line).join("\n")}\n}\n`;
}

export function practiceNotice(starter: PracticeStarter): string {
  if (starter.check === "fails-by-design") return "Practice copy · this lesson's code does not compile yet: fixing it is the exercise. Run shows the compiler's message. Your saved drafts are not changed.";
  if (starter.wrap === "main-added") return "Practice copy · this lesson's definitions with an empty main added. Call them from main, then Run or Debug locally. Your saved drafts are not changed.";
  if (starter.wrap === "in-main") return "Practice copy · this lesson's code placed inside main. Edit it, then Run or Debug locally. Your saved drafts are not changed.";
  return "Practice copy of this lesson's code · edit it, then Run or Debug locally. Your saved drafts are not changed.";
}

/** The Playground document, or undefined when the lesson is not listed or its text changed. */
export function practiceCopy(lesson: { id: string; writing?: object | null }, starter: PracticeStarter | undefined): PlaygroundDocument | undefined {
  if (!starter || starter.lessonId !== lesson.id) return undefined;
  const code = (lesson.writing as Record<string, unknown> | null | undefined)?.[starter.source];
  if (typeof code !== "string" || sha256(code) !== starter.sha256) return undefined;
  const program = practiceProgram(code, starter.wrap);
  if (sha256(program) !== starter.programSha256) return undefined;
  return { schemaVersion: 1, name: `${lesson.id}-practice`, entryFile: "main.rs", edition: starter.edition, files: { "main.rs": program } };
}
