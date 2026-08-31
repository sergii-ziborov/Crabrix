import Foundation

enum AlgorithmVerificationCaseKind: String, Sendable {
    case visible
    case semantic
    case boundary
    case adversarial
    case normalisation
}

struct AlgorithmVerificationCase: Equatable, Sendable {
    let kind: AlgorithmVerificationCaseKind
    let input: String
    let expectedAnswer: String
}

/// App-private semantic probes for Algorithm Atlas. Every pattern must own at
/// least one input whose correct answer differs from the visible example. The
/// catalog builds two additional normalisation cases around these probes, so a
/// challenge is accepted only after four private harness calls.
enum AlgorithmVerificationData {
    private static func probe(
        _ input: String,
        _ expectedAnswer: String,
        kind: AlgorithmVerificationCaseKind = .boundary
    ) -> AlgorithmVerificationCase {
        AlgorithmVerificationCase(kind: kind, input: input, expectedAnswer: expectedAnswer)
    }

    private static let semanticProbes: [String: AlgorithmVerificationCase] = [
        // Linear scans and explicit state
        "linear-scan": probe("[1, 2, 3]", "-1"),
        "min-max-tracking": probe("[5, 5]", "0"),
        "frequency-counting": probe("[3, 2, 3, 2]", "2", kind: .adversarial),
        "running-accumulator": probe("[1, 2]", "-1"),
        "adjacent-pair-scan": probe("[1, 2, 3]", "0"),
        "stable-compaction": probe("[0, 0, 5]", "5"),
        "predicate-partition": probe("[1, 3]", "0"),
        "boyer-moore-majority": probe("[7, 7, 2]", "7"),
        "reservoir-sampling": probe("values=[5,6,7]; choices=[0,0,2]", "7"),
        "floyd-state-cycle": probe("next=[1,2,0]", "0"),

        // Hash maps and sets
        "hash-membership": probe("[1, 2, 3]", "false"),
        "hash-frequency": probe("abc; abd", "false"),
        "complement-lookup": probe("[2, 8] target=10", "0,1"),
        "group-by-key": probe("[abc,bca,foo]", "2"),
        "index-map": probe("[1, 2, 3, 2]", "2"),
        "coordinate-compression": probe("[5, 5, -1]", "1,1,0"),
        "longest-consecutive-set": probe("[9, 1, 2, 3, 10]", "3"),
        "bidirectional-map": probe("abba; red blue blue green", "false", kind: .adversarial),
        "randomized-set": probe("add1 add2 remove2 add3", "1,3"),
        "rolling-fingerprint": probe("digits=[9,9]", "99"),

        // Prefix sums and range queries
        "prefix-sum": probe("[1, 2, 3, 4]", "9"),
        "suffix-aggregate": probe("[2, 4, 1]", "4,4,1"),
        "equilibrium-index": probe("[2, 1, -1]", "0"),
        "difference-array": probe("n=4 updates=(0,1,2),(2,3,1)", "2,2,1,1"),
        "prefix-suffix-product": probe("[2,3,4]", "12,8,6"),
        "prefix-xor": probe("[0,1,1,1,1]", "0"),
        "prefix-sum-2d": probe("[[0,0],[1,2],[3,4]]", "10"),
        "imos-sweep": probe("n=4 updates=(0,1,2),(1,3,1)", "3"),
        "fenwick-tree": probe("n=4 adds=(1,3),(2,4),(4,8) query=4", "15"),
        "segment-tree": probe("values=[9,5,7] update=(1,6) query=0..2", "6"),

        // Two pointers
        "opposite-ends": probe("[1,2,3]", "false"),
        "same-direction": probe("[1,6,5]", "6,5"),
        "slow-fast": probe("[1,2,3,4,5]", "3"),
        "sorted-two-sum": probe("[1,8,9]", "2,3"),
        "palindrome-pointers": probe("Rust", "false"),
        "three-sum": probe("[0,0,0]", "1"),
        "dutch-flag": probe("[1,2,0]", "0,1,2"),
        "container-area": probe("[1,1]", "1"),
        "in-place-merge": probe("a=[2,0] m=1; b=[1]", "1,2"),
        "trapping-water": probe("[2,0,2]", "2"),

        // Sliding windows
        "fixed-window": probe("[1,1,1,5]", "7"),
        "variable-window": probe("[7]", "1"),
        "unique-window": probe("bbbbb", "1"),
        "at-most-k": probe("[1,2,3]", "2"),
        "exactly-k-difference": probe("[1,2]", "1"),
        "frequency-balanced-window": probe("ABC", "2"),
        "minimum-cover-window": probe("ABC", "ABC"),
        "monotonic-deque-window": probe("[4,2,12,3]", "12,12"),
        "rolling-window-statistic": probe("[1,2,3,4]", "2,3"),
        "dual-heap-window-median": probe("[2,1,4]", "2"),

        // Stacks, queues, and monotonic structures
        "delimiter-stack": probe("([)]", "false", kind: .adversarial),
        "postfix-evaluation": probe("5 2 -", "3"),
        "min-stack": probe("push7 push3 pop min", "7"),
        "queue-with-stacks": probe("enqueue1 enqueue2 dequeue front", "2"),
        "next-greater-stack": probe("[1,3,2]", "3,-1,-1"),
        "monotonic-increasing-stack": probe("[2,1,3]", "-1,-1,1"),
        "monotonic-decreasing-stack": probe("[10,20,15]", "1,2,1"),
        "circular-monotonic-stack": probe("[3,1,2]", "-1,2,3"),
        "expression-shunting-yard": probe("2 * 3 + 4", "2 3 * 4 +"),
        "largest-histogram": probe("[2,2]", "4"),

        // Sorting and selection
        "insertion-sort": probe("[3,1]", "1,3"),
        "selection-sort": probe("[1,2,3]", "0"),
        "merge-sort": probe("[(1,b),(1,a),(0,z)]", "0z,1b,1a"),
        "quicksort": probe("[2,2,1]", "1,2,2"),
        "heap-sort": probe("[0,-1]", "-1,0"),
        "counting-sort": probe("[5,0,5]", "0,5,5"),
        "radix-sort": probe("[10,1,0]", "0,1,10"),
        "bucket-sort": probe("[0.9,0.1]", "0.1,0.9"),
        "quickselect": probe("[9,1,5]", "9"),
        "median-of-medians": probe("[9,8,7,6,5]", "9"),

        // Binary search
        "binary-exact": probe("[1,3,9]", "2"),
        "lower-bound": probe("[4,4]", "0"),
        "upper-bound": probe("[1,4,4]", "3"),
        "first-last-position": probe("[8]", "0,0"),
        "rotated-search": probe("[0,1,2]", "0"),
        "peak-search": probe("[3,2,1]", "0"),
        "matrix-binary-search": probe("[[1,2],[3,4]]", "false"),
        "binary-search-answer": probe("weights=[1,2,3] days=3", "3"),
        "exponential-search": probe("[21,30]", "0"),
        "partition-median": probe("[1] and [3]", "2"),

        // Linked lists
        "list-reversal": probe("9->8", "8,9"),
        "list-middle": probe("1->2", "2"),
        "list-cycle": probe("values=[1,2,3] tail->none", "false"),
        "merge-two-lists": probe("1->3 and 2->4", "1,2,3,4"),
        "remove-nth-from-end": probe("1->2", "2"),
        "list-intersection": probe("A=1->9; B=2->9", "9"),
        "partition-list": probe("4->1", "1,4"),
        "reorder-list": probe("1->2->3->4", "1,4,2,3"),
        "copy-random-list": probe("values=[1] random=[null]", "1:null"),
        "reverse-k-group": probe("1->2", "1,2"),

        // Trees and BSTs
        "tree-preorder": probe("[1,2,3]", "1,2,3"),
        "tree-inorder": probe("[2,1,3]", "1,2,3"),
        "tree-postorder": probe("[1,2,3]", "2,3,1"),
        "tree-level-order": probe("[2,3,4]", "2,7"),
        "tree-height-balance": probe("[1,2,null,3]", "false"),
        "bst-search-insert": probe("BST=[2,1,3]", "1,2,3,5"),
        "lowest-common-ancestor": probe("tree=[5,1]", "5"),
        "tree-serialize": probe("tree=[1]", "1,#,#"),
        "tree-diameter": probe("[1,2]", "1"),
        "tree-rerooting": probe("n=3 edges=(0,1),(1,2)", "3,2,3"),

        // Heaps and streaming
        "binary-heap": probe("[3,1]", "1,3"),
        "top-k-minheap": probe("[1,2,3,4]", "4,3,2"),
        "kth-stream": probe("stream=[9,8,7,6]", "7,7"),
        "k-way-merge": probe("[1,10];[2,3];[4]", "1,2,3,4,10"),
        "closest-k-heap": probe("[(0,1),(2,0),(0,3)]", "0:1,2:0"),
        "two-heap-median": probe("[1,3]", "1,2"),
        "lazy-heap-deletion": probe("push5 push1 delete1 min", "5"),
        "priority-scheduling": probe("(id0,t0,d2),(id1,t0,d1),(id2,t3,d1)", "1,0,2"),
        "meeting-rooms-heap": probe("[(1,2),(2,3)]", "1"),
        "huffman-greedy-heap": probe("weights=[1,2,3]", "9"),

        // DFS, BFS, and graph traversal
        "adjacency-list": probe("n=3 edges=(0,1),(1,2)", "1"),
        "graph-dfs": probe("edges=(0,2),(0,1)", "0,1,2"),
        "graph-bfs": probe("n=4 edges=(0,1)", "0,1,-1,-1"),
        "connected-components": probe("n=4 edges=none", "4"),
        "grid-flood-fill": probe("[[1,0],[0,1]]", "1"),
        "bipartite-coloring": probe("n=3 edges=(0,1),(1,2),(2,0)", "false", kind: .adversarial),
        "undirected-cycle": probe("edges=(0,1),(1,2)", "false"),
        "kahn-topological": probe("n=3 edges=1->2", "0,1,2"),
        "dfs-topological": probe("n=3 edges=0->1", "2,0,1"),
        "strong-components": probe("edges=0->1,1->0,1->2", "0,1;2"),

        // Weighted graphs, spanning trees, and flow
        "dijkstra": probe("edges=0-1:2,0-2:5,1-2:1", "0,2,3"),
        "zero-one-bfs": probe("edges=0-1:1,1-3:1", "2"),
        "dag-shortest-path": probe("0->4:2", "2"),
        "prim-mst": probe("edges=0-1:2,1-2:3,0-2:10", "5"),
        "kruskal-mst": probe("edges=0-1:2,1-2:3,0-2:10", "2,3"),
        "bellman-ford": probe("edges=0->1:2,1->2:3", "0,2,5"),
        "floyd-warshall": probe("matrix=[[0,7,2],[inf,0,1],[inf,inf,0]]", "2"),
        "a-star": probe("start=0,0 goal=1,1", "2"),
        "bidirectional-bfs": probe("hit -> hot via [hot]", "2"),
        "dinic-max-flow": probe("0->3:7", "7"),

        // Backtracking and exhaustive search
        "subsets": probe("[9]", ";9"),
        "permutations": probe("[1,2,3]", "6"),
        "combinations": probe("[1,2]", "1,2"),
        "combination-sum": probe("candidates=[7]", "7"),
        "parentheses-generation": probe("n=1", "()"),
        "word-grid-search": probe("grid=A word=B", "false"),
        "palindrome-partition": probe("aaa", "4"),
        "n-queens": probe("n=4", "2"),
        "sudoku": probe("row0=53467891.", "2"),
        "meet-in-middle": probe("[1,2,3]", "false"),

        // Greedy choices and intervals
        "activity-selection": probe("[(1,2),(2,3)]", "2"),
        "merge-intervals": probe("[(1,2),(3,4)]", "1-2,3-4"),
        "insert-interval": probe("[(1,3),(9,10)]", "1-3,4-8,9-10"),
        "sweep-line-events": probe("[(1,2),(2,3)]", "1"),
        "jump-game": probe("[3,2,1,0,4]", "false", kind: .adversarial),
        "jump-game-two": probe("[1,1,1,1]", "3"),
        "gas-station": probe("gas=[2] cost=[1]", "0"),
        "partition-labels": probe("abc", "1,1,1"),
        "deadline-scheduling": probe("jobs=(d1,p5),(d1,p10)", "10"),
        "minimum-arrows": probe("[(1,5),(2,4)]", "1"),

        // One-dimensional dynamic programming
        "memoization": probe("n=5", "5"),
        "tabulation": probe("n=3", "3"),
        "rolling-dp": probe("cost=[1,2]", "1"),
        "house-robber": probe("[5,1,1,5]", "10"),
        "kadane": probe("[-5,-2]", "-2"),
        "coin-change-min": probe("coins=[11]", "1"),
        "word-break-dp": probe("text=apple dict=[app]", "false"),
        "decode-ways": probe("06", "0", kind: .adversarial),
        "lis-patience": probe("[3,2,1]", "1"),
        "zero-one-knapsack": probe("weights=[7] values=[10]", "10"),

        // Two-dimensional and compressed-state dynamic programming
        "grid-path-dp": probe("rows=2 cols=2", "2"),
        "subset-sum": probe("[5,5]", "false"),
        "longest-common-subsequence": probe("abc and def", "0"),
        "edit-distance": probe("a -> b", "1"),
        "longest-pal-subsequence": probe("abc", "1"),
        "matrix-chain": probe("dimensions=[10,20,30]", "6000"),
        "interval-dp": probe("[1]", "1"),
        "digit-dp": probe("bound=9 sum=5", "1"),
        "bitmask-dp": probe("matrix=[[0,1,10],[1,0,2],[10,2,0]]", "13"),
        "tree-dp": probe("tree=[1,2,3]", "5"),

        // Tries and string matching
        "string-frequency": probe("aabbc", "c"),
        "string-two-pointers": probe("Rust", "false"),
        "run-length-encoding": probe("ab", "a1b1"),
        "kmp": probe("text=aaaa pattern=aa", "0"),
        "z-algorithm": probe("aaaa", "0,3,2,1"),
        "rabin-karp": probe("text=aaaa pattern=aa", "0,1,2"),
        "trie": probe("words=[cat,dog] prefix=ca", "1"),
        "aho-corasick": probe("text=aaaa patterns=[a,aa]", "7"),
        "suffix-array": probe("aba", "2,0,1"),
        "manacher": probe("cbbd", "bb"),

        // Mathematics, bit manipulation, and combinatorics
        "euclid-gcd": probe("a=12 b=8", "4"),
        "bitmask-enumeration": probe("values=[2,3]", "3"),
        "xor-cancellation": probe("[9,1,1]", "9"),
        "sieve": probe("n=10", "2,3,5,7"),
        "fast-power": probe("base=2 exp=5 mod=13", "6"),
        "modular-inverse": probe("a=2 mod=5", "3"),
        "binomial-coefficients": probe("n=5 k=2", "10"),
        "gray-code": probe("n=2", "0,1,3,2"),
        "matrix-exponentiation": probe("n=10", "55"),
        "miller-rabin": probe("n=15", "false", kind: .adversarial),

        // Advanced data structures
        "sparse-table": probe("[1,2,3,4,5,6,7]", "1,3,5"),
        "disjoint-set-union": probe("n=4 unions=(0,1)", "3"),
        "lazy-segment-tree": probe("values=[0,0,0,0,0,0]", "9"),
        "treap": probe("insert4 insert2 delete4 inorder", "2"),
        "skip-list": probe("[3,6,7]", "false"),
        "dsu-rollback": probe("n=3 unions=(0,1) checkpoint union=(1,2) rollback query=(0,1)", "true"),
        "mo-algorithm": probe("[1,1,1,1,1,1]", "1,1,1"),
        "heavy-light": probe("edges=(0,1),(1,2),(1,3),(3,4) values=[1,1,1,1,1]", "4"),
        "centroid-decomposition": probe("n=5 edges=(0,1),(0,2),(0,3),(0,4)", "0"),
        "suffix-automaton": probe("aaa", "3"),
    ]

    static func semanticProbe(for patternID: String) -> AlgorithmVerificationCase? {
        semanticProbes[patternID]
    }

    static var coveredPatternIDs: Set<String> { Set(semanticProbes.keys) }
}
