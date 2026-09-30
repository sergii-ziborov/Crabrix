import Foundation
import SwiftUI

/// Records everything the learner earns and keeps it on disk.
///
/// One store is shared by every feature, so rating is genuinely "for all of it"
/// and a later online sync has a single source to reconcile.
@MainActor
final class CrabrixProgressStore: ObservableObject {
    @Published private(set) var state: CrabrixProgressState
    @Published private(set) var achievementFamilies: [CrabrixAchievementFamily]
    @Published private(set) var atlasPatternCount: Int
    @Published private(set) var atlasMethodCount: Int
    /// Achievements unlocked by the most recent event, for a one-shot banner.
    @Published var pendingCelebration: [CrabrixAchievement] = []

    private let defaults: UserDefaults
    private static let storageKey = "crabrix.progress.state.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let loaded = Self.load(from: defaults)
        state = loaded
        achievementFamilies = CrabrixAchievementCatalog.families(for: loaded.achievementMethods)
        atlasPatternCount = loaded.achievementMethods.reduce(0) { $0 + $1.patternIDs.count }
        atlasMethodCount = loaded.achievementMethods.count
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
        // Drop obsolete pre-tier ids. Keep earned Atlas method tiers while
        // their signed metadata is being loaded from the transition pack.
        let known = Set(allAchievements.map(\.id))
        updated.unlockedAchievementIDs = updated.unlockedAchievementIDs.filter {
            known.contains($0) || ($0.hasPrefix("algorithm-") && Self.isTieredAchievementID($0))
        }
        for achievement in allAchievements where achievement.isEarned(in: updated) {
            updated.unlockedAchievementIDs.insert(achievement.id)
        }
        updated.achievementCatalogVersion = CrabrixAchievementCatalog.version

        state = updated
        persist()
    }

    /// Switch method achievements to the signed installed Atlas metadata.
    /// Any already satisfied rung is recorded silently, so loading or updating
    /// a pack never creates a second reward celebration.
    func configureAcademy(repository: InstalledCourseRepository) {
        let methods = repository.algorithmMethods()
        guard !methods.isEmpty else { return }
        let currentIDs = Set(methods.map(\.id))
        let earnedPrevious = state.achievementMethods.filter { method in
            !currentIDs.contains(method.id)
                && state.unlockedAchievementIDs.contains {
                    $0.hasPrefix("algorithm-\(method.id).")
                }
        }
        let preservedMethods = methods + earnedPrevious
        atlasPatternCount = methods.reduce(0) { $0 + $1.patternIDs.count }
        atlasMethodCount = methods.count
        achievementFamilies = CrabrixAchievementCatalog.families(for: preservedMethods)

        var updated = state
        updated.achievementMethods = preservedMethods
        for achievement in allAchievements where achievement.isEarned(in: updated) {
            updated.unlockedAchievementIDs.insert(achievement.id)
        }
        if updated != state {
            state = updated
            persist()
        }
    }

    var allAchievements: [CrabrixAchievement] {
        achievementFamilies.flatMap(\.achievements)
    }

    /// The highest tier reached in each family, for a compact summary.
    var earnedTiers: [(family: CrabrixAchievementFamily, tier: AchievementTier?)] {
        achievementFamilies.map { ($0, $0.awardedTier(in: state)) }
    }

    var rank: CrabrixRank { CrabrixRank.rank(for: state.totalPoints) }

    /// Whether the day's run reward is still unclaimed.
    func isFirstRunToday(now: Date = Date()) -> Bool {
        guard let last = state.lastRunRewardDay else { return true }
        return !Calendar.current.isDate(last, inSameDayAs: now)
    }

    var earnedAchievements: [CrabrixAchievement] {
        allAchievements.filter { state.unlockedAchievementIDs.contains($0.id) }
    }

    var lockedAchievements: [CrabrixAchievement] {
        allAchievements.filter { !state.unlockedAchievementIDs.contains($0.id) }
    }

    /// Applies an event: adds its points, updates the counters it affects, then
    /// unlocks whatever that made true.
    @discardableResult
    func record(_ event: CrabrixProgressEvent, eventKey: String? = nil) -> Bool {
        if let eventKey, hasApplied(eventKey) { return false }
        var updated = state
        if let eventKey { Self.remember(eventKey, in: &updated) }
        updated.totalPoints += event.points
        updated.lastActiveAt = Date()

        switch event {
        case .lessonCompleted:
            updated.lessonsCompleted += 1
            updated.rustLessonsCompleted += 1
        case .algorithmStudyStepCompleted:
            updated.lessonsCompleted += 1
            updated.algorithmStudySteps += 1
        case .algorithmChallengeSolved:
            // Mastery of the pattern itself is recorded separately, by id, so
            // this only moves the curriculum counters.
            updated.lessonsCompleted += 1
        case let .buildSucceeded(contribution):
            updated.buildsSucceeded += 1
            updated.linesChanged += contribution.changedLines
        case .dailyRunBonus:
            updated.lastRunRewardDay = Calendar.current.startOfDay(for: Date())
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
        case let .codeTyped(characters):
            updated.charactersTyped += characters
        case let .codeRecallFinished(bestLevel, linesRecalled):
            updated.codeRecallRuns += 1
            updated.codeRecallBestLevel = max(updated.codeRecallBestLevel, bestLevel)
            updated.codeRecallLines += linesRecalled
        }

        // Points can themselves unlock an achievement, so evaluate afterwards.
        let unlocked = allAchievements.filter {
            $0.isEarned(in: updated) && !updated.unlockedAchievementIDs.contains($0.id)
        }
        for achievement in unlocked {
            updated.unlockedAchievementIDs.insert(achievement.id)
        }

        state = updated
        persist()
        if !unlocked.isEmpty {
            let pendingIDs = Set(pendingCelebration.map(\.id))
            pendingCelebration += unlocked.filter { !pendingIDs.contains($0.id) }
        }
        return true
    }

    func clearCelebration() { pendingCelebration = [] }

    /// Whether a reward identity has already been paid.
    private func hasApplied(_ eventKey: String) -> Bool {
        CrabrixProgressState.isBoundedEventKey(eventKey)
            ? state.recentBuildRevisions.contains(eventKey)
            : state.processedEventKeys.contains(eventKey)
    }

    /// Records a reward identity so a relaunch cannot pay it twice.
    ///
    /// Lesson, pattern, crate, and repair identities are finite, so they are
    /// kept for good. Source revisions are not: they are held in a bounded
    /// window instead, which is far longer than any plausible farming loop and
    /// keeps the persisted state from growing with every edit.
    private static func remember(_ eventKey: String, in state: inout CrabrixProgressState) {
        guard CrabrixProgressState.isBoundedEventKey(eventKey) else {
            state.processedEventKeys.insert(eventKey)
            return
        }
        state.recentBuildRevisions.append(eventKey)
        let overflow = state.recentBuildRevisions.count
            - CrabrixProgressState.maximumRecentBuildRevisions
        if overflow > 0 { state.recentBuildRevisions.removeFirst(overflow) }
    }

    /// Records mastery only once per exact pattern. Rating already comes from
    /// the challenge lesson, so this method unlocks solution-method ladders without
    /// creating a second reward that could be farmed by rerunning the project.
    @discardableResult
    func recordAlgorithmSolved(challenge: AlgorithmChallenge) -> Bool {
        // The caller supplies a challenge from a verified CourseSession or
        // InstalledCourseRepository. Reward identity is the stable pattern ID,
        // so a pack update or reinstallation cannot pay it twice.
        let patternID = challenge.patternID
        guard !patternID.isEmpty,
              !state.solvedAlgorithmPatternIDs.contains(patternID)
        else { return false }

        var updated = state
        updated.solvedAlgorithmPatternIDs.insert(patternID)
        updated.lastActiveAt = Date()
        let unlocked = allAchievements.filter {
            $0.isEarned(in: updated) && !updated.unlockedAchievementIDs.contains($0.id)
        }
        for achievement in unlocked {
            updated.unlockedAchievementIDs.insert(achievement.id)
        }

        state = updated
        persist()
        if !unlocked.isEmpty {
            let pendingIDs = Set(pendingCelebration.map(\.id))
            pendingCelebration += unlocked.filter { !pendingIDs.contains($0.id) }
        }
        return true
    }

    /// Resets everything. Only reachable from an explicit Settings action.
    func reset() {
        state = CrabrixProgressState()
        achievementFamilies = CrabrixAchievementCatalog.families
        atlasPatternCount = 0
        atlasMethodCount = 0
        pendingCelebration = []
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static func isTieredAchievementID(_ id: String) -> Bool {
        guard let separator = id.lastIndex(of: "."), separator > id.startIndex else {
            return false
        }
        return Int(id[id.index(after: separator)...]).map {
            (0..<AchievementTier.allCases.count).contains($0)
        } ?? false
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
