import {build} from '../site/node_modules/esbuild/lib/main.js';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
await build({absWorkingDir:root,entryPoints:['packages/crabrix-playground-mcp/test/runtime-archive-probe.ts','packages/crabrix-playground-mcp/test/runtime-local-probe.ts','packages/crabrix-playground-mcp/test/runtime-browser-probe.ts','packages/crabrix-playground-mcp/test/runtime-matrix-probe.ts','packages/crabrix-playground-mcp/test/runtime-inspect-probe.ts'],outdir:'build/mcp-runtime-20261029',outExtension:{'.js':'.mjs'},bundle:true,platform:'node',format:'esm',target:'node22',banner:{js:'import { createRequire as __crabrixCreateRequire } from "node:module"; const require = __crabrixCreateRequire(import.meta.url);'}});
