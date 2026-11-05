import {test} from 'node:test';
import assert from 'node:assert/strict';
import {WASI,File,Directory,PreopenDirectory,OpenFile,ConsoleStdout} from '@bjorn3/browser_wasi_shim';
import {boundBuildScript} from '../lib/browser-cargo-build-sandbox.ts';
function sandbox(){
 const out=new Map(),source=new Map([['source.rs',new File(new TextEncoder().encode('original'),{readonly:true})]]),tmp=new Map();
 const wasi=new WASI([],[],[new OpenFile(new File([])),new ConsoleStdout(()=>{}),new ConsoleStdout(()=>{}),new PreopenDirectory('/out',out),new PreopenDirectory('/source',source),new PreopenDirectory('/tmp',tmp)]);
 const memory=new WebAssembly.Memory({initial:2});wasi.inst={exports:{memory}};
 boundBuildScript(wasi,[3,5],[out,tmp]);
 const bytes=new Uint8Array(memory.buffer),view=new DataView(memory.buffer);
 const open=(fd,path,flags=1,rights=64n)=>{bytes.set(new TextEncoder().encode(path),100);const r=wasi.wasiImport.path_open(fd,0,100,path.length,flags,rights,0n,0,8);assert.equal(r,0);return view.getUint32(8,true);};
 return {wasi,out,source,tmp,memory,bytes,view,open};
}
test('build script can write its output, cannot create or truncate source, and closing a descriptor revokes write access',()=>{
 const {wasi,out,source,bytes,view,open}=sandbox();const fd=open(3,'generated.rs');
 bytes.set(new TextEncoder().encode('generated'),200);view.setUint32(24,200,true);view.setUint32(28,9,true);
 assert.equal(wasi.wasiImport.fd_write(fd,24,1,40),0);assert.equal(new TextDecoder().decode(out.get('generated.rs').data),'generated');
 assert.throws(()=>open(4,'unexpected.rs'),/read-only/);assert.throws(()=>open(4,'source.rs',8),/read-only/);
 assert.throws(()=>wasi.wasiImport.fd_renumber(fd,4),/renumbering/);
 assert.equal(wasi.wasiImport.fd_close(fd),0);
 assert.throws(()=>wasi.wasiImport.fd_write(fd,24,1,40),/read-only/);
 const reused=open(4,'source.rs',0,0n);
 assert.throws(()=>wasi.wasiImport.fd_write(reused,24,1,40),/read-only/);
 assert.equal(new TextDecoder().decode(source.get('source.rs').data),'original');
 assert.throws(()=>wasi.wasiImport.path_rename(3,100,1,4,100,1),/renames/);
});
test('build script bounds sparse offsets, resize syscalls, cumulative writes and generated entries',()=>{
 const {wasi,out,bytes,view,open}=sandbox();const fd=open(3,'generated.rs');
 assert.throws(()=>wasi.wasiImport.fd_seek(fd,10_000_000n,0,40),/offset/);
 assert.throws(()=>wasi.wasiImport.fd_filestat_set_size(fd,10_000_000n),/resize/);
 bytes.fill(1,1000,65000);view.setUint32(24,1000,true);view.setUint32(28,64000,true);
 for(let i=0;i<65;i++)assert.equal(wasi.wasiImport.fd_write(1,24,1,40),0);
 assert.throws(()=>wasi.wasiImport.fd_write(1,24,1,40),/budget/);
 const other=sandbox();for(let i=0;i<257;i++)other.out.set('f'+i,new File([]));
 assert.throws(()=>other.open(3,'one-more'),/file limit/);
});
test('build script checks the combined sizes and nesting of output and scratch directories',()=>{
 const s=sandbox();s.out.set('one',new File(new Uint8Array(2*1024*1024)));s.tmp.set('two',new File(new Uint8Array(2*1024*1024)));s.tmp.set('extra',new File([1]));
 assert.throws(()=>s.open(3,'new'),/4 MiB/);
 const deep=sandbox();let map=deep.out;for(let i=0;i<18;i++){const next=new Map();map.set('nested',new Directory(next));map=next;}
 assert.throws(()=>deep.open(3,'new'),/nesting/);
});
