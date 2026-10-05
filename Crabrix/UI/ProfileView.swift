#if CRABRIX_SOCIAL
import GameKit
#endif
import PhotosUI
import SwiftUI

/// The player's profile: rating and achievements.
///
/// Local rating and achievements work without an account. Game Center is an
/// optional Apple-hosted copy of selected scores and milestones.
struct ProfileView: View {
    @EnvironmentObject private var progress: CrabrixProgressStore
    @EnvironmentObject private var academy: AcademyContentStore
    let completedLessonIDs: Set<String>
    #if CRABRIX_SOCIAL
    @EnvironmentObject private var gameCenter: GameCenterService
    #endif

    @StateObject private var avatarStore = LocalAvatarStore()

    #if CRABRIX_SOCIAL
    @State private var gameCenterPanel: GameCenterPanel?

    private enum GameCenterPanel: Identifiable {
        case leaderboard
        case achievements
        var id: String { self == .leaderboard ? "leaderboard" : "achievements" }
    }
    #endif
    @State private var selectedAvatarItem: PhotosPickerItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                identityCard
                statsCard
                AchievementsSection(store: progress)
            }
            .padding(22)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
        }
        .background(CrabrixTheme.background.ignoresSafeArea())
        .foregroundStyle(CrabrixTheme.primary)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Avatar",
            isPresented: Binding(
                get: { avatarStore.errorMessage != nil },
                set: { if !$0 { avatarStore.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { avatarStore.errorMessage = nil }
        } message: {
            Text(avatarStore.errorMessage ?? "The image could not be loaded.")
        }
        .task(id: selectedAvatarItem) {
            guard let selectedAvatarItem else { return }
            do {
                guard let data = try await selectedAvatarItem.loadTransferable(
                    type: Data.self
                ) else {
                    avatarStore.errorMessage = "The selected image could not be read."
                    return
                }
                await avatarStore.importImageData(data)
            } catch {
                avatarStore.errorMessage = error.localizedDescription
            }
        }
        #if CRABRIX_SOCIAL
        .sheet(item: $gameCenterPanel) { panel in
            GameCenterSheet(
                controller: panel == .leaderboard
                    ? gameCenter.makeLeaderboardViewController()
                    : gameCenter.makeAchievementsViewController(),
                onDismiss: { gameCenterPanel = nil }
            )
            .ignoresSafeArea()
        }
        .task {
            if gameCenter.isEnabled {
                gameCenter.authenticate()
                await gameCenter.submit(state: progress.state)
            }
        }
        #endif
    }

    private var identityCard: some View {
        let hasCustomAvatar = avatarStore.hasCustomAvatar
        return VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 15) {
                avatarPicker
                VStack(alignment: .leading, spacing: 3) {
                    Text(playerTitle)
                        .font(.title3.bold())
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(CrabrixTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                #if CRABRIX_SOCIAL
                if gameCenter.isEnabled, let rank = gameCenter.globalRank {
                    VStack(spacing: 1) {
                        Text("#\(rank)")
                            .font(.title3.bold().monospacedDigit())
                            .foregroundStyle(CrabrixTheme.amber)
                        Text("GLOBAL")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(CrabrixTheme.muted)
                    }
                }
                #endif
            }

            HStack(spacing: 10) {
                PhotosPicker(
                    selection: $selectedAvatarItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label(
                        hasCustomAvatar ? "Change photo" : "Choose photo",
                        systemImage: "photo.on.rectangle"
                    )
                }
                .buttonStyle(.bordered)

                if hasCustomAvatar {
                    Button(role: .destructive) {
                        avatarStore.removeAvatar()
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }

                if avatarStore.isImporting {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .font(.caption.bold())

            #if CRABRIX_SOCIAL
            Toggle(isOn: Binding(
                get: { gameCenter.isEnabled },
                set: { gameCenter.setEnabled($0) }
            )) {
                Label("Game Center", systemImage: "gamecontroller.fill")
                    .font(.subheadline.bold())
            }
            .tint(CrabrixTheme.mint)
            .accessibilityHint("Share your rating and selected achievements with Apple's Game Center. Local progress always remains on this device.")

            if gameCenter.isEnabled, gameCenter.isSignedIn {
                HStack(spacing: 10) {
                    Button { gameCenterPanel = .leaderboard } label: {
                        Label("Leaderboard", systemImage: "list.number")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(CrabrixTheme.amber)

                    Button { gameCenterPanel = .achievements } label: {
                        Label("Game Center", systemImage: "rosette")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .font(.subheadline.bold())
                Text("Your rating and selected achievements sync through Apple Game Center.")
                    .font(.caption)
                    .foregroundStyle(CrabrixTheme.muted)
            } else if gameCenter.isEnabled {
                Text(gameCenterStatusText)
                    .font(.caption)
                    .foregroundStyle(CrabrixTheme.muted)
                Button("Try Game Center again") { gameCenter.authenticate() }
                    .font(.caption.bold())
                    .disabled(gameCenter.status == .authenticating)
            } else {
                localStorageNote
            }
            #else
            localStorageNote
            #endif

            Divider().overlay(CrabrixTheme.border)
            combinedProgress
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .crabrixPanel(cornerRadius: 16)
    }

    private var localStorageNote: some View {
        Label(
            "Your rating, achievements, and progress are saved on this device.",
            systemImage: "internaldrive.fill"
        )
        .font(.caption)
        .foregroundStyle(CrabrixTheme.muted)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var playerTitle: String {
        #if CRABRIX_SOCIAL
        gameCenter.isSignedIn ? gameCenter.playerName : "Playing offline"
        #else
        "Playing offline"
        #endif
    }

    private var avatarPicker: some View {
        let customImage = avatarStore.image
        #if CRABRIX_SOCIAL
        let gameCenterImage = gameCenter.isEnabled
            ? gameCenter.photo
            : nil
        #else
        let gameCenterImage: UIImage? = nil
        #endif
        let hasCustomAvatar = customImage != nil
        return PhotosPicker(
            selection: $selectedAvatarItem,
            matching: .images,
            photoLibrary: .shared()
        ) {
            ProfileAvatarPickerLabel(
                customImage: customImage,
                gameCenterImage: gameCenterImage
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            hasCustomAvatar ? "Change profile photo" : "Choose profile photo"
        )
    }

    private var combinedProgress: some View {
        let rank = progress.rank
        let courses = academy.repository?.courses ?? []
        let lessonIDs = Set(courses.flatMap { $0.units.flatMap(\.lessons).map(\.id) })
        let lessonTotal = academy.repository?.learningTotals().installedLessons ?? 0
        let lessonCompleted = completedLessonIDs.intersection(lessonIDs).count
        let lessonProgress = lessonTotal == 0
            ? 0
            : Double(lessonCompleted) / Double(lessonTotal)

        return VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                ProfileMetric(
                    title: "RATING",
                    value: CrabrixPointsFormatter.string(progress.state.totalPoints),
                    detail: rank.title,
                    systemImage: rank.systemImage,
                    tint: CrabrixTheme.amber,
                    progress: rank.progress(points: progress.state.totalPoints)
                )

                Divider()

                ProfileMetric(
                    title: "INSTALLED LESSONS",
                    value: lessonTotal == 0 ? "—" : "\(lessonCompleted)/\(lessonTotal)",
                    detail: "\(progress.state.lessonsCompleted) lifetime completions",
                    systemImage: "map.fill",
                    tint: CrabrixTheme.mint,
                    progress: lessonProgress
                )
            }

            HStack {
                Label(
                    "\(progress.earnedAchievements.count)/\(progress.allAchievements.count) achievements",
                    systemImage: "rosette"
                )
                Spacer(minLength: 0)
                if let next = rank.next {
                    Text("\(next - progress.state.totalPoints) pts to next rank")
                } else {
                    Label("Top rank", systemImage: "crown.fill")
                }
            }
            .font(.caption2.monospaced())
            .foregroundStyle(CrabrixTheme.muted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Rating \(progress.state.totalPoints), rank \(rank.title). "
                + "\(lessonCompleted) of \(lessonTotal) installed learning steps complete; "
                + "\(progress.state.lessonsCompleted) lifetime completions, including "
                + "\(progress.state.rustLessonsCompleted) Rust lessons."
        )
    }

    private var subtitle: String {
        #if CRABRIX_SOCIAL
        guard gameCenter.isEnabled else {
            return "Everything is stored on this device"
        }
        switch gameCenter.status {
        case .signedIn:
            return "Game Center · rating syncs to the global board"
        default:
            return "Everything is stored on this device"
        }
        #else
        return "Everything is stored on this device"
        #endif
    }

    #if CRABRIX_SOCIAL
    private var gameCenterStatusText: String {
        switch gameCenter.status {
        case .idle:
            return "Game Center is on. Local progress remains available offline."
        case .authenticating:
            return "Connecting to Game Center…"
        case .signedIn:
            return "Connected to Game Center."
        case .unavailable(let reason):
            return "Game Center is unavailable: \(reason) Local progress is safe."
        }
    }
    #endif

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("LIFETIME")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(CrabrixTheme.muted)
            let state = progress.state
            statRow(
                "Rust lessons",
                "\(state.rustLessonsCompleted)",
                "graduationcap.fill"
            )
            statRow(
                "Atlas study steps",
                "\(state.algorithmStudySteps)",
                "book.pages.fill"
            )
            statRow(
                "Algorithms mastered",
                "\(state.solvedAlgorithmPatternIDs.count)",
                "function"
            )
            statRow("Successful runs", "\(state.buildsSucceeded)", "play.circle.fill")
            statRow("Lines of Rust changed", "\(state.linesChanged)", "chart.bar.doc.horizontal.fill")
            statRow("Diagnostics repaired", "\(state.diagnosticsRepaired)", "bandage.fill")
            statRow("Crates compiled", "\(state.packagesCompiled)", "shippingbox.fill")
            statRow("Term Train pairs", "\(state.termTrainPairsMatched)", "link")
            statRow("Code Recall best", "\(state.codeRecallBestLevel) lines", "brain.head.profile")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .crabrixPanel(cornerRadius: 16)
    }

    private func statRow(_ label: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(CrabrixTheme.blue)
                .frame(width: 20)
            Text(label).font(.subheadline)
            Spacer(minLength: 0)
            Text(value)
                .font(.subheadline.monospaced().bold())
                .monospacedDigit()
        }
    }
}

private struct ProfileAvatarPickerLabel: View {
    let customImage: UIImage?
    let gameCenterImage: UIImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image = customImage ?? gameCenterImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "person.fill")
                        .font(.title)
                        .foregroundStyle(CrabrixTheme.muted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(CrabrixTheme.raised)
                }
            }
            .frame(width: 68, height: 68)
            .clipShape(Circle())
            .overlay { Circle().stroke(CrabrixTheme.border, lineWidth: 1.5) }

            Image(systemName: "camera.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 23, height: 23)
                .background(CrabrixTheme.coral, in: Circle())
                .overlay { Circle().stroke(CrabrixTheme.panel, lineWidth: 2) }
        }
    }
}

private struct ProfileMetric: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let tint: Color
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.caption.bold())
                    .foregroundStyle(tint)
                    .frame(width: 27, height: 27)
                    .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(CrabrixTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Text(value)
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(detail)
                .font(.caption2.bold())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            ProgressView(value: progress)
                .tint(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if CRABRIX_SOCIAL
/// Hosts Game Center's own leaderboard and achievement screens.
private struct GameCenterSheet: UIViewControllerRepresentable {
    let controller: GKGameCenterViewController
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> GKGameCenterViewController {
        controller.gameCenterDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: GKGameCenterViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency GKGameCenterControllerDelegate {
        let onDismiss: () -> Void

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        func gameCenterViewControllerDidFinish(_ controller: GKGameCenterViewController) {
            onDismiss()
        }
    }
}

/// Presents Game Center's sign-in screen when it asks for one.
struct GameCenterAuthenticationPresenter: ViewModifier {
    @ObservedObject var service: GameCenterService

    func body(content: Content) -> some View {
        content.sheet(isPresented: isPresented) {
            if let controller = service.authenticationViewController {
                AuthenticationSheet(controller: controller).ignoresSafeArea()
            }
        }
    }

    private var isPresented: Binding<Bool> {
        Binding(
            get: { service.authenticationViewController != nil },
            set: { if !$0 { service.authenticationViewController = nil } }
        )
    }

    private struct AuthenticationSheet: UIViewControllerRepresentable {
        let controller: UIViewController
        func makeUIViewController(context: Context) -> UIViewController { controller }
        func updateUIViewController(_ controller: UIViewController, context: Context) {}
    }
}

extension View {
    func gameCenterAuthentication(_ service: GameCenterService) -> some View {
        modifier(GameCenterAuthenticationPresenter(service: service))
    }
}
#endif
