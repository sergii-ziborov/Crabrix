import { pageMetadata, pageUrl } from "@/lib/seo";
import { StructuredData } from "@/components/structured-data";
import { BlogImage } from "@/components/blog-image";
import Link from "next/link";
import { posts } from "@/lib/posts";

export const metadata = pageMetadata({"title": "Practical Rust Guides: Iterators, UTF-8, Testing and Cargo", "description": "Learn Rust with practical guides to iterators, UTF-8 strings, testing, Cargo features, enums and releases. Runnable code, original diagrams and official sources.", "path": "/blog/"});

export default function BlogPage() {
  return (
    <div className="site-shell">
      <StructuredData data={{ "@context": "https://schema.org", "@type": "ItemList",
        name: "Crabrix practical Rust guides", numberOfItems: posts.length,
        itemListElement: posts.map((post, index) => ({ "@type": "ListItem", position: index + 1,
          url: pageUrl(`/blog/${post.slug}/`), name: post.title })) }} />
      <div className="page-intro">
        <p className="eyebrow">Crabrix blog</p>
        <h1>Rust you can put to work.</h1>
        <p className="lede">Practical guides to Rust iterators, text, testing, Cargo features and state machines, alongside release notes and ownership fundamentals.</p>
      </div>
      <div className="post-grid">
        {posts.map((post, index) => {
          const image = post.sections.find((section) => section.image)?.image;
          return (
            <Link className="post-card" href={`/blog/${post.slug}`} key={post.slug}>
              {image && <BlogImage image={image} decorative card priority={index === 0} />}
              <span className="card-kicker"><time dateTime={post.date}>{post.date}</time> · {post.readingMinutes} min read</span>
              <h2>{post.title}</h2>
              <p>{post.summary}</p>
              <span className="card-meta">Read article →</span>
            </Link>
          );
        })}
      </div>
    </div>
  );
}
