import { Gunzip } from 'fflate';
import { manifestTable } from './browser-cargo-manifest.ts';
export const CARGO_BUDGET = Object.freeze({ packages: 16, compressedBytes: 4 * 1024 * 1024, crateBytes: 8 * 1024 * 1024, totalBytes: 32 * 1024 * 1024, fileBytes: 2 * 1024 * 1024, entries: 2048, indexBytes: 8 * 1024 * 1024 });
const decoder = new TextDecoder('utf-8', { fatal: true });
export type CrateArchive = {
    files: Map<string, Uint8Array>;
    manifest: Record<string, unknown>;
    libPath: string;
    libName: string;
    edition: string;
    env: string[];
    bytes: number;
    buildScript?: string;
};
export const digest = async (bytes: Uint8Array) => Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', new Uint8Array(bytes))), b => b.toString(16).padStart(2, '0')).join('');
function pathOK(path: string) { return !!path && path.length <= 512 && !path.startsWith('/') && !path.includes('\\') && !path.includes(':') && !/[\x00-\x1f\x7f]/.test(path) && path.split('/').every(p => !!p && p !== '.' && p !== '..' && !['__proto__', 'constructor', 'prototype'].includes(p)); }
function octal(bytes: Uint8Array) { const s = decoder.decode(bytes).replace(/\0.*$/s, '').trim(); if (!/^[0-7]+$/.test(s))
    throw new Error('Unsupported crate archive number.'); const n = parseInt(s, 8); if (!Number.isSafeInteger(n))
    throw new Error('Crate archive number overflow.'); return n; }
const field = (b: Uint8Array) => decoder.decode(b.subarray(0, b.indexOf(0) < 0 ? b.length : b.indexOf(0)));
/** Check compressed/expanded sizes, tar checksums and every path before mounting any source. */
export function readCrateArchive(compressed: Uint8Array, name: string, version: string): CrateArchive {
    if (compressed.length < 18 || compressed.length > CARGO_BUDGET.compressedBytes)
        throw new Error(`${name}: archive exceeds the 4 MiB download budget.`);
    const declared = new DataView(compressed.buffer, compressed.byteOffset, compressed.byteLength).getUint32(compressed.length - 4, true);
    if (declared > CARGO_BUDGET.crateBytes)
        throw new Error(`${name}: archive expands beyond 8 MiB.`);
    const chunks: Uint8Array[] = [];
    let expanded = 0;
    const gunzip = new Gunzip((chunk) => { expanded += chunk.length; if (expanded > CARGO_BUDGET.crateBytes)
        throw new Error(`${name}: archive expansion limit.`); chunks.push(chunk); });
    for (let at = 0; at < compressed.length; at += 1024)
        gunzip.push(compressed.subarray(at, at + 1024), at + 1024 >= compressed.length);
    const tar = new Uint8Array(expanded);
    let next = 0;
    for (const chunk of chunks) {
        tar.set(chunk, next);
        next += chunk.length;
    }
    const files = new Map<string, Uint8Array>(), directories = new Set<string>();
    let entries = 0, total = 0, ended = false;
    for (let at = 0; at + 512 <= tar.length;) {
        const header = tar.subarray(at, at + 512);
        if (header.every(b => b === 0)) {
            ended = true;
            break;
        }
        if (++entries > CARGO_BUDGET.entries)
            throw new Error(`${name}: archive has too many entries.`);
        let checksum = 0;
        for (let i = 0; i < 512; i++)
            checksum += i >= 148 && i < 156 ? 32 : header[i];
        if (checksum !== octal(header.subarray(148, 156)))
            throw new Error(`${name}: invalid tar header checksum.`);
        const prefix = field(header.subarray(345, 500)), leaf = field(header.subarray(0, 100));
        let path = (prefix ? prefix + '/' : '') + leaf;
        const kind = header[156], size = octal(header.subarray(124, 136));
        at += 512;
        if (kind !== 0 && kind !== 48 && kind !== 53)
            throw new Error(`${name}: links and special tar entries are not accepted.`);
        if (kind === 53)
            path = path.replace(/\/$/, '');
        if (!pathOK(path) || !path.startsWith(name + '-' + version + '/') && path !== name + '-' + version)
            throw new Error(`${name}: unsafe archive path.`);
        if (size > CARGO_BUDGET.fileBytes || at + size > tar.length)
            throw new Error(`${name}: oversized or truncated archive file.`);
        const relative = path.slice((name + '-' + version + '/').length);
        if (kind === 53) {
            if (size !== 0)
                throw new Error(`${name}: invalid directory entry.`);
            if (relative)
                directories.add(relative);
        }
        else {
            if (!relative || files.has(relative))
                throw new Error(`${name}: duplicate archive file.`);
            total += size;
            if (total > CARGO_BUDGET.crateBytes)
                throw new Error(`${name}: extracted file limit.`);
            files.set(relative, tar.slice(at, at + size));
        }
        at += Math.ceil(size / 512) * 512;
    }
    if (!ended)
        throw new Error(`${name}: truncated archive.`);
    for (const path of files.keys()) {
        let parent = path;
        while (parent.includes('/')) {
            parent = parent.slice(0, parent.lastIndexOf('/'));
            if (files.has(parent))
                throw new Error(`${name}: file-directory collision.`);
        }
        if (directories.has(path))
            throw new Error(`${name}: file-directory collision.`);
    }
    const bytes = files.get('Cargo.toml');
    if (!bytes)
        throw new Error(`${name}: package manifest is missing.`);
    const table = manifestTable(decoder.decode(bytes)), pkg = table.package as Record<string, unknown> | undefined, lib = (table.lib ?? {}) as Record<string, unknown>;
    if (!pkg || pkg.name !== name || pkg.version !== version)
        throw new Error(`${name}: archive identity differs from the registry.`);
    if (pkg.links !== undefined || table['build-dependencies'] && Object.keys(table['build-dependencies'] as object).length)
        throw new Error(`${name}: native links or build dependencies need another Cargo profile.`);
    const buildScript = pkg.build === false ? undefined : typeof pkg.build === 'string' ? pkg.build : files.has('build.rs') ? 'build.rs' : undefined;
    if (pkg.build !== undefined && typeof pkg.build !== 'boolean' && typeof pkg.build !== 'string' || buildScript !== undefined && (!pathOK(buildScript) || !files.has(buildScript)))
        throw new Error(`${name}: invalid build script path.`);
    if (lib['proc-macro'] === true || Array.isArray(lib['crate-type']) && (lib['crate-type'] as unknown[]).some(v => v !== 'lib' && v !== 'rlib'))
        throw new Error(`${name}: host procedural macros and native crate types are not available in this browser.`);
    const libPath = typeof lib.path === 'string' ? lib.path : 'src/lib.rs', libName = typeof lib.name === 'string' ? lib.name : name.replaceAll('-', '_'), edition = String(pkg.edition ?? '2015');
    if (!pathOK(libPath) || !files.has(libPath) || !/^[A-Za-z_][A-Za-z0-9_]*$/.test(libName) || !['2015', '2018', '2021', '2024'].includes(edition))
        throw new Error(`${name}: unsupported library target.`);
    const env = ['CARGO_MANIFEST_DIR=/crates/' + name + '-' + version];
    for (const key of ['NAME', 'VERSION', 'DESCRIPTION', 'AUTHORS', 'HOMEPAGE', 'REPOSITORY', 'LICENSE', 'LICENSE_FILE', 'RUST_VERSION']) {
        const value = pkg[key.toLowerCase().replaceAll('_', '-')];
        const text = Array.isArray(value) ? value.join(':') : typeof value === 'string' ? value : '';
        if (text.length > 4096 || text.includes('\0'))
            throw new Error(`${name}: oversized package metadata.`);
        env.push('CARGO_PKG_' + key + '=' + text);
    }
    const [major, minor, patch] = version.split(/[.+-]/);
    env.push('CARGO_PKG_VERSION_MAJOR=' + major, 'CARGO_PKG_VERSION_MINOR=' + minor, 'CARGO_PKG_VERSION_PATCH=' + patch, 'CARGO_PKG_VERSION_PRE=' + (version.split('-')[1]?.split('+')[0] ?? ''));
    return { files, manifest: table, libPath, libName, edition, env, bytes: total, ...(buildScript ? { buildScript } : {}) };
}
