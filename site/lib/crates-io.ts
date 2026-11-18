import semver from 'semver';
import toolchain from './playground-toolchain.json' with { type: 'json' };

// Package discovery for the browser Packages panel, modelled on the native
// CratesIOClient. Requests go straight from the browser to the public
// crates.io API (it answers with `Access-Control-Allow-Origin: *`), carry no
// cookies or referrer, and contain only the search terms or crate name.

export const CRATES_IO_API = 'https://crates.io/api/v1';
export const CRATE_SEARCH_DEBOUNCE_MS = 350;
export const CRATE_SEARCH_PAGE_SIZE = 30;
const REQUEST_TIMEOUT_MS = 15000;

export type CrateSort = 'relevance' | 'downloads' | 'recent-downloads' | 'recent-updates' | 'new' | 'alpha';
export const CRATE_SORTS: readonly { value: CrateSort; title: string }[] = [
    { value: 'relevance', title: 'Relevance' },
    { value: 'downloads', title: 'Most downloaded' },
    { value: 'recent-downloads', title: 'Trending' },
    { value: 'recent-updates', title: 'Recently updated' },
    { value: 'new', title: 'Newest' },
    { value: 'alpha', title: 'Name' },
];
export const DEFAULT_CRATE_SORT: CrateSort = 'downloads';
export const isCrateSort = (value: unknown): value is CrateSort => CRATE_SORTS.some(sort => sort.value === value);

export type CrateSummary = {
    name: string;
    description?: string;
    downloads: number;
    recentDownloads?: number;
    maxVersion: string;
    repository?: string;
    exactMatch: boolean;
};
export type CrateSearchPage = { crates: CrateSummary[]; total: number };
export type CrateVersionInfo = {
    num: string;
    downloads: number;
    yanked: boolean;
    rustVersion?: string;
    createdAt?: string;
    hasLib?: boolean;
};
export type CrateDetails = { crate: CrateSummary; versions: CrateVersionInfo[] };
export type CrateOwnerInfo = { login: string; name?: string };

/** crates.io names are ASCII letters, digits, `-` and `_`, at most 64 characters. */
const registryName = (name: string) => /^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$/.test(name);
const object = (value: unknown): Record<string, unknown> => value && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : {};
const text = (value: unknown) => typeof value === 'string' && value.trim() ? value.trim() : undefined;
const count = (value: unknown) => typeof value === 'number' && Number.isFinite(value) && value >= 0 ? Math.floor(value) : undefined;

export function crateSearchURL(query: string, sort: CrateSort = DEFAULT_CRATE_SORT, page = 1, perPage = CRATE_SEARCH_PAGE_SIZE): string {
    const params = new URLSearchParams({
        q: query.trim().slice(0, 100),
        sort: isCrateSort(sort) ? sort : DEFAULT_CRATE_SORT,
        page: String(Math.max(1, Math.floor(page) || 1)),
        per_page: String(Math.min(100, Math.max(1, Math.floor(perPage) || CRATE_SEARCH_PAGE_SIZE))),
    });
    return `${CRATES_IO_API}/crates?${params}`;
}
export function crateDetailsURL(name: string): string {
    if (!registryName(name))
        throw new Error('Invalid crate name.');
    return `${CRATES_IO_API}/crates/${encodeURIComponent(name)}`;
}
export const crateOwnersURL = (name: string) => crateDetailsURL(name) + '/owners';
export const cratePageURL = (name: string) => `https://crates.io/crates/${encodeURIComponent(name)}`;

const COUNT_UNITS = [[1e9, 'B'], [1e6, 'M'], [1e3, 'K']] as const;
const compactAmount = (amount: number) => String(Number(amount.toFixed(amount >= 100 ? 0 : amount >= 10 ? 1 : 2)));
/** Same shape as the app's CrateCountFormatter: 999, 1.5K, 12.3M, 442M, 1.73B. */
export function compactCount(value: number): string {
    const n = count(value) ?? 0;
    for (let index = 0; index < COUNT_UNITS.length; index++) {
        const [size, suffix] = COUNT_UNITS[index];
        if (n < size)
            continue;
        const amount = compactAmount(n / size);
        // 999,999 would round to "1000K"; the next unit reads as "1M".
        if (Number(amount) >= 1000 && index > 0)
            return compactAmount(n / COUNT_UNITS[index - 1][0]) + COUNT_UNITS[index - 1][1];
        return amount + suffix;
    }
    return String(n);
}
export const exactCount = (value: number) => new Intl.NumberFormat('en-US').format(count(value) ?? 0);

/**
 * The requirement written to Cargo.toml for a chosen version, as in the app:
 * the bare version, which Cargo reads as a caret requirement (`^1.0.19`).
 * Build metadata is not part of a requirement, so it is dropped.
 */
export function versionRequirement(version: string | undefined): string {
    const bare = (version ?? '').trim().replace(/\+.*$/, '');
    return semver.valid(bare) ? bare : '';
}
/** Mirrors the browser resolver's MSRV gate: an unreadable rust-version is unsupported. */
export function rustVersionSupported(rustVersion: string | undefined, browserRust: string = toolchain.rustVersion): boolean {
    if (rustVersion === undefined)
        return true;
    if (!/^\d+\.\d+(?:\.\d+)?$/.test(rustVersion))
        return false;
    const needed = semver.coerce(rustVersion), available = semver.coerce(browserRust);
    return !!needed && !!available && semver.lte(needed, available);
}
/**
 * Preselects the crate's max_version like the app, unless that version is yanked
 * or needs a newer Rust than the browser compiler; then the highest usable stable
 * release, then any non-yanked version.
 */
export function preferredVersion(versions: readonly CrateVersionInfo[], maxVersion: string | undefined, browserRust: string = toolchain.rustVersion): string | undefined {
    const usable = (version: CrateVersionInfo) => !version.yanked && rustVersionSupported(version.rustVersion, browserRust);
    const max = versions.find(version => version.num === maxVersion);
    if (max && usable(max))
        return max.num;
    const stable = versions.filter(version => usable(version) && semver.valid(version.num) && !semver.prerelease(version.num))
        .sort((a, b) => semver.rcompare(a.num, b.num));
    return stable[0]?.num ?? versions.find(usable)?.num ?? versions.find(version => !version.yanked)?.num;
}
/** Only http(s) links from registry metadata are offered as links. */
export function safeExternalURL(raw: string | undefined): string | undefined {
    if (!raw)
        return undefined;
    try {
        const url = new URL(raw);
        return url.protocol === 'https:' || url.protocol === 'http:' ? url.href : undefined;
    }
    catch {
        return undefined;
    }
}

function crateSummary(value: unknown): CrateSummary | null {
    const item = object(value), name = text(item.name);
    const maxVersion = text(item.max_version) ?? text(item.newest_version) ?? text(item.default_version);
    if (!name || !registryName(name) || !maxVersion)
        return null;
    return {
        name,
        description: text(item.description)?.replace(/\s+/g, ' '),
        downloads: count(item.downloads) ?? 0,
        recentDownloads: count(item.recent_downloads),
        maxVersion,
        repository: text(item.repository),
        exactMatch: item.exact_match === true,
    };
}
/** Validates a search response; an exact name match is listed first. */
export function normalizeSearchPage(value: unknown): CrateSearchPage {
    const body = object(value);
    if (!Array.isArray(body.crates))
        throw new Error('crates.io returned an unreadable response.');
    const seen = new Set<string>(), crates: CrateSummary[] = [];
    for (const item of body.crates) {
        const crate = crateSummary(item);
        if (crate && !seen.has(crate.name)) {
            seen.add(crate.name);
            crates.push(crate);
        }
    }
    crates.sort((a, b) => Number(b.exactMatch) - Number(a.exactMatch));
    return { crates, total: count(object(body.meta).total) ?? crates.length };
}
/** Versions newest first by publication date, as in the app. */
export function normalizeCrateDetails(value: unknown): CrateDetails {
    const body = object(value), crate = crateSummary(body.crate);
    if (!crate || !Array.isArray(body.versions))
        throw new Error('crates.io returned an unreadable response.');
    const seen = new Set<string>(), versions: CrateVersionInfo[] = [];
    for (const raw of body.versions) {
        const item = object(raw), num = text(item.num);
        if (!num || seen.has(num) || !semver.valid(num))
            continue;
        seen.add(num);
        versions.push({
            num,
            downloads: count(item.downloads) ?? 0,
            yanked: item.yanked === true,
            rustVersion: text(item.rust_version),
            createdAt: text(item.created_at),
            hasLib: typeof item.has_lib === 'boolean' ? item.has_lib : undefined,
        });
    }
    versions.sort((a, b) => (b.createdAt ?? '').localeCompare(a.createdAt ?? ''));
    return { crate, versions };
}
export function normalizeOwners(value: unknown): CrateOwnerInfo[] {
    const users = object(value).users;
    if (!Array.isArray(users))
        return [];
    return users.flatMap(raw => {
        const item = object(raw), login = text(item.login);
        return login ? [{ login, name: text(item.name) }] : [];
    });
}
export const ownerName = (owner: CrateOwnerInfo) => owner.name ?? owner.login;

async function getJSON(url: string, signal: AbortSignal): Promise<unknown> {
    signal.throwIfAborted();
    const controller = new AbortController(), abort = () => controller.abort();
    let timedOut = false;
    signal.addEventListener('abort', abort, { once: true });
    const timer = setTimeout(() => { timedOut = true; controller.abort(); }, REQUEST_TIMEOUT_MS);
    try {
        let response: Response;
        try {
            response = await fetch(url, { credentials: 'omit', redirect: 'error', referrerPolicy: 'no-referrer', signal: controller.signal });
        }
        catch (error) {
            if (signal.aborted)
                throw error;
            throw new Error(timedOut ? 'crates.io did not respond in time.' : 'Could not reach crates.io. Check the connection and try again.');
        }
        if (!response.ok)
            throw new Error(response.status === 404 ? 'crates.io has no crate with this name.' : `crates.io returned HTTP ${response.status}.`);
        try {
            return await response.json();
        }
        catch (error) {
            if (signal.aborted)
                throw error;
            throw new Error('crates.io returned an unreadable response.');
        }
    }
    finally {
        clearTimeout(timer);
        signal.removeEventListener('abort', abort);
    }
}

// Successful answers are kept for this page visit only, so going back or
// reopening the catalogue does not repeat a request.
const searchCache = new Map<string, CrateSearchPage>(), detailsCache = new Map<string, CrateDetails>(), ownersCache = new Map<string, CrateOwnerInfo[]>();
function remember<T>(cache: Map<string, T>, key: string, value: T, limit: number): T {
    cache.delete(key);
    cache.set(key, value);
    while (cache.size > limit)
        cache.delete(cache.keys().next().value!);
    return value;
}
const searchKey = (query: string, sort: CrateSort) => sort + '\n' + query.trim().slice(0, 100);
export const cachedCrateSearch = (query: string, sort: CrateSort) => searchCache.get(searchKey(query, sort));
export async function searchCrates(query: string, sort: CrateSort, signal: AbortSignal): Promise<CrateSearchPage> {
    const key = searchKey(query, sort), cached = searchCache.get(key);
    if (cached)
        return cached;
    return remember(searchCache, key, normalizeSearchPage(await getJSON(crateSearchURL(query, sort), signal)), 40);
}
export async function loadCrateDetails(name: string, signal: AbortSignal): Promise<CrateDetails> {
    const cached = detailsCache.get(name);
    if (cached)
        return cached;
    return remember(detailsCache, name, normalizeCrateDetails(await getJSON(crateDetailsURL(name), signal)), 20);
}
export async function loadCrateOwners(name: string, signal: AbortSignal): Promise<CrateOwnerInfo[]> {
    const cached = ownersCache.get(name);
    if (cached)
        return cached;
    return remember(ownersCache, name, normalizeOwners(await getJSON(crateOwnersURL(name), signal)), 40);
}
/** Test hook: forget remembered registry answers. */
export function clearCratesIOCache() {
    searchCache.clear();
    detailsCache.clear();
    ownersCache.clear();
}
