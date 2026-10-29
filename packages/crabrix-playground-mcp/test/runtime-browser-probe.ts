import assert from 'node:assert/strict';
import path from 'node:path';
import {mkdir,writeFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {Client} from '@modelcontextprotocol/client';
import {StdioClientTransport} from '@modelcontextprotocol/client/stdio';
const require=createRequire(import.meta.url);
const {chromium}=require('/Users/serhiirihgt/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const output=path.resolve('build/mcp-runtime-20261029/browser-runtime');await mkdir(output,{recursive:true});
const transport=new StdioClientTransport({command:process.execPath,args:[path.resolve('build/mcp-runtime-20261029/runtime-local-probe.mjs')],stderr:'pipe'});
const client=new Client({name:'Crabrix actual runtime qualification',version:'1'});
const browser=await chromium.launch({headless:true});const page=await browser.newPage({viewport:{width:1440,height:1000}});
const errors:string[]=[],posts:string[]=[];page.on('pageerror',(error:Error)=>errors.push(error.message));page.on('request',(request:any)=>{if(request.method()==='POST')posts.push(request.postData()??'');});
async function tool(name:string,args:Record<string,unknown>={}):Promise<any>{const result=await client.callTool({name,arguments:args});if(result.isError)throw new Error(JSON.stringify(result.content));return result.structuredContent;}
async function until(predicate:()=>Promise<boolean>,label:string,timeout=180000){const end=Date.now()+timeout;while(!await predicate()){if(Date.now()>end)throw new Error('Timed out: '+label);await new Promise(resolve=>setTimeout(resolve,1500));}}
async function poll(target:string,sourceRevision:string,job:string){let result:any;await until(async()=>{result=await tool('crabrix_runtime_job',{target,sourceRevision,job,operation:'status'});return result.state==='finished'||result.state==='paused';},'owned job result');return result;}
let created:any;
try{
 await client.connect(transport);created=await tool('crabrix_create',{name:'Local MCP runtime proof',files:{'main.rs':'fn main(){println!("mcp-local-runtime=42 🦀");}\n'},lifetimeMinutes:15});
 await page.goto(created.link);await page.waitForSelector('.cm-content');await page.getByRole('button',{name:'✓ Check',exact:true}).click();
 await page.waitForFunction(()=>!(document.querySelector('.pg-check')as HTMLButtonElement)?.disabled,null,{timeout:300000});
 console.log('Browser compiler explicitly prepared');
 let clients:any;await until(async()=>{clients=await tool('crabrix_runtime_clients');if(clients.warnings?.length)console.log('Runtime verification warnings:',JSON.stringify(clients.warnings));return clients.clients.some((c:any)=>c.ready);},'signed browser capabilities',30000);
 const target=clients.clients.find((c:any)=>c.ready).fingerprint,revision=clients.source.revision;
 const denied=await client.callTool({name:'crabrix_runtime_start',arguments:{target,sourceRevision:revision,operation:'run'}});assert.equal(denied.isError,true);
 await tool('crabrix_runtime_request',{target,operations:['check','build','run','debug']});await page.getByRole('button',{name:'Share Playground',exact:true}).click();
 await page.getByRole('button',{name:'Allow selected operations · 10 min',exact:true}).waitFor({timeout:20000});
 await page.screenshot({path:output+'/permission-before-allow.png',mask:[page.locator('.pg-share-body textarea')]});
 await page.getByRole('button',{name:'Allow selected operations · 10 min',exact:true}).click();
 await until(async()=>{clients=await tool('crabrix_runtime_clients');return !!clients.clients.find((c:any)=>c.fingerprint===target)?.grant;},'explicit browser grant');
 await page.getByRole('button',{name:'Close',exact:true}).click();
 const build=await tool('crabrix_runtime_start',{target,sourceRevision:revision,operation:'build'});assert.equal(build.ok,true);const built=await poll(target,revision,build.job);assert.equal(built.succeeded,true);
 const buildOut=await tool('crabrix_runtime_job',{target,sourceRevision:revision,job:build.job,operation:'stdout'});assert.equal(buildOut.text,'');console.log('Actual browser Build: main not executed');
 const run=await tool('crabrix_runtime_start',{target,sourceRevision:revision,operation:'run'});assert.equal(run.ok,true);const ran=await poll(target,revision,run.job);assert.equal(ran.succeeded,true);
 const stdout=await tool('crabrix_runtime_job',{target,sourceRevision:revision,job:run.job,operation:'stdout'});assert.match(stdout.text,/mcp-local-runtime=42 🦀/);console.log('Actual browser Run returned signed stdout');
 const file=await tool('crabrix_read_file',{path:'main.rs'});await tool('crabrix_apply_changes',{expectedRevision:file.revision,changes:[{path:'main.rs',text:'#[derive(Debug)]\nstruct Item { name: String, values: Vec<i32> }\nfn main(){\n let item = Item { name:String::from("crab"),values:vec![2,4,6] };\n println!("{:?}",item);\n}\n'}]});
 clients=await tool('crabrix_runtime_clients');const debugRev=clients.source.revision;await until(async()=>{clients=await tool('crabrix_runtime_clients');return clients.clients.find((c:any)=>c.fingerprint===target)?.revision===debugRev;},'new source acknowledged by browser');
 const debug=await tool('crabrix_runtime_start',{target,sourceRevision:debugRev,operation:'debug'});assert.equal(debug.ok,true);const paused=await poll(target,debugRev,debug.job);assert.equal(paused.state,'paused');
 for(let i=0;i<4;i++){const locals=await tool('crabrix_runtime_job',{target,sourceRevision:debugRev,job:debug.job,operation:'locals'});if(JSON.stringify(locals).includes('values'))break;await tool('crabrix_runtime_job',{target,sourceRevision:debugRev,job:debug.job,operation:'step',mode:'over'});await poll(target,debugRev,debug.job);}
 const locals=await tool('crabrix_runtime_job',{target,sourceRevision:debugRev,job:debug.job,operation:'locals'});assert.match(JSON.stringify(locals),/crab|values/);
 await tool('crabrix_runtime_job',{target,sourceRevision:debugRev,job:debug.job,operation:'stop'});await until(async()=>{const s=await tool('crabrix_runtime_job',{target,sourceRevision:debugRev,job:debug.job,operation:'status'});return s.state==='finished';},'owned Debug stop');
 assert(!posts.some(value=>value.includes('mcp-local-runtime=42')),'Source plaintext reached an HTTP request');assert.deepEqual(errors,[]);
 await page.screenshot({path:output+'/debug-stopped.png'});
 await writeFile(output+'/result.json',JSON.stringify({passed:true,localCompiler:true,noPlaintextSourcePosts:true,buildMainUntouched:true,runStdout:true,debugLocals:true,stop:true,errors},null,2));
 console.log('PASS official SDK → actual browser: permission, Build/Run, structured Debug locals/Step/Stop, encrypted-only relay');
}catch(error){await page.screenshot({path:output+'/failure.png',mask:[page.locator('.pg-share-body textarea')]}).catch(()=>{});console.log('Runtime UI:',(await page.locator('.pg-runtime-permissions').innerText().catch(()=>'' )).slice(0,1200));throw error;}finally{if(created)try{await tool('crabrix_end_room');}catch{}await client.close();await transport.close();await browser.close();}
