import { countAcademyEvent } from "@/lib/academy-events";
import { academyEventsEnabled } from "@/lib/flags";

// Minimal, anonymous counters for "Learn Rust with Your AI Agent" (docs/ai-learning/PLAN.md,
// Phase 7). Only a fixed event name and detail are read from the body. Cookies, IP address and
// user agent are never read or stored.
export const dynamic = "force-dynamic";
const accepted = () => new Response(null, { status: 204, headers: { "Cache-Control": "no-store" } });

export async function POST(request: Request) {
  const length = Number(request.headers.get("content-length") ?? "0");
  if (length > 256) return new Response(null, { status: 413 });
  let text = "";
  try { text = (await request.text()).slice(0, 257); } catch { return new Response(null, { status: 400 }); }
  if (text.length > 256) return new Response(null, { status: 413 });
  let body: { event?: unknown; detail?: unknown } = {};
  try { body = JSON.parse(text); } catch { return new Response(null, { status: 400 }); }
  if (!body || typeof body !== "object") return new Response(null, { status: 400 });
  if (!academyEventsEnabled()) return accepted();
  try {
    return countAcademyEvent(body.event, body.detail) ? accepted() : new Response(null, { status: 400 });
  } catch {
    return accepted(); // a full disk or locked database never breaks a page
  }
}
