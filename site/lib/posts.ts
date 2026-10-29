import postData from "@/content/posts.json";

export type PostImage = {
  src: string;
  alt: string;
  caption: string;
  width?: number;
  height?: number;
};

export type Post = {
  slug: string;
  title: string;
  date: string;
  readingMinutes: number;
  summary: string;
  relatedSlugs?: string[];
  sections: {
    heading: string;
    paragraphs: string[];
    code?: string;
    codeLanguage?: string;
    image?: PostImage;
    sources?: { title: string; url: string }[];
    links?: { title: string; url: string }[];
  }[];
};

export const posts: Post[] = postData;

export function postWordCount(post: Post): number {
  return post.sections.flatMap((section) => section.paragraphs).join(" ").trim().split(/\s+/).length;
}

export function postBySlug(slug: string): Post | undefined {
  return posts.find((post) => post.slug === slug);
}
