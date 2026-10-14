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
        return Self.rewardCalendar.startOfDay(for: now) > last
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
    func record(_ event: CrabrixProgressEvent, eventKey: String? = nil, now: Date = Date()) -> Bool {
        guard event.isValid else { return false }
        // The compiler drill has one identity even if a caller omits its key.
        let identity = eventKey ?? (event == .practicePassed ? "practice:compiler-borrow:first-completion" : nil)
        if let identity, hasApplied(identity) { return false }
        if event == .dailyRunBonus, !isFirstRunToday(now: now) { return false }
        var updated = state
        if let identity { Self.remember(identity, in: &updated) }
        updated.totalPoints += Self.rewardPoints(for: event, state: &updated, now: now)
        updated.lastActiveAt = now

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
            updated.lastRunRewardDay = Self.rewardCalendar.startOfDay(for: now)
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

    /// Source rewards and pending typing use the same content identity. Typing
    /// then deleting back to a previously paid revision cannot drain more points.
    @discardableResult
    func recordSourceRun(
        contribution: CodeContribution,
        sourceTreeHash: String,
        scoringSourceHash: String? = nil,
        typedCharacters: Int,
        now: Date = Date()
    ) -> Bool {
        guard CrabrixProgressEvent.buildSucceeded(contribution).isValid else { return false }
        let scoringHash = scoringSourceHash ?? sourceTreeHash
        let identity = CrabrixProgressState.buildRevisionKeyPrefix + scoringHash
        let alreadyPaid = hasApplied(CrabrixProgressState.buildRevisionKeyPrefix + sourceTreeHash)
        let recorded: Bool
        if alreadyPaid {
            // Carry an existing exact-byte reward into the normalized identity.
            var updated = state
            if !hasApplied(identity) {
                Self.remember(identity, in: &updated)
                state = updated
                persist()
            }
            recorded = false
        } else if contribution.changedLines > 0 {
            recorded = record(.buildSucceeded(contribution), eventKey: identity, now: now)
        } else {
            recorded = false
        }
        record(.dailyRunBonus, now: now)
        let payableTyping = min(typedCharacters, contribution.addedCharacters)
        if recorded, contribution.changedLines > 0, payableTyping > 0 {
            record(
                .codeTyped(characters: payableTyping),
                eventKey: "typing-revision:\(scoringHash)",
                now: now
            )
        }
        return recorded
    }

    private static var rewardCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    /// Limits apply inside the store, so relaunching or switching projects cannot
    /// bypass them. Curriculum first-completion rewards keep their full value.
    private static func rewardPoints(
        for event: CrabrixProgressEvent,
        state: inout CrabrixProgressState,
        now: Date
    ) -> Int {
        var points = max(0, event.points)
        let bucket: String
        let limit: Int
        switch event {
        case .buildSucceeded, .diagnosticRepaired, .packagesCompiled:
            bucket = "build"
            limit = 300
        case .codeTyped:
            bucket = "typing"
            limit = 500
        case let .termTrainFinished(_, _, seconds):
            bucket = "training"
            limit = 600
            let key = seconds == nil ? "term-train:practice" : "term-train:timed"
            let previous = state.trainingBestPoints[key, default: 0]
            state.trainingBestPoints[key] = max(previous, points)
            points = max(0, points - previous)
        case .codeRecallFinished:
            bucket = "training"
            limit = 600
            let key = "code-recall"
            let previous = state.trainingBestPoints[key, default: 0]
            state.trainingBestPoints[key] = max(previous, points)
            points = max(0, points - previous)
        default:
            return points
        }

        let day = rewardCalendar.startOfDay(for: now)
        if state.rewardDay == nil || day > state.rewardDay! {
            state.rewardDay = day
            state.dailyRewardPoints = [:]
        }
        // A backwards clock must not reopen an already spent budget.
        guard state.rewardDay == day else { return 0 }
        let paid = state.dailyRewardPoints[bucket, default: 0]
        let reward = min(points, max(0, limit - paid))
        state.dailyRewardPoints[bucket] = paid + reward
        return reward
    }

    /// Whether a reward identity has already been paid.
    private func hasApplied(_ eventKey: String) -> Bool {
        CrabrixProgressState.isBoundedEventKey(eventKey)
            ? state.recentBuildRevisions.contains { Self.canonicalRevisionKey($0) == Self.canonicalRevisionKey(eventKey) }
            : state.processedEventKeys.contains(eventKey)
    }

    /// Old build keys included the ProjectID. The source identity is global so
    /// cloning a project cannot buy another reward for the same code.
    private static func canonicalRevisionKey(_ key: String) -> String {
        guard key.hasPrefix(CrabrixProgressState.buildRevisionKeyPrefix),
              let revision = key.split(separator: ":").last
        else { return key }
        return CrabrixProgressState.buildRevisionKeyPrefix + revision
    }

    /// Records a reward identity so a relaunch cannot pay it twice.
    ///
    /// Curriculum identities are permanent. Source and typing revisions use a
    /// bounded cache; the persisted daily budget limits rewards after eviction.
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
