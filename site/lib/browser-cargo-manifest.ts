import { parse, stringify, type TomlTable } from 'smol-toml';
import semver from 'semver';
import type { PlaygroundDocument } from './playground-document.ts';
import toolchain from './playground-toolchain.json' with { type: 'json' };
export type CargoDependency = {
    alias: string;
    name: string;
    requirement: string;
    features: string[];
    defaults: boolean;
    optional: boolean;
};
export type CargoFeatures = Record<string, string[]>;
export type CargoRoot = {
    path: string;
    prefix: string;
    text: string;
    lock: string;
    name: string;
    version: string;
    edition: '2021' | '2024';
    dependencies: CargoDependency[];
    features: CargoFeatures;
    enabled: string[];
};
const object = (v: unknown): Record<string, unknown> => v && typeof v === 'object' && !Array.isArray(v) ? v as Record<string, unknown> : {};
export const crateName = (name: string) => /^[a-z][a-z0-9_-]{0,63}$/.test(name) && !['__proto__', 'constructor', 'prototype'].includes(name);
export function manifestTable(text: string): Record<string, unknown> {
    if (new TextEncoder().encode(text).length > 128 * 1024)
        throw new Error('This Cargo manifest is larger than 128 KiB.');
    try {
        return parse(text);
    }
    catch {
        throw new Error('Cargo.toml is not valid TOML. Open it and correct the reported manifest.');
    }
}
export function cargoRange(value: string): string {
    if (value.length > 128 || /\|\||\s-\s|[\r\n]/.test(value))
        throw new Error(`Unsupported Cargo version requirement: ${value.slice(0, 128)}`);
    const req = value.trim() || '*';
    const normalized = /^[0-9]/.test(req) && !/[xX*]/.test(req) ? '^' + req : req;
    const range = semver.validRange(normalized.replaceAll(',', ' '));
    if (!range)
        throw new Error(`Unsupported Cargo version requirement: ${value}`);
    return range;
}
const strings = (v: unknown, label: string) => {
    if (v === undefined)
        return [];
    if (!Array.isArray(v) || v.length > 256 || v.some(s => typeof s !== 'string' || s.length > 128))
        throw new Error(`Invalid ${label}.`);
    return v as string[];
};
export function featureTable(value: unknown): CargoFeatures {
    if (value !== undefined && (!value || typeof value !== 'object' || Array.isArray(value)))
        throw new Error('Invalid Cargo features table.');
    const result: CargoFeatures = Object.create(null);
    for (const [name, list] of Object.entries(object(value))) {
        if (!/^[A-Za-z0-9_+.-]{1,128}$/.test(name))
            throw new Error('This browser Cargo profile does not support that feature name.');
        result[name] = strings(list, 'feature list');
    }
    return result;
}
export function dependencyTable(value: unknown): CargoDependency[] {
    if (value !== undefined && (!value || typeof value !== 'object' || Array.isArray(value)))
        throw new Error('Invalid Cargo dependencies table.');
    return Object.entries(object(value)).map(([alias, declared]) => {
        const item = typeof declared === 'string' ? { version: declared } : object(declared);
        if (!crateName(alias) || !Object.keys(item).length || ['path', 'git', 'workspace', 'registry', 'registry-index'].some(k => k in item))
            throw new Error(`${alias}: this browser profile accepts crates.io registry dependencies only.`);
        const name = typeof item.package === 'string' ? item.package : alias;
        if (!crateName(name) || item.version !== undefined && typeof item.version !== 'string')
            throw new Error(`Invalid dependency ${alias}.`);
        if (item.optional !== undefined && typeof item.optional !== 'boolean' || item['default-features'] !== undefined && typeof item['default-features'] !== 'boolean')
            throw new Error(`Invalid dependency flags for ${alias}.`);
        const requirement = typeof item.version === 'string' ? item.version : '*';
        cargoRange(requirement);
        const features = strings(item.features, 'dependency features');
        if (features.some(f => !/^[A-Za-z0-9_+.-]{1,128}$/.test(f)))
            throw new Error(`Invalid dependency features for ${alias}.`);
        return { alias, name, requirement, features, defaults: item['default-features'] !== false, optional: item.optional === true };
    });
}
/** Expand default/explicit features and optional edges without executing manifest data. */
export function activeDependencies(deps: CargoDependency[], table: CargoFeatures, requested: string[], defaults: boolean): {
    enabled: string[];
    dependencies: CargoDependency[];
} {
    const enabled = new Set<string>(), active = new Set(deps.filter(d => !d.optional).map(d => d.alias)), extras = new Map<string, Set<string>>();
    const explicit = new Set(Object.values(table).flat().filter(s => s.startsWith('dep:')).map(s => s.slice(4)));
    const queue = [...requested, ...(defaults && table.default ? ['default'] : [])];
    let steps = 0;
    for (let at = 0; at < queue.length; at++) {
        if (++steps > 2048)
            throw new Error('The Cargo feature graph is too large.');
        const name = queue[at];
        if (enabled.has(name))
            continue;
        if (!(name in table)) {
            const dep = deps.find(d => d.optional && d.alias === name && !explicit.has(name));
            if (!dep)
                throw new Error(`Unknown Cargo feature ${name}.`);
            enabled.add(name);
            active.add(name);
            continue;
        }
        enabled.add(name);
        for (const edge of table[name]) {
            if (edge.startsWith('dep:')) {
                const alias = edge.slice(4);
                if (!deps.some(d => d.alias === alias))
                    throw new Error(`Unknown optional dependency ${alias}.`);
                active.add(alias);
            }
            else if (edge.includes('/')) {
                const [raw, feature, ...more] = edge.split('/'), weak = raw.endsWith('?'), alias = weak ? raw.slice(0, -1) : raw;
                if (more.length || !feature || !deps.some(d => d.alias === alias))
                    throw new Error(`Unsupported Cargo feature edge ${edge}.`);
                if (!weak)
                    active.add(alias);
                const list = extras.get(alias) ?? new Set();
                list.add(feature);
                extras.set(alias, list);
            }
            else
                queue.push(edge);
        }
    }
    return { enabled: [...enabled].sort(), dependencies: deps.filter(d => active.has(d.alias)).map(d => ({ ...d, features: [...new Set([...d.features, ...(extras.get(d.alias) ?? [])])].sort() })) };
}
export function findCargoManifest(source: PlaygroundDocument): string | undefined {
    const parts = source.entryFile.split('/');
    parts.pop();
    while (true) {
        const path = [...parts, 'Cargo.toml'].join('/');
        if (source.files[path] !== undefined)
            return path;
        if (!parts.length)
            return;
        parts.pop();
    }
}
export function readCargoRoot(source: PlaygroundDocument): CargoRoot | null {
    const path = findCargoManifest(source);
    if (!path)
        return null;
    const text = source.files[path], table = manifestTable(text), pkg = object(table.package), prefix = path.slice(0, -'Cargo.toml'.length);
    if (table.workspace || table.patch || table.replace)
        throw new Error('Workspaces and registry overrides need the native Cargo workflow.');
    if (!Object.keys(pkg).length || typeof pkg.name !== 'string' || !crateName(pkg.name))
        throw new Error('Add a valid [package] name to Cargo.toml.');
    const version = pkg.version === undefined ? '0.0.0' : pkg.version;
    if (typeof version !== 'string' || !semver.valid(version))
        throw new Error('Use a valid package version; workspace inheritance is not available in this browser profile.');
    if (pkg['rust-version'] !== undefined && (typeof pkg['rust-version'] !== 'string' || !/^\d+\.\d+(?:\.\d+)?$/.test(pkg['rust-version']) || !semver.coerce(pkg['rust-version']) || semver.gt(semver.coerce(pkg['rust-version'])!, semver.coerce(toolchain.rustVersion)!)))
        throw new Error(`This package requires a newer or unrecognized Rust version; the browser uses ${toolchain.rustVersion}.`);
    // Imports already ask the user to choose the runner's supported edition.
    // Keep that explicit choice rather than silently changing it from Cargo.toml.
    const edition = source.edition;
    if (pkg.links !== undefined || pkg.build !== false && (pkg.build !== undefined || source.files[prefix + 'build.rs'] !== undefined) || Object.keys(object(table['build-dependencies'])).length)
        throw new Error('Build scripts and native build dependencies are not supported by this browser Cargo profile.');
    if (Object.keys(object(table.target)).length)
        throw new Error('Target-specific root dependencies need a separate Cargo profile; no requirements were omitted.');
    const dependencies = dependencyTable(table.dependencies), features = featureTable(table.features), active = activeDependencies(dependencies, features, [], true);
    return { path, prefix, text, lock: source.files[prefix + 'Cargo.lock'] ?? '', name: pkg.name, version, edition, dependencies: active.dependencies, features, enabled: active.enabled };
}
export function addCargoDependency(source: PlaygroundDocument, name: string, version: string): {
    path: string;
    text: string;
} {
    if (!crateName(name))
        throw new Error('Use a crates.io name with lowercase letters, digits, hyphens or underscores.');
    cargoRange(version);
    const path = findCargoManifest(source) ?? 'Cargo.toml', table = source.files[path] ? manifestTable(source.files[path]) : { package: { name: 'playground', version: '0.1.0', edition: source.edition } };
    if (table.workspace)
        throw new Error('Select a package rather than a virtual workspace.');
    const deps = object(table.dependencies);
    if (Object.hasOwn(deps, name))
        throw new Error(`${name} is already declared. Edit its existing Cargo.toml entry.`);
    table.dependencies = { ...deps, [name]: version.trim() || '*' };
    return { path, text: stringify(table as TomlTable) };
}
