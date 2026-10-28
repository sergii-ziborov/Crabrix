import capabilities from "@/content/capabilities.json";

// Public product metadata only. This is not a tool endpoint and accepts no
// project source, room key, credentials, edit command or execution request.
export function GET() {
  return Response.json(capabilities, { headers: { "Cache-Control": "public, max-age=300" } });
}
