import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { postBySlug, posts } from "@/lib/posts";

export function generateStaticParams() {
  return posts.map((post) => ({ slug: post.slug }));
}

export async function generateMetadata({ params }: { params: Promise<{ slug: string }> }): Promise<Metadata> {
  const post = postBySlug((await params).slug);
  return post ? { title: post.title, description: post.summary } : {};
}

export default async function ArticlePage({ params }: { params: Promise<{ slug: string }> }) {
  const post = postBySlug((await params).slug);
  if (!post) notFound();
  return (
    <div className="site-shell article-page">
      <nav className="breadcrumbs" aria-label="Breadcrumbs"><Link href="/blog">Blog</Link><span>/</span><span>{post.title}</span></nav>
      <div className="page-intro article-content">
        <p className="eyebrow">Crabrix blog</p>
        <h1>{post.title}</h1>
        <p className="lede">{post.summary}</p>
        <p className="article-date">{post.date} · {post.readingMinutes} min read</p>
      </div>
      <article className="article-content">
        {post.sections.map((section) => <section key={section.heading}>
          <h2>{section.heading}</h2>
          {section.paragraphs.map((paragraph) => <p key={paragraph}>{paragraph}</p>)}
          {section.code && <pre><code>{section.code}</code></pre>}
        </section>)}
        <p><Link href="/learn">Explore the free Crabrix lessons →</Link></p>
      </article>
    </div>
  );
}
