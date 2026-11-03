import { playgroundRooms, roomCodec, snapshotLimit, validatePacket, PlaygroundError } from "@/lib/playground-rooms";
import { clientKey } from "@/lib/client-key";
import { guardPlaygroundOrigin, limitedJSON, playgroundFailure, privateHeaders } from "@/lib/playground-api";
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  try {
    guardPlaygroundOrigin(request);
    const ip = clientKey(request.headers.get("x-real-ip"));
    playgroundRooms.admitCreate(ip);
    const body = await limitedJSON(request);
    if (Object.keys(body).some(key => !["snapshot", "lifetimeSeconds", "codec"].includes(key))) throw new PlaygroundError("Unexpected request field.");
    const codec = roomCodec(body.codec);
    const packet = validatePacket(body.snapshot, snapshotLimit(codec));
    const room = playgroundRooms.create(packet, Number(body.lifetimeSeconds), ip, codec);
    return Response.json(room, { status: 201, headers: privateHeaders });
  } catch (error) { return playgroundFailure(error); }
}
