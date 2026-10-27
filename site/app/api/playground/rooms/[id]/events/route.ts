import { playgroundRooms } from "@/lib/playground-rooms";
import { bearer, guardPlaygroundOrigin, playgroundFailure, privateHeaders } from "@/lib/playground-api";
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(request: Request, context: { params: Promise<{ id: string }> }) {
  let release: (() => void) | undefined;
  let timer: ReturnType<typeof setInterval> | undefined;
  try {
    guardPlaygroundOrigin(request);
    const { id } = await context.params, capability = bearer(request);
    const peer = new URL(request.url).searchParams.get("peer") ?? "";
    playgroundRooms.access(id, capability);
    playgroundRooms.limit("stream:" + id + ":" + capability, 30);
    const encoder = new TextEncoder();
    let controller: ReadableStreamDefaultController<Uint8Array>;
    let closed = false;
    const close = () => { if (closed) return; closed = true; release?.(); if (timer) clearInterval(timer); try { controller.close(); } catch {} };
    const stream = new ReadableStream<Uint8Array>({
      start(target) {
        controller = target;
        const send = (type: string, value: unknown) => {
          if (closed) return;
          // A stalled reader cannot accumulate an unbounded source queue.
          if ((controller.desiredSize ?? 0) < -2) { close(); return; }
          try { controller.enqueue(encoder.encode(`event: ${type}\ndata: ${JSON.stringify(value)}\n\n`)); }
          catch { close(); }
        };
        release = playgroundRooms.subscribe(id, capability, peer, event => {
          if (typeof event === "string") { send(event, {}); close(); }
          else send("kind" in event ? "presence" : "update", event);
        });
        send("state", playgroundRooms.state(id, capability));
        timer = setInterval(() => {
          playgroundRooms.prune();
          if (!closed) send("ping", { now: Date.now() });
        }, 1000);
        request.signal.addEventListener("abort", close, { once: true });
        if (request.signal.aborted) close();
      },
      cancel: close,
    });
    return new Response(stream, { headers: { ...privateHeaders, "Content-Type": "text/event-stream", "X-Accel-Buffering": "no", "Connection": "keep-alive" } });
  } catch (error) {
    release?.(); if (timer) clearInterval(timer);
    return playgroundFailure(error);
  }
}
