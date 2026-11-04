import { exclusionReason, inspectLocalFiles, inspectZip, ZIP_LIMITS } from './playground-import-sources.ts';
import type { ImportInspection } from './playground-import-plan.ts';
function active(signal: AbortSignal) { if (signal.aborted)
    throw new DOMException('Import canceled.', 'AbortError'); }
function wait<T>(signal: AbortSignal, begin: (done: (value: T) => void, fail: (error: unknown) => void) => void): Promise<T> {
    return new Promise((resolve, reject) => {
        active(signal);
        const canceled = () => reject(new DOMException('Import canceled.', 'AbortError'));
        const finish = (work: () => void) => { signal.removeEventListener('abort', canceled); if (!signal.aborted)
            work(); };
        signal.addEventListener('abort', canceled, { once: true });
        begin(value => finish(() => resolve(value)), error => finish(() => reject(error)));
    });
}
/** Capture entry handles during the drop event; browsers clear DataTransfer afterwards. */
export function inspectDroppedFiles(transfer: DataTransfer, signal: AbortSignal): Promise<ImportInspection> {
    const entries = Array.from(transfer.items ?? []).filter(item => item.kind === 'file').map(item => item.webkitGetAsEntry?.() ?? null);
    const files = Array.from(transfer.files);
    return (async () => {
        if (files.length > ZIP_LIMITS.entries || entries.length > ZIP_LIMITS.entries)
            throw new Error('This drop has too many entries. Choose a smaller source folder.');
        if (files.length === 1 && /\.zip$/i.test(files[0].name) && !entries.some(entry => entry?.isDirectory)) {
            const file = files[0];
            if (file.size > ZIP_LIMITS.inputBytes)
                throw new Error('This archive is larger than 16 MiB. Import a smaller source folder.');
            const bytes = new Uint8Array(await file.arrayBuffer());
            active(signal);
            return inspectZip(bytes, file.name);
        }
        const found: {
            path: string;
            file: File;
        }[] = [];
        let visited = 0;
        async function walk(entry: FileSystemEntry, parent: string, depth: number): Promise<void> {
            active(signal);
            if (++visited > ZIP_LIMITS.entries || depth > 32)
                throw new Error('This drop has too many entries or nested folders. Choose a smaller source folder.');
            const path = parent ? `${parent}/${entry.name}` : entry.name;
            if (entry.isFile) {
                const file = await wait<File>(signal, (done, fail) => (entry as FileSystemFileEntry).file(done, fail));
                found.push({ path, file });
                return;
            }
            // Do not enumerate private or generated trees just to reject their contents later.
            if (exclusionReason(path + '/source.rs', 0))
                return;
            const reader = (entry as FileSystemDirectoryEntry).createReader();
            while (true) {
                const batch = await wait<FileSystemEntry[]>(signal, (done, fail) => reader.readEntries(done, fail));
                if (!batch.length)
                    break;
                for (const child of batch)
                    await walk(child, path, depth + 1);
            }
        }
        if (entries.length && entries.every(Boolean))
            for (const entry of entries)
                await walk(entry!, '', 0);
        else
            for (const file of files)
                found.push({ path: file.webkitRelativePath || file.name, file });
        if (!found.length)
            throw new Error('No source files were found. Use Import → Folder if this browser cannot read a dropped folder.');
        let selectedBytes = 0;
        const input: {
            path: string;
            bytes: Uint8Array;
        }[] = [], oversized = new Uint8Array(65537), empty = new Uint8Array();
        for (const { path, file } of found) {
            active(signal);
            const reason = exclusionReason(path, file.size);
            if (reason) {
                input.push({ path, bytes: file.size > 65536 ? oversized : empty });
                continue;
            }
            selectedBytes += file.size;
            if (selectedBytes > ZIP_LIMITS.extractedBytes)
                throw new Error('The selectable text exceeds 8 MiB. Choose a smaller source folder.');
            input.push({ path, bytes: new Uint8Array(await file.arrayBuffer()) });
        }
        active(signal);
        const result = inspectLocalFiles(input, 'files', 'Dropped files and folders');
        result.notes.push('Dropped folder names are kept. Private, build and vendor folders are skipped.');
        return result;
    })();
}
