import { notFound, permanentRedirect } from "next/navigation";
import { BlogArchive, blogArchiveMetadata } from "@/components/blog-archive";
import { BLOG_PAGE_SIZE, blogPage, parseBlogPage } from "@/lib/blog-pagination";
import { posts } from "@/lib/posts";

type Props = { params: Promise<{ page: string }> };

function archivePage(value: string): number {
  const page = parseBlogPage(value);
  if (!page || !blogPage(posts, page)) notFound();
  if (page === 1) permanentRedirect("/blog/");
  return page;
}

export function generateStaticParams() {
  return Array.from({ length: Math.max(0, Math.ceil(posts.length / BLOG_PAGE_SIZE) - 1) }, (_, index) => ({ page: String(index + 2) }));
}

export async function generateMetadata({ params }: Props) {
  return blogArchiveMetadata(archivePage((await params).page));
}

export default async function BlogArchivePage({ params }: Props) {
  return <BlogArchive page={archivePage((await params).page)} />;
}
