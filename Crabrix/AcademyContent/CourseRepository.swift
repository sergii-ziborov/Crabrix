import Foundation

/// The Academy UI can depend on this instead of static Swift content catalogs.
/// Repositories are immutable snapshots; updates create a new snapshot while an
/// open CourseSession continues to retain its old version.
protocol CourseRepository: Sendable {
    var courses: [RustCourse] { get }
    func writing(for lessonID: String) -> RustLessonWriting?
    func depth(for lessonID: String) -> RustLessonDepth?
    func evidence(for lessonID: String) -> LessonEvidence?
    func starterProject(for lessonID: String) -> CourseProjectTemplate?
    func challenge(for lessonID: String) -> AlgorithmChallenge?
    func termPairs() -> [CourseTermPairDTO]
}

extension CourseRepository {
    func course(id: String) -> RustCourse? {
        courses.first { $0.id == id }
    }

    func course(containing lessonID: String) -> RustCourse? {
        courses.first { course in
            course.units.contains { unit in unit.lessons.contains { $0.id == lessonID } }
        }
    }

    func lesson(id: String) -> RustLesson? {
        courses.lazy.flatMap(\.units).flatMap(\.lessons).first { $0.id == id }
    }

    /// Practice sessions snapshot these values at launch, so a course update
    /// cannot change an answer or snippet in the middle of a round.
    func practiceQuestions() -> [RustQuestion] {
        courses
            .filter { $0.id != "algorithms" }
            .flatMap { $0.units.flatMap(\.lessons) }
            .compactMap { lesson -> RustQuestion? in
                guard let writing = writing(for: lesson.id) else { return nil }
                return RustQuestion(
                    topic: lesson.id,
                    lessonTitle: lesson.title,
                    prompt: writing.question,
                    code: writing.practiceCode,
                    answers: writing.answers,
                    correctAnswer: writing.correctAnswer,
                    feedback: writing.feedback
                )
            }
            .filter(\.isWellFormed)
    }

    func recallSnippets() -> [CodeRecallSnippet] {
        courses.flatMap { $0.units.flatMap(\.lessons) }
            .compactMap { lesson -> CodeRecallSnippet? in
                guard let writing = writing(for: lesson.id) else { return nil }
                let lines = CodeRecallDeck.usableLines(from: writing.exampleCode)
                guard lines.count >= CodeRecallDeck.minimumLines else { return nil }
                return CodeRecallSnippet(
                    topic: lesson.id,
                    title: lesson.title,
                    lines: Array(lines.prefix(CodeRecallDeck.maximumLines))
                )
            }
    }

    func trainableTermPairs() -> [TermTrainPair] {
        // Term Train is the Rust drill. Atlas has its own progression, so its
        // term cards stay in the installed pack but do not enter this deck.
        let rustLessonIDs = Set(courses.filter { $0.id != "algorithms" }
            .flatMap { $0.units.flatMap(\.lessons) }.map(\.id))
        return termPairs().filter { rustLessonIDs.contains($0.topic) }.map {
            TermTrainPair(id: $0.id, term: $0.term,
                          description: $0.description, topic: $0.topic)
        }
    }
}

struct LoadedCourse: Sendable {
    let course: RustCourse
    let order: Int
    let writing: [String: RustLessonWriting]
    let depth: [String: RustLessonDepth]
    let evidence: [String: LessonEvidence]
    let projects: [String: CourseProjectTemplate]
    let challenges: [String: AlgorithmChallenge]
    let terms: [CourseTermPairDTO]
    let contentVersion: String
    let archiveSHA256: String
}
