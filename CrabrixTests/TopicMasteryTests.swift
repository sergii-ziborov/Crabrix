import XCTest
@testable import Crabrix

/// A generator with a fixed sequence, so weighted selection can be asserted.
/// Shared by every test that needs a deterministic draw.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        // xorshift64*, deterministic and good enough for test selection.
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 2_685_821_657_736_338_717
    }
}

final class TopicMasteryRecordTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    func testAnUnseenTopicSitsInTheMiddleAndIsDue() {
        let record = TopicMasteryRecord(topic: "ownership", now: epoch)
        XCTAssertEqual(record.strength, 0.5)
        XCTAssertTrue(record.isDue(at: epoch))
        XCTAssertEqual(record.attempts, 0)
    }

    func testCorrectAnswersFollowTheSM2Intervals() {
        var record = TopicMasteryRecord(topic: "borrowing", now: epoch)

        record.record(quality: 5, now: epoch)
        XCTAssertEqual(record.repetitions, 1)
        XCTAssertEqual(record.intervalDays, 1, accuracy: 0.001)

        record.record(quality: 5, now: epoch)
        XCTAssertEqual(record.repetitions, 2)
        XCTAssertEqual(record.intervalDays, 6, accuracy: 0.001, "SM-2's second interval is six days")

        record.record(quality: 5, now: epoch)
        XCTAssertEqual(record.repetitions, 3)
        // Third and later intervals multiply by the ease factor.
        XCTAssertGreaterThan(record.intervalDays, 6)
    }

    func testAWrongAnswerResetsTheScheduleToTomorrow() {
        var record = TopicMasteryRecord(topic: "lifetimes", now: epoch)
        for _ in 0..<3 { record.record(quality: 5, now: epoch) }
        XCTAssertGreaterThan(record.intervalDays, 6)

        record.record(quality: 1, now: epoch)
        XCTAssertEqual(record.repetitions, 0, "a lapse restarts the streak")
        XCTAssertEqual(record.intervalDays, 1, accuracy: 0.001)
        XCTAssertEqual(record.incorrect, 1)
    }

    func testEaseNeverFallsBelowTheSM2Floor() {
        var record = TopicMasteryRecord(topic: "unsafe", now: epoch)
        for _ in 0..<40 { record.record(quality: 0, now: epoch) }
        XCTAssertGreaterThanOrEqual(record.easeFactor, TopicMasteryRecord.minimumEase)
    }

    func testStrengthRewardsAccuracyAndStreak() {
        var strong = TopicMasteryRecord(topic: "a", now: epoch)
        for _ in 0..<6 { strong.record(quality: 5, now: epoch) }

        var weak = TopicMasteryRecord(topic: "b", now: epoch)
        for _ in 0..<6 { weak.record(quality: 1, now: epoch) }

        XCTAssertGreaterThan(strong.strength, 0.9)
        XCTAssertLessThan(weak.strength, 0.2)
        XCTAssertGreaterThan(strong.strength, weak.strength)
    }
}

final class TopicSchedulerTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    func testUnseenTopicsOutrankMasteredOnes() {
        var mastered = TopicMasteryRecord(topic: "known", now: epoch)
        for _ in 0..<5 { mastered.record(quality: 5, now: epoch) }

        let unseen = TopicScheduler.weight(for: nil, now: epoch)
        let known = TopicScheduler.weight(for: mastered, now: epoch)
        XCTAssertGreaterThan(unseen, known)
    }

    func testWeakTopicsOutrankStrongOnes() {
        var weak = TopicMasteryRecord(topic: "weak", now: epoch)
        for _ in 0..<4 { weak.record(quality: 1, now: epoch) }
        var strong = TopicMasteryRecord(topic: "strong", now: epoch)
        for _ in 0..<4 { strong.record(quality: 5, now: epoch) }

        XCTAssertGreaterThan(
            TopicScheduler.weight(for: weak, now: epoch),
            TopicScheduler.weight(for: strong, now: epoch)
        )
    }

    func testAnOverdueTopicGainsUrgency() {
        var record = TopicMasteryRecord(topic: "due", now: epoch)
        record.record(quality: 5, now: epoch) // due in one day

        let justScheduled = TopicScheduler.weight(for: record, now: epoch)
        let tenDaysLate = TopicScheduler.weight(
            for: record,
            now: epoch.addingTimeInterval(11 * 86_400)
        )
        XCTAssertGreaterThan(tenDaysLate, justScheduled)
    }

    func testPickNeverRepeatsAndRespectsTheCount() {
        var generator = SeededGenerator(state: 42)
        let topics = ["a", "b", "c", "d", "e"]
        let picked = TopicScheduler.pick(
            count: 3, from: topics, records: [:], now: epoch, using: &generator
        )
        XCTAssertEqual(picked.count, 3)
        XCTAssertEqual(Set(picked).count, 3, "a round must not ask the same topic twice")
        XCTAssertTrue(picked.allSatisfy(topics.contains))
    }

    func testPickCannotAskForMoreThanExists() {
        var generator = SeededGenerator(state: 7)
        let picked = TopicScheduler.pick(
            count: 10, from: ["only"], records: [:], now: epoch, using: &generator
        )
        XCTAssertEqual(picked, ["only"])
    }

    func testWeakTopicsAreChosenMoreOftenOverManyRounds() {
        var records: [String: TopicMasteryRecord] = [:]
        for name in ["strong1", "strong2", "strong3"] {
            var record = TopicMasteryRecord(topic: name, now: epoch)
            for _ in 0..<6 { record.record(quality: 5, now: epoch) }
            records[name] = record
        }
        var weak = TopicMasteryRecord(topic: "weak", now: epoch)
        for _ in 0..<6 { weak.record(quality: 1, now: epoch) }
        records["weak"] = weak

        let topics = ["strong1", "strong2", "strong3", "weak"]
        var generator = SeededGenerator(state: 99)
        var weakPicks = 0
        for _ in 0..<200 {
            let picked = TopicScheduler.pick(
                count: 1, from: topics, records: records, now: epoch, using: &generator
            )
            if picked.first == "weak" { weakPicks += 1 }
        }
        // Uniform selection would land near 50 of 200; weighting should beat that clearly.
        XCTAssertGreaterThan(weakPicks, 80, "the weak topic should dominate selection")
        XCTAssertLessThan(weakPicks, 200, "but selection must stay random, not fixed")
    }
}

@MainActor
final class TopicMasteryStoreTests: XCTestCase {
    private func makeStore() -> (TopicMasteryStore, String) {
        let suite = "crabrix.mastery.tests.\(UUID().uuidString)"
        return (TopicMasteryStore(defaults: UserDefaults(suiteName: suite)!), suite)
    }

    func testRecordsAnswersAndPersistsThem() {
        let suite = "crabrix.mastery.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let store = TopicMasteryStore(defaults: defaults)
        store.record(topic: "ownership", correct: true)
        store.record(topic: "ownership", correct: true)
        store.record(topic: "borrowing", correct: false)

        let reopened = TopicMasteryStore(defaults: defaults)
        XCTAssertEqual(reopened.record(for: "ownership")?.correct, 2)
        XCTAssertEqual(reopened.record(for: "borrowing")?.incorrect, 1)
        XCTAssertGreaterThan(
            reopened.record(for: "ownership")?.strength ?? 0,
            reopened.record(for: "borrowing")?.strength ?? 1
        )
    }

    func testWeakestReportsOnlyAttemptedTopics() {
        let (store, suite) = makeStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        store.record(topic: "seen", correct: false)
        let weakest = store.weakest(from: ["seen", "never-attempted"])
        XCTAssertEqual(weakest.map(\.topic), ["seen"])
    }

    func testSummaryCountsStrongAndWeakSeparately() {
        let (store, suite) = makeStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        for _ in 0..<6 { store.record(topic: "solid", correct: true) }
        for _ in 0..<6 { store.record(topic: "shaky", correct: false) }

        let summary = store.summary
        XCTAssertEqual(summary.seen, 2)
        XCTAssertEqual(summary.strong, 1)
        XCTAssertEqual(summary.weak, 1)
    }

    func testResetClearsEverything() {
        let (store, suite) = makeStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        store.record(topic: "x", correct: true)
        store.reset()
        XCTAssertTrue(store.records.isEmpty)
    }
}

final class RustQuestionBankTests: XCTestCase {
    func testEveryQuestionIsWellFormed() {
        XCTAssertFalse(RustQuestionBank.all.isEmpty)
        for question in RustQuestionBank.all {
            XCTAssertTrue(question.isWellFormed, "\(question.topic) is malformed")
        }
    }

    func testQuestionTopicsMatchRealLessons() {
        let lessonIDs = Set(
            RustCourseCatalog.courses.flatMap { $0.units.flatMap(\.lessons) }.map(\.id)
        )
        for question in RustQuestionBank.all {
            XCTAssertTrue(
                lessonIDs.contains(question.topic),
                "\(question.topic) has no matching lesson"
            )
        }
    }

    func testTopicsAreUniqueSoARoundCannotRepeatItself() {
        let topics = RustQuestionBank.topics
        XCTAssertEqual(Set(topics).count, topics.count)
    }

    func testEveryLessonContributesAQuestion() {
        // Practice is derived from lesson writing, so a lesson without content
        // vanishes from Quick Practice silently instead of failing loudly.
        let lessons = RustCourseCatalog.courses.flatMap { $0.units.flatMap(\.lessons) }
        let covered = Set(RustQuestionBank.topics)
        let missing = lessons.map(\.id).filter { !covered.contains($0) }
        XCTAssertTrue(missing.isEmpty, "lessons with no question: \(missing)")
        XCTAssertEqual(RustQuestionBank.all.count, lessons.count)
    }

    func testEveryQuestionCarriesTheSnippetItAsksAbout() {
        // Several prompts are phrased as "why is that rejected?", which only
        // works because the code travels with the question outside its lesson.
        for question in RustQuestionBank.all {
            XCTAssertFalse(
                question.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "\(question.topic) has a prompt with no code to point at"
            )
            for line in question.code.split(separator: "\n", omittingEmptySubsequences: false) {
                XCTAssertLessThanOrEqual(
                    line.count, 52,
                    "\(question.topic) practice line is too wide for a phone: \(line)"
                )
            }
        }
    }

    func testARoundDrawsDistinctQuestions() {
        var generator = SeededGenerator(state: 5)
        let round = RustQuestionBank.round(count: 4, records: [:], using: &generator)
        XCTAssertEqual(round.count, min(4, RustQuestionBank.all.count))
        XCTAssertEqual(Set(round.map(\.topic)).count, round.count)
    }
}

final class TermTrainTopicTests: XCTestCase {
    func testEveryPairPointsAtARealLesson() {
        let lessonIDs = Set(
            RustCourseCatalog.courses.flatMap { $0.units.flatMap(\.lessons) }.map(\.id)
        )
        for pair in TermTrainDeck.all {
            XCTAssertTrue(
                lessonIDs.contains(pair.topic),
                "\(pair.id) points at unknown topic \(pair.topic)"
            )
        }
    }

    func testTermsAndDescriptionsAreUnique() {
        XCTAssertEqual(Set(TermTrainDeck.all.map(\.term)).count, TermTrainDeck.all.count)
        XCTAssertEqual(Set(TermTrainDeck.all.map(\.description)).count, TermTrainDeck.all.count)
    }

    func testTheDeckGrewWithTheCurriculum() {
        XCTAssertGreaterThanOrEqual(TermTrainDeck.all.count, 40)
        // Terms should be spread across many lessons, not clustered in a few.
        XCTAssertGreaterThanOrEqual(Set(TermTrainDeck.all.map(\.topic)).count, 25)
    }

    func testBoardLeansTowardsWeakTopics() {
        let epoch = Date(timeIntervalSince1970: 1_700_000_000)
        var records: [String: TopicMasteryRecord] = [:]
        // Master everything except one topic.
        let weakTopic = TermTrainDeck.all[0].topic
        for pair in TermTrainDeck.all where pair.topic != weakTopic {
            var record = TopicMasteryRecord(topic: pair.topic, now: epoch)
            for _ in 0..<6 { record.record(quality: 5, now: epoch) }
            records[pair.topic] = record
        }

        // A mastered topic to compare against, so the assertion is about the
        // weighting rather than about how many pairs the deck happens to hold.
        let masteredTopic = try! XCTUnwrap(
            TermTrainDeck.all.first { $0.topic != weakTopic }?.topic
        )

        var weakAppearances = 0
        var masteredAppearances = 0
        let rounds = 60
        for _ in 0..<rounds {
            let board = TermTrainDeck.board(records: records, now: epoch)
            if board.contains(where: { $0.topic == weakTopic }) { weakAppearances += 1 }
            if board.contains(where: { $0.topic == masteredTopic }) { masteredAppearances += 1 }
        }

        XCTAssertGreaterThan(
            weakAppearances, rounds / 2,
            "the untouched topic should be on most boards"
        )
        XCTAssertGreaterThan(
            weakAppearances, masteredAppearances * 3,
            "a weak topic must be drawn far more often than a mastered one"
        )
    }
}

final class WeakTopicDeduplicationTests: XCTestCase {
    private func makeStore() -> (TopicMasteryStore, String) {
        let suite = "crabrix.tests.\(UUID().uuidString)"
        return (TopicMasteryStore(defaults: UserDefaults(suiteName: suite)!), suite)
    }

    func testATopicListedTwiceIsRecommendedOnce() {
        let (store, suite) = makeStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        store.record(topic: "lifetimes", correct: false)
        store.record(topic: "traits", correct: false)

        // The card builds its list from the question bank plus the Term Train
        // deck, and both cover "lifetimes".
        let weakest = store.weakest(from: ["lifetimes", "traits", "lifetimes", "lifetimes"], limit: 4)
        XCTAssertEqual(weakest.map(\.topic).filter { $0 == "lifetimes" }.count, 1)
    }

    func testTheRealCardInputContainsRepeatsThatMustBeCollapsed() {
        // Guards the actual source of the bug rather than a synthetic list.
        let combined = RustQuestionBank.topics + TermTrainDeck.all.map(\.topic)
        XCTAssertGreaterThan(
            combined.count, Set(combined).count,
            "if this stops repeating, the dedupe is still correct but this test is moot"
        )
        XCTAssertEqual(
            TopicMasteryStore.deduplicated(combined).count,
            Set(combined).count
        )
    }

    func testDeduplicationKeepsTheFirstAppearanceOrder() {
        XCTAssertEqual(
            TopicMasteryStore.deduplicated(["b", "a", "b", "c", "a"]),
            ["b", "a", "c"]
        )
    }

    func testDueTopicsAlsoCollapseRepeats() {
        let (store, suite) = makeStore()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let due = store.dueTopics(from: ["ownership", "ownership", "borrowing"])
        XCTAssertEqual(due.count, Set(due).count)
    }
}
