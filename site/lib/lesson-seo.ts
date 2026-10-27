import type { Lesson } from "./courses";

// Only dates of recorded editorial changes, never the time of each build.
export const lessonModifiedDates: Record<string, string> = Object.fromEntries(
  ["strings", "collections", "number-types", "operators", "control-flow", "enums"].map((id) => [`basics/${id}`, "2026-10-20"]),
);
lessonModifiedDates["systems/ffi"] = "2026-10-20";
lessonModifiedDates["interview/q-ffi-abi"] = "2026-10-20";
lessonModifiedDates["interview/q-syscalls"] = "2026-10-20";
lessonModifiedDates["interview/q-dyn-generics"] = "2026-10-20";
for (const path of ["concurrency/pinning-intuition", "concurrency/async-cancellation",
  "projects/errors", "projects/doc-examples", "systems/cfg-features",
  "interview/q-indexes", "interview/q-complexity", "ownership/phantom-data"]) {
  lessonModifiedDates[path] = "2026-10-27";
}
// Every Atlas step was revised in this recorded editorial pass.
const atlasPatternsRevised20261027 = [
  "a-star", "activity-selection", "adjacency-list", "adjacent-pair-scan", "aho-corasick",
  "at-most-k", "bellman-ford", "bidirectional-bfs", "bidirectional-map", "binary-exact",
  "binary-heap", "binary-search-answer", "binomial-coefficients", "bipartite-coloring", "bitmask-dp",
  "bitmask-enumeration", "boyer-moore-majority", "bst-search-insert", "bucket-sort", "centroid-decomposition",
  "circular-monotonic-stack", "closest-k-heap", "coin-change-min", "combination-sum", "combinations",
  "complement-lookup", "connected-components", "container-area", "coordinate-compression", "copy-random-list",
  "counting-sort", "dag-shortest-path", "deadline-scheduling", "decode-ways", "delimiter-stack",
  "dfs-topological", "difference-array", "digit-dp", "dijkstra", "dinic-max-flow",
  "disjoint-set-union", "dsu-rollback", "dual-heap-window-median", "dutch-flag", "edit-distance",
  "equilibrium-index", "euclid-gcd", "exactly-k-difference", "exponential-search", "expression-shunting-yard",
  "fast-power", "fenwick-tree", "first-last-position", "fixed-window", "floyd-state-cycle",
  "floyd-warshall", "frequency-balanced-window", "frequency-counting", "gas-station", "graph-bfs",
  "graph-dfs", "gray-code", "grid-flood-fill", "grid-path-dp", "group-by-key",
  "hash-frequency", "hash-membership", "heap-sort", "heavy-light", "house-robber",
  "huffman-greedy-heap", "imos-sweep", "in-place-merge", "index-map", "insert-interval",
  "insertion-sort", "interval-dp", "jump-game", "jump-game-two", "k-way-merge",
  "kadane", "kahn-topological", "kmp", "kruskal-mst", "kth-stream",
  "largest-histogram", "lazy-heap-deletion", "lazy-segment-tree", "linear-scan", "lis-patience",
  "list-cycle", "list-intersection", "list-middle", "list-reversal", "longest-common-subsequence",
  "longest-consecutive-set", "longest-pal-subsequence", "lower-bound", "lowest-common-ancestor", "manacher",
  "matrix-binary-search", "matrix-chain", "matrix-exponentiation", "median-of-medians", "meet-in-middle",
  "meeting-rooms-heap", "memoization", "merge-intervals", "merge-sort", "merge-two-lists",
  "miller-rabin", "min-max-tracking", "min-stack", "minimum-arrows", "minimum-cover-window",
  "mo-algorithm", "modular-inverse", "monotonic-decreasing-stack", "monotonic-deque-window", "monotonic-increasing-stack",
  "n-queens", "next-greater-stack", "opposite-ends", "palindrome-partition", "palindrome-pointers",
  "parentheses-generation", "partition-labels", "partition-list", "partition-median", "peak-search",
  "permutations", "postfix-evaluation", "predicate-partition", "prefix-suffix-product", "prefix-sum",
  "prefix-sum-2d", "prefix-xor", "prim-mst", "priority-scheduling", "queue-with-stacks",
  "quickselect", "quicksort", "rabin-karp", "radix-sort", "randomized-set",
  "remove-nth-from-end", "reorder-list", "reservoir-sampling", "reverse-k-group", "rolling-dp",
  "rolling-fingerprint", "rolling-window-statistic", "rotated-search", "run-length-encoding", "running-accumulator",
  "same-direction", "segment-tree", "selection-sort", "sieve", "skip-list",
  "slow-fast", "sorted-two-sum", "sparse-table", "stable-compaction", "string-frequency",
  "string-two-pointers", "strong-components", "subset-sum", "subsets", "sudoku",
  "suffix-aggregate", "suffix-array", "suffix-automaton", "sweep-line-events", "tabulation",
  "three-sum", "top-k-minheap", "trapping-water", "treap", "tree-diameter",
  "tree-dp", "tree-height-balance", "tree-inorder", "tree-level-order", "tree-postorder",
  "tree-preorder", "tree-rerooting", "tree-serialize", "trie", "two-heap-median",
  "undirected-cycle", "unique-window", "upper-bound", "variable-window", "word-break-dp",
  "word-grid-search", "xor-cancellation", "z-algorithm", "zero-one-bfs", "zero-one-knapsack",
];
for (const pattern of atlasPatternsRevised20261027) {
  for (const stage of ["model", "recognize", "challenge"]) {
    lessonModifiedDates[`algorithms/algorithm.${pattern}.${stage}`] = "2026-10-27";
  }
}
export const courseModifiedDates: Record<string, string> = {
  basics: "2026-10-20", systems: "2026-10-27", interview: "2026-10-27",
  algorithms: "2026-10-27", ownership: "2026-10-27", projects: "2026-10-27", concurrency: "2026-10-27",
};

export function searchDescription(text: string): string {
  const plain = text.replace(/`/g, "").replace(/\s+/g, " ").trim();
  if (plain.length <= 170) return plain;
  const prefix = plain.slice(0, 167);
  return `${prefix.slice(0, prefix.lastIndexOf(" "))}…`;
}

export function lessonDescription(lesson: Lesson): string {
  const summary = searchDescription(lesson.writing?.summary || lesson.concept);
  return searchDescription(`${lesson.title}: ${summary}${summary.length < 60 ? " Study the Rust pattern, then try the exercise." : ""}`);
}
