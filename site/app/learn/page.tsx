import { pageMetadata } from "@/lib/seo";
import Link from "next/link";
import { courseSnapshot, courseLessons } from "@/lib/courses";

export const metadata = pageMetadata({"title": "Learn Rust Free: 742 Lessons and Algorithm Atlas Steps", "description": "Start Rust Basics, ownership, Cargo and algorithms with clear examples and infographics. Preview any lesson; a free account opens the complete Academy.", "path": "/learn/"});

export default function LearnPage() {
  const snapshot = courseSnapshot();
  return (
    <div className="site-shell">
      <div className="page-intro">
        <p className="eyebrow">The Crabrix Academy · free on the web</p>
        <h1>Learn Rust, one real idea at a time.</h1>
        <p className="lede">Explore the beginning of any lesson. A free account opens all {snapshot.rustLessonCount} guided Rust lessons and 600 Algorithm Atlas steps, with explanations, code and infographics. The app adds offline reading, editable projects, local compilation, practice and progress.</p>
        <p className="card-meta">{snapshot.courseCount} courses · {snapshot.lessonCount} lessons and steps · same curriculum as the app · free with an account</p>
      </div>
      <div className="catalog-grid">
        {snapshot.courses.map((course) => (
          <Link className="course-card" href={`/learn/${course.id}`} key={course.id}>
            <span className="card-kicker">{course.level} · {course.units.length} units</span>
            <h2>{course.title}</h2>
            <p>{course.subtitle}</p>
            <span className="card-meta">{courseLessons(course).length} lessons →</span>
          </Link>
        ))}
      </div>
    </div>
  );
}
