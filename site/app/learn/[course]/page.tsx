import type { Metadata } from "next";
import { pageMetadata, pageUrl, breadcrumbs } from "@/lib/seo";
import { StructuredData } from "@/components/structured-data";
import Link from "next/link";
import { notFound } from "next/navigation";
import { courseById, courseLessons, courseSnapshot, lessonRef } from "@/lib/courses";
import { appSupportsBridgeCredits, bridgeAudience } from "@/lib/bridges";
import { CourseIcon } from "@/components/course-icon";
import { AlgorithmVisualizer } from "@/components/algorithm-visualizer";
import { publicAlgorithmDemo } from "@/lib/algorithm-traces";
import { courseDescription } from "@/lib/lesson-seo";
import { algorithmMethodGuides, algorithmGuideSources } from "@/lib/algorithm-method-guides";

export function generateStaticParams() {
  return courseSnapshot().courses.map((course) => ({ course: course.id }));
}

export async function generateMetadata({ params }: { params: Promise<{ course: string }> }): Promise<Metadata> {
  const course = courseById((await params).course);
  const audience = course && bridgeAudience(course.id);
  return course ? pageMetadata({ title: audience?.pageTitle ?? `${course.title} — Free Rust Lessons`, description: audience?.description ?? courseDescription(course), path: `/learn/${course.id}/` }) : {};
}

export default async function CoursePage({ params }: { params: Promise<{ course: string }> }) {
  const course = courseById((await params).course);
  if (!course) notFound();
  const audience = bridgeAudience(course.id);
  const creditRows = audience ? courseLessons(course).flatMap(lesson => {
    const covered = (lesson.bridge?.credits ?? []).flatMap(path => { const ref = lessonRef(path); return ref ? [ref] : []; });
    return covered.length ? [{ lesson, covered }] : [];
  }) : [];
  const creditCount = creditRows.reduce((sum, row) => sum + row.covered.length, 0);
  return (
    <div className="site-shell course-page">
      <StructuredData data={{ "@context": "https://schema.org", "@graph": [
        { "@type": "Course", name: course.title, description: course.subtitle,
          url: pageUrl(`/learn/${course.id}/`), inLanguage: "en", educationalLevel: course.level,
          provider: { "@type": "Organization", name: "Crabrix", url: pageUrl("/") },
          offers: { "@type": "Offer", price: "0", priceCurrency: "USD", category: "Free" },
          coursePrerequisites: audience?.prerequisites ?? "No account required. Read the complete lessons and try their examples for free.",
          ...(audience ? { audience: { "@type": "EducationalAudience", educationalRole: audience.audience },
            teaches: courseLessons(course).map(lesson => lesson.concept) } : {}),
        },
        breadcrumbs([{ name: "Crabrix", path: "/" }, { name: "Learn Rust", path: "/learn/" }, { name: course.title, path: `/learn/${course.id}/` }]),
      ] }} />
      <nav className="breadcrumbs" aria-label="Breadcrumbs"><Link prefetch={false} href="/learn">Learn</Link><span>/</span><span>{course.title}</span></nav>
      <div className="page-intro">
        <p className="eyebrow">Free course · {audience ? `for ${audience.audience}` : course.level}</p>
        <div className="academy-heading"><CourseIcon course={course.id} size={72} /><h1>{course.title}</h1></div>
        <p className="lede">{course.subtitle}</p>
        {audience && <p>{audience.intro}</p>}
        <p className="card-meta">{course.units.length} units · {courseLessons(course).length} lessons{audience ? ` · covers ${creditCount} Academy lessons` : ""} · complete lessons free without registration</p>
      </div>
      {course.id === "algorithms" && <>
        <section className="unit-panel" aria-labelledby="choose-method">
          <h2 id="choose-method">Choose an algorithm from the problem's constraints</h2>
          <p>Start with the operations, input guarantees and size limits. The method guides below explain what each family preserves, where it fails, and what to watch for in Rust. Each pattern has three separate steps: build a mental model, decide when it applies, then solve a challenge. The guides, complete examples, exercises and walkthroughs are public. No sign-in is needed.</p>
          <nav className="method-index" aria-label="Algorithm methods">{course.units.map(unit => <a key={unit.id} href={`#${unit.id}`}>{unit.title}</a>)}</nav>
        </section>
        <AlgorithmVisualizer trace={publicAlgorithmDemo()} demo />
        <p className="card-meta">Every pattern below includes a walkthrough of its actual Rust example: arrays, graphs, trees, call stacks and more. Explore all 200 patterns and their practice examples without registration.</p>
      </>}
      <div className="unit-list">
        {course.units.map((unit) => (
          <section className="unit-panel" key={unit.id} id={unit.id}>
            <h2>{unit.title}</h2>
            <p>{unit.subtitle}</p>
            {course.id === "algorithms" && algorithmMethodGuides[unit.id] && <div className="method-guide">
              <p>{algorithmMethodGuides[unit.id].choose}</p>
              <p><strong>Before you commit:</strong> {algorithmMethodGuides[unit.id].check}</p>
              <p><strong>In Rust:</strong> {algorithmMethodGuides[unit.id].rust}</p>
            </div>}
            <div className="lesson-list">
              {unit.lessons.map((lesson) => (
                <Link prefetch={false} className="lesson-link" key={lesson.id} href={`/learn/${course.id}/${lesson.id}`}>
                  <span>{lesson.title}</span><small>{lesson.minutes} min</small>
                </Link>
              ))}
            </div>
          </section>
        ))}
      </div>
      {creditRows.length > 0 && audience && <section className="unit-panel bridge-skip" aria-labelledby="skip-known">
        <h2 id="skip-known">Skip what you already know</h2>
        <p>Each lesson here teaches and checks the rule of the Academy lessons next to it. After this course, continue with the lessons it does not cover{appSupportsBridgeCredits ? <>; in the Crabrix app, finishing a lesson here marks the lessons it covers as known from {audience.language}</> : ""}.</p>
        <table className="bridge-contrasts"><thead><tr><th scope="col">This course</th><th scope="col">Academy lessons it covers</th></tr></thead>
          <tbody>{creditRows.map(row => <tr key={row.lesson.id}>
            <td><Link prefetch={false} href={`/learn/${course.id}/${row.lesson.id}`}>{row.lesson.title}</Link></td>
            <td>{row.covered.map((ref, refIndex) => <span key={`${ref.course.id}/${ref.lesson.id}`}>{refIndex > 0 && ", "}<Link prefetch={false} href={`/learn/${ref.course.id}/${ref.lesson.id}`}>{ref.lesson.title}</Link> <small>({ref.course.title})</small></span>)}</td>
          </tr>)}</tbody>
        </table>
      </section>}
      {course.id === "algorithms" && <aside className="lesson-reading method-sources" aria-label="Algorithm reference reading">
        <h2>Reference reading</h2><p>These original method guides connect the Atlas practice path to the standard library and algorithm design fundamentals.</p>
        <ul>{algorithmGuideSources.map(source => <li key={source.url}><a href={source.url}>{source.title} ↗</a></li>)}</ul>
        <p><Link prefetch={false} href="/learn/basics/collections/">Review Rust collections first →</Link> · <Link prefetch={false} href="/learn/interview/q-complexity/">Practice explaining complexity in an interview →</Link></p>
      </aside>}
    </div>
  );
}
