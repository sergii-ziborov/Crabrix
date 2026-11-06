import { pageMetadata, pageUrl } from "@/lib/seo";
import { StructuredData } from "@/components/structured-data";
import Link from "next/link";
import { courseSnapshot, courseLessons } from "@/lib/courses";
import { CourseIcon } from "@/components/course-icon";

export const metadata = pageMetadata({"title": `Learn Rust Free: ${courseSnapshot().lessonCount} Lessons and Algorithm Atlas Steps`, "description": "Start Rust Basics, ownership, Cargo and algorithms with clear examples and infographics. Read complete lessons, code and exercises without registration.", "path": "/learn/"});

export default function LearnPage() {
  const snapshot = courseSnapshot();
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
      <div className="catalog-grid">
        {snapshot.courses.map((course) => (
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
