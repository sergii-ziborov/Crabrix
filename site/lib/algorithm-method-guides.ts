// Public editorial guidance for choosing a method, separate from the gated
// worked solutions and quizzes. Keys are the existing Atlas unit anchors.
export type AlgorithmMethodGuide = { choose: string; check: string; rust: string };

export const algorithmMethodGuides: Record<string, AlgorithmMethodGuide> = {
  'algorithms-scans': {
    choose: 'Start with a scan when the answer can be updated from the next item and a small amount of retained state. A first-match query, running maximum and best subarray all visit a sequence, but retain different facts. Write a sentence describing the processed prefix before choosing the accumulator. This makes initialization and early stopping part of the argument, rather than special cases added after the loop.',
    check: 'Test an empty input, a one-item input and a sequence whose best answer is not at either end. An initial maximum of zero fails for all-negative data; an index and a value are different outputs.',
    rust: 'Use a borrowed slice and iter().enumerate() when positions matter. Choose an accumulator type that can hold the total, and use Option when absence is a real result.',
  },
  'algorithms-hashing': {
    choose: 'Choose a hash map when the next operation asks whether a key has appeared, how many times it appeared, or which earlier position belongs to it. A set answers membership; a map can retain a count or an index. Complement lookup replaces repeatedly searching an earlier prefix with a lookup, but the order of lookup and insertion determines whether an element can incorrectly match itself.',
    check: 'Expected constant-time lookup is not a worst-case guarantee, and extra storage usually grows with distinct keys. Include duplicates and distinguish an absent entry from a stored zero.',
    rust: 'HashMap::entry helps update counts without a second search. Do not depend on HashMap iteration order for canonical output; sort keys or use an ordered collection when ordering is part of the contract.',
  },
  'algorithms-ranges': {
    choose: 'Prefix sums trade a linear preprocessing pass for cheap queries on an unchanged sequence. Define prefix[0] as zero and prefix[i] as the sum before index i; then a half-open interval [l, r) uses prefix[r] minus prefix[l]. Difference arrays reverse the viewpoint: record range-update boundaries now and reconstruct values in a later scan. Two-dimensional variants need an explicit coordinate convention before inclusion and exclusion are applied.',
    check: 'A prefix-sum array does not cheaply support arbitrary interleaved updates. Check empty ranges, the full range and an interval starting at zero; use a Fenwick or segment tree if updates must be queried immediately.',
    rust: 'Reserve one extra prefix entry and keep positions separate from signed totals. A wider integer type can prevent overflow even when every individual input fits i32.',
  },
  'algorithms-two-pointers': {
    choose: 'Use two pointers when moving a boundary rules out candidates in a provable direction. Sorted two-sum can discard an endpoint because of ordering; stable compaction instead keeps a write position behind a read position. These are different invariants, despite both using two indices. Count total pointer advances across the whole run to establish linear work, instead of assuming that a nested loop must be quadratic.',
    check: 'Sortedness, stable output order and whether a pair may reuse one position are contract decisions. Sorting can change original indices. Test duplicate values, crossed boundaries and inputs shorter than two elements.',
    rust: 'Half-open intervals make an empty slice easier to handle than computing len() - 1 immediately. Separate reads and writes carefully when compacting a mutable slice.',
  },
  'algorithms-sliding-window': {
    choose: 'A sliding window is a contiguous interval whose state can be updated when an item enters or leaves. Fixed-width sums need both updates; a longest valid window also needs a rule for shrinking. Distinct-count constraints can use frequencies. A sum constraint with only nonnegative values may be monotone as the right boundary advances, while arbitrary negative values can invalidate that reasoning.',
    check: 'Do not apply a familiar shrink-until-valid loop without proving what moving the left boundary does. Distinguish at-most-k from exactly-k and test k equal to zero, repeated values and a window covering the entire input.',
    rust: 'Keep zero-count entries out of a distinct-key map, or maintain a separate distinct counter. Record half-open boundaries so the stored length is right - left.',
  },
  'algorithms-stacks-queues': {
    choose: 'A stack retains the most recent unresolved work; a queue retains the earliest. Monotonic stacks go further by removing candidates that a new value makes permanently irrelevant. In next-greater-element problems, a popped position receives its answer once, which explains the amortized bound. A monotonic deque combines this dominance argument with expiry from a moving window.',
    check: 'Decide whether equal values count as greater and whether you need values or positions. Keeping only values loses the ability to expire an old duplicate. Each push and pop must have a reason tied to the query.',
    rust: 'Vec works well for a stack; VecDeque provides efficient removal from the front. Use indices when answers refer to positions, and handle an empty last() with Option.',
  },
  'algorithms-sorting-selection': {
    choose: 'Sort when a global order enables later operations such as merging intervals, grouping equal keys or scanning adjacent values. Selection answers a narrower question: finding the kth item does not require fully sorting every element. Comparison sorting, counting and radix methods make different assumptions about keys. Account for the cost of establishing order before advertising a fast scan that depends on it.',
    check: 'Specify whether equal keys must retain their original order. Counting sort depends on the key range, not just the number of items. A fast average-case partition algorithm still needs a strategy for adversarial pivots.',
    rust: 'Choose sort or sort_unstable based on stability requirements, and define a consistent comparison. Use select_nth_unstable when a partition around one rank is sufficient; its remaining partitions are not sorted.',
  },
  'algorithms-binary-search': {
    choose: 'Binary search applies to an ordered partition, not only to a sorted list of numbers. Exact lookup, first-true boundary and minimum-feasible-answer problems require different return contracts. For answer search, prove that feasibility changes in one direction and include the cost of evaluating that predicate. State what the interval contains before each midpoint update so termination follows from a strictly smaller interval.',
    check: 'Test no matches, all matches, duplicates and an answer on each boundary. A non-monotone predicate cannot be rescued by changing midpoint arithmetic. A valid insertion position is not necessarily a found element.',
    rust: 'slice::binary_search returns Result with a found index or insertion position; duplicate matches are not a first-occurrence guarantee. partition_point can express lower and upper boundaries with the required predicate.',
  },
  'algorithms-linked-lists': {
    choose: 'Linked-list algorithms manipulate reachability rather than contiguous positions. Reversal preserves the unprocessed suffix while redirecting one link; slow and fast pointers compare positions reached at different speeds. Choose a representation before translating a diagram into code: an owned chain, an index arena and shared mutable nodes have different ownership costs even if the graph looks similar.',
    check: 'Include an empty list, a single node, a head change and the smallest cycle allowed by the representation. Pointer identity and equal node values are different questions. Do not use a cycle-based method on a representation that cannot contain a cycle.',
    rust: 'Option<Box<Node>> makes ownership transfer explicit for an acyclic chain. take() can detach a link before reattaching it; index-based arenas can simplify algorithms that require stable node identity.',
  },
  'algorithms-trees': {
    choose: 'Pick traversal order from the information a node needs. Preorder handles a node before descendants; postorder combines completed child results; breadth-first traversal groups nodes by distance from the root. A binary-search tree additionally promises an ordering relation, which an arbitrary binary tree does not. Recursive return values should state exactly what a subtree contributes to its parent.',
    check: 'A balanced-tree logarithmic search bound is not a guarantee for a skewed tree. Test missing children and a chain-shaped tree. Establish whether the input is actually a tree before relying on the absence of revisits.',
    rust: 'A Vec stack or VecDeque queue can replace deep recursion. Borrow nodes for inspection and separate an arena index from payload values when multiple edges refer to the same stored node.',
  },
  'algorithms-heaps-streaming': {
    choose: 'Use a heap when repeatedly removing the best current candidate matters more than retrieving every item in sorted order. A bounded heap can retain the largest k values while a stream arrives; two heaps can maintain a median with a size and ordering invariant. Lazy deletion postpones removal of obsolete entries, but every later access must recognize those stale entries.',
    check: 'Specify k equal to zero, fewer than k arrivals, duplicate priorities and ties in output order. The heap top is extremal; iterating the heap does not produce a sorted sequence. Count both live and stale storage in a lazy-deletion design.',
    rust: 'BinaryHeap is a max-heap; Reverse changes an orderable priority into a min-heap. Include a deterministic secondary key when equal priorities require a stable decision.',
  },
  'algorithms-graph-traversal': {
    choose: 'Use BFS for shortest paths measured in edges on an unweighted graph, and DFS for reachability, completion order or recursive structure. Marking a node when it is enqueued avoids repeated queue entries. Connected components require starting again from each unvisited vertex. Topological ordering adds a directed-acyclic precondition and a way to detect that the precondition failed.',
    check: 'Directed and undirected edges require different cycle checks. Include isolated vertices, disconnected components, self-loops and parallel edges when allowed. A traversal from one source cannot certify facts about unreachable components.',
    rust: 'Vec<Vec<usize>> is a straightforward adjacency list for dense vertex IDs. Keep a visited or color array separate from the frontier; an explicit stack avoids depending on an unbounded call stack.',
  },
  'algorithms-weighted-graphs': {
    choose: 'Choose shortest-path machinery from edge constraints: BFS for equal unit weights, 0–1 BFS for zero/one weights, and Dijkstra for nonnegative weights. Negative edges need a different argument, such as Bellman–Ford, or a topological order when the graph is a DAG. A minimum spanning tree connects vertices cheaply; it does not minimize every path from a chosen source. Flow solves a capacity-constrained question instead.',
    check: 'Keep unreachable distance distinct from a large finite value. Reject stale priority-queue entries and guard distance addition against overflow. Check negative-cycle handling where applicable, disconnected graphs and ties.',
    rust: 'Use BinaryHeap with Reverse for minimum distances and a type wide enough for whole paths. Store predecessor information separately when the required output is a path rather than only a cost.',
  },
  'algorithms-backtracking': {
    choose: 'Backtracking explores choices, restores state and explores the next choice. Define which prefix or partial assignment has already been decided, then prune only when no extension can satisfy the contract. Permutations, combinations and subsets differ in whether order and repeated choices matter. A good pruning rule saves a subtree of work; it must not silently discard a valid solution.',
    check: 'Estimate the search space before running it: a recursive implementation does not make exponential output polynomial. Test duplicate inputs and the empty choice. Separate stopping after one answer from enumerating every answer.',
    rust: 'Push a choice onto a Vec, recurse, then pop it on every path that continues the search. Clone only when retaining a completed answer; bound input size and recursion depth for interactive execution.',
  },
  'algorithms-greedy-intervals': {
    choose: 'A greedy method commits to a locally preferred choice and needs a reason that an optimal solution can share it. Earliest finishing time works for maximizing the count of compatible unweighted intervals, but not automatically for maximizing arbitrary weights. Merging intervals asks a different question again: it combines overlaps instead of selecting a compatible subset. Write the objective before choosing the sort key.',
    check: 'Define whether touching endpoints overlap. Build a small counterexample for a tempting alternative, such as selecting the shortest interval or the earliest start. If future choices depend on more state than the greedy rule preserves, consider dynamic programming.',
    rust: 'Sort interval records by the proved key, with an explicit tie-breaker. Keep endpoint arithmetic and comparison rules consistent across sorting, merging and acceptance checks.',
  },
  'algorithms-dynamic-1d': {
    choose: 'Dynamic programming is useful when multiple choices reuse the same subproblem. Name the meaning of dp[i] before writing a recurrence: best cost ending at i and best cost among the first i items are not interchangeable. Memoization discovers states on demand; tabulation visits them in a dependency order. Rolling state saves memory only when older states can no longer be needed.',
    check: 'Choose base cases from the state definition and distinguish unreachable from zero. A transition can accidentally reuse the current item if updates run in the wrong direction. Compare a small optimized instance with a simpler exhaustive reference.',
    rust: 'Vec<Option<Cost>> can represent unknown or unreachable states without an invented numeric sentinel. Read dependencies before overwriting rolling entries, and explain whether reconstructing a chosen solution needs extra storage.',
  },
  'algorithms-dynamic-2d': {
    choose: 'Add a state dimension only when it retains information needed by future decisions: two string prefixes for edit distance, an interval for a split problem, or a subset mask for a visited set. The number of states and the transitions examined per state jointly determine work. A compact recurrence is not necessarily cheap when each state scans many possible splits.',
    check: 'Prove the iteration order makes dependencies available. A memory-compressed table may lose the path needed for reconstruction. Count exponential subset states explicitly and test empty dimensions before indexing a final cell.',
    rust: 'A flat Vec can hold a rectangular table if row/column indexing is checked consistently. Calculate allocation size with checked arithmetic and choose input limits before constructing a large table in a browser or on a phone.',
  },
  'algorithms-strings-tries': {
    choose: 'String methods depend on what a symbol means. Byte-oriented matching is useful for a specified ASCII or byte contract; Unicode scalar values and user-perceived characters require different representations. KMP reuses a matched prefix after a mismatch; a trie shares prefixes among many keys. Rolling hashes speed comparisons probabilistically unless collisions are checked or the contract tolerates that risk.',
    check: 'Test repeated prefixes, an empty pattern and a mismatch immediately after a long match. State whether overlapping matches count. Do not claim collision-free equality solely because two hashes match, or assume every Rust string index is a character boundary.',
    rust: 'Use as_bytes() for byte contracts and chars() when scalar values are intended. A UTF-8 string cannot be sliced safely at arbitrary byte offsets; keep the representation consistent with output positions.',
  },
  'algorithms-math-bits': {
    choose: 'Number and bit techniques replace repeated work with algebraic structure. Euclid reduces a greatest-common-divisor problem; exponentiation by squaring follows the bits of an exponent. Bit masks represent small finite sets, but the number of subsets still doubles for each additional element. Modular arithmetic needs stated preconditions: reducing values modulo m does not make every division valid.',
    check: 'Test zero, one, the highest allowed bit and the largest permitted intermediate product. A modular inverse exists only under the required coprimality condition. Explain what a randomized test guarantees instead of treating a likely answer as a proof for every integer.',
    rust: 'Use an unsigned type for a fixed-width mask and guard shift counts. Widen products before reducing modulo a modulus, or use an overflow-safe multiplication method when the wider product still will not fit.',
  },
  'algorithms-advanced-structures': {
    choose: 'Choose a structure by its operation mix. A Fenwick tree is compact for prefix aggregates with suitable updates; a segment tree supports a broader family of interval combinations. A sparse table suits immutable data and a compatible query operation. Disjoint-set union tracks connectivity as components merge; rollback changes which optimizations are legal. Write the update and query contract before selecting a familiar name.',
    check: 'Lazy propagation needs a precise rule for composing pending updates and applying them to aggregates. An optimization valid for ordinary DSU can complicate rollback. Compare random small operation sequences with a plain array or simple connectivity reference.',
    rust: 'Store tree nodes in a Vec with explicit index conventions. Account for auxiliary and pending-update storage; checked size calculations and bounded inputs prevent an ambitious data structure from exhausting an interactive runtime.',
  },
};

export const algorithmGuideSources = [
  { title: 'Rust standard collections: operation costs and choosing a collection', url: 'https://doc.rust-lang.org/std/collections/index.html' },
  { title: 'Rust slice search, sorting and partition APIs', url: 'https://doc.rust-lang.org/std/primitive.slice.html' },
  { title: 'MIT 6.006: algorithm design and correctness lecture notes', url: 'https://ocw.mit.edu/courses/6-006-introduction-to-algorithms-spring-2020/pages/lecture-notes/' },
];
