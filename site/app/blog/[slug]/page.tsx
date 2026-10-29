import type { Metadata } from "next";
import { pageMetadata, pageUrl, breadcrumbs } from "@/lib/seo";
import { StructuredData } from "@/components/structured-data";
import Link from "next/link";
import { notFound } from "next/navigation";
import { postBySlug, posts, postWordCount } from "@/lib/posts";
import { SyntaxCode } from "@/components/SyntaxCode";
import { BlogImage } from "@/components/blog-image";

function prose(text: string) {
  return text.split(/(`[^`]+`)/g).map((part, index) => part.startsWith("`") && part.endsWith("`") ? <code key={index}>{part.slice(1, -1)}</code> : part);
}

export function generateStaticParams() {
  return posts.map((post) => ({ slug: post.slug }));
}

export async function generateMetadata({ params }: { params: Promise<{ slug: string }> }): Promise<Metadata> {
  const post = postBySlug((await params).slug);
  const image = post?.sections.find((section) => section.image)?.image;
  return post ? pageMetadata({ title: post.title, description: post.summary,
    path: `/blog/${post.slug}/`, image: image?.src, imageAlt: image?.alt, articleDate: post.date }) : {};
}

export default async function ArticlePage({ params }: { params: Promise<{ slug: string }> }) {
  const post = postBySlug((await params).slug);
  if (!post) notFound();
  const cover = post.sections.find((section) => section.image)?.image;
  const related = (post.relatedSlugs ?? []).flatMap((slug) => {
    const article = postBySlug(slug);
    return article ? [article] : [];
  });
  const sectionId = (heading: string) => heading.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
  return (
    <div className="site-shell article-page">
      <StructuredData data={{ "@context": "https://schema.org", "@graph": [
        { "@type": "BlogPosting", headline: post.title, description: post.summary,
          mainEntityOfPage: pageUrl(`/blog/${post.slug}/`), datePublished: post.date,
          author: { "@type": "Person", name: "Serhii Ziborov", url: pageUrl("/about/") },
          publisher: { "@type": "Organization", name: "Crabrix", url: pageUrl("/") },
          image: post.sections.flatMap((section) => section.image ? [new URL(section.image.src, pageUrl("/")).href] : []),
          inLanguage: "en", isAccessibleForFree: true, wordCount: postWordCount(post),
        },
        breadcrumbs([{ name: "Crabrix", path: "/" }, { name: "Rust Blog", path: "/blog/" }, { name: post.title, path: `/blog/${post.slug}/` }]),
      ] }} />
      <nav className="breadcrumbs" aria-label="Breadcrumbs"><Link href="/blog">Blog</Link><span>/</span><span>{post.title}</span></nav>
      <div className="page-intro article-content">
        <p className="eyebrow">Crabrix blog</p>
        <h1>{post.title}</h1>
        <p className="lede">{post.summary}</p>
        <p className="article-date"><time dateTime={post.date}>{post.date}</time> · {post.readingMinutes} min read</p>
        <nav className="article-toc" aria-label="Article contents">
          <strong>In this article</strong>
          <ol>{post.sections.map((section) => <li key={section.heading}><a href={`#${sectionId(section.heading)}`}>{section.heading}</a></li>)}</ol>
        </nav>
      </div>
      <article className="article-content">
        {post.sections.map((section) => <section key={section.heading} id={sectionId(section.heading)}>
          <h2>{section.heading}</h2>
          {section.paragraphs.map((paragraph) => <p key={paragraph}>{prose(paragraph)}</p>)}
          {section.code && (section.codeLanguage && section.codeLanguage !== "rust" ? <pre><code className={`language-${section.codeLanguage}`}>{section.code}</code></pre> : <SyntaxCode code={section.code} />)}
          {section.image && <figure className="article-image">
            <BlogImage image={section.image} priority={section.image === cover} />
            <figcaption>{section.image.caption}</figcaption>
          </figure>}
          {section.sources && <p className="article-sources">Sources: {section.sources.map((source, index) => <span key={source.url}>{index > 0 && " · "}<a href={source.url}>{source.title}</a></span>)}</p>}
          {section.links && <p className="article-sources">Explore in Crabrix: {section.links.map((link, index) => <span key={link.url}>{index > 0 && " · "}<Link href={link.url}>{link.title}</Link></span>)}</p>}
        </section>)}
        <p><Link href="/learn">Explore the free Crabrix lessons →</Link></p>
        {related.length > 0 && <aside className="article-related" aria-label="Related Rust guides">
          <h2>Continue with a related Rust guide</h2>
          <ul>{related.map((article) => <li key={article.slug}><Link href={`/blog/${article.slug}/`}>{article.title}</Link></li>)}</ul>
        </aside>}
      </article>
    </div>
  );
}
