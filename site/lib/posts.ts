import postData from "@/content/posts.json";

export type PostImage = {
  src: string;
  alt: string;
  caption: string;
};

export type Post = {
  slug: string;
  title: string;
  date: string;
  readingMinutes: number;
  summary: string;
  sections: {
    heading: string;
    paragraphs: string[];
    code?: string;
    codeLanguage?: string;
    image?: PostImage;
    sources?: { title: string; url: string }[];
  }[];
};

export const posts: Post[] = postData;

export function postBySlug(slug: string): Post | undefined {
  return posts.find((post) => post.slug === slug);
}
