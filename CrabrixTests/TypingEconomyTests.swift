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
final class BuildEnergyTests: XCTestCase {
    private func makeStore() -> (CrabrixVitalsStore, String) {
        let suite = "crabrix.tests.\(UUID().uuidString)"
        return (CrabrixVitalsStore(defaults: UserDefaults(suiteName: suite)!), suite)
    }

    func testRunningYourOwnCodeCostsNothing() {
        let (store, suite) = makeStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let health = store.health
        let energy = store.energy

        // Compiling is the point of the app. Charging for it made a failed
        // build cost the learner twice: once in time, once in meter.
        store.refresh()

        XCTAssertEqual(store.energy, energy)
        XCTAssertEqual(store.health, health)
    }
}
