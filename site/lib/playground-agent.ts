import { CLIENT_CODECS, type PlaygroundLink } from "./playground-session";

/** The relay's agent capability for a room. It expires with the room. */
export type AgentAccess = { access: string; mode: "edit" | "view"; expiresAt: number };

/** Exchanges a person token for the matching agent token. Agent tokens cannot call this. */
export async function fetchAgentAccess(id: string, personAccess: string): Promise<AgentAccess> {
  const response = await fetch(`/api/playground/rooms/${id}/agent/`, { credentials: "omit", cache: "no-store", headers: { Authorization: "Bearer " + personAccess, "X-Crabrix-Codecs": CLIENT_CODECS } });
  const result = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(result.error ?? "Could not get an agent link for this room.");
  if (typeof result.access !== "string" || (result.mode !== "edit" && result.mode !== "view") || !Number.isSafeInteger(result.expiresAt)) throw new Error("The relay returned an invalid agent link.");
  return { access: result.access, mode: result.mode, expiresAt: result.expiresAt };
}

/** A remote MCP URL for the room. It carries the room key, so treat it like the room link. */
export function agentLink(room: Pick<PlaygroundLink, "id" | "key">, agentAccess: string, origin = location.origin): string {
  return `${origin}/mcp/${room.id}/${agentAccess}/${room.key}`;
}
