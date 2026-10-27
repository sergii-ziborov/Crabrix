const assert = require('node:assert/strict');
const fs = require('node:fs');
const {chromium} = require('/Users/serhiirihgt/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const origin=process.env.CRABRIX_PLAYGROUND_ORIGIN||'http://127.0.0.1:3393';
const output='build/debugger-values-20261027';
const source='struct Crab { name: String, scores: Vec<u32> }\nfn main(){\n let text=String::from("Ferris 🦀");\n let numbers=vec![1u32,2,42];\n let crab=Crab{name:String::from("Crab"),scores:vec![7,8]};\n println!("{text} {} {}",numbers.len(),crab.name);\n}\n';
(async()=>{const browser=await chromium.launch({headless:true});const results=[];try{
  const page=await browser.newPage({viewport:{width:1440,height:1000}});const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.goto(origin+'/playground/');await page.waitForSelector('.cm-content');await page.locator('.cm-content').fill(source);
  await page.getByRole('button',{name:'Debug Rust',exact:true}).click();await page.getByRole('button',{name:'▶ Continue',exact:true}).waitFor({timeout:300000});
  await page.route('**/*',r=>r.abort()); // actual Rust builds/inspection stay local after acquisition
  await page.getByRole('button',{name:'Add breakpoint at line 6',exact:true}).click();await page.getByRole('button',{name:'▶ Continue',exact:true}).click();
  await page.waitForFunction(()=>document.querySelector('.pg-debug-location')?.textContent.includes('main.rs:6'),{},{timeout:45000});
  const values=await page.locator('.pg-debug-panel table').innerText();
  for(const expected of ['Ferris 🦀','[len=3] [1, 2, 42]','scores: [len=2] [7, 8]']) assert.ok(values.includes(expected),values);
  for(const [name,width,height]of[['phone',390,844],['tablet',1024,1366],['desktop',1440,1000]]){
    await page.setViewportSize({width,height});
    for(const theme of['Light','Dark','Amber Circuit','Cyberpunk']){
      await page.getByRole('button',{name:'Editor settings',exact:true}).click();await page.getByRole('button',{name:theme,exact:false}).last().click();await page.getByRole('button',{name:'Close',exact:true}).click();
      await page.locator('.pg-debug-panel table').scrollIntoViewIfNeeded();
      const geometry=await page.evaluate(()=>({width:innerWidth,body:document.body.scrollWidth,tabsBottom:document.querySelector('.pg-dock-tabs').getBoundingClientRect().bottom,workspaceBottom:document.querySelector('.pg-workspace').getBoundingClientRect().bottom,workspaceScroll:document.querySelector('.pg-workspace').scrollLeft,toolbarOverflow:document.querySelector('.pg-toolbar').scrollWidth-document.querySelector('.pg-toolbar').clientWidth}));
      assert.ok(geometry.body<=width&&geometry.tabsBottom<=height+1&&geometry.workspaceBottom<=height+1&&geometry.workspaceScroll===0&&geometry.toolbarOverflow<=1,JSON.stringify(geometry));
      await page.screenshot({path:`${output}/values-${name}-${theme.replaceAll(' ','-')}.png`});results.push({name,theme,geometry});
    }
  }
  await page.getByRole('button',{name:'Remove breakpoint at line 6',exact:true}).click();await page.getByRole('button',{name:'▶ Continue',exact:true}).click();await page.getByRole('button',{name:'▶ Run',exact:true}).waitFor();
  assert.equal((await page.locator('.cm-content').innerText()).trim(),source.trim());
  const asyncSource='async fn work()->u32 {\n let text=String::from("Async 🦀");\n let values=vec![7u32,8];\n std::future::ready(()).await;\n println!("{text} {}",values.len());\n 42\n}\nfn main(){\n use std::{future::Future,task::{Context,Poll,Waker}};\n let mut task=Box::pin(work());\n let mut cx=Context::from_waker(Waker::noop());\n loop { if let Poll::Ready(v)=task.as_mut().poll(&mut cx){println!("answer={v}");break;} }\n}';
  await page.locator('.cm-content').fill(asyncSource);await page.getByRole('button',{name:'Debug Rust',exact:true}).click();await page.getByRole('button',{name:'▶ Continue',exact:true}).waitFor({timeout:45000});
  await page.getByRole('button',{name:'Add breakpoint at line 5',exact:true}).click();await page.getByRole('button',{name:'▶ Continue',exact:true}).click();
  await page.waitForFunction(()=>document.querySelector('.pg-debug-location')?.textContent.includes('main.rs:5 · work'),{},{timeout:45000});
  assert.match(await page.locator('.pg-debug-panel table').innerText(),/Async 🦀/);
  assert.equal(await page.locator('.pg-frame').filter({hasText:'work'}).count(),1);
  await page.screenshot({path:output+'/async-values.png'});
  await page.getByRole('button',{name:'Remove breakpoint at line 5',exact:true}).click();await page.getByRole('button',{name:'▶ Continue',exact:true}).click();await page.getByRole('button',{name:'▶ Run',exact:true}).waitFor();await page.getByRole('tab',{name:'Output',exact:true}).click();
  await page.waitForFunction(()=>document.querySelector('.pg-output pre')?.textContent==='Async 🦀 2\nanswer=42\n');assert.deepEqual(errors,[]);
  fs.writeFileSync(output+'/browser-values.json',JSON.stringify({at:new Date().toISOString(),origin,backendExecution:false,layouts:results,aggregateInspection:true,asyncBreakpointAndLocals:true,sourcePreserved:true,networkDeniedAfterAcquisition:true},null,2));console.log('PASS aggregate locals, async breakpoint, 12 layouts, offline builds');
}finally{await browser.close()}})().catch(e=>{console.error(e);process.exitCode=1});
