// Game Center is optional. Local progress never depends on authentication.
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
/// Every part of this is optional. The player explicitly enables it in Profile;
/// disabling it stops future submissions without changing local progress.
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

    /// A stable subset of the local catalogue. Installed Atlas packs can add
    /// more local tiers, but Game Center IDs must be configured in App Store
    /// Connect and cannot change with downloaded course data.
    static let achievementIDs: Set<String> = [
        "builds.0", "builds.2", "lessons.0", "lessons.2", "practice.0",
        "crates.0", "rating.0", "rating.4", "algorithm-atlas.0",
        "algorithm-atlas.4"
    ]

    static func gameCenterAchievementID(for localID: String) -> String {
        // Game Center accepts letters, digits, underscores, and periods.
        "com.sergiiziborov.Crabrix.\(localID.replacingOccurrences(of: "-", with: "_"))"
    }

    @Published private(set) var isEnabled: Bool

    @Published private(set) var status: Status = .idle
    @Published private(set) var playerName = ""
    @Published private(set) var photo: UIImage?
    @Published private(set) var globalRank: Int?
    /// Set when Game Center wants to present its own sign-in screen.
    @Published var authenticationViewController: UIViewController?

    private var lastSubmittedPoints: Int?
    private var reportedAchievementProgress: [String: Double] = [:]
    private var authenticatedPlayerID: String?
    private var pendingState: CrabrixProgressState?
    private var submissionInProgress = false
    private let defaults: UserDefaults
    private static let enabledKey = "crabrix.gameCenter.enabled"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.enabledKey)
    }

    var isSignedIn: Bool { status.isSignedIn }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
        if enabled {
            authenticate()
        } else {
            // GameKit has no per-app sign-out. Disconnect this app's UI and
            // stop future requests; existing Game Center scores remain there.
            GKLocalPlayer.local.authenticateHandler = nil
            authenticationViewController = nil
            playerName = ""
            photo = nil
            globalRank = nil
            lastSubmittedPoints = nil
            reportedAchievementProgress.removeAll()
            authenticatedPlayerID = nil
            pendingState = nil
            status = .idle
        }
    }

    /// Starts authentication. Safe to call more than once.
    func authenticate() {
        guard isEnabled else { return }
        guard !status.isSignedIn else { return }
        guard status != .authenticating else { return }
        status = .authenticating

        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            guard let self else { return }
            Task { @MainActor in
                self.handleAuthentication(viewController: viewController, error: error)
            }
        }
    }

    private func handleAuthentication(viewController: UIViewController?, error: Error?) {
        guard isEnabled else { return }
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

        let playerID = GKLocalPlayer.local.gamePlayerID
        if authenticatedPlayerID != playerID {
            // A second Apple player on this device must receive the local
            // snapshot too, even when its score matches the previous player.
            authenticatedPlayerID = playerID
            lastSubmittedPoints = nil
            reportedAchievementProgress.removeAll()
        }
        playerName = GKLocalPlayer.local.displayName
        status = .signedIn(playerName: playerName)
        loadPhoto()
        Task { await refreshRank() }
    }

    /// The player's Game Center photo, which is the avatar without an upload flow.
    private func loadPhoto() {
        GKLocalPlayer.local.loadPhoto(for: .normal) { [weak self] image, _ in
            Task { @MainActor in
                guard let self, self.isEnabled, self.isSignedIn else { return }
                self.photo = image
            }
        }
    }

    /// Submits the rating and any newly earned achievements.
    ///
    /// Nothing here is required for the app to work, so a failure is recorded
    /// and forgotten rather than surfaced as an error the reader must act on.
    func submit(state: CrabrixProgressState) async {
        guard isEnabled, isSignedIn else { return }
        pendingState = state
        guard !submissionInProgress else { return }
        submissionInProgress = true
        defer { submissionInProgress = false }

        while isEnabled, isSignedIn, let next = pendingState {
            pendingState = nil
            await submitSnapshot(next)
        }
    }

    private func submitSnapshot(_ state: CrabrixProgressState) async {
        if lastSubmittedPoints != state.totalPoints {
            do {
                try await GKLeaderboard.submitScore(
                    state.totalPoints,
                    context: 0,
                    player: GKLocalPlayer.local,
                    leaderboardIDs: [Self.leaderboardID]
                )
                guard isEnabled else { return }
                lastSubmittedPoints = state.totalPoints
                await refreshRank()
            } catch {
                // Offline, or the leaderboard is not configured yet. Local
                // rating is the source of truth either way.
            }
        }

        guard isEnabled, isSignedIn else { return }
        await submitAchievements(state: state)
    }

    private func submitAchievements(state: CrabrixProgressState) async {
        let pending = CrabrixAchievementCatalog.all.compactMap { achievement -> GKAchievement? in
            guard Self.achievementIDs.contains(achievement.id) else { return nil }
            let value = achievement.progress(state)
            guard value.target > 0 else { return nil }
            let percent = min(100, Double(value.current) / Double(value.target) * 100)
            let gameCenterID = Self.gameCenterAchievementID(for: achievement.id)
            guard percent > (reportedAchievementProgress[gameCenterID] ?? 0) else {
                return nil
            }
            let report = GKAchievement(identifier: gameCenterID)
            report.percentComplete = percent
            report.showsCompletionBanner = false // the in-app animation is the banner
            return report
        }

        guard !pending.isEmpty else { return }
        do {
            try await GKAchievement.report(pending)
            guard isEnabled else { return }
            for achievement in pending {
                reportedAchievementProgress[achievement.identifier] = achievement.percentComplete
            }
        } catch {
            // Same as above: reporting is a bonus, never a requirement.
        }
    }

    /// The player's position on the global board, for the profile screen.
    func refreshRank() async {
        guard isEnabled, isSignedIn else { return }
        do {
            let boards = try await GKLeaderboard.loadLeaderboards(IDs: [Self.leaderboardID])
            guard let board = boards.first else { return }
            let entry = try await board.loadEntries(for: [GKLocalPlayer.local], timeScope: .allTime)
            if isEnabled { globalRank = entry.0?.rank }
        } catch {
            if isEnabled { globalRank = nil }
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
