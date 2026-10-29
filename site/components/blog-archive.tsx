import Link from "next/link";
import { notFound } from "next/navigation";
import { BlogImage } from "@/components/blog-image";
import { StructuredData } from "@/components/structured-data";
import { blogPage, blogPagePath } from "@/lib/blog-pagination";
import { posts } from "@/lib/posts";
import { breadcrumbs, pageMetadata, pageUrl } from "@/lib/seo";

export function blogArchiveMetadata(page: number) {
  const archive = blogPage(posts, page);
  if (!archive) notFound();
  return pageMetadata({
    title: page === 1 ? "Rust Guides and News: Cargo, Memoization and Releases" : `Rust Guides and News — Page ${page}`,
    description: page === 1
      ? "Practical Rust guides and verified release news. Learn Cargo builds, memoization, ownership, testing and portability with runnable examples and original diagrams."
      : `Page ${page} of the Crabrix Rust blog. Browse articles ${archive.start}–${archive.end} of ${archive.total}: practical Rust guides, runnable examples and carefully sourced release news.`,
    path: blogPagePath(page),
  });
}

export function BlogArchive({ page }: { page: number }) {
  const archive = blogPage(posts, page);
  if (!archive) notFound();
  const pageNumbers = Array.from({ length: archive.pageCount }, (_, index) => index + 1);
  return <div className="site-shell blog-archive">
    <StructuredData data={{ "@context": "https://schema.org", "@graph": [
      { "@type": "ItemList", name: "Crabrix practical Rust guides", url: pageUrl(blogPagePath(page)),
        numberOfItems: archive.total,
        itemListElement: archive.posts.map((post, index) => ({ "@type": "ListItem", position: archive.start + index,
          url: pageUrl(`/blog/${post.slug}/`), name: post.title })) },
      breadcrumbs([{ name: "Crabrix", path: "/" }, { name: "Rust Blog", path: "/blog/" },
        ...(page > 1 ? [{ name: `Page ${page}`, path: blogPagePath(page) }] : [])]),
    ] }} />
    <div className="page-intro">
      <p className="eyebrow">Crabrix blog{page > 1 ? ` · Page ${page} of ${archive.pageCount}` : ""}</p>
      <h1>{page === 1 ? "Rust you can put to work." : `Rust guides and news: page ${page}.`}</h1>
      <p className="lede">Practical guides to Cargo builds, memoization, ownership, text and testing, alongside carefully sourced Rust release and infrastructure news.</p>
      <p className="blog-archive-count">Articles {archive.start}–{archive.end} of {archive.total} · Newest first</p>
    </div>
    <div className="post-grid">
      {archive.posts.map((post, index) => {
        const image = post.sections.find((section) => section.image)?.image;
        return <Link className="post-card" href={`/blog/${post.slug}/`} key={post.slug}>
          {image && <BlogImage image={image} decorative card priority={index === 0} />}
          <span className="card-kicker"><time dateTime={post.date}>{post.date}</time> · {post.readingMinutes} min read</span>
          <h2>{post.title}</h2>
          <p>{post.summary}</p>
          <span className="card-meta">Read article →</span>
        </Link>;
      })}
    </div>
    {archive.pageCount > 1 && <nav className="blog-pagination" aria-label="Blog pages">
      {page > 1
        ? <Link className="blog-page-direction blog-page-previous" href={blogPagePath(page - 1)} rel="prev">← Previous</Link>
        : <span className="blog-page-direction blog-page-previous" aria-disabled="true">← Previous</span>}
      <ol>{pageNumbers.map((number) => <li key={number}>
        <Link href={blogPagePath(number)} aria-label={`Page ${number}`} aria-current={number === page ? "page" : undefined}>{number}</Link>
      </li>)}</ol>
      {page < archive.pageCount
        ? <Link className="blog-page-direction blog-page-next" href={blogPagePath(page + 1)} rel="next">Next →</Link>
        : <span className="blog-page-direction blog-page-next" aria-disabled="true">Next →</span>}
    </nav>}
  </div>;
}
