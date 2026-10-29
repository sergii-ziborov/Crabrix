import * as Y from "yjs";
import { Awareness, applyAwarenessUpdate, encodeAwarenessUpdate } from "y-protocols/awareness";
import { RUNTIME_LIMITS, type RuntimeEnvelope } from "./playground-runtime-protocol";
import { isWellFormedUTF16 } from "./playground-document";

export const participantColors = ["#2876bd", "#aa44b8", "#9f6812", "#187b53"];
export function createPresence(doc: Y.Doc, name?: string): Awareness {
  const awareness = new Awareness(doc);
  awareness.setLocalState({ user: { name: name || `Guest ${String(doc.clientID).slice(-4)}`, color: participantColors[doc.clientID % participantColors.length] }, cursor: null });
  return awareness;
}
export const localPresence = (awareness: Awareness) => encodeAwarenessUpdate(awareness, [awareness.clientID]);

// This carries bounded opaque envelopes only. Receiving code must authenticate
// and locally authorize them; a presence field itself is never executable.
export function publishRuntimePresence(awareness: Awareness, envelope: RuntimeEnvelope | null) {
  if (envelope !== null && new TextEncoder().encode(JSON.stringify(envelope)).length > RUNTIME_LIMITS.envelopeBytes) throw new Error("Runtime presence exceeds its message budget.");
  const state = awareness.getLocalState();
  if (!state) throw new Error("This participant is disconnected.");
  const next = { ...state, runtime: envelope };
  const proposed = new Map(awareness.getStates()); proposed.set(awareness.clientID, next);
  // Reserve the maximum extra varuint bytes needed by the next awareness clock.
  // Refuse the runtime message rather than removing or shortening a selection.
  if (encodeAwarenessUpdate(awareness, [awareness.clientID], proposed).length > 3992) throw new Error("Runtime message and selection exceed the transient presence budget.");
  awareness.setLocalState(next);
}

export type RuntimePresenceFrame = { clientID: number; clock: number; envelope: string };
export function remoteRuntimePresence(awareness: Awareness): RuntimePresenceFrame[] {
  const result: RuntimePresenceFrame[] = [];
  awareness.getStates().forEach((state, clientID) => {
    if (clientID === awareness.clientID || !state.runtime || typeof state.runtime !== "object" || Array.isArray(state.runtime)) return;
    const envelope = JSON.stringify(state.runtime);
    if (new TextEncoder().encode(envelope).length <= RUNTIME_LIMITS.envelopeBytes) result.push({ clientID, clock: awareness.meta.get(clientID)?.clock ?? 0, envelope });
  });
  return result;
}

// Participant supplied names and colours are used in editor decorations. Validate
// before handing the protocol update to CodeMirror or the native renderer.
export function receivePresence(awareness: Awareness, bytes: Uint8Array, origin: unknown) {
  if (bytes.length > 4000) throw new Error("Oversized participant presence.");
  const scratch = new Y.Doc();
  // The scratch document carries no source updates. Reuse the recipient's ID
  // here so its own probe ID can never accidentally collide with a real peer.
  scratch.clientID = awareness.clientID;
  const probe = new Awareness(scratch);
  probe.setLocalState(null);
  try {
    applyAwarenessUpdate(probe, bytes, origin);
    if (probe.getStates().size > 4) throw new Error("Invalid participant presence.");
    const remoteIDs = [...probe.meta.keys()].filter(client => client !== probe.clientID && client !== awareness.clientID);
    if (remoteIDs.some(client => !Number.isInteger(client) || client < 0 || client > 0xffffffff || !Number.isSafeInteger(probe.meta.get(client)!.clock) || probe.meta.get(client)!.clock < 0)) throw new Error("Invalid participant identifier or clock.");
    for (const [client, state] of probe.getStates()) {
      if (!Number.isInteger(client) || client < 0 || client > 0xffffffff) throw new Error("Invalid participant identifier.");
      if (client === awareness.clientID) continue;
      if (!state.user || typeof state.user.name !== "string" || !isWellFormedUTF16(state.user.name) || state.user.name.length > 40 || /[\u0000-\u001f]/.test(state.user.name) || !/^#[a-f0-9]{6}$/i.test(state.user.color) || state.user.colorLight !== undefined) throw new Error("Invalid participant identity.");
      if (state.cursor !== null && state.cursor !== undefined) {
        if (JSON.stringify(state.cursor).length > 1000 || !state.cursor.anchor || !state.cursor.head) throw new Error("Invalid participant selection.");
        Y.createRelativePositionFromJSON(state.cursor.anchor); Y.createRelativePositionFromJSON(state.cursor.head);
      }
      if (state.runtime !== null && state.runtime !== undefined && new TextEncoder().encode(JSON.stringify(state.runtime)).length > RUNTIME_LIMITS.envelopeBytes) throw new Error("Oversized runtime presence.");
    }
    // A peer can choose any awareness ID. Never let a claimed local ID replace
    // this client's cursor, identity or runtime field, even with a higher clock.
    applyAwarenessUpdate(awareness, encodeAwarenessUpdate(probe, remoteIDs), origin);
  } finally { probe.destroy(); scratch.destroy(); }
}

export type RemoteSelection = { clientID: number; name: string; color: string; file: string; anchor: number; head: number };
export function remoteSelections(doc: Y.Doc, awareness: Awareness, includeLocal = false): RemoteSelection[] {
  const files = doc.getMap<Y.Text>("files"), result: RemoteSelection[] = [];
  awareness.getStates().forEach((state, clientID) => {
    if ((!includeLocal && clientID === awareness.clientID) || !state.cursor) return;
    const anchor = Y.createAbsolutePositionFromRelativePosition(state.cursor.anchor, doc);
    const head = Y.createAbsolutePositionFromRelativePosition(state.cursor.head, doc);
    if (!anchor || !head || anchor.type !== head.type) return;
    const file = Array.from(files).find(([, text]) => text === anchor.type)?.[0];
    if (file) result.push({ clientID, name: state.user.name, color: state.user.color, file, anchor: anchor.index, head: head.index });
  });
  return result;
}
