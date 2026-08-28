import Foundation
import SwiftUI

/// Records everything the learner earns and keeps it on disk.
///
/// One store is shared by every feature, so rating is genuinely "for all of it"
/// and a later online sync has a single source to reconcile.
@MainActor
final class CrabrixProgressStore: ObservableObject {
    @Published private(set) var state: CrabrixProgressState
    /// Achievements unlocked by the most recent event, for a one-shot banner.
    @Published var pendingCelebration: [CrabrixAchievement] = []

    private let defaults: UserDefaults
    private static let storageKey = "crabrix.progress.state.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        state = Self.load(from: defaults)
        adoptCatalogIfNeeded()
    }

    /// Reconciles a state written against an older achievement catalogue.
    ///
    /// Tiers changed every id, so without this every badge the learner already
    /// held would fire again as a fresh unlock — a parade of modal
    /// celebrations for work done weeks ago. Anything already satisfied is
    /// recorded silently instead, and only genuinely new rungs celebrate.
    private func adoptCatalogIfNeeded() {
        guard state.achievementCatalogVersion < CrabrixAchievementCatalog.version else { return }

        var updated = state
        // Ids from the previous catalogue no longer name anything; drop them so
        // the earned count reflects the ladders that actually exist.
        let known = Set(CrabrixAchievementCatalog.all.map(\.id))
        updated.unlockedAchievementIDs = updated.unlockedAchievementIDs.intersection(known)
        for achievement in CrabrixAchievementCatalog.all where achievement.isEarned(in: updated) {
            updated.unlockedAchievementIDs.insert(achievement.id)
        }
        updated.achievementCatalogVersion = CrabrixAchievementCatalog.version

        state = updated
        persist()
    }

    /// The highest tier reached in each family, for a compact summary.
    var earnedTiers: [(family: CrabrixAchievementFamily, tier: AchievementTier?)] {
        CrabrixAchievementCatalog.families.map { ($0, $0.earnedTier(in: state)) }
    }

    var rank: CrabrixRank { CrabrixRank.rank(for: state.totalPoints) }

    var earnedAchievements: [CrabrixAchievement] {
        CrabrixAchievementCatalog.all.filter { state.unlockedAchievementIDs.contains($0.id) }
    }

    var lockedAchievements: [CrabrixAchievement] {
        CrabrixAchievementCatalog.all.filter { !state.unlockedAchievementIDs.contains($0.id) }
    }

    /// Applies an event: adds its points, updates the counters it affects, then
    /// unlocks whatever that made true.
    func record(_ event: CrabrixProgressEvent) {
        var updated = state
        updated.totalPoints += event.points
        updated.lastActiveAt = Date()

        switch event {
        case .lessonCompleted:
            updated.lessonsCompleted += 1
        case let .buildSucceeded(contribution):
            updated.buildsSucceeded += 1
            updated.linesChanged += contribution.changedLines
        case .diagnosticRepaired:
            updated.diagnosticsRepaired += 1
        case .practicePassed:
            updated.practiceRoundsPassed += 1
        case let .termTrainFinished(pairs, streak, seconds):
            updated.termTrainRuns += 1
            updated.termTrainPairsMatched += pairs
            updated.termTrainBestStreak = max(updated.termTrainBestStreak, streak)
            if let seconds, seconds > 0, pairs > 0 {
                let perMinute = Int((Double(pairs) * 60 / Double(seconds)).rounded(.down))
                updated.bestTimedPairsPerMinute = max(updated.bestTimedPairsPerMinute, perMinute)
            }
        case let .packagesCompiled(count):
            updated.packagesCompiled += count
        case let .codeRecallFinished(bestLevel, linesRecalled):
            updated.codeRecallRuns += 1
            updated.codeRecallBestLevel = max(updated.codeRecallBestLevel, bestLevel)
            updated.codeRecallLines += linesRecalled
        }

        // Points can themselves unlock an achievement, so evaluate afterwards.
        let unlocked = CrabrixAchievementCatalog.newlyEarned(in: updated)
        for achievement in unlocked {
            updated.unlockedAchievementIDs.insert(achievement.id)
        }

        state = updated
        persist()
        if !unlocked.isEmpty { pendingCelebration = unlocked }
    }

    func clearCelebration() { pendingCelebration = [] }

    /// Resets everything. Only reachable from an explicit Settings action.
    func reset() {
        state = CrabrixProgressState()
        pendingCelebration = []
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static func load(from defaults: UserDefaults) -> CrabrixProgressState {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(CrabrixProgressState.self, from: data),
              decoded.version == CrabrixProgressState.currentVersion
        else {
            return CrabrixProgressState()
        }
        return decoded
    }
}

enum CrabrixPointsFormatter {
    static func string(_ points: Int) -> String {
        points >= 10_000
            ? "\(points / 1_000)K"
            : points.formatted(.number.grouping(.automatic))
    }
}
