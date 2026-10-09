import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { courseById, courseLessons, courseSnapshot, lessonById } from "@/lib/courses";

function prose(text: string) {
  return text.split(/(`[^`]+`)/g).map((part, index) =>
    part.startsWith("`") && part.endsWith("`")
      ? <code key={index}>{part.slice(1, -1)}</code>
      : part);
}

export function generateStaticParams() {
  return courseSnapshot().courses.flatMap((course) =>
    course.units.flatMap((unit) => unit.lessons.map((lesson) => ({ course: course.id, lesson: lesson.id }))));
}

export async function generateMetadata({ params }: { params: Promise<{ course: string; lesson: string }> }): Promise<Metadata> {
  const { course: courseId, lesson: lessonId } = await params;
  const course = courseById(courseId);
  const lesson = course && lessonById(course, lessonId)?.lesson;
  return lesson ? { title: `${lesson.title} — ${course.title}`, description: lesson.writing?.summary || lesson.concept } : {};
}

export default async function LessonPage({ params }: { params: Promise<{ course: string; lesson: string }> }) {
  const { course: courseId, lesson: lessonId } = await params;
  const course = courseById(courseId);
  if (!course) notFound();
  const found = lessonById(course, lessonId);
  if (!found) notFound();
  const { unit, lesson } = found;
  const writing = lesson.writing;
  const depth = lesson.depth;
  const algorithm = lesson.algorithm;
  const lessons = courseLessons(course);
  const index = lessons.findIndex((item) => item.id === lesson.id);
  const isBasics = course.id === "basics";
  const explanationParagraphs = writing?.explanation?.split(/\n\s*\n/) || [];
  const exampleSection = (writing?.exampleCode || writing?.practiceCode) && <section><h2>Read the Rust</h2>
    {writing?.exampleCode && <><pre><code>{writing.exampleCode}</code></pre>{writing.exampleCaption && <p>{writing.exampleCaption}</p>}</>}
    {writing?.practiceCode && writing.practiceCode !== writing.exampleCode && <><h3>Practice starter</h3><pre><code>{writing.practiceCode}</code></pre></>}
  </section>;
  return (
    <div className="site-shell lesson-page">
      <nav className="breadcrumbs" aria-label="Breadcrumbs">
        <Link href="/learn">Learn</Link><span>/</span>
        <Link href={`/learn/${course.id}`}>{course.title}</Link><span>/</span>
        <span>{unit.title}</span>
      </nav>
      <div className="page-intro lesson-content">
        <p className="eyebrow">{unit.title} · {lesson.minutes} min · free lesson</p>
        <h1>{lesson.title}</h1>
        <p className="lede">{writing?.summary || lesson.concept}</p>
        {writing?.rule && <div className="lesson-callout"><strong>Core idea</strong><p>{prose(writing.rule)}</p></div>}
      </div>
      <article className="lesson-content">
        {!isBasics && lesson.illustration && <figure className="lesson-infographic">
          <img src={`/learn-media/${course.id}/${lesson.illustration.path.slice(6)}`} alt={lesson.illustration.alt} loading="lazy" />
          <figcaption>{lesson.illustration.caption}</figcaption>
        </figure>}
        {isBasics && explanationParagraphs.length > 0 && <section className="lesson-reading"><h2>Start with the idea</h2>
          <p>{prose(explanationParagraphs[0])}</p>
        </section>}
        {isBasics && exampleSection}
        {isBasics && lesson.illustration && <figure className="lesson-infographic">
          <img src={`/learn-media/${course.id}/${lesson.illustration.path.slice(6)}`} alt={lesson.illustration.alt} loading="lazy" />
          <figcaption>{lesson.illustration.caption}</figcaption>
        </figure>}
        {isBasics && explanationParagraphs.length > 1 && <section className="lesson-reading"><h2>Work through it</h2>
          {explanationParagraphs.slice(1).map((paragraph, paragraphIndex) => <p key={paragraphIndex}>{prose(paragraph)}</p>)}
        </section>}
        {!isBasics && writing?.explanation && <section><h2>Understand it</h2>
          {explanationParagraphs.map((paragraph, paragraphIndex) => <p key={paragraphIndex}>{prose(paragraph)}</p>)}
        </section>}
        {algorithm && <section><h2>The pattern</h2>
          {algorithm.idea && <p>{algorithm.idea}</p>}
          {algorithm.useCases && <p><strong>When to use it:</strong> {algorithm.useCases}</p>}
          {algorithm.complexity && <p><strong>Complexity:</strong> {algorithm.complexity}</p>}
          {algorithm.visibleInput && <p><strong>Input:</strong> <code>{algorithm.visibleInput}</code></p>}
          {algorithm.rustSketch && <pre><code>{algorithm.rustSketch}</code></pre>}
        </section>}
        {!isBasics && exampleSection}
        {(writing?.task || algorithm?.task || writing?.success) && <section><h2>Try it</h2>
          <p>{prose(writing?.task || algorithm?.task || "")}</p>
          {writing?.success && <p><strong>What success looks like:</strong> {prose(writing.success)}</p>}
        </section>}
        {writing?.question && <section><h2>Check your understanding</h2><p>{writing.question}</p>
          <details className="answer-reveal"><summary>Reveal the answer</summary>
            {writing.answers && <ol>{writing.answers.map((answer, answerIndex) => <li className={answerIndex === writing.correctAnswer ? "correct" : undefined} key={answerIndex}>{answer}</li>)}</ol>}
            {writing.feedback && <p>{writing.feedback}</p>}
          </details>
        </section>}
        {isBasics && depth?.transferChallenge && <section className="lesson-next-step"><h2>One more experiment</h2>
          <p>{prose(depth.transferChallenge)}</p>
        </section>}
        {!isBasics && depth && <section><h2>Go deeper</h2>
          {depth.misconception && <p><strong>Common misconception:</strong> {depth.misconception}</p>}
          {depth.correction && <p>{prose(depth.correction)}</p>}
          {depth.traceSteps && <ol>{depth.traceSteps.map((step, stepIndex) => <li key={stepIndex}><strong>{step.title}:</strong> {prose(step.detail)}</li>)}</ol>}
          {depth.transferChallenge && <p><strong>Transfer challenge:</strong> {prose(depth.transferChallenge)}</p>}
          {depth.connections && depth.connections.length > 0 && <><h3>Connections</h3><ul>{depth.connections.map((connection, connectionIndex) => <li key={connectionIndex}><strong>{connection.title}:</strong> {connection.concept}</li>)}</ul></>}
        </section>}
        {algorithm?.expectedAnswer && <details><summary>Reveal the Algorithm Atlas answer</summary><p><code>{algorithm.expectedAnswer}</code></p></details>}
        <nav className="lesson-list" aria-label="Lesson navigation">
          {index > 0 && <Link className="lesson-link" href={`/learn/${course.id}/${lessons[index - 1].id}`}>← {lessons[index - 1].title}</Link>}
          {index + 1 < lessons.length && <Link className="lesson-link" href={`/learn/${course.id}/${lessons[index + 1].id}`}>{lessons[index + 1].title} →</Link>}
        </nav>
      </article>
    </div>
  );
}
