import Foundation

/// Everything the learner has done, in one place.
///
/// Rating is deliberately a single number earned across the whole app — lessons,
/// builds, practice, and Term Train all feed it — so it can later be reconciled
/// with a server without changing how any feature reports progress.
struct CrabrixProgressState: Codable, Equatable, Sendable {
    /// Bumped when the shape changes so an old payload is discarded rather than
    /// mis-decoded.
    static let currentVersion = 1

    var version = CrabrixProgressState.currentVersion
    var totalPoints = 0
    var lessonsCompleted = 0
    var buildsSucceeded = 0
    var linesChanged = 0
    var diagnosticsRepaired = 0
    var practiceRoundsPassed = 0
    var termTrainRuns = 0
    var termTrainPairsMatched = 0
    var termTrainBestStreak = 0
    var bestTimedPairsPerMinute = 0
    var packagesCompiled = 0
    var codeRecallRuns = 0
    var codeRecallBestLevel = 0
    var codeRecallLines = 0
    var charactersTyped = 0
    /// Exact algorithm patterns whose compiler-backed challenge was completed.
    /// A set makes mastery and its achievements naturally idempotent.
    var solvedAlgorithmPatternIDs: Set<String> = []
    /// Start of the day the last full run reward was paid, so the bonus is
    /// once daily and the rest of the rating comes from writing.
    var lastRunRewardDay: Date?
    var unlockedAchievementIDs: Set<String> = []
    var lastActiveAt: Date?
    /// Which achievement catalogue this state was last reconciled against, so
    /// a reshaped catalogue can be adopted without replaying old unlocks.
    var achievementCatalogVersion = 0
    /// Stable reward identities already applied locally. Counters and points
    /// can therefore be replayed after a relaunch without being paid twice.
    var processedEventKeys: Set<String> = []

    init() {}

    /// Decodes field by field, falling back to the default when a key is absent.
    ///
    /// The synthesised decoder throws on a missing key, and the store treats a
    /// decode failure as "start over". Adding one counter would therefore have
    /// silently wiped everyone's rating on update. This is the fix.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func int(_ key: CodingKeys) throws -> Int {
            try container.decodeIfPresent(Int.self, forKey: key) ?? 0
        }
        version = try container.decodeIfPresent(Int.self, forKey: .version)
            ?? CrabrixProgressState.currentVersion
        totalPoints = try int(.totalPoints)
        lessonsCompleted = try int(.lessonsCompleted)
        buildsSucceeded = try int(.buildsSucceeded)
        linesChanged = try int(.linesChanged)
        diagnosticsRepaired = try int(.diagnosticsRepaired)
        practiceRoundsPassed = try int(.practiceRoundsPassed)
        termTrainRuns = try int(.termTrainRuns)
        termTrainPairsMatched = try int(.termTrainPairsMatched)
        termTrainBestStreak = try int(.termTrainBestStreak)
        bestTimedPairsPerMinute = try int(.bestTimedPairsPerMinute)
        packagesCompiled = try int(.packagesCompiled)
        codeRecallRuns = try int(.codeRecallRuns)
        codeRecallBestLevel = try int(.codeRecallBestLevel)
        codeRecallLines = try int(.codeRecallLines)
        charactersTyped = try int(.charactersTyped)
        solvedAlgorithmPatternIDs = try container
            .decodeIfPresent(Set<String>.self, forKey: .solvedAlgorithmPatternIDs) ?? []
        lastRunRewardDay = try container.decodeIfPresent(Date.self, forKey: .lastRunRewardDay)
        achievementCatalogVersion = try int(.achievementCatalogVersion)
        processedEventKeys = try container
            .decodeIfPresent(Set<String>.self, forKey: .processedEventKeys) ?? []
        unlockedAchievementIDs = try container
            .decodeIfPresent(Set<String>.self, forKey: .unlockedAchievementIDs) ?? []
        lastActiveAt = try container.decodeIfPresent(Date.self, forKey: .lastActiveAt)
    }
}

/// Something the learner did that is worth points.
enum CrabrixProgressEvent: Sendable, Equatable {
    case lessonCompleted
    /// A successful run, paid by how much of the project actually changed
    /// since the last one rather than by a flat fee per tap.
    case buildSucceeded(CodeContribution)
    case diagnosticRepaired
    case practicePassed
    /// One Term Train run: how many pairs were matched, the longest streak, and
    /// the elapsed seconds when the run was timed.
    case termTrainFinished(pairs: Int, streak: Int, seconds: Int?)
    case packagesCompiled(Int)
    /// One Code Recall run: the deepest window rebuilt and the total lines.
    case codeRecallFinished(bestLevel: Int, linesRecalled: Int)
    /// Rust actually typed, which is where most rating now comes from.
    case codeTyped(characters: Int)

    var points: Int {
        switch self {
        case .lessonCompleted:
            return 120
        case let .buildSucceeded(contribution):
            return contribution.points
        case .diagnosticRepaired:
            return 60
        case .practicePassed:
            return 45
        case let .termTrainFinished(pairs, streak, seconds):
            // Matching pairs is the base; a clean streak and a fast timed run
            // are what separate a good run from a lucky one.
            let base = pairs * 10
            let streakBonus = streak >= 3 ? streak * 5 : 0
            var speedBonus = 0
            if let seconds, seconds > 0, pairs > 0 {
                speedBonus = max(0, 60 - seconds) / 2
            }
            return base + streakBonus + speedBonus
        case let .packagesCompiled(count):
            return count * 40
        case let .codeRecallFinished(bestLevel, linesRecalled):
            // Depth is what the game actually measures, so it is worth more per
            // unit than the raw number of lines tapped.
            return bestLevel * 30 + linesRecalled * 4
        case let .codeTyped(characters):
            // Roughly a point per line of Rust actually typed.
            return characters / 40
        }
    }
}

/// A rating tier, so the number means something at a glance.
struct CrabrixRank: Equatable, Sendable {
    let title: String
    let systemImage: String
    let threshold: Int
    let next: Int?

    var isMaximum: Bool { next == nil }

    /// 0…1 through the current tier.
    func progress(points: Int) -> Double {
        guard let next, next > threshold else { return 1 }
        return min(1, max(0, Double(points - threshold) / Double(next - threshold)))
    }

    static let ladder: [(title: String, systemImage: String, threshold: Int)] = [
        ("Newcomer", "circle.dashed", 0),
        ("Apprentice", "leaf.fill", 250),
        ("Builder", "hammer.fill", 750),
        ("Borrow Checker", "link.circle.fill", 1_800),
        ("Crate Author", "shippingbox.fill", 3_500),
        ("Rustacean", "crown.fill", 6_000),
    ]

    static func rank(for points: Int) -> CrabrixRank {
        let index = ladder.lastIndex { points >= $0.threshold } ?? 0
        let entry = ladder[index]
        let next = index + 1 < ladder.count ? ladder[index + 1].threshold : nil
        return CrabrixRank(
            title: entry.title,
            systemImage: entry.systemImage,
            threshold: entry.threshold,
            next: next
        )
    }
}

/// A single unlockable, defined by a predicate over the recorded state.
/// How far along a family of achievements the learner has climbed.
///
/// One badge that unlocks on the first try and never moves again says nothing
/// about someone who has done the same thing ten thousand times. Every family
/// therefore has a ladder, and the tier is what the badge actually reports.
enum AchievementTier: Int, CaseIterable, Comparable, Sendable {
    case bronze = 0
    case silver
    case gold
    case platinum
    case diamond

    static func < (lhs: AchievementTier, rhs: AchievementTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var title: String {
        switch self {
        case .bronze: "Bronze"
        case .silver: "Silver"
        case .gold: "Gold"
        case .platinum: "Platinum"
        case .diamond: "Diamond"
        }
    }

    var numeral: String {
        switch self {
        case .bronze: "I"
        case .silver: "II"
        case .gold: "III"
        case .platinum: "IV"
        case .diamond: "V"
        }
    }
}

/// One achievement at one tier.
struct CrabrixAchievement: Identifiable, Sendable {
    let familyID: String
    let tier: AchievementTier
    let title: String
    let detail: String
    let systemImage: String
    let target: Int
    let measure: @Sendable (CrabrixProgressState) -> Int

    /// Stable across releases: the persisted set is keyed on this.
    var id: String { "\(familyID).\(tier.rawValue)" }

    /// Title as it reads on a badge, e.g. "Photographic III".
    var tieredTitle: String { "\(title) \(tier.numeral)" }

    /// How far along, clamped to the target.
    func progress(_ state: CrabrixProgressState) -> (current: Int, target: Int) {
        (min(measure(state), target), target)
    }

    func isEarned(in state: CrabrixProgressState) -> Bool {
        measure(state) >= target
    }
}

/// A ladder of achievements measuring one thing.
struct CrabrixAchievementFamily: Identifiable, Sendable {
    let id: String
    let title: String
    let systemImage: String
    /// Ascending, one per tier, at most five.
    let thresholds: [Int]
    let measure: @Sendable (CrabrixProgressState) -> Int
    /// Reads the requirement for a threshold, e.g. "Finish 50 local builds."
    let requirement: @Sendable (Int) -> String
    let group: CrabrixAchievementGroup

    init(
        id: String,
        title: String,
        systemImage: String,
        thresholds: [Int],
        measure: @escaping @Sendable (CrabrixProgressState) -> Int,
        requirement: @escaping @Sendable (Int) -> String,
        group: CrabrixAchievementGroup = .general
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.thresholds = thresholds
        self.measure = measure
        self.requirement = requirement
        self.group = group
    }

    var achievements: [CrabrixAchievement] {
        zip(thresholds, AchievementTier.allCases).map { threshold, tier in
            CrabrixAchievement(
                familyID: id,
                tier: tier,
                title: title,
                detail: requirement(threshold),
                systemImage: systemImage,
                target: threshold,
                measure: measure
            )
        }
    }

    /// The highest tier earned so far, or nil when none is.
    func earnedTier(in state: CrabrixProgressState) -> AchievementTier? {
        achievements.last { $0.isEarned(in: state) }?.tier
    }

    /// The next rung, for a progress bar. Nil once the family is complete.
    func nextTarget(in state: CrabrixProgressState) -> CrabrixAchievement? {
        achievements.first { !$0.isEarned(in: state) }
    }
}

enum CrabrixAchievementGroup: String, Sendable {
    case general
    case algorithms
}

enum CrabrixAchievementCatalog {
    /// Bumped when the ladders change shape, so the store can adopt a new
    /// catalogue without replaying a decade of unlocks as fresh celebrations.
    static let version = 5

    private static let generalFamilies: [CrabrixAchievementFamily] = [
        CrabrixAchievementFamily(
            id: "builds",
            title: "It Compiles",
            systemImage: "play.circle.fill",
            thresholds: [1, 10, 50, 250, 1_000],
            measure: { $0.buildsSucceeded },
            requirement: { $0 == 1 ? "Run a Rust program locally." : "Finish \($0) successful local runs." }
        ),
        CrabrixAchievementFamily(
            id: "contribution",
            title: "Real Work",
            systemImage: "chart.line.uptrend.xyaxis",
            thresholds: [100, 1_000, 10_000, 50_000, 250_000],
            measure: { $0.linesChanged },
            requirement: { "Change \($0.formatted(.number)) lines of Rust across your projects." }
        ),
        CrabrixAchievementFamily(
            id: "lessons",
            title: "Coursework",
            systemImage: "graduationcap.fill",
            thresholds: [1, 5, 25, 75, 142],
            measure: { $0.lessonsCompleted },
            requirement: { $0 == 1 ? "Complete a lesson on the Rust path." : "Complete \($0) lessons." }
        ),
        CrabrixAchievementFamily(
            id: "diagnostics",
            title: "Borrow Checker Whisperer",
            systemImage: "bandage.fill",
            thresholds: [1, 10, 50, 200, 750],
            measure: { $0.diagnosticsRepaired },
            requirement: { $0 == 1 ? "Repair a compiler diagnostic." : "Repair \($0) compiler diagnostics." }
        ),
        CrabrixAchievementFamily(
            id: "practice",
            title: "Practice Makes Compilers",
            systemImage: "checkmark.seal.fill",
            thresholds: [1, 5, 25, 100, 500],
            measure: { $0.practiceRoundsPassed },
            requirement: { $0 == 1 ? "Pass a practice round." : "Pass \($0) practice rounds." }
        ),
        CrabrixAchievementFamily(
            id: "crates",
            title: "Dependency Wrangler",
            systemImage: "shippingbox.fill",
            thresholds: [1, 5, 20, 75, 250],
            measure: { $0.packagesCompiled },
            requirement: { $0 == 1 ? "Compile a crates.io package on device." : "Compile \($0) crates.io packages." }
        ),
        CrabrixAchievementFamily(
            id: "train-runs",
            title: "All Connected",
            systemImage: "link.circle.fill",
            thresholds: [1, 10, 50, 200, 1_000],
            measure: { $0.termTrainRuns },
            requirement: { $0 == 1 ? "Finish a Term Train run." : "Finish \($0) Term Train runs." }
        ),
        CrabrixAchievementFamily(
            id: "train-pairs",
            title: "Vocabulary Drilled",
            systemImage: "square.stack.3d.up.fill",
            thresholds: [10, 50, 250, 1_000, 5_000],
            measure: { $0.termTrainPairsMatched },
            requirement: { "Match \($0.formatted(.number)) Term Train pairs in total." }
        ),
        CrabrixAchievementFamily(
            id: "train-streak",
            title: "Perfect Chain",
            systemImage: "bolt.fill",
            thresholds: [3, 5, 10, 20, 40],
            measure: { $0.termTrainBestStreak },
            requirement: { "Match \($0) pairs in a row without a mistake." }
        ),
        CrabrixAchievementFamily(
            id: "train-speed",
            title: "Quick Recall",
            systemImage: "timer",
            thresholds: [6, 10, 15, 20, 30],
            measure: { $0.bestTimedPairsPerMinute },
            requirement: { "Match \($0) pairs a minute in a timed run." }
        ),
        CrabrixAchievementFamily(
            id: "recall-runs",
            title: "Photographic",
            systemImage: "eye.fill",
            thresholds: [1, 10, 50, 250, 1_000],
            measure: { $0.codeRecallRuns },
            requirement: { $0 == 1 ? "Finish a Code Recall run." : "Finish \($0) Code Recall runs." }
        ),
        CrabrixAchievementFamily(
            id: "recall-depth",
            title: "Deep Recall",
            systemImage: "brain.head.profile",
            // The window caps at CodeRecallDeck.maximumLines, so the top rung is
            // a perfect run rather than an unreachable number.
            thresholds: [3, 4, 5, 6, 8],
            measure: { $0.codeRecallBestLevel },
            requirement: { "Rebuild a \($0)-line snippet from memory." }
        ),
        CrabrixAchievementFamily(
            id: "recall-lines",
            title: "Total Recall",
            systemImage: "text.line.first.and.arrowtriangle.forward",
            thresholds: [25, 100, 500, 2_000, 10_000],
            measure: { $0.codeRecallLines },
            requirement: { "Recall \($0.formatted(.number)) lines of Rust in Code Recall." }
        ),
        CrabrixAchievementFamily(
            id: "typing",
            title: "Written by Hand",
            systemImage: "keyboard.fill",
            thresholds: [1_000, 10_000, 50_000, 200_000, 1_000_000],
            measure: { $0.charactersTyped },
            requirement: { "Type \($0.formatted(.number)) characters of Rust." }
        ),
        CrabrixAchievementFamily(
            id: "rating",
            title: "Rising Rustacean",
            systemImage: "crown.fill",
            // Deliberately the rank ladder: the badge and the rank agree.
            thresholds: [250, 750, 1_800, 3_500, 6_000],
            measure: { $0.totalPoints },
            requirement: { "Reach \($0.formatted(.number)) rating points." }
        ),
    ]

    private static let algorithmFamilies: [CrabrixAchievementFamily] = {
        let overall = CrabrixAchievementFamily(
            id: "algorithm-atlas",
            title: "Algorithm Atlas",
            systemImage: "point.3.connected.trianglepath.dotted",
            thresholds: [1, 25, 75, 150, 200],
            measure: { $0.solvedAlgorithmPatternIDs.count },
            requirement: {
                $0 == 1
                    ? "Solve a compiler-backed algorithm challenge."
                    : "Master \($0) unique algorithm patterns."
            },
            group: .algorithms
        )

        let categories = AlgorithmCourseCatalog.categories.map { category in
            let patternIDs = Set(category.patterns.map(\.id))
            return CrabrixAchievementFamily(
                id: "algorithm-\(category.id)",
                title: category.achievementTitle,
                systemImage: category.systemImage,
                thresholds: [1, 3, 5, 8, 10],
                measure: { state in
                    state.solvedAlgorithmPatternIDs.intersection(patternIDs).count
                },
                requirement: {
                    $0 == 1
                        ? "Solve one challenge in \(category.title)."
                        : "Solve \($0) unique challenges in \(category.title)."
                },
                group: .algorithms
            )
        }
        return [overall] + categories
    }()

    static let families: [CrabrixAchievementFamily] = generalFamilies + algorithmFamilies

    static let all: [CrabrixAchievement] = families.flatMap(\.achievements)

    static func family(id: String) -> CrabrixAchievementFamily? {
        families.first { $0.id == id }
    }

    static func achievement(id: String) -> CrabrixAchievement? {
        all.first { $0.id == id }
    }

    /// Achievements that are satisfied by `state` but not yet recorded.
    static func newlyEarned(in state: CrabrixProgressState) -> [CrabrixAchievement] {
        all.filter { $0.isEarned(in: state) && !state.unlockedAchievementIDs.contains($0.id) }
    }
}
