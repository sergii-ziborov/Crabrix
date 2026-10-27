// Fixed bundled compiler in a host harness; no npm/Node APIs are supplied to it.
const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const context = vm.createContext({});
for (const file of ['WebCompilerRuntime', 'WebProjectBuilder']) vm.runInContext(fs.readFileSync(`Crabrix/Resources/${file}.js`, 'utf8'), context);
let count = 0;
const base = { 'index.html': '<script data-x="a>b" type="module" src="/src/app.ts"></script>', 'package.json': '{}' };
function build(files, entry) { return JSON.parse(context.CrabrixWebBuilder.build(JSON.stringify({ ...base, ...files }), entry || 'index.html')); }
function run(files) {
  const result = build(files); assert.ok(!result.error && !result.missing, JSON.stringify(result));
  const output = {}; vm.runInNewContext(result.assets['crabrix-web/entry-0.js'], output);
  count++; return output;
}
function fail(source, match) { const result = build({ 'src/app.ts': source }); assert.match(result.error.message, match); count++; }
assert.equal(run({'src/app.ts': 'import { answer } from "./value"; globalThis.answer=answer as number', 'src/value.ts':'export const answer: number=42'}).answer, 42);
assert.equal(run({'src/app.ts':'import data from "./data.json";globalThis.answer=data.n','src/data.json':'{"n":7}'}).answer,7);
assert.equal(run({'src/app.ts':'import text from "./message.txt?raw";globalThis.answer=text','src/message.txt':'🦀 offline'}).answer,'🦀 offline');
assert.equal(run({'src/app.ts':'globalThis.answer=import.meta.env.PROD ? 10 : 0'}).answer,10);
const library = { 'package.json':'{"dependencies":{"demo":"^1.0.0"}}', 'node_modules/demo/package.json':'{"name":"demo","version":"1.2.0","exports":{"browser":"./browser.js","default":"./node.js"}}', 'node_modules/demo/browser.js':'export const answer=11', 'node_modules/demo/node.js':'require("fs")' };
assert.equal(run({...library,'src/app.ts':'import {answer} from "demo"; globalThis.answer=answer'}).answer,11);
assert.equal(run({...library,'node_modules/demo/package.json':'{"name":"demo","version":"1.2.0","exports":{"import":"./esm.js","require":"./cjs.js"}}','node_modules/demo/esm.js':'export default 3','node_modules/demo/cjs.js':'module.exports=9','src/app.ts':'import a from "demo";globalThis.answer=a+require("demo")'}).answer,12);
assert.equal(run({...library,'node_modules/demo/browser.js':'if(process.env.NODE_ENV !== "production") { require("fs"); } export const answer=12','src/app.ts':'import {answer} from "demo";globalThis.answer=answer'}).answer,12);
assert.equal(run({...library,'node_modules/demo/package.json':'{"name":"demo","version":"1.2.0","main":"index.js","browser":{"fs":false}}','node_modules/demo/index.js':'module.exports=Object.keys(require("fs")).length','src/app.ts':'globalThis.answer=require("demo")'}).answer,0);
let result=build({...library,'node_modules/demo/package.json':'{"name":"demo","version":"1.2.0","exports":{"browser":null,"default":"./node.js"}}','src/app.ts':'import x from "demo"'});assert.match(result.error.message,/unavailable/);count++;
result=build({'package.json':'{"dependencies":{"demo":"^1.0.0"}}','src/app.ts':'import x from "demo"'});assert.equal(result.missing.name,'demo');assert.equal(result.missing.directory,'node_modules/demo');count++;
result=build({'package.json':'{"dependencies":{"demo":"github:someone/demo"}}','src/app.ts':'import x from "demo"'});assert.match(result.error.message,/registry version ranges/);count++;
result=build({'src/app.ts':'const broken: = ;'});assert.equal(result.error.file,'src/app.ts');assert.equal(result.error.line,1);count++;
fail('import fs from "node:fs"',/server-only/);
fail('import("https://cdn.test/a.js")',/unavailable offline/);
fail('const name="x";require(name)',/literal/);
fail('const name="x";import(name)',/literal/);
fail('await Promise.resolve(1)',/Top-level await/);
fail('const all=import.meta.glob("./*.ts")',/plugin/);
fail('import "./missing"',/not found/);
fail('import "../../escape"',/escapes/);
fail('import "./style.module.css"',/not found/);
result=build({'index.html':'<script type="module">globalThis.x=1</script><script type="module">globalThis.y=2</script>'});assert.match(result.error.message,/one module/);count++;
result=build({'index.html':'<!-- <script type="module" src="missing.js"></script> --><script type="module" src="src/app.ts"></script>','src/app.ts':'globalThis.answer=2'});assert.ok(!result.error);count++;
result=build({'src/app.ts':'import "./a.css"','src/a.css':'@import "./b.css";body {color:red}', 'src/b.css':'button {color:blue}'});assert.ok(!result.error,JSON.stringify(result));assert.match(result.assets['crabrix-web/entry-0.js'],/color:blue/);count++;
assert.equal(context.CrabrixWebBuilder.selectVersion(['1.2.0','1.4.0','2.0.0','2.1.0-beta.1'],['^1.0.0','>=1.3']), '1.4.0');count++;
assert.equal(run({'src/app.ts':'import {group} from \"./group\";globalThis.answer=group.answer','src/group.ts':'export * as group from \"./value\"','src/value.ts':'export const answer=19'}).answer,19);
const fixture=JSON.parse(fs.readFileSync('CrabrixTests/Fixtures/BrowserReactProject.json','utf8'));result=JSON.parse(context.CrabrixWebBuilder.build(JSON.stringify(fixture),'index.html'));assert.equal(result.moduleCount,133);assert.equal(result.packageRoots.length,8);assert.ok(!result.assets['crabrix-web.lock.json']);count++;
console.log(`PASS ${count} offline browser compiler checks`);
