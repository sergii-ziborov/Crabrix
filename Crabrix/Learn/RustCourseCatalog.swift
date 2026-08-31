import Foundation

enum RustCourseTheme: String, Sendable {
    case basics
    case ownership
    case projects
    case concurrency
    case systems
    case interview
    case algorithms
}

struct RustCourse: Identifiable, Sendable {
    let id: String
    let level: String
    let title: String
    let subtitle: String
    let systemImage: String
    let theme: RustCourseTheme
    let units: [RustLearningUnit]
}

enum RustCourseCatalog {
    static let courses: [RustCourse] = [
        RustCourse(
            id: "basics",
            level: "BEGINNER",
            title: "Rust Basics",
            subtitle: "A gradual path from the first line to small, reliable programs",
            systemImage: "leaf.fill",
            theme: .basics,
            units: units("foundations", "expressions-flow", "small-programs", "modeling")
        ),
        RustCourse(
            id: "algorithms",
            level: "EASY → HARD",
            title: "Algorithms",
            subtitle: "200 reusable patterns, each taught twice and then proved in a Rust challenge",
            systemImage: "point.3.connected.trianglepath.dotted",
            theme: .algorithms,
            units: AlgorithmCourseCatalog.units
        ),
        RustCourse(
            id: "ownership",
            level: "INTERMEDIATE",
            title: "Ownership Mastery",
            subtitle: "Borrowing, lifetimes, traits, iterators, and compiler-guided repair",
            systemImage: "link.circle.fill",
            theme: .ownership,
            units: units(
                "ownership", "abstraction",
                "ownership-practice", "abstraction-practice"
            )
        ),
        RustCourse(
            id: "projects",
            level: "ADVANCED",
            title: "Cargo & Real Projects",
            subtitle: "Modules, testing, error design, dependencies, and smart pointers",
            systemImage: "shippingbox.fill",
            theme: .projects,
            units: units(
                "projects", "pointers",
                "cargo-workflow", "project-quality"
            )
        ),
        RustCourse(
            id: "concurrency",
            level: "ADVANCED",
            title: "Concurrency & Async",
            subtitle: "Threads, channels, shared state, and async/await",
            systemImage: "arrow.triangle.branch",
            theme: .concurrency,
            units: units(
                "threads", "async",
                "concurrency-safety", "async-reliability"
            )
        ),
        RustCourse(
            id: "systems",
            level: "EXPERT",
            title: "Macros & Systems Rust",
            subtitle: "Metaprogramming, unsafe, FFI, performance, and idioms",
            systemImage: "cpu.fill",
            theme: .systems,
            units: units(
                "meta", "systems",
                "macro-design", "unsafe-engineering"
            )
        ),
        RustCourse(
            id: "interview",
            level: "CAREER",
            title: "Rust Interview Prep",
            subtitle: "Explain the hard ideas clearly and practice common interview questions",
            systemImage: "person.wave.2.fill",
            theme: .interview,
            units: interviewUnits + RustAdvancedExpansion.interviewUnits
        ),
    ]

    static func course(id: String) -> RustCourse? {
        courses.first { $0.id == id }
    }

    static func course(containingLessonID lessonID: String) -> RustCourse? {
        courses.first { course in
            course.units.contains { unit in
                unit.lessons.contains { $0.id == lessonID }
            }
        }
    }

    static func lesson(id: String) -> RustLesson? {
        courses
            .lazy
            .flatMap(\.units)
            .flatMap(\.lessons)
            .first { $0.id == id }
    }

    static var lessonCount: Int {
        courses.flatMap(\.units).flatMap(\.lessons).count
    }

    /// Lessons on the Rust language path, excluding the Algorithms course.
    ///
    /// The Atlas is three times the size of the Academy and its steps are
    /// rewarded separately, so anything that means "how much Rust has been
    /// taught" has to ask for this number rather than for `lessonCount`.
    static let academyLessonCount: Int = courses
        .filter { $0.theme != .algorithms }
        .flatMap(\.units)
        .flatMap(\.lessons)
        .count

    private static func units(_ ids: String...) -> [RustLearningUnit] {
        RustLearningPath.units.filter { ids.contains($0.id) }
    }

    private static let interviewUnits = [
        RustLearningUnit(
            id: "interview-language",
            level: 1,
            title: "Core Rust Questions",
            subtitle: "Answer with a model, not memorized jargon",
            lessons: [
                RustLesson(id: "q-ownership", title: "Explain Ownership", concept: "Moves, Copy, Drop, and scope", minutes: 8, exercise: .planned),
                RustLesson(id: "q-borrowing", title: "Why Borrowing Works", concept: "Aliasing and mutation rules", minutes: 9, exercise: .borrowDiagnostic),
                RustLesson(id: "q-lifetimes", title: "Lifetime Reasoning", concept: "Relationships, not object duration", minutes: 10, exercise: .planned),
                RustLesson(id: "q-option-result", title: "Option vs Result", concept: "Absence, failure, and propagation", minutes: 8, exercise: .planned),
            ]
        ),
        RustLearningUnit(
            id: "interview-systems",
            level: 2,
            title: "Systems Design Questions",
            subtitle: "Show how Rust's guarantees affect architecture",
            lessons: [
                RustLesson(id: "q-send-sync", title: "Send and Sync", concept: "Thread-safety marker traits", minutes: 11, exercise: .planned),
                RustLesson(id: "q-box-rc-arc", title: "Box, Rc, and Arc", concept: "Ownership and allocation choices", minutes: 12, exercise: .planned),
                RustLesson(id: "q-dyn-generics", title: "dyn Trait vs Generics", concept: "Dispatch and code size tradeoffs", minutes: 11, exercise: .planned),
                RustLesson(id: "q-unsafe", title: "Reasoning About unsafe", concept: "Sound abstractions and invariants", minutes: 12, exercise: .planned),
            ]
        ),
        RustLearningUnit(
            id: "interview-concurrency",
            level: 3,
            title: "Concurrency in Depth",
            subtitle: "The follow-up questions after Send and Sync",
            lessons: [
                RustLesson(id: "q-atomics", title: "Atomics and Ordering", concept: "Relaxed, Acquire/Release, SeqCst", minutes: 13, exercise: .planned),
                RustLesson(id: "q-deadlock", title: "Deadlocks", concept: "What the borrow checker does not prevent", minutes: 10, exercise: .planned),
                RustLesson(id: "q-channels-vs-mutex", title: "Channels vs Mutex", concept: "Moving ownership or sharing it", minutes: 10, exercise: .planned),
                RustLesson(id: "q-async-vs-threads", title: "Async vs Threads", concept: "Waiting versus computing", minutes: 11, exercise: .planned),
                RustLesson(id: "q-blocking-async", title: "Blocking an Executor", concept: "Why one sync call stalls a runtime", minutes: 10, exercise: .planned),
                RustLesson(id: "q-cancellation", title: "Cancellation Safety", concept: "Dropping a future mid-await", minutes: 12, exercise: .planned),
            ]
        ),
        RustLearningUnit(
            id: "interview-platform",
            level: 4,
            title: "Systems and Networking",
            subtitle: "The layer under your Rust service, which interviews always reach",
            lessons: [
                RustLesson(id: "q-stack-heap", title: "Stack and Heap", concept: "Where values live and what a move copies", minutes: 9, exercise: .planned),
                RustLesson(id: "q-virtual-memory", title: "Virtual Memory", concept: "Pages, faults, and resident size", minutes: 11, exercise: .planned),
                RustLesson(id: "q-syscalls", title: "Syscalls and Buffering", concept: "Where the cost of IO actually is", minutes: 10, exercise: .planned),
                RustLesson(id: "q-tcp-udp", title: "TCP vs UDP", concept: "Streams, datagrams, and trade-offs", minutes: 9, exercise: .planned),
                RustLesson(id: "q-http-versions", title: "HTTP/1.1, 2, and 3", concept: "Head-of-line blocking per layer", minutes: 10, exercise: .planned),
                RustLesson(id: "q-tls", title: "What TLS Guarantees", concept: "Identity, confidentiality, integrity", minutes: 11, exercise: .planned),
                RustLesson(id: "q-backpressure", title: "Backpressure", concept: "Bounded queues and load shedding", minutes: 10, exercise: .planned),
            ]
        ),
        RustLearningUnit(
            id: "interview-data",
            level: 5,
            title: "Data and Distributed Systems",
            subtitle: "The half of a backend interview that is not the language",
            lessons: [
                RustLesson(id: "q-acid", title: "Transactions and Isolation", concept: "Which anomaly each level allows", minutes: 12, exercise: .planned),
                RustLesson(id: "q-indexes", title: "Indexes and B-trees", concept: "Leftmost prefix and write cost", minutes: 11, exercise: .planned),
                RustLesson(id: "q-cap", title: "CAP in Practice", concept: "What happens during a partition", minutes: 11, exercise: .planned),
                RustLesson(id: "q-idempotency", title: "Idempotency and Retries", concept: "Making at-least-once safe", minutes: 10, exercise: .planned),
                RustLesson(id: "q-caching", title: "Caching and Invalidation", concept: "Staleness budgets and stampedes", minutes: 11, exercise: .planned),
            ]
        ),
        RustLearningUnit(
            id: "interview-craft",
            level: 6,
            title: "Engineering Craft",
            subtitle: "How you work, which is the part every panel scores",
            lessons: [
                RustLesson(id: "q-complexity", title: "Complexity in Practice", concept: "Constants, cache, and amortised cost", minutes: 10, exercise: .planned),
                RustLesson(id: "q-hashmap", title: "Hashing and Collisions", concept: "Why Rust seeds its hasher", minutes: 10, exercise: .planned),
                RustLesson(id: "q-testing-strategy", title: "Choosing a Test", concept: "Unit, property, fuzz, integration", minutes: 11, exercise: .planned),
                RustLesson(id: "q-api-design", title: "API Design and Semver", concept: "Making misuse impossible to express", minutes: 12, exercise: .planned),
                RustLesson(id: "q-perf-profiling", title: "Profiling First", concept: "Measure, change one thing, measure", minutes: 10, exercise: .planned),
                RustLesson(id: "q-ffi-abi", title: "FFI and ABI", concept: "Ownership across the C boundary", minutes: 13, exercise: .planned),
            ]
        ),
    ]
}
