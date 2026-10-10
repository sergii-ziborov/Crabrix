export async function GET() { return new Response("ok\n", { headers: { "Cache-Control": "no-store" } }); }
