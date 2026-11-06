import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { courseById, courseLessons } from "@/lib/courses";
export async function GET(_request: Request, { params }: { params: Promise<{ path: string[] }> }) {
  const cache = { "Cache-Control": "public, max-age=3600", "X-Content-Type-Options": "nosniff" };
  const path = (await params).path;
  if (path.length !== 2 || !/^[a-z0-9_-]+$/.test(path[0]) || !/^[a-z0-9_-]+\.png$/.test(path[1])) return new Response("Not found", { status: 404, headers: cache });
  const course = courseById(path[0]);
  if (!course || !courseLessons(course).some((lesson) => lesson.illustration?.path === `media/${path[1]}`)) return new Response("Not found", { status: 404, headers: cache });
  try {
    const bytes = await readFile(join(process.cwd(), "content", "learn-media", ...path));
    return new Response(bytes, { headers: { ...cache, "Content-Type": "image/png" } });
  } catch { return new Response("Not found", { status: 404, headers: cache }); }
}
