import { validatePlaygroundDocument } from "./playground-document";

// Execution identity is independent of origin metadata, room sequence, edit
// order, locale and dictionary insertion order. Preserve exact source bytes.
export function runtimeSource(input: unknown): { canonical: string; paths: string[] } {
  const source = validatePlaygroundDocument(input);
  const entries = Object.entries(source.files).sort(([left], [right]) => left < right ? -1 : left > right ? 1 : 0);
  return {
    canonical: JSON.stringify(["crabrix-runtime-source-v1", source.name, source.entryFile, source.edition, entries]),
    paths: entries.map(([path]) => path),
  };
}

export async function runtimeSourceRevision(input: unknown): Promise<string> {
  const bytes = new TextEncoder().encode(runtimeSource(input).canonical);
  return Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)), b => b.toString(16).padStart(2, "0")).join("");
}
