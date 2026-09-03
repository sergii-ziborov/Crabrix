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
            // Only the API the answer names. English wording differs between
            // an answer and an explanation all the time; a method or type the
            // lesson never shows is a real hole.
            let apiTerms = Self.apiTerms(of: correct)
            let missing = apiTerms.filter { !material.contains($0.lowercased()) }
            if !missing.isEmpty {
                unanswerable.append(
                    Finding(
                        lessonID: lesson.id,
                        detail: "answer names \(missing.sorted().joined(separator: ", ")), "
                            + "which the lesson never shows"
                    )
                )
            }
        }

        func report(_ title: String, _ findings: [Finding], limit: Int = 200) {
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

    /// The Rust the answer actually names: `entry()`, `clone`, `PhantomData`,
    /// `cargo`. Plain prose is deliberately ignored — an answer may say
    /// "looks the key up once" while the lesson says "one lookup", and that is
    /// writing, not a gap.
    private static func apiTerms(of answer: String) -> Set<String> {
        let words = answer.split(whereSeparator: { !$0.isLetter && $0 != "_" })
            .map(String.init)
        var terms: Set<String> = []
        for word in words {
            let isCall = answer.contains(word + "(")
            let isSnake = word.contains("_") && word.lowercased() == word
            let isTypeName = word.count > 2
                && word.first?.isUppercase == true
                && word.dropFirst().contains(where: \.isUppercase)
            let isToolOrMethod = Self.knownRustTerms.contains(word)
            if isCall || isSnake || isTypeName || isToolOrMethod {
                terms.insert(word)
            }
        }
        return terms
    }

    /// Names a learner cannot guess: if the answer depends on one and the
    /// lesson never shows it, the question is unanswerable from the page.
    ///
    /// Matched case-sensitively and kept to concrete API. Words like `drop`,
    /// `lifetime` or `trait` also exist in ordinary English — "drop the clone",
    /// "tied to the input's lifetime" — and flagging those produced noise
    /// rather than gaps.
    private static let knownRustTerms: Set<String> = [
        "Box", "Mutex", "RwLock", "Arc", "Rc", "Weak", "RefCell", "Cell",
        "Cow", "Vec", "HashMap", "BTreeMap", "Pin", "PhantomData", "Result",
        "cargo", "clone", "rustc", "clippy",
    ]
}
