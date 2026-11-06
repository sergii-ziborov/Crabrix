import type { Metadata } from "next";
import { pageMetadata, pageUrl, breadcrumbs } from "@/lib/seo";
import { lessonDescription, lessonPageModifiedDate } from "@/lib/lesson-seo";
import Link from "next/link";
import { notFound } from "next/navigation";
import { courseById, courseLessons, lessonById } from "@/lib/courses";
import { SyntaxCode } from "@/components/SyntaxCode";
import { StructuredData } from "@/components/structured-data";
import { CourseIcon } from "@/components/course-icon";
import { AlgorithmVisualizer } from "@/components/algorithm-visualizer";
import { lessonAlgorithmTrace } from "@/lib/algorithm-traces";
import { lessonRelatedPosts } from '@/lib/lesson-related-posts';
import { postBySlug } from '@/lib/posts';

export const dynamic = "force-dynamic";

function prose(text: string) {
  return text.split(/(`[^`]+`)/g).map((part, index) =>
    part.startsWith("`") && part.endsWith("`")
      ? <code key={index}>{part.slice(1, -1)}</code>
      : part);
}

export async function generateMetadata({ params }: { params: Promise<{ course: string; lesson: string }> }): Promise<Metadata> {
  const { course: courseId, lesson: lessonId } = await params;
  const course = courseById(courseId);
  const lesson = course && lessonById(course, lessonId)?.lesson;
  return lesson ? pageMetadata({ title: `${lesson.title} — ${course.title}`, description: lessonDescription(lesson), path: `/learn/${course.id}/${lesson.id}/`, kind: "article", modifiedDate: lessonPageModifiedDate(course.id, lesson.id) }) : {};
}

export default async function LessonPage({ params }: { params: Promise<{ course: string; lesson: string }> }) {
  const { course: courseId, lesson: lessonId } = await params;
  const course = courseById(courseId);
  if (!course) notFound();
  const found = lessonById(course, lessonId);
  if (!found) notFound();
  const { unit, lesson } = found;
  const patternSteps = course.id === "algorithms" && lesson.algorithm?.patternID
    ? unit.lessons.filter(item => item.algorithm?.patternID === lesson.algorithm?.patternID) : [];
  const patternNavigation = patternSteps.length > 0 && <nav className="pattern-navigation" aria-label="Steps in this algorithm pattern">
    <h2>Study this pattern</h2>
    <ol>{patternSteps.map(item => <li key={item.id}>{item.id === lesson.id
      ? <span aria-current="page">{item.title}</span>
      : <Link prefetch={false} href={`/learn/${course.id}/${item.id}`}>{item.title}</Link>}</li>)}</ol>
    <p><Link prefetch={false} href={`/learn/algorithms/#${unit.id}`}>Compare methods in {unit.title} →</Link></p>
  </nav>;
  const relatedPosts = lessonRelatedPosts(course.id, lesson.id).flatMap(slug => {
    const post = postBySlug(slug);
    return post ? [post] : [];
  });
  const relatedReading = relatedPosts.length > 0 && <aside className="lesson-reading" aria-label="Related Rust guides">
    <h2>Related free reading</h2><ul>{relatedPosts.map(post => <li key={post.slug}><Link prefetch={false} href={`/blog/${post.slug}/`}>{post.title}</Link></li>)}</ul>
  </aside>;
  const structuredData = <StructuredData data={{ "@context": "https://schema.org", "@graph": [{ "@type": "Article",
    inLanguage: "en", timeRequired: `PT${lesson.minutes}M`, articleSection: course.title,
    headline: lesson.title, description: lessonDescription(lesson),
    url: pageUrl(`/learn/${course.id}/${lesson.id}/`), mainEntityOfPage: pageUrl(`/learn/${course.id}/${lesson.id}/`), isAccessibleForFree: true,
    about: { "@type": "Thing", name: lesson.concept },
    isPartOf: { "@type": "Course", name: course.title, url: pageUrl(`/learn/${course.id}/`) },
    ...(lessonPageModifiedDate(course.id, lesson.id) ? { dateModified: lessonPageModifiedDate(course.id, lesson.id) } : {}),
    author: { "@type": "Person", name: "Serhii Ziborov", url: "https://crabrix.com/about/" },
  }, breadcrumbs([{ name: "Crabrix", path: "/" }, { name: "Learn Rust", path: "/learn/" },
    { name: course.title, path: `/learn/${course.id}/` }, { name: lesson.title, path: `/learn/${course.id}/${lesson.id}/` }])] }} />;
  const writing = lesson.writing;
  const depth = lesson.depth;
  const resources = (Array.isArray(lesson.resources) ? lesson.resources : []).filter(resource => {
    if (!resource || typeof resource.title !== 'string' || typeof resource.url !== 'string') return false;
    try {
      const url = new URL(resource.url);
      return url.protocol === 'https:' && !url.username && !url.password &&
        (url.hostname === 'doc.rust-lang.org' || (url.hostname === 'github.com' &&
          url.pathname.startsWith('/sergii-ziborov/crabrix-courses/')));
    } catch { return false; }
  });
  const algorithm = lesson.algorithm;
  const algorithmTrace = course.id === "algorithms" ? lessonAlgorithmTrace(lesson) : undefined;
  const lessons = courseLessons(course);
  const index = lessons.findIndex((item) => item.id === lesson.id);
  const isBasics = course.id === "basics";
  const explanationParagraphs = writing?.explanation?.split(/\n\s*\n/) || [];
  const exampleSection = (writing?.exampleCode || writing?.practiceCode) && <section><h2>Read the code</h2>
    {writing?.exampleCode && <><SyntaxCode code={writing.exampleCode} />{writing.exampleCaption && <p>{prose(writing.exampleCaption)}</p>}</>}
    {writing?.practiceCode && writing.practiceCode !== writing.exampleCode && <><h3>Practice starter</h3><SyntaxCode code={writing.practiceCode} /></>}
    {lesson.playgroundProject && <p><Link prefetch={false} className="btn" href={`/playground/?lesson=${course.id}/${lesson.id}`} target="_blank" rel="nofollow noopener">Open local example in Playground ↗</Link></p>}
  </section>;
  return (
    <div className="site-shell lesson-page">
      {structuredData}
      <nav className="breadcrumbs" aria-label="Breadcrumbs">
        <Link prefetch={false} href="/learn">Learn</Link><span>/</span>
        <Link prefetch={false} href={`/learn/${course.id}`}>{course.title}</Link><span>/</span>
        <span>{unit.title}</span>
      </nav>
      <div className="page-intro lesson-content">
        <p className="eyebrow">{unit.title} · {lesson.minutes} min · free lesson</p>
        <div className="academy-heading"><CourseIcon course={course.id} size={64} /><h1>{lesson.title}</h1></div>
        <p className="lede">{prose(writing?.summary || lesson.concept)}</p>
        {writing?.rule && <div className="lesson-callout"><strong>Core idea</strong><p>{prose(writing.rule)}</p></div>}
      </div>
      <article className="lesson-content lesson-full">
        {algorithmTrace && <AlgorithmVisualizer key={`${lesson.id}:${algorithmTrace.key}`} trace={algorithmTrace} practice={{href: `/playground/?lesson=${encodeURIComponent(`${course.id}/${lesson.id}`)}`, variation: depth?.transferChallenge}} />}
        {!isBasics && lesson.illustration && <figure className="lesson-infographic">
          <img src={`/learn-media/${course.id}/${lesson.illustration.path.slice(6)}`} alt={lesson.illustration.alt} width={lesson.illustration.width} height={lesson.illustration.height} loading="lazy" />
          <figcaption>{prose(lesson.illustration.caption)}</figcaption>
        </figure>}
        {isBasics && explanationParagraphs.length > 0 && <section className="lesson-reading"><h2>Start with the idea</h2>
          <p>{prose(explanationParagraphs[0])}</p>
        </section>}
        {isBasics && exampleSection}
        {isBasics && lesson.illustration && <figure className="lesson-infographic">
          <img src={`/learn-media/${course.id}/${lesson.illustration.path.slice(6)}`} alt={lesson.illustration.alt} width={lesson.illustration.width} height={lesson.illustration.height} loading="lazy" />
          <figcaption>{prose(lesson.illustration.caption)}</figcaption>
        </figure>}
        {isBasics && explanationParagraphs.length > 1 && <section className="lesson-reading"><h2>Work through it</h2>
          {explanationParagraphs.slice(1).map((paragraph, paragraphIndex) => <p key={paragraphIndex}>{prose(paragraph)}</p>)}
        </section>}
        {!isBasics && writing?.explanation && <section><h2>Understand it</h2>
          {explanationParagraphs.map((paragraph, paragraphIndex) => <p key={paragraphIndex}>{prose(paragraph)}</p>)}
        </section>}
        {algorithm && <section><h2>The pattern</h2>
          {algorithm.idea && <p>{prose(algorithm.idea)}</p>}
          {algorithm.useCases && <p><strong>When to use it:</strong> {prose(algorithm.useCases)}</p>}
          {algorithm.complexity && <p><strong>Complexity:</strong> {algorithm.complexity}</p>}
          {algorithm.visibleInput && <p><strong>Input:</strong> <code>{algorithm.visibleInput}</code></p>}
          {algorithm.rustSketch && algorithm.rustSketch !== writing?.exampleCode && <SyntaxCode code={algorithm.rustSketch} />}
        </section>}
        {!isBasics && exampleSection}
        {(writing?.task || algorithm?.task || writing?.success) && <section><h2>Try it</h2>
          <p>{prose(writing?.task || algorithm?.task || "")}</p>
          {writing?.success && <p><strong>What success looks like:</strong> {prose(writing.success)}</p>}
        </section>}
        {resources.length > 0 && <aside className="lesson-reading" aria-label="Companion sources">
          <h2>Companion sources</h2>
          <ul>{resources.map(resource => <li key={resource.url}><a href={resource.url} rel="noopener noreferrer">{resource.title} ↗</a></li>)}</ul>
        </aside>}
        {writing?.question && <section><h2>Check your understanding</h2><p>{prose(writing.question)}</p>
          <details className="answer-reveal"><summary>Reveal the answer</summary>
            {writing.answers && <ol>{writing.answers.map((answer, answerIndex) => <li className={answerIndex === writing.correctAnswer ? "correct" : undefined} key={answerIndex}>{prose(answer)}</li>)}</ol>}
            {writing.feedback && <p>{prose(writing.feedback)}</p>}
          </details>
        </section>}
        {isBasics && depth?.transferChallenge && <section className="lesson-next-step"><h2>One more experiment</h2>
          <p>{prose(depth.transferChallenge)}</p>
        </section>}
        {!isBasics && depth && <section><h2>Go deeper</h2>
          {depth.misconception && <p><strong>Common misconception:</strong> {prose(depth.misconception)}</p>}
          {depth.correction && <p>{prose(depth.correction)}</p>}
          {depth.traceSteps && <ol>{depth.traceSteps.map((step, stepIndex) => <li key={stepIndex}><strong>{step.title}:</strong> {prose(step.detail)}</li>)}</ol>}
          {depth.transferChallenge && <p><strong>Transfer challenge:</strong> {prose(depth.transferChallenge)}</p>}
          {depth.connections && depth.connections.length > 0 && <><h3>Connections</h3><ul>{depth.connections.map((connection, connectionIndex) => <li key={connectionIndex}><strong>{connection.title}:</strong> {connection.concept}</li>)}</ul></>}
        </section>}
        {algorithm?.expectedAnswer && <details><summary>Reveal the Algorithm Atlas answer</summary><p><code>{algorithm.expectedAnswer}</code></p></details>}
        {relatedReading}
        {patternNavigation}
        <nav className="lesson-list" aria-label="Lesson navigation">
          {index > 0 && <Link prefetch={false} className="lesson-link" href={`/learn/${course.id}/${lessons[index - 1].id}`}>← {lessons[index - 1].title}</Link>}
          {index + 1 < lessons.length && <Link prefetch={false} className="lesson-link" href={`/learn/${course.id}/${lessons[index + 1].id}`}>{lessons[index + 1].title} →</Link>}
        </nav>
      </article>
    </div>
  );
}
