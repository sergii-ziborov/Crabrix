import { playgroundRooms, ROOM_LIMITS, validatePacket, PlaygroundError } from "@/lib/playground-rooms";
import { guardPlaygroundOrigin, limitedJSON, playgroundFailure, privateHeaders } from "@/lib/playground-api";
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  try {
    guardPlaygroundOrigin(request);
    playgroundRooms.limit("create:global", 120);
    playgroundRooms.limit("create:ip:" + (request.headers.get("x-real-ip") ?? "direct"), 12);
    const body = await limitedJSON(request);
    if (Object.keys(body).some(key => !["snapshot", "lifetimeSeconds"].includes(key))) throw new PlaygroundError("Unexpected request field.");
    const packet = validatePacket(body.snapshot, ROOM_LIMITS.snapshotBytes);
    const room = playgroundRooms.create(packet, Number(body.lifetimeSeconds));
    return Response.json(room, { status: 201, headers: privateHeaders });
  } catch (error) { return playgroundFailure(error); }
}
