import SwiftUI

/// The single rating number, its tier, and how far the next tier is.
struct RatingSummaryCard: View {
    @ObservedObject var store: CrabrixProgressStore

    var body: some View {
        let rank = store.rank
        return VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 13) {
                Image(systemName: rank.systemImage)
                    .font(.title2)
                    .foregroundStyle(CrabrixTheme.amber)
                    .frame(width: 46, height: 46)
                    .background(CrabrixTheme.amber.opacity(0.14), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 2) {
                    Text("RATING")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(CrabrixTheme.muted)
                    Text(CrabrixPointsFormatter.string(store.state.totalPoints))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(rank.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(CrabrixTheme.mint)
                    Text("\(store.earnedAchievements.count)/\(CrabrixAchievementCatalog.all.count) achievements")
                        .font(.caption2.monospaced())
                        .foregroundStyle(CrabrixTheme.muted)
                }
            }

            if let next = rank.next {
                ProgressView(value: rank.progress(points: store.state.totalPoints))
                    .tint(CrabrixTheme.amber)
                Text("\(next - store.state.totalPoints) points to the next rank")
                    .font(.caption2)
                    .foregroundStyle(CrabrixTheme.muted)
            } else {
                Label("Top rank reached", systemImage: "crown.fill")
                    .font(.caption2)
                    .foregroundStyle(CrabrixTheme.amber)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .crabrixPanel(cornerRadius: 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Rating \(store.state.totalPoints) points, rank \(rank.title)"
        )
    }
}

/// One achievement, earned or still in progress.
extension AchievementTier {
    var tint: Color {
        switch self {
        case .bronze: Color(red: 0.80, green: 0.53, blue: 0.31)
        case .silver: Color(red: 0.72, green: 0.76, blue: 0.80)
        case .gold: CrabrixTheme.amber
        case .platinum: CrabrixTheme.blue
        case .diamond: CrabrixTheme.mint
        }
    }
}

/// The tier chip, e.g. a gold "III".
struct AchievementTierBadge: View {
    let tier: AchievementTier
    var isEarned = true

    var body: some View {
        Text(tier.numeral)
            .font(.system(size: 10, weight: .black, design: .rounded))
            .foregroundStyle(isEarned ? CrabrixTheme.background : CrabrixTheme.muted)
            .frame(width: 20, height: 20)
            .background(isEarned ? tier.tint : CrabrixTheme.border, in: Circle())
            .accessibilityLabel("\(tier.title) tier")
    }
}

/// One family: the tier reached, and how far the next rung is.
struct AchievementFamilyRow: View {
    let family: CrabrixAchievementFamily
    let state: CrabrixProgressState

    var body: some View {
        let earned = family.earnedTier(in: state)
        let next = family.nextTarget(in: state)
        let value = next?.progress(state)

        return HStack(spacing: 12) {
            Image(systemName: earned == nil ? "lock.fill" : family.systemImage)
                .font(.subheadline)
                .foregroundStyle(earned.map(\.tint) ?? CrabrixTheme.muted)
                .frame(width: 38, height: 38)
                .background(
                    (earned.map(\.tint) ?? CrabrixTheme.muted).opacity(0.14),
                    in: RoundedRectangle(cornerRadius: 11)
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(family.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(earned == nil ? CrabrixTheme.muted : CrabrixTheme.primary)
                    if let earned {
                        Text(earned.title.uppercased())
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundStyle(earned.tint)
                    }
                }

                // The whole ladder at a glance: filled rungs are earned.
                HStack(spacing: 4) {
                    ForEach(family.achievements) { rung in
                        AchievementTierBadge(
                            tier: rung.tier,
                            isEarned: state.unlockedAchievementIDs.contains(rung.id)
                        )
                    }
                }

                if let next, let value {
                    Text(next.detail)
                        .font(.caption2)
                        .foregroundStyle(CrabrixTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    ProgressView(value: Double(value.current), total: Double(value.target))
                        .tint(next.tier.tint)
                } else {
                    Label("Every tier earned", systemImage: "checkmark.seal.fill")
                        .font(.caption2.bold())
                        .foregroundStyle(CrabrixTheme.mint)
                }
            }

            Spacer(minLength: 0)

            if let value = next?.progress(state) {
                Text("\(value.current.formatted(.number))/\(value.target.formatted(.number))")
                    .font(.caption2.monospaced())
                    .foregroundStyle(CrabrixTheme.muted)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(earned: earned, next: next))
    }

    private func accessibilityLabel(
        earned: AchievementTier?,
        next: CrabrixAchievement?
    ) -> String {
        guard let earned else {
            let value = next?.progress(state)
            return "\(family.title), not started"
                + (value.map { ", \($0.current) of \($0.target)" } ?? "")
        }
        guard let next else { return "\(family.title), every tier earned" }
        let value = next.progress(state)
        return "\(family.title), \(earned.title) tier, \(value.current) of \(value.target) toward \(next.tier.title)"
    }
}

/// One tier, used where a single achievement is shown rather than a ladder.
struct AchievementRow: View {
    let achievement: CrabrixAchievement
    let state: CrabrixProgressState

    private var isEarned: Bool { state.unlockedAchievementIDs.contains(achievement.id) }

    var body: some View {
        let value = achievement.progress(state)
        return HStack(spacing: 12) {
            Image(systemName: isEarned ? achievement.systemImage : "lock.fill")
                .font(.subheadline)
                .foregroundStyle(isEarned ? achievement.tier.tint : CrabrixTheme.muted)
                .frame(width: 36, height: 36)
                .background(
                    (isEarned ? achievement.tier.tint : CrabrixTheme.muted).opacity(0.13),
                    in: RoundedRectangle(cornerRadius: 10)
                )
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(achievement.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(isEarned ? CrabrixTheme.primary : CrabrixTheme.muted)
                    AchievementTierBadge(tier: achievement.tier, isEarned: isEarned)
                }
                Text(achievement.detail)
                    .font(.caption2)
                    .foregroundStyle(CrabrixTheme.muted)
                    .lineLimit(2)
                if !isEarned, value.target > 1 {
                    ProgressView(value: Double(value.current), total: Double(value.target))
                        .tint(achievement.tier.tint)
                }
            }
            Spacer(minLength: 0)
            if isEarned {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(achievement.tier.tint)
            } else if value.target > 1 {
                Text("\(value.current)/\(value.target)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(CrabrixTheme.muted)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(achievement.tieredTitle), \(isEarned ? "earned" : "\(value.current) of \(value.target)")"
        )
    }
}

/// Every family, the ones with progress first.
struct AchievementsSection: View {
    @ObservedObject var store: CrabrixProgressStore

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label("ACHIEVEMENTS", systemImage: "rosette")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(CrabrixTheme.muted)
                Spacer()
                Text("\(store.earnedAchievements.count) of \(CrabrixAchievementCatalog.all.count) tiers")
                    .font(.caption2.monospaced())
                    .foregroundStyle(CrabrixTheme.muted)
            }
            VStack(spacing: 14) {
                ForEach(sortedGeneralFamilies) { family in
                    AchievementFamilyRow(family: family, state: store.state)
                }

                Divider().overlay(CrabrixTheme.border)

                HStack(spacing: 10) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .foregroundStyle(CrabrixTheme.indigo)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ALGORITHM ACHIEVEMENTS")
                            .font(.caption.monospaced().bold())
                            .foregroundStyle(CrabrixTheme.primary)
                        Text("\(store.state.solvedAlgorithmPatternIDs.count)/200 patterns · 20 independent methods")
                            .font(.caption2)
                            .foregroundStyle(CrabrixTheme.muted)
                    }
                }

                ForEach(sortedAlgorithmFamilies) { family in
                    AchievementFamilyRow(family: family, state: store.state)
                }
            }
            .padding(15)
            .crabrixPanel(cornerRadius: 16)
        }
    }

    /// Families with something earned come first, deepest first, so the ladder
    /// you are actually climbing is at the top.
    private var sortedGeneralFamilies: [CrabrixAchievementFamily] {
        sorted(CrabrixAchievementCatalog.families.filter { $0.group == .general })
    }

    private var sortedAlgorithmFamilies: [CrabrixAchievementFamily] {
        sorted(CrabrixAchievementCatalog.families.filter { $0.group == .algorithms })
    }

    private func sorted(_ families: [CrabrixAchievementFamily]) -> [CrabrixAchievementFamily] {
        families.sorted { lhs, rhs in
            let left = lhs.earnedTier(in: store.state)?.rawValue ?? -1
            let right = rhs.earnedTier(in: store.state)?.rawValue ?? -1
            return left == right ? lhs.title < rhs.title : left > right
        }
    }
}

/// What the learner is weakest at, and what practice will focus on next.
struct WeakTopicsCard: View {
    var store: TopicMasteryStore = .shared
    /// Tapping a topic should take you to the lesson it came from; without it
    /// the card names your weak spots and then leaves you to find them.
    var onSelect: ((String) -> Void)?

    private var weakest: [(topic: String, strength: Double)] {
        store.weakest(from: RustQuestionBank.topics + TermTrainDeck.all.map(\.topic), limit: 4)
    }

    private func title(for topic: String) -> String {
        RustCourseCatalog.lesson(id: topic)?.title ?? topic
    }

    /// Shown beside the title so two lessons with similar names are still
    /// tellable apart at a glance.
    private func courseTitle(for topic: String) -> String? {
        RustCourseCatalog.course(containingLessonID: topic)?.title.uppercased()
    }

    var body: some View {
        let summary = store.summary
        return VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label("WHAT TO PRACTISE", systemImage: "target")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(CrabrixTheme.muted)
                Spacer()
                if summary.seen > 0 {
                    Text("\(summary.strong) strong · \(summary.weak) weak")
                        .font(.caption2.monospaced())
                        .foregroundStyle(CrabrixTheme.muted)
                }
            }

            if weakest.isEmpty {
                Text("Answer a few practice questions and Crabrix will start bringing back whatever you get wrong.")
                    .font(.caption)
                    .foregroundStyle(CrabrixTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(weakest, id: \.topic) { entry in
                    Button {
                        onSelect?(entry.topic)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(title(for: entry.topic))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(CrabrixTheme.primary)
                                if let course = courseTitle(for: entry.topic) {
                                    Text(course)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(CrabrixTheme.muted)
                                }
                                Spacer()
                                Text("\(Int((entry.strength * 100).rounded()))%")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(CrabrixTheme.muted)
                                if onSelect != nil {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(CrabrixTheme.muted)
                                }
                            }
                            ProgressView(value: entry.strength)
                                .tint(entry.strength < 0.4 ? CrabrixTheme.coral : CrabrixTheme.amber)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(onSelect == nil)
                }
                Text("Practice and Term Train draw on these first, then space them out as they stick.")
                    .font(.caption2)
                    .foregroundStyle(CrabrixTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .crabrixPanel(cornerRadius: 16)
    }
}
