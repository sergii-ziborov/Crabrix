import {serveStdio} from '@modelcontextprotocol/server/stdio';
import {makeServer} from '../src/server';
import {PlaygroundRoom} from '../src/room';
const room=new PlaygroundRoom(process.env.CRABRIX_QA_ORIGIN??'http://127.0.0.1:3399');
const handle=serveStdio(()=>makeServer(room));
let closing=false;
const close=async()=>{if(closing)return;closing=true;room.dispose();await handle.close();};
process.stdin.once('end',()=>{void close();});process.once('SIGINT',()=>{void close();});process.once('SIGTERM',()=>{void close();});
