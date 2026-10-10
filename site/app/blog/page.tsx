import type { Metadata } from "next";
import Link from "next/link";
import { posts } from "@/lib/posts";

export const metadata: Metadata = {
  title: "Blog",
  description: "Practical Rust guides, release upgrades, ownership, error handling and notes from the Crabrix workspace.",
};

export default function BlogPage() {
  return (
    <div className="site-shell">
      <div className="page-intro">
        <p className="eyebrow">Crabrix blog</p>
        <h1>Rust you can put to work.</h1>
        <p className="lede">Release guides, practical examples, and careful explanations from the Crabrix workspace.</p>
      </div>
      <div className="post-grid">
        {posts.map((post) => (
          <Link className="post-card" href={`/blog/${post.slug}`} key={post.slug}>
            {post.sections.find((section) => section.image)?.image && <img className="post-cover" src={post.sections.find((section) => section.image)!.image!.src} alt="" loading="lazy" />}
            <span className="card-kicker">{post.date} · {post.readingMinutes} min read</span>
            <h2>{post.title}</h2>
            <p>{post.summary}</p>
            <span className="card-meta">Read article →</span>
          </Link>
        ))}
      </div>
    </div>
  );
}
