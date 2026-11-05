import { pageMetadata } from "@/lib/seo";
import { PlaygroundLoader } from "@/components/playground/loader";
import "./playground.css";
import { currentViewer } from '@/lib/auth';
import { courseById, lessonById } from '@/lib/courses';
import { notFound, redirect } from 'next/navigation';
import { lessonPlayground } from '@/lib/lesson-playground';
export const metadata = pageMetadata({ title: "Rust Playground — Run Rust Locally in Your Browser", description: "Run Rust locally in your browser, prepare supported Cargo crates, organize source folders and code together in encrypted rooms. Live interviews, AI agents and ZIP export. No login.", path: "/playground/", modifiedDate: "2026-11-05" });
export default async function PlaygroundPage({ searchParams }: { searchParams: Promise<{ lesson?: string | string[] }> }) {
  const { lesson: path } = await searchParams;
  if (path === undefined) return <PlaygroundLoader />;
  if (typeof path !== 'string' || !/^[a-z0-9-]+\/[a-z0-9-]+$/.test(path)) notFound();
  // The ordinary Playground is public. Full Academy starter text retains the
  // same free-account gate as its lesson and is never sent to a guest client.
  if (!await currentViewer()) redirect('/login/?next=' + encodeURIComponent('/playground/?lesson=' + path));
  const [courseId, lessonId] = path.split('/');
  const course = courseById(courseId);
  const lesson = course && lessonById(course, lessonId)?.lesson;
  if (!lesson?.playgroundProject) notFound();
  return <PlaygroundLoader key={path} initialDocument={lessonPlayground(lesson.playgroundProject)} initialNotice="Lesson copy · prepare the pinned packages on this device, then Run or Debug locally." />;
}
