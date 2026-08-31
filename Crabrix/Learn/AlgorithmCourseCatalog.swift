import Foundation

enum AlgorithmDifficulty: String, CaseIterable, Sendable {
    case easy
    case medium
    case hard

    var title: String { rawValue.uppercased() }

    var lessonMinutes: Int {
        switch self {
        case .easy: 8
        case .medium: 11
        case .hard: 15
        }
    }
}

enum AlgorithmLessonStage: String, Sendable {
    case model
    case recognize
    case challenge
}

struct AlgorithmPattern: Identifiable, Sendable {
    let id: String
    let title: String
    let difficulty: AlgorithmDifficulty
    let categoryID: String
    let categoryTitle: String
    let idea: String
    let useCases: String
    let complexity: String
    let task: String
    let visibleInput: String
    let expectedAnswer: String
    let rustSketch: String

    var lessons: [RustLesson] {
        [
            lesson(stage: .model, title: "\(title): Mental Model", concept: idea),
            lesson(stage: .recognize, title: "\(title): When to Use It", concept: useCases),
            lesson(stage: .challenge, title: "Challenge: \(title)", concept: task),
        ]
    }

    func lessonID(_ stage: AlgorithmLessonStage) -> String {
        "algorithm.\(id).\(stage.rawValue)"
    }

    private func lesson(stage: AlgorithmLessonStage, title: String, concept: String) -> RustLesson {
        RustLesson(
            id: lessonID(stage),
            title: title,
            concept: concept,
            minutes: difficulty.lessonMinutes,
            exercise: stage == .challenge ? .algorithmChallenge : .planned
        )
    }
}

struct AlgorithmCategory: Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let achievementTitle: String
    let patterns: [AlgorithmPattern]
}

struct AlgorithmChallenge: Equatable, Sendable {
    let lessonID: String
    let patternID: String
    let projectName: String
    /// The only source the learner sees and edits. Test inputs and expected
    /// answers deliberately stay out of this file.
    let source: String
    /// App-private executable harness supplied to rustc at build time.
    let verificationSource: String
    /// One visible case plus private semantic and input-normalisation cases.
    /// These stay outside the editable project and are never printed on failure.
    let verificationCases: [AlgorithmVerificationCase]
    let expectedOutput: String
    let requiredSourceFragments: [String]
    let forbiddenSourceFragments: [String]
}

enum AlgorithmCourseCatalog {
    /// Stable, independent method families. `categories` remains as a
    /// compatibility name so saved progress and achievement IDs do not change
    /// when the learning hierarchy becomes method-first.
    static let categories: [AlgorithmCategory] = AlgorithmCourseData.categories
    static let methods: [AlgorithmCategory] = categories
    static let patterns: [AlgorithmPattern] = categories.flatMap(\.patterns)

    /// Mental-model and recognition steps across every pattern: what the Atlas
    /// asks a learner to read rather than to prove to the compiler.
    static let studyStepCount: Int = patterns.count * 2
    /// Compiler-verified challenges, one per pattern.
    static let challengeCount: Int = patterns.count

    static let units: [RustLearningUnit] = categories.enumerated().map { index, category in
        RustLearningUnit(
            id: "algorithms-\(category.id)",
            level: index + 1,
            title: category.title,
            subtitle: category.subtitle,
            lessons: category.patterns.flatMap(\.lessons)
        )
    }

    static let termPairs: [TermTrainPair] = patterns.map { pattern in
        TermTrainPair(
            id: "algorithm-term-\(pattern.id)",
            term: pattern.title,
            description: pattern.idea,
            topic: pattern.lessonID(.recognize)
        )
    }

    private static let lessonLookup: [String: (pattern: AlgorithmPattern, stage: AlgorithmLessonStage)] = {
        var result: [String: (AlgorithmPattern, AlgorithmLessonStage)] = [:]
        for pattern in patterns {
            for stage in [AlgorithmLessonStage.model, .recognize, .challenge] {
                result[pattern.lessonID(stage)] = (pattern, stage)
            }
        }
        return result
    }()

    static func pattern(id: String) -> AlgorithmPattern? {
        patterns.first { $0.id == id }
    }

    static func pattern(forLessonID lessonID: String) -> AlgorithmPattern? {
        lessonLookup[lessonID]?.pattern
    }

    static func stage(forLessonID lessonID: String) -> AlgorithmLessonStage? {
        lessonLookup[lessonID]?.stage
    }

    static func pattern(forChallengeLessonID lessonID: String) -> AlgorithmPattern? {
        guard lessonLookup[lessonID]?.stage == .challenge else { return nil }
        return lessonLookup[lessonID]?.pattern
    }

    static func category(id: String) -> AlgorithmCategory? {
        categories.first { $0.id == id }
    }

    static func method(id: String) -> AlgorithmCategory? {
        methods.first { $0.id == id }
    }

    static func categoryID(forPatternID patternID: String) -> String? {
        pattern(id: patternID)?.categoryID
    }

    static func nextLessonInSameMethod(after lessonID: String) -> RustLesson? {
        guard let pattern = pattern(forLessonID: lessonID),
              let method = method(id: pattern.categoryID)
        else { return nil }

        let lessons = method.patterns.flatMap(\.lessons)
        guard let index = lessons.firstIndex(where: { $0.id == lessonID }) else { return nil }
        let nextIndex = lessons.index(after: index)
        return nextIndex < lessons.endIndex ? lessons[nextIndex] : nil
    }

    static func writing(for lessonID: String) -> RustLessonWriting? {
        guard let entry = lessonLookup[lessonID] else { return nil }
        return writing(for: entry.pattern, stage: entry.stage)
    }

    static func challenge(for lessonID: String) -> AlgorithmChallenge? {
        guard let pattern = pattern(forChallengeLessonID: lessonID),
              let semanticProbe = AlgorithmVerificationData.semanticProbe(for: pattern.id)
        else { return nil }
        let output = "PASS \(pattern.id)\n"
        let cases = verificationCases(for: pattern, semanticProbe: semanticProbe)
        return AlgorithmChallenge(
            lessonID: lessonID,
            patternID: pattern.id,
            projectName: "algorithm-\(pattern.id)",
            source: challengeSource(for: pattern),
            verificationSource: verificationSource(for: pattern, cases: cases),
            verificationCases: cases,
            expectedOutput: output,
            requiredSourceFragments: ["pub fn solve", "input: &str", "-> String"],
            forbiddenSourceFragments: [
                "todo!(\"implement",
                "\"\(rustStringLiteral(pattern.expectedAnswer))\".to_string()",
                "String::from(\"\(rustStringLiteral(pattern.expectedAnswer))\")",
            ]
        )
    }

    private static func writing(
        for pattern: AlgorithmPattern,
        stage: AlgorithmLessonStage
    ) -> RustLessonWriting {
        switch stage {
        case .model:
            RustLessonWriting(
                summary: pattern.idea,
                explanation: "\(pattern.title) belongs to \(pattern.categoryTitle). Its invariant is the part that stays true after every step; tracing that invariant is more reliable than memorising lines. Typical uses include \(pattern.useCases).",
                exampleCaption: "Rust sketch · target \(pattern.complexity)",
                exampleCode: pattern.rustSketch,
                task: "Trace the sketch by hand and name the state that changes after each iteration.",
                success: "You can explain the invariant, termination condition, and \(pattern.complexity) bound without looking at the code.",
                rule: "Preserve the invariant first; the implementation is a consequence of it.",
                practiceCode: pattern.rustSketch,
                question: "What should you identify before translating this pattern into Rust?",
                answers: [
                    "Its invariant and the state changed by one step",
                    "The shortest variable names",
                    "A recursive implementation in every case",
                ],
                correctAnswer: 0,
                feedback: "The invariant explains both correctness and which state may change."
            )

        case .recognize:
            RustLessonWriting(
                summary: "Recognise the problem shape before choosing \(pattern.title).",
                explanation: "Reach for this pattern when the prompt contains \(pattern.useCases). Confirm that its assumptions actually hold, then compare \(pattern.complexity) with the input limits. Similar-looking prompts may need a different pattern when data is unsorted, weights are negative, or state cannot be updated locally.",
                exampleCaption: "Classification checklist for \(pattern.title)",
                exampleCode: """
                // 1. What structure or monotonic property is promised?
                // 2. What result must be maintained or optimised?
                // 3. Which edge case breaks the obvious approach?
                // Candidate: \(pattern.title)
                """,
                task: "Name two problem families that fit and one counterexample where this pattern is the wrong choice.",
                success: "You can justify the choice from constraints rather than from a remembered problem title.",
                rule: "Choose a pattern from the input guarantees and required operations, not from surface wording.",
                practiceCode: pattern.rustSketch,
                question: "Which group is the strongest signal for this pattern?",
                answers: [
                    "Any problem that contains a Vec",
                    pattern.useCases,
                    "Only problems with exactly one input value",
                ],
                correctAnswer: 1,
                feedback: "The useful signal is the operation and guarantee: \(pattern.useCases)."
            )

        case .challenge:
            RustLessonWriting(
                summary: pattern.task,
                explanation: "This is an original Crabrix exercise in the same problem family as common interview-platform questions. Visible input: \(pattern.visibleInput). Expected answer: \(pattern.expectedAnswer). Implement solve instead of printing the expected value directly; Crabrix supplies several verification cases privately when you Run. The input grammar matches the visible example, and whitespace surrounding the complete input is insignificant.",
                exampleCaption: "Editable solution · verification data stays outside the project",
                exampleCode: challengeSource(for: pattern),
                task: pattern.task,
                success: "The harness prints PASS \(pattern.id), and your explanation still meets \(pattern.complexity).",
                rule: "First make the visible case correct, then test a smallest, duplicate, or adversarial case. Trim whitespace surrounding the complete input before parsing.",
                practiceCode: challengeSource(for: pattern),
                question: "Which performance target should guide this solution?",
                answers: [
                    pattern.complexity,
                    "No complexity bound is needed",
                    "Always O(n!) time",
                ],
                correctAnswer: 0,
                feedback: "The intended target is \(pattern.complexity); defend any different tradeoff explicitly."
            )
        }
    }

    private static func challengeSource(for pattern: AlgorithmPattern) -> String {
        let task = rustComment(pattern.task)
        return """
        pub fn solve(input: &str) -> String {
            // \(task)
            // Parse the visible input into the structures your algorithm needs.
            // Whitespace surrounding the complete input is insignificant.
            let _ = input;
            todo!("implement \(pattern.title)")
        }
        """
    }

    private static func verificationCases(
        for pattern: AlgorithmPattern,
        semanticProbe: AlgorithmVerificationCase
    ) -> [AlgorithmVerificationCase] {
        [
            AlgorithmVerificationCase(
                kind: .visible,
                input: pattern.visibleInput,
                expectedAnswer: pattern.expectedAnswer
            ),
            semanticProbe,
            AlgorithmVerificationCase(
                kind: .normalisation,
                input: "\n\(semanticProbe.input)\n",
                expectedAnswer: semanticProbe.expectedAnswer
            ),
            AlgorithmVerificationCase(
                kind: .normalisation,
                input: "  \n\(pattern.visibleInput)\n  ",
                expectedAnswer: pattern.expectedAnswer
            ),
        ]
    }

    private static func verificationSource(
        for pattern: AlgorithmPattern,
        cases: [AlgorithmVerificationCase]
    ) -> String {
        let rustCases = cases.map { testCase in
            "    (r#\"\(rustRawString(testCase.input))\"#, r#\"\(rustRawString(testCase.expectedAnswer))\"#),"
        }.joined(separator: "\n")
        return """
        mod solution;

        fn main() {
            let cases = [
        \(rustCases)
            ];
            for (case_index, (input, expected)) in cases.iter().enumerate() {
                if solution::solve(input) != *expected {
                    eprintln!("PRIVATE CASE {} FAILED", case_index + 1);
                    std::process::exit(1);
                }
            }
            println!("PASS \(pattern.id)");
        }
        """
    }

    private static func rustComment(_ value: String) -> String {
        value.replacingOccurrences(of: "\n", with: " ")
    }

    private static func rustRawString(_ value: String) -> String {
        value.replacingOccurrences(of: "\"#", with: "\" #")
    }

    private static func rustStringLiteral(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}

struct AlgorithmPatternSeed: Sendable {
    let id: String
    let title: String
    let difficulty: AlgorithmDifficulty
    let idea: String
    let useCases: String
    let complexity: String
    let task: String
    let input: String
    let output: String
}

struct AlgorithmCategorySeed: Sendable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let achievementTitle: String
    let rustSketch: String
    let patterns: [AlgorithmPatternSeed]

    var category: AlgorithmCategory {
        AlgorithmCategory(
            id: id,
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            achievementTitle: achievementTitle,
            patterns: patterns.map { seed in
                AlgorithmPattern(
                    id: seed.id,
                    title: seed.title,
                    difficulty: seed.difficulty,
                    categoryID: id,
                    categoryTitle: title,
                    idea: seed.idea,
                    useCases: seed.useCases,
                    complexity: seed.complexity,
                    task: seed.task,
                    visibleInput: seed.input,
                    expectedAnswer: seed.output,
                    rustSketch: rustSketch
                )
            }
        )
    }
}
