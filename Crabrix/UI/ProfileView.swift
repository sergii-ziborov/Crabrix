import GameKit
import PhotosUI
import SwiftUI

/// The player's profile: identity, rating, vitals, and achievements.
///
/// Identity comes from Game Center, so there is no Crabrix account to create
/// and no password to handle. Everything on this screen works signed out too —
/// signing in adds the global leaderboard and the photo, nothing more.
struct ProfileView: View {
    @EnvironmentObject private var progress: CrabrixProgressStore
    @EnvironmentObject private var vitals: CrabrixVitalsStore
    @EnvironmentObject private var gameCenter: GameCenterService
    @EnvironmentObject private var leaderboard: LeaderboardClient

    @StateObject private var avatarStore = LocalAvatarStore()

    @State private var gameCenterPanel: GameCenterPanel?
    @State private var isRemovalConfirmed = false
    @State private var selectedAvatarItem: PhotosPickerItem?

    private enum GameCenterPanel: Identifiable {
        case leaderboard
        case achievements
        var id: String { self == .leaderboard ? "leaderboard" : "achievements" }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                identityCard
                if CrabrixReleaseFeatures.crabrixBoardEnabled {
                    publishCard
                }
                VitalsCard(store: vitals)
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
        .sheet(item: $gameCenterPanel) { panel in
            GameCenterSheet(
                controller: panel == .leaderboard
                    ? gameCenter.makeLeaderboardViewController()
                    : gameCenter.makeAchievementsViewController()
            )
            .ignoresSafeArea()
        }
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
        .task {
            if CrabrixReleaseFeatures.gameCenterEnabled {
                gameCenter.authenticate()
                await gameCenter.submit(state: progress.state)
            }
            if CrabrixReleaseFeatures.crabrixBoardEnabled {
                await leaderboard.publish(state: progress.state)
                await leaderboard.loadBoard()
            }
        }
    }

    private var identityCard: some View {
        let hasCustomAvatar = avatarStore.hasCustomAvatar
        return VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 15) {
                avatarPicker
                VStack(alignment: .leading, spacing: 3) {
                    Text(gameCenter.isSignedIn ? gameCenter.playerName : "Playing offline")
                        .font(.title3.bold())
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(CrabrixTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if CrabrixReleaseFeatures.gameCenterEnabled,
                   let rank = gameCenter.globalRank {
                    VStack(spacing: 1) {
                        Text("#\(rank)")
                            .font(.title3.bold().monospacedDigit())
                            .foregroundStyle(CrabrixTheme.amber)
                        Text("GLOBAL")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(CrabrixTheme.muted)
                    }
                }
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

            if CrabrixReleaseFeatures.gameCenterEnabled, gameCenter.isSignedIn {
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
            } else {
                // No "Connect Game Center" button here on purpose. Sign-in is
                // attempted automatically on appear, and offering a button that
                // cannot work on a build without the entitlement would be a
                // control that does nothing.
                Label(
                    "Your rating, achievements, and progress are saved on this device.",
                    systemImage: "internaldrive.fill"
                )
                .font(.caption)
                .foregroundStyle(CrabrixTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            }

            Divider().overlay(CrabrixTheme.border)
            combinedProgress
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .crabrixPanel(cornerRadius: 16)
    }

    private var avatarPicker: some View {
        let customImage = avatarStore.image
        let gameCenterImage = CrabrixReleaseFeatures.gameCenterEnabled
            ? gameCenter.photo
            : nil
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
        // Every step the Learn tab offers, the Algorithm Atlas included.
        let lessonTotal = RustCourseCatalog.lessonCount
        let lessonCompleted = min(progress.state.lessonsCompleted, lessonTotal)
        let rustLessons = min(
            progress.state.rustLessonsCompleted,
            RustCourseCatalog.academyLessonCount
        )
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
                    title: "LEARN RUST",
                    value: "\(lessonCompleted)/\(lessonTotal)",
                    detail: "\(Int((lessonProgress * 100).rounded()))% complete",
                    systemImage: "map.fill",
                    tint: CrabrixTheme.mint,
                    progress: lessonProgress
                )
            }

            HStack {
                Label(
                    "\(progress.earnedAchievements.count)/\(CrabrixAchievementCatalog.all.count) achievements",
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
                + "\(lessonCompleted) of \(lessonTotal) learning steps complete, "
                + "including \(rustLessons) of "
                + "\(RustCourseCatalog.academyLessonCount) Rust lessons."
        )
    }

    private var subtitle: String {
        // Nothing here names Game Center unless it actually connected: an
        // explanation of a feature the build cannot offer reads as a fault.
        guard CrabrixReleaseFeatures.gameCenterEnabled else {
            return "Everything is stored on this device"
        }
        switch gameCenter.status {
        case .signedIn:
            return "Game Center · rating syncs to the global board"
        default:
            return "Everything is stored on this device"
        }
    }

    /// Opt-in publishing to the public board on crabrix.com.
    ///
    /// Separate from Game Center on purpose: this one works today, needs no
    /// entitlement, and asks for nothing except a display name.
    private var publishCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("PUBLIC BOARD", systemImage: "globe")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(CrabrixTheme.muted)
                Spacer()
                Link(destination: LeaderboardClient.boardURL) {
                    Label("crabrix.com", systemImage: "arrow.up.right.square")
                        .font(.caption2.monospaced())
                }
            }

            Toggle(isOn: $leaderboard.isEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Publish my rating").font(.subheadline.bold())
                    Text("A name and your rating only. No account, no email, no password.")
                        .font(.caption2)
                        .foregroundStyle(CrabrixTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(CrabrixTheme.mint)

            if leaderboard.isEnabled {
                TextField("Display name", text: $leaderboard.displayName)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { Task { await leaderboard.publish(state: progress.state, force: true) } }

                HStack(spacing: 10) {
                    Button {
                        Task { await leaderboard.publish(state: progress.state, force: true) }
                    } label: {
                        Label("Publish now", systemImage: "arrow.up.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(CrabrixTheme.mint)
                    .disabled(!leaderboard.canPublish)

                    Spacer(minLength: 0)
                    publishStatus
                }
                .font(.caption.bold())
            }

            // Always offered, whether publishing is currently on or off: the
            // entry may still exist from an earlier session.
            Button(role: .destructive) {
                isRemovalConfirmed = true
            } label: {
                Label("Remove my entry from the board", systemImage: "trash")
                    .font(.caption.bold())
            }
            .confirmationDialog(
                "Remove your entry?",
                isPresented: $isRemovalConfirmed,
                titleVisibility: .visible
            ) {
                Button("Remove from the board", role: .destructive) {
                    Task { await leaderboard.stopPublishingAndForget() }
                }
                Button("Keep it", role: .cancel) {}
            } message: {
                Text("Your name and rating are deleted from crabrix.com. Everything on this device stays exactly as it is.")
            }

            Text("Names are checked before they appear. Report anything offensive from the support page and it will be removed.")
                .font(.caption2)
                .foregroundStyle(CrabrixTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            Link(destination: LeaderboardClient.supportURL) {
                Label("Report a name · Support", systemImage: "exclamationmark.bubble")
                    .font(.caption2.bold())
            }

            if !leaderboard.board.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("TOP RIGHT NOW")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(CrabrixTheme.muted)
                    ForEach(leaderboard.board.prefix(5)) { entry in
                        HStack(spacing: 9) {
                            Text("#\(entry.rank)")
                                .font(.caption2.monospaced().bold())
                                .foregroundStyle(entry.rank <= 3 ? CrabrixTheme.amber : CrabrixTheme.muted)
                                .frame(width: 26, alignment: .leading)
                            Text(entry.name).font(.caption)
                            Spacer(minLength: 0)
                            Text(CrabrixPointsFormatter.string(entry.points))
                                .font(.caption.monospaced().bold())
                                .foregroundStyle(CrabrixTheme.amber)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .crabrixPanel(cornerRadius: 16)
    }

    @ViewBuilder
    private var publishStatus: some View {
        switch leaderboard.status {
        case .idle:
            EmptyView()
        case .sending:
            ProgressView().controlSize(.mini)
        case let .published(rank, total):
            Label(Self.publishedLabel(rank: rank, total: total), systemImage: "checkmark.circle.fill")
                .foregroundStyle(CrabrixTheme.mint)
        case .removed:
            Label("Removed", systemImage: "trash")
                .foregroundStyle(CrabrixTheme.muted)
        case let .failed(reason):
            Label(reason, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(CrabrixTheme.amber)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
    }

    private static func publishedLabel(rank: Int?, total: Int?) -> String {
        guard let rank else { return "Published" }
        guard let total, total > 0 else { return "#\(rank)" }
        return "#\(rank) of \(total)"
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("LIFETIME")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(CrabrixTheme.muted)
            let state = progress.state
            statRow(
                "Rust lessons",
                "\(state.rustLessonsCompleted)/\(RustCourseCatalog.academyLessonCount)",
                "graduationcap.fill"
            )
            statRow(
                "Atlas study steps",
                "\(state.algorithmStudySteps)/\(AlgorithmCourseCatalog.studyStepCount)",
                "book.pages.fill"
            )
            statRow(
                "Algorithms mastered",
                "\(state.solvedAlgorithmPatternIDs.count)/\(AlgorithmCourseCatalog.challengeCount)",
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

/// Hosts Game Center's own leaderboard and achievement screens.
private struct GameCenterSheet: UIViewControllerRepresentable {
    let controller: GKGameCenterViewController

    func makeUIViewController(context: Context) -> GKGameCenterViewController {
        controller.gameCenterDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: GKGameCenterViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency GKGameCenterControllerDelegate {
        func gameCenterViewControllerDidFinish(_ controller: GKGameCenterViewController) {
            controller.dismiss(animated: true)
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
