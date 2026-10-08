import type { Metadata } from "next";
import Link from "next/link";
import { posts } from "@/lib/posts";

export const metadata: Metadata = {
  title: "Blog",
  description: "Notes about building Crabrix, running Rust locally on iPhone and learning by making real projects.",
};

export default function BlogPage() {
  return (
    <div className="site-shell">
      <div className="page-intro">
        <p className="eyebrow">Crabrix blog</p>
        <h1>Notes from the workspace.</h1>
        <p className="lede">How the app works, what it can do today, and ways to turn a lesson into your own Rust project.</p>
      </div>
      <div className="post-grid">
        {posts.map((post) => (
          <Link className="post-card" href={`/blog/${post.slug}`} key={post.slug}>
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
