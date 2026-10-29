import type { Awareness } from 'y-protocols/awareness';
import { createRuntimeSigner, verifyRuntimeEnvelope, type RuntimeEnvelope, type RuntimeOperation } from './playground-runtime-protocol';
import { publishRuntimePresence, remoteRuntimePresence } from './playground-presence';
import { runtimeSourceRevision } from './playground-runtime-source';
import { base64url } from './playground-crypto';
import type { PlaygroundSession } from './playground-session';
import type { PlaygroundDocument } from './playground-document';

type Client = { fingerprint: string; revision: string; expires: number; name: string; profile: string; operations: string[]; ready: boolean; busy: boolean; permissions: string; editConfirmed: boolean; job?: {id:string;requestID:string;operation:string;state:string} };
type Grant = { id: string; expires: number; operations: string[] };
export class RuntimeController {
  private signer: Awaited<ReturnType<typeof createRuntimeSigner>>;
  private clients = new Map<string, Client>();
  private grants = new Map<string, Grant>();
  private waiting = new Map<string, { target: string; operation: string; revision: string; job: string; resolve: (value: any) => void; reject: (error: Error) => void }>();
  private seen = new Map<number, number>();
  private timer: ReturnType<typeof setInterval>;
  private stopped = false;
  private scanning = false;
  private warnings:string[]=[];
  private heartbeating = false;
  private publishing = Promise.resolve();
  private publishCount = 0;
  private publishedAt = 0;
  private requests = new Map<string,{target:string;revision:string;operations:string[]}>();
  private publish(envelope:RuntimeEnvelope) {
    if(this.publishCount>=16) return Promise.reject(new Error('Runtime transport is busy.'));
    this.publishCount++;
    const next=this.publishing.then(async()=>{await new Promise(resolve=>setTimeout(resolve,Math.max(0,220-(Date.now()-this.publishedAt))));if(this.stopped)throw new Error('Runtime controller disconnected.');publishRuntimePresence(this.awareness,envelope);this.publishedAt=Date.now();});
    this.publishing=next.catch(()=>{});void next.finally(()=>{this.publishCount--;}).catch(()=>{});return next;
  }
  private constructor(private session: PlaygroundSession, private awareness: Awareness, private source: () => PlaygroundDocument, signer: Awaited<ReturnType<typeof createRuntimeSigner>>) {
    this.signer = signer; awareness.on('change', this.changed);
    this.timer = setInterval(() => { void this.heartbeat(); void this.scan(); }, 5000);
    session.onRuntimeReset = () => { this.clients.clear(); this.grants.clear(); this.requests.clear(); for (const pending of this.waiting.values()) pending.reject(new Error('Runtime connection changed.')); this.waiting.clear(); };
    void this.heartbeat(); void this.scan();
  }
  static async create(session: PlaygroundSession, awareness: Awareness, source: () => PlaygroundDocument) { return new RuntimeController(session, awareness, source, await createRuntimeSigner()); }
  private changed = () => { void this.scan(); };
  private async heartbeat() {
    if(this.heartbeating)return;this.heartbeating=true;
    try {
      if (this.stopped || !this.session.connected || !this.session.runtimeEditConfirmed) return;
      const envelope = await this.signer.sign({ kind:'capabilities',room:this.session.link.id,target:'',requestID:base64url(crypto.getRandomValues(new Uint8Array(18))),operation:'discover' }, { role:'controller',name:'Claude · MCP' }, { editCapability:this.session.link.access });
      if (!this.stopped) await this.publish(envelope);
      for(const [requestID,request] of this.requests){
        const packet=await this.signer.sign({kind:'permission-request',room:this.session.link.id,target:request.target,requestID,operation:'grant',revision:request.revision},{name:'Claude · MCP',operations:request.operations},{editCapability:this.session.link.access});
        await this.publish(packet);
      }
    } catch { /* View access and reconnecting never imply execution permission. */ }
    finally {this.heartbeating=false;}
  }
  private async scan() {
    if (this.scanning || this.stopped) return; this.scanning = true;
    try {
      const peers=remoteRuntimePresence(this.awareness), live=new Set(peers.map(p=>p.clientID));for(const id of this.seen.keys())if(!live.has(id))this.seen.delete(id);
      for (const item of peers) {
        if (this.seen.get(item.clientID) === item.clock) continue; this.seen.set(item.clientID,item.clock);
        try {
          const frame = await verifyRuntimeEnvelope(JSON.parse(item.envelope),{room:this.session.link.id,editCapability:this.session.link.access});
          if (this.stopped) return;
          const p = frame.payload as any, h=frame.header;
          if (h[1] === 'capabilities' && p?.role === 'host' && typeof p.name === 'string' && p.name.length <= 60 && p.profile === 'shared-std-v1' && Array.isArray(p.operations) && p.operations.every((op:unknown)=>['check','build','run','debug'].includes(String(op))) && typeof p.ready === 'boolean' && typeof p.busy === 'boolean' && typeof p.editConfirmed === 'boolean') {
            if(p.permissions!=='granted')this.grants.delete(frame.sender);
            if (this.clients.has(frame.sender) || this.clients.size < 16) this.clients.set(frame.sender,{fingerprint:frame.sender,revision:h[7],expires:h[11],name:p.name,profile:p.profile,operations:p.operations,ready:p.ready,busy:p.busy,permissions:p.permissions,editConfirmed:p.editConfirmed,...(p.job?.controller===this.signer.fingerprint && typeof p.job.id==='string' && /^[A-Za-z0-9_-]{16,64}$/.test(p.job.id) && typeof p.job.requestID==='string' && ['check','build','run','debug'].includes(p.job.operation) && ['working','paused','finished'].includes(p.job.state)?{job:{id:p.job.id,requestID:p.job.requestID,operation:p.job.operation,state:p.job.state}}:{})});
          } else if (h[1] === 'response' && h[4] === this.signer.fingerprint && frame.editAccessProved) {
            const pending=this.waiting.get(h[5]);
            if (!pending || pending.target!==frame.sender || pending.operation!==h[6] || (h[6]!=='grant' && pending.revision!==h[7]) || (pending.job && pending.job!==h[8])) continue;
            if (h[6]==='grant' && p.ok===true && typeof p.grant==='string' && /^[A-Za-z0-9_-]{16,64}$/.test(p.grant) && Number.isSafeInteger(p.expires) && Array.isArray(p.operations) && p.operations.length>0 && p.operations.length<=4 && new Set(p.operations).size===p.operations.length && p.operations.every((op:unknown)=>['check','build','run','debug'].includes(String(op))) && p.expires>Date.now() && p.expires<=Math.min(Date.now()+605000,this.session.link.expiresAt)) this.grants.set(frame.sender,{id:p.grant,expires:p.expires,operations:p.operations});
            this.waiting.delete(h[5]); this.requests.delete(h[5]); pending.resolve({...p,job:h[8]||p.job,sourceRevision:h[7]});
          }
        } catch(error) { const warning=error instanceof Error?error.message:'Invalid runtime presence';if(!this.warnings.includes(warning))this.warnings=[...this.warnings,warning].slice(-8); }
      }
      for (const [key,value] of this.clients) if(value.expires<=Date.now()) this.clients.delete(key);
    } finally { this.scanning=false; }
  }
  status() {
    return {controller:this.signer.fingerprint,warnings:this.warnings,clients:[...this.clients.values()].filter(c=>c.expires>Date.now()).map(client=>({...client,grant:this.grants.get(client.fingerprint)?.expires!>Date.now()?this.grants.get(client.fingerprint):null})),execution:'Selected client only; no backend execution. Verify controller/device keys and allow operations in Share on that client.'};
  }
  async request(target: string,operations:string[]) {
    await this.session.confirmRuntimeEditAccess();
    const revision=await runtimeSourceRevision(this.source()), requestID=base64url(crypto.getRandomValues(new Uint8Array(18)));
    const envelope=await this.signer.sign({kind:'permission-request',room:this.session.link.id,target,requestID,operation:'grant',revision},{name:'Claude · MCP',operations},{editCapability:this.session.link.access});
    // The acknowledgement may arrive long after the tool returns, while the
    // human chooses operations locally. Keep a bounded pending grant listener.
    if(this.waiting.size>=8) throw new Error('Too many pending runtime requests.');
    const timeout=setTimeout(()=>{this.waiting.delete(requestID);this.requests.delete(requestID);},120_000);
    this.waiting.set(requestID,{target,operation:'grant',revision,job:'',resolve:()=>clearTimeout(timeout),reject:()=>clearTimeout(timeout)});
    this.requests.set(requestID,{target,revision,operations});
    await this.publish(envelope);
    return {pending:true,controller:this.signer.fingerprint,target,requestID,instructions:'Open Share Playground on the selected device/browser, compare this controller key, choose operations and press Allow. Poll runtime clients for the grant; no code has executed.'};
  }
  async command(target:string,operation:RuntimeOperation,revision:string,job='',arguments_:Record<string,unknown>={}) {
    const grant=this.grants.get(target);
    if(!grant||grant.expires<=Date.now()) throw new Error('No current grant from this client. Request access and let the user allow it on the target.');
    const requestID=base64url(crypto.getRandomValues(new Uint8Array(18)));
    const envelope=await this.signer.sign({kind:'command',room:this.session.link.id,target,requestID,operation,revision,job},{grant:grant.id,...arguments_},{editCapability:this.session.link.access});
    return this.exchange(envelope,target,operation,revision,job);
  }
  private async exchange(envelope:RuntimeEnvelope,target:string,operation:string,revision:string,job:string):Promise<any> {
    if(this.waiting.size>=8) throw new Error('Too many pending runtime commands.');
    const requestID=envelope.header[5];
    return new Promise((resolve,reject)=>{
      const timeout=setTimeout(()=>{clearInterval(retry);this.waiting.delete(requestID);reject(new Error('Client acknowledgement timed out. Poll clients/job status before deciding whether to start a new job.'));},10_000);
      const retry=setInterval(()=>{if(!this.stopped) void this.publish(envelope).catch(()=>{})},1500);
      this.waiting.set(requestID,{target,operation,revision,job,resolve:value=>{clearTimeout(timeout);clearInterval(retry);resolve(value);},reject:error=>{clearTimeout(timeout);clearInterval(retry);reject(error);}});
      void this.publish(envelope).catch(error=>{this.waiting.delete(requestID);clearTimeout(timeout);clearInterval(retry);reject(error);});
    });
  }
  close(){this.stopped=true;clearInterval(this.timer);this.awareness.off('change',this.changed);for(const pending of this.waiting.values())pending.reject(new Error('Runtime controller disconnected.'));this.waiting.clear();this.requests.clear();this.grants.clear();this.clients.clear();this.signer.destroy();}
}
