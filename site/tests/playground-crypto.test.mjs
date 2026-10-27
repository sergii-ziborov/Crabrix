import { test } from 'node:test';
import assert from 'node:assert/strict';
import { encryptPlayground, decryptPlayground, newEncryptionSecret } from '../lib/playground-crypto.ts';
import { limitProgramMemory } from '../lib/wasm-resource-limits.ts';

test('AES-GCM authenticates source, key and packet; distinct nonces avoid reuse', async () => {
 const key=newEncryptionSecret(), bytes=new TextEncoder().encode('fn main() { println!("🦀"); }');
 const first=await encryptPlayground(key,bytes), second=await encryptPlayground(key,bytes);
 assert.notEqual(first.iv,second.iv); assert.notEqual(first.data,second.data);
 assert.deepEqual(await decryptPlayground(key,first),bytes);
 await assert.rejects(decryptPlayground(newEncryptionSecret(),first));
 const data=Buffer.from(first.data,'base64url');data[0]^=1;
 await assert.rejects(decryptPlayground(key,{...first,data:data.toString('base64url')}));
 await assert.rejects(decryptPlayground(key,first,4));
});

test('user Wasm memory maximum is rewritten and enforced by the actual engine', async()=>{
 // Minimal Wasm with an unbounded 1-page memory and an exported memory.
 const bytes=Uint8Array.from([0,97,115,109,1,0,0,0,5,3,1,0,1,7,10,1,6,109,101,109,111,114,121,2,0]);
 const module=await WebAssembly.instantiate(limitProgramMemory(bytes,2));
 const memory=module.instance.exports.memory;
 assert.equal(memory.grow(1),1); assert.throws(()=>memory.grow(1),RangeError);
 assert.throws(()=>limitProgramMemory(bytes,0),/64 MiB/);
});
