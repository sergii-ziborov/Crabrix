import type { MetadataRoute } from "next";
import { courseSnapshot } from "@/lib/courses";
import { pageUrl } from "@/lib/seo";
import { posts } from "@/lib/posts";
import { BLOG_PAGE_SIZE, blogPage, blogPagePath } from "@/lib/blog-pagination";
import { lessonPageModifiedDate, courseModifiedDates } from "@/lib/lesson-seo";
import { postModificationDate } from '@/lib/post-dates';

// The route cache survives container replacement; read this release's corpus
// on request so a previous release cannot keep new lessons out of the sitemap.
export const dynamic = "force-dynamic";

export default function sitemap(): MetadataRoute.Sitemap {
  const paths = ["", "about", "technology", "support", "privacy", "terms", "licenses", "learn", "blog", "guide", "playground", "ai", "sitemap"];
  const courseEntries = courseSnapshot().courses.flatMap((course) => [
    { url: pageUrl(`learn/${course.id}`), ...(courseModifiedDates[course.id] ? { lastModified: courseModifiedDates[course.id] } : {}) },
    ...course.units.flatMap((unit) => unit.lessons.map((lesson) => ({
      url: pageUrl(`learn/${course.id}/${lesson.id}`),
      ...(lessonPageModifiedDate(course.id, lesson.id) ? { lastModified: lessonPageModifiedDate(course.id, lesson.id) } : {}),
    }))),
  ]);
  const pageModifiedDates: Record<string, string> = {
    "": "2026-11-05", about: "2026-11-05", ai: "2026-11-05", learn: "2026-11-06",
    playground: "2026-11-05", guide: "2026-11-06", technology: "2026-11-05", privacy: "2026-11-06", terms: "2026-11-06", licenses: "2026-11-06",
  };
  const archiveModified = (page: number) => blogPage(posts, page)?.posts.map(postModificationDate).sort().at(-1);
  const firstArchiveModified = archiveModified(1);
  if (firstArchiveModified) pageModifiedDates.blog = firstArchiveModified;
  return [...paths.map((path) => ({ url: pageUrl(path),
    ...(pageModifiedDates[path] ? { lastModified: pageModifiedDates[path] } : {}),
  })), ...Array.from({ length: Math.max(0, Math.ceil(posts.length / BLOG_PAGE_SIZE) - 1) }, (_, index) => ({ url: pageUrl(blogPagePath(index + 2)), lastModified: archiveModified(index + 2) })), ...courseEntries,
    ...posts.map((post) => ({ url: pageUrl(`blog/${post.slug}`), lastModified: postModificationDate(post),
      images: post.sections.flatMap((section) => section.image ? [new URL(section.image.src, pageUrl("/")).href] : []),
    })),
  ];
}
