import Foundation

/// How much health and energy a learner has, and how fast it comes back.
///
/// Both scale with rating rather than being fixed: a higher rank means a bigger
/// pool *and* faster recovery, so the number on the profile buys something real
/// instead of only reading well. That is the part Duolingo's hearts do not do.
struct VitalsCapacity: Equatable, Sendable {
    let maxHealth: Int
    let maxEnergy: Int
    /// Points restored per hour.
    let healthPerHour: Double
    let energyPerHour: Double
    /// Mistakes absorbed per day before health is actually spent.
    let dailyShields: Int

    /// - Parameter rankIndex: position on `CrabrixRank.ladder`, 0 upwards.
    static func forRank(index rankIndex: Int) -> VitalsCapacity {
        let tier = max(0, min(rankIndex, CrabrixRank.ladder.count - 1))
        // Regeneration outruns the bigger pool on purpose: rank has to make a
        // full refill *faster*, not just hold more. Scaling the rate more
        // slowly than the capacity would quietly punish a promotion.
        return VitalsCapacity(
            maxHealth: 5 + tier * 2,
            maxEnergy: 30 + tier * 10,
            healthPerHour: 2.0 + Double(tier) * 0.9,
            energyPerHour: 10.0 + Double(tier) * 4.2,
            dailyShields: tier >= 2 ? 2 : 1
        )
    }

    static func forPoints(_ points: Int) -> VitalsCapacity {
        let rank = CrabrixRank.rank(for: points)
        let index = CrabrixRank.ladder.firstIndex { $0.threshold == rank.threshold } ?? 0
        return forRank(index: index)
    }

    /// Minutes to recover one health point, for the "back in N min" label.
    var minutesPerHealth: Double { healthPerHour > 0 ? 60 / healthPerHour : .infinity }
    var minutesPerEnergy: Double { energyPerHour > 0 ? 60 / energyPerHour : .infinity }
}

/// What one action did to the learner's vitals, so the UI can explain it.
enum VitalsOutcome: Equatable, Sendable {
    /// The action was free — an already-paid page, or a training screen.
    case free
    case spent(energy: Int)
    case damaged(health: Int)
    /// A mistake a daily shield absorbed, so no health was lost.
    case shielded
    /// A run of correct answers handed some energy back.
    case refunded(energy: Int)
    /// Not enough of the resource to proceed.
    case blocked
}

/// The persisted pool. Values are fractional so a partial hour of regeneration
/// is never rounded away and then lost.
struct CrabrixVitalsState: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version = CrabrixVitalsState.currentVersion
    var health: Double = 5
    var energy: Double = 30
    var updatedAt = Date()
    /// Lesson pages already paid for. Re-reading one is always free.
    var chargedPageIDs: Set<String> = []
    /// Correct answers in a row, which earn energy back.
    var flowStreak = 0
    var shieldsUsed = 0
    var shieldDay: Date?

    /// Energy charged per lesson page the first time it is read.
    static let energyPerLessonPage = 2
    /// Correct answers needed in a row before energy is handed back.
    static let flowStreakForRefund = 3

    /// Applies elapsed-time regeneration up to `now`.
    ///
    /// A clock that moved backwards regenerates nothing rather than draining,
    /// which is the safe direction to fail in.
    func regenerated(to now: Date, capacity: VitalsCapacity) -> CrabrixVitalsState {
        var next = self
        let hours = max(0, now.timeIntervalSince(updatedAt) / 3_600)
        next.health = min(Double(capacity.maxHealth), health + hours * capacity.healthPerHour)
        next.energy = min(Double(capacity.maxEnergy), energy + hours * capacity.energyPerHour)
        // A pool already over capacity (the rank dropped, or a gift) is left
        // alone rather than clipped, so nothing the learner earned disappears.
        next.health = max(next.health, health > Double(capacity.maxHealth) ? health : next.health)
        next.energy = max(next.energy, energy > Double(capacity.maxEnergy) ? energy : next.energy)
        next.updatedAt = now
        return next
    }

    /// Whole points, which is what the UI shows.
    var healthPoints: Int { Int(health.rounded(.down)) }
    var energyPoints: Int { Int(energy.rounded(.down)) }

    func canStartLessonPage(_ pageID: String) -> Bool {
        chargedPageIDs.contains(pageID)
            || energy >= Double(Self.energyPerLessonPage)
    }

    /// Charges for a lesson page, once ever.
    mutating func chargeLessonPage(_ pageID: String) -> VitalsOutcome {
        guard !chargedPageIDs.contains(pageID) else { return .free }
        guard energy >= Double(Self.energyPerLessonPage) else { return .blocked }
        energy -= Double(Self.energyPerLessonPage)
        chargedPageIDs.insert(pageID)
        return .spent(energy: Self.energyPerLessonPage)
    }

    /// Applies a wrong answer, spending a daily shield first if one is left.
    mutating func recordMistake(now: Date, capacity: VitalsCapacity) -> VitalsOutcome {
        flowStreak = 0
        resetShieldsIfNewDay(now: now)
        if shieldsUsed < capacity.dailyShields {
            shieldsUsed += 1
            return .shielded
        }
        guard health >= 1 else {
            health = 0
            return .blocked
        }
        health -= 1
        return .damaged(health: 1)
    }

    /// Applies a correct answer. A run of them hands energy back, so someone
    /// who actually knows the material is never gated by the meter.
    mutating func recordCorrect(capacity: VitalsCapacity) -> VitalsOutcome {
        flowStreak += 1
        guard flowStreak % Self.flowStreakForRefund == 0 else { return .free }
        guard energy < Double(capacity.maxEnergy) else { return .free }
        energy = min(Double(capacity.maxEnergy), energy + 1)
        return .refunded(energy: 1)
    }

    private mutating func resetShieldsIfNewDay(now: Date) {
        let calendar = Calendar.current
        if let shieldDay, calendar.isDate(shieldDay, inSameDayAs: now) { return }
        shieldDay = now
        shieldsUsed = 0
    }

    /// Seconds until the next whole point arrives, or nil when already full.
    static func secondsToNextPoint(
        value: Double,
        maximum: Int,
        perHour: Double
    ) -> TimeInterval? {
        guard value < Double(maximum), perHour > 0 else { return nil }
        let missing = 1 - (value - value.rounded(.down))
        let needed = missing == 0 ? 1 : missing
        return needed / perHour * 3_600
    }
}
