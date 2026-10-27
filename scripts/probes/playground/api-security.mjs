import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
const origin=process.env.CRABRIX_PLAYGROUND_ORIGIN||'http://127.0.0.1:3393';
const root=origin+'/api/playground/rooms/';
const packet={iv:randomBytes(12).toString('base64url'),data:randomBytes(32).toString('base64url')};
const json=(value,access)=>({method:'POST',headers:{'Content-Type':'application/json',...(access?{Authorization:'Bearer '+access}:{})},body:JSON.stringify(value)});
let response=await fetch(root,json({snapshot:packet,lifetimeSeconds:86401}));assert.equal(response.status,400);
response=await fetch(root,json({snapshot:packet,lifetimeSeconds:60}));assert.equal(response.status,201);const room=await response.json();const url=root+room.id+'/';
assert.equal((await fetch(url)).status,401);
assert.equal((await fetch(url,{headers:{Authorization:'Bearer '+room.view,Origin:'https://attacker.example'}})).status,403);
response=await fetch(url,{headers:{Authorization:'Bearer '+room.view}});assert.equal(response.status,200);const state=await response.json();assert.equal(state.expiresAt,room.expiresAt);assert.deepEqual(state.snapshot,packet);assert.equal(JSON.stringify(state).includes(room.edit),false);
assert.equal((await fetch(url,json({type:'update',peer:'not_joined_000001',messageID:'message_000000001',packet},room.view))).status,403);
assert.equal((await fetch(url,json({type:'update',peer:'not_joined_000001',messageID:'message_000000001',packet},room.edit))).status,409);
const controllers=[];
try{
 for(let i=0;i<4;i++){const abort=new AbortController();controllers.push(abort);response=await fetch(url+'events/?peer=participant_00000'+i,{headers:{Authorization:'Bearer '+room.edit},signal:abort.signal});assert.equal(response.status,200);}
 response=await fetch(url+'events/?peer=participant_000009',{headers:{Authorization:'Bearer '+room.edit}});assert.equal(response.status,409);
 assert.equal((await fetch(url,{method:'DELETE',headers:{Authorization:'Bearer '+room.edit}})).status,403);
 assert.equal((await fetch(url,{method:'DELETE',headers:{Authorization:'Bearer '+room.owner}})).status,204);
 assert.equal((await fetch(url,{headers:{Authorization:'Bearer '+room.view}})).status,410);
 console.log('PASS real HTTP capabilities, origin checks, 24h maximum, four-peer stream admission, owner deletion and post-deletion access');
}finally{for(const abort of controllers)abort.abort();}
