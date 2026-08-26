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
                RustLesson(id: "control-flow", title: "Control Flow", concept: "if, loop, while, and for", minutes: 8, exercise: .planned),
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
                RustLesson(id: "iterators", title: "Iterators & Closures", concept: "Lazy transformations", minutes: 11, exercise: .planned),
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
                RustLesson(id: "concurrency", title: "Concurrency", concept: "Send, Sync, and threads", minutes: 13, exercise: .planned),
            ]
        ),
    ]
}
