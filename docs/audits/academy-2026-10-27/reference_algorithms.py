"""Small independent answer oracles for the exact Atlas exercise contracts.

These intentionally use simple enumeration where sample sizes permit it.
They check answers, not the complexity or Rust implementation of a solution.
Unimplemented/ambiguous contracts raise NotImplementedError, never pass silently.
"""

import ast
import bisect
from collections import Counter
import itertools
import math
import re
import statistics


def array(text):
    return ast.literal_eval(re.search(r"\[[^\[\]]*\]", text)[0])


def comma(items):
    return ",".join(str(x).lower() if isinstance(x, bool) else str(x) for x in items)


def number(text, key):
    return int(re.search(rf"\b{key}=(-?\d+)", text)[1])


def pal(text):
    return text == text[::-1]


def solve(pattern, text):
    text = text.strip()
    # Independent direct checks of numeric/string answers, not library names.
    if pattern in {"linear-scan", "min-max-tracking", "frequency-counting",
                   "running-accumulator", "adjacent-pair-scan", "stable-compaction",
                   "predicate-partition", "boyer-moore-majority", "hash-membership",
                   "index-map", "coordinate-compression", "longest-consecutive-set",
                   "prefix-sum", "suffix-aggregate", "equilibrium-index",
                   "prefix-suffix-product", "prefix-xor", "opposite-ends",
                   "same-direction", "slow-fast", "sorted-two-sum", "three-sum",
                   "dutch-flag", "container-area", "trapping-water", "fixed-window",
                   "variable-window", "at-most-k", "exactly-k-difference",
                   "monotonic-deque-window", "rolling-window-statistic",
                   "dual-heap-window-median", "next-greater-stack",
                   "monotonic-increasing-stack", "monotonic-decreasing-stack",
                   "circular-monotonic-stack", "largest-histogram", "insertion-sort",
                   "selection-sort", "quicksort", "heap-sort", "counting-sort",
                   "radix-sort", "bucket-sort", "quickselect", "median-of-medians",
                   "binary-exact", "lower-bound", "upper-bound", "first-last-position",
                   "rotated-search", "exponential-search", "binary-heap", "top-k-minheap",
                   "kth-stream", "two-heap-median", "subsets", "permutations",
                   "combinations", "subset-sum", "meet-in-middle", "house-robber",
                   "kadane", "lis-patience", "interval-dp", "xor-cancellation"}:
        a = array(text)
    match pattern:
        case "linear-scan": return str(next((i for i, x in enumerate(a) if x < 0), -1))
        case "min-max-tracking": return str(max(a) - min(a))
        case "frequency-counting":
            counts = Counter(a)
            return str(min(counts, key=lambda x: (-counts[x], x)))
        case "running-accumulator": return str(sum(x if i % 2 == 0 else -x for i, x in enumerate(a)))
        case "adjacent-pair-scan": return str(sum(y < x for x, y in zip(a, a[1:])))
        case "stable-compaction": return comma(x for x in a if x != 0)
        case "predicate-partition": return str(sum(x % 2 == 0 for x in a))
        case "boyer-moore-majority": return str(Counter(a).most_common(1)[0][0])
        case "hash-membership": return str(len(set(a)) != len(a)).lower()
        case "index-map": return str(min(j-i for i in range(len(a)) for j in range(i+1, len(a)) if a[i] == a[j]))
        case "coordinate-compression": return comma(sorted(set(a)).index(x) for x in a)
        case "longest-consecutive-set":
            values = set(a)
            return str(max(sum(1 for _ in itertools.takewhile(lambda k: k in values, itertools.count(x))) for x in values))
        case "hash-frequency":
            left, right = text.split(";")
            return str(Counter(left.strip()) == Counter(right.strip())).lower()
        case "group-by-key":
            words = text.strip("[]").split(",")
            return str(max(Counter("".join(sorted(w.strip())) for w in words).values()))
        case "bidirectional-map":
            letters, words = text.split(";"); words = words.split()
            return str(len(letters) == len(words) and len(set(letters)) == len(set(words)) == len(set(zip(letters, words)))).lower()
        case "prefix-sum": return str(sum(a[1:4]))
        case "suffix-aggregate": return comma(max(a[i:]) for i in range(len(a)))
        case "equilibrium-index": return str(next((i for i in range(len(a)) if sum(a[:i]) == sum(a[i+1:])), -1))
        case "prefix-suffix-product": return comma(math.prod(a[:i]+a[i+1:]) for i in range(len(a)))
        case "prefix-xor":
            value = 0
            for x in a[1:5]: value ^= x
            return str(value)
        case "difference-array" | "imos-sweep":
            values = [0] * number(text, "n")
            for left, right, delta in re.findall(r"\((\d+),(\d+),(-?\d+)\)", text):
                for i in range(int(left), int(right)+1): values[i] += int(delta)
            return str(max(values)) if pattern == "imos-sweep" else comma(values)
        case "prefix-sum-2d":
            matrix = ast.literal_eval(text)
            return str(sum(matrix[r][c] for r in [1, 2] for c in [0, 1]))
        case "fenwick-tree":
            pairs = [(int(i), int(v)) for i, v in re.findall(r"\((\d+),(-?\d+)\)", text)]
            return str(sum(v for i, v in pairs if i <= number(text, "query")))
        case "segment-tree":
            values = array(text)
            index, value = map(int, re.search(r"update=\((\d+),(-?\d+)\)", text).groups())
            left, right = map(int, re.search(r"query=(\d+)\.\.(\d+)", text).groups())
            values[index] = value
            return str(min(values[left:right+1]))
        case "lazy-segment-tree":
            values = array(text)
            for i in range(1, 5): values[i] += 3
            return str(sum(values[2:6]))
        case "opposite-ends": return str(any(x+y == 10 for x, y in itertools.combinations(a, 2))).lower()
        case "same-direction": return comma(x for x in a if x >= 5)
        case "slow-fast": return str(a[len(a)//2])
        case "sorted-two-sum": return comma(next((i+1, j+1) for i in range(len(a)) for j in range(i+1, len(a)) if a[i]+a[j] == 17))
        case "palindrome-pointers" | "string-two-pointers": return str(pal("".join(c.lower() for c in text if c.isascii() and c.isalnum()))).lower()
        case "three-sum": return str(len({tuple(sorted(t)) for t in itertools.combinations(a, 3) if sum(t) == 0}))
        case "container-area": return str(max(min(a[i], a[j])*(j-i) for i in range(len(a)) for j in range(i+1, len(a))))
        case "trapping-water": return str(sum(min(max(a[:i+1]), max(a[i:]))-x for i, x in enumerate(a)))
        case "fixed-window": return str(max(sum(a[i:i+3]) for i in range(len(a)-2)))
        case "variable-window": return str(min(j-i for i in range(len(a)) for j in range(i+1, len(a)+1) if sum(a[i:j]) >= 7))
        case "unique-window": return str(max(j-i for i in range(len(text)) for j in range(i+1, len(text)+1) if len(set(text[i:j])) == j-i))
        case "at-most-k": return str(max(j-i for i in range(len(a)) for j in range(i+1, len(a)+1) if len(set(a[i:j])) <= 2))
        case "exactly-k-difference": return str(sum(len(set(a[i:j])) == 2 for i in range(len(a)) for j in range(i+1, len(a)+1)))
        case "frequency-balanced-window": return str(max(j-i for i in range(len(text)) for j in range(i+1, len(text)+1) if j-i-max(Counter(text[i:j]).values()) <= 1))
        case "minimum-cover-window": return min((text[i:j] for i in range(len(text)) for j in range(i+1, len(text)+1) if set('ABC') <= set(text[i:j])), key=len)
        case "monotonic-deque-window": return comma(max(a[i:i+3]) for i in range(len(a)-2))
        case "rolling-window-statistic": return comma(sum(a[i:i+3])//3 for i in range(len(a)-2))
        case "dual-heap-window-median": return comma(sorted(a[i:i+3])[1] for i in range(len(a)-2))
        case "delimiter-stack":
            stack = []
            for c in text:
                if c in "([{": stack.append(c)
                elif c in ")]}":
                    if not stack or stack.pop() != dict(zip(")]}", "([{"))[c]: return "false"
            return str(not stack).lower()
        case "postfix-evaluation":
            stack = []
            for token in text.split():
                if token in ['+', '-', '*', '/']:
                    right, left = stack.pop(), stack.pop()
                    stack.append({'+': lambda: left+right, '-': lambda: left-right, '*': lambda: left*right, '/': lambda: int(left/right)}[token]())
                else: stack.append(int(token))
            return str(stack[-1])
        case "next-greater-stack": return comma(next((v for v in a[i+1:] if v > x), -1) for i, x in enumerate(a))
        case "monotonic-increasing-stack": return comma(next((v for v in reversed(a[:i]) if v < x), -1) for i, x in enumerate(a))
        case "monotonic-decreasing-stack":
            # Literally the published task: count EARLIER days; excludes today.
            return comma(sum(1 for _ in itertools.takewhile(lambda v: v <= x, reversed(a[:i]))) for i, x in enumerate(a))
        case "circular-monotonic-stack": return comma(next((a[(i+j)%len(a)] for j in range(1, len(a)) if a[(i+j)%len(a)] > x), -1) for i, x in enumerate(a))
        case "largest-histogram": return str(max(min(a[i:j])*(j-i) for i in range(len(a)) for j in range(i+1, len(a)+1)))
        case "insertion-sort" | "quicksort" | "heap-sort" | "counting-sort" | "radix-sort" | "dutch-flag" | "binary-heap" | "bucket-sort": return comma(sorted(a))
        case "selection-sort":
            swaps = 0
            for i in range(len(a)):
                j = min(range(i, len(a)), key=a.__getitem__)
                if i != j: a[i], a[j] = a[j], a[i]; swaps += 1
            return str(swaps)
        case "quickselect": return str(sorted(a)[2])
        case "median-of-medians": return str(sorted(a)[4])
        case "binary-exact" | "rotated-search" | "exponential-search":
            target = {"binary-exact": 9, "rotated-search": 0, "exponential-search": 21}[pattern]
            return str(a.index(target) if target in a else -1)
        case "lower-bound": return str(bisect.bisect_left(a, 4))
        case "upper-bound": return str(bisect.bisect_right(a, 4))
        case "first-last-position": return comma((a.index(8), len(a)-1-a[::-1].index(8))) if 8 in a else '-1,-1'
        case "top-k-minheap": return comma(sorted(a, reverse=True)[:3])
        case "kth-stream": return comma(sorted(a[:i], reverse=True)[2] for i in range(3, len(a)+1))
        case "two-heap-median": return comma(f'{statistics.median(a[:i]):g}' for i in range(1, len(a)+1))
        case "k-way-merge": return comma(sorted(itertools.chain.from_iterable(ast.literal_eval(part) for part in text.split(';'))))
        case "huffman-greedy-heap":
            values = array(text); total = 0
            while len(values)>1:
                values.sort(); value = values.pop(0)+values.pop(0); total += value; values.append(value)
            return str(total)
        case "subsets": return ';'.join(comma(a[i] for i in range(len(a)) if mask>>i&1) for mask in range(1<<len(a)))
        case "permutations": return str(math.factorial(len(a)))
        case "combinations": return ';'.join(comma(c) for c in itertools.combinations(a, 2))
        case "subset-sum" | "meet-in-middle":
            target = 11 if pattern == 'subset-sum' else 15
            return str(any(sum(c) == target for n in range(len(a)+1) for c in itertools.combinations(a, n))).lower()
        case "memoization" | "matrix-exponentiation":
            a, b = 0, 1
            for _ in range(number(text, 'n')): a, b = b, a+b
            return str(a)
        case "tabulation":
            a, b = 1, 1
            for _ in range(number(text, 'n')): a, b = b, a+b
            return str(a)
        case "rolling-dp":
            a, b = 0, 0
            for cost in array(text): a, b = b, cost+min(a, b)
            return str(min(a, b))
        case "house-robber":
            a0, b = 0, 0
            for x in a: a0, b = b, max(b, a0+x)
            return str(b)
        case "kadane": return str(max(sum(a[i:j]) for i in range(len(a)) for j in range(i+1, len(a)+1)))
        case "lis-patience": return str(max((len(c) for n in range(len(a)+1) for c in itertools.combinations(a, n) if all(x<y for x,y in zip(c, c[1:]))), default=0))
        case "grid-path-dp":
            r, c = number(text, 'rows'), number(text, 'cols')
            return str(math.comb(r+c-2, r-1))
        case "longest-common-subsequence":
            a, b = text.split(' and ')
            def subsequences(s): return {''.join(c) for n in range(len(s)+1) for c in itertools.combinations(s,n)}
            return str(max(map(len, subsequences(a) & subsequences(b))))
        case "longest-pal-subsequence": return str(max(len(c) for n in range(len(text)+1) for c in itertools.combinations(text,n) if c == c[::-1]))
        case "edit-distance":
            a, b = text.split(' -> '); dp = list(range(len(b)+1))
            for i, x in enumerate(a, 1):
                row = [i]
                for j, y in enumerate(b, 1): row.append(min(row[-1]+1, dp[j]+1, dp[j-1]+(x != y)))
                dp = row
            return str(dp[-1])
        case "euclid-gcd": return str(math.gcd(number(text, 'a'), number(text, 'b')))
        case "xor-cancellation":
            value = 0
            for x in a: value ^= x
            return str(value)
        case "sieve": return comma(n for n in range(2, number(text, 'n')+1) if all(n%d for d in range(2, math.isqrt(n)+1)))
        case "fast-power": return str(pow(number(text,'base'), number(text,'exp'), number(text,'mod')))
        case "modular-inverse": return str(pow(number(text,'a'), -1, number(text,'mod')))
        case "binomial-coefficients": return str(math.comb(number(text,'n'), number(text,'k')))
        case "gray-code": return comma(i^(i>>1) for i in range(1<<number(text,'n')))
        case "bitmask-enumeration":
            a = array(text)
            return comma(mask for mask in range(1<<len(a)) if sum(x for i,x in enumerate(a) if mask>>i&1) == 5)
        case "rolling-fingerprint":
            h = 0
            for d in array(text): h = (10*h+d)%101
            return str(h)
        case "digit-dp": return str(sum(sum(map(int,str(i))) == number(text,'sum') for i in range(number(text,'bound')+1)))
        case "string-frequency":
            counts = Counter(text)
            return next(c for c in text if counts[c] == 1)
        case "run-length-encoding": return ''.join(c+str(len(list(g))) for c,g in itertools.groupby(text))
        case "kmp" | "rabin-karp":
            haystack, needle = re.fullmatch(r'text=(.*) pattern=(.*)',text).groups()
            matches = [i for i in range(len(haystack)-len(needle)+1) if haystack.startswith(needle,i)]
            return str(matches[0] if matches else -1) if pattern == 'kmp' else comma(matches)
        case "z-algorithm":
            values = [0]
            for i in range(1,len(text)):
                j = 0
                while i+j<len(text) and text[j] == text[i+j]: j+=1
                values.append(j)
            return comma(values)
        case "suffix-array": return comma(sorted(range(len(text)), key=lambda i:text[i:]))
        case "suffix-automaton": return str(len({text[i:j] for i in range(len(text)) for j in range(i+1,len(text)+1)}))
        case "manacher": return max((text[i:j] for i in range(len(text)) for j in range(i+1,len(text)+1) if pal(text[i:j])), key=len)
        case "trie":
            words, prefix = re.fullmatch(r'words=\[(.*)\] prefix=(.*)',text).groups()
            return str(sum(word.startswith(prefix) for word in words.split(',')))
        case "partition-labels":
            last = {c:i for i,c in enumerate(text)}; end=0; start=0; sizes=[]
            for i,c in enumerate(text):
                end=max(end,last[c])
                if i==end: sizes.append(i-start+1); start=i+1
            return comma(sizes)
        case _: raise NotImplementedError(pattern)
