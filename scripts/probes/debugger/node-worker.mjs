import { parentPort, workerData } from 'node:worker_threads';
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
console.log = () => {}; // WASI shim development diagnostics, not guest stdout.
globalThis.self = {location:{origin:'https://debug-fixture.invalid'},postMessage:message=>parentPort.postMessage(message)};
globalThis.fetch = async url => {
  const path = new URL(url).pathname;
  if (!['/playground-runtime/rustc.wasm.gz','/playground-runtime/sysroot.zip'].includes(path)) throw Error('Network denied in debugger gate');
  return new Response(await readFile(workerData.publicRoot + path));
};
await import(pathToFileURL(workerData.bundle).href);
parentPort.on('message',data=>self.onmessage({data}));
