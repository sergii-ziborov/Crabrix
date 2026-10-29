import type { MetadataRoute } from "next";
import { courseSnapshot } from "@/lib/courses";
import { pageUrl } from "@/lib/seo";
import { posts } from "@/lib/posts";
import { BLOG_PAGE_SIZE, blogPagePath } from "@/lib/blog-pagination";
import { lessonModifiedDates, courseModifiedDates } from "@/lib/lesson-seo";

export const dynamic = "force-static";

export default function sitemap(): MetadataRoute.Sitemap {
  const paths = ["", "about", "technology", "support", "privacy", "terms", "licenses", "learn", "blog", "guide", "playground", "playground/mcp", "sitemap"];
  const courseEntries = courseSnapshot().courses.flatMap((course) => [
    { url: pageUrl(`learn/${course.id}`), ...(courseModifiedDates[course.id] ? { lastModified: courseModifiedDates[course.id] } : {}) },
    ...course.units.flatMap((unit) => unit.lessons.map((lesson) => ({
      url: pageUrl(`learn/${course.id}/${lesson.id}`),
      ...(lessonModifiedDates[`${course.id}/${lesson.id}`] ? { lastModified: lessonModifiedDates[`${course.id}/${lesson.id}`] } : {}),
    }))),
  ]);
  const pageModifiedDates: Record<string, string> = {
    "playground/mcp": "2026-10-29", learn: "2026-10-29",
    playground: "2026-10-29", guide: "2026-10-29", blog: "2026-10-29", technology: "2026-10-27", privacy: "2026-10-27", licenses: "2026-10-27",
  };
  return [...paths.map((path) => ({ url: pageUrl(path),
    ...(pageModifiedDates[path] ? { lastModified: pageModifiedDates[path] } : {}),
  })), ...Array.from({ length: Math.max(0, Math.ceil(posts.length / BLOG_PAGE_SIZE) - 1) }, (_, index) => ({ url: pageUrl(blogPagePath(index + 2)) })), ...courseEntries,
    ...posts.map((post) => ({ url: pageUrl(`blog/${post.slug}`), lastModified: post.modifiedDate ?? post.date,
      images: post.sections.flatMap((section) => section.image ? [new URL(section.image.src, pageUrl("/")).href] : []),
    })),
  ];
}
