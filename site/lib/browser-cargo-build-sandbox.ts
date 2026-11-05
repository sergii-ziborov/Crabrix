import { Directory, File, WASI } from '@bjorn3/browser_wasi_shim';

/** Additional host-side bounds for build.rs; no network, subprocesses or real FS. */
export function boundBuildScript(wasi: WASI, writable: number[], outputs: Map<string, File | Directory>[]) {
    const mutable = new Set(writable), imports = wasi.wasiImport;
    let writes = 0, opens = 0, operations = 0;
    const checkFiles = () => {
        let count = 0, bytes = 0;
        function visit(map: Map<string, File | Directory>, depth: number) {
            if (depth > 16) throw new Error('Build script directory nesting limit.');
            for (const [path, entry] of map) {
                if (++count > 256 || !path || path === '.' || path === '..' || path.includes('/') || path.includes('\\')) throw new Error('Build script generated file limit.');
                if (entry instanceof Directory) visit(entry.contents as Map<string, File | Directory>, depth + 1);
                else {
                    bytes += entry.data.length;
                    if (entry.data.length > 2 * 1024 * 1024 || bytes > 4 * 1024 * 1024) throw new Error('Build script generated data exceeds 4 MiB.');
                }
            }
        }
        for (const output of outputs) visit(output, 0);
    };
    for (const key of Object.keys(imports)) {
        const original = imports[key] as (...args: never[]) => number;
        // All imports are synchronous. Check after each allocation as well as
        // before mutation so sparse writes cannot allocate unbounded host data.
        Object.assign(imports, { [key]: (...args: (number | bigint)[]) => {
            if (++operations > 500_000) throw new Error('Build script system-call limit.');
            const fd = Number(args[0]);
            if (key === 'fd_renumber') throw new Error('Build script descriptor renumbering is unavailable.');
            if (['fd_allocate', 'fd_filestat_set_size'].includes(key)) throw new Error('Build scripts cannot resize guest files directly.');
            if (key === 'fd_seek' && (BigInt(args[1]) < -4_194_304n || BigInt(args[1]) > 4_194_304n) || key === 'fd_pwrite' && (BigInt(args[3]) < 0n || BigInt(args[3]) > 2_097_152n)) throw new Error('Build script file offset limit.');
            if (key === 'path_open') {
                if (++opens > 1024) throw new Error('Build script file-open limit.');
                if (!mutable.has(fd) && (Number(args[4]) & 9 || (BigInt(args[5]) & 64n) !== 0n)) throw new Error('Build script sources are read-only.');
            }
            if (key.startsWith('path_') && !['path_open', 'path_filestat_get', 'path_readlink'].includes(key) && !mutable.has(fd)) throw new Error('Build script sources are read-only.');
            if (['path_link', 'path_rename', 'path_symlink'].includes(key)) throw new Error('Build script links and renames are unavailable.');
            if (key === 'fd_write' || key === 'fd_pwrite') {
                if (fd !== 1 && fd !== 2 && !mutable.has(fd)) throw new Error('Build script sources are read-only.');
                const view = new DataView(wasi.inst.exports.memory.buffer), pointer = Number(args[1]) >>> 0, count = Number(args[2]) >>> 0;
                if (count > 1024 || pointer + count * 8 > view.byteLength) throw new Error('Invalid build script I/O vector.');
                for (let i = 0; i < count; i++) writes += view.getUint32(pointer + i * 8 + 4, true);
                if (writes > 4 * 1024 * 1024) throw new Error('Build script write budget exceeded.');
            }
            const result = original(...args as never[]);
            if (key === 'path_open' && result === 0) {
                const opened = new DataView(wasi.inst.exports.memory.buffer).getUint32(Number(args[8]), true);
                if (mutable.has(fd)) mutable.add(opened); else mutable.delete(opened);
            }
            if (key === 'fd_close') mutable.delete(fd);
            if (key.startsWith('path_') || ['fd_write', 'fd_pwrite'].includes(key)) checkFiles();
            return result;
        } });
    }
}
