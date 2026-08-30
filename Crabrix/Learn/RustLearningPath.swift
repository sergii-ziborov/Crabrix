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
        case algorithmChallenge
        case planned
    }

    let id: String
    let title: String
    let concept: String
    let minutes: Int
    let exercise: Exercise
}

enum LessonOutputMatcher: Codable, Equatable, Sendable {
    case exact(String)
    case contains(String)
    case differsFrom(String)

    func matches(_ output: String) -> Bool {
        switch self {
        case let .exact(expected): output == expected
        case let .contains(fragment): output.contains(fragment)
        case let .differsFrom(starter): !output.isEmpty && output != starter
        }
    }
}

/// The proof a lesson requires. A successful process exit is only one input;
/// it is never, by itself, a universal lesson validator.
enum LessonEvidence: Equatable, Sendable {
    case compilerRun(
        expectedOutput: LessonOutputMatcher,
        requiresSourceChange: Bool,
        requiredFiles: [String]
    )
    case repair(
        removesDiagnostic: String,
        expectedOutput: LessonOutputMatcher,
        requiredSourceFragments: [String]
    )
    case algorithmChallenge(
        expectedOutput: LessonOutputMatcher,
        requiredSourceFragments: [String],
        forbiddenSourceFragments: [String]
    )
    case reasoning(correctAnswer: Int)
}

enum LessonAttemptResult: String, Codable, Equatable, Sendable {
    case passed
    case failed
}

/// Persisted evidence contains hashes and compiler facts, never the learner's
/// source code.
struct LessonAttemptEvidence: Codable, Equatable, Sendable {
    static let validatorVersion = "lesson-evidence-1"

    let lessonID: String
    let projectRevision: String
    let validatorVersion: String
    let compilerVersion: String?
    let result: LessonAttemptResult
    let diagnosticCodes: [String]
    let stdoutHash: String?
    let completedAt: Date
}

struct LessonEvidenceValidation: Equatable, Sendable {
    let passed: Bool
    let detail: String
}

enum LessonEvidenceValidator {
    static func validateCompilerAttempt(
        lesson: RustLesson,
        result: CompilationResult,
        project: CrabrixProject,
        initialSourceTreeHash: String?,
        currentSourceTreeHash: String,
        observedDiagnosticCodes: Set<String>
    ) -> LessonEvidenceValidation {
        guard result.succeeded, result.phase == .run else {
            return LessonEvidenceValidation(
                passed: false,
                detail: "Run the lesson project successfully to produce compiler evidence."
            )
        }

        switch lesson.evidence {
        case let .compilerRun(output, requiresSourceChange, requiredFiles):
            if requiresSourceChange, initialSourceTreeHash == currentSourceTreeHash {
                return LessonEvidenceValidation(
                    passed: false,
                    detail: "The starter project ran unchanged. Make the requested edit and run again."
                )
            }
            let missingFiles = requiredFiles.filter { project.files[$0] == nil }
            guard missingFiles.isEmpty else {
                return LessonEvidenceValidation(
                    passed: false,
                    detail: "Required lesson files are missing: \(missingFiles.joined(separator: ", "))."
                )
            }
            guard output.matches(result.stdout) else {
                return LessonEvidenceValidation(
                    passed: false,
                    detail: "The program ran, but stdout does not yet prove the requested behavior."
                )
            }
            return LessonEvidenceValidation(
                passed: true,
                detail: "The edited project compiled and its stdout matched this lesson's validator."
            )

        case let .repair(code, output, requiredFragments):
            guard observedDiagnosticCodes.contains(code) else {
                return LessonEvidenceValidation(
                    passed: false,
                    detail: "Reproduce \(code) first, then repair that exact diagnostic."
                )
            }
            guard !result.diagnostics.contains(where: { $0.code == code }) else {
                return LessonEvidenceValidation(
                    passed: false,
                    detail: "\(code) is still present."
                )
            }
            let allSource = project.files.keys.sorted().compactMap { project.files[$0] }
                .joined(separator: "\n")
            let missingFragments = requiredFragments.filter { !allSource.contains($0) }
            guard missingFragments.isEmpty else {
                return LessonEvidenceValidation(
                    passed: false,
                    detail: "The repair removed required behavior from the starter project."
                )
            }
            guard output.matches(result.stdout) else {
                return LessonEvidenceValidation(
                    passed: false,
                    detail: "The diagnostic is gone, but the expected behavior was not preserved."
                )
            }
            return LessonEvidenceValidation(
                passed: true,
                detail: "\(code) was reproduced, removed, and the expected behavior still ran."
            )

        case let .algorithmChallenge(output, requiredFragments, forbiddenFragments):
            guard initialSourceTreeHash != currentSourceTreeHash else {
                return LessonEvidenceValidation(
                    passed: false,
                    detail: "The starter algorithm is unchanged. Implement solve(), then run it again."
                )
            }
            let allSource = project.files.keys.sorted().compactMap { project.files[$0] }
                .joined(separator: "\n")
            let missingFragments = requiredFragments.filter { !allSource.contains($0) }
            guard missingFragments.isEmpty else {
                return LessonEvidenceValidation(
                    passed: false,
                    detail: "Keep the supplied solve() function and visible verification harness."
                )
            }
            let remainingPlaceholders = forbiddenFragments.filter { allSource.contains($0) }
            guard remainingPlaceholders.isEmpty else {
                return LessonEvidenceValidation(
                    passed: false,
                    detail: "Replace the starter todo! placeholder with your algorithm."
                )
            }
            guard output.matches(result.stdout) else {
                return LessonEvidenceValidation(
                    passed: false,
                    detail: "The program ran, but the visible algorithm case did not pass yet."
                )
            }
            return LessonEvidenceValidation(
                passed: true,
                detail: "rustc accepted the solution and the visible algorithm case passed."
            )

        case .reasoning:
            return LessonEvidenceValidation(
                passed: false,
                detail: "This lesson is completed by its explanation question, not by a generic Run."
            )
        }
    }
}

extension RustLesson {
    var hasCompilerLab: Bool {
        if case .planned = exercise { return false }
        return true
    }

    var evidence: LessonEvidence {
        switch exercise {
        case .runnable:
            .compilerRun(
                expectedOutput: .differsFrom("Hello, Crabrix!\n"),
                requiresSourceChange: true,
                requiredFiles: ["main.rs"]
            )
        case .borrowDiagnostic:
            .repair(
                removesDiagnostic: "E0502",
                expectedOutput: .contains("crab"),
                requiredSourceFragments: ["items.push(", "println!"]
            )
        case .multiFile:
            .compilerRun(
                expectedOutput: .differsFrom("hello from two Rust files\n"),
                requiresSourceChange: true,
                requiredFiles: ["Cargo.toml", "src/main.rs", "src/greeter.rs"]
            )
        case .algorithmChallenge:
            if let challenge = AlgorithmCourseCatalog.challenge(for: id) {
                .algorithmChallenge(
                    expectedOutput: .exact(challenge.expectedOutput),
                    requiredSourceFragments: challenge.requiredSourceFragments,
                    forbiddenSourceFragments: ["todo!(\"implement"]
                )
            } else {
                .reasoning(correctAnswer: RustLessonLibrary.writing(for: id)?.correctAnswer ?? 0)
            }
        case .planned:
            .reasoning(correctAnswer: RustLessonLibrary.writing(for: id)?.correctAnswer ?? 1)
        }
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
                RustLesson(id: "print-formatting", title: "Printing Values", concept: "Format strings and placeholders", minutes: 5, exercise: .planned),
                RustLesson(id: "number-types", title: "Numbers", concept: "Integer and floating-point types", minutes: 6, exercise: .planned),
                RustLesson(id: "booleans-comparisons", title: "Booleans", concept: "Comparisons and logical operators", minutes: 5, exercise: .planned),
                RustLesson(id: "chars-and-text", title: "Characters & Text", concept: "char, &str, and Unicode", minutes: 6, exercise: .planned),
                RustLesson(id: "compiler-feedback", title: "Reading rustc", concept: "Expected, found, spans, and help", minutes: 6, exercise: .planned),
            ]
        ),
    ] + RustBasicsExpansion.units + [
        RustLearningUnit(
            id: "ownership",
            level: 5,
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
            level: 4,
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
            level: 6,
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
            level: 7,
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
            level: 8,
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
            level: 9,
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
            level: 10,
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
            level: 11,
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
            level: 12,
            title: "Systems Rust",
            subtitle: "The unchecked edges, handled carefully",
            lessons: [
                RustLesson(id: "unsafe", title: "unsafe Rust", concept: "Five powers and their invariants", minutes: 13, exercise: .planned),
                RustLesson(id: "ffi", title: "FFI", concept: "extern \"C\", repr(C), and raw pointers", minutes: 13, exercise: .planned),
                RustLesson(id: "performance", title: "Performance", concept: "Allocation, iterators, and measuring", minutes: 12, exercise: .planned),
                RustLesson(id: "idioms", title: "Rust Idioms", concept: "Newtype, builder, and typestate", minutes: 11, exercise: .planned),
            ]
        ),
    ] + RustAdvancedExpansion.allUnits
}
