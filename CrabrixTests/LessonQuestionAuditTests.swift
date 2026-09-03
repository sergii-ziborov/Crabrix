import XCTest
@testable import Crabrix

/// A report on the quick-check questions, not a gate.
///
/// Two complaints from a device session drive it: some questions are guessable
/// without knowing any Rust, and some cannot be answered from what the lesson
/// itself says. Both are content defects that structural tests never saw, so
/// this prints them per lesson and leaves fixing to the catalogue.
final class LessonQuestionAuditTests: XCTestCase {
    private struct Finding {
        let lessonID: String
        let detail: String
    }

    func testAuditQuickCheckQuestions() throws {
        let lessons = RustCourseCatalog.courses
            .flatMap(\.units)
            .flatMap(\.lessons)
            // The Atlas has its own generated writing and its own verifier.
            .filter { AlgorithmCourseCatalog.pattern(forLessonID: $0.id) == nil }

        var jokeDistractors: [Finding] = []
        var longestIsCorrect: [Finding] = []
        var unanswerable: [Finding] = []
        var shortQuestions: [Finding] = []
        var duplicateQuestions: [Finding] = []
        var seenQuestions: [String: String] = [:]

        // Phrases that make an option obviously wrong to anyone, so the
        // question stops testing the lesson and starts testing reading.
        let tells = [
            "loudly", "add unsafe", "ignore the warning", "magic", "by accident",
            "randomly", "nothing happens", "it can fail",
        ]

        for lesson in lessons {
            guard let writing = RustLessonLibrary.writing(for: lesson.id) else {
                XCTFail("missing writing for \(lesson.id)")
                continue
            }
            let correct = writing.answers[writing.correctAnswer]

            for answer in writing.answers where answer != correct {
                let lowered = answer.lowercased()
                if let tell = tells.first(where: { lowered.contains($0) }) {
                    jokeDistractors.append(
                        Finding(lessonID: lesson.id, detail: "“\(answer)” — tell: \(tell)")
                    )
                }
            }

            if writing.answers.allSatisfy({ $0 == correct || $0.count < correct.count }) {
                longestIsCorrect.append(
                    Finding(lessonID: lesson.id, detail: "correct answer is the longest option")
                )
            }

            if writing.question.count < 24 {
                shortQuestions.append(
                    Finding(lessonID: lesson.id, detail: "“\(writing.question)”")
                )
            }

            if let other = seenQuestions[writing.question] {
                duplicateQuestions.append(
                    Finding(lessonID: lesson.id, detail: "same question as \(other)")
                )
            } else {
                seenQuestions[writing.question] = lesson.id
            }

            // Everything the learner has read by the time the question appears.
            let material = [
                writing.summary, writing.explanation, writing.rule,
                writing.exampleCaption, writing.exampleCode, writing.task,
                writing.practiceCode, writing.question,
            ].joined(separator: " ").lowercased()
            let keywords = Self.keywords(of: correct)
            let covered = keywords.filter { material.contains($0) }
            if !keywords.isEmpty, covered.isEmpty {
                unanswerable.append(
                    Finding(
                        lessonID: lesson.id,
                        detail: "nothing in the lesson mentions \(keywords.sorted().joined(separator: ", "))"
                    )
                )
            }
        }

        func report(_ title: String, _ findings: [Finding], limit: Int = 12) {
            print("\n=== \(title): \(findings.count)")
            for finding in findings.prefix(limit) {
                print("  \(finding.lessonID): \(finding.detail)")
            }
            if findings.count > limit { print("  … \(findings.count - limit) more") }
        }

        print("\n### QUICK CHECK AUDIT over \(lessons.count) language lessons")
        report("Joke distractors", jokeDistractors)
        report("Correct answer is the longest option", longestIsCorrect)
        report("Answer not derivable from the lesson", unanswerable)
        report("Question too short to be specific", shortQuestions)
        report("Duplicate questions", duplicateQuestions)
    }

    /// Content words worth looking for, ignoring the filler that appears in
    /// every sentence.
    private static func keywords(of answer: String) -> Set<String> {
        let stopWords: Set<String> = [
            "the", "and", "that", "with", "from", "into", "before", "after",
            "while", "when", "which", "must", "then", "this", "they", "them",
            "have", "only", "each", "same", "does", "your", "value", "values",
            "code", "compiler", "rust", "type", "types", "because", "there",
            "cannot", "would", "could", "still", "every", "other", "another",
        ]
        return Set(
            answer.lowercased()
                .split(whereSeparator: { !$0.isLetter })
                .map(String.init)
                .filter { $0.count >= 5 && !stopWords.contains($0) }
        )
    }
}
