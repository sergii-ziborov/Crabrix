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

/// The deck for Code Recall, built from lesson example code.
///
/// Nothing is hand-written here: adding a lesson adds a snippet, in the same way
/// adding a lesson adds a question. The game cannot drift from the curriculum.
enum CodeRecallDeck {
    /// The shortest and longest snippets a round can use.
    static let minimumLines = 3
    static let maximumLines = 8

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

    static func snippet(topic: String) -> CodeRecallSnippet? {
        all.first { $0.topic == topic }
    }

    /// Picks the next snippet, favouring the topics the learner is weakest at.
    static func next(
        records: [String: TopicMasteryRecord],
        excluding used: Set<String> = [],
        now: Date = Date(),
        using generator: inout some RandomNumberGenerator
    ) -> CodeRecallSnippet? {
        let pool = all.filter { !used.contains($0.topic) }
        let candidates = pool.isEmpty ? all : pool
        guard !candidates.isEmpty else { return nil }
        let picked = TopicScheduler.pick(
            count: 1,
            from: candidates.map(\.topic),
            records: records,
            now: now,
            using: &generator
        )
        guard let topic = picked.first else { return candidates.first }
        return snippet(topic: topic)
    }

    static func next(
        records: [String: TopicMasteryRecord],
        excluding used: Set<String> = [],
        now: Date = Date()
    ) -> CodeRecallSnippet? {
        var generator = SystemRandomNumberGenerator()
        return next(records: records, excluding: used, now: now, using: &generator)
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
