import XCTest
@testable import Crabrix

final class TypingLedgerTests: XCTestCase {
    private func makeLedger() -> (TypingLedger, String) {
        let suite = "crabrix.tests.\(UUID().uuidString)"
        return (TypingLedger(defaults: UserDefaults(suiteName: suite)!), suite)
    }

    func testShortInsertionsCountAsTypedAndLongOnesDoNot() {
        let (ledger, suite) = makeLedger()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let projectID = UUID()

        for character in "fn main() {}" {
            ledger.record(projectID: projectID, filePath: "main.rs", inserted: String(character))
        }
        XCTAssertEqual(ledger.typedShare(projectID: projectID), 1.0, accuracy: 0.001)

        // A paste of a whole file is not writing.
        ledger.record(
            projectID: projectID,
            filePath: "main.rs",
            inserted: String(repeating: "x", count: 500)
        )
        XCTAssertLessThan(ledger.typedShare(projectID: projectID), 0.1)
    }

    func testTheAccessoryRowStillCountsAsTyping() {
        let (ledger, suite) = makeLedger()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let projectID = UUID()
        // "&mut " comes from the keyboard row, and is deliberate writing.
        ledger.record(projectID: projectID, filePath: "main.rs", inserted: "&mut ")
        XCTAssertEqual(ledger.typedShare(projectID: projectID), 1.0, accuracy: 0.001)
    }

    func testAProjectWithNoHistoryIsNeitherRewardedNorPunished() {
        let (ledger, suite) = makeLedger()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        // An imported repository predates any typing; it is not cheating.
        XCTAssertEqual(ledger.typedShare(projectID: UUID()), 0.5, accuracy: 0.001)
    }

    func testProjectsAreCountedSeparately() {
        let (ledger, suite) = makeLedger()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let typedID = UUID()
        let pastedID = UUID()
        ledger.record(projectID: typedID, filePath: "main.rs", inserted: "let x = 1;")
        ledger.record(
            projectID: pastedID,
            filePath: "main.rs",
            inserted: String(repeating: "y", count: 300)
        )
        XCTAssertGreaterThan(ledger.typedShare(projectID: typedID), 0.9)
        XCTAssertLessThan(ledger.typedShare(projectID: pastedID), 0.1)
    }

    func testPendingTypedCharactersDrainOnce() {
        let (ledger, suite) = makeLedger()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let projectID = UUID()
        ledger.record(projectID: projectID, filePath: "main.rs", inserted: "abcde")
        XCTAssertEqual(ledger.drainPendingTyped(projectID: projectID), 5)
        XCTAssertEqual(
            ledger.drainPendingTyped(projectID: projectID),
            0,
            "draining twice must not pay twice"
        )
    }

    func testPastedCharactersEarnNoTypingRating() {
        let (ledger, suite) = makeLedger()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let projectID = UUID()
        ledger.record(
            projectID: projectID,
            filePath: "main.rs",
            inserted: String(repeating: "z", count: 400)
        )
        XCTAssertEqual(ledger.drainPendingTyped(projectID: projectID), 0)
    }

    func testPendingCharactersCannotDrainAcrossProjects() {
        let (ledger, suite) = makeLedger()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let first = UUID()
        let second = UUID()

        ledger.record(projectID: first, filePath: "main.rs", inserted: "abc")
        ledger.record(projectID: second, filePath: "main.rs", inserted: "de")

        XCTAssertEqual(ledger.drainPendingTyped(projectID: second), 2)
        XCTAssertEqual(ledger.pendingTyped(projectID: first), 3)
    }
}

final class RunRewardEconomyTests: XCTestCase {
    func testHandWrittenCodeIsWorthMoreThanTheSameCodePasted() {
        var typed = CodeContribution(addedLines: 60)
        typed.typedShare = 1.0
        var pasted = CodeContribution(addedLines: 60)
        pasted.typedShare = 0.0
        XCTAssertGreaterThan(typed.points, pasted.points)
        // And meaningfully so, not by a rounding error.
        XCTAssertGreaterThan(Double(typed.points), Double(pasted.points) * 1.8)
    }

    @MainActor
    func testTheSameRevisionIsPaidOnceHoweverOftenItIsRun() {
        let suite = "crabrix.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let store = CrabrixProgressStore(defaults: defaults)

        var contribution = CodeContribution(addedLines: 80)
        contribution.typedShare = 1.0
        let key = CrabrixProgressState.buildRevisionKeyPrefix + "project:revision-a"
        XCTAssertTrue(store.record(.buildSucceeded(contribution), eventKey: key))
        let afterFirst = store.state.totalPoints
        XCTAssertGreaterThan(afterFirst, 20)

        XCTAssertFalse(
            store.record(.buildSucceeded(contribution), eventKey: key),
            "a loop of identical builds must not out-earn writing"
        )
        XCTAssertEqual(store.state.totalPoints, afterFirst)

        // Editing and running again on the same day is real work, and is paid.
        XCTAssertTrue(store.record(
            .buildSucceeded(contribution),
            eventKey: CrabrixProgressState.buildRevisionKeyPrefix + "project:revision-b"
        ))
        XCTAssertGreaterThan(store.state.totalPoints, afterFirst)
    }

    @MainActor
    func testRevisionIdentitiesStayBoundedWhileLessonIdentitiesDoNot() {
        let suite = "crabrix.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let store = CrabrixProgressStore(defaults: defaults)

        let limit = CrabrixProgressState.maximumRecentBuildRevisions
        for index in 0...(limit + 20) {
            store.record(
                .buildSucceeded(CodeContribution(addedLines: 1)),
                eventKey: CrabrixProgressState.buildRevisionKeyPrefix + "project:\(index)"
            )
        }
        XCTAssertEqual(store.state.recentBuildRevisions.count, limit)
        XCTAssertTrue(store.state.processedEventKeys.isEmpty, "revisions never join the permanent set")
        // The window keeps the newest revisions, so the loop just run is still
        // recognised as already paid.
        XCTAssertFalse(store.record(
            .buildSucceeded(CodeContribution(addedLines: 1)),
            eventKey: CrabrixProgressState.buildRevisionKeyPrefix + "project:\(limit + 20)"
        ))
        // A lesson is finite and stays remembered for good.
        store.record(.lessonCompleted, eventKey: "lesson:basics-1:first-completion")
        XCTAssertTrue(store.state.processedEventKeys.contains("lesson:basics-1:first-completion"))
    }

    func testTypingIsWhereTheRatingComesFrom() {
        // A day of writing should beat the one run bonus it is paired with.
        let aDayOfTyping = CrabrixProgressEvent.codeTyped(characters: 8_000)
        var run = CodeContribution(addedLines: 40)
        run.typedShare = 1.0
        XCTAssertGreaterThan(aDayOfTyping.points, CrabrixProgressEvent.buildSucceeded(run).points)
    }

    func testTypingRatingScalesWithVolume() {
        XCTAssertEqual(CrabrixProgressEvent.codeTyped(characters: 40).points, 1)
        XCTAssertEqual(CrabrixProgressEvent.codeTyped(characters: 4_000).points, 100)
        XCTAssertEqual(CrabrixProgressEvent.codeTyped(characters: 10).points, 0)
    }

    @MainActor
    func testTheDailyRunRewardResetsTheNextDay() {
        let suite = "crabrix.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let store = CrabrixProgressStore(defaults: defaults)

        XCTAssertTrue(store.isFirstRunToday())
        store.record(.dailyRunBonus)

        XCTAssertFalse(store.isFirstRunToday(), "the day's reward is already paid")
        let tomorrow = Date().addingTimeInterval(86_400)
        XCTAssertTrue(store.isFirstRunToday(now: tomorrow))
    }
}

@MainActor
final class RatingAbuseTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    private func defaults() -> (UserDefaults, String) {
        let suite = "crabrix.rating-abuse.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    func testTypingAndDeletingBackToTheSameRevisionCannotPayAgain() {
        let (defaults, suite) = defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CrabrixProgressStore(defaults: defaults)
        let contribution = CodeContribution(addedLines: 10, addedCharacters: 400)
        XCTAssertTrue(store.recordSourceRun(
            contribution: contribution, sourceTreeHash: "source-a", typedCharacters: 400, now: now
        ))
        let points = store.state.totalPoints
        for _ in 0..<20 {
            XCTAssertFalse(store.recordSourceRun(
                contribution: contribution, sourceTreeHash: "source-a", typedCharacters: 4_000, now: now
            ))
        }
        XCTAssertEqual(store.state.totalPoints, points)
        XCTAssertEqual(store.state.charactersTyped, 400)
    }

    func testCloningALegacyProjectCannotPayForItsSourceAgain() {
        let (defaults, suite) = defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = CrabrixProgressStore(defaults: defaults)
        first.record(.buildSucceeded(CodeContribution(addedLines: 10)), eventKey: "build-revision:old-project:same-source", now: now)
        let points = first.state.totalPoints
        let reopened = CrabrixProgressStore(defaults: defaults)
        XCTAssertFalse(reopened.record(
            .buildSucceeded(CodeContribution(addedLines: 10)),
            eventKey: "build-revision:new-project:same-source", now: now
        ))
        XCTAssertEqual(reopened.state.totalPoints, points)
    }

    func testLegacyBuildsMigrateWithoutPayingForANormalizedCopy() {
        let (defaults, suite) = defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CrabrixProgressStore(defaults: defaults)
        let contribution = CodeContribution(addedLines: 10)
        store.record(.buildSucceeded(contribution), eventKey: "build-revision:project:raw-source", now: now)
        XCTAssertFalse(store.recordSourceRun(
            contribution: contribution, sourceTreeHash: "raw-source", scoringSourceHash: "normalized-source", typedCharacters: 400, now: now
        ))
        let points = store.state.totalPoints
        XCTAssertFalse(store.recordSourceRun(
            contribution: contribution, sourceTreeHash: "formatted-copy", scoringSourceHash: "normalized-source", typedCharacters: 400, now: now
        ))
        XCTAssertEqual(store.state.totalPoints, points)
    }

    func testWhitespaceAndCommentRevisionsCannotEvictPaidWork() {
        let (defaults, suite) = defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CrabrixProgressStore(defaults: defaults)
        store.recordSourceRun(contribution: CodeContribution(addedLines: 2, addedCharacters: 40), sourceTreeHash: "real-source", typedCharacters: 40, now: now)
        let points = store.state.totalPoints
        for index in 0..<500 {
            XCTAssertFalse(store.recordSourceRun(
                contribution: CodeContribution(), sourceTreeHash: "formatting-\(index)", typedCharacters: 400, now: now
            ))
        }
        XCTAssertEqual(store.state.totalPoints, points)
        XCTAssertEqual(store.state.recentBuildRevisions.count, 2)
    }

    func testManyUniqueRevisionsCannotExceedTheDailyBudgetEvenAfterEviction() {
        let (defaults, suite) = defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CrabrixProgressStore(defaults: defaults)
        for index in 0..<450 {
            store.recordSourceRun(contribution: CodeContribution(addedLines: 4, addedCharacters: 160), sourceTreeHash: "source-\(index)", typedCharacters: 400, now: now)
        }
        XCTAssertEqual(store.state.totalPoints, 300 + 500 + 25)
        let reopened = CrabrixProgressStore(defaults: defaults)
        reopened.recordSourceRun(contribution: CodeContribution(addedLines: 4, addedCharacters: 160), sourceTreeHash: "source-0", typedCharacters: 400, now: now)
        XCTAssertEqual(reopened.state.totalPoints, store.state.totalPoints)
        // The next day still rewards new work.
        reopened.recordSourceRun(contribution: CodeContribution(addedLines: 4, addedCharacters: 160), sourceTreeHash: "new-day-source", typedCharacters: 400, now: now.addingTimeInterval(86_400))
        XCTAssertGreaterThan(reopened.state.totalPoints, store.state.totalPoints)
    }

    func testChangingTheClockBackCannotReopenABudget() {
        let (defaults, suite) = defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CrabrixProgressStore(defaults: defaults)
        store.record(.codeTyped(characters: 20_000), now: now)
        let points = store.state.totalPoints
        store.record(.codeTyped(characters: 20_000), now: now.addingTimeInterval(-86_400))
        store.record(.codeTyped(characters: 20_000), now: now)
        XCTAssertEqual(store.state.totalPoints, points)
    }

    func testDeletedTypingCannotBeBankedForATinyNewEdit() {
        let (defaults, suite) = defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CrabrixProgressStore(defaults: defaults)
        let contribution = CodeContribution.measure(
            previous: ["main.rs": "fn main() { let x = 1; }"],
            current: ["main.rs": "fn main() { let x = 2; }"]
        )
        store.recordSourceRun(contribution: contribution, sourceTreeHash: "tiny-edit", typedCharacters: 20_000, now: now)
        XCTAssertEqual(store.state.charactersTyped, contribution.addedCharacters)
        XCTAssertLessThan(store.state.charactersTyped, 40)
        XCTAssertEqual(store.state.dailyRewardPoints["typing", default: 0], 0)
    }

    func testRepeatingPracticePaysOnlyOncePerQuestionAcrossRelaunches() {
        let (defaults, suite) = defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = CrabrixProgressStore(defaults: defaults)
        first.record(.practicePassed, eventKey: "practice:variables:first-completion")
        let reopened = CrabrixProgressStore(defaults: defaults)
        XCTAssertFalse(reopened.record(.practicePassed, eventKey: "practice:variables:first-completion"))
        XCTAssertTrue(reopened.record(.practicePassed, eventKey: "practice:ownership:first-completion"))
        XCTAssertEqual(reopened.state.totalPoints, 90)
        XCTAssertEqual(reopened.state.practiceRoundsPassed, 2)
    }

    func testTheCompilerDrillCannotBeFarmedWithoutAnEventKey() {
        let (defaults, suite) = defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CrabrixProgressStore(defaults: defaults)
        XCTAssertTrue(store.record(.practicePassed))
        XCTAssertFalse(store.record(.practicePassed))
        XCTAssertEqual(store.state.totalPoints, 45)
    }

    func testTermTrainPaysOnlyForABetterResultButRetainsTrainingStatistics() {
        let (defaults, suite) = defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = CrabrixProgressStore(defaults: defaults)
        first.record(.termTrainFinished(pairs: 5, streak: 5, seconds: nil), now: now)
        let points = first.state.totalPoints
        let reopened = CrabrixProgressStore(defaults: defaults)
        reopened.record(.termTrainFinished(pairs: 5, streak: 5, seconds: nil), now: now.addingTimeInterval(86_400))
        XCTAssertEqual(reopened.state.totalPoints, points)
        reopened.record(.termTrainFinished(pairs: 6, streak: 6, seconds: nil), now: now.addingTimeInterval(86_400))
        XCTAssertEqual(reopened.state.totalPoints, 90)
        XCTAssertEqual(reopened.state.termTrainRuns, 3)
        XCTAssertEqual(reopened.state.termTrainPairsMatched, 16)
    }

    func testCodeRecallPaysOnlyTheImprovementOverTheBestRun() {
        let (defaults, suite) = defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CrabrixProgressStore(defaults: defaults)
        store.record(.codeRecallFinished(bestLevel: 3, linesRecalled: 3), now: now)
        let points = store.state.totalPoints
        store.record(.codeRecallFinished(bestLevel: 3, linesRecalled: 3), now: now)
        store.record(.codeRecallFinished(bestLevel: 2, linesRecalled: 2), now: now)
        XCTAssertEqual(store.state.totalPoints, points)
        store.record(.codeRecallFinished(bestLevel: 4, linesRecalled: 7), now: now)
        XCTAssertEqual(store.state.totalPoints, 148)
        XCTAssertEqual(store.state.codeRecallRuns, 4)
    }

    func testDailyBonusIsGuardedInsideTheStoreAndSurvivesRelaunch() {
        let (defaults, suite) = defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CrabrixProgressStore(defaults: defaults)
        XCTAssertTrue(store.record(.dailyRunBonus, now: now))
        XCTAssertFalse(store.record(.dailyRunBonus, now: now))
        let reopened = CrabrixProgressStore(defaults: defaults)
        XCTAssertFalse(reopened.record(.dailyRunBonus, now: now))
        XCTAssertFalse(reopened.record(.dailyRunBonus, now: now.addingTimeInterval(-86_400)))
        XCTAssertTrue(reopened.record(.dailyRunBonus, now: now.addingTimeInterval(86_400)))
        XCTAssertEqual(reopened.state.totalPoints, 50)
    }

    func testRepairAndPackageLoopsShareTheBuildBudget() {
        let (defaults, suite) = defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CrabrixProgressStore(defaults: defaults)
        for index in 0..<30 {
            store.record(.diagnosticRepaired, eventKey: "repair:\(index)", now: now)
            store.record(.packagesCompiled(1), eventKey: "crate:\(index)", now: now)
        }
        XCTAssertEqual(store.state.totalPoints, 300)
        store.record(.lessonCompleted, eventKey: "lesson:new:first-completion", now: now)
        XCTAssertEqual(store.state.totalPoints, 420, "a curriculum step keeps its full reward")
    }

    func testInvalidPayloadsCannotChangeRatingOrCounters() {
        let (defaults, suite) = defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CrabrixProgressStore(defaults: defaults)
        let before = store.state
        let events: [CrabrixProgressEvent] = [
            .codeTyped(characters: -40), .packagesCompiled(-1),
            .termTrainFinished(pairs: -1, streak: 0, seconds: nil),
            .termTrainFinished(pairs: 1, streak: 100, seconds: 0),
            .codeRecallFinished(bestLevel: Int.max, linesRecalled: Int.max),
            .buildSucceeded(CodeContribution(addedLines: Int.max)),
        ]
        for event in events { XCTAssertFalse(store.record(event)) }
        XCTAssertEqual(store.state, before)
    }
}
