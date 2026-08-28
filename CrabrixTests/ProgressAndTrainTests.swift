import XCTest
@testable import Crabrix

@MainActor
final class CrabrixProgressStoreTests: XCTestCase {
    private func makeStore() -> (CrabrixProgressStore, UserDefaults, String) {
        let suite = "crabrix.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (CrabrixProgressStore(defaults: defaults), defaults, suite)
    }

    override func tearDown() {
        super.tearDown()
    }

    func testStartsEmptyAndAccumulatesAcrossEveryFeature() {
        let (store, _, suite) = makeStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        XCTAssertEqual(store.state.totalPoints, 0)
        XCTAssertEqual(store.rank.title, "Newcomer")

        let contribution = CodeContribution(addedLines: 12, removedLines: 3)
        store.record(.buildSucceeded(contribution))
        store.record(.lessonCompleted)
        store.record(.practicePassed)

        XCTAssertEqual(store.state.buildsSucceeded, 1)
        XCTAssertEqual(store.state.lessonsCompleted, 1)
        XCTAssertEqual(store.state.practiceRoundsPassed, 1)
        XCTAssertEqual(
            store.state.totalPoints,
            CrabrixProgressEvent.buildSucceeded(contribution).points
                + CrabrixProgressEvent.lessonCompleted.points
                + CrabrixProgressEvent.practicePassed.points
        )
    }

    func testPersistsAcrossInstances() {
        let suite = "crabrix.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let first = CrabrixProgressStore(defaults: defaults)
        first.record(.lessonCompleted)
        first.record(.termTrainFinished(pairs: 6, streak: 4, seconds: 30))
        let expected = first.state.totalPoints

        let reopened = CrabrixProgressStore(defaults: defaults)
        XCTAssertEqual(reopened.state.totalPoints, expected)
        XCTAssertEqual(reopened.state.lessonsCompleted, 1)
        XCTAssertEqual(reopened.state.termTrainPairsMatched, 6)
        XCTAssertEqual(reopened.state.termTrainBestStreak, 4)
    }

    func testKeepsTheBestTermTrainNumbersNotTheLatest() {
        let (store, _, suite) = makeStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        store.record(.termTrainFinished(pairs: 12, streak: 7, seconds: 60))
        store.record(.termTrainFinished(pairs: 2, streak: 1, seconds: 60))

        XCTAssertEqual(store.state.termTrainRuns, 2)
        XCTAssertEqual(store.state.termTrainPairsMatched, 14, "total pairs should accumulate")
        XCTAssertEqual(store.state.termTrainBestStreak, 7, "a worse run must not lower the best streak")
        XCTAssertEqual(store.state.bestTimedPairsPerMinute, 12)
    }

    func testUnlocksAchievementsOnceAndReportsThemForCelebration() {
        let (store, _, suite) = makeStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        store.record(.buildSucceeded(CodeContribution(addedLines: 4)))
        XCTAssertTrue(store.state.unlockedAchievementIDs.contains("builds.0"))
        XCTAssertEqual(store.pendingCelebration.map(\.id), ["builds.0"])

        store.clearCelebration()
        store.record(.buildSucceeded(CodeContribution(addedLines: 4)))
        XCTAssertTrue(
            store.pendingCelebration.isEmpty,
            "an already-unlocked achievement must not be celebrated again"
        )
        XCTAssertEqual(store.state.unlockedAchievementIDs.filter { $0 == "builds.0" }.count, 1)
    }

    func testRanksAdvanceWithPointsAndReportRemainingDistance() {
        XCTAssertEqual(CrabrixRank.rank(for: 0).title, "Newcomer")
        XCTAssertEqual(CrabrixRank.rank(for: 250).title, "Apprentice")
        XCTAssertEqual(CrabrixRank.rank(for: 749).title, "Apprentice")
        XCTAssertEqual(CrabrixRank.rank(for: 750).title, "Builder")

        let top = CrabrixRank.rank(for: 99_999)
        XCTAssertTrue(top.isMaximum)
        XCTAssertEqual(top.progress(points: 99_999), 1)

        let mid = CrabrixRank.rank(for: 500)
        XCTAssertEqual(mid.progress(points: 500), 0.5, accuracy: 0.01)
    }

    func testResetClearsEverything() {
        let (store, _, suite) = makeStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        store.record(.lessonCompleted)
        store.reset()
        XCTAssertEqual(store.state.totalPoints, 0)
        XCTAssertTrue(store.state.unlockedAchievementIDs.isEmpty)
    }
}

final class TermTrainDeckTests: XCTestCase {
    func testDealsAFullBoardOfDistinctPairs() {
        let board = TermTrainDeck.board()
        XCTAssertEqual(board.count, TermTrainDeck.boardSize)
        XCTAssertEqual(Set(board.map(\.id)).count, board.count, "a board must not repeat a pair")
    }

    func testExcludesPairsAlreadyOnTheBoard() {
        let first = TermTrainDeck.board()
        let replacement = TermTrainDeck.replacement(excluding: Set(first.map(\.id)))
        let id = replacement?.id
        XCTAssertNotNil(id)
        XCTAssertFalse(first.map(\.id).contains(id ?? ""))
    }

    func testFallsBackToTheFullDeckWhenEverythingIsUsed() {
        let all = Set(TermTrainDeck.all.map(\.id))
        // With nothing left to draw from, a board is still dealt rather than
        // leaving the player with an empty screen.
        let board = TermTrainDeck.board(excluding: all)
        XCTAssertEqual(board.count, TermTrainDeck.boardSize)
        XCTAssertNil(TermTrainDeck.replacement(excluding: all))
    }

    func testEveryPairHasBothSidesFilledIn() {
        for pair in TermTrainDeck.all {
            XCTAssertFalse(pair.term.trimmingCharacters(in: .whitespaces).isEmpty, pair.id)
            XCTAssertFalse(pair.description.trimmingCharacters(in: .whitespaces).isEmpty, pair.id)
        }
        XCTAssertEqual(
            Set(TermTrainDeck.all.map(\.id)).count,
            TermTrainDeck.all.count,
            "pair ids must be unique"
        )
    }

    func testModesDifferInClockAndPenalty() {
        XCTAssertNil(TermTrainMode.practice.duration)
        XCTAssertEqual(TermTrainMode.practice.mistakePenaltySeconds, 0)
        XCTAssertEqual(TermTrainMode.timed.duration, 60)
        XCTAssertGreaterThan(TermTrainMode.timed.mistakePenaltySeconds, 0)
    }

    func testRunResultScoresSpeedOnlyForTimedRuns() {
        let timed = TermTrainRunResult(
            mode: .timed, matched: 8, mistakes: 2, bestStreak: 5, elapsedSeconds: 30
        )
        let practice = TermTrainRunResult(
            mode: .practice, matched: 8, mistakes: 2, bestStreak: 5, elapsedSeconds: 30
        )

        XCTAssertEqual(timed.accuracy, 0.8, accuracy: 0.001)
        XCTAssertGreaterThan(
            timed.progressEvent.points,
            practice.progressEvent.points,
            "a fast timed run should be worth more than the same untimed run"
        )
        if case let .termTrainFinished(_, _, seconds) = practice.progressEvent {
            XCTAssertNil(seconds, "practice runs must not report a speed")
        } else {
            XCTFail("unexpected event")
        }
    }

    func testAccuracyIsZeroForARunWithNoAttempts() {
        let empty = TermTrainRunResult(
            mode: .practice, matched: 0, mistakes: 0, bestStreak: 0, elapsedSeconds: 1
        )
        XCTAssertEqual(empty.accuracy, 0)
    }
}

final class RustLessonProgressionNextStepTests: XCTestCase {
    private var allSteps: [RustLessonProgression.Step] {
        RustCourseCatalog.courses.flatMap { course in
            course.units.flatMap(\.lessons).map {
                RustLessonProgression.Step(courseID: course.id, lessonID: $0.id)
            }
        }
    }

    func testGoesToTheLessonRightAfterTheOneJustFinished() throws {
        let steps = allSteps
        let first = try XCTUnwrap(steps.first)
        let second = try XCTUnwrap(steps.dropFirst().first)

        let next = RustLessonProgression.nextStep(
            after: first.lessonID,
            completedLessonIDs: [first.lessonID]
        )
        XCTAssertEqual(next, second)
    }

    func testReviewingDoesNotSkipTheImmediatelyFollowingCompletedLesson() throws {
        let steps = allSteps
        let first = try XCTUnwrap(steps.first)
        let second = try XCTUnwrap(steps.dropFirst().first)

        let next = RustLessonProgression.nextStep(
            after: first.lessonID,
            completedLessonIDs: [first.lessonID, second.lessonID]
        )
        XCTAssertEqual(next, second)
    }

    func testContinuesIntoTheNextCourseAtACourseBoundary() throws {
        let steps = allSteps
        let firstCourse = try XCTUnwrap(RustCourseCatalog.courses.first)
        let lastOfFirst = try XCTUnwrap(
            steps.last(where: { $0.courseID == firstCourse.id })
        )
        let next = try XCTUnwrap(
            RustLessonProgression.nextStep(after: lastOfFirst.lessonID, completedLessonIDs: [lastOfFirst.lessonID])
        )
        XCTAssertNotEqual(next.courseID, firstCourse.id, "should move on to the next course")
    }

    func testFallsBackToAnEarlierGapWhenEverythingAfterIsDone() throws {
        let steps = allSteps
        let first = try XCTUnwrap(steps.first)
        // Everything except the very first lesson is finished.
        let completed = Set(steps.dropFirst().map(\.lessonID))
        let next = RustLessonProgression.nextStep(
            after: steps.last?.lessonID,
            completedLessonIDs: completed
        )
        XCTAssertEqual(next, first)
    }

    func testWithoutAnActiveLessonItPicksTheFirstUnfinishedOne() throws {
        let steps = allSteps
        let first = try XCTUnwrap(steps.first)
        let second = try XCTUnwrap(steps.dropFirst().first)

        XCTAssertEqual(
            RustLessonProgression.nextStep(after: nil, completedLessonIDs: []),
            first
        )
        XCTAssertEqual(
            RustLessonProgression.nextStep(after: nil, completedLessonIDs: [first.lessonID]),
            second
        )
    }

    func testAnUnknownLessonStillYieldsAConcreteStep() {
        XCTAssertNotNil(
            RustLessonProgression.nextStep(after: "not-a-lesson", completedLessonIDs: [])
        )
    }
}

final class CodeRecallDeckTests: XCTestCase {
    func testTheDeckIsDerivedFromLessonsAndIsNotEmpty() {
        XCTAssertFalse(CodeRecallDeck.all.isEmpty)
        let lessonIDs = Set(
            RustCourseCatalog.courses.flatMap { $0.units.flatMap(\.lessons) }.map(\.id)
        )
        for snippet in CodeRecallDeck.all {
            XCTAssertTrue(lessonIDs.contains(snippet.topic), "\(snippet.topic) has no lesson")
        }
    }

    func testEverySnippetIsLongEnoughAndHasNoRepeatedLines() {
        for snippet in CodeRecallDeck.all {
            XCTAssertGreaterThanOrEqual(snippet.lines.count, CodeRecallDeck.minimumLines, snippet.topic)
            XCTAssertLessThanOrEqual(snippet.lines.count, CodeRecallDeck.maximumLines, snippet.topic)
            // A duplicated line would make the correct order ambiguous.
            XCTAssertEqual(
                Set(snippet.lines).count,
                snippet.lines.count,
                "\(snippet.topic) repeats a line, so its order cannot be checked"
            )
            for line in snippet.lines {
                XCTAssertFalse(line.trimmingCharacters(in: .whitespaces).isEmpty, snippet.topic)
            }
        }
    }

    func testAWindowNeverExceedsTheSnippet() {
        let snippet = try! XCTUnwrap(CodeRecallDeck.all.first)
        XCTAssertEqual(snippet.window(size: 99).count, snippet.lines.count)
        XCTAssertEqual(snippet.window(size: 3).count, min(3, snippet.lines.count))
        XCTAssertGreaterThanOrEqual(snippet.window(size: 0).count, 2)
    }

    func testTheNextSnippetAvoidsOnesAlreadySeen() {
        var generator = SeededGenerator(state: 11)
        let first = try! XCTUnwrap(
            CodeRecallDeck.next(records: [:], using: &generator)
        )
        let second = try! XCTUnwrap(
            CodeRecallDeck.next(records: [:], excluding: [first.topic], using: &generator)
        )
        XCTAssertNotEqual(first.topic, second.topic)
    }

    func testScoringRewardsDepthOverVolume() {
        let deep = CodeRecallRunResult(bestLevel: 7, roundsCleared: 1, linesRecalled: 7)
        let shallow = CodeRecallRunResult(bestLevel: 3, roundsCleared: 3, linesRecalled: 9)
        XCTAssertGreaterThan(deep.progressEvent.points, shallow.progressEvent.points)
    }
}

final class CurriculumCoverageTests: XCTestCase {
    private var lessonIDs: [String] {
        RustCourseCatalog.courses.flatMap { $0.units.flatMap(\.lessons) }.map(\.id)
    }

    func testEveryLessonHasATermTrainPair() {
        // Term Train, Quick Practice, and Code Recall are all derived from the
        // curriculum. A lesson with no pair is a topic the drill cannot reach.
        let covered = Set(TermTrainDeck.all.map(\.topic))
        let missing = lessonIDs.filter { !covered.contains($0) }
        XCTAssertTrue(missing.isEmpty, "lessons with no Term Train pair: \(missing)")
    }

    func testNoTwoCardsShareATermOrADescription() {
        // A board with two identical faces has no single correct match.
        let terms = TermTrainDeck.all.map(\.term)
        let descriptions = TermTrainDeck.all.map(\.description)
        XCTAssertEqual(Set(terms).count, terms.count, "a duplicated term makes a round unwinnable")
        XCTAssertEqual(Set(descriptions).count, descriptions.count)
    }

    func testTheInterviewCourseCoversTheTopicsThatShipWithRust() {
        let ids = Set(lessonIDs)
        // Rust roles are rarely only about Rust; these come up beside it.
        let expected = [
            "q-atomics", "q-deadlock", "q-async-vs-threads", "q-cancellation",
            "q-stack-heap", "q-virtual-memory", "q-syscalls",
            "q-tcp-udp", "q-http-versions", "q-tls", "q-backpressure",
            "q-acid", "q-indexes", "q-cap", "q-idempotency", "q-caching",
            "q-complexity", "q-hashmap", "q-testing-strategy",
            "q-api-design", "q-perf-profiling", "q-ffi-abi",
        ]
        let missing = expected.filter { !ids.contains($0) }
        XCTAssertTrue(missing.isEmpty, "interview prep is missing: \(missing)")
    }

    func testEveryDrillDrawsFromTheWholeCurriculum() {
        let lessons = lessonIDs.count
        XCTAssertEqual(RustQuestionBank.all.count, lessons, "Quick Practice should reach every lesson")
        XCTAssertGreaterThanOrEqual(
            Set(TermTrainDeck.all.map(\.topic)).count, lessons,
            "Term Train should reach every lesson"
        )
        XCTAssertGreaterThan(CodeRecallDeck.all.count, lessons / 2, "Code Recall needs a real pool")
    }
}

final class ProgressStateCompatibilityTests: XCTestCase {
    /// A payload written by an older build, before several counters existed.
    private let legacyJSON = """
    {
      "version": 1,
      "totalPoints": 1450,
      "lessonsCompleted": 9,
      "buildsSucceeded": 22,
      "diagnosticsRepaired": 4,
      "practiceRoundsPassed": 6,
      "termTrainRuns": 3,
      "termTrainPairsMatched": 41,
      "termTrainBestStreak": 7,
      "bestTimedPairsPerMinute": 11,
      "packagesCompiled": 2,
      "unlockedAchievementIDs": ["first-build", "first-lesson"]
    }
    """

    func testAPayloadFromAnOlderBuildStillDecodes() throws {
        // Adding a counter must never cost someone their rating. Without an
        // explicit decoder, a missing key throws and the store silently starts
        // over from zero.
        let state = try JSONDecoder().decode(
            CrabrixProgressState.self,
            from: Data(legacyJSON.utf8)
        )
        XCTAssertEqual(state.totalPoints, 1450)
        XCTAssertEqual(state.lessonsCompleted, 9)
        XCTAssertEqual(state.buildsSucceeded, 22)
        // Fields the old build never wrote come back as their defaults.
        XCTAssertEqual(state.linesChanged, 0)
        XCTAssertEqual(state.codeRecallRuns, 0)
        XCTAssertEqual(state.codeRecallBestLevel, 0)
    }

    func testRoundTripKeepsEveryField() throws {
        var state = CrabrixProgressState()
        state.totalPoints = 999
        state.linesChanged = 4_200
        state.codeRecallBestLevel = 7
        state.unlockedAchievementIDs = ["a", "b"]

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(CrabrixProgressState.self, from: data)
        XCTAssertEqual(decoded, state)
    }
}
