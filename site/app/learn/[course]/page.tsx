import type { Metadata } from "next";
import { pageMetadata, pageUrl, breadcrumbs } from "@/lib/seo";
import { StructuredData } from "@/components/structured-data";
import Link from "next/link";
import { notFound } from "next/navigation";
import { courseById, courseLessons, courseSnapshot } from "@/lib/courses";
import { CourseIcon } from "@/components/course-icon";
import { AlgorithmVisualizer } from "@/components/algorithm-visualizer";
import { publicAlgorithmDemo } from "@/lib/algorithm-traces";
import { courseDescription } from "@/lib/lesson-seo";

export function generateStaticParams() {
  return courseSnapshot().courses.map((course) => ({ course: course.id }));
}

export async function generateMetadata({ params }: { params: Promise<{ course: string }> }): Promise<Metadata> {
  const course = courseById((await params).course);
  return course ? pageMetadata({ title: `${course.title} — Free Rust Lessons`, description: courseDescription(course), path: `/learn/${course.id}/` }) : {};
}

export default async function CoursePage({ params }: { params: Promise<{ course: string }> }) {
  const course = courseById((await params).course);
  if (!course) notFound();
  return (
    <div className="site-shell course-page">
      <StructuredData data={{ "@context": "https://schema.org", "@graph": [
        { "@type": "Course", name: course.title, description: course.subtitle,
          url: pageUrl(`/learn/${course.id}/`), inLanguage: "en", educationalLevel: course.level,
          provider: { "@type": "Organization", name: "Crabrix", url: pageUrl("/") },
          offers: { "@type": "Offer", price: "0", priceCurrency: "USD", category: "Free" },
          coursePrerequisites: "A free Academy account to read complete lessons; previews are public.",
        },
        breadcrumbs([{ name: "Crabrix", path: "/" }, { name: "Learn Rust", path: "/learn/" }, { name: course.title, path: `/learn/${course.id}/` }]),
      ] }} />
      <nav className="breadcrumbs" aria-label="Breadcrumbs"><Link href="/learn">Learn</Link><span>/</span><span>{course.title}</span></nav>
      <div className="page-intro">
        <p className="eyebrow">Free course · {course.level}</p>
        <div className="academy-heading"><CourseIcon course={course.id} size={72} /><h1>{course.title}</h1></div>
        <p className="lede">{course.subtitle}</p>
        <p className="card-meta">{course.units.length} units · {courseLessons(course).length} lessons · complete lessons free with an account</p>
      </div>
      {course.id === "algorithms" && <>
        <AlgorithmVisualizer trace={publicAlgorithmDemo()} demo />
        <p className="card-meta">Every pattern below includes a walkthrough of its actual Rust example: arrays, graphs, trees, call stacks and more. Sign in to explore all 200 patterns and their practice examples.</p>
      </>}
      <div className="unit-list">
        {course.units.map((unit) => (
          <section className="unit-panel" key={unit.id} id={unit.id}>
            <h2>{unit.title}</h2>
            <p>{unit.subtitle}</p>
            <div className="lesson-list">
              {unit.lessons.map((lesson) => (
                <Link className="lesson-link" key={lesson.id} href={`/learn/${course.id}/${lesson.id}`}>
                  <span>{lesson.title}</span><small>{lesson.minutes} min</small>
                </Link>
              ))}
            </div>
          </section>
        ))}
      </div>
    </div>
  );
}
