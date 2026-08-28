import Foundation

/// What the learner has shown they know, per topic.
///
/// Scheduling follows SM-2, the SuperMemo algorithm that Anki and most spaced
/// repetition tools are built on: each correct answer stretches the interval by
/// an ease factor, and a wrong answer sends the topic back to the start. The
/// point is that weak topics come back soon and strong ones stop taking up time.
struct TopicMasteryRecord: Codable, Equatable, Sendable {
    let topic: String
    /// Consecutive correct answers. A miss resets this to zero.
    var repetitions: Int = 0
    /// SM-2 ease factor, never allowed below 1.3.
    var easeFactor: Double = 2.5
    /// Days until this topic should be seen again.
    var intervalDays: Double = 0
    var dueAt: Date
    var correct: Int = 0
    var incorrect: Int = 0
    var lastSeenAt: Date?

    static let minimumEase = 1.3

    init(topic: String, now: Date = Date()) {
        self.topic = topic
        dueAt = now
    }

    var attempts: Int { correct + incorrect }

    /// 0…1. An unseen topic sits at 0.5 so it is neither favoured nor buried.
    var strength: Double {
        guard attempts > 0 else { return 0.5 }
        let accuracy = Double(correct) / Double(attempts)
        // Repeated success matters as well as raw accuracy, so a topic answered
        // right five times in a row outranks one answered right once.
        let streak = min(Double(repetitions) / 5.0, 1.0)
        return min(1, max(0, accuracy * 0.7 + streak * 0.3))
    }

    func isDue(at moment: Date = Date()) -> Bool { dueAt <= moment }

    /// Applies one answer using SM-2.
    ///
    /// - Parameter quality: 0…5 as in SM-2. Below 3 counts as a lapse.
    mutating func record(quality: Int, now: Date = Date()) {
        let clamped = min(5, max(0, quality))
        lastSeenAt = now

        if clamped < 3 {
            incorrect += 1
            repetitions = 0
            intervalDays = 1
        } else {
            correct += 1
            repetitions += 1
            intervalDays = switch repetitions {
            case 1: 1
            case 2: 6
            default: intervalDays * easeFactor
            }
        }

        // The standard SM-2 ease update, floored so a topic never becomes
        // impossible to graduate from.
        let delta = 0.1 - Double(5 - clamped) * (0.08 + Double(5 - clamped) * 0.02)
        easeFactor = max(Self.minimumEase, easeFactor + delta)
        dueAt = now.addingTimeInterval(intervalDays * 86_400)
    }
}

/// Chooses what to ask next.
enum TopicScheduler {
    /// How much a topic wants to be picked right now.
    ///
    /// Overdue and weak topics score highest; a strong topic that is not due yet
    /// keeps a small floor so review never becomes entirely predictable.
    static func weight(
        for record: TopicMasteryRecord?,
        now: Date = Date()
    ) -> Double {
        guard let record else { return 3.0 } // never seen: worth introducing
        let weakness = 1.0 - record.strength

        // The floor is deliberately far below the unseen weight. As the
        // curriculum grows, a mastered topic that is not due yet has to become
        // cheap enough that the handful of weak ones still fill the board —
        // otherwise adding lessons quietly dilutes the whole schedule.
        var score = 0.08 + weakness * 3.0
        if record.isDue(at: now) {
            let overdueDays = now.timeIntervalSince(record.dueAt) / 86_400
            score += 1.5 + min(overdueDays, 14) * 0.25
        }
        return max(0.02, score)
    }

    /// Picks `count` topics, weighted by need and without repeats.
    ///
    /// - Parameter generator: injected so tests are deterministic.
    static func pick(
        count: Int,
        from topics: [String],
        records: [String: TopicMasteryRecord],
        now: Date = Date(),
        using generator: inout some RandomNumberGenerator
    ) -> [String] {
        guard count > 0 else { return [] }
        var pool = topics
        var chosen: [String] = []

        while chosen.count < count, !pool.isEmpty {
            let weights = pool.map { weight(for: records[$0], now: now) }
            let total = weights.reduce(0, +)
            guard total > 0 else {
                chosen.append(pool.removeFirst())
                continue
            }

            var roll = Double.random(in: 0..<total, using: &generator)
            var index = pool.indices.last ?? 0
            for candidate in pool.indices {
                roll -= weights[candidate]
                if roll < 0 {
                    index = candidate
                    break
                }
            }
            chosen.append(pool.remove(at: index))
        }
        return chosen
    }

    static func pick(
        count: Int,
        from topics: [String],
        records: [String: TopicMasteryRecord],
        now: Date = Date()
    ) -> [String] {
        var generator = SystemRandomNumberGenerator()
        return pick(count: count, from: topics, records: records, now: now, using: &generator)
    }
}

/// The persisted mastery table.
final class TopicMasteryStore: @unchecked Sendable {
    static let shared = TopicMasteryStore()

    private let lock = NSLock()
    private let defaults: UserDefaults
    private static let storageKey = "crabrix.mastery.v1"
    private var cache: [String: TopicMasteryRecord]?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var records: [String: TopicMasteryRecord] {
        lock.lock()
        defer { lock.unlock() }
        return loadLocked()
    }

    func record(for topic: String) -> TopicMasteryRecord? {
        lock.lock()
        defer { lock.unlock() }
        return loadLocked()[topic]
    }

    /// Records one answer and reschedules the topic.
    func record(topic: String, correct: Bool, now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        var current = loadLocked()
        var entry = current[topic] ?? TopicMasteryRecord(topic: topic, now: now)
        // Binary answers map onto SM-2's scale as a clean pass or a clear lapse.
        entry.record(quality: correct ? 4 : 1, now: now)
        current[topic] = entry
        cache = current
        persistLocked(current)
    }

    /// Topics that are due, weakest first.
    func dueTopics(from topics: [String], now: Date = Date()) -> [String] {
        let current = records
        return Self.deduplicated(topics)
            .filter { current[$0]?.isDue(at: now) ?? true }
            .sorted { lhs, rhs in
                let l = current[lhs]?.strength ?? 0.5
                let r = current[rhs]?.strength ?? 0.5
                return l == r ? lhs < rhs : l < r
            }
    }

    /// The topics the learner is weakest at, for a "needs work" summary.
    ///
    /// Callers assemble the list from several sources — the question bank and
    /// the Term Train deck both cover the same lessons — so the same topic
    /// arrives more than once. Without this the summary recommended one topic
    /// twice in a row, which reads as a bug because it is one.
    func weakest(from topics: [String], limit: Int = 5) -> [(topic: String, strength: Double)] {
        let current = records
        return Self.deduplicated(topics)
            .compactMap { topic -> (String, Double)? in
                guard let entry = current[topic], entry.attempts > 0 else { return nil }
                return (topic, entry.strength)
            }
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map { (topic: $0.0, strength: $0.1) }
    }

    var summary: (seen: Int, strong: Int, weak: Int) {
        let current = records.values.filter { $0.attempts > 0 }
        return (
            seen: current.count,
            strong: current.filter { $0.strength >= 0.75 }.count,
            weak: current.filter { $0.strength < 0.5 }.count
        )
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        cache = [:]
        defaults.removeObject(forKey: Self.storageKey)
    }

    /// Keeps first appearance order, which is the caller's priority order.
    static func deduplicated(_ topics: [String]) -> [String] {
        var seen = Set<String>()
        return topics.filter { seen.insert($0).inserted }
    }

    private func loadLocked() -> [String: TopicMasteryRecord] {
        if let cache { return cache }
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([String: TopicMasteryRecord].self, from: data)
        else {
            cache = [:]
            return [:]
        }
        cache = decoded
        return decoded
    }

    private func persistLocked(_ value: [String: TopicMasteryRecord]) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
