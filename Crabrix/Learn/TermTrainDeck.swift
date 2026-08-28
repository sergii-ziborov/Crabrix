import Foundation

/// One term and the meaning it has to be matched with.
struct TermTrainPair: Identifiable, Equatable, Sendable {
    let id: String
    let term: String
    let description: String
    /// The lesson this term belongs to, so a run feeds topic mastery.
    let topic: String

    init(id: String, term: String, description: String, topic: String? = nil) {
        self.id = id
        self.term = term
        self.description = description
        self.topic = topic ?? id
    }
}

/// How a Term Train run is played.
enum TermTrainMode: String, CaseIterable, Identifiable, Sendable {
    /// No clock. Keep going until the board is clear.
    case practice
    /// Beat the clock; the board refills so the run is about recall speed.
    case timed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .practice: "Practice"
        case .timed: "Timed"
        }
    }

    var detail: String {
        switch self {
        case .practice: "No clock — clear the board at your own pace"
        case .timed: "60 seconds — the board refills, match as many as you can"
        }
    }

    var systemImage: String {
        switch self {
        case .practice: "infinity"
        case .timed: "timer"
        }
    }

    var duration: Int? {
        switch self {
        case .practice: nil
        case .timed: 60
        }
    }

    /// A wrong match costs time in the timed mode only.
    var mistakePenaltySeconds: Int {
        switch self {
        case .practice: 0
        case .timed: 3
        }
    }
}

enum TermTrainDeck {
    /// How many pairs are on the board at once.
    static let boardSize = 5

    static let all: [TermTrainPair] = [
        TermTrainPair(id: "ownership", term: "Ownership", description: "One value has one owner; dropping the owner releases it.", topic: "ownership"),
        TermTrainPair(id: "borrow", term: "Borrow", description: "Use a value through a reference without taking ownership.", topic: "borrowing"),
        TermTrainPair(id: "mutable", term: "mut", description: "Explicitly allows a binding or reference to change a value.", topic: "variables"),
        TermTrainPair(id: "result", term: "Result<T, E>", description: "Represents either a successful value or a recoverable error.", topic: "option-result"),
        TermTrainPair(id: "trait", term: "Trait", description: "Defines shared behavior that multiple types can implement.", topic: "traits"),
        TermTrainPair(id: "option", term: "Option<T>", description: "Models a value that may be absent, without using null.", topic: "option-result"),
        TermTrainPair(id: "lifetime", term: "Lifetime", description: "Names how long a reference stays valid relative to others.", topic: "lifetimes"),
        TermTrainPair(id: "move", term: "Move", description: "Transfers ownership so the original binding can no longer be used.", topic: "ownership"),
        TermTrainPair(id: "clone", term: "Clone", description: "Makes an explicit deep copy when sharing a reference is not enough.", topic: "copy-clone"),
        TermTrainPair(id: "slice", term: "Slice", description: "A borrowed view over a contiguous run of elements.", topic: "slices"),
        TermTrainPair(id: "enum", term: "enum", description: "A type that is exactly one of several named variants.", topic: "enums"),
        TermTrainPair(id: "match", term: "match", description: "Branches on a value and forces every case to be handled.", topic: "pattern-matching"),
        TermTrainPair(id: "iterator", term: "Iterator", description: "Produces items one at a time and stays lazy until consumed.", topic: "iterators"),
        TermTrainPair(id: "cargo", term: "Cargo", description: "Resolves dependencies, builds crates, and runs the test suite.", topic: "dependencies"),
        TermTrainPair(id: "crate", term: "Crate", description: "The unit a Rust compilation and a published package are made of.", topic: "modules"),
        TermTrainPair(id: "box", term: "Box<T>", description: "Stores a value on the heap behind a single owning pointer.", topic: "box"),
        TermTrainPair(id: "arc", term: "Arc<T>", description: "Shares ownership across threads with atomic reference counting.", topic: "shared-state"),
        TermTrainPair(id: "question", term: "?", description: "Returns early from a function when a Result or Option is empty.", topic: "errors"),
        TermTrainPair(id: "shadowing", term: "Shadowing", description: "Re-declares a name with a new binding, possibly of another type.", topic: "variables"),
        TermTrainPair(id: "tuple", term: "Tuple", description: "Groups a fixed number of values that may have different types.", topic: "types"),
        TermTrainPair(id: "overflow", term: "checked_add", description: "Returns None instead of wrapping or panicking on overflow.", topic: "operators"),
        TermTrainPair(id: "expression", term: "Tail expression", description: "The final value of a block, returned when the semicolon is omitted.", topic: "functions"),
        TermTrainPair(id: "doc-test", term: "Doc test", description: "An example inside /// that cargo test compiles and runs.", topic: "comments-docs"),
        TermTrainPair(id: "copy", term: "Copy", description: "Duplicates on assignment instead of moving, for cheap values.", topic: "copy-clone"),
        TermTrainPair(id: "drop", term: "Drop", description: "Runs cleanup deterministically when a value leaves scope.", topic: "drop-order"),
        TermTrainPair(id: "str", term: "&str", description: "A borrowed view into UTF-8 text that owns nothing.", topic: "strings"),
        TermTrainPair(id: "guard", term: "Match guard", description: "An extra condition an arm must satisfy to be chosen.", topic: "pattern-matching"),
        TermTrainPair(id: "derive", term: "#[derive]", description: "Generates a mechanical trait implementation for each field.", topic: "derive"),
        TermTrainPair(id: "closure", term: "FnMut", description: "A closure that mutably borrows what it captured.", topic: "closures"),
        TermTrainPair(id: "assoc", term: "Associated type", description: "Fixes one output type per trait implementation.", topic: "associated-types"),
        TermTrainPair(id: "from", term: "From", description: "Defines a conversion, and grants Into for free.", topic: "operator-traits"),
        TermTrainPair(id: "generic", term: "Trait bound", description: "States the capability a generic body needs from its type.", topic: "generics"),
        TermTrainPair(id: "module", term: "pub", description: "Decides what escapes a module's boundary.", topic: "modules"),
        TermTrainPair(id: "test-attr", term: "#[test]", description: "Marks a function compiled only for the test harness.", topic: "testing"),
        TermTrainPair(id: "semver", term: "SemVer", description: "\"1.2\" means at least 1.2.0 and below 2.0.0.", topic: "dependencies"),
        TermTrainPair(id: "workspace", term: "Workspace", description: "Several crates resolved against one shared lockfile.", topic: "workspaces"),
        TermTrainPair(id: "refcell", term: "RefCell<T>", description: "Moves the borrow rules to runtime; a violation panics.", topic: "rc-refcell"),
        TermTrainPair(id: "rc", term: "Rc<T>", description: "Shares ownership on a single thread by counting handles.", topic: "rc-refcell"),
        TermTrainPair(id: "weak", term: "Weak<T>", description: "Observes without owning, so a cycle cannot leak.", topic: "cycles"),
        TermTrainPair(id: "deref", term: "Deref", description: "Lets a wrapper be used where the inner reference is expected.", topic: "deref-drop"),
        TermTrainPair(id: "channel", term: "mpsc", description: "Moves values from many senders to one receiver.", topic: "channels"),
        TermTrainPair(id: "mutex", term: "Mutex<T>", description: "Holds the data itself, so unlocked access cannot be written.", topic: "shared-state"),
        TermTrainPair(id: "send", term: "Send", description: "Marks a type that may be moved to another thread.", topic: "send-sync"),
        TermTrainPair(id: "sync", term: "Sync", description: "Marks a type whose reference may be shared across threads.", topic: "send-sync"),
        TermTrainPair(id: "future", term: "Future", description: "Describes work that makes progress only when polled.", topic: "futures"),
        TermTrainPair(id: "runtime", term: "Executor", description: "The library that actually polls futures to completion.", topic: "async-runtime"),
        TermTrainPair(id: "join", term: "join!", description: "Runs several futures at once and waits for all of them.", topic: "async-patterns"),
        TermTrainPair(id: "macro-rules", term: "macro_rules!", description: "Expands matched token patterns into code before type checking.", topic: "declarative-macros"),
        TermTrainPair(id: "proc-macro", term: "Proc macro", description: "A program the compiler runs, built for the host machine.", topic: "proc-macros"),
        TermTrainPair(id: "cfg", term: "#[cfg]", description: "Removes code from the build before it is type checked.", topic: "cfg-features"),
        TermTrainPair(id: "unsafe-kw", term: "unsafe", description: "Unlocks five operations; the borrow checker still applies.", topic: "unsafe"),
        TermTrainPair(id: "repr-c", term: "#[repr(C)]", description: "Fixes field order so a struct matches its C counterpart.", topic: "ffi"),
        TermTrainPair(id: "newtype", term: "Newtype", description: "Wraps a primitive so the type system can tell values apart.", topic: "idioms"),
        TermTrainPair(id: "capacity", term: "with_capacity", description: "Allocates once up front instead of resizing repeatedly.", topic: "performance"),
        TermTrainPair(id: "vec", term: "Vec<T>", description: "A growable, heap-allocated sequence that owns its elements.", topic: "collections"),
        TermTrainPair(id: "hashmap", term: "entry", description: "Inserts a default only when a key is missing, then hands back a reference.", topic: "collections"),

        // Beginner ground the drill was missing.
        TermTrainPair(id: "main-fn", term: "fn main", description: "The entry point every Rust binary starts executing from.", topic: "hello-rust"),
        TermTrainPair(id: "if-expression", term: "if as an expression", description: "Every branch must produce the same type, because it yields a value.", topic: "control-flow"),
        TermTrainPair(id: "elision", term: "Lifetime elision", description: "The rules that let most signatures omit lifetime annotations.", topic: "lifetimes-intro"),
        TermTrainPair(id: "impl-block", term: "impl", description: "Attaches methods and constructors to a type.", topic: "structs"),
        TermTrainPair(id: "receiver", term: "&mut self", description: "A method receiver that borrows the value in order to change it.", topic: "structs"),
        TermTrainPair(id: "iterator-trait", term: "Iterator::next", description: "The single method a custom iterator has to implement.", topic: "iterator-impl"),
        TermTrainPair(id: "spawn", term: "thread::spawn", description: "Starts a thread whose closure must own everything it uses.", topic: "concurrency"),
        TermTrainPair(id: "thread-join", term: "JoinHandle::join", description: "Waits for a thread and hands back what it returned.", topic: "concurrency"),

        // Interview vocabulary: core language.
        TermTrainPair(id: "double-free", term: "Double free", description: "The bug single ownership makes impossible to write.", topic: "q-ownership"),
        TermTrainPair(id: "nll", term: "Non-lexical lifetimes", description: "A borrow ends at its last use, not at the end of the block.", topic: "q-borrowing"),
        TermTrainPair(id: "dangling", term: "Dangling reference", description: "A borrow of data that has already been dropped, which Rust rejects.", topic: "q-lifetimes"),
        TermTrainPair(id: "ok-or", term: "ok_or", description: "Turns an absent Option into a Result with a reason attached.", topic: "q-option-result"),
        TermTrainPair(id: "rc-not-send", term: "Rc across threads", description: "Rejected while compiling: its count is not atomic.", topic: "q-send-sync"),
        TermTrainPair(id: "sync-rule", term: "T is Sync when", description: "A shared reference to it is itself safe to send.", topic: "q-send-sync"),
        TermTrainPair(id: "atomic-count", term: "Atomic refcount", description: "What Arc pays for and Rc deliberately does not.", topic: "q-box-rc-arc"),
        TermTrainPair(id: "monomorphisation", term: "Monomorphisation", description: "One specialised copy of a generic per concrete type.", topic: "q-dyn-generics"),
        TermTrainPair(id: "vtable", term: "vtable", description: "The pointer table a trait object dispatches through at runtime.", topic: "q-dyn-generics"),
        TermTrainPair(id: "soundness", term: "Sound abstraction", description: "A safe API no caller can use to reach undefined behaviour.", topic: "q-unsafe"),

        // Interview vocabulary: concurrency.
        TermTrainPair(id: "acquire-release", term: "Acquire/Release", description: "Pairs so writes before the release are visible after the acquire.", topic: "q-atomics"),
        TermTrainPair(id: "seqcst", term: "SeqCst", description: "The strongest ordering: one global sequence, and the highest cost.", topic: "q-atomics"),
        TermTrainPair(id: "lock-order", term: "Lock ordering", description: "Always taking locks in one fixed order, which removes the cycle.", topic: "q-deadlock"),
        TermTrainPair(id: "mpsc", term: "mpsc channel", description: "Many producers, one consumer, ownership moving between them.", topic: "q-channels-vs-mutex"),
        TermTrainPair(id: "cpu-bound", term: "CPU-bound", description: "Work that computes rather than waits, so parallelism is what helps.", topic: "q-async-vs-threads"),
        TermTrainPair(id: "spawn-blocking", term: "spawn_blocking", description: "Moves a synchronous call off the executor threads.", topic: "q-blocking-async"),
        TermTrainPair(id: "cancel-safety", term: "Cancel safety", description: "A future can be dropped at an await without losing state.", topic: "q-cancellation"),

        // Interview vocabulary: systems and networking.
        TermTrainPair(id: "heap", term: "Heap", description: "Holds values sized at runtime, and needs an owner to free them.", topic: "q-stack-heap"),
        TermTrainPair(id: "page-fault", term: "Page fault", description: "The trap that makes the kernel back an address with a real frame.", topic: "q-virtual-memory"),
        TermTrainPair(id: "syscall", term: "Syscall", description: "A privilege-boundary crossing that costs far more than a call.", topic: "q-syscalls"),
        TermTrainPair(id: "datagram", term: "Datagram", description: "A message that may be lost, duplicated, or arrive out of order.", topic: "q-tcp-udp"),
        TermTrainPair(id: "hol-blocking", term: "Head-of-line blocking", description: "One stalled item holding up everything queued behind it.", topic: "q-http-versions"),
        TermTrainPair(id: "forward-secrecy", term: "Forward secrecy", description: "Recorded traffic stays unreadable even if the key leaks later.", topic: "q-tls"),
        TermTrainPair(id: "bounded-queue", term: "Bounded queue", description: "A limit that makes a producer wait instead of exhausting memory.", topic: "q-backpressure"),

        // Interview vocabulary: data and distributed systems.
        TermTrainPair(id: "isolation", term: "Serializable", description: "The level that behaves as if transactions ran one at a time.", topic: "q-acid"),
        TermTrainPair(id: "leftmost", term: "Leftmost prefix", description: "The only column order a composite index can actually serve.", topic: "q-indexes"),
        TermTrainPair(id: "partition", term: "Network partition", description: "The split that forces the choice between consistency and availability.", topic: "q-cap"),
        TermTrainPair(id: "idempotent", term: "Idempotency key", description: "Lets a repeated request return the first result instead of redoing it.", topic: "q-idempotency"),
        TermTrainPair(id: "stampede", term: "Cache stampede", description: "Every request missing at once the moment a hot key expires.", topic: "q-caching"),

        // Interview vocabulary: craft.
        TermTrainPair(id: "amortised", term: "Amortised O(1)", description: "Cheap on average, with an occasional expensive reallocation.", topic: "q-complexity"),
        TermTrainPair(id: "hash-flooding", term: "Hash flooding", description: "Chosen colliding keys turning a map lookup linear.", topic: "q-hashmap"),
        TermTrainPair(id: "property-test", term: "Property test", description: "Checks an invariant over generated inputs, not three examples.", topic: "q-testing-strategy"),
        TermTrainPair(id: "non-exhaustive", term: "non_exhaustive", description: "Forces a wildcard arm so adding a variant is not a breaking change.", topic: "q-api-design"),
        TermTrainPair(id: "release-build", term: "Release build", description: "The only build whose timings are worth comparing.", topic: "q-perf-profiling"),
        TermTrainPair(id: "abi", term: "ABI", description: "The binary contract two compiled languages agree on.", topic: "q-ffi-abi"),
    ]

    /// A fresh board, excluding anything already on screen.
    ///
    /// When mastery records are supplied the board leans towards terms the
    /// learner is weak on or that are due for review, rather than picking evenly.
    static func board(
        excluding used: Set<String> = [],
        size: Int = boardSize,
        records: [String: TopicMasteryRecord] = [:],
        now: Date = Date(),
        shuffled: Bool = true
    ) -> [TermTrainPair] {
        let available = all.filter { !used.contains($0.id) }
        let pool = available.count >= size ? available : all
        guard shuffled else { return Array(pool.prefix(size)) }
        guard !records.isEmpty else { return Array(pool.shuffled().prefix(size)) }

        let byTopic = Dictionary(grouping: pool, by: \.topic)
        var chosen: [TermTrainPair] = []
        var remaining = pool

        while chosen.count < size, !remaining.isEmpty {
            let topics = Array(Set(remaining.map(\.topic)))
            let picked = TopicScheduler.pick(count: 1, from: topics, records: records, now: now)
            guard let topic = picked.first,
                  let candidate = (byTopic[topic] ?? []).first(where: { pair in
                      remaining.contains(where: { $0.id == pair.id })
                  })
            else {
                break
            }
            chosen.append(candidate)
            remaining.removeAll { $0.id == candidate.id }
        }

        // Top up if mastery selection could not fill the board.
        for pair in remaining.shuffled() where chosen.count < size {
            chosen.append(pair)
        }
        return Array(chosen.prefix(size))
    }

    /// One replacement pair for the timed board, avoiding what is on screen.
    static func replacement(
        excluding used: Set<String>,
        records: [String: TopicMasteryRecord] = [:],
        now: Date = Date(),
        shuffled: Bool = true
    ) -> TermTrainPair? {
        let available = all.filter { !used.contains($0.id) }
        guard !available.isEmpty else { return nil }
        guard shuffled else { return available.first }
        guard !records.isEmpty else { return available.randomElement() }

        let topics = Array(Set(available.map(\.topic)))
        let picked = TopicScheduler.pick(count: 1, from: topics, records: records, now: now)
        if let topic = picked.first,
           let match = available.first(where: { $0.topic == topic }) {
            return match
        }
        return available.randomElement()
    }
}

/// The outcome of one run, which is what feeds rating and achievements.
struct TermTrainRunResult: Equatable, Sendable {
    let mode: TermTrainMode
    let matched: Int
    let mistakes: Int
    let bestStreak: Int
    let elapsedSeconds: Int

    var accuracy: Double {
        let attempts = matched + mistakes
        return attempts == 0 ? 0 : Double(matched) / Double(attempts)
    }

    var progressEvent: CrabrixProgressEvent {
        .termTrainFinished(
            pairs: matched,
            streak: bestStreak,
            seconds: mode == .timed ? elapsedSeconds : nil
        )
    }
}
