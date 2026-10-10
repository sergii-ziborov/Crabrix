import { cpSync, mkdirSync, rmSync } from 'node:fs';
import { resolve, join } from 'node:path';
const destination = resolve(process.argv[2] || '../build/site-server-release');
rmSync(destination, { recursive: true, force: true });
mkdirSync(destination, { recursive: true });
// pnpm links inside the traced tree must remain relative when shipped to Linux.
// Node's default cp behaviour rewrites them to paths on the build computer.
cpSync('.next/standalone', join(destination, 'standalone'), { recursive: true, verbatimSymlinks: true });
cpSync('.next/static', join(destination, 'static'), { recursive: true });
cpSync('public', join(destination, 'public'), { recursive: true });
cpSync('hetzner', join(destination, 'hetzner'), { recursive: true });
cpSync('compose.prebuilt.yaml', join(destination, 'compose.prebuilt.yaml'));
mkdirSync(join(destination, 'scripts'));
cpSync('scripts/backup-accounts.mjs', join(destination, 'scripts/backup-accounts.mjs'));
console.log('Prepared standalone server release:', destination);
