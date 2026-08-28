import Foundation

struct RustLearningUnit: Identifiable, Sendable {
    let id: String
    let level: Int
    let title: String
    let subtitle: String
    let lessons: [RustLesson]
}

struct RustLesson: Identifiable, Sendable {
    enum Exercise: Sendable {
        case runnable
        case borrowDiagnostic
        case multiFile
        case planned
    }

    let id: String
    let title: String
    let concept: String
    let minutes: Int
    let exercise: Exercise
}

extension RustLesson {
    var hasCompilerLab: Bool {
        if case .planned = exercise { return false }
        return true
    }
}

enum RustLearningPath {
    static let units: [RustLearningUnit] = [
        RustLearningUnit(
            id: "foundations",
            level: 1,
            title: "Rust Foundations",
            subtitle: "Read, edit, compile, and trust rustc",
            lessons: [
                RustLesson(id: "hello-rust", title: "Hello, Rust", concept: "Functions and stdout", minutes: 4, exercise: .runnable),
                RustLesson(id: "variables", title: "Variables", concept: "let, mut, and shadowing", minutes: 6, exercise: .planned),
                RustLesson(id: "types", title: "Types", concept: "Scalars, tuples, and arrays", minutes: 7, exercise: .planned),
                RustLesson(id: "operators", title: "Operators & Casting", concept: "Arithmetic, overflow, and as", minutes: 7, exercise: .planned),
                RustLesson(id: "functions", title: "Functions", concept: "Parameters, returns, and expressions", minutes: 7, exercise: .planned),
                RustLesson(id: "control-flow", title: "Control Flow", concept: "if, loop, while, and for", minutes: 8, exercise: .planned),
                RustLesson(id: "comments-docs", title: "Comments & Docs", concept: "/// doc comments and examples", minutes: 5, exercise: .planned),
            ]
        ),
        RustLearningUnit(
            id: "ownership",
            level: 2,
            title: "Ownership & Borrowing",
            subtitle: "The ideas that make Rust different",
            lessons: [
                RustLesson(id: "ownership", title: "Ownership", concept: "Moves and scope", minutes: 8, exercise: .planned),
                RustLesson(id: "borrowing", title: "Borrowing", concept: "References and E0502", minutes: 9, exercise: .borrowDiagnostic),
                RustLesson(id: "slices", title: "Slices", concept: "Borrowed views into data", minutes: 8, exercise: .planned),
                RustLesson(id: "copy-clone", title: "Copy & Clone", concept: "When a value duplicates instead of moving", minutes: 8, exercise: .planned),
                RustLesson(id: "drop-order", title: "Drop & Scope", concept: "Deterministic cleanup without a GC", minutes: 8, exercise: .planned),
                RustLesson(id: "lifetimes-intro", title: "Lifetime Intuition", concept: "Why references stay valid", minutes: 10, exercise: .planned),
            ]
        ),
        RustLearningUnit(
            id: "modeling",
            level: 3,
            title: "Modeling Data",
            subtitle: "Make invalid states harder to express",
            lessons: [
                RustLesson(id: "structs", title: "Structs", concept: "Named data and methods", minutes: 8, exercise: .planned),
                RustLesson(id: "enums", title: "Enums & Match", concept: "Variants and exhaustive handling", minutes: 10, exercise: .planned),
                RustLesson(id: "option-result", title: "Option & Result", concept: "Explicit absence and failure", minutes: 10, exercise: .planned),
                RustLesson(id: "collections", title: "Collections", concept: "Vec, String, and HashMap", minutes: 9, exercise: .planned),
                RustLesson(id: "strings", title: "Strings & UTF-8", concept: "String, &str, chars, and bytes", minutes: 10, exercise: .planned),
                RustLesson(id: "pattern-matching", title: "Pattern Matching", concept: "Destructuring, guards, and bindings", minutes: 11, exercise: .planned),
                RustLesson(id: "derive", title: "Derive Macros", concept: "Debug, Clone, PartialEq, and Default", minutes: 8, exercise: .planned),
            ]
        ),
        RustLearningUnit(
            id: "abstraction",
            level: 4,
            title: "Rust Abstractions",
            subtitle: "Reuse without hiding the cost",
            lessons: [
                RustLesson(id: "generics", title: "Generics", concept: "Reusable types and functions", minutes: 10, exercise: .planned),
                RustLesson(id: "traits", title: "Traits", concept: "Shared behavior and bounds", minutes: 11, exercise: .planned),
                RustLesson(id: "lifetimes", title: "Lifetimes", concept: "Relationships between borrows", minutes: 12, exercise: .planned),
                RustLesson(id: "closures", title: "Closures", concept: "Fn, FnMut, FnOnce, and capture", minutes: 11, exercise: .planned),
                RustLesson(id: "iterators", title: "Iterators", concept: "Lazy transformations", minutes: 11, exercise: .planned),
                RustLesson(id: "iterator-impl", title: "Writing an Iterator", concept: "impl Iterator and the next method", minutes: 11, exercise: .planned),
                RustLesson(id: "associated-types", title: "Associated Types", concept: "One output type per implementation", minutes: 11, exercise: .planned),
                RustLesson(id: "operator-traits", title: "Operator Traits", concept: "Add, Display, From, and Into", minutes: 11, exercise: .planned),
            ]
        ),
        RustLearningUnit(
            id: "projects",
            level: 5,
            title: "Real Projects",
            subtitle: "Cargo-shaped code beyond one file",
            lessons: [
                RustLesson(id: "modules", title: "Modules", concept: "Cargo.toml and sibling files", minutes: 9, exercise: .multiFile),
                RustLesson(id: "testing", title: "Testing", concept: "Unit and integration tests", minutes: 10, exercise: .planned),
                RustLesson(id: "errors", title: "Error Design", concept: "Propagation and custom errors", minutes: 11, exercise: .planned),
                RustLesson(id: "dependencies", title: "Dependencies", concept: "crates.io, SemVer, and features", minutes: 10, exercise: .planned),
                RustLesson(id: "workspaces", title: "Workspaces", concept: "Many crates, one lockfile", minutes: 9, exercise: .planned),
            ]
        ),
        RustLearningUnit(
            id: "pointers",
            level: 6,
            title: "Smart Pointers",
            subtitle: "Ownership shapes beyond a plain value",
            lessons: [
                RustLesson(id: "box", title: "Box<T>", concept: "Heap allocation and recursive types", minutes: 9, exercise: .planned),
                RustLesson(id: "rc-refcell", title: "Rc & RefCell", concept: "Shared ownership and interior mutability", minutes: 12, exercise: .planned),
                RustLesson(id: "deref-drop", title: "Deref & Drop", concept: "Making a type behave like a reference", minutes: 10, exercise: .planned),
                RustLesson(id: "cycles", title: "Reference Cycles", concept: "Weak<T> and leaks Rust cannot prevent", minutes: 11, exercise: .planned),
            ]
        ),
        RustLearningUnit(
            id: "threads",
            level: 7,
            title: "Fearless Concurrency",
            subtitle: "Share data across threads without data races",
            lessons: [
                RustLesson(id: "concurrency", title: "Threads", concept: "spawn, join, and move closures", minutes: 11, exercise: .planned),
                RustLesson(id: "channels", title: "Channels", concept: "Message passing with mpsc", minutes: 11, exercise: .planned),
                RustLesson(id: "shared-state", title: "Shared State", concept: "Mutex, RwLock, and Arc", minutes: 12, exercise: .planned),
                RustLesson(id: "send-sync", title: "Send & Sync", concept: "The traits behind thread safety", minutes: 11, exercise: .planned),
            ]
        ),
        RustLearningUnit(
            id: "async",
            level: 8,
            title: "Async Rust",
            subtitle: "Concurrency without a thread per task",
            lessons: [
                RustLesson(id: "futures", title: "Futures", concept: "async fn, await, and laziness", minutes: 12, exercise: .planned),
                RustLesson(id: "async-runtime", title: "Runtimes", concept: "Why async needs an executor", minutes: 11, exercise: .planned),
                RustLesson(id: "async-patterns", title: "Async Patterns", concept: "join, select, and cancellation", minutes: 12, exercise: .planned),
            ]
        ),
        RustLearningUnit(
            id: "meta",
            level: 9,
            title: "Macros & Metaprogramming",
            subtitle: "Code that writes code, checked by the compiler",
            lessons: [
                RustLesson(id: "declarative-macros", title: "macro_rules!", concept: "Pattern-based code generation", minutes: 12, exercise: .planned),
                RustLesson(id: "proc-macros", title: "Procedural Macros", concept: "Derive, attribute, and function macros", minutes: 12, exercise: .planned),
                RustLesson(id: "cfg-features", title: "cfg & Features", concept: "Compiling different code per target", minutes: 10, exercise: .planned),
            ]
        ),
        RustLearningUnit(
            id: "systems",
            level: 10,
            title: "Systems Rust",
            subtitle: "The unchecked edges, handled carefully",
            lessons: [
                RustLesson(id: "unsafe", title: "unsafe Rust", concept: "Five powers and their invariants", minutes: 13, exercise: .planned),
                RustLesson(id: "ffi", title: "FFI", concept: "extern \"C\", repr(C), and raw pointers", minutes: 13, exercise: .planned),
                RustLesson(id: "performance", title: "Performance", concept: "Allocation, iterators, and measuring", minutes: 12, exercise: .planned),
                RustLesson(id: "idioms", title: "Rust Idioms", concept: "Newtype, builder, and typestate", minutes: 11, exercise: .planned),
            ]
        ),
    ]
}
