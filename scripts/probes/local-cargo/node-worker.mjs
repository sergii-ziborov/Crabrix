import {parentPort, workerData} from 'node:worker_threads';
import fs from 'node:fs';
import path from 'node:path';
console.log=()=>{};
const entries=new Map();let offline=false, requests=[];
globalThis.location=new URL('https://cargo-gate.invalid');
globalThis.caches={open:async()=>({match:async key=>entries.get(String(key))?.clone(),put:async(key,response)=>entries.set(String(key),response.clone()),delete:async key=>entries.delete(String(key))})};
globalThis.self={location:globalThis.location,postMessage:message=>parentPort.postMessage(message)};
globalThis.fetch=async url=>{
  if(offline)throw Error('NETWORK AFTER PREPARE: '+url);
  requests.push(String(url));
  const u=new URL(url);
  if(u.origin===location.origin && ['/playground-runtime/rustc.wasm.gz','/playground-runtime/sysroot.zip'].includes(u.pathname))return new Response(fs.readFileSync(path.join(workerData.publicRoot,u.pathname)));
  if(u.hostname==='raw.githubusercontent.com'){
    const name=u.pathname.split('/').at(-1),index=fs.readFileSync(workerData.indices.map(base=>path.join(base,u.pathname.split('/master/')[1])).find(file=>fs.existsSync(file)));
    const lines=index.toString().split('\0').filter(x=>x.startsWith('{"name":'));
    if(!lines.length)throw Error('No registry lines for '+name);
    return new Response(lines.join('\n'));
  }
  if(u.hostname==='static.crates.io') return new Response(fs.readFileSync(path.join(workerData.cache,path.basename(u.pathname))));
  throw Error('Forbidden network origin '+url);
};
await import(workerData.bundle);
parentPort.on('message',data=>{if(data.type==='offline'){offline=true;parentPort.postMessage({type:'offline',requests});}else self.onmessage({data});});
