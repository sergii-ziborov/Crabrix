import "server-only";
import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { bridgeLessonsCrediting, courseById, courseLessons, courseSnapshot, lessonById, lessonRef, type Course, type Lesson } from "./courses";
import { lessonAlgorithmTrace } from "./algorithm-traces";
import { pageUrl, siteOrigin } from "./seo";
import { appSupportsBridgeCredits } from "./bridges";
import { practiceCopy, practiceNotice, type PracticeStarter } from "./practice-copy";
import { lessonPlayground } from "./lesson-playground";
import type { PlaygroundDocument } from "./playground-document";

/**
 * Public, read-only Academy API v1 (docs/ai-learning/PLAN.md). It exposes only what the
 * lesson web pages already publish. Grading harnesses and check files are not in the web
 * corpus, so they cannot appear here. Nothing here reads accounts or learner progress.
 */
export const ACADEMY_SCHEMA_VERSION = 1;

type PathStep = { courseId: string; lessonId: string };
type LearningPath = { id: string; title: string; audience: string; description: string; steps: PathStep[] };
type ExampleProject = {
  id: string; title: string; detail: string; difficulty: string; category: string; concepts: string[];
  order: number; entryFile: string; readme: string; files: Record<string, string>;
};

const contentFile = (name: string) => join(process.cwd(), "content", name);
let paths: LearningPath[] | undefined;
let examples: ExampleProject[] | undefined;
let contract: string | undefined;
let schema: string | undefined;
let starters: Map<string, PracticeStarter> | undefined;
let index: Record<string, unknown> | undefined;

export function catalogVersion(): string {
  return courseSnapshot().sourceCommit.slice(0, 12);
}

export function learningPaths(): LearningPath[] {
  paths ??= existsSync(contentFile("academy-paths.json"))
    ? (JSON.parse(readFileSync(contentFile("academy-paths.json"), "utf8")).paths as LearningPath[]) : [];
  return paths;
}

export function exampleProjects(): ExampleProject[] {
  examples ??= existsSync(contentFile("academy-examples.json"))
    ? (JSON.parse(readFileSync(contentFile("academy-examples.json"), "utf8")).examples as ExampleProject[]) : [];
  return examples;
}

export function teachingContract(): string {
  contract ??= existsSync(contentFile("academy-teaching-contract.md"))
    ? readFileSync(contentFile("academy-teaching-contract.md"), "utf8") : "";
  return contract;
}

export function learningStateSchema(): string {
  schema ??= existsSync(contentFile("academy-learning-state.schema.json"))
    ? readFileSync(contentFile("academy-learning-state.schema.json"), "utf8") : "";
  return schema;
}

function practiceStarters(): Map<string, PracticeStarter> {
  starters ??= new Map(existsSync(contentFile("academy-practice-starters.json"))
    ? (JSON.parse(readFileSync(contentFile("academy-practice-starters.json"), "utf8")).starters as PracticeStarter[])
      .map(starter => [`${starter.courseId}/${starter.lessonId}`, starter]) : []);
  return starters;
}

/** A practice copy of the lesson's own code for the Playground, when it was qualified. */
export function lessonPracticeCopy(course: Course, lesson: Lesson): { document: PlaygroundDocument; notice: string } | undefined {
  if (course.id === "algorithms" || lesson.playgroundProject) return undefined;
  const starter = practiceStarters().get(`${course.id}/${lesson.id}`);
  const document = practiceCopy(lesson, starter);
  return document && starter ? { document, notice: practiceNotice(starter) } : undefined;
}

export function teachingContractVersion(): string {
  return /Version (\d+\.\d+\.\d+)/.exec(teachingContract())?.[1] ?? "0.0.0";
}

const lessonUrl = (courseId: string, lessonId: string) => pageUrl(`/learn/${courseId}/${lessonId}/`);
const playgroundUrl = (courseId: string, lessonId: string) => `${siteOrigin}/playground/?lesson=${courseId}/${lessonId}`;

export type PlaygroundKind = "lesson-project" | "practice-copy" | "algorithm-trace";

/** Mirrors app/playground/page.tsx: what /playground/?lesson=<course>/<lesson> opens, if anything. */
export function playgroundKind(course: Course, lesson: Lesson): PlaygroundKind | null {
  if (course.id === "algorithms") {
    try { return lessonAlgorithmTrace(lesson) ? "algorithm-trace" : null; } catch { return null; }
  }
  if (lesson.playgroundProject) return "lesson-project";
  return lessonPracticeCopy(course, lesson) ? "practice-copy" : null;
}

/** Only lessons the Playground can open get a link. */
export function playgroundAvailable(course: Course, lesson: Lesson): boolean {
  return playgroundKind(course, lesson) !== null;
}

/**
 * Whether the released App Store version has the lesson yet. The website can run ahead of
 * the app: the bridge courses and "What Rust Is" ship with Crabrix 1.1.9. Flip with
 * appSupportsBridgeCredits when that version is live.
 */
export function appAvailability(courseId: string, lessonId: string): "released" | "next-app-version" {
  if (appSupportsBridgeCredits) return "released";
  return courseId.startsWith("rust-for-") || `${courseId}/${lessonId}` === "basics/what-is-rust" ? "next-app-version" : "released";
}

function shortSummary(lesson: Lesson): string {
  const text = (lesson.writing?.summary || lesson.concept).replace(/\s+/g, " ").trim();
  return text.length <= 300 ? text : `${text.slice(0, text.lastIndexOf(" ", 297))}…`;
}

function unitOf(course: Course, lessonId: string) {
  return course.units.find(unit => unit.lessons.some(lesson => lesson.id === lessonId));
}

export function academyIndex(): Record<string, unknown> {
  if (index) return index;
  const snapshot = courseSnapshot();
  const courses = [...snapshot.courses].sort((a, b) => a.order - b.order);
  index = {
    schemaVersion: ACADEMY_SCHEMA_VERSION,
    catalogVersion: catalogVersion(),
    source: { repository: snapshot.source, commit: snapshot.sourceCommit },
    platforms: {
      web: "Every lesson listed here is public at its url.",
      app: "The Crabrix iOS app installs signed CoursePacks; a lesson can reach the app later than the website. Each lesson's appAvailability is \"released\" (in the App Store version) or \"next-app-version\".",
    },
    courses: courses.map(course => ({
      id: course.id, title: course.title, subtitle: course.subtitle, level: course.level, order: course.order,
      url: pageUrl(`/learn/${course.id}/`), lessonCount: courseLessons(course).length,
      units: course.units.map(unit => ({ id: unit.id, title: unit.title, subtitle: unit.subtitle, lessonIds: unit.lessons.map(lesson => lesson.id) })),
    })),
    lessons: courses.flatMap(course => course.units.flatMap(unit => unit.lessons.map(lesson => ({
      courseId: course.id, unitId: unit.id, id: lesson.id, title: lesson.title, concept: lesson.concept,
      summary: shortSummary(lesson), rule: lesson.writing?.rule ?? "", minutes: lesson.minutes,
      exerciseKind: lesson.exerciseKind, url: lessonUrl(course.id, lesson.id),
      playground: playgroundAvailable(course, lesson), bridgeFrom: lesson.bridge?.from ?? null,
      credits: lesson.bridge?.credits ?? [], appAvailability: appAvailability(course.id, lesson.id),
    })))),
    paths: learningPaths().map(path => ({ id: path.id, title: path.title, audience: path.audience,
      description: path.description, stepCount: path.steps.length })),
    examples: exampleProjects().map(example => ({ id: example.id, title: example.title, detail: example.detail,
      difficulty: example.difficulty, category: example.category, concepts: example.concepts })),
    teachingContract: { version: teachingContractVersion(), url: `${siteOrigin}/api/academy/v1/teaching-contract.md` },
    learningState: { schemaVersion: 1, schemaUrl: `${siteOrigin}/api/academy/v1/learning-state.schema.json` },
  };
  return index;
}

export function academyLesson(courseId: string, lessonId: string): Record<string, unknown> | undefined {
  const course = courseById(courseId);
  const found = course && lessonById(course, lessonId);
  if (!course || !found) return undefined;
  const { lesson, unit } = found;
  const lessons = courseLessons(course);
  const position = lessons.findIndex(item => item.id === lesson.id);
  const neighbour = (item: Lesson | undefined, relation: "previous" | "next") =>
    item ? [{ courseId: course.id, lessonId: item.id, title: item.title, relation }] : [];
  const related = [
    ...neighbour(lessons[position - 1], "previous"),
    ...neighbour(lessons[position + 1], "next"),
    ...(lesson.bridge?.credits ?? []).flatMap(path => {
      const ref = lessonRef(path);
      return ref ? [{ courseId: ref.course.id, lessonId: ref.lesson.id, title: ref.lesson.title, relation: "covers" }] : [];
    }),
    ...bridgeLessonsCrediting(course.id, lesson.id).map(ref => ({ courseId: ref.course.id, lessonId: ref.lesson.id, title: ref.lesson.title, relation: "coveredBy" })),
  ];
  const kind = playgroundKind(course, lesson);
  const { playgroundProject: _project, resources: _resources, illustration, ...rest } = lesson;
  void _project; void _resources;
  return {
    schemaVersion: ACADEMY_SCHEMA_VERSION, catalogVersion: catalogVersion(),
    courseId: course.id, courseTitle: course.title, unitId: unit.id, unitTitle: unit.title,
    id: rest.id, title: rest.title, concept: rest.concept, minutes: rest.minutes, exerciseKind: rest.exerciseKind,
    url: lessonUrl(course.id, lesson.id),
    writing: rest.writing ?? null, depth: rest.depth ?? null, algorithm: rest.algorithm ?? null, bridge: rest.bridge ?? null,
    illustration: illustration ? { url: `${siteOrigin}/learn-media/${course.id}/${illustration.path.slice(6)}`, alt: illustration.alt, caption: illustration.caption } : null,
    playground: kind ? { available: true, url: playgroundUrl(course.id, lesson.id), kind } : { available: false, url: null, kind: null },
    appAvailability: appAvailability(course.id, lesson.id),
    related,
  };
}

export function academyPath(pathId: string): Record<string, unknown> | undefined {
  const path = learningPaths().find(item => item.id === pathId);
  if (!path) return undefined;
  return {
    schemaVersion: ACADEMY_SCHEMA_VERSION, catalogVersion: catalogVersion(),
    id: path.id, title: path.title, audience: path.audience, description: path.description,
    steps: path.steps.flatMap(step => {
      const ref = lessonRef(`${step.courseId}/${step.lessonId}`);
      return ref ? [{ courseId: step.courseId, lessonId: step.lessonId, title: ref.lesson.title,
        url: lessonUrl(step.courseId, step.lessonId), note: unitOf(ref.course, ref.lesson.id)?.title ?? "" }] : [];
    }),
  };
}

/** An Examples project as a new Playground document; the original stays unchanged. */
export function examplePlaygroundDocument(exampleId: string): PlaygroundDocument | undefined {
  const example = exampleProjects().find(item => item.id === exampleId);
  if (!example) return undefined;
  const edition = /edition\s*=\s*"(2021|2024)"/.exec(example.files["Cargo.toml"] ?? "")?.[1] === "2024" ? "2024" : "2021";
  try {
    return lessonPlayground({ schemaVersion: 1, name: example.id, entryFile: example.entryFile, edition, files: { ...example.files } });
  } catch { return undefined; }
}

export function academyExample(exampleId: string): Record<string, unknown> | undefined {
  const example = exampleProjects().find(item => item.id === exampleId);
  if (!example) return undefined;
  return {
    schemaVersion: ACADEMY_SCHEMA_VERSION, catalogVersion: catalogVersion(),
    id: example.id, title: example.title, detail: example.detail, difficulty: example.difficulty,
    category: example.category, concepts: example.concepts, readme: example.readme, files: example.files,
    entryFile: example.entryFile, illustration: null,
    playground: examplePlaygroundDocument(example.id)
      ? { available: true, url: `${siteOrigin}/playground/?example=${example.id}`, kind: "example-copy" } : { available: false, url: null, kind: null },
  };
}

/** Strong validator for one response body. */
export function etagFor(body: string): string {
  return `"${createHash("sha256").update(body).digest("base64url").slice(0, 27)}"`;
}
