import { readFileSync } from "node:fs";
import { join } from "node:path";

export type Lesson = {
  id: string;
  title: string;
  concept: string;
  minutes: number;
  order: number;
  exerciseKind: string;
  illustration?: { path: string; alt: string; caption: string };
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
