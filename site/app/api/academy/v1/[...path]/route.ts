import { academyExample, academyIndex, academyLesson, academyPath, ACADEMY_SCHEMA_VERSION, etagFor, learningStateSchema, teachingContract } from "@/lib/academy";
import { ACADEMY_MCP_URL } from "@/lib/ai-learning";
import { academyApiEnabled, academyMcpState, aiLearningEnabled, learningLinksEnabled } from "@/lib/flags";

// Public, read-only Academy API v1 for AI agents and the Crabrix MCP. No cookies or
// accounts are read; every response is the same for every caller.
const id = /^[a-z0-9][a-z0-9.-]{0,127}$/;

function respond(request: Request, body: string, contentType: string, maxAge = 300): Response {
  const etag = etagFor(body);
  const headers = {
    "Content-Type": contentType, ETag: etag, "Cache-Control": `public, max-age=${maxAge}`,
    "Access-Control-Allow-Origin": "*", "X-Content-Type-Options": "nosniff",
  };
  if (request.headers.get("if-none-match") === etag) return new Response(null, { status: 304, headers });
  return new Response(body, { status: 200, headers });
}

function failure(status: 400 | 404 | 503, code: "BAD_REQUEST" | "NOT_FOUND" | "UNAVAILABLE", message: string): Response {
  return Response.json({ schemaVersion: ACADEMY_SCHEMA_VERSION, error: { code, message } },
    { status, headers: { "Cache-Control": "public, max-age=60", "Access-Control-Allow-Origin": "*" } });
}

export async function GET(request: Request, { params }: { params: Promise<{ path: string[] }> }) {
  const path = (await params).path;
  const json = (value: Record<string, unknown> | undefined, what: string) =>
    value ? respond(request, JSON.stringify(value), "application/json; charset=utf-8") : failure(404, "NOT_FOUND", `No such ${what}.`);
  // The switchboard answers even when the API is paused (PLAN.md, Phase 7); the app reads it
  // only when its Learn with AI screen opens.
  if (path.length === 1 && path[0] === "status.json") {
    return respond(request, JSON.stringify({ schemaVersion: ACADEMY_SCHEMA_VERSION,
      learnWithAI: aiLearningEnabled() ? "on" : "paused", academyApi: academyApiEnabled() ? "on" : "paused",
      academyMcp: { url: ACADEMY_MCP_URL, state: academyMcpState() },
      learningLinks: learningLinksEnabled() ? "on" : "paused", message: null }), "application/json; charset=utf-8", 60);
  }
  if (!academyApiEnabled()) return failure(503, "UNAVAILABLE", "The Crabrix Academy API is paused. Lessons stay readable at https://crabrix.com/learn/.");
  if (path.length === 1 && path[0] === "index.json") return json(academyIndex(), "index");
  if (path.length === 1 && path[0] === "learning-state.schema.json" && learningStateSchema()) return respond(request, learningStateSchema(), "application/schema+json; charset=utf-8");
  if (path.length === 1 && path[0] === "teaching-contract.md") return respond(request, teachingContract(), "text/markdown; charset=utf-8");
  if (path.length === 3 && path[0] === "lessons" && path[2].endsWith(".json")) {
    const lessonId = path[2].slice(0, -5);
    if (!id.test(path[1]) || !id.test(lessonId)) return failure(400, "BAD_REQUEST", "Course and lesson IDs are lowercase letters, digits, dots and hyphens.");
    return json(academyLesson(path[1], lessonId), "lesson");
  }
  if (path.length === 2 && (path[0] === "paths" || path[0] === "examples") && path[1].endsWith(".json")) {
    const key = path[1].slice(0, -5);
    if (!id.test(key)) return failure(400, "BAD_REQUEST", "IDs are lowercase letters, digits, dots and hyphens.");
    return path[0] === "paths" ? json(academyPath(key), "learning path") : json(academyExample(key), "example");
  }
  return failure(404, "NOT_FOUND", "Unknown Academy API path. Start at /api/academy/v1/index.json.");
}
