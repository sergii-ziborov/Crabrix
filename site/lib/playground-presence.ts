import * as Y from "yjs";
import { Awareness, applyAwarenessUpdate, encodeAwarenessUpdate } from "y-protocols/awareness";

export const participantColors = ["#2876bd", "#aa44b8", "#9f6812", "#187b53"];
export function createPresence(doc: Y.Doc, name?: string): Awareness {
  const awareness = new Awareness(doc);
  awareness.setLocalState({ user: { name: name || `Guest ${String(doc.clientID).slice(-4)}`, color: participantColors[doc.clientID % participantColors.length] }, cursor: null });
  return awareness;
}
export const localPresence = (awareness: Awareness) => encodeAwarenessUpdate(awareness, [awareness.clientID]);

// Participant supplied names and colours are used in editor decorations. Validate
// before handing the protocol update to CodeMirror or the native renderer.
export function receivePresence(awareness: Awareness, bytes: Uint8Array, origin: unknown) {
  if (bytes.length > 4000) throw new Error("Oversized participant presence.");
  const scratch = new Y.Doc(), probe = new Awareness(scratch);
  probe.setLocalState(null);
  try {
    applyAwarenessUpdate(probe, bytes, origin);
    if (probe.getStates().size > 4) throw new Error("Invalid participant presence.");
    for (const [client, state] of probe.getStates()) {
      if (client === awareness.clientID) continue;
      if (!state.user || typeof state.user.name !== "string" || state.user.name.length > 40 || /[\u0000-\u001f]/.test(state.user.name) || !/^#[a-f0-9]{6}$/i.test(state.user.color) || state.user.colorLight !== undefined) throw new Error("Invalid participant identity.");
      if (state.cursor !== null && state.cursor !== undefined) {
        if (JSON.stringify(state.cursor).length > 1000 || !state.cursor.anchor || !state.cursor.head) throw new Error("Invalid participant selection.");
        Y.createRelativePositionFromJSON(state.cursor.anchor); Y.createRelativePositionFromJSON(state.cursor.head);
      }
    }
    applyAwarenessUpdate(awareness, bytes, origin);
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
