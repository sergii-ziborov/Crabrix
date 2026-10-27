import { build } from '../site/node_modules/esbuild/lib/main.js';
// JavaScriptCore has no browser globals. Only these fixed, bounded host services
// are exposed; no fetch, filesystem, evaluation of user code or dynamic imports.
const prelude = `
const __timers = new Map(); let __timerID = 0;
globalThis.setInterval = (fn, ms) => { const id = ++__timerID; __timers.set(id, {fn, ms, at:Date.now()}); return id; };
globalThis.clearInterval = id => __timers.delete(id);
globalThis.__tick = () => { const now=Date.now(); for(const value of __timers.values()) if(now-value.at>=value.ms){value.at=now;value.fn();} };
globalThis.crypto = {getRandomValues(array){const values=__crabrixRandom(array.length);for(let i=0;i<array.length;i++)array[i]=values[i];return array;}};
globalThis.console = {log(){},warn(){},error(){}};
globalThis.TextEncoder = class { encode(text=''){const bytes=[];for(const char of String(text)){let n=char.codePointAt(0);if(n>=0xd800&&n<=0xdfff)n=0xfffd;if(n<128)bytes.push(n);else if(n<2048)bytes.push(192|(n>>6),128|(n&63));else if(n<65536)bytes.push(224|(n>>12),128|((n>>6)&63),128|(n&63));else bytes.push(240|(n>>18),128|((n>>12)&63),128|((n>>6)&63),128|(n&63));}return Uint8Array.from(bytes);} };
globalThis.TextDecoder = class {decode(bytes=new Uint8Array()){return decodeURIComponent(Array.from(bytes,b=>'%'+b.toString(16).padStart(2,'0')).join(''));}};
`;
await build({ entryPoints:['site/native/playground-bridge.ts'], bundle:true, format:'iife', globalName:'CrabrixPlaygroundCodec', target:'es2020', minify:true, legalComments:'inline', banner:{js:prelude}, outfile:'Crabrix/Resources/PlaygroundCodec.js' });
