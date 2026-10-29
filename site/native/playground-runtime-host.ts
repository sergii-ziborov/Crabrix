import { RuntimeHostCore, type RuntimeHostContext, type RuntimeJobUpdate } from '../lib/playground-runtime-host';
import type { RuntimeAction } from '../lib/playground-runtime-authority';
let host: RuntimeHostCore | undefined;
export async function hostRequest(request: Record<string, unknown>) {
  const context = request.context as RuntimeHostContext;
  if (!context || !/^[A-Za-z0-9_-]{24}$/.test(context.room) || !/^[a-f0-9]{64}$/.test(context.target) || !/^[a-f0-9]{64}$/.test(context.revision) || !Array.isArray(context.paths) || context.paths.length > 16 || !Array.isArray(context.lines) || context.lines.length !== context.paths.length) throw new Error('Invalid local host context.');
  if (request.action === 'initialize') host = new RuntimeHostCore(context);
  if (!host) throw new Error('Local runtime host is not initialized.');
  host.tick(context);
  if (request.action === 'frame') await host.frame(JSON.parse(request.envelope as string));
  else if (request.action === 'allow') host.allow(request.controller as string, request.requestID as string, request.operations as RuntimeAction[]);
  else if (request.action === 'revoke') host.revoke();
  else if (request.action === 'clear-output') host.clearOutput();
  else if (request.action === 'local-output') host.reportLocal(request.revision as string, request.update as RuntimeJobUpdate);
  else if (request.action === 'update') host.update(request.job as string, request.update as RuntimeJobUpdate);
  else if (!['initialize','tick'].includes(String(request.action))) throw new Error('Invalid local host action.');
  return host.drain();
}
export function callHost(requestJSON: string, complete: (reply: string) => void) {
  void hostRequest(JSON.parse(requestJSON)).then(reply => complete(JSON.stringify(reply)), () => complete(JSON.stringify({ error: 'Local runtime host refused this operation.' })));
}
