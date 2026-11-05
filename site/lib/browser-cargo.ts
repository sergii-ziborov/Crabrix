import { stringify, type TomlTable } from 'smol-toml';
import semver from 'semver';
import toolchain from './playground-toolchain.json' with { type: 'json' };
import { validatePlaygroundDocument, type PlaygroundDocument } from './playground-document.ts';
import { activeDependencies, cargoRange, crateName, dependencyTable, featureTable, manifestTable, readCargoRoot, type CargoDependency, type CargoRoot } from './browser-cargo-manifest.ts';
import { CARGO_BUDGET, digest, readCrateArchive, type CrateArchive } from './browser-cargo-archive.ts';
import { cargoTargetMatches } from './browser-cargo-target.ts';
export type CargoPin = {
    name: string;
    version: string;
    checksum: string;
};
export type PreparedCrate = CargoPin & {
    id: string;
    archive: CrateArchive;
    features: string[];
    dependencies: Record<string, string>;
};
export type PreparedCargo = {
    root: CargoRoot;
    packages: PreparedCrate[];
    dependencies: Record<string, string>;
    rootFeatures: string[];
    identity: string;
};
type Progress = (message: string) => void;
const enc = new TextEncoder(), hex = /^[a-f0-9]{64}$/;
const object = (v: unknown): Record<string, unknown> => v && typeof v === 'object' && !Array.isArray(v) ? v as Record<string, unknown> : {};
const cacheName = 'crabrix-cargo-source-v1-' + toolchain.compiler.expandedSHA256;
const key = (path: string) => new URL('/.crabrix-cargo/' + path, location.origin).href;
const assertActive = (signal: AbortSignal) => { if (signal.aborted)
    throw new DOMException('Package preparation canceled.', 'AbortError'); };
export async function cargoInputKey(source: PlaygroundDocument) { const root = readCargoRoot(source); return digest(enc.encode(JSON.stringify([toolchain.toolchainID, root?.path, root?.text, root?.lock]))); }
async function storage() { try {
    return await caches.open(cacheName);
}
catch {
    throw new Error('Browser storage is unavailable. Package sources cannot be retained safely; use Open in Crabrix.');
} }
function lockPackages(root: CargoRoot): Record<string, unknown>[] {
    if (!root.lock)
        return [];
    const lock = manifestTable(root.lock);
    if (lock.version !== 3 && lock.version !== 4)
        throw new Error('This browser Cargo profile reads Cargo.lock versions 3 and 4.');
    if (!Array.isArray(lock.package) || lock.package.length > 4096)
        throw new Error('Cargo.lock has no bounded package list.');
    return lock.package.map(object);
}
function matchingLock(root: CargoRoot, pin: CargoPin) { const matches = lockPackages(root).filter(p => p.source !== undefined && p.name === pin.name && p.version === pin.version); for (const item of matches)
    if (item.source !== 'registry+https://github.com/rust-lang/crates.io-index' || item.checksum !== pin.checksum)
        throw new Error(`${pin.name}: Cargo.lock checksum or registry differs from the prepared source.`); }
async function responseBytes(response: Response, max: number): Promise<Uint8Array> {
    if (!response.body)
        throw new Error('The cached response has no body.');
    const reader = response.body.getReader(), chunks: Uint8Array[] = [];
    let size = 0;
    while (true) {
        const item = await reader.read();
        if (item.done)
            break;
        size += item.value.length;
        if (size > max) {
            await reader.cancel();
            throw new Error('Cached package data exceeds its budget.');
        }
        chunks.push(item.value);
    }
    const bytes = new Uint8Array(size);
    let at = 0;
    for (const chunk of chunks) {
        bytes.set(chunk, at);
        at += chunk.length;
    }
    return bytes;
}
async function fetchBytes(url: string, max: number, signal: AbortSignal): Promise<Uint8Array> {
    assertActive(signal);
    const controller = new AbortController(), abort = () => controller.abort();
    signal.addEventListener('abort', abort, { once: true });
    const timer = setTimeout(abort, 30000);
    try {
        const response = await fetch(url, { credentials: 'omit', redirect: 'error', cache: 'no-store', signal: controller.signal });
        if (!response.ok || !response.body)
            throw new Error('Registry source could not be downloaded. Check connectivity and retry.');
        const reader = response.body.getReader(), chunks: Uint8Array[] = [];
        let size = 0;
        while (true) {
            const item = await reader.read();
            if (item.done)
                break;
            size += item.value.length;
            if (size > max) {
                await reader.cancel();
                throw new Error('Registry response exceeds its download budget.');
            }
            chunks.push(item.value);
        }
        const bytes = new Uint8Array(size);
        let at = 0;
        for (const chunk of chunks) {
            bytes.set(chunk, at);
            at += chunk.length;
        }
        return bytes;
    }
    finally {
        clearTimeout(timer);
        signal.removeEventListener('abort', abort);
    }
}
export function registryIndexPath(name: string) { if (!crateName(name))
    throw new Error('Invalid registry crate name.'); return name.length === 1 ? '1/' + name : name.length === 2 ? '2/' + name : name.length === 3 ? '3/' + name[0] + '/' + name : name.slice(0, 2) + '/' + name.slice(2, 4) + '/' + name; }
const msrvOK = (value: unknown) => value === undefined || value === null || typeof value === 'string' && /^\d+\.\d+(?:\.\d+)?$/.test(value) && !!semver.coerce(value) && semver.lte(semver.coerce(value)!, semver.coerce(toolchain.rustVersion)!);
export function selectRegistryVersion(text: string, dep: CargoDependency, locked: Record<string, unknown>[]): CargoPin {
    if (enc.encode(text).length > CARGO_BUDGET.indexBytes)
        throw new Error('Registry index is too large.');
    const lines = text.trim().split('\n');
    if (lines.length > 10000)
        throw new Error('Registry index has too many versions.');
    const versions: Record<string, unknown>[] = [];
    for (const line of lines) {
        const item = object(JSON.parse(line));
        if (item.name !== dep.name || typeof item.vers !== 'string' || !semver.valid(item.vers) || typeof item.cksum !== 'string' || !hex.test(item.cksum) || item.v !== undefined && item.v !== 1 && item.v !== 2)
            continue;
        if (typeof item.yanked !== 'boolean') continue;
        if (!msrvOK(item.rust_version))
            continue;
        const pin = locked.find(p => p.name === dep.name && p.version === item.vers);
        if (item.yanked === true && !pin)
            continue;
        if (semver.satisfies(item.vers, cargoRange(dep.requirement)))
            versions.push(item);
    }
    versions.sort((a, b) => semver.rcompare(a.vers as string, b.vers as string));
    const item = versions.find(v => locked.some(p => p.name === dep.name && p.version === v.vers)) ?? versions[0];
    if (!item)
        throw new Error(`${dep.name}: no non-yanked version satisfies ${dep.requirement} on Rust ${toolchain.rustVersion}.`);
    return { name: dep.name, version: item.vers as string, checksum: item.cksum as string };
}
function normalDependencies(archive: CrateArchive): CargoDependency[] {
    const dependencies = dependencyTable(archive.manifest.dependencies);
    for (const [selector, table] of Object.entries(object(archive.manifest.target))) {
        const target = object(table);
        if (!cargoTargetMatches(selector)) continue;
        if (Object.keys(object(target['build-dependencies'])).length)
            throw new Error('Target-specific build dependencies need another Cargo profile.');
        for (const dep of dependencyTable(target.dependencies)) {
            const previous = dependencies.find(item => item.alias === dep.alias);
            if (!previous) dependencies.push(dep);
            else {
                if (previous.name !== dep.name || previous.requirement !== dep.requirement)
                    throw new Error('Overlapping target dependencies require compatible identical version declarations.');
                previous.features = [...new Set([...previous.features, ...dep.features])];
                previous.defaults ||= dep.defaults;
                previous.optional &&= dep.optional;
            }
        }
    }
    const pkg = object(archive.manifest.package);
    if (!msrvOK(pkg['rust-version']))
        throw new Error('This dependency requires a newer Rust compiler.');
    return dependencies;
}
/** One version per crate, additive features, normal registry edges; conflicts are refused, never guessed away. */
export async function assembleCargoGraph(root: CargoRoot, resolve: (dep: CargoDependency) => Promise<{
    pin: CargoPin;
    archive: CrateArchive;
}>, signal: AbortSignal): Promise<PreparedCargo> {
    const nodes = new Map<string, PreparedCrate>(), wanted = new Map<string, {
        features: Set<string>;
        defaults: boolean;
        signature: string;
    }>(), queue = [...root.dependencies];
    let steps = 0, total = 0;
    while (queue.length) {
        assertActive(signal);
        if (++steps > 1024)
            throw new Error('The Cargo feature graph exceeds this browser profile.');
        const dep = queue.shift()!;
        let node = nodes.get(dep.name);
        if (!node) {
            if (nodes.size >= CARGO_BUDGET.packages)
                throw new Error(`The browser Cargo profile supports up to ${CARGO_BUDGET.packages} registry crates.`);
            const { pin, archive } = await resolve(dep);
            if (pin.name !== dep.name || !semver.valid(pin.version) || !semver.satisfies(pin.version, cargoRange(dep.requirement)) || !hex.test(pin.checksum))
                throw new Error('Prepared crate identity mismatch.');
            total += archive.bytes;
            if (total > CARGO_BUDGET.totalBytes)
                throw new Error('Prepared crate sources exceed 32 MiB.');
            node = { ...pin, id: pin.name + '@' + pin.version, archive, features: [], dependencies: Object.create(null) };
            nodes.set(dep.name, node);
        }
        if (!semver.satisfies(node.version, cargoRange(dep.requirement)))
            throw new Error(`${dep.name}: dependency versions conflict in this single-version browser profile. Pin compatible versions or use the native Cargo workflow.`);
        const request = wanted.get(dep.name) ?? { features: new Set<string>(), defaults: false, signature: '' };
        for (const feature of dep.features)
            request.features.add(feature);
        request.defaults ||= dep.defaults;
        const signature = JSON.stringify([[...request.features].sort(), request.defaults]);
        if (request.signature === signature)
            continue;
        request.signature = signature;
        wanted.set(dep.name, request);
        const active = activeDependencies(normalDependencies(node.archive), featureTable(node.archive.manifest.features), [...request.features], request.defaults);
        node.features = active.enabled;
        node.dependencies = Object.fromEntries(active.dependencies.map(d => [d.alias, d.name]));
        queue.push(...active.dependencies);
    }
    const ordered: PreparedCrate[] = [], visited = new Set<string>(), visiting = new Set<string>();
    function visit(name: string) { if (visited.has(name))
        return; if (visiting.has(name))
        throw new Error('Cyclic Cargo dependencies cannot be built.'); visiting.add(name); const node = nodes.get(name); if (!node)
        throw new Error('Incomplete prepared Cargo graph.'); for (const dep of Object.values(node.dependencies))
        visit(dep); visiting.delete(name); visited.add(name); ordered.push(node); }
    for (const dep of root.dependencies)
        visit(dep.name);
    const identity = await digest(enc.encode(JSON.stringify(ordered.map(p => [p.id, p.checksum, p.features, p.dependencies]))));
    return { root, packages: ordered, dependencies: Object.fromEntries(root.dependencies.map(d => [d.alias, d.name])), rootFeatures: root.enabled, identity };
}
async function cachedArchive(cache: Cache, pin: CargoPin): Promise<CrateArchive> { const response = await cache.match(key('archive/' + pin.checksum)); if (!response)
    throw new Error(`${pin.name}: prepared source is missing from this browser. Choose Prepare packages.`); const bytes = await responseBytes(response, CARGO_BUDGET.compressedBytes); if (await digest(bytes) !== pin.checksum)
    throw new Error(`${pin.name}: cached archive failed SHA-256 verification. Prepare packages again.`); return readCrateArchive(bytes, pin.name, pin.version); }
function updatedLock(root: CargoRoot, graph: PreparedCargo): string {
    const previous = lockPackages(root).filter(p => p.name !== root.name || p.source !== undefined), packages = [...previous];
    for (const node of graph.packages) {
        const entry = { name: node.name, version: node.version, source: 'registry+https://github.com/rust-lang/crates.io-index', checksum: node.checksum, ...(Object.keys(node.dependencies).length ? { dependencies: [...new Set(Object.values(node.dependencies).map(name => { const d = graph.packages.find(p => p.name === name)!; return d.name + ' ' + d.version; }))].sort() } : {}) };
        const at = packages.findIndex(p => p.name === node.name && p.version === node.version && p.source === entry.source);
        if (at >= 0)
            packages[at] = entry;
        else
            packages.push(entry);
    }
    packages.push({ name: root.name, version: root.version, dependencies: [...new Set(Object.values(graph.dependencies).map(name => { const p = graph.packages.find(p => p.name === name)!; return p.name + ' ' + p.version; }))].sort() });
    packages.sort((a, b) => String(a.name).localeCompare(String(b.name)) || String(a.version).localeCompare(String(b.version)));
    return '# Generated by Crabrix for the prepared registry graph.\n' + stringify({ version: 3, package: packages } as TomlTable);
}
export async function prepareBrowserCargo(source: PlaygroundDocument, signal: AbortSignal, progress: Progress, writeLock = true): Promise<{
    graph: PreparedCargo;
    lockPath: string;
    lockText: string;
    manifestText: string;
}> {
    const root = readCargoRoot(source);
    if (!root)
        throw new Error('Add a crate or create Cargo.toml first.');
    const cache = await storage(), indices = new Map<string, string>(), locked = lockPackages(root);
    const graph = await assembleCargoGraph(root, async (dep) => {
        progress(`Resolving ${dep.name} · ${dep.requirement}`);
        let index = indices.get(dep.name);
        if (!index) {
            index = new TextDecoder('utf-8', { fatal: true }).decode(await fetchBytes('https://raw.githubusercontent.com/rust-lang/crates.io-index/master/' + registryIndexPath(dep.name), CARGO_BUDGET.indexBytes, signal));
            indices.set(dep.name, index);
        }
        const pin = selectRegistryVersion(index, dep, locked);
        matchingLock(root, pin);
        let archive: CrateArchive;
        try {
            archive = await cachedArchive(cache, pin);
        }
        catch {
            progress(`Downloading ${pin.name} ${pin.version}`);
            const bytes = await fetchBytes(`https://static.crates.io/crates/${pin.name}/${pin.name}-${pin.version}.crate`, CARGO_BUDGET.compressedBytes, signal);
            if (await digest(bytes) !== pin.checksum)
                throw new Error(`${pin.name}: archive failed registry SHA-256 verification.`);
            archive = readCrateArchive(bytes, pin.name, pin.version);
            await cache.put(key('archive/' + pin.checksum), new Response(new Uint8Array(bytes)));
        }
        assertActive(signal);
        return { pin, archive };
    }, signal);
    const lockPath = root.prefix + 'Cargo.lock', lockText = updatedLock(root, graph);
    const future = writeLock ? validatePlaygroundDocument({ ...source, files: { ...source.files, [lockPath]: lockText } }) : source;
    const receipt = { version: 1, input: await cargoInputKey(future), packages: graph.packages.map(p => ({ name: p.name, version: p.version, checksum: p.checksum })) };
    assertActive(signal);
    await cache.put(key('graph/' + receipt.input), new Response(JSON.stringify(receipt), { headers: { 'Content-Type': 'application/json' } }));
    progress(`Prepared ${graph.packages.length} crate${graph.packages.length === 1 ? '' : 's'} · SHA-256 verified`);
    return { graph, lockPath, lockText, manifestText: root.text };
}
export async function loadPreparedCargo(source: PlaygroundDocument): Promise<PreparedCargo | null> {
    const root = readCargoRoot(source);
    if (!root || !root.dependencies.length)
        return null;
    const cache = await storage(), input = await cargoInputKey(source), response = await cache.match(key('graph/' + input));
    if (!response)
        throw new Error('Cargo source is not prepared for this manifest and lockfile. Choose Prepare packages on this device; Run does not download crates.');
    const text = new TextDecoder('utf-8', { fatal: true }).decode(await responseBytes(response, 64 * 1024));
    const receipt = JSON.parse(text);
    if (receipt.version !== 1 || receipt.input !== input || !Array.isArray(receipt.packages) || receipt.packages.length > CARGO_BUDGET.packages)
        throw new Error('Invalid prepared graph receipt.');
    const pins: CargoPin[] = receipt.packages;
    for (const pin of pins)
        if (!pin || !crateName(pin.name) || !semver.valid(pin.version) || !hex.test(pin.checksum))
            throw new Error('Invalid prepared package identity.');
    if (new Set(pins.map(p => p.name)).size !== pins.length)
        throw new Error('Ambiguous prepared graph.');
    const graph = await assembleCargoGraph(root, async (dep) => { const pin = pins.find(p => p.name === dep.name && semver.satisfies(p.version, cargoRange(dep.requirement))); if (!pin)
        throw new Error(`${dep.name}: prepared graph no longer matches the manifest.`); matchingLock(root, pin); return { pin, archive: await cachedArchive(cache, pin) }; }, new AbortController().signal);
    if (graph.packages.length !== pins.length)
        throw new Error('Prepared graph contains unrelated packages.');
    return graph;
}
