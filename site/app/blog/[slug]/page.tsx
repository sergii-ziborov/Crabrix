import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { postBySlug, posts } from "@/lib/posts";
import { SyntaxCode } from "@/components/SyntaxCode";

function prose(text: string) {
  return text.split(/(`[^`]+`)/g).map((part, index) => part.startsWith("`") && part.endsWith("`") ? <code key={index}>{part.slice(1, -1)}</code> : part);
}

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
  const sectionId = (heading: string) => heading.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
  return (
    <div className="site-shell article-page">
      <nav className="breadcrumbs" aria-label="Breadcrumbs"><Link href="/blog">Blog</Link><span>/</span><span>{post.title}</span></nav>
      <div className="page-intro article-content">
        <p className="eyebrow">Crabrix blog</p>
        <h1>{post.title}</h1>
        <p className="lede">{post.summary}</p>
        <p className="article-date">{post.date} · {post.readingMinutes} min read</p>
        <nav className="article-toc" aria-label="Article contents">
          <strong>In this article</strong>
          <ol>{post.sections.map((section) => <li key={section.heading}><a href={`#${sectionId(section.heading)}`}>{section.heading}</a></li>)}</ol>
        </nav>
      </div>
      <article className="article-content">
        {post.sections.map((section) => <section key={section.heading} id={sectionId(section.heading)}>
          <h2>{section.heading}</h2>
          {section.paragraphs.map((paragraph) => <p key={paragraph}>{prose(paragraph)}</p>)}
          {section.code && (section.codeLanguage === "shell" ? <pre><code>{section.code}</code></pre> : <SyntaxCode code={section.code} />)}
          {section.image && <figure className="article-image">
            <img src={section.image.src} alt={section.image.alt} loading="lazy" />
            <figcaption>{section.image.caption}</figcaption>
          </figure>}
          {section.sources && <p className="article-sources">Sources: {section.sources.map((source, index) => <span key={source.url}>{index > 0 && " · "}<a href={source.url}>{source.title}</a></span>)}</p>}
        </section>)}
        <p><Link href="/learn">Explore the free Crabrix lessons →</Link></p>
      </article>
    </div>
  );
}
