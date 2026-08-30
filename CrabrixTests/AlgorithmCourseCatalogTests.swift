import XCTest
@testable import Crabrix

final class AlgorithmCourseCatalogTests: XCTestCase {
    private var patterns: [AlgorithmPattern] { AlgorithmCourseCatalog.patterns }

    func testCatalogContainsTwentyMethodChaptersAndTwoHundredPatterns() {
        XCTAssertEqual(AlgorithmCourseCatalog.categories.count, 20)
        XCTAssertEqual(AlgorithmCourseCatalog.methods.map(\.id), AlgorithmCourseCatalog.categories.map(\.id))
        XCTAssertEqual(patterns.count, 200)
        XCTAssertTrue(AlgorithmCourseCatalog.categories.allSatisfy { $0.patterns.count == 10 })
        XCTAssertEqual(Set(patterns.map(\.id)).count, 200)
    }

    func testCanonicalSolutionMethodsAreFirstClassChapters() {
        let titles = Set(AlgorithmCourseCatalog.methods.map(\.title))
        XCTAssertTrue(titles.contains("Two Pointers"))
        XCTAssertTrue(titles.contains("Sliding Window"))
        XCTAssertTrue(titles.contains("Binary Search"))
        XCTAssertTrue(titles.contains("DFS, BFS & Graph Traversal"))
        XCTAssertTrue(titles.contains("1D Dynamic Programming"))
        XCTAssertTrue(titles.contains("2D & Advanced Dynamic Programming"))
    }

    func testEveryPatternHasModelRecognitionAndCompilerChallenge() {
        let lessons = AlgorithmCourseCatalog.units.flatMap(\.lessons)
        XCTAssertEqual(lessons.count, 600)
        XCTAssertEqual(Set(lessons.map(\.id)).count, 600)

        for pattern in patterns {
            XCTAssertEqual(pattern.lessons.map(\.id), [
                pattern.lessonID(.model),
                pattern.lessonID(.recognize),
                pattern.lessonID(.challenge),
            ])
            if case .planned = pattern.lessons[0].exercise {} else {
                XCTFail("\(pattern.id) model step should be guided")
            }
            if case .planned = pattern.lessons[1].exercise {} else {
                XCTFail("\(pattern.id) recognition step should be guided")
            }
            if case .algorithmChallenge = pattern.lessons[2].exercise {} else {
                XCTFail("\(pattern.id) third step must run a local challenge")
            }
        }
    }

    func testEveryPatternHasCompleteOriginalTeachingMaterial() throws {
        for pattern in patterns {
            XCTAssertFalse(pattern.title.isEmpty, pattern.id)
            XCTAssertFalse(pattern.idea.isEmpty, pattern.id)
            XCTAssertFalse(pattern.useCases.isEmpty, pattern.id)
            XCTAssertFalse(pattern.complexity.isEmpty, pattern.id)
            XCTAssertFalse(pattern.task.isEmpty, pattern.id)
            XCTAssertFalse(pattern.visibleInput.isEmpty, pattern.id)
            XCTAssertFalse(pattern.expectedAnswer.isEmpty, pattern.id)

            for lesson in pattern.lessons {
                let writing = try XCTUnwrap(RustLessonLibrary.writing(for: lesson.id), lesson.id)
                XCTAssertEqual(writing.answers.count, 3, lesson.id)
                XCTAssertTrue(writing.answers.indices.contains(writing.correctAnswer), lesson.id)
                XCTAssertFalse(writing.summary.isEmpty, lesson.id)
                XCTAssertFalse(writing.explanation.isEmpty, lesson.id)
            }

            let challenge = try XCTUnwrap(
                AlgorithmCourseCatalog.challenge(for: pattern.lessonID(.challenge)),
                pattern.id
            )
            XCTAssertTrue(challenge.source.contains("fn solve"), pattern.id)
            XCTAssertTrue(challenge.source.contains("assert_eq!"), pattern.id)
            XCTAssertTrue(challenge.source.contains("todo!(\"implement"), pattern.id)
            XCTAssertEqual(challenge.expectedOutput, "PASS \(pattern.id)\n")
        }
    }

    func testDifficultyNeverMovesBackwardsInsideAMethod() {
        func rank(_ difficulty: AlgorithmDifficulty) -> Int {
            switch difficulty {
            case .easy: 0
            case .medium: 1
            case .hard: 2
            }
        }

        for method in AlgorithmCourseCatalog.methods {
            let ranks = method.patterns.map { rank($0.difficulty) }
            XCTAssertEqual(ranks, ranks.sorted(), method.id)
        }
    }

    func testAlgorithmMethodPathStaysInsideCompactAndRegularWidths() {
        for width: CGFloat in [240, 280, 320, 339, 534, 760] {
            for index in 0..<10 {
                let labelWidth = AlgorithmMethodPathLayout.labelWidth(for: width)
                let nodeX = AlgorithmMethodPathLayout.nodeCenterX(width: width, index: index)
                let labelX = AlgorithmMethodPathLayout.labelCenterX(
                    width: width,
                    nodeX: nodeX,
                    labelWidth: labelWidth,
                    labelToRight: AlgorithmMethodPathLayout.labelToRight(at: index)
                )
                let radius = AlgorithmMethodPathLayout.nodeDiameter / 2

                XCTAssertGreaterThanOrEqual(nodeX - radius, AlgorithmMethodPathLayout.edgeInset)
                XCTAssertLessThanOrEqual(nodeX + radius, width - AlgorithmMethodPathLayout.edgeInset)
                XCTAssertGreaterThanOrEqual(labelX - labelWidth / 2, AlgorithmMethodPathLayout.edgeInset)
                XCTAssertLessThanOrEqual(labelX + labelWidth / 2, width - AlgorithmMethodPathLayout.edgeInset)
            }
        }
    }

    func testCourseThemesAreStableAndUnique() {
        XCTAssertEqual(RustCourseCatalog.courses.count, 7)
        XCTAssertEqual(Set(RustCourseCatalog.courses.map(\.theme.rawValue)).count, 7)
        XCTAssertEqual(RustCourseCatalog.course(id: "algorithms")?.theme, .algorithms)
        XCTAssertEqual(RustCourseCatalog.lessonCount, 742)
    }

    func testAlgorithmValidatorRejectsPlaceholderAndAcceptsEditedVisibleCase() throws {
        let pattern = try XCTUnwrap(patterns.first)
        let lesson = try XCTUnwrap(RustCourseCatalog.lesson(id: pattern.lessonID(.challenge)))
        let challenge = try XCTUnwrap(AlgorithmCourseCatalog.challenge(for: lesson.id))
        let starter = CrabrixProject(
            name: challenge.projectName,
            files: ["main.rs": challenge.source],
            entryFile: "main.rs",
            provenance: nil
        )
        let run = CompilationResult(
            succeeded: true,
            phase: .run,
            exitCode: 0,
            diagnostics: [],
            stdout: challenge.expectedOutput,
            stderr: "",
            duration: .milliseconds(1),
            detail: "fixture"
        )

        let unchanged = LessonEvidenceValidator.validateCompilerAttempt(
            lesson: lesson,
            result: run,
            project: starter,
            initialSourceTreeHash: "same",
            currentSourceTreeHash: "same",
            observedDiagnosticCodes: []
        )
        XCTAssertFalse(unchanged.passed)

        let solvedSource = challenge.source.replacingOccurrences(
            of: "todo!(\"implement \(pattern.title)\")",
            with: "\"\(pattern.expectedAnswer)\".to_string()"
        )
        let solved = CrabrixProject(
            name: challenge.projectName,
            files: ["main.rs": solvedSource],
            entryFile: "main.rs",
            provenance: nil
        )
        let accepted = LessonEvidenceValidator.validateCompilerAttempt(
            lesson: lesson,
            result: run,
            project: solved,
            initialSourceTreeHash: "before",
            currentSourceTreeHash: "after",
            observedDiagnosticCodes: []
        )
        XCTAssertTrue(accepted.passed, accepted.detail)
    }
}

@MainActor
final class AlgorithmAchievementTests: XCTestCase {
    func testEachMethodHasAFiveTierLadderPlusOverallAtlas() {
        let families = CrabrixAchievementCatalog.families.filter { $0.group == .algorithms }
        XCTAssertEqual(families.count, 21)
        XCTAssertEqual(families.first { $0.id == "algorithm-atlas" }?.thresholds, [1, 25, 75, 150, 200])
        for category in AlgorithmCourseCatalog.categories {
            XCTAssertEqual(
                families.first { $0.id == "algorithm-\(category.id)" }?.thresholds,
                [1, 3, 5, 8, 10]
            )
        }
    }

    func testPatternMasteryIsIdempotentAndPersists() throws {
        let suite = "crabrix.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let pattern = try XCTUnwrap(AlgorithmCourseCatalog.patterns.first)

        let store = CrabrixProgressStore(defaults: defaults)
        XCTAssertTrue(store.recordAlgorithmSolved(patternID: pattern.id))
        XCTAssertFalse(store.recordAlgorithmSolved(patternID: pattern.id))
        XCTAssertEqual(store.state.solvedAlgorithmPatternIDs, [pattern.id])
        XCTAssertEqual(store.state.totalPoints, 0, "the lesson already owns the rating reward")

        let reopened = CrabrixProgressStore(defaults: defaults)
        XCTAssertEqual(reopened.state.solvedAlgorithmPatternIDs, [pattern.id])
        XCTAssertFalse(reopened.recordAlgorithmSolved(patternID: pattern.id))
    }

    func testThreeUniqueMethodSolutionsUnlockOnlyThatMethodSilverTier() throws {
        let suite = "crabrix.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let category = try XCTUnwrap(AlgorithmCourseCatalog.categories.first)
        let store = CrabrixProgressStore(defaults: defaults)

        for pattern in category.patterns.prefix(3) {
            store.recordAlgorithmSolved(patternID: pattern.id)
        }

        XCTAssertTrue(store.state.unlockedAchievementIDs.contains("algorithm-atlas.0"))
        XCTAssertTrue(store.state.unlockedAchievementIDs.contains("algorithm-\(category.id).1"))
        let another = try XCTUnwrap(AlgorithmCourseCatalog.categories.dropFirst().first)
        XCTAssertFalse(store.state.unlockedAchievementIDs.contains("algorithm-\(another.id).0"))
    }
}
