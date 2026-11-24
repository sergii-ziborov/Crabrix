import { learnLinksResponse } from "@/lib/learn-links";

// Learning links (docs/ai-learning/learning-link.md, "Website API"): ciphertext and token hashes
// only, for the Crabrix app and the remote MCP server. Cookies are never read. All logic and
// validation live in lib/learn-links.ts. With trailingSlash: true the canonical paths end in "/".
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

type Context = { params: Promise<{ path?: string[] }> };
const handle = async (request: Request, { params }: Context) => learnLinksResponse(request, (await params).path ?? []);

export const GET = handle;
export const POST = handle;
export const PUT = handle;
export const DELETE = handle;
// So an unsupported method gets the same JSON 405 (or 503 when paused). OPTIONS stays Next's default.
export const PATCH = handle;
