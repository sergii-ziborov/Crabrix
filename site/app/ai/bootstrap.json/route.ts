import { aiBootstrap } from "@/lib/ai-bootstrap";

export const dynamic = "force-static";

export function GET() {
  return Response.json(aiBootstrap, { headers: { "Cache-Control": "public, max-age=3600" } });
}
