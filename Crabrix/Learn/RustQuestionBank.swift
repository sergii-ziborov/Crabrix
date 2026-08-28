import Foundation

/// One multiple-choice question, tied to the lesson it came from.
struct RustQuestion: Identifiable, Sendable, Equatable {
    /// The lesson id, which doubles as the mastery topic.
    let topic: String
    let lessonTitle: String
    let prompt: String
    /// The snippet the prompt refers to. Quick Practice shows a question with
    /// no surrounding lesson, so "why is that rejected?" only means something
    /// when the code it is asking about travels with it.
    let code: String
    let answers: [String]
    let correctAnswer: Int
    let feedback: String

    var id: String { topic }

    var isWellFormed: Bool {
        !prompt.isEmpty
            && !code.isEmpty
            && answers.count >= 2
            && answers.indices.contains(correctAnswer)
            && Set(answers).count == answers.count
    }
}

/// Every question in the app, derived from the curriculum.
///
/// Quick Practice does not keep its own list: adding a lesson with written
/// content adds a question here automatically, so the two can never drift apart.
enum RustQuestionBank {
    static let all: [RustQuestion] = {
        RustCourseCatalog.courses
            .flatMap { $0.units.flatMap(\.lessons) }
            .compactMap { lesson in
                guard let writing = RustLessonLibrary.writing(for: lesson.id) else { return nil }
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
    }()

    static var topics: [String] { all.map(\.topic) }

    static func question(for topic: String) -> RustQuestion? {
        all.first { $0.topic == topic }
    }

    /// A practice round, weighted towards what the learner is weakest at.
    static func round(
        count: Int,
        records: [String: TopicMasteryRecord],
        now: Date = Date()
    ) -> [RustQuestion] {
        let picked = TopicScheduler.pick(
            count: count,
            from: topics,
            records: records,
            now: now
        )
        return picked.compactMap(question(for:))
    }

    /// Deterministic variant, for tests.
    static func round(
        count: Int,
        records: [String: TopicMasteryRecord],
        now: Date = Date(),
        using generator: inout some RandomNumberGenerator
    ) -> [RustQuestion] {
        TopicScheduler
            .pick(count: count, from: topics, records: records, now: now, using: &generator)
            .compactMap(question(for:))
    }
}
