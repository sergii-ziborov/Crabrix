// Coordinator for PlaygroundTwoDeviceTests/testLinksSelectionsAndDebugAcrossTwoAppsAndWebsite.
// Run the two Xcode UI tests after this process prints READY. No account or source execution on the relay.
const {spawn}=require('node:child_process');
const {createInterface}=require('node:readline');
const http=require('node:http');
const fs=require('node:fs');
const assert=require('node:assert/strict');
const {createHash}=require('node:crypto');
const {chromium}=require(process.env.CRABRIX_PLAYWRIGHT_MODULE||'/Users/serhiirihgt/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const origin=process.env.CRABRIX_PLAYGROUND_ORIGIN||'https://crabrix.com';
const output=process.env.CRABRIX_PROBE_OUTPUT||'build/playground-crossclient-20261028';
fs.mkdirSync(output,{recursive:true});
const nonce='cross-client-'+Date.now(),events=[],reports=[],selectionNames=new Set();let phase='joining';
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
async function wait(fn,label,timeout=240000){const end=Date.now()+timeout;while(Date.now()<end){if(fn())return;await sleep(150)}throw Error('Timeout: '+label)}
const debugSource='fn main() {\n let message=String::from("shared-debug");\n let numbers=vec![2u32,40];\n println!("{} {}",message,numbers.iter().sum::<u32>());\n}\n';
(async()=>{let browser,server,room;const peer=spawn(process.env.CRABRIX_NATIVE_PROBE||'build/playground-crossclient/native-peer',['Crabrix/Resources/PlaygroundCodec.js',origin]);
const send=value=>peer.stdin.write(JSON.stringify(value)+'\n');
createInterface({input:peer.stdout}).on('line',line=>{const value=JSON.parse(line);events.push(value);if(value.event==='error')console.log('NATIVE ERROR',value.error);for(const s of value.selections||[])if(s.head!==s.anchor)selectionNames.add(s.clientID)});
peer.stderr.on('data',b=>process.stderr.write(b));
try{
 send({type:'create',document:{schemaVersion:1,name:'cross-client-interview',entryFile:'main.rs',edition:'2024',files:{'main.rs':'// native-pair '+nonce+'\nfn main(){println!("join-only");}\n'}}});
 await wait(()=>events.some(e=>e.event==='ready'),'room creation',30000);
 room=events.find(e=>e.event==='ready').link;
 const url=origin+'/playground/room/'+room.id+'/#'+new URLSearchParams({key:room.key,access:room.access,expires:room.expiresAt,mode:room.mode});
 server=http.createServer((req,res)=>{res.setHeader('Cache-Control','no-store');res.setHeader('Content-Type','application/json');if(req.url==='/fixture')res.end(JSON.stringify({url,nonce}));else if(req.url==='/phase')res.end(JSON.stringify({phase}));else if(req.url==='/event'&&req.method==='POST'){let body='';req.on('data',b=>body+=b);req.on('end',()=>{const event=JSON.parse(body);reports.push({...event,at:new Date().toISOString()});console.log('APP',event.role,event.event);res.end('{}')})}else{res.statusCode=404;res.end('{}')}}).listen(3395,'127.0.0.1');
 browser=await chromium.launch({headless:true});const page=await browser.newPage({viewport:{width:1440,height:1000}});const errors=[];page.on('pageerror',e=>errors.push(e.message));
 // Optional byte-identical local asset mirror speeds repeated UI qualification.
 // Room creation, encrypted source/presence, app clients and page still use production HTTPS.
 const mirrored=process.env.CRABRIX_LOCAL_TOOLCHAIN_MIRROR==='1';
 if(mirrored){const manifest=JSON.parse(fs.readFileSync('site/lib/playground-toolchain.json','utf8'));for(const asset of[manifest.compiler,manifest.sysroot]){const body=fs.readFileSync('site/public'+asset.url);assert.equal(createHash('sha256').update(body).digest('hex'),asset.sha256);await page.route(origin+asset.url,route=>route.fulfill({body,contentType:asset.url.endsWith('.zip')?'application/zip':'application/gzip'}))}}
 await page.goto(url);await page.waitForSelector('.cm-content');
 await page.waitForFunction(n=>document.querySelector('.cm-content')?.textContent.includes(n),nonce);
 // Warm the local compiler before the paired debugging phase; the source stays in this browser.
 await page.getByRole('button',{name:'✓ Check',exact:true}).click();
 await page.waitForFunction(()=>document.querySelector('.pg-check')?.disabled===false,null,{timeout:300000});
 console.log('READY two-device fixture on 127.0.0.1:3395');
 await wait(()=>events.some(e=>e.document?.files['main.rs']?.includes('from-phone')),'phone source');
 await wait(()=>events.some(e=>e.document?.files['main.rs']?.includes('from-pad')),'pad source');
 await page.waitForFunction(()=>{const s=document.querySelector('.cm-content')?.textContent||'';return s.includes('from-phone')&&s.includes('from-pad')});
 console.log('PASS both actual native editors and website converge');
 await wait(()=>selectionNames.size>=2,'non-empty selections from both actual native editors',45000);
 await page.waitForSelector('.cm-ySelection');
 await page.screenshot({path:output+'/native-selections-in-browser.png'});
 console.log('PASS both native selections reach the relay and browser decoration');
 // Browser selection is visible in both app canvases; screenshots are attached to the Xcode result.
 const nativeSelectionIDs=new Set(selectionNames),beforeSelection=events.length;
 await page.locator('.cm-content').focus();await page.keyboard.press('Meta+ArrowUp');await page.keyboard.down('Shift');await page.keyboard.press('ArrowRight');await page.keyboard.press('ArrowRight');await page.keyboard.up('Shift');
 await wait(()=>events.slice(beforeSelection).some(e=>e.selections?.some(s=>!nativeSelectionIDs.has(s.clientID)&&s.anchor===0&&s.head===2)),'browser selection received by native transport');
 send({type:'selection',file:'main.rs',anchor:3,length:5});
 await sleep(1500);phase='selection-ready';
 await wait(()=>reports.filter(x=>x.event==='selection-captured').length===2,'native selection screenshots');
 await page.getByRole('button',{name:'✓ Check',exact:true}).waitFor({timeout:300000});
 await page.locator('.cm-content').fill(debugSource);
 await wait(()=>reports.filter(x=>x.event==='debug-paused').length===2,'both app debuggers paused');
 await page.getByRole('button',{name:'Debug Rust',exact:true}).click();
 await page.getByRole('button',{name:'▶ Continue',exact:true}).waitFor({timeout:300000});
 await page.getByRole('button',{name:'Step over',exact:true}).click();
 await page.waitForFunction(()=>document.querySelector('.pg-debug-location')?.textContent.includes('main.rs:3'));
 assert.match(await page.locator('.pg-debug-panel table').innerText(),/shared-debug/);
 await page.getByRole('button',{name:'Step over',exact:true}).click();
 await page.waitForFunction(()=>document.querySelector('.pg-debug-location')?.textContent.includes('main.rs:4'));
 assert.match(await page.locator('.pg-debug-panel table').innerText(),/2, 40/);
 await page.screenshot({path:output+'/browser-local-debug.png'});
 // Selection changes must not stop a paused native/browser debug session.
 send({type:'selection',file:'main.rs',anchor:3,length:4});await sleep(600);
 assert.equal(await page.getByRole('button',{name:'Step over',exact:true}).isVisible(),true);
 // A new shared source snapshot invalidates all old local debugger sessions.
 send({type:'edit',file:'main.rs',text:'fn main(){println!("shared-final=42");}\n'});
 await page.waitForFunction(()=>document.querySelector('.pg-notice')?.textContent.includes('Debug stopped because shared source changed'));
 await wait(()=>reports.filter(x=>x.event==='debug-stopped').length===2,'native debug cancellation');
 await page.getByRole('button',{name:'▶ Run',exact:true}).click();
 await page.waitForFunction(()=>document.querySelector('.pg-output pre')?.textContent==='shared-final=42\n',null,{timeout:90000});
 await wait(()=>reports.filter(x=>x.event==='done').length===2,'both apps run locally and reopen HTTPS link');
 assert.deepEqual(errors,[]);
 fs.writeFileSync(output+'/result.json',JSON.stringify({at:new Date().toISOString(),origin,toolchainBytesFromVerifiedLocalMirror:mirrored,sourceCommit:process.env.CRABRIX_APP_SOURCE||'ecc45983a60bd8ed794d03bcae5ada145f52edc7',reports,nativeSelectionParticipants:nativeSelectionIDs.size,passed:['custom scheme opens both actual apps','native-native and native-web source','both native selections render in browser','browser selection reaches native transport and both app canvases','independent native and browser String/Vec debugging','selection does not invalidate browser Debug','remote source cancels stale Debug on all clients','actual local stdout on all three clients'],sourceExecutedOnBackend:false,physicalDevices:false},null,2));
 console.log('PASS two app editors, links, selections, three local debuggers and actual stdout');
}finally{server?.close();send({type:'exit'});peer.kill();await browser?.close()}})().catch(e=>{console.error(e);process.exitCode=1});
