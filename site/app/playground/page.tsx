import { pageMetadata } from "@/lib/seo";
import { PlaygroundLoader } from "@/components/playground/loader";
import "./playground.css";
import { courseById, lessonById } from '@/lib/courses';
import { notFound } from 'next/navigation';
import { lessonPlayground } from '@/lib/lesson-playground';
import { algorithmPlayground } from '@/lib/algorithm-playground';
import { lessonAlgorithmTrace } from '@/lib/algorithm-traces';
import { examplePlaygroundDocument, lessonPracticeCopy } from '@/lib/academy';
import { AIArrival } from '@/components/ai-learning-client';
import { aiLearningEnabled } from '@/lib/flags';
export const metadata = pageMetadata({ title: "Rust Playground — Run Rust Locally in Your Browser", description: "Run Rust locally in your browser, prepare supported Cargo crates, organize source folders and code together in encrypted rooms. Live interviews, AI agents and ZIP export. No login.", path: "/playground/", modifiedDate: "2026-11-18" });
export default async function PlaygroundPage({ searchParams }: { searchParams: Promise<{ lesson?: string | string[]; example?: string | string[] }> }) {
  const { lesson: path, example } = await searchParams;
  if (path === undefined && example !== undefined) {
    // A copy of an Examples project; the original stays unchanged (PLAN.md Phase 4).
    if (typeof example !== 'string' || !/^[a-z0-9][a-z0-9-]{0,79}$/.test(example)) notFound();
    const document = examplePlaygroundDocument(example);
    if (!document) notFound();
    return <>{aiLearningEnabled() && <AIArrival place="playground" kind="example-copy" />}<PlaygroundLoader key={`example/${example}`} initialDocument={document} initialNotice="Example copy · edit it freely, then Run or Debug locally. The original Example and your saved drafts are not changed." /></>;
  }
  if (path === undefined) return <PlaygroundLoader />;
  if (typeof path !== 'string' || path.length > 256 || !/^[a-z0-9-]+\/[a-z0-9][a-z0-9.-]*$/.test(path)) notFound();
  // Only the validated starter attached to a known public lesson is exposed.
  const [courseId, lessonId] = path.split('/');
  const course = courseById(courseId);
  const lesson = course && lessonById(course, lessonId)?.lesson;
  if (!lesson) notFound();
  if (course?.id === 'algorithms') {
    const trace = lessonAlgorithmTrace(lesson);
    if (!trace) notFound();
    return <>{aiLearningEnabled() && <AIArrival place="playground" kind="algorithm-trace" />}<PlaygroundLoader key={path} initialDocument={algorithmPlayground(trace, lesson.id)} initialNotice="Algorithm example copy · change the original input, then Run or Debug locally. The recording stays unchanged." /></>;
  }
  if (!lesson.playgroundProject) {
    // A practice copy of the lesson's own code, qualified in crabrix-courses (PLAN.md Phase 4).
    const copy = course && lessonPracticeCopy(course, lesson);
    if (!copy) notFound();
    return <>{aiLearningEnabled() && <AIArrival place="playground" kind="practice-copy" />}<PlaygroundLoader key={path} initialDocument={copy.document} initialNotice={copy.notice} /></>;
  }
  const notice = path === 'projects/feature-compatibility-matrix'
    ? 'Lesson copy · use Run for this feature example. Its conditional statements are outside the source Debug profile.'
    : 'Lesson copy · edit and run locally. If Cargo dependencies are declared, prepare them on this device first.';
  return <>{aiLearningEnabled() && <AIArrival place="playground" kind="lesson-project" />}<PlaygroundLoader key={path} initialDocument={lessonPlayground(lesson.playgroundProject)} initialNotice={notice} /></>;
}
