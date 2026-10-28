import { instrumentRust } from "../lib/rust-debug-instrumentation";
export function instrument(json: string): string {
  try { const request = JSON.parse(json); return JSON.stringify(instrumentRust(request.files, request.entryFile, request.excludedRustFiles)); }
  catch (error) { return JSON.stringify({ error: error instanceof Error ? error.message : String(error) }); }
}
