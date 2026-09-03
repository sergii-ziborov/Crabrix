// Compiled only into development builds. The App Store 1.0 binary is built
// without CRABRIX_SOCIAL, so none of this reaches a shipped app.
#if CRABRIX_SOCIAL
import Foundation
import GameKit
import SwiftUI

/// Identity, achievements, and the leaderboard — through Game Center.
///
/// There is deliberately no Crabrix account: no password to store, no reset
/// email to send, and no personal data to hold. Game Center already supplies a
/// verified player, a display name, and a photo, and it is the only identity
/// Apple lets an iOS app use without asking for credentials.
///
/// Every part of this is optional. If the player is not signed in, or the build
/// is not provisioned for Game Center, the app keeps working exactly as it does
/// offline: rating, achievements, and vitals are local first and always have been.
@MainActor
final class GameCenterService: ObservableObject {
    enum Status: Equatable {
        case idle
        case authenticating
        case signedIn(playerName: String)
        /// Signed out, unavailable, or refused. Carries something to show.
        case unavailable(reason: String)

        var isSignedIn: Bool {
            if case .signedIn = self { return true }
            return false
        }
    }

    /// The single leaderboard the rating is submitted to.
    static let leaderboardID = "com.sergiiziborov.Crabrix.rating"

    @Published private(set) var status: Status = .idle
    @Published private(set) var playerName = ""
    @Published private(set) var photo: UIImage?
    @Published private(set) var globalRank: Int?
    /// Set when Game Center wants to present its own sign-in screen.
    @Published var authenticationViewController: UIViewController?

    private var lastSubmittedPoints: Int?
    private var reportedAchievementIDs: Set<String> = []

    var isSignedIn: Bool { status.isSignedIn }

    /// Starts authentication. Safe to call more than once.
    func authenticate() {
        guard CrabrixReleaseFeatures.gameCenterEnabled else { return }
        guard case .idle = status else { return }
        status = .authenticating

        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            guard let self else { return }
            Task { @MainActor in
                self.handleAuthentication(viewController: viewController, error: error)
            }
        }
    }

    private func handleAuthentication(viewController: UIViewController?, error: Error?) {
        if let viewController {
            // Game Center wants to ask the player to sign in; the app presents it.
            authenticationViewController = viewController
            status = .unavailable(reason: "Sign in to Game Center to join the leaderboard.")
            return
        }

        if let error {
            status = .unavailable(reason: Self.describe(error))
            return
        }

        guard GKLocalPlayer.local.isAuthenticated else {
            status = .unavailable(reason: "Not signed in to Game Center.")
            return
        }

        playerName = GKLocalPlayer.local.displayName
        status = .signedIn(playerName: playerName)
        loadPhoto()
        Task { await refreshRank() }
    }

    /// The player's Game Center photo, which is the avatar without an upload flow.
    private func loadPhoto() {
        GKLocalPlayer.local.loadPhoto(for: .normal) { [weak self] image, _ in
            Task { @MainActor in self?.photo = image }
        }
    }

    /// Submits the rating and any newly earned achievements.
    ///
    /// Nothing here is required for the app to work, so a failure is recorded
    /// and forgotten rather than surfaced as an error the reader must act on.
    func submit(state: CrabrixProgressState) async {
        guard CrabrixReleaseFeatures.gameCenterEnabled else { return }
        guard isSignedIn else { return }

        if lastSubmittedPoints != state.totalPoints {
            do {
                try await GKLeaderboard.submitScore(
                    state.totalPoints,
                    context: 0,
                    player: GKLocalPlayer.local,
                    leaderboardIDs: [Self.leaderboardID]
                )
                lastSubmittedPoints = state.totalPoints
                await refreshRank()
            } catch {
                // Offline, or the leaderboard is not configured yet. Local
                // rating is the source of truth either way.
            }
        }

        await submitAchievements(state: state)
    }

    private func submitAchievements(state: CrabrixProgressState) async {
        let pending = CrabrixAchievementCatalog.all.compactMap { achievement -> GKAchievement? in
            let value = achievement.progress(state)
            guard value.target > 0 else { return nil }
            let percent = min(100, Double(value.current) / Double(value.target) * 100)
            // Only send what moved, so a launch does not re-report everything.
            guard percent > 0, !reportedAchievementIDs.contains(achievement.id) || percent >= 100 else {
                return nil
            }
            let report = GKAchievement(identifier: achievement.id)
            report.percentComplete = percent
            report.showsCompletionBanner = false // the in-app animation is the banner
            return report
        }

        guard !pending.isEmpty else { return }
        do {
            try await GKAchievement.report(pending)
            reportedAchievementIDs.formUnion(pending.map(\.identifier))
        } catch {
            // Same as above: reporting is a bonus, never a requirement.
        }
    }

    /// The player's position on the global board, for the profile screen.
    func refreshRank() async {
        guard isSignedIn else { return }
        do {
            let boards = try await GKLeaderboard.loadLeaderboards(IDs: [Self.leaderboardID])
            guard let board = boards.first else { return }
            let entry = try await board.loadEntries(for: [GKLocalPlayer.local], timeScope: .allTime)
            globalRank = entry.0?.rank
        } catch {
            globalRank = nil
        }
    }

    /// Game Center's own leaderboard UI, which is free and needs no website.
    func makeLeaderboardViewController() -> GKGameCenterViewController {
        GKGameCenterViewController(
            leaderboardID: Self.leaderboardID,
            playerScope: .global,
            timeScope: .allTime
        )
    }

    func makeAchievementsViewController() -> GKGameCenterViewController {
        GKGameCenterViewController(state: .achievements)
    }

    private static func describe(_ error: Error) -> String {
        let code = GKError.Code(rawValue: (error as NSError).code)
        return switch code {
        case .gameUnrecognized:
            "This build is not registered for Game Center yet."
        case .notAuthenticated:
            "Not signed in to Game Center."
        case .communicationsFailure:
            "Game Center is unreachable right now."
        default:
            error.localizedDescription
        }
    }
}
#endif
