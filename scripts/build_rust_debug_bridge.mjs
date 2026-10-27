import { build } from '../site/node_modules/esbuild/lib/main.js';
await build({ entryPoints:['site/native/rust-debug-bridge.ts'], bundle:true, format:'iife', globalName:'CrabrixRustDebugCompiler', target:'es2020', minify:true, legalComments:'inline', outfile:'Crabrix/Resources/RustDebugCompiler.js' });
