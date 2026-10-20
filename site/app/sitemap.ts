import type { MetadataRoute } from "next";
import { courseSnapshot } from "@/lib/courses";
import { pageUrl } from "@/lib/seo";
import { posts } from "@/lib/posts";
import { lessonModifiedDates, courseModifiedDates } from "@/lib/lesson-seo";

export const dynamic = "force-static";

export default function sitemap(): MetadataRoute.Sitemap {
  const paths = ["", "about", "technology", "support", "privacy", "terms", "licenses", "learn", "blog", "sitemap"];
  const courseEntries = courseSnapshot().courses.flatMap((course) => [
    { url: pageUrl(`learn/${course.id}`), ...(courseModifiedDates[course.id] ? { lastModified: courseModifiedDates[course.id] } : {}) },
    ...course.units.flatMap((unit) => unit.lessons.map((lesson) => ({
      url: pageUrl(`learn/${course.id}/${lesson.id}`),
      ...(lessonModifiedDates[`${course.id}/${lesson.id}`] ? { lastModified: lessonModifiedDates[`${course.id}/${lesson.id}`] } : {}),
    }))),
  ]);
  return [...paths.map((path) => ({ url: pageUrl(path) })), ...courseEntries,
    ...posts.map((post) => ({ url: pageUrl(`blog/${post.slug}`), lastModified: post.date,
      images: post.sections.flatMap((section) => section.image ? [new URL(section.image.src, pageUrl("/")).href] : []),
    })),
  ];
}
