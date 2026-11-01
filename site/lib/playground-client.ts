import type { CreatedPlayground, PlaygroundLink } from "./playground-session";

// Conflict, rate limit and busy relay: the next timed snapshot succeeds and no source is at risk.
export const isTransientSnapshotStatus = (status: number) => status === 409 || status === 429 || status === 503;

// The owner and view tokens stay in this tab's session storage. The address bar holds
// only the edit link, because people copy that URL to share it.
type OwnerStorage = Pick<Storage, "getItem" | "setItem" | "removeItem">;
const ownerKey = (id: string) => "crabrix.playground.owner.v1." + id;
const capability = /^[A-Za-z0-9_-]{43}$/;
const tabStorage = (): OwnerStorage => sessionStorage;

export function rememberOwnerCapabilities(room: CreatedPlayground, storage = tabStorage) {
  try { storage().setItem(ownerKey(room.id), JSON.stringify({ owner: room.owner, view: room.view })); } catch {}
}

export function restoreOwnerCapabilities(link: PlaygroundLink, storage = tabStorage): CreatedPlayground | null {
  if (link.mode !== "edit") return null;
  try {
    const saved = JSON.parse(storage().getItem(ownerKey(link.id)) ?? "null");
    return capability.test(saved?.owner) && capability.test(saved?.view) ? { ...link, owner: saved.owner, view: saved.view } : null;
  } catch { return null; }
}

export function forgetOwnerCapabilities(id: string, storage = tabStorage) {
  try { storage().removeItem(ownerKey(id)); } catch {}
}
