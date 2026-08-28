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

        for character in "fn main() {}" { ledger.record(project: "p", inserted: String(character)) }
        XCTAssertEqual(ledger.typedShare(project: "p"), 1.0, accuracy: 0.001)

        // A paste of a whole file is not writing.
        ledger.record(project: "p", inserted: String(repeating: "x", count: 500))
        XCTAssertLessThan(ledger.typedShare(project: "p"), 0.1)
    }

    func testTheAccessoryRowStillCountsAsTyping() {
        let (ledger, suite) = makeLedger()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        // "&mut " comes from the keyboard row, and is deliberate writing.
        ledger.record(project: "p", inserted: "&mut ")
        XCTAssertEqual(ledger.typedShare(project: "p"), 1.0, accuracy: 0.001)
    }

    func testAProjectWithNoHistoryIsNeitherRewardedNorPunished() {
        let (ledger, suite) = makeLedger()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        // An imported repository predates any typing; it is not cheating.
        XCTAssertEqual(ledger.typedShare(project: "imported"), 0.5, accuracy: 0.001)
    }

    func testProjectsAreCountedSeparately() {
        let (ledger, suite) = makeLedger()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        ledger.record(project: "typed", inserted: "let x = 1;")
        ledger.record(project: "pasted", inserted: String(repeating: "y", count: 300))
        XCTAssertGreaterThan(ledger.typedShare(project: "typed"), 0.9)
        XCTAssertLessThan(ledger.typedShare(project: "pasted"), 0.1)
    }

    func testPendingTypedCharactersDrainOnce() {
        let (ledger, suite) = makeLedger()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        ledger.record(project: "p", inserted: "abcde")
        XCTAssertEqual(ledger.drainPendingTyped(), 5)
        XCTAssertEqual(ledger.drainPendingTyped(), 0, "draining twice must not pay twice")
    }

    func testPastedCharactersEarnNoTypingRating() {
        let (ledger, suite) = makeLedger()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        ledger.record(project: "p", inserted: String(repeating: "z", count: 400))
        XCTAssertEqual(ledger.drainPendingTyped(), 0)
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

    func testOnlyTheFirstRunOfTheDayPaysForTheRun() {
        var first = CodeContribution(addedLines: 80)
        first.typedShare = 1.0
        var later = first
        later.isFirstRunToday = false
        XCTAssertGreaterThan(first.points, 20)
        XCTAssertEqual(later.points, 1, "a loop of builds must not out-earn writing")
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
        var contribution = CodeContribution(addedLines: 10)
        contribution.isFirstRunToday = true
        store.record(.buildSucceeded(contribution))

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

    func testARunCostsEnergy() {
        let (store, suite) = makeStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let before = store.energy
        store.spendOnBuild()
        XCTAssertEqual(store.energy, before - CrabrixVitalsState.energyPerBuild)
    }

    func testAnEmptyPoolNeverBlocksARun() {
        let (store, suite) = makeStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        for _ in 0..<(store.capacity.maxEnergy + 5) { store.spendOnBuild() }
        // Being unable to run your own code would be the wrong trade.
        XCTAssertGreaterThanOrEqual(store.energy, 0)
        XCTAssertEqual(store.spendOnBuild(), .free, "out of energy is free, not refused")
    }
}
