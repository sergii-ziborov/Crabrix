import GameKit
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

    @State private var gameCenterPanel: GameCenterPanel?
    @State private var isRemovalConfirmed = false

    private enum GameCenterPanel: Identifiable {
        case leaderboard
        case achievements
        var id: String { self == .leaderboard ? "leaderboard" : "achievements" }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                identityCard
                publishCard
                RatingSummaryCard(store: progress)
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
        .task {
            gameCenter.authenticate()
            await gameCenter.submit(state: progress.state)
            await leaderboard.publish(state: progress.state)
            await leaderboard.loadBoard()
        }
    }

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 15) {
                avatar
                VStack(alignment: .leading, spacing: 3) {
                    Text(gameCenter.isSignedIn ? gameCenter.playerName : "Playing offline")
                        .font(.title3.bold())
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(CrabrixTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if let rank = gameCenter.globalRank {
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

            if gameCenter.isSignedIn {
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
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .crabrixPanel(cornerRadius: 16)
    }

    private var avatar: some View {
        Group {
            if let photo = gameCenter.photo {
                Image(uiImage: photo)
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
        .frame(width: 60, height: 60)
        .clipShape(Circle())
        .overlay { Circle().stroke(CrabrixTheme.border, lineWidth: 1.5) }
    }

    private var subtitle: String {
        // Nothing here names Game Center unless it actually connected: an
        // explanation of a feature the build cannot offer reads as a fault.
        switch gameCenter.status {
        case .signedIn:
            "Game Center · rating syncs to the global board"
        default:
            "Everything is stored on this device"
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
            statRow("Lessons completed", "\(state.lessonsCompleted)", "graduationcap.fill")
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

/// Hosts Game Center's own leaderboard and achievement screens.
private struct GameCenterSheet: UIViewControllerRepresentable {
    let controller: GKGameCenterViewController

    func makeUIViewController(context: Context) -> GKGameCenterViewController {
        controller.gameCenterDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: GKGameCenterViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, GKGameCenterControllerDelegate {
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
