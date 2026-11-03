import { playgroundRooms } from "@/lib/playground-rooms";
import { bearer, declaredCodecs, guardPlaygroundOrigin, playgroundFailure, privateHeaders } from "@/lib/playground-api";
export const runtime = "nodejs";
export const dynamic = "force-dynamic";
type Context = { params: Promise<{ id: string }> };

// Returns the agent capability matching the caller's person link. Agent links cannot call this.
export async function GET(request: Request, context: Context) {
  try {
    guardPlaygroundOrigin(request);
    const { id } = await context.params, capability = bearer(request);
    playgroundRooms.admit(id, capability, declaredCodecs(request));
    return Response.json(playgroundRooms.agent(id, capability), { headers: privateHeaders });
  } catch (error) { return playgroundFailure(error); }
}
