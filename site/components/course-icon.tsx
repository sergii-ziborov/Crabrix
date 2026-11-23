const courseIDs = new Set(["basics", "algorithms", "ownership", "projects", "concurrency", "systems", "interview"]);

/** The original course artwork from the native Crabrix asset catalog. */
const bridgeBadges: Record<string, string> = { "rust-for-c-developers": "C", "rust-for-nodejs-developers": "JS" };

export function CourseIcon({ course, size = 56 }: { course: string; size?: number }) {
  if (bridgeBadges[course]) {
    return <span className="course-icon bridge-badge" style={{ width: size, height: size }} aria-hidden="true">
      <b style={{ fontSize: size * 0.38 }}>{bridgeBadges[course]}</b><small style={{ fontSize: Math.max(10, size * 0.17) }}>→ Rust</small>
    </span>;
  }
  if (!courseIDs.has(course)) return null;
  return <img className="course-icon" src={`/course-icons/${course}.webp`} width={size} height={size} alt="" decoding="async" />;
}
