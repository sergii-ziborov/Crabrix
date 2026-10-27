import { PlaygroundError } from "./playground-rooms.ts";

export const privateHeaders = { "Cache-Control": "private, no-store, max-age=0", "Referrer-Policy": "no-referrer", "X-Content-Type-Options": "nosniff" };

export function bearer(request: Request): string {
  const value = request.headers.get("authorization") ?? "";
  if (!/^Bearer [A-Za-z0-9_-]{43}$/.test(value)) throw new PlaygroundError("Open a complete authorized Playground link.", 401);
  return value.slice(7);
}

export function guardPlaygroundOrigin(request: Request) {
  const origin = request.headers.get("origin");
  const expected = process.env.SITE_ORIGIN ?? new URL(request.url).origin;
  // Native clients have no Origin. Every room operation still needs a random capability.
  if (origin && origin !== expected) throw new PlaygroundError("Use this operation from Crabrix.", 403);
  if (request.headers.get("sec-fetch-site") === "cross-site") throw new PlaygroundError("Cross-site Playground requests are not accepted.", 403);
}

export async function limitedJSON(request: Request, maximum = 400_000, timeoutMs = 10_000): Promise<Record<string, unknown>> {
  if (!request.headers.get("content-type")?.toLowerCase().startsWith("application/json") || request.headers.get("content-encoding")) throw new PlaygroundError("Send uncompressed JSON.", 415);
  const declared = Number(request.headers.get("content-length") ?? "0");
  if (!Number.isFinite(declared) || declared < 0 || declared > maximum) throw new PlaygroundError("Request too large.", 413);
  const reader = request.body?.getReader();
  if (!reader) throw new PlaygroundError("Missing request body.");
  const chunks: Uint8Array[] = []; let length = 0;
  const deadline = Date.now() + timeoutMs;
  while (true) {
    let timer: ReturnType<typeof setTimeout> | undefined;
    let next: ReadableStreamReadResult<Uint8Array>;
    try {
      next = await Promise.race([reader.read(), new Promise<never>((_, reject) => { timer = setTimeout(() => reject(new PlaygroundError("Request body timed out.", 408)), Math.max(0, deadline - Date.now())); })]);
    } catch (error) { void reader.cancel().catch(() => {}); throw error; }
    finally { if (timer) clearTimeout(timer); }
    const { done, value } = next;
    if (done) break;
    length += value.byteLength;
    if (length > maximum) { await reader.cancel(); throw new PlaygroundError("Request too large.", 413); }
    chunks.push(value);
  }
  const buffer = new Uint8Array(length); let offset = 0;
  for (const chunk of chunks) { buffer.set(chunk, offset); offset += chunk.byteLength; }
  let result: unknown;
  try { result = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(buffer)); }
  catch { throw new PlaygroundError("Invalid UTF-8 JSON."); }
  if (!result || typeof result !== "object" || Array.isArray(result)) throw new PlaygroundError("Invalid request.");
  return result as Record<string, unknown>;
}

export function playgroundFailure(error: unknown): Response {
  const known = error instanceof PlaygroundError;
  return Response.json({ error: known ? error.message : "This Playground operation could not be completed." }, { status: known ? error.status : 500, headers: privateHeaders });
}
