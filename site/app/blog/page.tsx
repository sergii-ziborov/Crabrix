import { BlogArchive, blogArchiveMetadata } from "@/components/blog-archive";

export const metadata = blogArchiveMetadata(1);

export default function BlogPage() {
  return <BlogArchive page={1} />;
}
