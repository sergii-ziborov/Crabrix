import Foundation

struct RustCourse: Identifiable, Sendable {
    let id: String
    let level: String
    let title: String
    let subtitle: String
    let systemImage: String
    let units: [RustLearningUnit]
}

enum RustCourseCatalog {
    static let courses: [RustCourse] = [
        RustCourse(
            id: "basics",
            level: "BEGINNER",
            title: "Rust Basics",
            subtitle: "Syntax, types, control flow, and your first compiled programs",
            systemImage: "leaf.fill",
            units: units("foundations", "modeling")
        ),
        RustCourse(
            id: "ownership",
            level: "INTERMEDIATE",
            title: "Ownership Mastery",
            subtitle: "Borrowing, lifetimes, traits, iterators, and compiler-guided repair",
            systemImage: "link.circle.fill",
            units: units("ownership", "abstraction")
        ),
        RustCourse(
            id: "projects",
            level: "ADVANCED",
            title: "Cargo & Real Projects",
            subtitle: "Modules, testing, error design, and concurrency",
            systemImage: "shippingbox.fill",
            units: units("projects")
        ),
        RustCourse(
            id: "interview",
            level: "CAREER",
            title: "Rust Interview Prep",
            subtitle: "Explain the hard ideas clearly and practice common interview questions",
            systemImage: "person.wave.2.fill",
            units: interviewUnits
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
    ]
}
