import test from "node:test";
import assert from "node:assert/strict";
import {
  CRATE_SORTS, DEFAULT_CRATE_SORT, clearCratesIOCache, compactCount, crateDetailsURL, crateOwnersURL, crateSearchURL, exactCount,
  loadCrateDetails, normalizeCrateDetails, normalizeOwners, normalizeSearchPage, preferredVersion, rustVersionSupported,
  safeExternalURL, searchCrates, versionRequirement,
} from "../lib/crates-io.ts";
import { addCargoDependency, cargoRange } from "../lib/browser-cargo-manifest.ts";
import { newPlaygroundDocument } from "../lib/playground-document.ts";

test("search URLs match the app's crates.io query and clamp paging", () => {
  const url = new URL(crateSearchURL("  serde json ", "recent-downloads", 2, 30));
  assert.equal(url.origin + url.pathname, "https://crates.io/api/v1/crates");
  assert.deepEqual([...url.searchParams], [["q", "serde json"], ["sort", "recent-downloads"], ["page", "2"], ["per_page", "30"]]);
  const empty = new URL(crateSearchURL("", DEFAULT_CRATE_SORT));
  assert.equal(empty.searchParams.get("q"), "");
  assert.equal(empty.searchParams.get("sort"), "downloads");
  const clamped = new URL(crateSearchURL("x".repeat(300), "bogus", 0, 500));
  assert.equal(clamped.searchParams.get("q").length, 100);
  assert.equal(clamped.searchParams.get("sort"), "downloads");
  assert.equal(clamped.searchParams.get("page"), "1");
  assert.equal(clamped.searchParams.get("per_page"), "100");
  assert.deepEqual(CRATE_SORTS.map(sort => sort.value), ["relevance", "downloads", "recent-downloads", "recent-updates", "new", "alpha"]);
  assert.deepEqual(CRATE_SORTS.map(sort => sort.title), ["Relevance", "Most downloaded", "Trending", "Recently updated", "Newest", "Name"]);
});

test("crate URLs accept registry names only", () => {
  assert.equal(crateDetailsURL("proc-macro2"), "https://crates.io/api/v1/crates/proc-macro2");
  assert.equal(crateOwnersURL("itoa"), "https://crates.io/api/v1/crates/itoa/owners");
  for (const name of ["", "../admin", "a/b", "serde?x=1", "x".repeat(65), "-lead"]) assert.throws(() => crateDetailsURL(name), /Invalid crate name/);
});

test("download counts use the app's compact form", () => {
  assert.equal(compactCount(0), "0");
  assert.equal(compactCount(999), "999");
  assert.equal(compactCount(1000), "1K");
  assert.equal(compactCount(1500), "1.5K");
  assert.equal(compactCount(12_345), "12.3K");
  assert.equal(compactCount(123_456), "123K");
  assert.equal(compactCount(999_999), "1M");
  assert.equal(compactCount(1_234_567), "1.23M");
  assert.equal(compactCount(442_331_304), "442M");
  assert.equal(compactCount(1_734_169_853), "1.73B");
  assert.equal(compactCount(-5), "0");
  assert.equal(compactCount(Number.NaN), "0");
  assert.equal(exactCount(1_734_169_853), "1,734,169,853");
});

test("a chosen version becomes a bare caret requirement Cargo accepts", () => {
  assert.equal(versionRequirement("1.0.19"), "1.0.19");
  assert.equal(versionRequirement(" 2.0.0-rc.1 "), "2.0.0-rc.1");
  assert.equal(versionRequirement("0.3.1+wasi-0.2"), "0.3.1");
  assert.equal(versionRequirement("not-a-version"), "");
  assert.equal(versionRequirement(undefined), "");
  assert.equal(cargoRange(versionRequirement("1.0.19")), ">=1.0.19 <2.0.0-0");
  const added = addCargoDependency(newPlaygroundDocument(), "itoa", versionRequirement("1.0.19"));
  assert.match(added.text, /\[dependencies\]\nitoa = "1\.0\.19"/);
});

test("MSRV gate and version preselection follow the browser resolver", () => {
  assert.equal(rustVersionSupported(undefined, "1.96.0-dev"), true);
  assert.equal(rustVersionSupported("1.96", "1.96.0-dev"), true);
  assert.equal(rustVersionSupported("1.96.1", "1.96.0-dev"), false);
  assert.equal(rustVersionSupported("1.70.0-nightly", "1.96.0-dev"), false);
  const v = (num, extra = {}) => ({ num, downloads: 1, yanked: false, ...extra });
  assert.equal(preferredVersion([v("2.0.0-rc.1"), v("1.2.0"), v("1.1.0")], "1.2.0", "1.96.0"), "1.2.0");
  assert.equal(preferredVersion([v("1.2.0", { yanked: true }), v("1.1.0"), v("1.0.0")], "1.2.0", "1.96.0"), "1.1.0");
  assert.equal(preferredVersion([v("2.0.0-rc.1"), v("1.2.0", { rustVersion: "1.99" }), v("1.0.9"), v("1.1.0")], "1.2.0", "1.96.0"), "1.1.0");
  assert.equal(preferredVersion([v("1.0.0", { yanked: true })], "1.0.0", "1.96.0"), undefined);
});

test("search responses are validated, deduplicated and list an exact match first", () => {
  const page = normalizeSearchPage({
    crates: [
      { name: "getrandom", max_version: "0.4.3", description: " Random\n bytes ", downloads: 10, recent_downloads: 2, exact_match: false },
      { name: "rand", max_version: "0.10.4", downloads: 9, recent_downloads: null, repository: "https://github.com/rust-random/rand", exact_match: true },
      { name: "rand", max_version: "0.10.4", downloads: 9 },
      { name: "../evil", max_version: "1.0.0" },
      { name: "noversion" },
      "junk",
    ],
    meta: { total: 3959 },
  });
  assert.deepEqual(page.crates.map(crate => crate.name), ["rand", "getrandom"]);
  assert.equal(page.total, 3959);
  assert.equal(page.crates[1].description, "Random bytes");
  assert.equal(page.crates[0].recentDownloads, undefined);
  assert.throws(() => normalizeSearchPage({ errors: [] }), /unreadable/);
});

test("crate details list versions newest first and keep yanked releases marked", () => {
  const details = normalizeCrateDetails({
    crate: { name: "demo", max_version: "1.1.0", downloads: 5 },
    versions: [
      { num: "1.0.0", created_at: "2025-01-01T00:00:00Z", downloads: 3, yanked: false, rust_version: null, has_lib: true },
      { num: "0.9.9", created_at: "2026-02-01T00:00:00Z", downloads: 1, yanked: true },
      { num: "1.1.0", created_at: "2026-01-01T00:00:00Z", downloads: 2, yanked: false, rust_version: "1.80" },
      { num: "garbage", created_at: "2027-01-01T00:00:00Z" },
    ],
  });
  assert.deepEqual(details.versions.map(version => version.num), ["0.9.9", "1.1.0", "1.0.0"]);
  assert.equal(details.versions[0].yanked, true);
  assert.equal(details.versions[1].rustVersion, "1.80");
  assert.equal(details.versions[2].rustVersion, undefined);
  assert.equal(details.versions[2].hasLib, true);
  assert.deepEqual(normalizeOwners({ users: [{ login: "dtolnay", name: "David Tolnay" }, { login: "bot", name: " " }, {}] }),
    [{ login: "dtolnay", name: "David Tolnay" }, { login: "bot", name: undefined }]);
  assert.equal(safeExternalURL("https://github.com/serde-rs/serde"), "https://github.com/serde-rs/serde");
  assert.equal(safeExternalURL("javascript:alert(1)"), undefined);
  assert.equal(safeExternalURL("not a url"), undefined);
});

test("registry requests omit credentials and referrer, reuse answers and explain failures", async () => {
  const previous = globalThis.fetch, calls = [];
  clearCratesIOCache();
  try {
    globalThis.fetch = async (url, init) => {
      calls.push([String(url), init]);
      if (String(url).includes("/crates/missing")) return new Response("{}", { status: 404 });
      if (String(url).includes("/crates/broken")) return new Response("not json", { status: 200 });
      return new Response(JSON.stringify({ crates: [{ name: "itoa", max_version: "1.0.19", downloads: 1 }], meta: { total: 1 } }));
    };
    const signal = new AbortController().signal;
    const first = await searchCrates("itoa", "downloads", signal), second = await searchCrates(" itoa ", "downloads", signal);
    assert.equal(first, second);
    assert.equal(calls.length, 1);
    assert.equal(calls[0][0], "https://crates.io/api/v1/crates?q=itoa&sort=downloads&page=1&per_page=30");
    assert.equal(calls[0][1].credentials, "omit");
    assert.equal(calls[0][1].referrerPolicy, "no-referrer");
    assert.equal(calls[0][1].headers, undefined);
    await assert.rejects(loadCrateDetails("missing", signal), /no crate with this name/);
    await assert.rejects(loadCrateDetails("broken", signal), /unreadable response/);
    globalThis.fetch = async () => { throw new TypeError("Failed to fetch"); };
    await assert.rejects(searchCrates("offline", "downloads", signal), /Could not reach crates\.io/);
    const aborted = new AbortController(); aborted.abort();
    await assert.rejects(searchCrates("other", "downloads", aborted.signal), error => error.name === "AbortError");
  } finally {
    globalThis.fetch = previous;
    clearCratesIOCache();
  }
});
