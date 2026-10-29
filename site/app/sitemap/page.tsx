import Link from "next/link";
import { pageMetadata } from "@/lib/seo";
import { courseSnapshot } from "@/lib/courses";
import { posts } from "@/lib/posts";

export const metadata = pageMetadata({ title: "Sitemap: All Rust Lessons and Articles", description: "Find every Crabrix course, all 754 Rust and algorithm lessons, and practical Rust blog guides. Public lesson previews; complete Academy free with an account.", path: "/sitemap/" });

export default function SitemapPage() {
  return <div className="site-shell">
    <div className="page-intro"><p className="eyebrow">Explore Crabrix</p><h1>Every lesson and Rust guide.</h1>
      <p className="lede">Browse 754 lesson previews, seven courses and {posts.length} practical articles. A free account opens complete Academy lessons.</p>
      <p><a href="/sitemap.xml">XML sitemap for search engines</a></p>
    </div>
    <section className="unit-panel"><h2><Link href="/guide/">Crabrix user guide</Link></h2><p>Screenshot walkthroughs for projects, offline packages, Check and Run, the terminal, device layouts and compiler boundaries.</p></section>
    <section className="unit-panel"><h2><Link href="/playground/mcp/">Crabrix Playground MCP</Link></h2><p>Download the Claude bridge, connect a temporary room and see AI edits and selections in Crabrix on your device.</p></section>
    <section className="unit-panel"><h2>Rust blog</h2><ul>{posts.map((post) => <li key={post.slug}><Link href={`/blog/${post.slug}/`}>{post.title}</Link> <time dateTime={post.date}>{post.date}</time></li>)}</ul></section>
    {courseSnapshot().courses.map((course) => <section className="unit-panel" key={course.id}>
      <h2><Link href={`/learn/${course.id}/`}>{course.title}</Link></h2>
      {course.units.map((unit) => <div key={unit.id}><h3>{unit.title}</h3><ul>
        {unit.lessons.map((lesson) => <li key={lesson.id}><Link href={`/learn/${course.id}/${lesson.id}/`}>{lesson.title}</Link></li>)}
      </ul></div>)}
    </section>)}
  </div>;
}
