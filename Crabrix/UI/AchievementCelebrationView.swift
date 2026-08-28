import SwiftUI
import UIKit

/// The unlock animation for one achievement.
///
/// Shown over whatever the learner was doing, because achievements are earned
/// in five different places and each of them should not have to draw its own.
struct AchievementCelebrationView: View {
    let achievement: CrabrixAchievement
    let onDismiss: () -> Void

    @State private var badgeScale = 0.35
    @State private var badgeRotation = -22.0
    @State private var ringScale = 0.6
    @State private var ringOpacity = 0.9
    @State private var raysProgress = 0.0
    @State private var textOffset = 22.0
    @State private var textOpacity = 0.0

    private static let rayCount = 14

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 18) {
                ZStack {
                    rays
                    expandingRing
                    badge
                }
                .frame(width: 190, height: 190)

                VStack(spacing: 7) {
                    Text("\(achievement.tier.title.uppercased()) UNLOCKED")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(achievement.tier.tint)
                    HStack(spacing: 8) {
                        Text(achievement.title)
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                        AchievementTierBadge(tier: achievement.tier)
                    }
                    Text(achievement.detail)
                        .font(.subheadline)
                        .foregroundStyle(CrabrixTheme.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .offset(y: textOffset)
                .opacity(textOpacity)

                Button("Nice", action: onDismiss)
                    .font(.headline)
                    .buttonStyle(.borderedProminent)
                    .tint(achievement.tier.tint)
                    .opacity(textOpacity)
            }
            .padding(30)
            .frame(maxWidth: 380)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(achievement.tier.tint.opacity(0.5), lineWidth: 1.5)
            }
            .shadow(color: .black.opacity(0.35), radius: 30, y: 14)
            .padding(28)
        }
        .foregroundStyle(CrabrixTheme.primary)
        .onAppear(perform: play)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(achievement.tier.title) unlocked: \(achievement.tieredTitle). \(achievement.detail)")
        .accessibilityAddTraits(.isModal)
    }

    private var badge: some View {
        Image(systemName: achievement.systemImage)
            .font(.system(size: 52, weight: .semibold))
            .foregroundStyle(CrabrixTheme.background)
            .frame(width: 108, height: 108)
            .background(
                LinearGradient(
                    colors: [achievement.tier.tint, CrabrixTheme.coral],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Circle()
            )
            .overlay { Circle().stroke(.white.opacity(0.45), lineWidth: 2) }
            .scaleEffect(badgeScale)
            .rotationEffect(.degrees(badgeRotation))
            .shadow(color: CrabrixTheme.amber.opacity(0.55), radius: 26)
    }

    private var expandingRing: some View {
        Circle()
            .stroke(achievement.tier.tint, lineWidth: 3)
            .frame(width: 118, height: 118)
            .scaleEffect(ringScale)
            .opacity(ringOpacity)
    }

    /// Rays are laid out by index rather than randomly so the burst renders the
    /// same every time and nothing depends on a random source.
    private var rays: some View {
        ForEach(0..<Self.rayCount, id: \.self) { index in
            let angle = Double(index) / Double(Self.rayCount) * 360
            let isLong = index.isMultiple(of: 2)
            Capsule()
                .fill(index.isMultiple(of: 3) ? CrabrixTheme.mint : achievement.tier.tint)
                .frame(width: 4, height: isLong ? 20 : 12)
                .offset(y: -60 - raysProgress * (isLong ? 34 : 24))
                .rotationEffect(.degrees(angle))
                .opacity(1 - raysProgress)
                .scaleEffect(0.4 + raysProgress * 0.8)
        }
    }

    private func play() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        withAnimation(.spring(response: 0.5, dampingFraction: 0.52)) {
            badgeScale = 1
            badgeRotation = 0
        }
        withAnimation(.easeOut(duration: 0.75)) {
            ringScale = 1.85
            ringOpacity = 0
            raysProgress = 1
        }
        withAnimation(.easeOut(duration: 0.42).delay(0.22)) {
            textOffset = 0
            textOpacity = 1
        }
    }
}

/// Presents queued unlocks one at a time, wherever they were earned.
private struct AchievementCelebrationModifier: ViewModifier {
    @ObservedObject var store: CrabrixProgressStore
    @State private var showing: CrabrixAchievement?

    func body(content: Content) -> some View {
        content
            .overlay {
                if let showing {
                    AchievementCelebrationView(achievement: showing, onDismiss: advance)
                        .transition(.opacity)
                        .zIndex(100)
                }
            }
            .animation(.easeInOut(duration: 0.22), value: showing?.id)
            .onChange(of: store.pendingCelebration.map(\.id)) { _, _ in
                if showing == nil { showing = store.pendingCelebration.first }
            }
            .onAppear {
                if showing == nil { showing = store.pendingCelebration.first }
            }
    }

    /// Drops the one just seen and moves to the next, so a burst of unlocks is
    /// shown in order instead of overwriting itself.
    private func advance() {
        guard let current = showing else { return }
        var queue = store.pendingCelebration
        queue.removeAll { $0.id == current.id }
        store.pendingCelebration = queue
        showing = queue.first
    }
}

extension View {
    /// Attach once, near the root: any achievement earned anywhere animates here.
    func achievementCelebrations(store: CrabrixProgressStore) -> some View {
        modifier(AchievementCelebrationModifier(store: store))
    }
}
