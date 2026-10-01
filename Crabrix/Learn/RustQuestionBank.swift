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

/// Schedules a round from questions supplied by the installed CourseRepository.
/// The frozen pre-CoursePack list below exists only for exporter parity tests.
enum RustQuestionBank {
#if DEBUG || CRABRIX_LEGACY_FIXTURES
    static let all: [RustQuestion] = {
        RustCourseCatalog.courses
            // Algorithms has its own 600-step progression. Mixing all of those
            // questions into the general Rust drill would drown out the
            // language curriculum instead of reinforcing it.
            .filter { $0.id != "algorithms" }
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
        round(count: count, from: all, records: records, now: now)
    }
#endif

    static func round(
        count: Int,
        from questions: [RustQuestion],
        records: [String: TopicMasteryRecord],
        now: Date = Date()
    ) -> [RustQuestion] {
        let picked = TopicScheduler.pick(
            count: count,
            from: questions.map(\.topic),
            records: records,
            now: now
        )
        let byTopic = Dictionary(uniqueKeysWithValues: questions.map { ($0.topic, $0) })
        return picked.compactMap { byTopic[$0] }
    }

    /// Deterministic variant, for tests.
#if DEBUG || CRABRIX_LEGACY_FIXTURES
    static func round(
        count: Int,
        records: [String: TopicMasteryRecord],
        now: Date = Date(),
        using generator: inout some RandomNumberGenerator
    ) -> [RustQuestion] {
        round(count: count, from: all, records: records, now: now, using: &generator)
    }
#endif

    static func round(
        count: Int,
        from questions: [RustQuestion],
        records: [String: TopicMasteryRecord],
        now: Date = Date(),
        using generator: inout some RandomNumberGenerator
    ) -> [RustQuestion] {
        let byTopic = Dictionary(uniqueKeysWithValues: questions.map { ($0.topic, $0) })
        return TopicScheduler
            .pick(count: count, from: questions.map(\.topic), records: records,
                  now: now, using: &generator)
            .compactMap { byTopic[$0] }
    }
}
