import * as Y from "yjs";
import { validatePlaygroundDocument, type PlaygroundDocument } from "./playground-document.ts";

export function documentFromY(doc: Y.Doc): PlaygroundDocument {
  const metadata = doc.getMap<unknown>("meta");
  const files = Object.fromEntries(Array.from(doc.getMap<Y.Text>("files"), ([path, text]) => {
    if (!(text instanceof Y.Text)) throw new Error("Invalid collaborative text file.");
    return [path, text.toString()];
  }));
  return validatePlaygroundDocument({ schemaVersion: metadata.get("schemaVersion"), name: metadata.get("name"), entryFile: metadata.get("entryFile"), edition: metadata.get("edition"), origin: metadata.get("origin"), files });
}

function replaceText(text: Y.Text, next: string) {
  const previous = text.toString();
  let prefix = 0;
  while (prefix < previous.length && prefix < next.length && previous[prefix] === next[prefix]) prefix++;
  // Yjs stores text in UTF-16 positions but serializes string items as UTF-8.
  // Never split a surrogate pair while computing the minimal native text edit.
  const low = (n: number) => n >= 0xdc00 && n <= 0xdfff;
  if (prefix > 0 && low(previous.charCodeAt(prefix))) prefix--;
  let suffix = 0;
  while (suffix < previous.length - prefix && suffix < next.length - prefix && previous[previous.length - 1 - suffix] === next[next.length - 1 - suffix]) suffix++;
  if (suffix > 0 && low(previous.charCodeAt(previous.length - suffix))) suffix--;
  const removed = previous.length - prefix - suffix, inserted = next.slice(prefix, next.length - suffix);
  if (removed) text.delete(prefix, removed);
  if (inserted) text.insert(prefix, inserted);
}

export function updateYDocument(doc: Y.Doc, input: PlaygroundDocument, origin: unknown = "source") {
  const source = validatePlaygroundDocument(input);
  doc.transact(() => {
    const metadata = doc.getMap("meta"), files = doc.getMap<Y.Text>("files");
    for (const [key, value] of Object.entries(source)) if (key !== "files" && JSON.stringify(metadata.get(key)) !== JSON.stringify(value)) metadata.set(key, value);
    if (!source.origin) metadata.delete("origin");
    for (const path of files.keys()) if (!(path in source.files)) files.delete(path);
    for (const [path, content] of Object.entries(source.files)) {
      let text = files.get(path);
      if (!text) { text = new Y.Text(); files.set(path, text); }
      replaceText(text, content);
    }
  }, origin);
}

export function yDocument(source: PlaygroundDocument): Y.Doc {
  const doc = new Y.Doc(); updateYDocument(doc, source, "initial"); return doc;
}

export function validatedYUpdate(bytes: Uint8Array): PlaygroundDocument {
  const doc = new Y.Doc();
  try { Y.applyUpdate(doc, bytes); return documentFromY(doc); }
  finally { doc.destroy(); }
}
