import { pageMetadata, pageUrl } from "@/lib/seo";
import { StructuredData } from "@/components/structured-data";
import Link from "next/link";
import { courseSnapshot, courseLessons, isBridgeCourse } from "@/lib/courses";
import { bridgeAudience } from "@/lib/bridges";
import { CourseIcon } from "@/components/course-icon";

export const metadata = pageMetadata({"title": `Learn Rust Free: ${courseSnapshot().lessonCount} Lessons and Algorithm Atlas Steps`, "description": "Start Rust Basics, ownership, Cargo and algorithms with clear examples and infographics. Read complete lessons, code and exercises without registration.", "path": "/learn/"});

export default function LearnPage() {
  const snapshot = courseSnapshot();
  const bridges = snapshot.courses.filter(isBridgeCourse);
  const academy = snapshot.courses.filter(course => !isBridgeCourse(course));
  return (
    <div className="site-shell">
      <StructuredData data={{ "@context": "https://schema.org", "@type": "ItemList",
        name: "Crabrix Rust courses", numberOfItems: snapshot.courses.length,
        itemListElement: snapshot.courses.map((course, index) => ({ "@type": "ListItem",
          position: index + 1, url: pageUrl(`/learn/${course.id}/`),
        })),
      }} />
      <div className="page-intro">
        <p className="eyebrow">The Crabrix Academy · free on the web</p>
        <h1>Learn Rust, one real idea at a time.</h1>
        <p className="lede">Read all {snapshot.rustLessonCount} guided Rust lessons and 600 Algorithm Atlas steps for free, with complete explanations, code and infographics. No registration required. The app adds offline reading, editable projects, local compilation, practice and progress.</p>
        <p className="card-meta">{snapshot.courseCount} courses · {snapshot.lessonCount} lessons and steps · same curriculum as the app · free without registration</p>
      </div>
      {bridges.length > 0 && <section className="bridge-entry" aria-labelledby="coming-from">
        <h2 id="coming-from">Already write C or Node.js? Start from what you know.</h2>
        <div className="catalog-grid">
          {bridges.map(course => (
            <Link prefetch={false} className="course-card bridge-card-link" href={`/learn/${course.id}`} key={course.id}>
              <span className="card-kicker">For {bridgeAudience(course.id)?.audience ?? course.level} · {courseLessons(course).length} side-by-side lessons</span>
              <div className="course-card-heading"><CourseIcon course={course.id} /><h3>{course.title}</h3></div>
              <p>{course.subtitle}</p>
              <span className="card-meta">See {bridgeAudience(course.id)?.language} and Rust side by side, then skip the Academy lessons you already know →</span>
            </Link>
          ))}
        </div>
      </section>}
      <div className="catalog-grid">
        {academy.map((course) => (
          <Link prefetch={false} className="course-card" href={`/learn/${course.id}`} key={course.id}>
            <span className="card-kicker">{course.level} · {course.units.length} units</span>
            <div className="course-card-heading"><CourseIcon course={course.id} /><h2>{course.title}</h2></div>
            <p>{course.subtitle}</p>
            <span className="card-meta">{courseLessons(course).length} lessons{course.id === "algorithms" ? " · step-by-step visuals" : ""} →</span>
          </Link>
        ))}
      </div>
    </div>
  );
}
