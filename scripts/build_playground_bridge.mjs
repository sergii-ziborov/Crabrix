import { build } from '../site/node_modules/esbuild/lib/main.js';
// JavaScriptCore has no browser globals. Only these fixed, bounded host services
// are exposed; no fetch, filesystem, evaluation of user code or dynamic imports.
const prelude = `
const __timers = new Map(); let __timerID = 0;
globalThis.setInterval = (fn, ms) => { const id = ++__timerID; __timers.set(id, {fn, ms, at:Date.now()}); return id; };
globalThis.clearInterval = id => __timers.delete(id);
globalThis.__tick = () => { const now=Date.now(); for(const value of __timers.values()) if(now-value.at>=value.ms){value.at=now;value.fn();} };
const __base64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
globalThis.btoa = value => {const text=String(value);if(text.length>8192)throw new Error('Oversized native base64 input.');for(let i=0;i<text.length;i++)if(text.charCodeAt(i)>255)throw new Error('Invalid native base64 byte.');let out='';for(let i=0;i<text.length;i+=3){const a=text.charCodeAt(i),b=i+1<text.length?text.charCodeAt(i+1):0,c=i+2<text.length?text.charCodeAt(i+2):0;out+=__base64[a>>2]+__base64[((a&3)<<4)|(b>>4)]+(i+1<text.length?__base64[((b&15)<<2)|(c>>6)]:'=')+(i+2<text.length?__base64[c&63]:'=');}return out;};
globalThis.atob = value => {const text=String(value);if(text.length>8192||!/^[A-Za-z0-9+/]*={0,2}$/.test(text))throw new Error('Invalid native base64 input.');const clean=text.replace(/=+$/,''),padding=text.length-clean.length;if(clean.length%4===1||padding&&(text.length%4!==0||padding!==4-clean.length%4))throw new Error('Invalid native base64 padding.');let out='',buffer=0,bits=0;for(const char of clean){buffer=(buffer<<6)|__base64.indexOf(char);bits+=6;if(bits>=8){bits-=8;out+=String.fromCharCode((buffer>>>bits)&255);buffer&=(1<<bits)-1;}}if(buffer!==0)throw new Error('Noncanonical native base64 input.');return out;};
globalThis.crypto = {getRandomValues(array){const values=__crabrixRandom(array.length);for(let i=0;i<array.length;i++)array[i]=values[i];return array;}};
const __runtimeBytes = value => {const bytes=value instanceof ArrayBuffer?new Uint8Array(value):new Uint8Array(value.buffer,value.byteOffset,value.byteLength);return Array.from(bytes);};
const __runtimeCrypto = value => {const result=JSON.parse(__crabrixRuntimeCrypto(JSON.stringify(value)));if(result.error)throw new Error(result.error);return result;};
globalThis.crypto.subtle = {
 async digest(algorithm,data){if(algorithm!=='SHA-256')throw new Error('Unsupported native digest.');return Uint8Array.from(__runtimeCrypto({op:'digest',data:__runtimeBytes(data)}).bytes).buffer;},
 async importKey(format,data,algorithm,extractable,usages){if(format!=='raw'||extractable||usages.length!==1||usages[0]!=='verify'||!['ECDSA','HMAC'].includes(algorithm.name)||algorithm.name==='ECDSA'&&algorithm.namedCurve!=='P-256'||algorithm.name==='HMAC'&&algorithm.hash!=='SHA-256')throw new Error('Unsupported native verification key.');return Object.freeze({name:algorithm.name,raw:__runtimeBytes(data)});},
 async verify(algorithm,key,signature,data){const name=typeof algorithm==='string'?algorithm:algorithm.name;if(!['ECDSA','HMAC'].includes(name)||name!==key.name||name==='ECDSA'&&algorithm.hash!=='SHA-256')throw new Error('Unsupported native verification algorithm.');return __runtimeCrypto({op:name==='ECDSA'?'ecdsa':'hmac',key:key.raw,signature:__runtimeBytes(signature),data:__runtimeBytes(data)}).valid===true;}
};
globalThis.console = {log(){},warn(){},error(){}};
globalThis.TextEncoder = class { encode(text=''){const bytes=[];for(const char of String(text)){let n=char.codePointAt(0);if(n>=0xd800&&n<=0xdfff)n=0xfffd;if(n<128)bytes.push(n);else if(n<2048)bytes.push(192|(n>>6),128|(n&63));else if(n<65536)bytes.push(224|(n>>12),128|((n>>6)&63),128|(n&63));else bytes.push(240|(n>>18),128|((n>>12)&63),128|((n>>6)&63),128|(n&63));}return Uint8Array.from(bytes);} };
globalThis.TextDecoder = class {decode(bytes=new Uint8Array()){return decodeURIComponent(Array.from(bytes,b=>'%'+b.toString(16).padStart(2,'0')).join(''));}};
`;
await build({ entryPoints:['site/native/playground-bridge.ts'], bundle:true, format:'iife', globalName:'CrabrixPlaygroundCodec', target:'es2020', minify:true, legalComments:'inline', banner:{js:prelude}, outfile:'Crabrix/Resources/PlaygroundCodec.js' });
