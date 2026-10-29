// Bundled, fixed CRDT implementation for JavaScriptCore. User source is data;
// it is never evaluated as JavaScript. Encryption and transport stay native.
import * as Y from "yjs";
import { documentFromY, updateYDocument } from "../lib/playground-collab";
import { createPresence, localPresence, receivePresence, remoteSelections, publishRuntimePresence, remoteRuntimePresence } from "../lib/playground-presence";
import { validatePlaygroundDocument } from "../lib/playground-document";
import { runtimeSource } from "../lib/playground-runtime-source";
export { callRuntime } from "./playground-runtime-policy";
const doc = new Y.Doc(), awareness = createPresence(doc);
const remote = {}, pending: Uint8Array[] = [];
let presenceDirty = true;
doc.on("update", (bytes: Uint8Array, origin: unknown) => { if (origin !== remote) pending.push(bytes); });
awareness.on("update", (_: unknown, origin: unknown) => { if (origin !== remote) presenceDirty = true; });
export function call(requestJSON: string): string {
  try {
    const request = JSON.parse(requestJSON);
    switch (request.type) {
      case "initialize": updateYDocument(doc, validatePlaygroundDocument(request.document)); break;
      case "document": break;
      case "runtime-presence": publishRuntimePresence(awareness, request.envelope ?? null); break;
      case "runtime-source": {
        const source = runtimeSource(documentFromY(doc));
        return JSON.stringify({ runtimeSource: source.canonical, runtimePaths: source.paths });
      }
      case "replace": updateYDocument(doc, validatePlaygroundDocument(request.document)); break;
      case "file": {
        const value = documentFromY(doc); value.files[request.path] = request.text;
        updateYDocument(doc, validatePlaygroundDocument(value)); break;
      }
      case "snapshot": break;
      case "merge": return JSON.stringify({ merged: Array.from(Y.mergeUpdates(request.updates.map((bytes: number[]) => Uint8Array.from(bytes)))) });
      case "state": {
        const candidate = new Y.Doc();
        try {
          Y.applyUpdate(candidate, Uint8Array.from(request.snapshot));
          for (const bytes of request.events) Y.applyUpdate(candidate, Uint8Array.from(bytes));
          documentFromY(candidate);
          const delta = Y.encodeStateAsUpdate(doc, Y.encodeStateVector(candidate));
          if (delta.length > 2) pending.push(delta);
          Y.applyUpdate(doc, Y.encodeStateAsUpdate(candidate), remote);
        } finally { candidate.destroy(); }
        break;
      }
      case "update": {
        const bytes = Uint8Array.from(request.bytes), candidate = new Y.Doc();
        try { Y.applyUpdate(candidate, Y.encodeStateAsUpdate(doc)); Y.applyUpdate(candidate, bytes); documentFromY(candidate); Y.applyUpdate(doc, bytes, remote); }
        finally { candidate.destroy(); }
        break;
      }
      case "selection": {
        const text = doc.getMap<Y.Text>("files").get(request.file);
        if (text) awareness.setLocalStateField("cursor", {
          anchor: Y.createRelativePositionFromTypeIndex(text, Math.max(0, Math.min(text.length, request.anchor))),
          head: Y.createRelativePositionFromTypeIndex(text, Math.max(0, Math.min(text.length, request.head))),
        });
        break;
      }
      case "presence": receivePresence(awareness, Uint8Array.from(request.bytes), remote); break;
      case "tick": (globalThis as unknown as { __tick: () => void }).__tick(); break;
      default: throw new Error("Unsupported collaboration operation.");
    }
    const updates = pending.splice(0);
    const result: Record<string, unknown> = { clientID: doc.clientID, selections: remoteSelections(doc, awareness), participants: awareness.getStates().size };
    result.runtimeFrames = remoteRuntimePresence(awareness);
    result.localSelection = remoteSelections(doc, awareness, true).find(value => value.clientID === doc.clientID);
    if (doc.getMap("files").size) result.document = documentFromY(doc);
    if (request.type === "snapshot") result.snapshot = Array.from(Y.encodeStateAsUpdate(doc));
    if (updates.length) result.update = Array.from(Y.mergeUpdates(updates));
    if (presenceDirty || request.type === "tick") { result.presence = Array.from(localPresence(awareness)); presenceDirty = false; }
    return JSON.stringify(result);
  } catch (error) { return JSON.stringify({ error: error instanceof Error ? error.message : String(error) }); }
}
