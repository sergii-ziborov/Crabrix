import {Worker} from 'node:worker_threads';
import fs from 'node:fs';import path from 'node:path';import assert from 'node:assert/strict';
import {build} from '../../../site/node_modules/esbuild/lib/main.js';
const root=path.resolve('.'),dir=path.join(root,'build/local-cargo-20261105'),cargo=path.join(process.env.HOME,'.cargo/registry');
fs.mkdirSync(dir,{recursive:true});
await build({entryPoints:[path.join(root,'scripts/probes/local-cargo/bridge.ts')],bundle:true,platform:'node',format:'esm',outfile:dir+'/worker.mjs'});
const fixtures=JSON.parse(fs.readFileSync(path.join(root,'CrabrixTests/CompilerCandidate/LocalCargoLessons.json')));
const worker=new Worker(new URL('./node-worker.mjs',import.meta.url),{workerData:{publicRoot:path.join(root,'site/public'),bundle:'file://'+dir+'/worker.mjs',cache:path.join(cargo,'cache',fs.readdirSync(cargo+'/cache')[0]),indices:fs.readdirSync(cargo+'/index').filter(x=>x.startsWith('index.crates.io-')).map(x=>path.join(cargo,'index',x,'.cache'))}});
let resolve,reject,timer,control,pauses=[];const receipt=[];
worker.on('message',m=>{if(m.type==='paused'){pauses.push(m);Atomics.store(control,0,2);Atomics.notify(control,0);}if(['ready','result','prepared','offline','error'].includes(m.type)){clearTimeout(timer);resolve?.(m);}});
worker.on('error',e=>reject?.(e));
const job=data=>new Promise((yes,no)=>{resolve=yes;reject=no;timer=setTimeout(()=>no(Error('timeout '+data.type)),180000);worker.postMessage(data);});
try{
 assert.equal((await job({type:'initialize'})).type,'ready');
 for(const f of fixtures){const prepared=await job({type:'prepare',document:f.document});assert.equal(prepared.type,'prepared',JSON.stringify(prepared));f.document.files[prepared.lockPath]=prepared.lockText;receipt.push({name:f.name,packages:prepared.packages});}
 fs.writeFileSync(dir+'/prepared-fixtures.json',JSON.stringify(fixtures,null,2)+'\n');
 const off=await job({type:'offline'});fs.writeFileSync(dir+'/network.json',JSON.stringify(off,null,2));
 const forbidden=await job({type:'run',document:fixtures[0].document,stdin:'',allowCargo:false});assert.equal(forbidden.type,'error');assert(forbidden.error.includes('manifest-free'));
 for(const [i,f]of fixtures.entries()){
  const run=await job({type:'run',document:f.document,stdin:''});assert.equal(run.compilation?.exitCode,0,JSON.stringify(run));assert.equal(run.execution?.exitCode,0,JSON.stringify(run));assert(run.execution.stdout.includes(f.expected));
  control=new Int32Array(new SharedArrayBuffer((8192+5)*4));pauses=[];
  const debug=await job({type:'debug',document:f.document,stdin:'',control:control.buffer});assert.equal(debug.compilation?.exitCode,0,JSON.stringify(debug));assert.equal(debug.execution?.exitCode,0,JSON.stringify(debug));assert.equal(debug.execution.stdout,run.execution.stdout);assert(pauses.length>0,'debug did not pause');
  receipt[i]={...receipt[i],run,debug,pauses:pauses.length};console.log(f.name,'run/debug passed',pauses.length);
 }
 fs.writeFileSync(dir+'/receipt.json',JSON.stringify({passed:true,offline:true,checks:receipt},null,2)+'\n');
}finally{clearTimeout(timer);await worker.terminate();}
