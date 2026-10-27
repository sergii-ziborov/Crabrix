import type { DebugSite } from "./rust-debug-instrumentation";
export type DebugVariable = { name: string; type: string; value: string };
export type DebugFrame = { site: DebugSite; locals: DebugVariable[] };
export type DebugPause = { site: DebugSite; frames: DebugFrame[]; reason: "entry" | "step" | "breakpoint"; runningMs: number };
export type DebugCommand = "continue" | "into" | "over" | "out";
export const debugCommands: Record<DebugCommand, number> = { continue: 1, into: 2, over: 3, out: 4 };
export const debugControlOffset = 4;
export function resolveDebugBreakpoints(sites: DebugSite[], requested: Record<string, number[]>): Set<number> {
  const bound = new Set<number>();
  for (const [file, lines] of Object.entries(requested)) {
    const executable = sites.filter(site => site.file === file && site.kind === "statement");
    for (const line of lines) {
      const next = Math.min(...executable.filter(site => site.line >= line).map(site => site.line));
      for (const site of executable) if (site.line === next) bound.add(site.id);
    }
  }
  return bound;
}

// One engine-independent state machine. Native has the same deliberately small
// protocol, driven by its condition variable rather than browser Atomics.
export class RustDebugSession {
  private frames: DebugFrame[] = [];
  private sites: Map<number, DebugSite>;
  private mode: DebugCommand = "into";
  private targetDepth = 0;
  private stoppedOnce = false;
  private events = 0;
  constructor(sites: DebugSite[], private control: Int32Array, private pause: (state: Omit<DebugPause, "runningMs">) => number) {
    this.sites = new Map(sites.map(site => [site.id, site]));
  }
  event(kind: number, siteID: number, bytes: Uint8Array) {
    if (++this.events > 2_000_000) throw new Error("Debug stopped at its checkpoint budget.");
    if (Atomics.load(this.control, 0) === 5) throw new Error("Debug stopped.");
    const site = this.sites.get(siteID);
    if (!site || bytes.length > 65536) throw new Error("Invalid local debugger event.");
    if (kind === 1) {
      if (site.kind !== "entry" || this.frames.length >= 256) throw new Error("Debug call stack limit reached.");
      this.frames.push({ site, locals: [] }); return;
    }
    const frame = this.frames.at(-1);
    if (!frame || frame.site.functionID !== site.functionID) throw new Error("Debug call stack does not match the compiled snapshot.");
    if (kind === 3) { this.frames.pop(); return; }
    if (kind !== 2 || site.kind !== "statement") throw new Error("Invalid debugger checkpoint.");
    const value: unknown = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
    if (!Array.isArray(value) || value.length > 32 || value.some(v => !Array.isArray(v) || v.length !== 3 || v.some(s => typeof s !== "string" || s.length > 1024))) throw new Error("Invalid local-variable snapshot.");
    frame.site = site; frame.locals = value.map(([name, type, value]) => ({ name, type, value }));
    const breakpoint = Atomics.load(this.control, debugControlOffset + siteID) === 1;
    const stepping = this.mode === "into" || this.mode === "over" && this.frames.length <= this.targetDepth || this.mode === "out" && this.frames.length < this.targetDepth;
    const requestedPause = Atomics.exchange(this.control, 1, 0) === 1;
    if (!breakpoint && !stepping && !requestedPause) return;
    const command = this.pause({ site, frames: this.frames.map(frame => ({ site: frame.site, locals: [...frame.locals] })), reason: breakpoint ? "breakpoint" : this.stoppedOnce ? "step" : "entry" });
    this.stoppedOnce = true; this.targetDepth = this.frames.length;
    this.mode = command === 2 ? "into" : command === 3 ? "over" : command === 4 ? "out" : "continue";
  }
}
