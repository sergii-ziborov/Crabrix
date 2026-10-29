"use client";
import { useEffect, useRef, useState } from 'react';
import { RuntimeHostCore, type RuntimeEffect, type RuntimeHostContext, type RuntimeJobUpdate } from '@/lib/playground-runtime-host';
import { createRuntimeSigner } from '@/lib/playground-runtime-protocol';
import { publishRuntimePresence, remoteRuntimePresence } from '@/lib/playground-presence';
import { runtimeSource, runtimeSourceRevision } from '@/lib/playground-runtime-source';
import type { PlaygroundSession } from '@/lib/playground-session';
import type { PlaygroundDocument } from '@/lib/playground-document';
import type { Awareness } from 'y-protocols/awareness';
import type { useRustCompiler } from './use-rust-compiler';
import type { RuntimeAction } from '@/lib/playground-runtime-authority';
type Compiler = ReturnType<typeof useRustCompiler>;
export function useRuntimeHost(session: PlaygroundSession | null, awareness: Awareness, source: () => PlaygroundDocument, compiler: Compiler) {
  const latest = useRef({source,compiler}); latest.current={source,compiler};
  const [notice,setNotice]=useState('');
  const [status,setStatus] = useState<ReturnType<RuntimeHostCore['drain']> & {fingerprint:string}>();
  const actions=useRef<{allow:(controller:string,requestID:string,operations:RuntimeAction[])=>Promise<void>;revoke:()=>void}|undefined>(undefined);
  useEffect(()=>{
    if(!session) return;
    let stopped=false, core:RuntimeHostCore, signer:Awaited<ReturnType<typeof createRuntimeSigner>>, queue=Promise.resolve(), connection=0;
    let active:string|undefined, activeRevision='', lastLocal:unknown, seen=new Map<number,number>(), lastVisible=document.visibilityState==='visible';
    const stop=()=>{if(active)latest.current.compiler.stopOwned(active);};
    async function context():Promise<RuntimeHostContext>{
      const s=latest.current.source(), c=latest.current.compiler, {paths}=runtimeSource(s);
      return {room:session!.link.id,target:signer.fingerprint,scope:session!.peer+':'+connection,revision:await runtimeSourceRevision(s),editCapability:session!.link.access,expires:session!.link.expiresAt,foreground:document.visibilityState==='visible',connected:session!.connected&&!session!.stopped,editConfirmed:session!.runtimeEditConfirmed,ready:c.ready,busy:c.activity!=='idle',name:'Crabrix · Browser',debug:crossOriginIsolated&&typeof SharedArrayBuffer!=='undefined',profileReady:!paths.some(p=>['cargo.toml','build.rs'].includes(p.split('/').at(-1)!.toLowerCase())),paths,lines:paths.map(p=>s.files[p].split('\n').length)};
    }
    async function flush(){
      const reply=core.drain(); if(stopped) return;
      setStatus({...reply,fingerprint:signer.fingerprint});
      for(const effect of reply.effects.filter(e=>e.type!=='start')) apply(effect);
      try {
      for(const p of reply.publications){
        const envelope=await signer.sign(p.fields,JSON.parse(p.payloadJSON),{...(p.proof?{editCapability:session!.link.access}:{})});
        if(!stopped)publishRuntimePresence(awareness,envelope);
      }
      } catch(error) {for(const effect of reply.effects.filter(e=>e.type==='start'))core.update(effect.job,{state:'finished',succeeded:false,stage:'Start acknowledgement could not be published; no code executed'});throw error;}
      for(const effect of reply.effects.filter(e=>e.type==='start'))apply(effect);
    }
    function enqueue(work:()=>Promise<void>){queue=queue.then(async()=>{if(!stopped&&core)await work();}).catch(error=>{if(!stopped)setNotice(error instanceof Error?error.message:'Local runtime is unavailable');});return queue;}
    function update(id:string,value:RuntimeJobUpdate){void enqueue(async()=>{core.tick(await context());core.update(id,value);await flush();});}
    function apply(effect:RuntimeEffect){
      const c=latest.current.compiler;
      if(effect.type==='start'){
        active=effect.job; activeRevision=effect.revision;
        try{c.start(effect.operation as RuntimeAction,latest.current.source(),'',{id:effect.job,update:value=>{if(value.state==='finished'&&active===effect.job)active=undefined;update(effect.job,value);}});}
        catch(error){active=undefined;update(effect.job,{state:'finished',succeeded:false,stage:error instanceof Error?error.message:'Shared start failed'});}
      }else if(effect.type==='stop'){if(active===effect.job)c.stopOwned(effect.job);else update(effect.job,{state:'finished',succeeded:false,stage:'Unstarted job stopped'});}
      else if(effect.type==='step'||effect.type==='continue')c.commandOwned(effect.job,effect.type==='continue'?'continue':effect.mode as 'into'|'over'|'out');
      else if(effect.type==='breakpoints'){
        const paths=runtimeSource(latest.current.source()).paths, points:Record<string,number[]>={};
        for(const [file,line]of effect.points??[])if(paths[file]) (points[paths[file]]??=[]).push(line);
        c.breakpointsOwned(effect.job,points);
      }
    }
    const changed=()=>{void enqueue(async()=>{
      const ctx=await context(); if(active&&activeRevision!==ctx.revision)stop(); core.tick(ctx);
      const result=latest.current.compiler.result;
      if(result&&result!==lastLocal){lastLocal=result;if(!result.shared)core.clearOutput();if(result.execution && !result.shared && result.sourceRevision===ctx.revision)core.reportLocal(ctx.revision,{stdout:result.execution.stdout,stderr:result.execution.stderr+(result.execution.trap??''),succeeded:result.execution.exitCode===0&&!result.execution.trap,exitCode:result.execution.exitCode});}
      const peers=remoteRuntimePresence(awareness);const live=new Set(peers.map(p=>p.clientID));for(const id of seen.keys())if(!live.has(id))seen.delete(id);
      for(const frame of peers) if(seen.get(frame.clientID)!==frame.clock){seen.set(frame.clientID,frame.clock);try{await core.frame(JSON.parse(frame.envelope));}catch{}}
      await flush();
    });};
    const visibility=()=>{if(document.visibilityState!=='visible'){stop();if(core)core.revoke();}lastVisible=document.visibilityState==='visible';changed();};
    const reset=()=>{stop();connection++;seen.clear();void enqueue(async()=>{core.revoke();core=new RuntimeHostCore(await context());await flush();});};
    session.onRuntimeReset=reset;
    void(async()=>{while(!stopped&&!session.receivedState){await new Promise(resolve=>setTimeout(resolve,50));} if(stopped)return; signer=await createRuntimeSigner();if(stopped){signer.destroy();return;}core=new RuntimeHostCore(await context());
      actions.current={allow:async(controller,requestID,operations)=>{await enqueue(async()=>{core.tick(await context());core.allow(controller,requestID,operations);await flush();});},revoke:()=>{stop();void enqueue(async()=>{core.revoke();await flush();});}};
      awareness.on('change',changed);awareness.doc.on('afterTransaction',changed);document.addEventListener('visibilitychange',visibility);changed();
    })().catch(error=>{if(!stopped)setNotice(error instanceof Error?error.message:'Local runtime is unavailable');});
    const timer=setInterval(()=>{void enqueue(async()=>{if(session!.connected&&lastVisible&&session!.link.mode==='edit'&&!session!.runtimeEditConfirmed&&remoteRuntimePresence(awareness).some(frame=>frame.envelope.includes('permission-request')))try{await session!.confirmRuntimeEditAccess();}catch{};const ctx=await context();if(active&&activeRevision!==ctx.revision)stop();core.tick(ctx);await flush();});changed();},1000);
    return()=>{stopped=true;stop();clearInterval(timer);awareness.off('change',changed);awareness.doc.off('afterTransaction',changed);document.removeEventListener('visibilitychange',visibility);signer?.destroy();actions.current=undefined;};
  },[session,awareness]);
  return {status,notice,allow:(controller:string,requestID:string,operations:RuntimeAction[])=>actions.current?.allow(controller,requestID,operations),revoke:()=>actions.current?.revoke()};
}
