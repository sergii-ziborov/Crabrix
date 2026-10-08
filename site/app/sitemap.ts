import type { MetadataRoute } from "next";
import { courseSnapshot } from "@/lib/courses";
import { posts } from "@/lib/posts";

export const dynamic = "force-static";

export default function sitemap(): MetadataRoute.Sitemap {
  const paths = ["", "about", "technology", "support", "privacy", "terms", "learn", "blog"];
  const coursePaths = courseSnapshot().courses.flatMap((course) => [
    `learn/${course.id}`,
    ...course.units.flatMap((unit) => unit.lessons.map((lesson) => `learn/${course.id}/${lesson.id}`)),
  ]);
  return [...paths, ...coursePaths, ...posts.map((post) => `blog/${post.slug}`)]
    .map((path) => ({ url: `https://crabrix.com/${path}` }));
}
