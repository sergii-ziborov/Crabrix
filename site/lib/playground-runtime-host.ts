import { RuntimeAuthority, runtimeActions, type RuntimeAction, type RuntimeGrant, type RuntimeOwnedJob } from './playground-runtime-authority';
import { verifyRuntimeEnvelope, type RuntimeFields, type RuntimeOperation, type VerifiedRuntimeFrame } from './playground-runtime-protocol';
import { base64url } from './playground-crypto';
import { isWellFormedUTF16 } from './playground-document';

export type RuntimeHostContext = {
  room: string; target: string; scope: string; revision: string; editCapability: string; expires: number;
  foreground: boolean; connected: boolean; editConfirmed: boolean; ready: boolean; busy: boolean;
  name: string; debug: boolean; profileReady: boolean; paths: string[]; lines: number[];
};
export type RuntimePublication = { fields: RuntimeFields; payloadJSON: string; proof: boolean };
export type RuntimeEffect = { type: 'start' | 'stop' | 'step' | 'continue' | 'breakpoints'; job: string; revision: string; operation: string; mode?: string; points?: number[][] };
export type RuntimeJobUpdate = { state: 'working' | 'paused' | 'finished' | 'progress'; stage?: string; succeeded?: boolean; exitCode?: number | null; stdout?: string; stderr?: string; diagnostics?: unknown[]; locals?: unknown[]; site?: unknown; durationMs?: number };
export type SharedRuntimeOutput = { id: string; sender: string; name: string; revision: string; stdout: string; stderr: string; truncated: boolean; succeeded: boolean; exitCode: number | null };
type OutputPreview = Omit<SharedRuntimeOutput, 'sender'|'name'|'revision'>;
type Job = RuntimeOwnedJob & { requestID: string; controller: string; deadline: number; stopping?: boolean; stage: string; succeeded?: boolean; exitCode?: number | null; stdout: string; stderr: string; diagnostics: unknown[]; locals: unknown[]; site: unknown; durationMs: number; truncated: boolean };
const enc = new TextEncoder();
export function runtimeClip(text: string, bytes: number): string {
  if (!isWellFormedUTF16(text)) throw new Error('Invalid runtime text.');
  const data = enc.encode(text); if (data.length <= bytes) return text;
  let end = bytes; while (end > 0 && (data[end] & 192) === 128) end--;
  return new TextDecoder('utf-8', { fatal: true }).decode(data.subarray(0, end));
}
const object = (x: unknown): x is Record<string, unknown> => !!x && typeof x === 'object' && !Array.isArray(x);
function boundedJSON(value: unknown, max = 768) { const text = JSON.stringify(value); if (text === undefined || enc.encode(text).length > max || !isWellFormedUTF16(text)) throw new Error('Runtime page exceeds its budget.'); return text; }
function page(items: unknown[], cursor: number) {
  if (cursor > items.length) throw new Error('Invalid result cursor.');
  const output: unknown[] = []; let next = cursor;
  while (next < items.length) {
    try { boundedJSON({ ok: true, items: [...output, items[next]], next: next + 1 < items.length ? next + 1 : null }); }
    catch { if (!output.length) { let summary=runtimeClip(JSON.stringify(items[next]),400); while(enc.encode(JSON.stringify(summary)).length>500) summary=runtimeClip(summary,Math.max(0,enc.encode(summary).length-50)); output.push({truncated:true,summary}); next++; } break; }
    output.push(items[next++]);
  }
  return { ok: true, items: output, next: next < items.length ? next : null };
}
function textPage(text: string, cursor: number, truncated: boolean) {
  if (cursor > text.length || cursor > 0 && /[\uDC00-\uDFFF]/.test(text[cursor])) throw new Error('Invalid UTF-16 result cursor.');
  let part = runtimeClip(text.slice(cursor), 600);
  while (true) {
    const next = cursor + part.length, value = { ok: true, text: part, next: next < text.length ? next : null, truncated };
    try { boundedJSON(value); return value; } catch { if (!part) throw new Error('Invalid result page.'); part = runtimeClip(part, Math.max(0, enc.encode(part).length - 64)); }
  }
}

/** Same bounded governor in browser and native JavaScriptCore. Only local wrappers
 * may submit context/allow/job updates; a network packet enters exclusively frame(). */
export class RuntimeHostCore {
  private context: RuntimeHostContext;
  private authority: RuntimeAuthority;
  private jobs = new Map<string, Job>();
  private publications: RuntimePublication[] = [];
  private effects: RuntimeEffect[] = [];
  private replies = new Map<string, RuntimePublication>();
  private lastCapabilities = 0;
  private quietUntil = 0;
  private generation = 0;
  private requestsSeen = new Map<string,{id:string;hash:string}>();
  private ownOutput?: OutputPreview;
  private sharedOutput: SharedRuntimeOutput | null = null;
  private seenOutputs = new Map<string, number>();
  private approved?: {controller:string;id:string;hash:string;publication:RuntimePublication};
  constructor(context: RuntimeHostContext) {
    this.context = context;
    this.authority = new RuntimeAuthority(() => ({ ...this.context, busy: this.context.busy || [...this.jobs.values()].some(j => j.state !== 'finished'), job: id => this.jobs.get(id) }), (grant) => {
      for (const job of this.jobs.values()) if (job.grant === grant && job.state !== 'finished') this.stop(job);
      for (const [id, job] of this.jobs) if (job.grant === grant) this.jobs.delete(id);
      this.replies.clear(); this.requestsSeen.clear(); this.approved=undefined; this.generation++;
    });
  }
  private stop(job: Job) { if (job.stopping) return; job.stopping = true; this.effects.push({ type: 'stop', job: job.id, revision: job.revision, operation: job.operation }); job.stage = 'Stopping owned job'; }
  private publish(fields: RuntimeFields, payload: unknown, proof = true) {
    const value = { fields, payloadJSON: boundedJSON(payload), proof }; this.publications.push(value); return value;
  }
  private reply(frame: VerifiedRuntimeFrame, payload: unknown, job = frame.header[8]) {
    this.quietUntil=Date.now()+350;
    const value = this.publish({ kind: 'response', room: this.context.room, target: frame.sender, requestID: frame.header[5], operation: frame.header[6], revision: frame.header[7], job }, payload);
    if (this.replies.size < 2048) this.replies.set(frame.sender + ':' + frame.header[5], value);
  }
  tick(context: RuntimeHostContext) {
    if (this.context.revision !== context.revision) { this.ownOutput=undefined; this.sharedOutput=null; }
    this.context = context; this.authority.tick();
    if (context.busy) this.sharedOutput=null;
    for (const job of this.jobs.values()) {
      if (job.state !== 'finished' && (job.revision !== context.revision || job.deadline <= Date.now())) this.stop(job);
      if (job.revision !== context.revision && job.state === 'finished') this.jobs.delete(job.id);
    }
    if (context.connected && context.foreground && context.expires > Date.now() && Date.now() - this.lastCapabilities >= 5000 && Date.now() >= this.quietUntil) this.capabilities();
  }
  private capabilities() {
    this.lastCapabilities = Date.now(); const c = this.context, grant = this.authority.status().grant;
    const payload: Record<string,unknown> = {
      role: 'host', name: runtimeClip(c.name, 60), profile: 'shared-std-v1', operations: c.debug ? [...runtimeActions] : ['check','build','run'], ready: c.ready,
      busy: c.busy || [...this.jobs.values()].some(j => j.state !== 'finished'), permissions: grant ? 'granted' : 'off', editConfirmed: c.editConfirmed, stdinBytes: 0, jobLimitSeconds: 120,
    };
    const latest=[...this.jobs.values()].at(-1);
    if(latest && latest.revision===c.revision)payload.job={id:latest.id,requestID:latest.requestID,controller:latest.controller,operation:latest.operation,state:latest.state};
    if(this.ownOutput){
      const output={...this.ownOutput};
      while(true){try{boundedJSON({...payload,output});payload.output=output;break;}catch{output.truncated=true;if(!output.stdout&&!output.stderr)break;const key=output.stdout.length>=output.stderr.length?'stdout':'stderr';output[key]=runtimeClip(output[key],Math.max(0,enc.encode(output[key]).length-48));}}
    }
    this.publish({ kind: 'capabilities', room: c.room, target: '', requestID: base64url(crypto.getRandomValues(new Uint8Array(18))), operation: 'discover', revision: c.revision }, payload, c.editConfirmed);
  }
  allow(controller: string, requestID: string, operations: RuntimeAction[]) {
    this.generation++;
    const requested=this.requestsSeen.get(controller);
    const grant = this.authority.allow(controller, requestID, operations);
    const publication=this.publish({ kind: 'response', room: this.context.room, target: controller, requestID, operation: 'grant', revision: this.context.revision }, { ok: true, grant: grant.id, operations: grant.operations, expires: grant.expires, profile: 'shared-std-v1' });
    if(requested?.id===requestID)this.approved={controller,id:requestID,hash:requested.hash,publication};
    this.requestsSeen.clear();this.lastCapabilities = Date.now(); return grant;
  }
  revoke() { this.generation++; this.authority.revoke(); this.requestsSeen.clear(); this.lastCapabilities = 0; }
  async frame(envelope: unknown) {
    const c = this.context, generation = this.generation;
    // Host broadcasts are authenticated for display only. They can never gain
    // edit authority, even when a view-only link contains a valid peer MAC.
    const hint=(envelope as {header?:unknown[]})?.header;
    const display=Array.isArray(hint)&&hint[1]==='capabilities';
    const frame = await verifyRuntimeEnvelope(envelope, { room: c.room, ...(display ? {readOnly:true} : {editCapability:c.editCapability,requireEditProof:true}) });
    if (generation !== this.generation || c.scope !== this.context.scope || !this.context.foreground || !this.context.connected) return;
    if (frame.header[1] === 'capabilities') {
      if(object(frame.payload)&&frame.payload.role==='host') { this.observeOutput(frame); return; }
      const controller=await verifyRuntimeEnvelope(envelope,{room:c.room,editCapability:c.editCapability,requireEditProof:true});
      if(generation===this.generation && c.scope===this.context.scope)this.authority.observeController(controller); return;
    }
    if(frame.header[4]!==c.target)return;
    if (frame.header[1] === 'permission-request') {
      if(this.approved?.controller===frame.sender && this.approved.id===frame.header[5] && this.approved.hash===frame.header[12] && this.authority.status().grant?.controller===frame.sender){this.quietUntil=Date.now()+350;this.publications.push(this.approved.publication);return;}
      this.authority.receiveRequest(frame); if(this.requestsSeen.size<4||this.requestsSeen.has(frame.sender))this.requestsSeen.set(frame.sender,{id:frame.header[5],hash:frame.header[12]});return;
    }
    if (frame.header[1] !== 'command') return;
    const admission = this.authority.admit(frame);
    if (admission.kind === 'duplicate') { const old = this.replies.get(frame.sender + ':' + frame.header[5]); if (old) {this.quietUntil=Date.now()+350;this.publications.push(old);} return; }
    if (admission.kind === 'denied') { this.reply(frame, { ok: false, reason: admission.reason }); return; }
    try { this.command(frame); } catch (error) { this.reply(frame, { ok: false, reason: runtimeClip(error instanceof Error ? error.message : 'Unsupported runtime command.', 500) }); }
  }
  private command(frame: VerifiedRuntimeFrame) {
    const payload = frame.payload, op = frame.header[6];
    if (!object(payload)) throw new Error('Invalid runtime command.');
    const allowed = ['grant', ...(['stdout','stderr','diagnostics','locals'].includes(op) ? ['cursor'] : op === 'step' ? ['mode'] : op === 'breakpoints' ? ['points'] : [])];
    if (Object.keys(payload).some(key => !allowed.includes(key))) throw new Error('Unsupported command fields; native stdin and arbitrary evaluations are not supplied.');
    if (runtimeActions.includes(op as RuntimeAction)) {
      const c = this.context, grant = this.authority.status().grant;
      if (!grant || !c.profileReady) throw new Error('Shared execution supports manifest-free standard-library Rust and local modules. Use ordinary local Run for Cargo dependencies, build scripts or native libraries. No requirements were omitted.');
      if (op === 'debug' && !c.debug) throw new Error('Local Debug is unavailable in this client.');
      if (this.jobs.size >= 4) { const old = [...this.jobs.values()].find(j => j.state === 'finished'); if (old) this.jobs.delete(old.id); else throw new Error('The local job budget is full.'); }
      this.sharedOutput=null;this.ownOutput=undefined;
      const job: Job = { requestID:frame.header[5],controller:frame.sender,id: base64url(crypto.getRandomValues(new Uint8Array(24))), grant: grant.id, revision: c.revision, operation: op as RuntimeAction, state: 'working', deadline: Math.min(Date.now()+120_000,grant.expires), stage: 'Starting shared source only', stdout: '', stderr: '', diagnostics: [], locals: [], site: null, durationMs: 0, truncated: false };
      this.jobs.set(job.id, job); this.reply(frame, { ok: true, job: job.id, state: job.state, profile: 'shared-std-v1' }, job.id);
      this.effects.push({ type: 'start', job: job.id, revision: job.revision, operation: op }); return;
    }
    const job = this.jobs.get(frame.header[8]); if (!job) throw new Error('This owned job is unavailable.');
    const cursor = payload.cursor ?? 0; if (!Number.isSafeInteger(cursor) || (cursor as number) < 0) throw new Error('Invalid result cursor.');
    if (op === 'status') this.reply(frame, { ok: true, state: job.state, stage: job.stage, succeeded: job.succeeded, exitCode: job.exitCode, durationMs: job.durationMs, truncated: job.truncated });
    else if (op === 'stdout' || op === 'stderr') this.reply(frame, textPage(job[op], cursor as number, job.truncated));
    else if (op === 'diagnostics' || op === 'locals') this.reply(frame, page(job[op], cursor as number));
    else if (op === 'stop') { if (job.state !== 'finished') this.stop(job); this.reply(frame, { ok: true, state: job.state === 'finished' ? 'finished' : 'stopping' }); }
    else if (op === 'continue' || op === 'step') {
      if (op === 'step' && !['into','over','out'].includes(String(payload.mode))) throw new Error('Choose into, over or out.');
      job.state = 'working'; job.locals = []; this.effects.push({ type: op, job: job.id, revision: job.revision, operation: job.operation, ...(op === 'step' ? { mode: String(payload.mode) } : {}) }); this.reply(frame, { ok: true, state: 'working' });
    } else if (op === 'breakpoints') {
      if (!Array.isArray(payload.points) || payload.points.length > 16 || payload.points.some(point => !Array.isArray(point) || point.length !== 2 || !Number.isSafeInteger(point[0]) || !Number.isSafeInteger(point[1]) || point[0] < 0 || point[0] >= this.context.paths.length || !this.context.paths[point[0]].endsWith('.rs') || point[1] < 1 || point[1] > this.context.lines[point[0]])) throw new Error('Choose up to sixteen breakpoints in shared source.');
      this.effects.push({ type: 'breakpoints', job: job.id, revision: job.revision, operation: job.operation, points: payload.points as number[][] }); this.reply(frame, { ok: true });
    } else throw new Error('Unsupported runtime operation.');
  }
  update(jobID: string, update: RuntimeJobUpdate) {
    const job = this.jobs.get(jobID); if (!job || job.state === 'finished') return;
    if (!['working','paused','finished','progress'].includes(update.state)) throw new Error('Invalid local job update.');
    if(update.state==='progress' && job.state!=='working')return;
    if(update.state!=='progress')job.state = update.state;
    job.stage = runtimeClip(update.stage ?? job.stage, 180); while(enc.encode(JSON.stringify(job.stage)).length>256) job.stage=runtimeClip(job.stage,Math.max(0,enc.encode(job.stage).length-32));
    if (update.succeeded !== undefined) job.succeeded = update.succeeded;
    if (update.exitCode !== undefined) job.exitCode = update.exitCode;
    job.durationMs = Math.max(0, Math.min(120_000, Math.round(update.durationMs ?? job.durationMs)));
    for (const stream of ['stdout','stderr'] as const) if (update[stream] !== undefined) { const text = update[stream]!; job[stream] = runtimeClip(text, 65536); job.truncated ||= job[stream] !== text; }
    for (const key of ['diagnostics','locals'] as const) if (update[key]) {
      let bytes = 0; job[key] = [];
      for (const item of update[key]!.slice(0,64)) { const size = enc.encode(JSON.stringify(item)).length; if (bytes+size > 65536) { job.truncated = true; break; } job[key].push(item); bytes += size; }
    }
    job.site = update.site ?? null;
    if(update.state==='finished' && job.revision===this.context.revision && ['run','debug'].includes(job.operation))this.reportLocal(job.revision,job);
  }
  clearOutput() { this.sharedOutput=null; this.ownOutput=undefined; }
  /** Trusted local completion only. Never call this for a received output. */
  reportLocal(revision: string, value: Pick<RuntimeJobUpdate,'stdout'|'stderr'|'succeeded'|'exitCode'> & {id?:string;truncated?:boolean}) {
    if(revision!==this.context.revision || !this.context.profileReady || !this.context.connected)return;
    this.ownOutput={id:value.id??base64url(crypto.getRandomValues(new Uint8Array(18))),stdout:runtimeClip(value.stdout??'',1024),stderr:runtimeClip(value.stderr??'',1024),succeeded:value.succeeded===true,exitCode:Number.isSafeInteger(value.exitCode)?value.exitCode!:null,truncated:value.truncated===true||enc.encode(value.stdout??'').length>1024||enc.encode(value.stderr??'').length>1024};
    this.sharedOutput=null;this.lastCapabilities=0;
  }
  private observeOutput(frame: VerifiedRuntimeFrame) {
    const c=this.context,p=frame.payload;
    if(frame.sender===c.target||frame.header[4]!==''||frame.header[6]!=='discover'||frame.header[7]!==c.revision||!object(p)||p.profile!=='shared-std-v1'||typeof p.name!=='string'||!p.name.length||enc.encode(p.name).length>60||!object(p.output))return;
    const o=p.output;
    if(typeof o.id!=='string'||!/^[A-Za-z0-9_-]{16,64}$/.test(o.id)||typeof o.stdout!=='string'||typeof o.stderr!=='string'||typeof o.truncated!=='boolean'||typeof o.succeeded!=='boolean'||o.exitCode!==null&&!Number.isSafeInteger(o.exitCode))return;
    const key=frame.sender+':'+o.id;
    if(this.seenOutputs.has(key))return;
    if(this.seenOutputs.size>=64)this.seenOutputs.delete(this.seenOutputs.keys().next().value!);
    this.seenOutputs.set(key,frame.header[11]);
    if(c.busy||[...this.jobs.values()].some(j=>j.state!=='finished'))return;
    this.sharedOutput={id:o.id,sender:frame.sender,name:p.name,revision:c.revision,stdout:o.stdout,stderr:o.stderr,truncated:o.truncated,succeeded:o.succeeded,exitCode:o.exitCode as number|null};
  }
  drain() {
    const status = this.authority.status();
    return { ...status, sharedOutput:this.sharedOutput, jobs: [...this.jobs.values()].map(j => ({ id: j.id, revision: j.revision, operation: j.operation, state: j.state, stage: j.stage })), effects: this.effects.splice(0), publications: this.publications.splice(0) };
  }
}
