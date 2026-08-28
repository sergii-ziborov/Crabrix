import Foundation
import SwiftUI

/// Owns the health and energy pool and keeps it on disk.
///
/// Kept beside `CrabrixProgressStore` rather than inside it: vitals change many
/// times an hour where rating changes rarely, and a separate key means adding
/// this feature does not invalidate progress people already earned.
@MainActor
final class CrabrixVitalsStore: ObservableObject {
    @Published private(set) var state: CrabrixVitalsState
    /// The most recent outcome, for a short explanatory toast.
    @Published var lastOutcome: VitalsOutcome?
    /// Rating drives capacity, so the store is told when it changes.
    @Published private(set) var points: Int

    private let defaults: UserDefaults
    private let now: () -> Date
    private static let storageKey = "crabrix.vitals.v1"
    private static let pointsKey = "crabrix.vitals.points"

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        let loaded = Self.load(from: defaults)
        let storedPoints = defaults.integer(forKey: Self.pointsKey)
        let capacity = VitalsCapacity.forPoints(storedPoints)
        points = storedPoints
        state = (loaded ?? Self.fresh(capacity: capacity)).regenerated(to: now(), capacity: capacity)
    }

    var capacity: VitalsCapacity { VitalsCapacity.forPoints(points) }

    var health: Int { state.healthPoints }
    var energy: Int { state.energyPoints }
    var isOutOfHealth: Bool { state.healthPoints <= 0 }
    var isOutOfEnergy: Bool { state.energyPoints < CrabrixVitalsState.energyPerLessonPage }
    /// Lessons pause when either pool runs out. Training never does.
    var isLessonBlocked: Bool { isOutOfHealth || isOutOfEnergy }

    var shieldsRemaining: Int {
        let calendar = Calendar.current
        guard let day = state.shieldDay, calendar.isDate(day, inSameDayAs: now()) else {
            return capacity.dailyShields
        }
        return max(0, capacity.dailyShields - state.shieldsUsed)
    }

    var secondsToNextHealth: TimeInterval? {
        CrabrixVitalsState.secondsToNextPoint(
            value: state.health,
            maximum: capacity.maxHealth,
            perHour: capacity.healthPerHour
        )
    }

    var secondsToNextEnergy: TimeInterval? {
        CrabrixVitalsState.secondsToNextPoint(
            value: state.energy,
            maximum: capacity.maxEnergy,
            perHour: capacity.energyPerHour
        )
    }

    /// Brings the pool up to date. Cheap, and safe to call on every appearance.
    func refresh(points newPoints: Int? = nil) {
        if let newPoints, newPoints != points {
            points = newPoints
            defaults.set(newPoints, forKey: Self.pointsKey)
        }
        state = state.regenerated(to: now(), capacity: capacity)
        persist()
    }

    /// Charges for reading one lesson page. A page already paid for is free.
    @discardableResult
    func startLessonPage(lessonID: String, page: Int) -> VitalsOutcome {
        refresh()
        var updated = state
        let outcome = updated.chargeLessonPage("\(lessonID)#\(page)")
        state = updated
        persist()
        publish(outcome)
        return outcome
    }

    /// Whether a page can be opened without spending what is not there.
    func canStartLessonPage(lessonID: String, page: Int) -> Bool {
        state.canStartLessonPage("\(lessonID)#\(page)")
    }

    @discardableResult
    func recordAnswer(correct: Bool) -> VitalsOutcome {
        refresh()
        var updated = state
        let outcome = correct
            ? updated.recordCorrect(capacity: capacity)
            : updated.recordMistake(now: now(), capacity: capacity)
        state = updated
        persist()
        publish(outcome)
        return outcome
    }

    /// Training is deliberately unlimited: it costs nothing and cannot be
    /// blocked, so there is always a way to keep learning while health returns.
    func recordTrainingAnswer(correct: Bool) {
        refresh()
        var updated = state
        if correct { _ = updated.recordCorrect(capacity: capacity) } else { updated.flowStreak = 0 }
        state = updated
        persist()
    }

    func clearOutcome() { lastOutcome = nil }

    func reset() {
        state = Self.fresh(capacity: capacity)
        lastOutcome = nil
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func publish(_ outcome: VitalsOutcome) {
        guard outcome != .free else { return }
        lastOutcome = outcome
    }

    private static func fresh(capacity: VitalsCapacity) -> CrabrixVitalsState {
        CrabrixVitalsState(
            health: Double(capacity.maxHealth),
            energy: Double(capacity.maxEnergy)
        )
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static func load(from defaults: UserDefaults) -> CrabrixVitalsState? {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(CrabrixVitalsState.self, from: data),
              decoded.version == CrabrixVitalsState.currentVersion
        else { return nil }
        return decoded
    }
}

enum VitalsFormatter {
    /// "4 min" / "1 h 12 min", for the "next heart in…" label.
    static func countdown(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(max(1, total))s" }
        let minutes = total / 60
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }
}
