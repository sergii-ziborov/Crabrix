import type { Lesson } from "./courses";

// Only dates of recorded editorial changes, never the time of each build.
export const lessonModifiedDates: Record<string, string> = Object.fromEntries(
  ["strings", "collections", "number-types", "operators", "control-flow", "enums"].map((id) => [`basics/${id}`, "2026-10-20"]),
);
lessonModifiedDates["systems/ffi"] = "2026-10-20";
lessonModifiedDates["interview/q-ffi-abi"] = "2026-10-20";
lessonModifiedDates["interview/q-syscalls"] = "2026-10-20";
lessonModifiedDates["interview/q-dyn-generics"] = "2026-10-20";
export const courseModifiedDates: Record<string, string> = {
  basics: "2026-10-20", systems: "2026-10-20", interview: "2026-10-20",
};

export function searchDescription(text: string): string {
  const plain = text.replace(/`/g, "").replace(/\s+/g, " ").trim();
  if (plain.length <= 170) return plain;
  const prefix = plain.slice(0, 167);
  return `${prefix.slice(0, prefix.lastIndexOf(" "))}…`;
}

export function lessonDescription(lesson: Lesson): string {
  const summary = searchDescription(lesson.writing?.summary || lesson.concept);
  return searchDescription(`${lesson.title}: ${summary}${summary.length < 60 ? " Study the Rust pattern, then try the exercise." : ""}`);
}
