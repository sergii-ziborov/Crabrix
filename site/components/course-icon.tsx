const courseIDs = new Set(["basics", "algorithms", "ownership", "projects", "concurrency", "systems", "interview"]);

/** The original course artwork from the native Crabrix asset catalog. */
export function CourseIcon({ course, size = 56 }: { course: string; size?: number }) {
  if (!courseIDs.has(course)) return null;
  return <img className="course-icon" src={`/course-icons/${course}.webp`} width={size} height={size} alt="" decoding="async" />;
}
