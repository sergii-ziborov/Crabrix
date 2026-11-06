import "server-only";
import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { join } from "node:path";
import type { AlgorithmTrace } from "./algorithm-trace-types";
import type { Lesson } from "./courses";

// Only the selected known lesson's validated trace is sent to its client.
// Complete lessons and traces are public; the raw content tree stays unserved.
export function lessonAlgorithmTrace(lesson: Lesson): AlgorithmTrace | undefined {
  if (!lesson.algorithm?.patternID || !lesson.writing?.exampleCode) return;
  const digest = createHash("sha256").update(lesson.writing.exampleCode).digest("hex");
  const key = `${lesson.algorithm.patternID}-${digest.slice(0, 16)}`;
  if (!/^[a-z0-9-]+$/.test(key)) throw new Error("Invalid algorithm trace key");
  const trace = readTrace(key);
  if (trace.sourceHash !== digest) throw new Error(`Stale algorithm trace: ${lesson.id}`);
  return trace;
}

function readTrace(key: string): AlgorithmTrace {
  return JSON.parse(readFileSync(join(process.cwd(), "content", "algorithm-traces", `${key}.json`), "utf8"));
}

export function publicAlgorithmDemo(): AlgorithmTrace { return readTrace("demo-linear-scan"); }
