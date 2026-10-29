import {Y} from '../../../site/lib/playground-collab';
import {createPresence,receivePresence,remoteRuntimePresence} from '../../../site/lib/playground-presence';
import {decryptPlayground} from '../../../site/lib/playground-crypto';
import {parsePlaygroundLink} from '../../../site/lib/playground-session';
import {verifyRuntimeEnvelope} from '../../../site/lib/playground-runtime-protocol';
const fixture=await(await fetch('http://127.0.0.1:3395/fixture')).json();const link=parsePlaygroundLink(new URL(fixture.url))!;
const state=await(await fetch(fixture.origin+'/api/playground/rooms/'+link.id+'/',{headers:{authorization:'Bearer '+link.access}})).json();
const doc=new Y.Doc(),awareness=createPresence(doc,'Passive QA');
try{Y.applyUpdate(doc,await decryptPlayground(link.key,state.snapshot));for(const event of state.events)Y.applyUpdate(doc,await decryptPlayground(link.key,event.packet));for(const presence of state.presence??[])receivePresence(awareness,await decryptPlayground(link.key,presence.packet),'passive QA');
for(const item of remoteRuntimePresence(awareness)){try{const f=await verifyRuntimeEnvelope(JSON.parse(item.envelope),{room:link.id,editCapability:link.access});const p=f.payload as any;console.log(JSON.stringify({kind:f.header[1],sender:f.sender.slice(0,8),target:f.header[4].slice(0,8),operation:f.header[6],role:p.role,name:p.name,permissions:p.permissions,ready:p.ready,state:p.state,stage:p.stage,succeeded:p.succeeded,ok:p.ok,hasGrant:!!p.grant,reason:p.reason,proof:f.editAccessProved,hasOutput:!!p.output,outputBytes:p.output?JSON.stringify(p.output).length:0,job:p.job?.operation}));}catch(error){console.log('Verification:',error instanceof Error?error.message:'invalid');}}}
finally{awareness.destroy();doc.destroy();}
