import assert from 'node:assert/strict';
import {Client} from '@modelcontextprotocol/client';
import {StdioClientTransport} from '@modelcontextprotocol/client/stdio';
const client=new Client({name:'Crabrix installed archive qualification',version:'1'});
const transport=new StdioClientTransport({command:process.execPath,args:[process.argv[2]],stderr:'pipe'});
try{
 await client.connect(transport);
 const tools=await client.listTools();assert.equal(tools.tools.length,12);assert(tools.tools.some(t=>t.name==='crabrix_runtime_start'));assert(tools.tools.some(t=>t.name==='crabrix_runtime_job'));
 const unconnected=await client.callTool({name:'crabrix_runtime_clients',arguments:{}});assert.equal(unconnected.isError,true,'Installing or discovering tools must not attach or run a project');
 console.log('PASS clean installed archive → official SDK stdio: 12 tools; unconnected execution refused');
}finally{await client.close();await transport.close();}
