import Link from "next/link";
import { pageMetadata, pageUrl, siteOrigin } from "@/lib/seo";
import { aiLearningEnabled } from "@/lib/flags";
import { courseSnapshot } from "@/lib/courses";
import { posts } from "@/lib/posts";

export const metadata = pageMetadata({ title: "Sitemap: All Rust Lessons and Articles", description: `Find every Crabrix course, all ${courseSnapshot().lessonCount} Rust and algorithm lessons, and practical Rust blog guides. Complete explanations, code and exercises, free without registration.`, path: "/sitemap/" });

/** The canonical path: Atlas lesson IDs end without a slash (see pageUrl). */
const pagePath = (path: string) => pageUrl(path).slice(siteOrigin.length);

export default function SitemapPage() {
  return <div className="site-shell">
    <div className="page-intro"><p className="eyebrow">Explore Crabrix</p><h1>Every lesson and Rust guide.</h1>
      <p className="lede">Browse {courseSnapshot().lessonCount} complete lessons and steps, {courseSnapshot().courses.length} courses and {posts.length} practical articles. Read the complete Academy without an account.</p>
      <p><a href="/sitemap.xml">XML sitemap for search engines</a></p>
    </div>
    <section className="unit-panel"><h2><Link prefetch={false} href="/guide/">Crabrix user guide</Link></h2><p>Screenshot walkthroughs for projects, offline packages, Check and Run, the terminal, device layouts and compiler boundaries.</p></section>
    {aiLearningEnabled() && <section className="unit-panel"><h2><Link prefetch={false} href="/learn/with-ai/">Learn Rust with your AI agent</Link></h2><p>Connect Claude, Claude Code, Codex or Cursor to Crabrix Academy, and with the Crabrix app let your agent see your progress and send you lessons.</p></section>}
    <section className="unit-panel"><h2><Link prefetch={false} href="/ai/">Connect AI to Crabrix</Link></h2><p>Set up Crabrix MCP or the SDK, connect a temporary room and see AI edits and selections in Crabrix on your device.</p></section>
    <section className="unit-panel"><h2><Link prefetch={false} href="/blog/">Rust blog</Link></h2><ul>{posts.map((post) => <li key={post.slug}><Link prefetch={false} href={`/blog/${post.slug}/`}>{post.title}</Link> <time dateTime={post.date}>{post.date}</time></li>)}</ul></section>
    {courseSnapshot().courses.map((course) => <section className="unit-panel" key={course.id}>
      <h2><Link prefetch={false} href={`/learn/${course.id}/`}>{course.title}</Link></h2>
      {course.units.map((unit) => <div key={unit.id}><h3>{unit.title}</h3><ul>
        {unit.lessons.map((lesson) => <li key={lesson.id}><Link prefetch={false} href={pagePath(`/learn/${course.id}/${lesson.id}`)}>{lesson.title}</Link></li>)}
      </ul></div>)}
    </section>)}
  </div>;
}
