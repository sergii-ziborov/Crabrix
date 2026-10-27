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
  ['String Vec and non-Debug nested structs',`struct Address { city: String } struct Person { name: String, scores: Vec<u32>, address: Address } fn main(){let mut text=String::from("Ferris 🦀\\n");text.push_str("Rust");let mut numbers=vec![1u32,2,3];numbers.push(42);let person=Person{name:String::from("Crab"),scores:vec![7,8],address:Address{city:String::from("Kyiv")}};println!("{} {} {}",text,numbers.len(),person.name);}`],
  ['Vec of structs and nested containers',`struct Row{label:String, flags:Vec<bool>} struct Table{rows:Vec<Row>, note:Option<String>, nums:[u32;3]} fn main(){let table=Table{rows:vec![Row{label:String::from("nested row"),flags:vec![true,false]}],note:Some(String::from("present")),nums:[1,2,3]};println!("{}",table.rows.len());}`],
  ['bounded previews never call user Debug',`struct Item { text: String, data: Vec<i32> } impl std::fmt::Debug for Item {fn fmt(&self,_:&mut std::fmt::Formatter<'_>)->std::fmt::Result {panic!("user Debug must never run")}} fn main(){let huge=vec![9u32;100000];let long=String::from("🦀").repeat(10000);let item=Item{text:String::from("safe"),data:vec![1,2]};println!("{} {} {}",huge.len(),long.len(),item.text);}`],
  ['tuple unit and unsupported fields',`struct Foreign; struct Pair(String,u32); struct Record { opaque: std::cell::Cell<i32>, label: String } fn main(){let pair=Pair(String::from("pair"),42);let unit=Foreign;let record=Record{opaque:std::cell::Cell::new(8),label:String::from("kept")};println!("{} {} {}",pair.0,pair.1,record.label);}`],
  ['aggregate moves partial moves and mutable borrows',`struct S{a:String,b:String} fn take(_:String){} fn main(){let value=String::from("moved");take(value);let s=S{a:String::from("a"),b:String::from("b")};let a=s.a;let mut v=vec![1,2];let p=&mut v;p.push(3);println!("{a} {} {}",s.b,v.len());}`],
  ['async polls interleave and cancel',`use std::{future::Future,task::{Poll,Context,Waker}}; async fn task(id:u32)->u32 { let text=String::from("async crab");let values=vec![id,42];let mut yielded=false;std::future::poll_fn(|cx|{if yielded{Poll::Ready(())}else{yielded=true;cx.waker().wake_by_ref();Poll::Pending}}).await;println!("{text} {}",values.len());id+1 } fn main(){let mut a=Box::pin(task(1));let mut b=Box::pin(task(2));let mut cancelled=Box::pin(task(99));let mut cx=Context::from_waker(Waker::noop());assert!(a.as_mut().poll(&mut cx).is_pending());assert!(b.as_mut().poll(&mut cx).is_pending());assert!(cancelled.as_mut().poll(&mut cx).is_pending());drop(cancelled);assert_eq!(a.as_mut().poll(&mut cx),Poll::Ready(2));assert_eq!(b.as_mut().poll(&mut cx),Poll::Ready(3));println!("async complete");}`],
  ['async blocks nested await returns and Send',`use std::{future::Future,task::{Poll,Context,Waker}}; fn drive<F:Future>(f:F)->F::Output{let mut f=Box::pin(f);let mut cx=Context::from_waker(Waker::noop());loop{if let Poll::Ready(v)=f.as_mut().poll(&mut cx){return v;}}} fn send<T:Send>(_:&T){} async fn add(n:u32)->u32 {if n==0{return 7;}let value=async move {let text=String::from("nested");println!("{text}");n+1}.await;value+1} fn main(){let task=async {add(3).await};send(&task);println!("{} {}",drive(task),drive(add(0)));}`],
  ['async expression at statement start',`use std::{future::Future,task::{Poll,Context,Waker}}; fn drive<F:Future>(f:F)->F::Output {let mut f=Box::pin(f);let mut cx=Context::from_waker(Waker::noop());loop{if let Poll::Ready(v)=f.as_mut().poll(&mut cx){return v;}}} async fn test()->u32{async{let n=3;println!("nested={n}");}.await;async{9}.await} fn main(){println!("{}",drive(test()));}`],
  ['packed and cfg fields stay opaque',`#[repr(packed)] struct Packed{a:u32} #[cfg(any())] struct Absent{field:Missing} struct Conditional{#[cfg(any())] absent:Missing, n:u32} fn main(){let packed=Packed{a:1};let conditional=Conditional{n:2};println!("ok");}`],
  ['unit tail'  ,'fn empty(){} fn main(){empty();let ready=true;println!("{ready}");}'],
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
    const locals=pauses.flatMap(p=>p.frames.flatMap(f=>f.locals));
    if(name==='String Vec and non-Debug nested structs'){
      assert.ok(locals.some(v=>v.name==='text' && v.value.includes('Ferris 🦀') && v.value.includes('Rust')),JSON.stringify(locals));
      assert.ok(locals.some(v=>v.name==='numbers' && v.value==='[len=4] [1, 2, 3, 42]'),JSON.stringify(locals));
      assert.ok(locals.some(v=>v.name==='person' && v.value.includes('name: "Crab"') && v.value.includes('city: "Kyiv"')),JSON.stringify(locals));
    }
    if(name==='Vec of structs and nested containers') assert.ok(locals.some(v=>v.name==='table' && v.value.includes('nested row') && v.value.includes('Some("present"')),JSON.stringify(locals));
    if(name==='bounded previews never call user Debug'){
      assert.ok(locals.some(v=>v.name==='huge' && v.value.includes('len=100000') && v.value.includes('…')));
      assert.ok(locals.some(v=>v.name==='item' && v.value.includes('text: "safe"')));
      assert.ok(locals.every(v=>v.value.length<=1024));
    }
    if(name.startsWith('async')) assert.ok(pauses.some(p=>['task','add','async block'].includes(p.site.function)), 'must pause inside async body');
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
