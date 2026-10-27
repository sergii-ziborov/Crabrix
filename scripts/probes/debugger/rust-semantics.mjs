import { Worker } from 'node:worker_threads';
import { resolve } from 'node:path';
import { build } from '../../../site/node_modules/esbuild/lib/main.js';
import assert from 'node:assert/strict';
import { writeFile } from 'node:fs/promises';
await build({entryPoints:['site/workers/rust.worker.ts'],bundle:true,platform:'node',format:'esm',outfile:'build/debugger-20261027/rust-worker-node.mjs'});
const worker = new Worker(new URL('./node-worker.mjs',import.meta.url),{workerData:{bundle:resolve('build/debugger-20261027/rust-worker-node.mjs'),publicRoot:resolve('site/public')}});
let done, reject, control, pauses=[];
worker.on('error',error=>reject?.(error));
worker.on('message',message=>{
  if(message.type==='paused') { pauses.push(message); Atomics.store(control,0,2); Atomics.notify(control,0); }
  if(['ready','result','error'].includes(message.type)) done?.(message);
});
function job(data){return new Promise((yes,no)=>{done=yes;reject=no;worker.postMessage(data)})}
const samples=[
  ['recursion','fn fact(n:u32)->u32 {if n<2 {return 1;} n*fact(n-1)} fn main(){println!("{}",fact(5));}'],
  ['moves and shadowing','fn main(){let x=1; {let x=String::from("inner");let y=x;println!("{y}");} let x=2;println!("{x}");}'],
  ['borrow and late initialization','fn main(){let mut x=1;let p=&mut x;*p+=2;let late:i32;late=4;println!("{} {}",x,late);}'],
  ['const evaluation','const fn value()->i32{3} fn main(){const N:i32=2;let x=const {value()+2};println!("{} {}",x,N);}'],
  ['Unicode and JSON chars','fn main(){let α=4;let quote=\'"\';let nl=\'\\n\';println!("{α} {quote:?} {nl:?}");}'],
  ['return break continue','fn choose(n:i32)->i32{if n>1{return n;} 0} fn main(){let mut total=0;for i in 0..8{if i==2{continue;}if i==5{break;}total+=choose(i);}println!("{total}");}'],
  ['closure borrows','fn main(){let mut x=1;let mut apply=||{x+=2;};apply();println!("{x}");}'],
  ['match shadow binding','fn main(){let x=4;match Some(String::from("ok")){Some(x)=>{let moved=x;println!("{moved}");},None=>{println!("{x}");}}}'],
  ['if let shadow binding','fn main(){let x=4;if let Some(x)=Some(String::from("ok")){let y=x;println!("{y}");}println!("{x}");}'],
  ['nested modules','mod util; fn main(){let answer=util::add(2,3);println!("{answer}");}',{'util.rs':'pub fn add(a:i32,b:i32)->i32{let sum=a+b;sum}'}],
  ['unit tail','fn empty(){} fn main(){empty();let ready=true;println!("{ready}");}'],
];
const results=[];
try {
  assert.equal((await job({type:'initialize'})).type,'ready');
  for(const [name,source,supporting={}] of samples){
    const document={schemaVersion:1,name:'debug-gate',entryFile:'main.rs',edition:'2024',files:{'main.rs':source,...supporting}};
    const normal=await job({type:'run',document,stdin:''});assert.equal(normal.compilation?.exitCode,0,`${name}: normal ${JSON.stringify(normal)}`);
    control=new Int32Array(new SharedArrayBuffer((8192+5)*4));pauses=[];
    const debug=await job({type:'debug',document,stdin:'',control:control.buffer});
    assert.equal(debug.compilation?.exitCode,0,`${name}: Debug ${JSON.stringify(debug)}`);
    assert.equal(debug.execution?.exitCode,0,`${name}: ${JSON.stringify(debug)}`);
    assert.equal(debug.execution.stdout,normal.execution.stdout,`${name}: semantics changed`);
    assert.ok(pauses.length>0,`${name}: did not pause`);
    results.push({name,pauses:pauses.length,stdout:debug.execution.stdout});console.log('PASS',name,pauses.length,'real pauses');
  }
  for(const [name,source] of [
    ['statement attributes','fn main(){ #[cfg(any())] let hidden=1; println!("ok"); }'],
    ['compile-time column','fn main(){println!("{}",column!());}'],
  ]) {
    const document={schemaVersion:1,name:'debug-gate',entryFile:'main.rs',edition:'2024',files:{'main.rs':source}};
    const normal=await job({type:'run',document,stdin:''});assert.equal(normal.compilation?.exitCode,0);
    control=new Int32Array(new SharedArrayBuffer((8192+5)*4));
    const debug=await job({type:'debug',document,stdin:'',control:control.buffer});assert.equal(debug.type,'error',`${name}: must fail closed instead of changing source semantics`);
    results.push({name,debugUnavailable:true,normalRunWorks:true});console.log('PASS safe fallback',name);
  }
  await writeFile('build/debugger-20261027/rust-semantics-result.json',JSON.stringify({at:new Date().toISOString(),actualPinnedRustCompiler:true,backendExecution:false,results},null,2));
}finally{await worker.terminate()}
