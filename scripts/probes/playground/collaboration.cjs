const { chromium } = require('/Users/serhiirihgt/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const {spawn} = require('node:child_process');
const {createInterface}=require('node:readline');
const fs=require('node:fs');
const root=process.cwd(), origin=process.env.CRABRIX_PLAYGROUND_ORIGIN||'http://127.0.0.1:3393';
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
function native(){const child=spawn(root+'/build/playground-20261027/native-probe',[root+'/Crabrix/Resources/PlaygroundCodec.js',origin],{stdio:['pipe','pipe','pipe']});const events=[];createInterface({input:child.stdout}).on('line',line=>{try{events.push(JSON.parse(line));if(events.at(-1).event==='error'||events.at(-1).event==='status')console.log('NATIVE',events.at(-1))}catch{console.log('NATIVE OUTPUT',line.slice(0,250))}});child.stderr.on('data',b=>console.log('NATIVE STDERR',b.toString().slice(0,500)));return{events,send:obj=>child.stdin.write(JSON.stringify(obj)+'\n'),child};}
async function wait(fn,label,ms=25000){const until=Date.now()+ms;while(Date.now()<until){const value=fn();if(value)return value;await sleep(100)}throw Error('Timeout: '+label)}
const source={schemaVersion:1,name:'interview',entryFile:'main.rs',edition:'2024',files:{'main.rs':'fn main() {\n    println!("shared");\n}\n'}};
const url=link=>origin+'/playground/room/'+link.id+'/#'+new URLSearchParams({key:link.key,access:link.access,expires:link.expiresAt,mode:link.mode});
(async()=>{let browser;const a=native(),b=native();try{
 a.send({type:'create',document:source});const ready=await wait(()=>a.events.find(e=>e.event==='ready')||a.events.find(e=>e.event==='error'),'native create');if(ready.error)throw Error(ready.error);const link=ready.link;
 b.send({type:'join',link});await wait(()=>b.events.find(e=>e.event==='document'),'native join');
 a.send({type:'edit',file:'main.rs',text:source.files['main.rs']+'// from native one\n'});await wait(()=>b.events.find(e=>e.document?.files['main.rs'].includes('from native one')),'native to native');console.log('PASS native → native source');
 b.send({type:'selection',file:'main.rs',anchor:3,length:4});await wait(()=>a.events.find(e=>e.selections?.some(s=>s.anchor===3&&s.head===7)),'native selection');console.log('PASS native → native selection');
 browser=await chromium.launch({headless:true});const context=await browser.newContext({viewport:{width:1440,height:1000}});const page=await context.newPage();page.on('pageerror',e=>console.log('PAGEERROR',e.message));await page.goto(url(link));await page.waitForSelector('.cm-content');await wait(async()=>false,'dummy',1).catch(()=>{});
 await page.waitForFunction(()=>document.querySelector('.cm-content')?.textContent.includes('from native one'));console.log('PASS native → website source');
 await page.locator('.cm-content').fill('fn main() { println!("browser edit"); }\n');await wait(()=>a.events.find(e=>e.document?.files['main.rs'].includes('browser edit')),'browser to native');console.log('PASS website → native source');
 const selectionStart=a.events.length;await page.bringToFront();await page.locator('.cm-content').focus();await page.keyboard.press('Meta+ArrowUp');await page.keyboard.down('Shift');await page.keyboard.press('ArrowRight');await page.keyboard.press('ArrowRight');await page.keyboard.up('Shift');await wait(()=>a.events.find((e,i)=>i>=selectionStart&&e.selections?.some(s=>Math.abs(s.head-s.anchor)===2)),'browser selection');console.log('PASS website → native selection');
 a.send({type:'selection',file:'main.rs',anchor:3,length:5});await page.waitForSelector('.cm-ySelection');console.log('PASS native → website selection rendering');
 await page.screenshot({path:root+'/build/playground-20261027/collaboration.png'});
 const context2=await browser.newContext();const page2=await context2.newPage();await page2.goto(url(link));await page2.waitForSelector('.cm-content');await page2.waitForFunction(()=>document.querySelector('.cm-content')?.textContent.includes('browser edit'));await page2.locator('.cm-content').fill('fn main() { println!("four participants"); }');await page.waitForFunction(()=>document.querySelector('.cm-content')?.textContent.includes('four participants'));console.log('PASS website ↔ website with two native peers');
 await context.setOffline(true);
 await page.locator('.cm-content').fill('fn main() { println!("four participants"); }\n// offline browser');
 a.send({type:'edit',file:'main.rs',text:'// online native\nfn main() { println!("four participants"); }'});
 await sleep(500);await context.setOffline(false);
 await page.waitForFunction(()=>document.querySelector('.cm-content')?.textContent.includes('online native')&&document.querySelector('.cm-content')?.textContent.includes('offline browser'),{timeout:25000});
 await wait(()=>b.events.find(e=>e.document?.files['main.rs'].includes('online native')&&e.document?.files['main.rs'].includes('offline browser')),'reconnected native convergence');
 console.log('PASS offline concurrent edits converge after reconnection');
 await page.reload();await page.waitForFunction(()=>document.querySelector('.cm-content')?.textContent.includes('offline browser'));console.log('PASS reload retains shared source without account');

 fs.writeFileSync(root+'/build/playground-20261027/collaboration-result.json',JSON.stringify({at:new Date().toISOString(),passed:['native-native source','native-native selection','native-web source','web-native source','web-native selection','native-web selection','web-web source','reconnect concurrent merge','shared page reload'],nativeImplementation:'same Swift transport, CryptoKit and bundled Yjs codec used in app',host:'macOS processes and Chromium; simulator UI separately required'},null,2));
}finally{a.send({type:'exit'});b.send({type:'exit'});await browser?.close();a.child.kill();b.child.kill();}})().catch(e=>{console.error(e);process.exitCode=1});
