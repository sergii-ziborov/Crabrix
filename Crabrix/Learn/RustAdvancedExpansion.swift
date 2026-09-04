import Foundation

/// Slower bridge lessons for every course after Rust Basics.
///
/// Existing unit and lesson identifiers stay untouched. These units are
/// appended to their courses, so an installation that already has progress
/// keeps every completion while gaining a gentler second pass through the
/// material.
enum RustAdvancedExpansion {
    static let ownershipUnits = [
        unit(
            id: "ownership-practice",
            level: 7,
            title: "Ownership in Practice",
            subtitle: "Make borrowing choices in real function boundaries",
            ids: [
                "move-functions", "mutable-borrows", "reborrowing",
                "partial-moves", "interior-mutability-intro",
                "lifetime-elision", "owned-or-borrowed",
            ]
        ),
        unit(
            id: "abstraction-practice",
            level: 8,
            title: "Abstractions in Practice",
            subtitle: "Choose dispatch, adapters, and capture deliberately",
            ids: [
                "trait-objects", "blanket-impls",
                "default-trait-methods", "generic-lifetimes",
                "iterator-adapters", "closure-capture-modes",
                "phantom-data",
            ]
        ),
    ]

    static let projectUnits = [
        unit(
            id: "cargo-workflow",
            level: 9,
            title: "Cargo Workflow",
            subtitle: "Understand what each project file and command controls",
            ids: [
                "package-layout", "cargo-command-cycle",
                "dependency-kinds", "feature-design",
                "lockfile-reproducibility",
            ]
        ),
        unit(
            id: "project-quality",
            level: 10,
            title: "Project Quality",
            subtitle: "Tests, docs, errors, and release behavior",
            ids: [
                "integration-tests", "error-context",
                "doc-examples", "release-profiles",
            ]
        ),
    ]

    static let concurrencyUnits = [
        unit(
            id: "concurrency-safety",
            level: 11,
            title: "Concurrency Safety",
            subtitle: "Reason about lifetime, locks, and atomic state",
            ids: [
                "scoped-threads", "mutex-poisoning",
                "atomics-basics", "deadlock-avoidance",
            ]
        ),
        unit(
            id: "async-reliability",
            level: 12,
            title: "Async Reliability",
            subtitle: "Pin work, cancel safely, and isolate blocking calls",
            ids: [
                "pinning-intuition", "async-cancellation",
                "blocking-async",
            ]
        ),
    ]

    static let systemsUnits = [
        unit(
            id: "macro-design",
            level: 13,
            title: "Macro Design",
            subtitle: "Keep generated code predictable and debuggable",
            ids: [
                "macro-hygiene", "token-trees",
                "proc-macro-boundaries",
            ]
        ),
        unit(
            id: "unsafe-engineering",
            level: 14,
            title: "Unsafe Engineering",
            subtitle: "State invariants, control layout, and measure first",
            ids: [
                "raw-pointers", "repr-layout", "unsafe-traits",
                "benchmarking-profiling",
            ]
        ),
    ]

    static let interviewUnits = [
        unit(
            id: "interview-live-coding",
            level: 7,
            title: "Live Coding",
            subtitle: "Turn an unclear prompt into testable Rust",
            ids: [
                "q-two-sum-rust", "q-lru-design",
                "q-parser-design", "q-debugging-session",
            ]
        ),
        unit(
            id: "interview-delivery",
            level: 8,
            title: "Engineering Communication",
            subtitle: "Show the reasoning behind a technical decision",
            ids: [
                "q-tradeoff-communication", "q-requirements",
                "q-code-review", "q-postmortem",
            ]
        ),
    ]

    static let allUnits = ownershipUnits + projectUnits
        + concurrencyUnits + systemsUnits

    static let writing: [String: RustLessonWriting] = Dictionary(
        uniqueKeysWithValues: specs.map { ($0.id, $0.writing) }
    )

    static let termPairs: [TermTrainPair] = specs.map(\.termPair)

    private static func unit(
        id: String,
        level: Int,
        title: String,
        subtitle: String,
        ids: [String]
    ) -> RustLearningUnit {
        let byID = Dictionary(uniqueKeysWithValues: specs.map { ($0.id, $0) })
        return RustLearningUnit(
            id: id,
            level: level,
            title: title,
            subtitle: subtitle,
            lessons: ids.compactMap { byID[$0]?.lesson }
        )
    }

    private static let specs: [AdvancedLessonSpec] = [
        .init(
            id: "move-functions",
            title: "Moves Across Functions",
            concept: "Parameters can take, borrow, or copy a value",
            minutes: 9,
            insight: "A parameter of type String takes ownership, while &str only borrows text. Read the signature before deciding whether the caller should keep using its value.",
            code: """
            fn inspect(text: &str) {
                println!("{text}");
            }
            let name = String::from("Ferris");
            inspect(&name);
            println!("{name}");
            """,
            question: "Why can name be printed after inspect?",
            answers: ["String is Copy", "inspect only borrowed it", "println! restores it"],
            correctAnswer: 1,
            term: "Taking ownership",
            termDescription: "A by-value parameter becomes the new owner."
        ),
        .init(
            id: "mutable-borrows",
            title: "Mutable Borrows",
            concept: "One temporary writer with exclusive access",
            minutes: 9,
            insight: "An &mut reference permits mutation without transferring ownership. Exclusivity lasts through its final use, preventing another reader or writer from observing a half-finished update.",
            code: """
            fn add_one(value: &mut i32) {
                *value += 1;
            }
            let mut score = 6;
            add_one(&mut score);
            println!("{score}");
            """,
            question: "What does &mut grant temporarily?",
            answers: ["Shared read access", "Exclusive write access", "A copied value"],
            correctAnswer: 1,
            term: "Exclusive borrow",
            termDescription: "A temporary reference that permits one writer."
        ),
        .init(
            id: "reborrowing",
            title: "Reborrowing",
            concept: "Lend access without consuming the original reference",
            minutes: 10,
            insight: "Passing &mut *value creates a shorter reborrow instead of moving the original mutable reference. This lets a helper work briefly and returns control to the outer borrower afterward.",
            code: """
            fn bump(value: &mut i32) {
                *value += 1;
            }
            fn twice(value: &mut i32) {
                bump(&mut *value);
                bump(&mut *value);
            }
            """,
            question: "Why is value usable for the second call?",
            answers: ["It was copied", "Each reborrow ends", "bump returns it"],
            correctAnswer: 1,
            term: "Reborrow",
            termDescription: "A shorter borrow made from an existing borrow."
        ),
        .init(
            id: "partial-moves",
            title: "Partial Moves",
            concept: "Move one field while borrowing another",
            minutes: 10,
            insight: "Destructuring can move an owned field and copy or borrow the rest. After a partial move the whole struct is unavailable, but fields that were not moved may still be used directly.",
            code: """
            struct User {
                name: String,
                level: u8,
            }
            let user = User {
                name: "Ada".into(), level: 7,
            };
            let name = user.name;
            println!("{}", user.level);
            """,
            question: "Why is user.name no longer available?",
            answers: ["It was moved", "level borrowed it", "Structs expire"],
            correctAnswer: 0,
            term: "Partial move",
            termDescription: "Moving one field without moving every field."
        ),
        .init(
            id: "interior-mutability-intro",
            title: "Interior Mutability",
            concept: "Move a checked borrow rule to runtime",
            minutes: 11,
            insight: "Cell and RefCell allow mutation behind an immutable outer binding. RefCell enforces the same shared-or-exclusive rule at runtime and panics if code violates it.",
            code: """
            use std::cell::RefCell;
            let notes = RefCell::new(Vec::new());
            notes.borrow_mut().push("ready");
            println!("{}", notes.borrow().len());
            """,
            question: "Where does RefCell check borrowing?",
            answers: ["At runtime", "In Cargo.lock", "It does not check"],
            correctAnswer: 0,
            term: "Interior mutability",
            termDescription: "Mutation behind a shared outer value."
        ),
        .init(
            id: "lifetime-elision",
            title: "Lifetime Elision",
            concept: "The common lifetime relationships Rust infers",
            minutes: 9,
            insight: "Rust omits obvious lifetime annotations using a small set of rules. One borrowed input can usually determine the returned borrow, keeping signatures readable without weakening the proof.",
            code: """
            fn first(text: &str) -> &str {
                text.split(' ').next().unwrap_or(text)
            }
            """,
            question: "Why does first need no named lifetime?",
            answers: [
                "Every &str already has a static lifetime",
                "One input determines output",
                "unwrap supplies the missing lifetime",
            ],
            correctAnswer: 1,
            term: "Elision rule",
            termDescription: "Inference rules for common borrow signatures."
        ),
        .init(
            id: "owned-or-borrowed",
            title: "Owned or Borrowed?",
            concept: "Choose a return type that matches the data flow",
            minutes: 10,
            insight: "Return a borrow when the result is a view into an input; return an owned value when new data is created or must escape independently. The choice affects allocation and API flexibility.",
            code: """
            fn label(input: &str) -> String {
                input.trim().to_uppercase()
            }
            fn trimmed(input: &str) -> &str {
                input.trim()
            }
            """,
            question: "Why does label return String?",
            answers: ["It creates new text", "&str is slower", "trim requires it"],
            correctAnswer: 0,
            term: "Ownership boundary",
            termDescription: "The API point that decides who owns output."
        ),
        .init(
            id: "trait-objects",
            title: "Trait Objects",
            concept: "Choose behavior at runtime with dyn Trait",
            minutes: 11,
            insight: "A trait object stores a pointer to data and a table of methods. It enables mixed concrete types in one collection at the cost of dynamic dispatch and some optimization opportunities.",
            code: """
            trait Draw { fn draw(&self); }
            fn render(items: &[Box<dyn Draw>]) {
                for item in items {
                    item.draw();
                }
            }
            """,
            question: "What does dyn Trait choose at runtime?",
            answers: ["The concrete method", "The lifetime", "The crate version"],
            correctAnswer: 0,
            term: "Dynamic dispatch",
            termDescription: "Selecting a trait method through a vtable."
        ),
        .init(
            id: "blanket-impls",
            title: "Blanket Implementations",
            concept: "Implement behavior for every matching type",
            minutes: 10,
            insight: "A generic impl can grant a trait to all types satisfying a bound. Blanket implementations are powerful because they shape which future implementations remain legal under coherence rules.",
            code: """
            trait Named { fn name(&self) -> String; }
            impl<T: std::fmt::Display> Named for T {
                fn name(&self) -> String {
                    self.to_string()
                }
            }
            """,
            question: "Who receives Named in this impl?",
            answers: ["Only String", "Every Display type", "Only local types"],
            correctAnswer: 1,
            term: "Blanket impl",
            termDescription: "One implementation covering a bounded type set."
        ),
        .init(
            id: "default-trait-methods",
            title: "Default Trait Methods",
            concept: "Share behavior while allowing an override",
            minutes: 9,
            insight: "A trait may provide a method body that implementations inherit. Defaults reduce repetition, while required methods still define the minimum contract each type must supply.",
            code: """
            trait Summary {
                fn title(&self) -> &str;
                fn summary(&self) -> String {
                    format!("Title: {}", self.title())
                }
            }
            """,
            question: "Which method must an impl provide?",
            answers: ["title", "summary", "Both methods"],
            correctAnswer: 0,
            term: "Default method",
            termDescription: "A trait method body implementations inherit."
        ),
        .init(
            id: "generic-lifetimes",
            title: "Generic Lifetimes",
            concept: "Combine type bounds with borrow relationships",
            minutes: 11,
            insight: "A function may be generic over both a data type and a lifetime. Keep each parameter only when the body needs it; extra bounds make an API less reusable without adding safety.",
            code: """
            fn choose<'a, T>(left: &'a T, right: &'a T)
                -> &'a T
            where T: Ord {
                if left > right { left } else { right }
            }
            """,
            question: "What does 'a connect here?",
            answers: ["Both inputs and output", "Only T", "The Ord impl"],
            correctAnswer: 0,
            term: "Generic borrow",
            termDescription: "A lifetime relationship independent of data type."
        ),
        .init(
            id: "iterator-adapters",
            title: "Iterator Pipelines",
            concept: "Transform lazily, then choose one consumer",
            minutes: 10,
            insight: "Adapters such as map and filter describe work but do nothing until a consumer asks for values. A clear pipeline separates selection, transformation, and collection without temporary vectors.",
            code: """
            let values = [1, 2, 3, 4];
            let total: i32 = values.iter()
                .filter(|v| **v % 2 == 0)
                .map(|v| v * v)
                .sum();
            """,
            question: "When does the pipeline perform work?",
            answers: ["At .iter()", "When sum consumes it", "During parsing"],
            correctAnswer: 1,
            term: "Iterator consumer",
            termDescription: "An operation that drives a lazy iterator."
        ),
        .init(
            id: "closure-capture-modes",
            title: "Closure Capture Modes",
            concept: "Infer shared, mutable, or moved captures",
            minutes: 11,
            insight: "A closure borrows, mutably borrows, or moves each captured value according to its body. The move keyword transfers captures even when the body would otherwise only borrow them.",
            code: """
            let name = String::from("Ferris");
            let announce = move || {
                println!("{name}");
            };
            announce();
            """,
            question: "What does move change?",
            answers: ["Capture ownership", "Return type", "Call syntax"],
            correctAnswer: 0,
            term: "Move closure",
            termDescription: "A closure that takes ownership of captures."
        ),
        .init(
            id: "phantom-data",
            title: "Phantom Types",
            concept: "Track a compile-time state with no stored value",
            minutes: 12,
            insight: "PhantomData tells the type system that a zero-sized marker matters to ownership or state. It enables APIs where illegal transitions have no callable method, without adding runtime storage.",
            code: """
            use std::marker::PhantomData;
            struct Ready;
            struct Job<State> {
                id: u32,
                state: PhantomData<State>,
            }
            """,
            question: "How many bytes does PhantomData add?",
            answers: ["Usually zero", "One pointer", "The size of State"],
            correctAnswer: 0,
            term: "PhantomData",
            termDescription: "A zero-sized marker carrying type information."
        ),
        .init(
            id: "package-layout",
            title: "Package Layout",
            concept: "Map Cargo targets to predictable source paths",
            minutes: 9,
            insight: "src/main.rs defines the default binary and src/lib.rs defines the library target. Additional binaries and integration tests have conventional directories that keep tooling automatic.",
            code: """
            // src/lib.rs
            pub fn answer() -> u32 { 42 }

            // src/main.rs
            fn main() {
                println!("{}", demo::answer());
            }
            """,
            question: "Which file defines the library target?",
            answers: ["src/lib.rs", "src/main.rs", "Cargo.lock"],
            correctAnswer: 0,
            term: "Cargo target layout",
            termDescription: "Conventional paths that define build targets."
        ),
        .init(
            id: "cargo-command-cycle",
            title: "Check, Build, Run",
            concept: "Choose the cheapest command that proves the next fact",
            minutes: 9,
            insight: "cargo check proves type correctness without final code generation, build creates artifacts, and run executes a binary after building it. Fast feedback comes from asking only for the evidence you need.",
            code: """
            // Fast type feedback:
            // cargo check
            // Produce an executable:
            // cargo build
            // Build and execute:
            // cargo run
            """,
            question: "Which command skips final code generation?",
            answers: ["cargo check", "cargo build", "cargo run"],
            correctAnswer: 0,
            term: "Cargo check cycle",
            termDescription: "Using the cheapest command for current evidence."
        ),
        .init(
            id: "dependency-kinds",
            title: "Dependency Kinds",
            concept: "Separate runtime, build, and test-only tools",
            minutes: 10,
            insight: "Normal dependencies become part of a target graph, build dependencies support build scripts, and dev dependencies exist for tests and examples. The distinction keeps production graphs smaller and clearer.",
            code: """
            [dependencies]
            log = "0.4"

            [dev-dependencies]
            pretty_assertions = "1"
            """,
            question: "Where does a test-only crate belong?",
            answers: ["dev-dependencies", "profile.release", "workspace"],
            correctAnswer: 0,
            term: "Dev dependency",
            termDescription: "A crate used by tests, examples, or benches."
        ),
        .init(
            id: "feature-design",
            title: "Feature Design",
            concept: "Make optional capability additive and explicit",
            minutes: 11,
            insight: "Cargo features are unified across a dependency graph, so disabling one consumer's feature may not disable it globally. Prefer additive capabilities and avoid features that make the same API mean incompatible things.",
            code: """
            #[cfg(feature = "color")]
            fn paint() { println!("color"); }

            #[cfg(not(feature = "color"))]
            fn paint() { println!("plain"); }
            """,
            question: "What style makes features compose well?",
            answers: ["Additive capability", "Mutual exclusion", "Hidden defaults"],
            correctAnswer: 0,
            term: "Additive feature",
            termDescription: "A feature that adds capability without conflict."
        ),
        .init(
            id: "lockfile-reproducibility",
            title: "Lockfile Reproducibility",
            concept: "Build the same resolved graph again",
            minutes: 10,
            insight: "Cargo.toml describes allowed versions while Cargo.lock records the exact chosen graph. Applications normally commit the lockfile so a later build does not silently select newer compatible releases.",
            code: """
            [[package]]
            name = "smallvec"
            version = "1.13.2"
            checksum = "..."
            """,
            question: "What does Cargo.lock pin?",
            answers: ["The exact graph", "Only the root name", "The Rust edition"],
            correctAnswer: 0,
            term: "Locked graph",
            termDescription: "Exact package versions selected for a build."
        ),
        .init(
            id: "integration-tests",
            title: "Integration Tests",
            concept: "Test the public API as an outside user",
            minutes: 10,
            insight: "Files under tests/ compile as separate crates and can only use the library's public API. That boundary catches accidental reliance on private implementation details.",
            code: """
            // tests/public_api.rs
            use demo::answer;

            #[test]
            fn answer_is_stable() {
                assert_eq!(answer(), 42);
            }
            """,
            question: "Why can this test not use private items?",
            answers: ["It is a separate crate", "Tests ban privacy", "assert_eq! hides them"],
            correctAnswer: 0,
            term: "Integration test crate",
            termDescription: "A separate test target using only public API."
        ),
        .init(
            id: "error-context",
            title: "Error Context",
            concept: "Preserve a cause while explaining the failed operation",
            minutes: 11,
            insight: "A useful error says what operation failed and retains the original cause. Add context at abstraction boundaries rather than replacing specific information with one vague message.",
            code: """
            fn port(text: &str) -> Result<u16, String> {
                text.parse().map_err(|error| {
                    format!("invalid port {text}: {error}")
                })
            }
            """,
            question: "What should context preserve?",
            answers: ["The original cause", "Only a short label", "A stack address"],
            correctAnswer: 0,
            term: "Error context boundary",
            termDescription: "The layer that adds operation-specific meaning."
        ),
        .init(
            id: "doc-examples",
            title: "Executable Documentation",
            concept: "Keep API examples checked by the test suite",
            minutes: 9,
            insight: "Rust documentation code blocks can compile and run as tests: cargo test builds every ``` block in a doc comment and runs it. A small realistic example teaches usage and fails when an API change makes the documentation stale.",
            code: """
            /// Adds one.
            ///
            /// ```
            /// assert_eq!(demo::add_one(4), 5);
            /// ```
            pub fn add_one(v: i32) -> i32 { v + 1 }
            """,
            question: "What checks a Rust doc example?",
            answers: ["cargo test", "cargo clean", "rustfmt only"],
            correctAnswer: 0,
            term: "Executable docs",
            termDescription: "Documentation examples compiled as tests."
        ),
        .init(
            id: "release-profiles",
            title: "Release Profiles",
            concept: "Tune optimization without changing source behavior",
            minutes: 10,
            insight: "Cargo profiles configure optimization, debug information, panic strategy, and more. Measure the real workload before trading compile time, binary size, or debuggability for speed.",
            code: """
            [profile.release]
            opt-level = 3
            lto = "thin"
            debug = 1
            """,
            question: "What should guide profile changes?",
            answers: ["Measurements", "The longest option list", "Debug defaults"],
            correctAnswer: 0,
            term: "Release profile",
            termDescription: "Cargo settings for optimized build artifacts."
        ),
        .init(
            id: "scoped-threads",
            title: "Scoped Threads",
            concept: "Borrow local data while threads are guaranteed to join",
            minutes: 11,
            insight: "thread::scope proves every spawned thread finishes before borrowed stack data disappears. It avoids unnecessary Arc or cloning when concurrency stays inside one lexical operation.",
            code: """
            let values = [2, 4, 6];
            std::thread::scope(|scope| {
                scope.spawn(|| {
                    println!("{}", values.len());
                });
            });
            """,
            question: "Why may the thread borrow values?",
            answers: ["The scope joins it", "Arrays are static", "spawn copies all"],
            correctAnswer: 0,
            term: "Scoped thread",
            termDescription: "A thread joined before borrowed locals expire."
        ),
        .init(
            id: "mutex-poisoning",
            title: "Mutex Poisoning",
            concept: "Notice a panic that may leave state inconsistent",
            minutes: 10,
            insight: "A standard Mutex becomes poisoned when a holder panics. Recovery is possible, but code must decide whether the protected invariant is still trustworthy instead of blindly ignoring the signal.",
            code: """
            use std::sync::Mutex;
            let value = Mutex::new(7);
            match value.lock() {
                Ok(guard) => println!("{guard}"),
                Err(poisoned) => {
                    println!("{}", *poisoned.into_inner());
                }
            }
            """,
            question: "What does poisoning report?",
            answers: ["A holder panicked", "The lock is slow", "The value moved"],
            correctAnswer: 0,
            term: "Poisoned mutex",
            termDescription: "A lock whose previous holder unwound in panic."
        ),
        .init(
            id: "atomics-basics",
            title: "Atomic State",
            concept: "Update one shared value without a lock",
            minutes: 12,
            insight: "Atomic operations are indivisible but still need an ordering that describes cross-thread visibility. Use the weakest ordering justified by a written synchronization argument, not by habit.",
            code: """
            use std::sync::atomic::{
                AtomicUsize, Ordering,
            };
            let count = AtomicUsize::new(0);
            count.fetch_add(1, Ordering::Relaxed);
            """,
            question: "What does an atomic ordering describe?",
            answers: ["Visibility constraints", "Integer size", "Thread count"],
            correctAnswer: 0,
            term: "Atomic ordering",
            termDescription: "Rules for visibility around atomic operations."
        ),
        .init(
            id: "deadlock-avoidance",
            title: "Deadlock Avoidance",
            concept: "Keep a global lock order and short critical sections",
            minutes: 11,
            insight: "Rust prevents data races, not deadlocks. A consistent order for acquiring multiple locks and avoiding calls into unknown code while locked remove common wait cycles.",
            code: """
            // Every path locks account id in ascending
            // order before transferring a balance.
            let (first, second) = if a_id < b_id {
                (&a, &b)
            } else {
                (&b, &a)
            };
            """,
            question: "What prevents the wait cycle here?",
            answers: ["One lock order", "More threads", "A mutable borrow"],
            correctAnswer: 0,
            term: "Global lock order",
            termDescription: "A global sequence for acquiring multiple locks."
        ),
        .init(
            id: "pinning-intuition",
            title: "Pinning Intuition",
            concept: "Promise that a value will not move in memory",
            minutes: 12,
            insight: "Pin protects location-sensitive values after they are pinned; it does not make every value immovable from creation. Most users interact through pinned futures while libraries handle the unsafe construction details.",
            code: """
            use std::pin::Pin;
            fn poll_name(value: Pin<&mut String>) {
                println!("{}", value.len());
            }
            """,
            question: "What does Pin promise?",
            answers: ["Stable location", "Thread safety", "Static lifetime"],
            correctAnswer: 0,
            term: "Pinned value",
            termDescription: "A value promised not to move from its location."
        ),
        .init(
            id: "async-cancellation",
            title: "Cancellation Safety",
            concept: "Expect a future to be dropped at any await point",
            minutes: 12,
            insight: "Selecting or timing out a future may drop it before completion. Keep partial state consistent across await points, or wrap the operation so retrying cannot duplicate or lose external effects.",
            code: """
            async fn save_then_ack() {
                save_record().await;
                // Cancellation here means saved,
                // but not acknowledged.
                send_ack().await;
            }
            """,
            question: "When may cancellation occur?",
            answers: ["At an await suspension", "Only at return", "Before async fn starts"],
            correctAnswer: 0,
            term: "Cancellation point",
            termDescription: "A suspension where a future may be dropped."
        ),
        .init(
            id: "blocking-async",
            title: "Blocking in Async Code",
            concept: "Keep executor threads available to poll other futures",
            minutes: 11,
            insight: "A blocking call occupies an executor worker without yielding, so unrelated tasks can stall. Move CPU-heavy or blocking work to a dedicated pool and await its result.",
            code: """
            async fn handler() {
                // Do not sleep the executor thread:
                // std::thread::sleep(...);
                async_timer().await;
            }
            """,
            question: "Why is a blocking sleep harmful here?",
            answers: ["It stalls a worker", "It moves the future", "It poisons a lock"],
            correctAnswer: 0,
            term: "Executor starvation",
            termDescription: "Blocking workers so futures cannot be polled."
        ),
        .init(
            id: "macro-hygiene",
            title: "Macro Hygiene",
            concept: "Resolve generated names without accidental capture",
            minutes: 11,
            insight: "Rust macros track syntax context so identifiers introduced by a macro do not casually collide with names at the call site. Use explicit paths such as $crate for helper items exported with a macro.",
            code: """
            #[macro_export]
            macro_rules! answer {
                () => { $crate::value() };
            }
            """,
            question: "What does $crate name?",
            answers: ["The defining crate", "The caller variable", "Cargo.lock"],
            correctAnswer: 0,
            term: "Macro hygiene",
            termDescription: "Context-aware resolution of generated names."
        ),
        .init(
            id: "token-trees",
            title: "Token Trees",
            concept: "Match Rust syntax as nested tokens, not raw text",
            minutes: 11,
            insight: "macro_rules! consumes token trees with balanced delimiters. Fragment specifiers such as expr and ty let the parser validate shapes before expansion, producing safer patterns than string substitution.",
            code: """
            macro_rules! twice {
                ($value:expr) => {{
                    let once = $value;
                    once + once
                }};
            }
            """,
            question: "What does :expr require?",
            answers: ["A Rust expression", "Any text", "A type only"],
            correctAnswer: 0,
            term: "Token tree",
            termDescription: "Balanced syntax tokens consumed by a macro."
        ),
        .init(
            id: "proc-macro-boundaries",
            title: "Proc-Macro Boundaries",
            concept: "Separate host-time generation from target code",
            minutes: 12,
            insight: "A procedural macro is compiled for and runs on the build host, then emits tokens for the target crate. It cannot depend on target runtime state and should emit spans that point errors back to useful input.",
            code: """
            // Host process:
            #[proc_macro_derive(Builder)]
            pub fn derive(input: TokenStream)
                -> TokenStream {
                expand(input)
            }
            """,
            question: "Where does a proc macro execute?",
            answers: ["On the build host", "Inside the target app", "In Cargo.toml"],
            correctAnswer: 0,
            term: "Host proc macro",
            termDescription: "Compile-time code executed for the build host."
        ),
        .init(
            id: "raw-pointers",
            title: "Raw Pointers",
            concept: "Represent an address without borrow guarantees",
            minutes: 12,
            insight: "Creating *const T or *mut T is safe; dereferencing one is unsafe because validity, alignment, initialization, and aliasing are now the programmer's proof obligations.",
            code: """
            let value = 7_u32;
            let pointer: *const u32 = &value;
            let read = unsafe { *pointer };
            println!("{read}");
            """,
            question: "Which operation needs unsafe?",
            answers: ["Dereferencing", "Creating the pointer", "Printing the value"],
            correctAnswer: 0,
            term: "Raw pointer invariant",
            termDescription: "Validity facts required before dereferencing."
        ),
        .init(
            id: "repr-layout",
            title: "Representation & Layout",
            concept: "Make a data layout contract explicit at a boundary",
            minutes: 12,
            insight: "Rust's default layout may change for optimization and is not an FFI contract. repr(C) gives C-compatible field ordering while fixed integer types make sizes explicit.",
            code: """
            #[repr(C)]
            struct Header {
                kind: u16,
                length: u32,
            }
            """,
            question: "Why add repr(C) at FFI?",
            answers: ["To define layout", "To allocate on heap", "To add Copy"],
            correctAnswer: 0,
            term: "repr(C) contract",
            termDescription: "A C-compatible field layout promise."
        ),
        .init(
            id: "unsafe-traits",
            title: "Unsafe Traits",
            concept: "Make an implementation promise other unsafe code relies on",
            minutes: 13,
            insight: "An unsafe trait means incorrect implementation can cause undefined behavior in code that trusts it. Document every invariant precisely and keep the unsafe impl beside evidence that it holds.",
            code: """
            unsafe trait StableAddress {}

            struct FixedBuffer([u8; 16]);
            // SAFETY: instances never expose moves.
            unsafe impl StableAddress for FixedBuffer {}
            """,
            question: "Why is the impl unsafe?",
            answers: ["Callers rely on its promise", "Traits are unchecked", "It uses an array"],
            correctAnswer: 0,
            term: "Unsafe trait contract",
            termDescription: "An invariant trusted by other unsafe code."
        ),
        .init(
            id: "benchmarking-profiling",
            title: "Benchmark & Profile",
            concept: "Find the real bottleneck before optimizing",
            minutes: 11,
            insight: "A benchmark measures a stable workload; a profiler explains where its time or allocations go. Change one variable, protect against optimized-away work, and compare distributions rather than one lucky run.",
            code: """
            let start = std::time::Instant::now();
            let answer = workload();
            std::hint::black_box(answer);
            println!("{:?}", start.elapsed());
            """,
            question: "What should happen before optimization?",
            answers: [
                "Measure a workload",
                "Rewrite the hot loop from intuition",
                "Raise opt-level blindly",
            ],
            correctAnswer: 0,
            term: "Performance baseline",
            termDescription: "A repeatable measurement before a code change."
        ),
        .init(
            id: "q-two-sum-rust",
            title: "Live Coding: Two Sum",
            concept: "Clarify duplicates, indices, and complexity first",
            minutes: 12,
            insight: "State the contract before reaching for HashMap: may one index be reused, can values repeat, and what should happen when no pair exists? Then explain the O(n) time and O(n) space tradeoff.",
            code: """
            fn two_sum(values: &[i32], target: i32)
                -> Option<(usize, usize)> {
                // Track value -> earlier index.
                todo!()
            }
            """,
            question: "What return type models no matching pair?",
            answers: ["Option", "bool only", "A panic"],
            correctAnswer: 0,
            term: "Live-coding contract",
            termDescription: "Explicit input, output, and edge-case rules."
        ),
        .init(
            id: "q-lru-design",
            title: "Design an LRU Cache",
            concept: "Combine lookup speed with recency updates",
            minutes: 13,
            insight: "Explain why a hash map alone cannot evict the least recent key in O(1). The usual design pairs lookup with an order structure and makes capacity, ownership, and mutation costs explicit.",
            code: """
            struct Lru<K, V> {
                capacity: usize,
                // map: K -> node
                // order: most to least recent
                marker: std::marker::PhantomData<(K, V)>,
            }
            """,
            question: "What second structure tracks recency?",
            answers: ["An order list", "Another capacity", "A thread"],
            correctAnswer: 0,
            term: "LRU recency index",
            termDescription: "An order structure updated on every access."
        ),
        .init(
            id: "q-parser-design",
            title: "Design a Parser",
            concept: "Separate tokenization, grammar, and diagnostics",
            minutes: 12,
            insight: "A strong answer defines input ownership, source spans, recovery strategy, and whether the parser returns a tree or events. Separate lexing from grammar only when that boundary improves errors or complexity.",
            code: """
            struct Span { start: usize, end: usize }
            enum Token<'a> {
                Word(&'a str, Span),
                Number(u64, Span),
            }
            """,
            question: "Why retain source spans?",
            answers: ["Precise diagnostics", "Faster allocation", "Automatic parsing"],
            correctAnswer: 0,
            term: "Parser source span",
            termDescription: "Input coordinates carried into diagnostics."
        ),
        .init(
            id: "q-debugging-session",
            title: "Debugging Out Loud",
            concept: "Form a hypothesis and request one discriminating fact",
            minutes: 11,
            insight: "Do not edit randomly during an interview. Restate the symptom, identify the first impossible state, propose one hypothesis, and choose the smallest observation that can disprove it.",
            code: """
            fn average(values: &[u32]) -> u32 {
                let total: u32 = values.iter().sum();
                total / values.len() as u32
            }
            """,
            question: "What edge case should be checked first?",
            answers: ["An empty slice", "A sorted slice", "A borrowed slice"],
            correctAnswer: 0,
            term: "Discriminating observation",
            termDescription: "One fact that can disprove a debug hypothesis."
        ),
        .init(
            id: "q-tradeoff-communication",
            title: "Communicate a Tradeoff",
            concept: "Tie a choice to constraints and a failure mode",
            minutes: 10,
            insight: "A senior answer does not call one tool universally best. Name the current constraint, compare at least two viable choices, state the cost you accept, and say what evidence would change the decision.",
            code: """
            enum Choice {
                Channel,
                Mutex,
            }
            // Choose from ownership and workload facts.
            """,
            question: "What makes a tradeoff answer testable?",
            answers: ["Decision criteria", "More jargon", "One absolute rule"],
            correctAnswer: 0,
            term: "Decision criterion",
            termDescription: "A constraint that can change a technical choice."
        ),
        .init(
            id: "q-requirements",
            title: "Clarify Requirements",
            concept: "Turn a broad prompt into boundaries and invariants",
            minutes: 10,
            insight: "Ask about scale, latency, durability, consistency, trust boundaries, and expected failure. Good clarifying questions shrink the design space and reveal which guarantee the interviewer actually wants explored.",
            code: """
            struct Requirements {
                max_items: usize,
                durable: bool,
                latency_ms: u64,
            }
            """,
            question: "Why ask for scale before choosing storage?",
            answers: ["It changes viable designs", "It names a type", "It avoids tests"],
            correctAnswer: 0,
            term: "Requirement boundary",
            termDescription: "A constraint that narrows the design space."
        ),
        .init(
            id: "q-code-review",
            title: "Review Rust Code",
            concept: "Prioritize correctness, API contracts, then style",
            minutes: 11,
            insight: "Start with soundness, data loss, and observable behavior before naming cosmetic issues. Explain impact, point to evidence, and offer a smaller safer change instead of rewriting to personal taste.",
            code: """
            fn first(values: &[String]) -> &str {
                values[0].as_str()
            }
            """,
            question: "What correctness risk appears first?",
            answers: ["Empty input panics", "The borrow is slow", "String is mutable"],
            correctAnswer: 0,
            term: "Review severity order",
            termDescription: "Correctness before maintainability before style."
        ),
        .init(
            id: "q-postmortem",
            title: "Explain an Incident",
            concept: "Describe conditions and controls, not one guilty person",
            minutes: 11,
            insight: "A useful postmortem separates trigger, contributing conditions, detection gaps, impact, and durable actions. Prefer controls that make recurrence harder over promises to be more careful.",
            code: """
            struct Incident {
                trigger: &'static str,
                detection_gap: &'static str,
                durable_action: &'static str,
            }
            """,
            question: "What is stronger than 'be careful'?",
            answers: ["A durable control", "A longer meeting", "One person's memory"],
            correctAnswer: 0,
            term: "Durable corrective action",
            termDescription: "A control that prevents or detects recurrence."
        ),
    ]
}

private struct AdvancedLessonSpec: Sendable {
    let id: String
    let title: String
    let concept: String
    let minutes: Int
    let insight: String
    let code: String
    let question: String
    let answers: [String]
    let correctAnswer: Int
    let term: String
    let termDescription: String

    var lesson: RustLesson {
        RustLesson(
            id: id,
            title: title,
            concept: concept,
            minutes: minutes,
            exercise: .planned
        )
    }

    var writing: RustLessonWriting {
        RustLessonWriting(
            summary: concept + ".",
            explanation: insight,
            exampleCaption: "The example makes the contract visible in code.",
            exampleCode: code,
            task: "Trace the example, name the guarantee, and identify where it ends.",
            success: "You can apply the rule to a new snippet and defend the tradeoff.",
            rule: insight.components(separatedBy: ".").first.map { $0 + "." } ?? insight,
            practiceCode: code,
            question: question,
            answers: answers,
            correctAnswer: correctAnswer,
            feedback: answers.indices.contains(correctAnswer)
                ? "Correct: \(answers[correctAnswer])."
                : "Review the contract in the example."
        )
    }

    var termPair: TermTrainPair {
        TermTrainPair(
            id: "advanced-\(id)",
            term: term,
            description: termDescription,
            topic: id
        )
    }
}
