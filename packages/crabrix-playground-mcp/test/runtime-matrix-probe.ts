import assert from 'node:assert/strict';
import path from 'node:path';
import {createServer} from 'node:http';
import {mkdir,writeFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {Client} from '@modelcontextprotocol/client';
import {StdioClientTransport} from '@modelcontextprotocol/client/stdio';
const require=createRequire(import.meta.url),{chromium}=require('/Users/serhiirihgt/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const origin=process.env.CRABRIX_QA_ORIGIN??'http://127.0.0.1:3399',nonce='mcp-matrix-'+Date.now(),output=path.resolve('build/mcp-runtime-20261029/'+(process.env.CRABRIX_QA_LABEL??'matrix'));await mkdir(output,{recursive:true});
const client=new Client({name:'Crabrix three-client runtime matrix',version:'1'}),transport=new StdioClientTransport({command:process.execPath,args:[process.env.CRABRIX_QA_CLI??path.resolve('build/mcp-runtime-20261029/runtime-local-probe.mjs')],stderr:'pipe'});
let aborted=false;const browser=await chromium.launch({headless:true});process.once('SIGINT',()=>{aborted=true;void browser.close();});const page=await browser.newPage({viewport:{width:1440,height:1000}});await page.addInitScript(()=>{const original=Worker.prototype.postMessage;(window as any).__localWorkerStarts=[];Worker.prototype.postMessage=function(value:any,...rest:any[]){if(['run','debug','check','build'].includes(value?.type))(window as any).__localWorkerStarts.push(value.type);return original.call(this,value,...rest as [any]);};});const errors:string[]=[];page.on('pageerror',(error:Error)=>errors.push(error.message));
async function call(name:string,args:Record<string,unknown>={}):Promise<any>{const r=await client.callTool({name,arguments:args});if(r.isError)throw new Error(JSON.stringify(r.content));return r.structuredContent;}
async function until(check:()=>Promise<boolean>,label:string,seconds=180){const end=Date.now()+seconds*1000;while(!await check()){if(aborted)throw new Error('QA matrix cancelled');if(Date.now()>end)throw new Error('Matrix timeout: '+label);await new Promise(resolve=>setTimeout(resolve,1800));}}
let room:any,phase='initializing';const reports:{role:string;event:string}[]=[],results:Record<string,unknown>={};
const coordinator=createServer((request,response)=>{
 response.setHeader('Content-Type','application/json');response.setHeader('Cache-Control','no-store');
 if(request.url==='/fixture')response.end(JSON.stringify({url:room?.link,nonce,origin}));
 else if(request.url==='/phase')response.end(JSON.stringify({phase}));
 else if(request.url==='/event'){let body='';request.on('data',bytes=>{body+=bytes;if(body.length>4096)request.destroy();});request.on('end',()=>{const event=JSON.parse(body);reports.push(event);console.log('Native UI:',event.role,event.event);response.end('{}');});}
 else{response.statusCode=404;response.end('{}');}
});
async function job(target:string,sourceRevision:string,id:string){let value:any;await until(async()=>{value=await call('crabrix_runtime_job',{target,sourceRevision,job:id,operation:'status'});return value.state==='finished'||value.state==='paused';},'job completion/pause');return value;}
try{
 await client.connect(transport);
 room=await call('crabrix_create',{name:nonce,lifetimeMinutes:30,files:{'main.rs':`// shared editing markers\n// ${nonce}\n#[derive(Debug)]\nstruct Item { name: String, values: Vec<i32> }\nfn main(){\n let item = Item { name: String::from("crab"), values:vec![2,4,6] };\n println!("local-matrix 🦀 {:?}",item);\n}\n`}});
 await page.goto(room.link);await page.waitForSelector('.cm-content');await page.getByRole('button',{name:'✓ Check',exact:true}).click();await page.waitForFunction(()=>!(document.querySelector('.pg-check')as HTMLButtonElement)?.disabled,null,{timeout:300000});
 await new Promise<void>((resolve,reject)=>{coordinator.once('error',reject);coordinator.listen(3395,'127.0.0.1',resolve);});phase='ready';console.log('READY matrix: launch CrabrixRuntimeGate on phone and iPad');
 await until(async()=>reports.filter(r=>r.event==='opened-edited').length===2,'both native source editors',300);
 const file=await call('crabrix_read_file',{path:'main.rs'});assert.match(file.text,/from-phone/);assert.match(file.text,/from-pad/);
 const crab=file.text.indexOf('🦀');await call('crabrix_select',{path:'main.rs',anchor:crab,head:crab+2,expectedRevision:file.revision});await page.waitForSelector('.cm-ySelection');
 let clients:any;await until(async()=>{clients=await call('crabrix_runtime_clients');return clients.clients.filter((c:any)=>c.ready).length===3;},'three signed runtime clients');
 const browserClient=clients.clients.find((c:any)=>c.name.includes('Browser'));
 const phone=clients.clients.find((c:any)=>c.name.includes('iPhone')),pad=clients.clients.find((c:any)=>c.name.includes('iPad'));assert(phone&&pad&&browserClient);
 for(const target of [phone,pad,browserClient])await call('crabrix_runtime_request',{target:target.fingerprint,operations:['check','build','run','debug']});
 await page.getByRole('button',{name:'Share Playground',exact:true}).click();await page.getByRole('button',{name:'Allow selected operations · 10 min',exact:true}).waitFor({timeout:30000});await page.getByRole('button',{name:'Allow selected operations · 10 min',exact:true}).click();await page.getByRole('button',{name:'Close',exact:true}).click();
 await until(async()=>{clients=await call('crabrix_runtime_clients');return clients.clients.filter((c:any)=>c.grant).length===3;},'three explicit grants',300);
 const revision=clients.source.revision;
 for(const [role,selected]of [['phone',phone],['pad',pad],['browser',browserClient]]as const){
  const target=selected.fingerprint;
  const workerStarts=await page.evaluate(()=>(window as any).__localWorkerStarts.length);
  const build=await call('crabrix_runtime_start',{target,sourceRevision:revision,operation:'build'});assert.equal(build.ok,true,JSON.stringify(build));assert.equal((await job(target,revision,build.job)).succeeded,true);
  const buildOut=await call('crabrix_runtime_job',{target,sourceRevision:revision,job:build.job,operation:'stdout'});assert.equal(buildOut.text,'');
  const run=await call('crabrix_runtime_start',{target,sourceRevision:revision,operation:'run'});assert.equal(run.ok,true);assert.equal((await job(target,revision,run.job)).succeeded,true);const out=await call('crabrix_runtime_job',{target,sourceRevision:revision,job:run.job,operation:'stdout'});assert.match(out.text,/local-matrix 🦀/);
  phase='output-'+role;
  for(const other of ['phone','pad'].filter(other=>other!==role))await until(async()=>reports.some(r=>r.role===other&&r.event==='mirrored-'+role),'passive output '+role+' → '+other,60);
  if(role!=='browser'){await page.getByRole('tab',{name:'Output',exact:true}).click();await page.getByRole('article',{name:'Shared output'}).waitFor({timeout:30000});assert.equal(await page.evaluate(()=>(window as any).__localWorkerStarts.length),workerStarts,'another participant must never start this browser compiler');}
  const debug=await call('crabrix_runtime_start',{target,sourceRevision:revision,operation:'debug'});assert.equal(debug.ok,true);const firstPause=await job(target,revision,debug.job);assert.equal(firstPause.state,'paused',JSON.stringify(firstPause));
  let locals:any;
  for(let step=0;step<5;step++){
   locals=await call('crabrix_runtime_job',{target,sourceRevision:revision,job:debug.job,operation:'locals'});
   if(JSON.stringify(locals).includes('values'))break;
   await call('crabrix_runtime_job',{target,sourceRevision:revision,job:debug.job,operation:'step',mode:'over'});const state=await job(target,revision,debug.job);if(state.state==='finished')throw new Error('Debug finished before locals were inspected: '+JSON.stringify(state));
  }
  assert.match(JSON.stringify(locals),/crab|values/);
  const breakpoints=await call('crabrix_runtime_job',{target,sourceRevision:revision,job:debug.job,operation:'breakpoints',points:[[0,6]]});assert.equal(breakpoints.ok,true);
  await call('crabrix_runtime_job',{target,sourceRevision:revision,job:debug.job,operation:'stop'});await until(async()=>{const s=await call('crabrix_runtime_job',{target,sourceRevision:revision,job:debug.job,operation:'status'});return s.state==='finished';},'Debug stop '+role);
  results[role]={buildMainUntouched:true,runStdout:true,passiveOutputWithoutOtherExecution:true,debugLocals:true,step:true,breakpoints:true,stop:true};phase='verified-'+role;console.log('Verified real local compiler:',role);
  if(role!=='browser')await until(async()=>reports.some(r=>r.role===role&&r.event==='ui-verified'),'native original dock tabs '+role,60);
 }
 // Also exercise ordinary user Run: no MCP start command is involved.
 for(const origin of ['phone','browser']){
  const current=await call('crabrix_read_file',{path:'main.rs'});
  const text=current.text.replace(/local-matrix|manual-phone|manual-browser/g,'manual-'+origin);
  await call('crabrix_apply_changes',{expectedRevision:current.revision,changes:[{path:'main.rs',text}]});
  await until(async()=>{const state=await call('crabrix_runtime_clients');return state.clients.length===3 && state.clients.every((c:any)=>c.revision===state.source.revision);},'new manual source on every client');
  const beforeStarts=await page.evaluate(()=>(window as any).__localWorkerStarts.length);
  if(origin==='phone'){
   phase='manual-phone';await until(async()=>reports.some(r=>r.role==='phone'&&r.event==='manual-run-started'),'ordinary native Run tap',45);
  }else{await page.getByRole('button',{name:'▶ Run',exact:true}).click();}
  await page.getByRole('tab',{name:'Output',exact:true}).click();
  if(origin==='phone'){
   await until(async()=>{const preview=page.getByRole('article',{name:'Shared output'});return await preview.count()>0 && (await preview.innerText()).includes('manual-phone');},'ordinary native output reaches browser');
   assert.equal(await page.evaluate(()=>(window as any).__localWorkerStarts.length),beforeStarts,'native Run cannot start the browser compiler');
  }else{
   await until(async()=>await page.getByRole('button',{name:'▶ Run',exact:true}).isVisible() && (await page.locator('.pg-output').innerText()).includes('manual-browser'),'ordinary browser Run result');
   assert.equal(await page.evaluate(()=>(window as any).__localWorkerStarts.length),beforeStarts+1);
  }
  phase='output-manual-'+origin;
  for(const other of ['phone','pad'].filter(other=>other!==origin))await until(async()=>reports.some(r=>r.role===other&&r.event==='mirrored-manual-'+origin),'ordinary output '+origin+' → '+other,45);
  results['ordinary-'+origin]={actualLocalRun:true,passiveOutput:true,noOtherCompilerStart:true};
 }
 phase='complete';await new Promise(resolve=>setTimeout(resolve,5000));assert.deepEqual(errors,[]);await page.screenshot({path:output+'/browser.png'});await writeFile(output+'/result.json',JSON.stringify({passed:true,results,reports,errors},null,2));
 console.log('PASS SDK ↔ website ↔ phone + iPad: shared code/selection, explicit grants, actual local Build/Run/Debug and Stop');
}finally{phase='complete';if(room)try{await call('crabrix_end_room');}catch{}await client.close();await transport.close();await browser.close();coordinator.closeAllConnections();await new Promise<void>(resolve=>coordinator.close(()=>resolve()));}
