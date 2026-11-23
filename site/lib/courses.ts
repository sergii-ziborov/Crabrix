import "server-only";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { PlaygroundDocument } from './playground-document';

export type BridgeLanguage = "c" | "javascript" | "typescript";
export type LessonBridge = {
  from: BridgeLanguage;
  fromLabel: string;
  fromCode: string;
  fromCaption: string;
  contrasts: { from: string; rust: string }[];
  /** "courseID/lessonID" of Academy lessons this lesson counts as known in the app. */
  credits: string[];
};

export type Lesson = {
  id: string;
  title: string;
  concept: string;
  minutes: number;
  order: number;
  exerciseKind: string;
  playgroundProject?: PlaygroundDocument;
  resources?: { title: string; url: string }[];
  illustration?: { path: string; alt: string; caption: string; width?: number; height?: number };
  bridge?: LessonBridge;
  writing?: {
    summary?: string;
    rule?: string;
    explanation?: string;
    exampleCode?: string;
    exampleCaption?: string;
    task?: string;
    practiceCode?: string;
    question?: string;
    answers?: string[];
    correctAnswer?: number;
    feedback?: string;
    success?: string;
  };
  depth?: {
    misconception?: string;
    correction?: string;
    traceSteps?: { title: string; detail: string }[];
    transferChallenge?: string;
    connections?: { title: string; concept: string; direction: string }[];
  };
  algorithm?: {
    categoryID?: string;
    patternID?: string;
    categoryTitle?: string;
    difficulty?: string;
    stage?: string;
    idea?: string;
    complexity?: string;
    useCases?: string;
    visibleInput?: string;
    task?: string;
    rustSketch?: string;
    expectedAnswer?: string;
  };
};

export type Unit = { id: string; title: string; subtitle: string; order: number; lessons: Lesson[] };
export type Course = { id: string; title: string; subtitle: string; level: string; order: number; units: Unit[] };
export type CourseSnapshot = {
  source: string;
  sourceCommit: string;
  courseCount: number;
  lessonCount: number;
  rustLessonCount: number;
  courses: Course[];
};

let snapshot: CourseSnapshot | undefined;

export function courseSnapshot(): CourseSnapshot {
  snapshot ??= JSON.parse(readFileSync(join(process.cwd(), "content", "courses.json"), "utf8")) as CourseSnapshot;
  return snapshot;
}

export function courseById(id: string): Course | undefined {
  return courseSnapshot().courses.find((course) => course.id === id);
}

export function lessonById(course: Course, id: string): { unit: Unit; lesson: Lesson } | undefined {
  for (const unit of course.units) {
    const lesson = unit.lessons.find((item) => item.id === id);
    if (lesson) return { unit, lesson };
  }
  return undefined;
}

export function courseLessons(course: Course): Lesson[] {
  return course.units.flatMap((unit) => unit.lessons);
}

/** A course written for developers coming from another language. */
export function isBridgeCourse(course: Course): boolean {
  return course.units.some((unit) => unit.lessons.some((lesson) => lesson.bridge));
}

export type LessonRef = { course: Course; lesson: Lesson };

/** Resolves a "courseID/lessonID" credit target. */
export function lessonRef(path: string): LessonRef | undefined {
  const [courseId, lessonId] = path.split("/", 2);
  const course = courseById(courseId);
  const lesson = course && lessonById(course, lessonId)?.lesson;
  return course && lesson ? { course, lesson } : undefined;
}

let creditIndex: Map<string, LessonRef[]> | undefined;

/** Bridge lessons that credit the given Academy lesson, in course order. */
export function bridgeLessonsCrediting(courseId: string, lessonId: string): LessonRef[] {
  if (!creditIndex) {
    creditIndex = new Map();
    for (const course of courseSnapshot().courses) {
      for (const lesson of courseLessons(course)) {
        for (const target of lesson.bridge?.credits ?? []) {
          creditIndex.set(target, [...(creditIndex.get(target) ?? []), { course, lesson }]);
        }
      }
    }
  }
  return creditIndex.get(`${courseId}/${lessonId}`) ?? [];
}
