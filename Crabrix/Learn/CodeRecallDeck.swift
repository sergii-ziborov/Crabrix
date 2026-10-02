import Foundation

/// One snippet to memorise, derived from a lesson.
struct CodeRecallSnippet: Identifiable, Equatable, Sendable {
    /// The lesson id, which doubles as the mastery topic.
    let topic: String
    let title: String
    /// Trimmed, non-empty, unique lines in their correct order.
    let lines: [String]

    var id: String { topic }

    /// A round only uses a window of the snippet, which is how difficulty grows.
    func window(size: Int) -> [String] {
        Array(lines.prefix(max(2, min(size, lines.count))))
    }
}

/// Builds Code Recall rounds from installed CourseRepository snippets.
/// The frozen pre-CoursePack list below exists only for exporter parity tests.
enum CodeRecallDeck {
    /// The shortest and longest snippets a round can use.
    static let minimumLines = 3
    static let maximumLines = 8

#if DEBUG || CRABRIX_LEGACY_FIXTURES
    static let all: [CodeRecallSnippet] = {
        RustCourseCatalog.courses
            .flatMap { $0.units.flatMap(\.lessons) }
            .compactMap { lesson -> CodeRecallSnippet? in
                guard let writing = RustLessonLibrary.writing(for: lesson.id) else { return nil }
                let lines = usableLines(from: writing.exampleCode)
                guard lines.count >= minimumLines else { return nil }
                return CodeRecallSnippet(
                    topic: lesson.id,
                    title: lesson.title,
                    lines: Array(lines.prefix(maximumLines))
                )
            }
    }()
#endif

    /// Lines worth showing: no blanks, and no repeats — a repeated line would
    /// make the correct order ambiguous and the round unfair.
    static func usableLines(from code: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in code.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, seen.insert(line).inserted else { continue }
            result.append(line)
        }
        return result
    }

#if DEBUG || CRABRIX_LEGACY_FIXTURES
    static func snippet(topic: String) -> CodeRecallSnippet? {
        all.first { $0.topic == topic }
    }
#endif

    /// Picks the next snippet, favouring the topics the learner is weakest at.
#if DEBUG || CRABRIX_LEGACY_FIXTURES
    static func next(
        records: [String: TopicMasteryRecord],
        excluding used: Set<String> = [],
        now: Date = Date(),
        using generator: inout some RandomNumberGenerator
    ) -> CodeRecallSnippet? {
        next(from: all, records: records, excluding: used,
             now: now, using: &generator)
    }
#endif

    static func next(
        from snippets: [CodeRecallSnippet],
        records: [String: TopicMasteryRecord],
        excluding used: Set<String> = [],
        now: Date = Date(),
        using generator: inout some RandomNumberGenerator
    ) -> CodeRecallSnippet? {
        let pool = snippets.filter { !used.contains($0.topic) }
        let candidates = pool.isEmpty ? snippets : pool
        guard !candidates.isEmpty else { return nil }
        let picked = TopicScheduler.pick(
            count: 1,
            from: candidates.map(\.topic),
            records: records,
            now: now,
            using: &generator
        )
        guard let topic = picked.first else { return candidates.first }
        return candidates.first { $0.topic == topic }
    }

#if DEBUG || CRABRIX_LEGACY_FIXTURES
    static func next(
        records: [String: TopicMasteryRecord],
        excluding used: Set<String> = [],
        now: Date = Date()
    ) -> CodeRecallSnippet? {
        var generator = SystemRandomNumberGenerator()
        return next(from: all, records: records, excluding: used,
                    now: now, using: &generator)
    }
#endif

    static func next(
        from snippets: [CodeRecallSnippet],
        records: [String: TopicMasteryRecord],
        excluding used: Set<String> = [],
        now: Date = Date()
    ) -> CodeRecallSnippet? {
        var generator = SystemRandomNumberGenerator()
        return next(from: snippets, records: records, excluding: used,
                    now: now, using: &generator)
    }
}

/// One Code Recall run, scored on how far the learner got.
struct CodeRecallRunResult: Equatable, Sendable {
    /// Longest window rebuilt correctly.
    let bestLevel: Int
    let roundsCleared: Int
    let linesRecalled: Int

    var progressEvent: CrabrixProgressEvent {
        .codeRecallFinished(bestLevel: bestLevel, linesRecalled: linesRecalled)
    }
}
