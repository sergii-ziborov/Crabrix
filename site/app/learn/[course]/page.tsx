import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { courseById, courseLessons, courseSnapshot } from "@/lib/courses";

export function generateStaticParams() {
  return courseSnapshot().courses.map((course) => ({ course: course.id }));
}

export async function generateMetadata({ params }: { params: Promise<{ course: string }> }): Promise<Metadata> {
  const course = courseById((await params).course);
  return course ? { title: `${course.title} — free lessons`, description: course.subtitle } : {};
}

export default async function CoursePage({ params }: { params: Promise<{ course: string }> }) {
  const course = courseById((await params).course);
  if (!course) notFound();
  return (
    <div className="site-shell course-page">
      <nav className="breadcrumbs" aria-label="Breadcrumbs"><Link href="/learn">Learn</Link><span>/</span><span>{course.title}</span></nav>
      <div className="page-intro">
        <p className="eyebrow">Free course · {course.level}</p>
        <h1>{course.title}</h1>
        <p className="lede">{course.subtitle}</p>
        <p className="card-meta">{course.units.length} units · {courseLessons(course).length} lessons · every lesson is open</p>
      </div>
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
