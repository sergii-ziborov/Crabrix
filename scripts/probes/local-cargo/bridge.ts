import { prepareBrowserCargo } from '../../../site/lib/browser-cargo';
import '../../../site/workers/rust.worker';
const original = self.onmessage!;
self.onmessage = async (event) => {
  if (event.data.type !== 'prepare') return original.call(self, event);
  try {
    const result = await prepareBrowserCargo(event.data.document, new AbortController().signal, () => {});
    self.postMessage({type:'prepared', lockPath:result.lockPath, lockText:result.lockText, packages:result.graph.packages.map(p=>[p.name,p.version,p.features])});
  } catch(e) { self.postMessage({type:'error',error:String(e)}); }
};
