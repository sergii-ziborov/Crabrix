import Foundation

/// Two hundred deliberately small pattern records grouped by the solution
/// method a learner should recognise. The prose and challenges are original;
/// the coverage mirrors common interview-study families without copying any
/// third-party problem statement.
enum AlgorithmCourseData {
    static let categories: [AlgorithmCategory] = seeds.map(\.category)

    private static let seeds: [AlgorithmCategorySeed] = [
        scans,
        hashing,
        ranges,
        pointers,
        windows,
        stacks,
        sorting,
        binarySearch,
        linkedLists,
        trees,
        heaps,
        graphTraversal,
        weightedGraphs,
        backtracking,
        greedy,
        dynamicOne,
        dynamicTwo,
        strings,
        mathBits,
        advanced,
    ]

    private static func p(
        _ id: String,
        _ title: String,
        _ difficulty: AlgorithmDifficulty,
        _ idea: String,
        _ uses: String,
        _ complexity: String,
        _ task: String,
        _ input: String,
        _ output: String
    ) -> AlgorithmPatternSeed {
        AlgorithmPatternSeed(
            id: id,
            title: title,
            difficulty: difficulty,
            idea: idea,
            useCases: uses,
            complexity: complexity,
            task: task,
            input: input,
            output: output
        )
    }

    private static let scans = AlgorithmCategorySeed(
        id: "scans",
        title: "Linear Scans & State",
        subtitle: "One pass, explicit state, and the invariants behind later patterns",
        systemImage: "arrow.right.to.line.compact",
        achievementTitle: "Scan Specialist",
        rustSketch: """
        fn scan(values: &[i32]) -> Option<usize> {
            for (index, value) in values.iter().enumerate() {
                if *value < 0 { return Some(index); }
            }
            None
        }
        """,
        patterns: [
            p("linear-scan", "Linear Scan", .easy, "Visit every element once and stop when the predicate is satisfied.", "unsorted lookup, validation, first or last matching position", "O(n) time · O(1) extra space", "Return the first index whose reading is negative, or -1 when none is negative.", "[4, 9, -2, 7]", "2"),
            p("min-max-tracking", "Min/Max Tracking", .easy, "Carry the best value seen so far and update it from each element.", "extrema, record highs, cheapest or most expensive observation", "O(n) time · O(1) extra space", "Return max - min for the sensor readings.", "[8, 3, 11, 6]", "8"),
            p("frequency-counting", "Frequency Counting", .easy, "Turn repeated observations into counts keyed by the observed value.", "duplicates, histograms, modes, inventory totals", "O(n) expected time · O(k) space", "Return the value that occurs most often; break ties by the smaller value.", "[4, 2, 4, 3, 2, 4]", "4"),
            p("running-accumulator", "Running Accumulator", .easy, "Fold a stream into one state such as a sum, product, checksum, or balance.", "totals, checksums, balances, stream summaries", "O(n) time · O(1) extra space", "Return the alternating sum a0 - a1 + a2 - a3 and so on.", "[7, 2, 5, 1]", "9"),
            p("adjacent-pair-scan", "Adjacent Pair Scan", .easy, "Compare each item with its predecessor while keeping only local context.", "trend changes, runs, inversions, boundary detection", "O(n) time · O(1) extra space", "Count positions where a reading is lower than the reading immediately before it.", "[3, 5, 4, 4, 1]", "2"),
            p("stable-compaction", "Stable Compaction", .medium, "Write kept elements forward so their relative order survives removal.", "remove-in-place, filtering buffers, zero compaction", "O(n) time · O(1) extra space", "Remove zeros stably and return the kept prefix as comma-separated values.", "[0, 4, 0, 2, 7, 0]", "4,2,7"),
            p("predicate-partition", "Predicate Partition", .medium, "Maintain a boundary between items that satisfy a predicate and those that do not.", "partitioning, preprocessing, quicksort-style boundaries", "O(n) time · O(1) extra space", "Place even values before odd values and return the boundary index after the evens.", "[5, 2, 8, 1, 4]", "3"),
            p("boyer-moore-majority", "Boyer–Moore Majority Vote", .medium, "Cancel different values in pairs so a strict majority remains as the candidate.", "strict-majority detection with constant memory", "O(n) time · O(1) space", "Return the strict majority value; the input guarantees that one exists.", "[2, 1, 2, 3, 2, 2, 4]", "2"),
            p("reservoir-sampling", "Reservoir Sampling", .medium, "Replace a fixed reservoir with decreasing probability while streaming unknown-length input.", "uniform sampling from streams and files too large for memory", "O(n) time · O(k) space", "For deterministic random choices [0,1,1,3], return the final one-item reservoir while scanning four values.", "values=[10,20,30,40]; choices=[0,1,1,3]", "40"),
            p("floyd-state-cycle", "Floyd State Cycle Detection", .hard, "Advance one state once and another twice; their meeting proves a cycle without a visited set.", "repeated state machines, linked transitions, duplicate-by-cycle reductions", "O(mu + lambda) time · O(1) space", "Given next indexes, return the first value in the cycle reached from index 0.", "next=[1,2,3,1]", "1"),
        ]
    )

    private static let hashing = AlgorithmCategorySeed(
        id: "hashing",
        title: "Hash Maps & Sets",
        subtitle: "Trade memory for direct membership, grouping, and complement lookup",
        systemImage: "number.square.fill",
        achievementTitle: "Hash Navigator",
        rustSketch: """
        use std::collections::HashMap;
        fn counts(values: &[i32]) -> HashMap<i32, usize> {
            let mut map = HashMap::new();
            for &value in values { *map.entry(value).or_insert(0) += 1; }
            map
        }
        """,
        patterns: [
            p("hash-membership", "Hash Membership", .easy, "Store seen keys so later membership checks are expected constant time.", "duplicate detection, visited values, allowlists and denylists", "O(n) expected time · O(n) space", "Return true when any badge ID occurs twice.", "[11, 8, 3, 8]", "true"),
            p("hash-frequency", "Hash Frequency Map", .easy, "Map each key to its number of occurrences in one pass.", "anagrams, top frequencies, multiset comparison", "O(n) expected time · O(k) space", "Return true when the two lowercase words have identical character counts.", "rust; tsur", "true"),
            p("complement-lookup", "Complement Lookup", .easy, "For each number, ask whether target - number has already appeared.", "pair sums, balanced deltas, matching requirements", "O(n) expected time · O(n) space", "Return the zero-based indexes of two values summing to target.", "[6, 4, 9, 7] target=13", "1,2"),
            p("group-by-key", "Group by Canonical Key", .medium, "Transform each item to a stable key and collect items sharing that key.", "anagram groups, bucketing records, equivalence classes", "O(total input) expected time · O(total input) space", "Group words by sorted letters and return the size of the largest group.", "[eat,tea,tan,ate,nat]", "3"),
            p("index-map", "Value-to-Index Map", .medium, "Remember the latest or earliest position associated with each value.", "distance between repeats, sparse lookup, reconciliation", "O(n) expected time · O(k) space", "Return the shortest distance between equal values.", "[5, 1, 9, 5, 1]", "3"),
            p("coordinate-compression", "Coordinate Compression", .medium, "Replace large ordered values with dense ranks while preserving comparisons.", "Fenwick indexes, sweep lines, sparse coordinates", "O(n log n) time · O(n) space", "Return dense zero-based ranks for the values in original order.", "[100, -5, 100, 20]", "2,0,2,1"),
            p("longest-consecutive-set", "Longest Consecutive Set Run", .medium, "Start only at values with no predecessor, then walk each consecutive run once.", "unsorted consecutive sequences and sparse integer runs", "O(n) expected time · O(n) space", "Return the length of the longest consecutive integer run.", "[100, 4, 200, 1, 3, 2]", "4"),
            p("bidirectional-map", "Bidirectional Mapping", .medium, "Maintain both key-to-value and value-to-key constraints to enforce a bijection.", "isomorphism, renaming, one-to-one assignments", "O(n) expected time · O(k) space", "Return true when pattern letters map one-to-one onto the words.", "abba; red blue blue red", "true"),
            p("randomized-set", "Indexed Randomized Set", .hard, "Combine a dense vector with a value-to-index map; delete by swapping with the last item.", "O(1) insert, delete, and random access", "O(1) expected per operation · O(n) space", "After add 4, add 9, remove 4, add 7, return the dense storage in any valid order shown sorted.", "add4 add9 remove4 add7", "7,9"),
            p("rolling-fingerprint", "Rolling Fingerprint", .hard, "Update a window hash by removing the outgoing contribution and adding the incoming one.", "substring search, duplicate blocks, content fingerprints", "O(n) expected time · O(1) rolling state", "Using base 10 and modulus 101, return the hash of digits 3,1,4.", "digits=[3,1,4]", "11"),
        ]
    )

    private static let ranges = AlgorithmCategorySeed(
        id: "ranges",
        title: "Prefix Sums & Range Queries",
        subtitle: "Precompute cumulative information so repeated range work becomes cheap",
        systemImage: "chart.bar.xaxis",
        achievementTitle: "Range Architect",
        rustSketch: """
        fn prefix(values: &[i64]) -> Vec<i64> {
            let mut sums = vec![0; values.len() + 1];
            for i in 0..values.len() { sums[i + 1] = sums[i] + values[i]; }
            sums
        }
        """,
        patterns: [
            p("prefix-sum", "Prefix Sum", .easy, "Store the sum before every boundary so a range is one subtraction.", "immutable range sums, cumulative totals, balance points", "O(n) build · O(1) query · O(n) space", "Return the sum from inclusive index 1 through 3.", "[5, 2, 7, 1, 4]", "10"),
            p("suffix-aggregate", "Suffix Aggregate", .easy, "Precompute information from right to left for queries about everything after a position.", "right-side maxima, suffix totals, partition checks", "O(n) build · O(1) query · O(n) space", "Return the suffix maximum at every index.", "[3, 1, 5, 2]", "5,5,5,2"),
            p("equilibrium-index", "Prefix/Suffix Balance", .easy, "Compare cumulative left state with total-minus-current-minus-left state.", "pivot indexes, balanced partitions, equal-load cuts", "O(n) time · O(1) extra space", "Return the first index whose left and right sums match.", "[1, 7, 3, 6, 5, 6]", "3"),
            p("difference-array", "Difference Array", .medium, "Mark only where a range update starts and stops, then integrate once.", "many offline range additions and schedule deltas", "O(n + q) time · O(n) space", "Apply +3 to indexes 1 through 3 and +2 to 2 through 4; return the final array.", "n=5 updates=(1,3,3),(2,4,2)", "0,3,5,5,2"),
            p("prefix-suffix-product", "Prefix/Suffix Product", .medium, "Combine the product before and after each index without division.", "product-except-self and exclusion aggregates", "O(n) time · O(1) output-excluded space", "Return the product of all values except the one at each position.", "[1,2,3,4]", "24,12,8,6"),
            p("prefix-xor", "Prefix XOR", .medium, "Use XOR self-cancellation so a range value is two prefix states combined.", "range XOR, parity masks, repeated-state detection", "O(n) build · O(1) query · O(n) space", "Return XOR from inclusive index 1 through 4.", "[5,1,7,3,2]", "7"),
            p("prefix-sum-2d", "2D Prefix Sum", .medium, "Store each rectangle from the origin and use inclusion-exclusion for any subrectangle.", "image regions, matrix queries, grid density", "O(rows*cols) build · O(1) query", "Return the sum of rows 1..2 and columns 0..1.", "[[1,2,3],[4,5,6],[7,8,9]]", "24"),
            p("imos-sweep", "Imos Sweep", .medium, "Record interval starts and ends, then sweep a running active count.", "coverage, bookings, overlapping demand", "O((n+q)) on discrete coordinates · O(n) space", "Parse n and inclusive (start,end,delta) updates; return the maximum simultaneous load.", "n=5 updates=(0,2,2),(1,3,3),(3,4,1)", "4"),
            p("fenwick-tree", "Fenwick Tree", .hard, "Store partial sums in power-of-two ranges and move indexes by their lowest set bit.", "dynamic prefix sums, frequency tables, inversion counts", "O(log n) update/query · O(n) space", "Apply the 1-indexed add operations and return the prefix sum through query.", "n=5 adds=(1,5),(3,2),(4,4) query=3", "7"),
            p("segment-tree", "Segment Tree", .hard, "Represent intervals as a binary tree so a query visits only canonical covering nodes.", "dynamic range min/max/sum and interval aggregation", "O(log n) update/query · O(n) space", "Build range minimum, apply the point update, then query the inclusive range.", "values=[5,4,7,2] update=(2,0) query=1..3", "0"),
        ]
    )

    private static let pointers = AlgorithmCategorySeed(
        id: "two-pointers",
        title: "Two Pointers",
        subtitle: "Use ordering or a maintained boundary to avoid nested scans",
        systemImage: "arrow.left.and.right",
        achievementTitle: "Pointer Pilot",
        rustSketch: """
        fn pair_sum(values: &[i32], target: i32) -> bool {
            let (mut left, mut right) = (0, values.len().saturating_sub(1));
            while left < right {
                match (values[left] + values[right]).cmp(&target) {
                    std::cmp::Ordering::Less => left += 1,
                    std::cmp::Ordering::Greater => right -= 1,
                    std::cmp::Ordering::Equal => return true,
                }
            }
            false
        }
        """,
        patterns: [
            p("opposite-ends", "Opposite-End Pointers", .easy, "Move inward from both ends when ordering tells which side cannot improve.", "sorted pairs, symmetry, boundary comparisons", "O(n) time · O(1) space", "Return true if the sorted values contain a pair summing to 10.", "[1,2,4,6,9]", "true"),
            p("same-direction", "Same-Direction Pointers", .easy, "Let a read pointer inspect every item while a write pointer marks the kept prefix.", "stable filtering, deduplication, in-place transforms", "O(n) time · O(1) space", "Remove values below 5 stably and return the kept prefix.", "[7,2,5,4,9]", "7,5,9"),
            p("slow-fast", "Slow/Fast Pointers", .easy, "Advance pointers at different rates so relative motion reveals a midpoint or cycle.", "linked-list middle, cycle detection, repeated transitions", "O(n) time · O(1) space", "Return the middle value; for even length choose the second middle.", "[4,8,15,16,23,42]", "16"),
            p("sorted-two-sum", "Sorted Two-Sum", .easy, "Compare the end-pair sum with the target and discard one impossible endpoint.", "one pair in sorted numeric data", "O(n) time · O(1) space", "Return one-based indexes of the pair summing to 17.", "[2,3,7,11,15]", "1,5"),
            p("palindrome-pointers", "Palindrome Pointers", .easy, "Compare normalized symbols from the outside inward and skip irrelevant input.", "palindrome validation and mirrored constraints", "O(n) time · O(1) space", "Ignore punctuation and case; return whether the text is a palindrome.", "Never odd or even", "true"),
            p("three-sum", "Three-Sum Reduction", .medium, "Sort, fix one value, and solve the remaining target with two pointers while skipping duplicates.", "unique triples and k-sum reductions", "O(n^2) time · O(1) excluding output", "Return the number of unique triples summing to zero.", "[-1,0,1,2,-1,-4]", "2"),
            p("dutch-flag", "Dutch National Flag", .medium, "Maintain less-than, unknown, and greater-than regions with three boundaries.", "three-way partitioning and duplicate-heavy quicksort", "O(n) time · O(1) space", "Sort values containing only 0, 1, and 2 in place.", "[2,0,2,1,1,0]", "0,0,1,1,2,2"),
            p("container-area", "Container Area", .medium, "The shorter boundary limits area, so only moving that boundary can improve the result.", "max area between ordered boundaries", "O(n) time · O(1) space", "Return the greatest area formed by two heights.", "[1,8,6,2,5,4,8,3,7]", "49"),
            p("in-place-merge", "Backward In-Place Merge", .medium, "Fill free capacity from the end so unread source values are never overwritten.", "merging sorted buffers with trailing capacity", "O(n+m) time · O(1) space", "Merge the second sorted list into the first buffer.", "a=[1,3,7,0,0,0] m=3; b=[2,5,6]", "1,2,3,5,6,7"),
            p("trapping-water", "Two-Pointer Rainwater", .hard, "The smaller side has a settled bound; accumulate its deficit before moving inward.", "water trapping and dual-boundary accumulation", "O(n) time · O(1) space", "Return total trapped units between bars.", "[0,1,0,2,1,0,1,3,2,1,2,1]", "6"),
        ]
    )

    private static let windows = AlgorithmCategorySeed(
        id: "sliding-window",
        title: "Sliding Window",
        subtitle: "Maintain exactly the state of one contiguous region",
        systemImage: "rectangle.and.hand.point.up.left.fill",
        achievementTitle: "Window Watcher",
        rustSketch: """
        fn best_k(values: &[i32], k: usize) -> i32 {
            let mut sum: i32 = values[..k].iter().sum();
            let mut best = sum;
            for right in k..values.len() {
                sum += values[right] - values[right - k];
                best = best.max(sum);
            }
            best
        }
        """,
        patterns: [
            p("fixed-window", "Fixed-Size Window", .easy, "Add the entering item and remove the leaving item instead of recomputing each range.", "fixed-length sums, averages, local scores", "O(n) time · O(1) extra space", "Return the greatest sum of any three adjacent values.", "[2,1,5,1,3,2]", "9"),
            p("variable-window", "Variable-Size Window", .easy, "Expand until a constraint fails, then shrink until it is valid again.", "minimum or maximum contiguous ranges under a monotone constraint", "O(n) time · O(1) or state space", "For positive values, return the minimum length with sum at least 7.", "[2,3,1,2,4,3]", "2"),
            p("unique-window", "Last-Seen Unique Window", .medium, "Jump the left boundary past a repeated symbol using its latest position.", "longest substring or subarray with unique items", "O(n) expected time · O(k) space", "Return the longest substring length without repeated characters.", "abcabcbb", "3"),
            p("at-most-k", "At-Most-K Window", .medium, "Keep a frequency state and shrink while more than k distinct values are present.", "longest range with bounded distinct items", "O(n) expected time · O(k) space", "Return the longest subarray containing at most two distinct values.", "[1,2,1,2,3,2,2]", "4"),
            p("exactly-k-difference", "Exactly-K by Difference", .medium, "Count windows with at most k and subtract those with at most k-1.", "exact distinct counts and exact bounded properties", "O(n) expected time · O(k) space", "Return the number of subarrays with exactly two distinct values.", "[1,2,1,2,3]", "7"),
            p("frequency-balanced-window", "Frequency-Balanced Window", .medium, "Track the dominant count so replacements needed equal window length minus that count.", "character replacement and bounded edits", "O(n) time · O(alphabet) space", "With at most one replacement, return the longest equal-character substring length.", "AABABBA", "4"),
            p("minimum-cover-window", "Minimum Cover Window", .hard, "Expand until all required multiplicities are covered, then shrink while coverage remains.", "smallest substring or range containing a multiset", "O(n) time · O(alphabet) space", "Return the shortest substring containing A, B, and C.", "ADOBECODEBANC", "BANC"),
            p("monotonic-deque-window", "Monotonic Deque Window", .hard, "Keep candidate indexes in decreasing value order and evict those outside the window.", "sliding maximum or minimum", "O(n) time · O(k) space", "Return maxima for every window of length three.", "[1,3,-1,-3,5,3,6,7]", "3,3,5,5,6,7"),
            p("rolling-window-statistic", "Rolling Mean and Variance", .hard, "Update sufficient statistics as samples enter and leave rather than retaining every computation.", "telemetry, anomaly windows, streaming statistics", "O(n) time · O(k) storage for eviction", "Return integer means for windows of length three.", "[2,4,6,8,10]", "4,6,8"),
            p("dual-heap-window-median", "Sliding Median with Two Heaps", .hard, "Balance lower and upper heaps while lazily deleting values that leave the window.", "window medians and percentile-like statistics", "O(n log k) time · O(k) space", "Return medians for every odd window of length three.", "[1,3,-1,-3,5,3,6,7]", "1,-1,-1,3,5,6"),
        ]
    )

    private static let stacks = AlgorithmCategorySeed(
        id: "stacks-queues",
        title: "Stack, Queue & Monotonic Patterns",
        subtitle: "Choose the removal order that matches the dependency",
        systemImage: "square.stack.3d.up.fill",
        achievementTitle: "Stack Tactician",
        rustSketch: """
        fn balanced(text: &str) -> bool {
            let mut stack = Vec::new();
            for ch in text.chars() {
                match ch {
                    '(' | '[' | '{' => stack.push(ch),
                    ')' => if stack.pop() != Some('(') { return false; },
                    ']' => if stack.pop() != Some('[') { return false; },
                    '}' => if stack.pop() != Some('{') { return false; },
                    _ => {}
                }
            }
            stack.is_empty()
        }
        """,
        patterns: [
            p("delimiter-stack", "Delimiter Stack", .easy, "Push open delimiters and require every close to match the most recent open.", "nested syntax, parsers, balanced scopes", "O(n) time · O(n) space", "Return true when the delimiters are correctly nested.", "{[()()]}[]", "true"),
            p("postfix-evaluation", "Postfix Evaluation", .easy, "Push operands and reduce the latest operands whenever an operator arrives.", "expression evaluators and stack machines", "O(n) time · O(n) space", "Evaluate the space-separated postfix expression.", "2 7 + 3 * 4 -", "23"),
            p("min-stack", "Min Stack", .easy, "Store each value together with the minimum at the moment it is pushed.", "constant-time minimum beside normal stack operations", "O(1) per operation · O(n) space", "After push 5, push 2, push 4, pop, return the minimum.", "push5 push2 push4 pop min", "2"),
            p("queue-with-stacks", "Queue from Two Stacks", .medium, "Reverse the input stack into an output stack only when the output side is empty.", "amortised FIFO from LIFO primitives", "O(1) amortised operation · O(n) space", "Execute the space-separated queue operations and return the value produced by front.", "enqueue3 enqueue5 enqueue8 dequeue dequeue enqueue2 front", "8"),
            p("next-greater-stack", "Next Greater Element", .medium, "Keep unresolved indexes in decreasing value order and resolve them when a larger value appears.", "next warmer day, next greater price, span queries", "O(n) time · O(n) space", "Return the next greater value to the right, or -1.", "[2,1,2,4,3]", "4,2,4,-1,-1"),
            p("monotonic-increasing-stack", "Monotonic Increasing Stack", .medium, "Pop larger candidates so the stack represents the nearest smaller boundary.", "nearest smaller values, histogram bounds, contribution counting", "O(n) time · O(n) space", "Return the previous strictly smaller value for each item, or -1.", "[4,5,2,10,8]", "-1,4,-1,2,2"),
            p("monotonic-decreasing-stack", "Monotonic Decreasing Stack", .medium, "Pop smaller candidates so unresolved values remain in decreasing order.", "stock span, next greater, visibility", "O(n) time · O(n) space", "Return the number of consecutive earlier days with price less than or equal to today.", "[100,80,60,70,60,75,85]", "1,1,1,2,1,4,6"),
            p("circular-monotonic-stack", "Circular Monotonic Stack", .hard, "Traverse indexes twice while storing each unresolved position only once.", "next greater in circular arrays", "O(n) time · O(n) space", "Return each value's next greater value in circular order.", "[1,2,1]", "2,-1,2"),
            p("expression-shunting-yard", "Shunting-Yard Parsing", .hard, "Use an operator stack to emit operations only when precedence and associativity allow.", "infix parsing and calculator implementations", "O(n) time · O(n) space", "Convert the infix expression to postfix tokens.", "3 + 4 * 2", "3 4 2 * +"),
            p("largest-histogram", "Largest Histogram Rectangle", .hard, "When height decreases, pop bars whose right boundary is now known and compute their maximal width.", "maximal rectangles and span-by-minimum problems", "O(n) time · O(n) space", "Return the largest rectangle area under the histogram.", "[2,1,5,6,2,3]", "10"),
        ]
    )

    private static let sorting = AlgorithmCategorySeed(
        id: "sorting-selection",
        title: "Sorting & Selection",
        subtitle: "Order everything, or isolate only the rank the problem needs",
        systemImage: "arrow.up.arrow.down.circle.fill",
        achievementTitle: "Sorting Smith",
        rustSketch: """
        fn insertion_sort(values: &mut [i32]) {
            for i in 1..values.len() {
                let mut j = i;
                while j > 0 && values[j] < values[j - 1] {
                    values.swap(j, j - 1);
                    j -= 1;
                }
            }
        }
        """,
        patterns: [
            p("insertion-sort", "Insertion Sort", .easy, "Grow a sorted prefix by shifting each new item to its insertion position.", "small inputs, nearly sorted data, online prefixes", "O(n^2) worst · O(n) best · O(1) space", "Sort the values in ascending order using a stable insertion process.", "[5,2,4,6,1,3]", "1,2,3,4,5,6"),
            p("selection-sort", "Selection Sort", .easy, "Select the minimum remaining value and place it at the next boundary.", "tiny arrays and minimum-swap teaching examples", "O(n^2) time · O(1) space", "Sort ascending and return the number of swaps performed by classic selection sort.", "[3,1,2]", "2"),
            p("merge-sort", "Merge Sort", .medium, "Sort halves independently, then merge two ordered streams without backtracking.", "stable sorting, linked data, inversion counting", "O(n log n) time · O(n) space", "Return the sorted values and preserve the original order of equal keys.", "[(2,a),(1,x),(2,b),(1,y)]", "1x,1y,2a,2b"),
            p("quicksort", "Quicksort", .medium, "Partition around a pivot, then recurse only on the two unresolved regions.", "fast general in-memory sorting", "O(n log n) average · O(n^2) worst · O(log n) stack average", "Sort the values using an in-place partition.", "[9,3,7,1,8,2]", "1,2,3,7,8,9"),
            p("heap-sort", "Heap Sort", .medium, "Build a max heap and repeatedly move the maximum into its final suffix position.", "bounded-memory worst-case sorting", "O(n log n) time · O(1) space", "Return the ascending ordering produced by an in-place max heap.", "[4,10,3,5,1]", "1,3,4,5,10"),
            p("counting-sort", "Counting Sort", .medium, "Count every key in a small known range and emit keys by frequency.", "dense bounded integers and histogram sorting", "O(n+k) time · O(k) space", "Sort values known to be in 0 through 5.", "[4,2,2,5,0,1,4]", "0,1,2,2,4,4,5"),
            p("radix-sort", "LSD Radix Sort", .medium, "Apply a stable bucket pass from the least significant digit toward the most significant.", "fixed-width nonnegative integers and identifiers", "O(d*(n+b)) time · O(n+b) space", "Sort the base-10 nonnegative integers.", "[170,45,75,90,802,24,2,66]", "2,24,45,66,75,90,170,802"),
            p("bucket-sort", "Bucket Sort", .medium, "Distribute values into range buckets, sort locally, and concatenate in bucket order.", "roughly uniform numeric distributions", "O(n+k) average · O(n^2) worst · O(n+k) space", "Bucket decimals by tenths and return ascending values.", "[0.42,0.32,0.23,0.52,0.25]", "0.23,0.25,0.32,0.42,0.52"),
            p("quickselect", "Quickselect", .hard, "Partition like quicksort but recurse only into the side containing the requested rank.", "kth order statistic without fully sorting", "O(n) average · O(n^2) worst · O(1) space", "Return the third smallest value.", "[7,10,4,3,20,15]", "7"),
            p("median-of-medians", "Median of Medians", .hard, "Choose a guaranteed-good pivot from medians of small groups before selecting one side.", "worst-case linear selection and adversarial inputs", "O(n) worst-case time · O(n) or in-place variants", "Return the fifth smallest value using deterministic selection.", "[12,3,5,7,4,19,26,1,9]", "7"),
        ]
    )

    private static let binarySearch = AlgorithmCategorySeed(
        id: "binary-search",
        title: "Binary Search",
        subtitle: "Exploit a monotone decision boundary, not only a sorted Vec",
        systemImage: "arrow.left.and.right.circle.fill",
        achievementTitle: "Search Cartographer",
        rustSketch: """
        fn lower_bound(values: &[i32], target: i32) -> usize {
            let (mut low, mut high) = (0, values.len());
            while low < high {
                let mid = low + (high - low) / 2;
                if values[mid] < target { low = mid + 1; } else { high = mid; }
            }
            low
        }
        """,
        patterns: [
            p("binary-exact", "Exact Binary Search", .easy, "Discard the half that cannot contain the target after comparing the midpoint.", "exact lookup in sorted random-access data", "O(log n) time · O(1) space", "Return the index of 9, or -1 if absent.", "[-1,0,3,5,9,12]", "4"),
            p("lower-bound", "Lower Bound", .easy, "Maintain the first position that may still hold a value greater than or equal to target.", "insertion positions, first valid value, duplicate ranges", "O(log n) time · O(1) space", "Return the first index whose value is at least 4.", "[1,2,4,4,7]", "2"),
            p("upper-bound", "Upper Bound", .easy, "Maintain the first position whose value is strictly greater than target.", "duplicate counts, right insertion positions", "O(log n) time · O(1) space", "Return the first index whose value is greater than 4.", "[1,2,4,4,7]", "4"),
            p("first-last-position", "First and Last Position", .medium, "Run two boundary searches instead of expanding linearly from one match.", "complete duplicate range in sorted data", "O(log n) time · O(1) space", "Return first and last index of 8.", "[5,7,7,8,8,10]", "3,4"),
            p("rotated-search", "Rotated Sorted Search", .medium, "At least one half remains sorted; use that fact to choose the viable side.", "lookup in a rotated distinct sorted array", "O(log n) time · O(1) space", "Return the index of 0.", "[4,5,6,7,0,1,2]", "4"),
            p("peak-search", "Peak Binary Search", .medium, "Compare adjacent slopes; one side is guaranteed to contain a peak.", "local maxima in unimodal or arbitrary peak-promising arrays", "O(log n) time · O(1) space", "Return any peak index.", "[1,2,3,1]", "2"),
            p("matrix-binary-search", "Flattened Matrix Search", .medium, "Map a flat midpoint back to row and column when rows form one global sorted order.", "sorted rectangular matrices", "O(log(rows*cols)) time · O(1) space", "Return true when 16 is present.", "[[1,3,5,7],[10,11,16,20],[23,30,34,60]]", "true"),
            p("binary-search-answer", "Binary Search on the Answer", .hard, "Search a numeric answer space whose feasibility predicate changes only once.", "minimum capacity, maximum minimum distance, allocation bounds", "O(log range * predicate) time", "Find the minimum daily capacity to ship weights in three days.", "weights=[1,2,3,4,5,6,7,8,9,10] days=3", "15"),
            p("exponential-search", "Exponential Search", .hard, "Double the search boundary until it brackets the target, then binary-search that finite range.", "unknown-length sorted streams and unbounded indexes", "O(log position) probes · O(1) space", "Return the index of 21 using exponential bracketing.", "[1,3,5,7,9,12,15,18,21,24]", "8"),
            p("partition-median", "Partition Median", .hard, "Binary-search a partition where every left-side value is no larger than every right-side value.", "median or kth item across two sorted arrays", "O(log min(n,m)) time · O(1) space", "Return the median of the two sorted arrays.", "[1,3] and [2,4]", "2.5"),
        ]
    )

    private static let linkedLists = AlgorithmCategorySeed(
        id: "linked-lists",
        title: "Linked List Techniques",
        subtitle: "Rewire ownership-like links without losing the unread suffix",
        systemImage: "link.circle.fill",
        achievementTitle: "Link Wrangler",
        rustSketch: """
        // Conceptual ownership-safe reversal:
        // while let Some(mut node) = head.take() {
        //     head = node.next.take();
        //     node.next = reversed;
        //     reversed = Some(node);
        // }
        """,
        patterns: [
            p("list-reversal", "Iterative List Reversal", .easy, "Detach the next link before redirecting the current node toward the reversed prefix.", "reverse traversal order and ownership-safe rewiring", "O(n) time · O(1) links", "Return the node values after reversing the list.", "1->2->3->4", "4,3,2,1"),
            p("list-middle", "Middle by Slow/Fast", .easy, "Move one pointer once and another twice so the slow pointer reaches the middle.", "middle node and half splitting", "O(n) time · O(1) space", "Return the second middle value of an even-length list.", "1->2->3->4->5->6", "4"),
            p("list-cycle", "Linked Cycle Detection", .easy, "Different pointer speeds meet inside a cycle but never in a finite acyclic list.", "cycle existence in pointer chains", "O(n) time · O(1) space", "Return true when the tail links back to node index 1.", "values=[3,2,0,-4] tail->1", "true"),
            p("merge-two-lists", "Merge Two Sorted Lists", .easy, "Always detach the smaller head and append it to the merged tail.", "sorted streams and divide-and-conquer merge", "O(n+m) time · O(1) links", "Return the merged sorted values.", "1->2->4 and 1->3->4", "1,1,2,3,4,4"),
            p("remove-nth-from-end", "Gap Pointer Removal", .medium, "Keep a fixed gap so the leading pointer reaching the end positions the trailing pointer before the target.", "nth from end without a length pass", "O(n) time · O(1) space", "Remove the second node from the end and return remaining values.", "1->2->3->4->5", "1,2,3,5"),
            p("list-intersection", "Pointer-Switch Intersection", .medium, "Switch each pointer to the other head so both traverse equal combined distance.", "shared-tail intersection without lengths", "O(n+m) time · O(1) space", "Return the first shared node value.", "A=4->1->8->4->5; B=5->6->1->8->4->5", "8"),
            p("partition-list", "Stable List Partition", .medium, "Build two stable chains around a pivot and join them after traversal.", "stable less-than partitioning", "O(n) time · O(1) links", "Partition around 3 while preserving order within both groups.", "1->4->3->2->5->2", "1,2,2,4,3,5"),
            p("reorder-list", "Reorder by Split, Reverse, Merge", .medium, "Find the middle, reverse the second half, then alternate nodes from both halves.", "outside-in list ordering", "O(n) time · O(1) links", "Reorder first, last, second, second-last and so on.", "1->2->3->4->5", "1,5,2,4,3"),
            p("copy-random-list", "Copy with Random Links", .hard, "Map old nodes to new nodes or interleave copies so arbitrary links can be reconstructed.", "deep copy of graphs shaped like a list", "O(n) time · O(n) map or O(1) interleaving", "Return copied values with random target indexes.", "values=[7,13,11] random=[null,0,1]", "7:null,13:0,11:1"),
            p("reverse-k-group", "Reverse Nodes in K-Groups", .hard, "Verify a complete group exists, reverse exactly that range, then reconnect both boundaries.", "block-wise list transformations", "O(n) time · O(1) links", "Reverse nodes in groups of three; leave a short suffix unchanged.", "1->2->3->4->5->6->7", "3,2,1,6,5,4,7"),
        ]
    )

    private static let trees = AlgorithmCategorySeed(
        id: "trees",
        title: "Tree Traversal & BST",
        subtitle: "Choose traversal order from when a node's result becomes known",
        systemImage: "tree.fill",
        achievementTitle: "Tree Climber",
        rustSketch: """
        fn height(node: Option<&Node>) -> usize {
            match node {
                None => 0,
                Some(node) => 1 + height(node.left.as_deref()).max(height(node.right.as_deref())),
            }
        }
        """,
        patterns: [
            p("tree-preorder", "Preorder DFS", .easy, "Process the node before its children so parent context is available first.", "serialization prefixes, copying, path construction", "O(n) time · O(h) stack", "Return preorder values of the level-order tree.", "[1,2,3,4,5,null,6]", "1,2,4,5,3,6"),
            p("tree-inorder", "Inorder DFS", .easy, "Visit left, node, then right; in a BST this emits sorted keys.", "BST iteration and expression trees", "O(n) time · O(h) stack", "Return inorder values of the BST.", "[4,2,6,1,3,5,7]", "1,2,3,4,5,6,7"),
            p("tree-postorder", "Postorder DFS", .easy, "Process children before the node so child results are complete when combined.", "height, deletion, subtree aggregation", "O(n) time · O(h) stack", "Return postorder values.", "[1,2,3,4,5,null,6]", "4,5,2,6,3,1"),
            p("tree-level-order", "Level-Order BFS", .easy, "Queue nodes and process exactly the current queue length to preserve level boundaries.", "shortest unweighted depth and level summaries", "O(n) time · O(w) queue", "Return level sums from root downward.", "[1,2,3,4,5,null,6]", "1,5,15"),
            p("tree-height-balance", "Height with Balance Sentinel", .medium, "Return height normally but propagate a sentinel immediately when a subtree is already unbalanced.", "balanced-tree validation without repeated heights", "O(n) time · O(h) stack", "Return true when every node's subtree heights differ by at most one.", "[3,9,20,null,null,15,7]", "true"),
            p("bst-search-insert", "BST Search and Insert", .medium, "Use the ordering invariant to follow one child and preserve it at insertion.", "ordered sets and maps", "O(h) time · O(h) stack or O(1) iterative", "Insert 5 and return inorder values.", "BST=[4,2,7,1,3]", "1,2,3,4,5,7"),
            p("lowest-common-ancestor", "Lowest Common Ancestor", .medium, "Combine child evidence; the first node reached from both targets is their lowest shared ancestor.", "hierarchy relationships and path convergence", "O(n) time · O(h) stack", "Return the lowest common ancestor of values 5 and 1.", "tree=[3,5,1,6,2,0,8,null,null,7,4]", "3"),
            p("tree-serialize", "Tree Serialize/Deserialize", .medium, "Emit null markers as well as values so structure is reconstructible, not only traversal order.", "persistence, transport, tree cloning", "O(n) time · O(n) output", "Serialize preorder using # for nulls.", "tree=[1,2,3,null,null,4,5]", "1,2,#,#,3,4,#,#,5,#,#"),
            p("tree-diameter", "Tree Diameter", .hard, "At each node combine the two deepest child paths while returning only the deepest one upward.", "longest path in a tree and path-through-node aggregation", "O(n) time · O(h) stack", "Return the diameter measured in edges.", "[1,2,3,4,5]", "3"),
            p("tree-rerooting", "Tree Rerooting DP", .hard, "Compute child-to-parent contributions, then propagate the outside contribution while changing the root.", "all-node distance sums and per-root tree answers", "O(n) time · O(n) space", "Return sum of distances from every node in the tree.", "n=4 edges=(0,1),(1,2),(1,3)", "5,3,5,5"),
        ]
    )

    private static let heaps = AlgorithmCategorySeed(
        id: "heaps-streaming",
        title: "Heaps & Streaming",
        subtitle: "Keep only the next best candidate instead of fully ordering the world",
        systemImage: "triangle.fill",
        achievementTitle: "Heap Keeper",
        rustSketch: """
        use std::cmp::Reverse;
        use std::collections::BinaryHeap;
        fn smallest(values: &[i32]) -> Option<i32> {
            let mut heap = BinaryHeap::new();
            for &value in values { heap.push(Reverse(value)); }
            heap.pop().map(|Reverse(value)| value)
        }
        """,
        patterns: [
            p("binary-heap", "Binary Heap", .easy, "Maintain a complete tree where every parent outranks its children.", "priority queues, repeated min or max extraction", "O(log n) push/pop · O(1) peek · O(n) space", "Insert 7, 2, 9, 4 into a min-heap and return pop order.", "[7,2,9,4]", "2,4,7,9"),
            p("top-k-minheap", "Top-K with a Min-Heap", .easy, "Keep a heap of only k winners and evict its smallest whenever it grows.", "largest k values and bounded leaderboards", "O(n log k) time · O(k) space", "Return the three largest values in descending order.", "[4,1,9,7,3,8]", "9,8,7"),
            p("kth-stream", "Kth Statistic in a Stream", .medium, "Keep k candidates so the heap root is the kth largest value after every insertion.", "live rank tracking and rolling thresholds", "O(log k) per item · O(k) space", "With k=3, return the kth largest after adding 4, 5, 8, 2, 10.", "stream=[4,5,8,2,10]", "4,4,5"),
            p("k-way-merge", "K-Way Heap Merge", .medium, "Push one frontier item per sorted source and advance only the source that wins.", "merge sorted lists, files, and event streams", "O(N log k) time · O(k) space", "Merge the three sorted sequences.", "[1,4,7];[2,5,8];[0,6,9]", "0,1,2,4,5,6,7,8,9"),
            p("closest-k-heap", "Bounded Heap for K Closest", .medium, "Keep the worst current winner at the root so a better candidate replaces it.", "nearest points, closest values, approximate neighbors", "O(n log k) time · O(k) space", "Return the two points closest to the origin, ordered by distance then coordinates.", "[(1,3),(-2,2),(2,-2),(5,1)]", "-2:2,2:-2"),
            p("two-heap-median", "Median from Two Heaps", .hard, "Keep the lower half in a max-heap and upper half in a min-heap with sizes differing by at most one.", "online medians and percentile pivots", "O(log n) insert · O(1) median · O(n) space", "Return medians after inserting 5, 2, 10, 4.", "[5,2,10,4]", "5,3.5,5,4.5"),
            p("lazy-heap-deletion", "Lazy Heap Deletion", .hard, "Record invalidated values separately and discard stale roots only when they surface.", "sliding heaps and priority updates without handles", "O(log n) amortised operation · O(n) space", "Apply the push/delete operations, then return the valid minimum requested by min.", "push4 push7 push2 delete2 min", "4"),
            p("priority-scheduling", "Priority Scheduling", .hard, "Order available work by the decision criterion while time controls when work becomes eligible.", "task scheduling, CPU queues, simulation", "O(n log n) time · O(n) space", "Run shortest available job first and return completion order by job ID.", "(id0,t0,d3),(id1,t1,d1),(id2,t1,d2)", "0,1,2"),
            p("meeting-rooms-heap", "Meeting Rooms Heap", .hard, "Sort by start time and reuse the room whose end time is smallest.", "minimum concurrent resources and interval allocation", "O(n log n) time · O(n) space", "Return the minimum rooms required.", "[(0,30),(5,10),(15,20)]", "2"),
            p("huffman-greedy-heap", "Huffman Merge Heap", .hard, "Repeatedly merge the two lightest items; the accumulated merge cost is optimal.", "prefix coding and minimum merge cost", "O(n log n) time · O(n) space", "Return the minimum total merge cost.", "weights=[5,9,12,13,16,45]", "224"),
        ]
    )

    private static let graphTraversal = AlgorithmCategorySeed(
        id: "graph-traversal",
        title: "DFS, BFS & Graph Traversal",
        subtitle: "Represent edges explicitly, then control frontier and visited state",
        systemImage: "circle.hexagongrid.fill",
        achievementTitle: "Graph Explorer",
        rustSketch: """
        use std::collections::VecDeque;
        fn bfs(graph: &[Vec<usize>], start: usize) -> Vec<usize> {
            let mut queue = VecDeque::from([start]);
            let mut seen = vec![false; graph.len()];
            let mut order = Vec::new();
            seen[start] = true;
            while let Some(node) = queue.pop_front() {
                order.push(node);
                for &next in &graph[node] {
                    if !seen[next] {
                        seen[next] = true;
                        queue.push_back(next);
                    }
                }
            }
            order
        }
        """,
        patterns: [
            p("adjacency-list", "Adjacency List", .easy, "Store only existing neighbors so traversal cost follows vertices plus edges.", "sparse graphs, networks, dependency relationships", "O(V+E) space", "Build an undirected adjacency list and return sorted neighbors of node 2.", "n=5 edges=(0,2),(1,2),(2,4)", "0,1,4"),
            p("graph-dfs", "Graph DFS", .easy, "Explore one branch fully while marking nodes before following outgoing edges.", "reachability, components, path existence", "O(V+E) time · O(V) space", "Return recursive DFS order using ascending neighbors from node 0.", "edges=(0,1),(0,2),(1,3),(2,4)", "0,1,3,2,4"),
            p("graph-bfs", "Graph BFS", .easy, "Process the frontier in queue order so first discovery has minimum edge count.", "unweighted shortest paths and layer expansion", "O(V+E) time · O(V) space", "Return distance in edges from node 0 to every node.", "n=5 edges=(0,1),(0,2),(1,3),(2,4)", "0,1,1,2,2"),
            p("connected-components", "Connected Components", .easy, "Start a traversal from every still-unseen node and count starts.", "islands, clusters, disconnected networks", "O(V+E) time · O(V) space", "Return the number of undirected connected components.", "n=6 edges=(0,1),(1,2),(3,4)", "3"),
            p("grid-flood-fill", "Grid Flood Fill", .medium, "Treat cells as graph nodes and traverse only neighbors satisfying the region predicate.", "islands, image fill, maze regions", "O(rows*cols) time · O(rows*cols) space worst", "Return the size of the component containing row 1 column 1.", "[[1,0,0],[1,1,0],[0,1,1]]", "5"),
            p("bipartite-coloring", "Bipartite Coloring", .medium, "Assign opposite colors across every edge and reject any edge whose endpoints match.", "two-team constraints and odd-cycle detection", "O(V+E) time · O(V) space", "Return whether the graph can be two-colored.", "n=4 edges=(0,1),(1,2),(2,3),(3,0)", "true"),
            p("undirected-cycle", "Undirected Cycle Detection", .medium, "During traversal ignore the edge back to the parent; any other seen neighbor closes a cycle.", "valid-tree checks and redundant connections", "O(V+E) time · O(V) space", "Return true when the undirected graph contains a cycle.", "edges=(0,1),(1,2),(2,0),(2,3)", "true"),
            p("kahn-topological", "Kahn Topological Sort", .medium, "Repeatedly remove zero-indegree nodes and decrement dependents; leftovers prove a cycle.", "course schedules and build dependency order", "O(V+E) time · O(V) space", "Return lexicographically smallest valid order.", "n=4 edges=0->1,0->2,1->3,2->3", "0,1,2,3"),
            p("dfs-topological", "DFS Topological Sort", .hard, "Append a node after all descendants; a gray-to-gray edge proves a directed cycle.", "dependency ordering and cycle diagnosis", "O(V+E) time · O(V) space", "Return reverse-postorder for ascending neighbors.", "n=4 edges=0->2,1->2,2->3", "1,0,2,3"),
            p("strong-components", "Strongly Connected Components", .hard, "Use finish order plus reversed edges, or low links, to collapse mutual reachability.", "dependency cycles, graph condensation, state machines", "O(V+E) time · O(V) space", "Return strongly connected components with sorted members.", "edges=0->1,1->2,2->0,2->3,3->4,4->3", "0,1,2;3,4"),
        ]
    )

    private static let weightedGraphs = AlgorithmCategorySeed(
        id: "weighted-graphs",
        title: "Shortest Paths, MST & Flow",
        subtitle: "Match edge guarantees to the correct shortest-path or connectivity proof",
        systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill",
        achievementTitle: "Route Engineer",
        rustSketch: """
        // Dijkstra invariant:
        // when the smallest tentative distance is popped and is current,
        // no later non-negative path can improve that node.
        """,
        patterns: [
            p("dijkstra", "Dijkstra", .medium, "Finalize the smallest tentative distance and relax its non-negative outgoing edges.", "single-source shortest paths with non-negative weights", "O((V+E) log V) time · O(V+E) space", "Return shortest distances from node 0.", "edges=0-1:4,0-2:1,2-1:2,1-3:1,2-3:5", "0,3,1,4"),
            p("zero-one-bfs", "0–1 BFS", .medium, "Push zero-cost edges to the deque front and unit-cost edges to the back.", "shortest paths with weights only 0 or 1", "O(V+E) time · O(V) space", "Return minimum cost from 0 to 3.", "edges=0-1:0,0-2:1,1-2:0,2-3:1", "1"),
            p("dag-shortest-path", "DAG Shortest Path", .medium, "Relax outgoing edges once in topological order because no path can return to an earlier node.", "weighted acyclic dependency graphs", "O(V+E) time · O(V) space", "Return shortest distance from 0 to 4.", "0->1:2,0->2:4,1->3:7,2->3:1,3->4:3", "8"),
            p("prim-mst", "Prim Minimum Spanning Tree", .medium, "Grow one connected tree by repeatedly choosing the cheapest edge crossing its boundary.", "minimum network wiring from a connected weighted graph", "O(E log V) time · O(V+E) space", "Return the MST total weight.", "edges=0-1:1,0-2:4,1-2:2,1-3:5,2-3:3", "6"),
            p("kruskal-mst", "Kruskal Minimum Spanning Tree", .medium, "Sort edges and add one only when union-find says it joins different components.", "minimum spanning forests and sparse edge lists", "O(E log E) time · O(V) DSU space", "Return the MST edge weights in chosen order.", "edges=0-1:1,0-2:4,1-2:2,1-3:5,2-3:3", "1,2,3"),
            p("bellman-ford", "Bellman–Ford", .hard, "Relax every edge V-1 times; an improvement on the next pass proves a reachable negative cycle.", "negative edges and negative-cycle detection", "O(VE) time · O(V) space", "Return shortest distances from 0.", "edges=0->1:4,0->2:5,1->2:-2", "0,4,2"),
            p("floyd-warshall", "Floyd–Warshall", .hard, "Allow intermediate vertices one by one and combine paths through the newly allowed vertex.", "all-pairs shortest paths on small dense graphs", "O(V^3) time · O(V^2) space", "Return shortest distance from 0 to 2.", "matrix=[[0,3,10],[inf,0,2],[inf,inf,0]]", "5"),
            p("a-star", "A* Search", .hard, "Prioritize distance-so-far plus an admissible estimate that never overstates remaining cost.", "goal-directed pathfinding with useful geometry", "O(E) worst · frontier depends on heuristic", "On a 4x4 empty grid, return shortest moves from (0,0) to (3,2) using Manhattan heuristic.", "start=0,0 goal=3,2", "5"),
            p("bidirectional-bfs", "Bidirectional BFS", .hard, "Expand the smaller frontier from each endpoint until the visited sets meet.", "unweighted shortest paths with one source and one target", "O(b^(d/2)) frontier typical · O(V) space", "Return word-ladder length changing one letter at a time.", "hit -> cog via [hot,dot,dog,lot,log,cog]", "5"),
            p("dinic-max-flow", "Dinic Maximum Flow", .hard, "Build a level graph with BFS and send blocking flows through level-respecting edges.", "capacity networks, matching, assignment", "O(V^2 E) general bound · O(V+E) space", "Return maximum flow from 0 to 3.", "0->1:3,0->2:2,1->2:1,1->3:2,2->3:3", "5"),
        ]
    )

    private static let backtracking = AlgorithmCategorySeed(
        id: "backtracking",
        title: "Backtracking & Exhaustive Search",
        subtitle: "Build a candidate, reject early, and undo exactly what you changed",
        systemImage: "arrow.uturn.backward.circle.fill",
        achievementTitle: "Search Sculptor",
        rustSketch: """
        fn choose(start: usize, values: &[i32], path: &mut Vec<i32>, out: &mut Vec<Vec<i32>>) {
            out.push(path.clone());
            for index in start..values.len() {
                path.push(values[index]);
                choose(index + 1, values, path, out);
                path.pop();
            }
        }
        """,
        patterns: [
            p("subsets", "Subset Generation", .easy, "At each item branch on exclude or include, or extend every current subset.", "power sets and optional choices", "O(n*2^n) time · O(n) recursion excluding output", "Return subsets in bitmask order.", "[1,2]", ";1;2;1,2"),
            p("permutations", "Permutation Backtracking", .easy, "Choose one unused item for the next position, recurse, then mark it unused again.", "orderings and assignment sequences", "O(n*n!) time · O(n) state excluding output", "Return the number of permutations of four distinct items.", "[1,2,3,4]", "24"),
            p("combinations", "Combination Backtracking", .easy, "Advance the start index so order does not create duplicate selections.", "choose-k sets and teams", "O(C(n,k)*k) output-sensitive", "Return all size-two combinations in lexicographic order.", "[1,2,3]", "1,2;1,3;2,3"),
            p("combination-sum", "Combination Sum", .medium, "Choose a candidate again or move forward while pruning when the remaining target is negative.", "unbounded sum construction and coin-like enumeration", "Exponential worst case · O(target) depth", "Return unique nondecreasing combinations summing to 7.", "candidates=[2,3,6,7]", "2,2,3;7"),
            p("parentheses-generation", "Valid Parentheses Generation", .medium, "Add an open symbol while available and a close only when it cannot exceed opens used.", "balanced sequence construction", "O(Catalan(n)*n) time · O(n) depth", "Return valid sequences for three pairs in lexicographic order.", "n=3", "((()));(()());(())();()(());()()()"),
            p("word-grid-search", "Grid Word Search", .medium, "Walk matching neighbors while temporarily marking the current cell unavailable in this path.", "path spelling and local grid constraints", "O(rows*cols*4^L) worst · O(L) depth", "Return true when the word can be traced without reusing a cell.", "grid=ABCE,SFCS,ADEE word=ABCCED", "true"),
            p("palindrome-partition", "Palindrome Partitioning", .medium, "Choose each palindromic prefix as the next piece and recurse on the remaining suffix.", "string segmentation under a local validity rule", "O(n*2^n) worst · O(n^2) palindrome work", "Return the number of palindrome partitions.", "aab", "2"),
            p("n-queens", "N-Queens", .hard, "Place one queen per row and reject occupied columns and both diagonals before recursing.", "constraint satisfaction with compact conflict sets", "O(n!) worst · O(n) state", "Return the number of solutions for a 5x5 board.", "n=5", "10"),
            p("sudoku", "Sudoku Constraint Search", .hard, "Choose an empty cell, try allowed symbols, and undo; picking the fewest candidates prunes harder.", "exact constraint completion", "Exponential worst case · O(empty cells) depth", "Return the missing digit in row 0 of the nearly solved grid.", "row0=53.678912", "4"),
            p("meet-in-middle", "Meet in the Middle", .hard, "Enumerate two half-spaces and combine their summaries instead of exploring the full product directly.", "subset sum around 40 items and split exhaustive search", "O(2^(n/2) log 2^(n/2)) time · O(2^(n/2)) space", "Return true if a subset sums to 15.", "[7,3,2,9,5,11]", "true"),
        ]
    )

    private static let greedy = AlgorithmCategorySeed(
        id: "greedy-intervals",
        title: "Greedy & Interval Methods",
        subtitle: "Make a locally safe commitment and prove what future choices remain",
        systemImage: "calendar.badge.clock",
        achievementTitle: "Greedy Strategist",
        rustSketch: """
        fn max_non_overlapping(mut ranges: Vec<(i32, i32)>) -> usize {
            ranges.sort_by_key(|range| range.1);
            let mut end = i32::MIN;
            ranges.into_iter().filter(|&(start, next_end)| {
                if start < end { false } else { end = next_end; true }
            }).count()
        }
        """,
        patterns: [
            p("activity-selection", "Activity Selection", .easy, "Choose the compatible interval that finishes earliest, leaving maximum room for the future.", "maximum count of non-overlapping jobs", "O(n log n) time · O(1) extra after sort", "Return the maximum number of compatible meetings.", "[(1,2),(3,4),(0,6),(5,7),(8,9),(5,9)]", "4"),
            p("merge-intervals", "Merge Intervals", .easy, "Sort by start and extend the current interval while the next one overlaps.", "calendar consolidation and covered ranges", "O(n log n) time · O(n) output", "Return merged closed intervals.", "[(1,3),(2,6),(8,10),(9,12)]", "1-6,8-12"),
            p("insert-interval", "Insert into Sorted Intervals", .medium, "Copy intervals before, merge every overlap, then copy intervals after.", "adding one booking to an already normalised schedule", "O(n) time · O(n) output", "Insert [4,8] and return merged intervals.", "[(1,2),(3,5),(6,7),(8,10),(12,16)]", "1-2,3-10,12-16"),
            p("sweep-line-events", "Sweep-Line Events", .medium, "Sort starts and ends as signed events and integrate active state across coordinates.", "overlap counts, skyline changes, resource demand", "O(n log n) time · O(n) events", "Return maximum simultaneous sessions; process ends before starts at equal time.", "[(1,4),(2,5),(4,6)]", "2"),
            p("jump-game", "Greedy Reach Frontier", .medium, "Maintain the farthest reachable index and fail only when the scan moves beyond it.", "reachability with forward jump capacity", "O(n) time · O(1) space", "Return whether the final index is reachable.", "[2,3,1,1,4]", "true"),
            p("jump-game-two", "Greedy Layered Jumps", .medium, "Treat the current reach as a BFS layer and commit a jump when the scan reaches its boundary.", "minimum jumps in forward-reach arrays", "O(n) time · O(1) space", "Return the minimum jumps to the final index.", "[2,3,1,1,4]", "2"),
            p("gas-station", "Gas Station Reset", .medium, "When running fuel becomes negative, no station in that failed segment can be a valid start.", "circular feasibility with cumulative gain", "O(n) time · O(1) space", "Return a valid starting station, or -1.", "gas=[1,2,3,4,5] cost=[3,4,5,1,2]", "3"),
            p("partition-labels", "Last-Occurrence Partition", .medium, "Extend the current segment to the farthest last occurrence of every symbol encountered.", "split sequences so each key belongs to one segment", "O(n) time · O(alphabet) space", "Return partition lengths.", "ababcbacadefegdehijhklij", "9,7,8"),
            p("deadline-scheduling", "Deadline Profit Scheduling", .hard, "Process jobs by deadline while a heap keeps only the best feasible set.", "max reward under unit-time deadlines", "O(n log n) time · O(n) space", "Return maximum profit using one slot per time and deadlines 1-based.", "jobs=(d2,p100),(d1,p19),(d2,p27),(d1,p25),(d3,p15)", "142"),
            p("minimum-arrows", "Interval Stabbing", .hard, "Sort by interval end and place a point only when the next interval starts after the current point.", "minimum sensors or arrows covering intervals", "O(n log n) time · O(1) extra", "Return the minimum points needed to hit all intervals.", "[(10,16),(2,8),(1,6),(7,12)]", "2"),
        ]
    )

    private static let dynamicOne = AlgorithmCategorySeed(
        id: "dynamic-1d",
        title: "1D Dynamic Programming",
        subtitle: "Define one state, its transition, base cases, and evaluation order",
        systemImage: "function",
        achievementTitle: "DP Builder",
        rustSketch: """
        fn ways(n: usize) -> usize {
            let (mut previous, mut current) = (1, 1);
            for _ in 0..n {
                (previous, current) = (current, previous + current);
            }
            previous
        }
        """,
        patterns: [
            p("memoization", "Top-Down Memoization", .easy, "Cache a recursive state the first time it is solved so overlapping subproblems run once.", "recursive recurrences with repeated states", "O(states * transition) time · O(states) space", "Return Fibonacci number F(12) with F(0)=0 and F(1)=1.", "n=12", "144"),
            p("tabulation", "Bottom-Up Tabulation", .easy, "Evaluate states in an order where every dependency is already available.", "iterative recurrences and stack-free DP", "O(states * transition) time · O(states) space", "Return the number of ways to climb five steps using moves of one or two.", "n=5", "8"),
            p("rolling-dp", "Rolling-State DP", .easy, "Discard table entries once no future transition can read them.", "constant-space Fibonacci-like recurrences", "O(n) time · O(1) space", "Return the minimum cost to move beyond the final stair.", "cost=[10,15,20]", "15"),
            p("house-robber", "Take-or-Skip DP", .medium, "For each item compare skipping it with taking it plus the best compatible earlier state.", "non-adjacent selection and weighted independent paths", "O(n) time · O(1) space", "Return the maximum non-adjacent sum.", "[2,7,9,3,1]", "12"),
            p("kadane", "Kadane Maximum Subarray", .medium, "At each item choose whether to extend the current segment or start a new one.", "best contiguous sum and one-dimensional local reset", "O(n) time · O(1) space", "Return the maximum contiguous sum.", "[-2,1,-3,4,-1,2,1,-5,4]", "6"),
            p("coin-change-min", "Coin Change Minimum", .medium, "Let each amount state choose one coin plus the best smaller reachable amount.", "minimum unbounded composition and denomination planning", "O(amount * coins) time · O(amount) space", "Return the fewest coins needed for amount 11.", "coins=[1,2,5]", "3"),
            p("word-break-dp", "Word Break DP", .medium, "Mark a prefix reachable when an earlier reachable prefix is followed by a dictionary word.", "string segmentation and tokenisation", "O(n^2) substring checks · O(n) state", "Return whether the text can be segmented into dictionary words.", "text=leetcode dict=[leet,code]", "true"),
            p("decode-ways", "Decode Ways DP", .medium, "Count valid one-symbol and two-symbol predecessors while rejecting leading zero states.", "encoded strings with local validity rules", "O(n) time · O(1) space", "Return the number of valid A=1 through Z=26 decodings.", "226", "3"),
            p("lis-patience", "Longest Increasing Subsequence", .hard, "Keep the smallest possible tail for an increasing subsequence of every length.", "sequence order, envelopes, chain length", "O(n log n) time · O(n) space", "Return the LIS length.", "[10,9,2,5,3,7,101,18]", "4"),
            p("zero-one-knapsack", "0/1 Knapsack", .hard, "Update capacities backward so each item contributes at most once.", "bounded selection under one capacity", "O(items*capacity) time · O(capacity) space", "Return maximum value at capacity 7.", "weights=[1,3,4,5] values=[1,4,5,7]", "9"),
        ]
    )

    private static let dynamicTwo = AlgorithmCategorySeed(
        id: "dynamic-2d",
        title: "2D & Advanced Dynamic Programming",
        subtitle: "Model two dimensions, intervals, subsets, and compressed state spaces",
        systemImage: "tablecells.fill",
        achievementTitle: "DP Navigator",
        rustSketch: """
        fn grid_paths(rows: usize, columns: usize) -> usize {
            let mut dp = vec![1; columns];
            for _ in 1..rows {
                for column in 1..columns { dp[column] += dp[column - 1]; }
            }
            dp[columns - 1]
        }
        """,
        patterns: [
            p("grid-path-dp", "Grid Path DP", .easy, "A cell combines ways or cost from the predecessor directions allowed by the movement rule.", "robot paths, matrix costs, obstacle grids", "O(rows*cols) time · O(cols) space possible", "Return unique paths through a 3 by 4 empty grid moving right or down.", "rows=3 cols=4", "10"),
            p("subset-sum", "Subset Sum DP", .medium, "Track reachable totals and update backward so every item is used at most once.", "partition checks and bounded target reachability", "O(n*target) time · O(target) space", "Return whether some subset sums to 11.", "[2,3,7,8,10]", "true"),
            p("longest-common-subsequence", "Longest Common Subsequence", .medium, "Match equal symbols diagonally; otherwise discard one suffix boundary and keep the better result.", "diffs, sequence similarity, deletion distance", "O(n*m) time · O(min(n,m)) space possible", "Return the LCS length.", "abcde and ace", "3"),
            p("edit-distance", "Edit Distance", .medium, "Each state chooses insert, delete, or replace from adjacent smaller prefixes.", "spell correction, fuzzy matching, sequence alignment", "O(n*m) time · O(min(n,m)) space possible", "Return Levenshtein distance.", "horse -> ros", "3"),
            p("longest-pal-subsequence", "Longest Palindromic Subsequence", .medium, "Equal interval ends add two; unequal ends discard one boundary and keep the better interval.", "palindrome retention and minimum deletions", "O(n^2) time · O(n^2) space", "Return the longest palindromic subsequence length.", "bbbab", "4"),
            p("matrix-chain", "Matrix Chain DP", .hard, "Try every final split of an interval and combine left cost, right cost, and multiplication cost.", "optimal parenthesisation and associative operation planning", "O(n^3) time · O(n^2) space", "Return minimum scalar multiplications.", "dimensions=[10,30,5,60]", "4500"),
            p("interval-dp", "Interval DP", .hard, "Solve increasing interval lengths and choose the last or first action inside each interval.", "bursting, merging, polygon triangulation", "O(n^3) typical · O(n^2) space", "Return maximum coins from bursting balloons.", "[3,1,5,8]", "167"),
            p("digit-dp", "Digit DP", .hard, "Process digits with position, tight-bound, leading-zero, and property state.", "count numbers under a bound satisfying digit constraints", "O(digits * states * base) time", "Count integers from 0 through 25 whose digit sum is 5.", "bound=25 sum=5", "3"),
            p("bitmask-dp", "Bitmask DP", .hard, "Encode the chosen subset in bits and transition by adding one unused item.", "small assignment, travelling salesperson, pairing", "O(2^n * n^2) typical · O(2^n*n) space", "Return minimum tour cost starting and ending at 0.", "matrix=[[0,10,15,20],[10,0,35,25],[15,35,0,30],[20,25,30,0]]", "80"),
            p("tree-dp", "Tree DP", .hard, "Return a compact choice summary from each subtree and combine children at their parent.", "independent sets, subtree counts, reroot-ready summaries", "O(n) time · O(h) stack", "Return maximum sum of non-adjacent tree nodes.", "tree=[3,2,3,null,3,null,1]", "7"),
        ]
    )

    private static let strings = AlgorithmCategorySeed(
        id: "strings-tries",
        title: "Tries & String Matching",
        subtitle: "Respect bytes versus characters, then exploit prefixes and borders",
        systemImage: "textformat.abc",
        achievementTitle: "String Detective",
        rustSketch: """
        fn prefix_function(bytes: &[u8]) -> Vec<usize> {
            let mut pi = vec![0; bytes.len()];
            for i in 1..bytes.len() {
                let mut j = pi[i - 1];
                while j > 0 && bytes[i] != bytes[j] { j = pi[j - 1]; }
                if bytes[i] == bytes[j] { j += 1; }
                pi[i] = j;
            }
            pi
        }
        """,
        patterns: [
            p("string-frequency", "Character Frequency", .easy, "Count the text unit the problem defines: bytes, Unicode scalar values, or grapheme clusters.", "anagrams, inventory, first unique symbol", "O(n) time · O(alphabet) space", "Return the first non-repeated ASCII character.", "swiss", "w"),
            p("string-two-pointers", "String Two Pointers", .easy, "Move across symbol boundaries deliberately rather than indexing arbitrary UTF-8 bytes.", "palindromes, trimming, mirrored comparison", "O(n) time · O(1) or decoded storage", "Return true after ignoring non-alphanumeric ASCII and case.", "A man, a plan, a canal: Panama", "true"),
            p("run-length-encoding", "Run-Length Encoding", .easy, "Group maximal adjacent equal symbols and emit the symbol with its run length.", "compression, repeated-span summaries, token runs", "O(n) time · O(n) output", "Encode consecutive characters as character followed by count.", "aaabbcaaaa", "a3b2c1a4"),
            p("kmp", "Knuth–Morris–Pratt", .medium, "Use the pattern's border table to reuse matched-prefix knowledge after a mismatch.", "linear exact substring search and border queries", "O(n+m) time · O(m) space", "Return the first pattern index in the text.", "text=ababcabcabababd pattern=ababd", "10"),
            p("z-algorithm", "Z Algorithm", .medium, "Reuse the rightmost prefix-matching box to compute how much of the prefix matches at every position.", "pattern search, repetitions, prefix matches", "O(n) time · O(n) space", "Return the Z array.", "aabcaabxaaaz", "0,1,0,0,3,1,0,0,2,2,1,0"),
            p("rabin-karp", "Rabin–Karp", .medium, "Compare rolling hashes first and verify actual bytes only on hash matches.", "multiple pattern candidates and substring fingerprints", "O(n+m) expected · O(n*m) collision worst", "Return every start index of the pattern.", "text=abracadabra pattern=abra", "0,7"),
            p("trie", "Prefix Trie", .medium, "Store one edge per next symbol so shared prefixes occupy shared nodes.", "prefix lookup, autocomplete, dictionary traversal", "O(total symbols) build · O(length) query", "Insert the listed words and return how many begin with prefix.", "words=[crab,crate,rust] prefix=cr", "2"),
            p("aho-corasick", "Aho–Corasick", .hard, "Add failure links to a trie so one scan reports all pattern suffixes ending at each position.", "many-pattern search, filters, signature scanning", "O(text + matches + total patterns) time", "Return matched pattern count including overlaps.", "text=ahishers patterns=[he,she,his,hers]", "4"),
            p("suffix-array", "Suffix Array", .hard, "Sort suffix ranks by doubling compared prefix length until every suffix has a unique rank.", "substring order, repeated substrings, offline text indexes", "O(n log^2 n) simple · O(n log n) tuned", "Return suffix starting indexes in lexicographic order.", "banana", "5,3,1,0,4,2"),
            p("manacher", "Manacher Palindrome Radii", .hard, "Mirror known radii inside the rightmost palindrome and expand only beyond its boundary.", "all palindromic centers and longest palindrome in linear time", "O(n) time · O(n) space", "Return the longest palindromic substring; choose the earliest on ties.", "babad", "bab"),
        ]
    )

    private static let mathBits = AlgorithmCategorySeed(
        id: "math-bits",
        title: "Math, Bits & Combinatorics",
        subtitle: "Replace simulation with algebraic structure and binary identities",
        systemImage: "sum",
        achievementTitle: "Bit Alchemist",
        rustSketch: """
        fn gcd(mut a: u64, mut b: u64) -> u64 {
            while b != 0 {
                (a, b) = (b, a % b);
            }
            a
        }
        """,
        patterns: [
            p("euclid-gcd", "Euclidean GCD", .easy, "Replace the larger pair with divisor and remainder without changing their greatest common divisor.", "fraction reduction, periods, lattice steps", "O(log min(a,b)) time · O(1) space", "Return gcd of 252 and 105.", "a=252 b=105", "21"),
            p("bitmask-enumeration", "Bitmask Enumeration", .easy, "Use each bit as an include/exclude choice for one item.", "small subsets, permissions, feature combinations", "O(2^n*n) time · O(1) state excluding output", "Return masks whose selected values sum to 5.", "values=[1,2,4]", "5"),
            p("xor-cancellation", "XOR Cancellation", .easy, "Equal values cancel and zero is neutral, leaving an odd-occurring value.", "single-number recovery and parity fingerprints", "O(n) time · O(1) space", "Every value occurs twice except one; return it.", "[4,1,2,1,2]", "4"),
            p("sieve", "Sieve of Eratosthenes", .medium, "Mark multiples beginning at p squared for each still-prime p.", "prime tables and factor-precomputation", "O(n log log n) time · O(n) space", "Return primes not exceeding 30.", "n=30", "2,3,5,7,11,13,17,19,23,29"),
            p("fast-power", "Binary Exponentiation", .medium, "Square the base and consume exponent bits so only logarithmically many multiplications occur.", "large powers, modular arithmetic, repeated transforms", "O(log exponent) time · O(1) space", "Return 3^13 modulo 1000.", "base=3 exp=13 mod=1000", "323"),
            p("modular-inverse", "Modular Inverse", .medium, "Use extended Euclid when gcd is one, or Fermat under a known prime modulus.", "division in modular arithmetic and combinatorics", "O(log modulus) time · O(1) space", "Return inverse of 3 modulo 11.", "a=3 mod=11", "4"),
            p("binomial-coefficients", "Binomial Coefficients", .medium, "Build Pascal recurrence or multiply a shortened numerator while controlling division.", "choose-k counts, lattice paths, probability", "O(n*k) DP or O(k) multiplicative time", "Return 20 choose 6.", "n=20 k=6", "38760"),
            p("gray-code", "Gray Code", .medium, "Map i to i xor (i shifted right) so neighboring codes differ by one bit.", "single-bit state transitions and test sequences", "O(2^n) time · O(2^n) output", "Return three-bit Gray code order.", "n=3", "0,1,3,2,6,7,5,4"),
            p("matrix-exponentiation", "Matrix Exponentiation", .hard, "Encode a linear recurrence as a matrix and exponentiate the transition by squaring.", "huge recurrence indexes and state transitions", "O(k^3 log n) time · O(k^2) space", "Return Fibonacci F(50).", "n=50", "12586269025"),
            p("miller-rabin", "Miller–Rabin Primality", .hard, "Write n-1 as d times a power of two and test whether modular powers witness compositeness.", "fast primality for large machine integers", "O(witnesses * log^3 n) basic modular cost", "Using deterministic 64-bit witnesses, return whether 2,147,483,647 is prime.", "n=2147483647", "true"),
        ]
    )

    private static let advanced = AlgorithmCategorySeed(
        id: "advanced-structures",
        title: "Advanced Data Structures",
        subtitle: "Compose range, ordering, and decomposition techniques for hard constraints",
        systemImage: "cpu.fill",
        achievementTitle: "Structure Master",
        rustSketch: """
        // Advanced structures start from the same discipline:
        // define the query monoid, update semantics, and the invariant that
        // makes each decomposition smaller than the original problem.
        """,
        patterns: [
            p("sparse-table", "Sparse Table", .medium, "Precompute answers for power-of-two blocks and combine two blocks for idempotent queries.", "immutable range minimum, maximum, gcd", "O(n log n) build · O(1) query · O(n log n) space", "Return minimums for ranges [0,3], [2,5], and [4,6].", "[7,2,3,0,5,10,3,12,18]", "0,0,3"),
            p("disjoint-set-union", "Disjoint Set Union", .medium, "Compress find paths and attach smaller trees beneath larger roots.", "dynamic connectivity, Kruskal, grouping", "Almost O(1) amortised · O(n) space", "Apply the listed unions and return the final component count.", "n=5 unions=(0,1),(1,2),(3,4)", "2"),
            p("lazy-segment-tree", "Lazy Segment Tree", .hard, "Store pending range operations at covering nodes and push them only before descending.", "range updates plus range aggregate queries", "O(log n) update/query · O(n) space", "Add 3 to range 1..4, then return sum of range 2..5.", "values=[1,2,3,4,5,6]", "27"),
            p("treap", "Randomized Treap", .hard, "Keep BST order by key and heap order by random priority; split and merge preserve both.", "ordered sets with expected logarithmic operations", "O(log n) expected operation · O(n) space", "Apply the insert/delete operations and return keys requested by inorder.", "insert5 insert2 insert8 insert1 delete2 inorder", "1,5,8"),
            p("skip-list", "Skip List", .hard, "Promote nodes randomly into sparse express lanes and descend when the next jump overshoots.", "probabilistic ordered maps and concurrent-friendly indexes", "O(log n) expected search/update · O(n) space", "Return whether 19 is found after inserting the values.", "[3,6,7,9,12,19,17,26,21,25]", "true"),
            p("dsu-rollback", "Rollback DSU", .hard, "Record every parent or size mutation so recursion over time can undo unions without path compression.", "offline dynamic connectivity and divide-over-time", "O(log n) union/find typical · O(changes) history", "Apply unions and checkpoint operations, then answer the connectivity query after rollback.", "n=4 unions=(0,1),(1,2) checkpoint union=(2,3) rollback query=(0,3)", "false"),
            p("mo-algorithm", "Mo's Algorithm", .hard, "Order offline range queries so adjacent queries move their boundaries only a small distance.", "many immutable range queries with cheap add/remove", "O((n+q)*sqrt(n)) operations · O(state) space", "Return distinct counts for ranges [0,3], [2,5], [0,5].", "[1,2,1,3,2,4]", "3,4,4"),
            p("heavy-light", "Heavy-Light Decomposition", .hard, "Choose one heavy child per node so any root path crosses only logarithmically many light edges.", "tree path queries with segment trees", "O(log^2 n) path query · O(n) space", "Return the sum on path 2 to 4.", "edges=(0,1),(1,2),(1,3),(3,4) values=[1,2,3,4,5]", "14"),
            p("centroid-decomposition", "Centroid Decomposition", .hard, "Remove a balancing centroid and recurse on components no larger than half the original.", "dynamic distance queries and divide-and-conquer on trees", "O(n log n) build · query/update depends on stored summary", "Return the first centroid of the tree, breaking ties by smaller index.", "n=6 edges=(0,1),(1,2),(1,3),(3,4),(3,5)", "1"),
            p("suffix-automaton", "Suffix Automaton", .hard, "Extend one character while cloning states when needed to preserve end-position equivalence classes.", "all substrings, repeated substring counts, online text indexing", "O(n) build · O(n) states", "Return the number of distinct non-empty substrings.", "ababa", "9"),
        ]
    )
}
