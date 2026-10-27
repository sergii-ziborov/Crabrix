import { playgroundRooms, ROOM_LIMITS, validatePacket, PlaygroundError } from "@/lib/playground-rooms";
import { bearer, guardPlaygroundOrigin, limitedJSON, playgroundFailure, privateHeaders } from "@/lib/playground-api";
export const runtime = "nodejs";
export const dynamic = "force-dynamic";
type Context = { params: Promise<{ id: string }> };

export async function GET(request: Request, context: Context) {
  try {
    guardPlaygroundOrigin(request);
    const { id } = await context.params;
    const capability = bearer(request);
    playgroundRooms.limit("read:" + id + ":" + capability, 120);
    return Response.json(playgroundRooms.state(id, capability), { headers: privateHeaders });
  } catch (error) { return playgroundFailure(error); }
}

export async function POST(request: Request, context: Context) {
  try {
    guardPlaygroundOrigin(request);
    const { id } = await context.params, capability = bearer(request);
    playgroundRooms.access(id, capability);
    const body = await limitedJSON(request);
    if (body.type === "presence" && typeof body.peer === "string") {
      playgroundRooms.publishPresence(id, capability, body.peer, validatePacket(body.packet, ROOM_LIMITS.presenceBytes));
      return new Response(null, { status: 204, headers: privateHeaders });
    }
    if (body.type === "snapshot") {
      const snapshot = validatePacket(body.packet, ROOM_LIMITS.snapshotBytes);
      if (!Number.isSafeInteger(body.sequence)) throw new PlaygroundError("Invalid snapshot sequence.");
      playgroundRooms.limit("snapshot:" + id + ":" + capability, 30);
      return Response.json(playgroundRooms.compact(id, capability, Number(body.sequence), snapshot), { headers: privateHeaders });
    }
    if (body.type === "update" && typeof body.peer === "string" && typeof body.messageID === "string") {
      const packet = validatePacket(body.packet, ROOM_LIMITS.updateBytes);
      return Response.json(playgroundRooms.append(id, capability, body.peer, body.messageID, packet), { headers: privateHeaders });
    }
    throw new PlaygroundError("Unsupported relay message.");
  } catch (error) { return playgroundFailure(error); }
}

export async function DELETE(request: Request, context: Context) {
  try {
    guardPlaygroundOrigin(request);
    playgroundRooms.close((await context.params).id, bearer(request));
    return new Response(null, { status: 204, headers: privateHeaders });
  } catch (error) { return playgroundFailure(error); }
}
