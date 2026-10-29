import {test} from 'node:test';
import assert from 'node:assert/strict';
import {RuntimeHostCore,type RuntimeHostContext} from '../../../site/lib/playground-runtime-host';
import {createRuntimeSigner,verifyRuntimeEnvelope,type RuntimeOperation} from '../../../site/lib/playground-runtime-protocol';
const room='r'.repeat(24),revision='a'.repeat(64),edit='A'.repeat(43);
async function fixture(){
 const controller=await createRuntimeSigner(),target=await createRuntimeSigner();
 let ctx:RuntimeHostContext={room,target:target.fingerprint,scope:'project-connection-1',revision,editCapability:edit,expires:Date.now()+3600000,foreground:true,connected:true,editConfirmed:true,ready:true,busy:false,name:'Crabrix',debug:true,profileReady:true,paths:['main.rs'],lines:[20]};
 const host=new RuntimeHostCore(ctx);let counter=0;
 const frame=async(kind:'command'|'permission-request'|'capabilities',operation:RuntimeOperation,payload:unknown,job='',source=ctx.revision,id='request-'+String(++counter).padStart(16,'0'))=>controller.sign({kind,operation,room,target:target.fingerprint,requestID:id,revision:source,job},payload,{editCapability:edit});
 async function allow(){await host.frame(await frame('permission-request','grant',{name:'Claude',operations:['check','build','run','debug']}));assert.equal(host.drain().effects.length,0);host.allow(controller.fingerprint,'request-'+String(counter).padStart(16,'0'),['check','build','run','debug']);const grant=host.drain().grant!;return grant;}
 return{controller,target,host,frame,allow,get ctx(){return ctx;},set(values:Partial<RuntimeHostContext>){ctx={...ctx,...values};host.tick(ctx);}};
}
test('host cannot execute without a local grant; start is acknowledged once and duplicate never runs twice',async()=>{
 const f=await fixture();try{
 await f.host.frame(await f.frame('command','run',{grant:'x'.repeat(32)}));assert.equal(f.host.drain().effects.length,0);
 const grant=await f.allow();const command=await f.frame('command','build',{grant:grant.id});await f.host.frame(command);const started=f.host.drain();assert.equal(started.effects.length,1);assert.equal(started.effects[0].type,'start');const job=started.effects[0].job;assert.equal(JSON.parse(started.publications.at(-1)!.payloadJSON).job,job);
 await f.host.frame(command);const duplicate=f.host.drain();assert.equal(duplicate.effects.length,0);assert.equal(JSON.parse(duplicate.publications.at(-1)!.payloadJSON).job,job);
 await f.host.frame(await f.frame('command','run',{grant:grant.id}));assert.equal(f.host.drain().effects.length,0);
 }finally{f.controller.destroy();f.target.destroy();}
});
test('result paging respects escaped Unicode budgets and debug commands need the paused owned job',async()=>{
 const f=await fixture();try{
 const grant=await f.allow();await f.host.frame(await f.frame('command','debug',{grant:grant.id}));const job=f.host.drain().effects[0].job;
 await f.host.frame(await f.frame('command','step',{grant:grant.id,mode:'into'},job));assert.equal(f.host.drain().effects.length,0);
 f.host.update(job,{state:'paused',stdout:'🦀\u0001'.repeat(18000),locals:[{name:'items',value:'"\\\u0001'.repeat(500)}]});
 await f.host.frame(await f.frame('command','stdout',{grant:grant.id},job));const page=JSON.parse(f.host.drain().publications.at(-1)!.payloadJSON);assert(page.next>0);assert(!/[\uD800-\uDBFF]$/.test(page.text));
 await f.host.frame(await f.frame('command','locals',{grant:grant.id},job));assert(f.host.drain().publications.every(p=>Buffer.byteLength(p.payloadJSON)<=768));
 await f.host.frame(await f.frame('command','breakpoints',{grant:grant.id,points:[[0,4]]},job));assert.equal(f.host.drain().effects[0]?.type,'breakpoints');
 await f.host.frame(await f.frame('command','step',{grant:grant.id,mode:'over'},job));assert.equal(f.host.drain().effects[0]?.type,'step');
 }finally{f.controller.destroy();f.target.destroy();}
});
test('background revocation stops only its own job, clears results and permits fresh grants instead of leaving an orphan busy job',async()=>{
 const f=await fixture();try{
 const grant=await f.allow();await f.host.frame(await f.frame('command','run',{grant:grant.id}));const job=f.host.drain().effects[0].job;
 f.set({foreground:false});const result=f.host.drain();assert.equal(result.effects[0].job,job);assert.equal(result.effects[0].type,'stop');assert.equal(result.grant,null);assert.equal(result.jobs.length,0);
 f.set({foreground:true});f.host.drain();const next=await f.allow();await f.host.frame(await f.frame('command','check',{grant:next.id}));assert.equal(f.host.drain().effects[0]?.type,'start');
 }finally{f.controller.destroy();f.target.destroy();}
});
test('source changes stop old owned work and unsupported manifest profiles refuse start without side effects',async()=>{
 const f=await fixture();try{
 const grant=await f.allow();f.set({profileReady:false});f.host.drain();await f.host.frame(await f.frame('command','run',{grant:grant.id}));const denied=f.host.drain();assert.equal(denied.effects.length,0);assert.equal(JSON.parse(denied.publications.at(-1)!.payloadJSON).ok,false);
 f.set({profileReady:true});f.host.drain();await f.host.frame(await f.frame('command','run',{grant:grant.id}));const job=f.host.drain().effects[0].job;
 f.set({revision:'b'.repeat(64)});assert.equal(f.host.drain().effects[0]?.job,job);
 await f.host.frame(await f.frame('command','stdout',{grant:grant.id},job,revision));assert.equal(JSON.parse(f.host.drain().publications.at(-1)!.payloadJSON).ok,false);
 }finally{f.controller.destroy();f.target.destroy();}
});

test('other participant output is display only, supports view links and cannot start or stop any compiler',async()=>{
 const f=await fixture(), peer=await createRuntimeSigner();try{
 f.set({editCapability:'V'.repeat(43),editConfirmed:false});f.host.drain();
 const broadcast=async(id:string,source=revision,text='hello 🦀')=>peer.sign({kind:'capabilities',room,target:'',requestID:'output-request-123456',operation:'discover',revision:source},{role:'host',name:'Other iPad',profile:'shared-std-v1',output:{id,stdout:text,stderr:'',truncated:false,succeeded:true,exitCode:0}},{editCapability:edit});
 const packet=await broadcast('output-report-123456');await f.host.frame(packet);let state=f.host.drain();assert.equal(state.effects.length,0);assert.equal(state.jobs.length,0);assert.equal(state.grant,null);assert.equal(state.sharedOutput?.stdout,'hello 🦀');
 await f.host.frame(await broadcast('output-report-223456','b'.repeat(64)));assert.equal(f.host.drain().sharedOutput?.id,'output-report-123456');
 f.set({busy:true});f.host.drain();const whileBusy=await broadcast('output-report-323456');await f.host.frame(whileBusy);assert.equal(f.host.drain().sharedOutput,null);
 f.set({busy:false});f.host.drain();await f.host.frame(whileBusy);assert.equal(f.host.drain().sharedOutput,null,'repeated preview cannot clobber own newer result');
 const damaged={...structuredClone(packet),signature:(packet.signature[0]==='A'?'B':'A')+packet.signature.slice(1)};await assert.rejects(f.host.frame(damaged));assert.equal(f.host.drain().effects.length,0);
 }finally{f.controller.destroy();f.target.destroy();peer.destroy();}
});
test('wrong-target commands are silently ignored even with a valid room MAC and never execute',async()=>{
 const f=await fixture(), other=await createRuntimeSigner();try{
 const grant=await f.allow();const command=await f.controller.sign({kind:'command',room,target:other.fingerprint,requestID:'wrong-target-123456',operation:'run',revision},{grant:grant.id},{editCapability:edit});await f.host.frame(command);const result=f.host.drain();assert.equal(result.effects.length,0);assert.equal(result.publications.length,0);assert.equal(result.jobs.length,0);
 }finally{f.controller.destroy();f.target.destroy();other.destroy();}
});
test('lost grant acknowledgment is retried without extending expiry or replacing the grant with capabilities',async()=>{
 const f=await fixture();try{
 const request=await f.frame('permission-request','grant',{name:'Claude',operations:['run']});await f.host.frame(request);f.host.drain();f.host.allow(f.controller.fingerprint,request.header[5],['run']);const first=f.host.drain(), grant=first.grant!;
 await f.host.frame(request);f.host.tick(f.ctx);const repeat=f.host.drain();assert.equal(repeat.grant?.id,grant.id);assert.equal(repeat.grant?.expires,grant.expires);assert.equal(repeat.publications.length,1);assert.equal(repeat.publications[0].fields.kind,'response');
 }finally{f.controller.destroy();f.target.destroy();}
});
test('local report is bounded, source-bound and broadcasts no execution effects; full owned output remains paged',async()=>{
 const f=await fixture();try{
 f.host.reportLocal(revision,{stdout:'🦀\u0001'.repeat(5000),stderr:'x'.repeat(1000),succeeded:true,exitCode:0});f.host.tick(f.ctx);const state=f.host.drain();assert.equal(state.effects.length,0);const caps=state.publications.find(p=>p.fields.kind==='capabilities')!;assert(Buffer.byteLength(caps.payloadJSON)<=768);assert.equal(JSON.parse(caps.payloadJSON).output.truncated,true);
 f.set({revision:'b'.repeat(64)});f.host.drain();f.host.reportLocal(revision,{stdout:'old'});assert.equal(f.host.drain().sharedOutput,null);
 }finally{f.controller.destroy();f.target.destroy();}
});

test('read-only signature verification can never authorize control even when a valid edit proof is attached',async()=>{
 const f=await fixture();try{
 const packet=await f.frame('permission-request','grant',{name:'Claude',operations:['run']});
 const readonly=await verifyRuntimeEnvelope(packet,{room,readOnly:true});assert.equal(readonly.editAccessProved,false);
 await assert.rejects(verifyRuntimeEnvelope(packet,{room,readOnly:true,requireEditProof:true,editCapability:edit}));
 }finally{f.controller.destroy();f.target.destroy();}
});

test('a valid grant never implicitly prepares a compiler or acquires packages',async()=>{
 const f=await fixture();try{const grant=await f.allow();f.set({ready:false});f.host.drain();await f.host.frame(await f.frame('command','run',{grant:grant.id}));const result=f.host.drain();assert.equal(result.effects.length,0);assert.equal(result.jobs.length,0);assert.match(JSON.parse(result.publications.at(-1)!.payloadJSON).reason,/no download/);}finally{f.controller.destroy();f.target.destroy();}
});

test('a delayed compiler stage cannot unpause the owned debugger',async()=>{
 const f=await fixture();try{const grant=await f.allow();await f.host.frame(await f.frame('command','debug',{grant:grant.id}));const job=f.host.drain().effects[0].job;f.host.update(job,{state:'paused',locals:[{name:'text',value:'crab'}]});f.host.update(job,{state:'progress',stage:'Old compiler stage'});await f.host.frame(await f.frame('command','locals',{grant:grant.id},job));const result=f.host.drain();assert.equal(result.jobs[0].state,'paused');assert.equal(JSON.parse(result.publications.at(-1)!.payloadJSON).items[0].value,'crab');assert.equal(result.effects.length,0);}finally{f.controller.destroy();f.target.destroy();}
});
