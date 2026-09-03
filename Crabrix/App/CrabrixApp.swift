import SwiftUI

/// Release capabilities stay explicit and auditable.
///
/// The production 1.0 binary is built without `CRABRIX_SOCIAL`, so Game Center
/// and the Crabrix board are not merely switched off: their services, their UI
/// and their network paths are not compiled into the app at all. These flags
/// remain so development builds, which do compile that code, still keep every
/// path dormant until provisioning and server evidence satisfy their gates.
enum CrabrixReleaseFeatures {
    static let gameCenterEnabled = false
    static let crabrixBoardEnabled = false
}

@main
struct CrabrixApp: App {
    /// Rating and achievements are earned everywhere, so the store is owned once
    /// at the root and handed to every feature that reports progress.
    @StateObject private var progress = CrabrixProgressStore()
    /// Health and energy live beside it, kept in step with rating because rank
    /// is what sets the size of both pools.
    @StateObject private var vitals = CrabrixVitalsStore()
    #if CRABRIX_SOCIAL
    /// Identity and the global board, through Game Center. Optional everywhere:
    /// the app is fully usable without ever signing in.
    @StateObject private var gameCenter = GameCenterService()
    /// The public board on crabrix.com. Opt-in, and off until asked for.
    @StateObject private var leaderboard = LeaderboardClient()
    #endif

    var body: some Scene {
        WindowGroup {
            socialEnvironment(
                ContentView()
                    .environmentObject(progress)
                    .environmentObject(vitals)
                    .achievementCelebrations(store: progress)
            )
            .task {
                vitals.refresh(points: progress.state.totalPoints)
                #if CRABRIX_SOCIAL
                if CrabrixReleaseFeatures.gameCenterEnabled {
                    gameCenter.authenticate()
                }
                #endif
            }
            .onReceive(progress.$state) { state in
                vitals.refresh(points: state.totalPoints)
                #if CRABRIX_SOCIAL
                Task {
                    if CrabrixReleaseFeatures.gameCenterEnabled {
                        await gameCenter.submit(state: state)
                    }
                    if CrabrixReleaseFeatures.crabrixBoardEnabled {
                        await leaderboard.publish(state: state)
                    }
                }
                #endif
            }
        }
    }

    /// Development builds hand the social services down the hierarchy. The
    /// production build has none to hand down, and the view tree is otherwise
    /// identical.
    @ViewBuilder
    private func socialEnvironment(_ content: some View) -> some View {
        #if CRABRIX_SOCIAL
        content
            .environmentObject(gameCenter)
            .environmentObject(leaderboard)
            .gameCenterAuthentication(gameCenter)
        #else
        content
        #endif
    }
}
