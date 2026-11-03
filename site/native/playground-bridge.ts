// Bundled, fixed CRDT implementation for JavaScriptCore. User source is data;
// it is never evaluated as JavaScript. Encryption and transport stay native.
import * as Y from "yjs";
import { documentFromY, updateYDocument } from "../lib/playground-collab";
import { applyOperations, documentFromProject, operationsFromReplace, readProject, schemaVersionOf, type ProjectOperation } from "../lib/playground-codec-v2";
import { createPresence, localPresence, receivePresence, remoteSelections, remoteSelectionsV2, publishRuntimePresence, remoteRuntimePresence } from "../lib/playground-presence";
import { validatePlaygroundDocument } from "../lib/playground-document";
import { runtimeSource } from "../lib/playground-runtime-source";
export { callRuntime } from "./playground-runtime-policy";
export { callHost } from "./playground-runtime-host";
const doc = new Y.Doc(), awareness = createPresence(doc);
const remote = {}, pending: Uint8Array[] = [];
let presenceDirty = true;
// The room's format, from the relay. A v2 room whose document is not v2 is read only.
let codec: 1 | 2 = 1, formatMismatch = false;
// Path -> file ID of the last document returned to Swift. The app edits whole projects,
// so its next change is read against this map: a kept path writes to the same file
// even after another participant renamed it.
let baseline: Record<string, string> = {};
doc.on("update", (bytes: Uint8Array, origin: unknown) => { if (origin !== remote) pending.push(bytes); });
awareness.on("update", (_: unknown, origin: unknown) => { if (origin !== remote) presenceDirty = true; });

// Snapshots and updates cross the bridge as standard base64: a byte array of a 512 KiB
// snapshot would not fit the 2,000,000 character message. The prelude's atob is
// limited to small values, so these run here.
const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
const lookup = new Map(Array.from(alphabet, (character, index) => [character.charCodeAt(0), index]));
export function decodeBase64(text: unknown, maximumBytes: number): Uint8Array {
  if (typeof text !== "string" || text.length % 4 !== 0 || text.length / 4 * 3 > maximumBytes + 2 || !/^[A-Za-z0-9+/]*={0,2}$/.test(text)) throw new Error("Invalid native collaboration bytes.");
  const padding = text.endsWith("==") ? 2 : text.endsWith("=") ? 1 : 0, bytes = new Uint8Array(text.length / 4 * 3 - padding);
  for (let i = 0, o = 0; i < text.length; i += 4) {
    const value = [0, 1, 2, 3].reduce((n, k) => n << 6 | (text[i + k] === "=" ? 0 : lookup.get(text.charCodeAt(i + k))!), 0);
    for (const shift of [16, 8, 0]) if (o < bytes.length) bytes[o++] = value >> shift & 255;
  }
  if (bytes.length > maximumBytes) throw new Error("Oversized native collaboration bytes.");
  return bytes;
}
export function encodeBase64(bytes: Uint8Array): string {
  const parts: string[] = [];
  for (let start = 0; start < bytes.length; start += 6144) {
    let chunk = "";
    for (let i = start; i < Math.min(bytes.length, start + 6144); i += 3) {
      const value = bytes[i] << 16 | (i + 1 < bytes.length ? bytes[i + 1] << 8 : 0) | (i + 2 < bytes.length ? bytes[i + 2] : 0);
      chunk += alphabet[value >> 18 & 63] + alphabet[value >> 12 & 63] + (i + 1 < bytes.length ? alphabet[value >> 6 & 63] : "=") + (i + 2 < bytes.length ? alphabet[value & 63] : "=");
    }
    parts.push(chunk);
  }
  return parts.join("");
}
const bytesOf = (value: unknown, maximum: number) => Array.isArray(value) ? Uint8Array.from(value as number[]) : decodeBase64(value, maximum);

/** A copy drops text that only Undo histories or deleted items still hold. */
function compactUpdate(): Uint8Array {
  const copy = new Y.Doc();
  try { Y.applyUpdate(copy, Y.encodeStateAsUpdate(doc)); return Y.encodeStateAsUpdate(copy); }
  finally { copy.destroy(); }
}

function operate(operations: ProjectOperation[]) {
  if (formatMismatch) throw new Error("This room's document has an unexpected format, so it is read only here.");
  // Collisions stay visible as conflict names instead of refusing a whole-project sync.
  if (operations.length) applyOperations(doc, operations, { origin: "replace", collisions: "allow" });
}

export function call(requestJSON: string): string {
  try {
    const request = JSON.parse(requestJSON);
    switch (request.type) {
      case "initialize": codec = 1; updateYDocument(doc, validatePlaygroundDocument(request.document)); break;
      case "document": break;
      case "runtime-presence": publishRuntimePresence(awareness, request.envelope ?? null); break;
      case "runtime-source": {
        const source = runtimeSource(codec === 2 ? documentFromProject(readProject(doc)) : documentFromY(doc));
        return JSON.stringify({ runtimeSource: source.canonical, runtimePaths: source.paths });
      }
      case "replace": {
        const next = validatePlaygroundDocument(request.document);
        if (codec === 1) updateYDocument(doc, next);
        else operate(operationsFromReplace(readProject(doc), request.baseline ?? baseline, next));
        break;
      }
      case "file": {
        if (codec === 1) { const value = documentFromY(doc); value.files[request.path] = request.text; updateYDocument(doc, validatePlaygroundDocument(value)); break; }
        const state = readProject(doc), id = baseline[request.path] ?? state.files.find(file => file.path === request.path)?.id;
        operate([id ? { kind: "write", file: { id }, text: request.text } : { kind: "create", path: request.path, text: request.text }]);
        break;
      }
      case "snapshot": break;
      case "merge": return JSON.stringify({ merged: encodeBase64(Y.mergeUpdates(request.updates.map((value: unknown) => bytesOf(value, 196_608)))) });
      case "state": {
        const format = request.codec === undefined ? 1 : request.codec;
        if (format !== 1 && format !== 2) throw new Error("This Playground uses a newer format. Update Crabrix to open it.");
        const candidate = new Y.Doc();
        try {
          Y.applyUpdate(candidate, bytesOf(request.snapshot, 512 * 1024));
          for (const bytes of request.events) Y.applyUpdate(candidate, bytesOf(bytes, 196_608));
          // v1 refuses an invalid project as before; v2 reads any state and checks only its format.
          if (format === 1) documentFromY(candidate);
          else formatMismatch = schemaVersionOf(candidate) !== 2;
          codec = format;
          const delta = Y.encodeStateAsUpdate(doc, Y.encodeStateVector(candidate));
          if (delta.length > 2 && !formatMismatch) pending.push(delta);
          Y.applyUpdate(doc, Y.encodeStateAsUpdate(candidate), remote);
        } finally { candidate.destroy(); }
        break;
      }
      case "update": {
        const bytes = bytesOf(request.bytes, 196_608);
        if (codec === 2) { Y.applyUpdate(doc, bytes, remote); break; }
        const candidate = new Y.Doc();
        try { Y.applyUpdate(candidate, Y.encodeStateAsUpdate(doc)); Y.applyUpdate(candidate, bytes); documentFromY(candidate); Y.applyUpdate(doc, bytes, remote); }
        finally { candidate.destroy(); }
        break;
      }
      case "selection": {
        let text: Y.Text | undefined;
        if (codec === 1) text = doc.getMap<Y.Text>("files").get(request.file);
        else { const id = readProject(doc).files.find(file => file.path === request.file)?.id; if (id) text = doc.getText("t:" + id); }
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
    const selections = codec === 2 ? remoteSelectionsV2 : remoteSelections;
    const result: Record<string, unknown> = { clientID: doc.clientID, selections: selections(doc, awareness), participants: awareness.getStates().size };
    result.runtimeFrames = remoteRuntimePresence(awareness);
    result.localSelection = selections(doc, awareness, true).find(value => value.clientID === doc.clientID);
    if (codec === 1) { if (doc.getMap("files").size) result.document = documentFromY(doc); }
    else {
      // A blocked project returns no document, so Swift keeps its copy read only
      // instead of failing validation and reconnecting in a loop.
      const state = readProject(doc), previous = baseline;
      result.recovery = state.recovery.length; result.formatMismatch = formatMismatch;
      if (state.blocked.length) result.blocked = state.blocked;
      else {
        result.document = documentFromProject(state);
        baseline = Object.fromEntries(state.files.map(file => [file.path, file.id]));
        // Another participant's rename, so the app can keep the same file open.
        const renamed: Record<string, string> = {};
        for (const [path, id] of Object.entries(previous)) { const now = state.files.find(file => file.id === id)?.path; if (now && now !== path) renamed[path] = now; }
        if (Object.keys(renamed).length) result.renamed = renamed;
      }
    }
    if (request.type === "snapshot") result.snapshot = encodeBase64(codec === 2 ? compactUpdate() : Y.encodeStateAsUpdate(doc));
    if (presenceDirty || request.type === "tick") { result.presence = Array.from(localPresence(awareness)); presenceDirty = false; }
    // Last, so a failure while reading the project above cannot drop outgoing edits.
    const updates = pending.splice(0);
    if (updates.length) result.update = encodeBase64(Y.mergeUpdates(updates));
    return JSON.stringify(result);
  } catch (error) { return JSON.stringify({ error: error instanceof Error ? error.message : String(error) }); }
}
