import XCTest
@testable import Crabrix

final class VitalsCapacityTests: XCTestCase {
    func testCapacityAndRegenerationGrowWithRank() {
        let newcomer = VitalsCapacity.forRank(index: 0)
        let rustacean = VitalsCapacity.forRank(index: CrabrixRank.ladder.count - 1)

        XCTAssertGreaterThan(rustacean.maxHealth, newcomer.maxHealth)
        XCTAssertGreaterThan(rustacean.maxEnergy, newcomer.maxEnergy)
        XCTAssertGreaterThan(rustacean.healthPerHour, newcomer.healthPerHour)
        XCTAssertGreaterThan(rustacean.energyPerHour, newcomer.energyPerHour)
    }

    func testCapacityIsMonotonicAcrossEveryRank() {
        // A promotion must never shrink the pool, or ranking up would feel like
        // a punishment.
        var previous = VitalsCapacity.forRank(index: 0)
        for index in 1..<CrabrixRank.ladder.count {
            let current = VitalsCapacity.forRank(index: index)
            XCTAssertGreaterThanOrEqual(current.maxHealth, previous.maxHealth)
            XCTAssertGreaterThanOrEqual(current.maxEnergy, previous.maxEnergy)
            XCTAssertGreaterThanOrEqual(current.healthPerHour, previous.healthPerHour)
            XCTAssertGreaterThanOrEqual(current.energyPerHour, previous.energyPerHour)
            previous = current
        }
    }

    func testCapacityIsDerivedFromRatingPoints() {
        let low = VitalsCapacity.forPoints(0)
        let high = VitalsCapacity.forPoints(6_000)
        XCTAssertEqual(low, VitalsCapacity.forRank(index: 0))
        XCTAssertEqual(high, VitalsCapacity.forRank(index: CrabrixRank.ladder.count - 1))
    }

    func testAFullRefillGetsFasterAtEveryRank() {
        // The pool grows with rank, so regeneration has to grow faster still or
        // ranking up would mean a longer wait for a full bar.
        var previousHealth = Double.infinity
        var previousEnergy = Double.infinity
        for index in 0..<CrabrixRank.ladder.count {
            let capacity = VitalsCapacity.forRank(index: index)
            let health = Double(capacity.maxHealth) / capacity.healthPerHour
            let energy = Double(capacity.maxEnergy) / capacity.energyPerHour
            XCTAssertLessThan(health, previousHealth, "rank \(index) refills health slower")
            XCTAssertLessThan(energy, previousEnergy, "rank \(index) refills energy slower")
            previousHealth = health
            previousEnergy = energy
        }
    }
}

final class CrabrixVitalsStateTests: XCTestCase {
    private let capacity = VitalsCapacity.forRank(index: 0)
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func drained() -> CrabrixVitalsState {
        CrabrixVitalsState(health: 1, energy: 4, updatedAt: start)
    }

    func testRegenerationIsProportionalToElapsedTime() {
        let state = drained().regenerated(
            to: start.addingTimeInterval(3_600),
            capacity: capacity
        )
        XCTAssertEqual(state.health, 1 + capacity.healthPerHour, accuracy: 0.0001)
        XCTAssertEqual(state.energy, 4 + capacity.energyPerHour, accuracy: 0.0001)
    }

    func testRegenerationStopsAtCapacity() {
        let state = drained().regenerated(
            to: start.addingTimeInterval(86_400 * 7),
            capacity: capacity
        )
        XCTAssertEqual(state.health, Double(capacity.maxHealth))
        XCTAssertEqual(state.energy, Double(capacity.maxEnergy))
    }

    func testAClockMovedBackwardsNeverDrains() {
        let state = drained().regenerated(
            to: start.addingTimeInterval(-86_400),
            capacity: capacity
        )
        XCTAssertEqual(state.health, 1)
        XCTAssertEqual(state.energy, 4)
    }

    func testPartialRegenerationAccumulatesRatherThanRounding() {
        // Ten six-minute steps have to equal one full hour, or a reader who
        // opens the app often would regenerate more slowly than one who does not.
        var stepped = drained()
        for step in 1...10 {
            stepped = stepped.regenerated(
                to: start.addingTimeInterval(Double(step) * 360),
                capacity: capacity
            )
        }
        let single = drained().regenerated(to: start.addingTimeInterval(3_600), capacity: capacity)
        XCTAssertEqual(stepped.health, single.health, accuracy: 0.0001)
    }

    func testALessonPageIsChargedOnceAndThenFree() {
        var state = CrabrixVitalsState(health: 5, energy: 20, updatedAt: start)
        XCTAssertEqual(
            state.chargeLessonPage("ownership#0"),
            .spent(energy: CrabrixVitalsState.energyPerLessonPage)
        )
        let afterFirst = state.energy
        XCTAssertEqual(state.chargeLessonPage("ownership#0"), .free)
        XCTAssertEqual(state.energy, afterFirst, "re-reading a page must not charge again")
    }

    func testAPageIsNotChargedWhenEnergyIsShort() {
        var state = CrabrixVitalsState(health: 5, energy: 1, updatedAt: start)
        XCTAssertEqual(state.chargeLessonPage("ownership#0"), .blocked)
        XCTAssertEqual(state.energy, 1)
        XCTAssertFalse(state.chargedPageIDs.contains("ownership#0"))
    }

    func testTheFirstMistakeOfTheDayIsShielded() {
        var state = CrabrixVitalsState(health: 5, energy: 20, updatedAt: start)
        XCTAssertEqual(state.recordMistake(now: start, capacity: capacity), .shielded)
        XCTAssertEqual(state.health, 5, "a shielded mistake costs no health")
        XCTAssertEqual(state.recordMistake(now: start, capacity: capacity), .damaged(health: 1))
        XCTAssertEqual(state.health, 4)
    }

    func testShieldsComeBackTheNextDay() {
        var state = CrabrixVitalsState(health: 5, energy: 20, updatedAt: start)
        _ = state.recordMistake(now: start, capacity: capacity)
        _ = state.recordMistake(now: start, capacity: capacity)
        let tomorrow = start.addingTimeInterval(86_400)
        XCTAssertEqual(state.recordMistake(now: tomorrow, capacity: capacity), .shielded)
    }

    func testHealthNeverGoesNegative() {
        var state = CrabrixVitalsState(health: 0, energy: 20, updatedAt: start)
        state.shieldsUsed = capacity.dailyShields
        state.shieldDay = start
        XCTAssertEqual(state.recordMistake(now: start, capacity: capacity), .blocked)
        XCTAssertEqual(state.health, 0)
    }

    func testARunOfCorrectAnswersHandsEnergyBack() {
        var state = CrabrixVitalsState(health: 5, energy: 10, updatedAt: start)
        for _ in 1..<CrabrixVitalsState.flowStreakForRefund {
            XCTAssertEqual(state.recordCorrect(capacity: capacity), .free)
        }
        XCTAssertEqual(state.recordCorrect(capacity: capacity), .refunded(energy: 1))
        XCTAssertEqual(state.energy, 11)
    }

    func testAMistakeBreaksTheFlowStreak() {
        var state = CrabrixVitalsState(health: 5, energy: 10, updatedAt: start)
        _ = state.recordCorrect(capacity: capacity)
        _ = state.recordCorrect(capacity: capacity)
        _ = state.recordMistake(now: start, capacity: capacity)
        // The streak restarted, so the next correct answer refunds nothing.
        XCTAssertEqual(state.recordCorrect(capacity: capacity), .free)
    }

    func testCountdownReportsTimeToTheNextWholePoint() {
        let seconds = CrabrixVitalsState.secondsToNextPoint(
            value: 2.5,
            maximum: 5,
            perHour: 2
        )
        XCTAssertEqual(try XCTUnwrap(seconds), 900, accuracy: 0.001)
        XCTAssertNil(
            CrabrixVitalsState.secondsToNextPoint(value: 5, maximum: 5, perHour: 2),
            "a full pool has nothing to wait for"
        )
    }
}

@MainActor
final class CrabrixVitalsStoreTests: XCTestCase {
    private func makeStore(
        suite: String = UUID().uuidString,
        now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_700_000_000) }
    ) -> (CrabrixVitalsStore, String) {
        let defaults = UserDefaults(suiteName: suite)!
        return (CrabrixVitalsStore(defaults: defaults, now: now), suite)
    }

    func testAFreshStoreStartsFull() {
        let (store, suite) = makeStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        XCTAssertEqual(store.health, store.capacity.maxHealth)
        XCTAssertEqual(store.energy, store.capacity.maxEnergy)
        XCTAssertFalse(store.isLessonBlocked)
    }

    func testReadingAPageTwiceChargesOnce() {
        let (store, suite) = makeStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let before = store.energy
        store.startLessonPage(lessonID: "ownership", page: 0)
        let afterFirst = store.energy
        store.startLessonPage(lessonID: "ownership", page: 0)
        XCTAssertEqual(afterFirst, before - CrabrixVitalsState.energyPerLessonPage)
        XCTAssertEqual(store.energy, afterFirst)
    }

    func testTrainingNeverCostsAnything() {
        let (store, suite) = makeStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let health = store.health
        let energy = store.energy
        for _ in 0..<20 { store.recordTrainingAnswer(correct: false) }
        XCTAssertEqual(store.health, health, "training must stay unlimited")
        XCTAssertEqual(store.energy, energy)
    }

    func testRatingRaisesTheCeiling() {
        let (store, suite) = makeStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let low = store.capacity.maxHealth
        store.refresh(points: 6_000)
        XCTAssertGreaterThan(store.capacity.maxHealth, low)
    }

    func testVitalsSurviveARelaunch() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let moment = Date(timeIntervalSince1970: 1_700_000_000)

        let first = CrabrixVitalsStore(defaults: defaults, now: { moment })
        first.startLessonPage(lessonID: "ownership", page: 0)
        let spent = first.energy

        let second = CrabrixVitalsStore(defaults: defaults, now: { moment })
        XCTAssertEqual(second.energy, spent)
        // And the page stays paid for, so a relaunch cannot re-charge it.
        second.startLessonPage(lessonID: "ownership", page: 0)
        XCTAssertEqual(second.energy, spent)
    }

    func testHealthComesBackWhileTheAppIsClosed() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        var moment = Date(timeIntervalSince1970: 1_700_000_000)

        let store = CrabrixVitalsStore(defaults: defaults, now: { moment })
        store.refresh()
        for _ in 0..<5 { _ = store.recordAnswer(correct: false) }
        let drained = store.health
        XCTAssertLessThan(drained, store.capacity.maxHealth)

        moment = moment.addingTimeInterval(3_600 * 4)
        store.refresh()
        XCTAssertGreaterThan(store.health, drained)
    }

    func testLessonsPauseButTrainingDoesNotWhenHealthRunsOut() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let moment = Date(timeIntervalSince1970: 1_700_000_000)
        let store = CrabrixVitalsStore(defaults: defaults, now: { moment })

        for _ in 0..<(store.capacity.maxHealth + store.capacity.dailyShields) {
            _ = store.recordAnswer(correct: false)
        }
        XCTAssertTrue(store.isOutOfHealth)
        XCTAssertTrue(store.isLessonBlocked)
        // Training still runs, which is the whole point of the design.
        store.recordTrainingAnswer(correct: true)
        XCTAssertTrue(store.isOutOfHealth)
    }
}
