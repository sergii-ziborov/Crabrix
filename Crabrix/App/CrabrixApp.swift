import SwiftUI

/// Release capabilities stay explicit and auditable.
///
/// Crabrix runs no service of its own. If ranking ever goes online it will be
/// Game Center, which Apple already operates — there is no Crabrix account, no
/// Crabrix server, and no first-party board to run, moderate or secure.
///
/// The production 1.0 binary is built without `CRABRIX_SOCIAL`, so even Game
/// Center is not merely switched off: its service, its UI and its network path
/// are not compiled into the app at all. This flag remains so development
/// builds, which do compile that code, still keep it dormant until the
/// provisioning gates pass.
enum CrabrixReleaseFeatures {
    static let gameCenterEnabled = false
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
                if CrabrixReleaseFeatures.gameCenterEnabled {
                    Task { await gameCenter.submit(state: state) }
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
            .gameCenterAuthentication(gameCenter)
        #else
        content
        #endif
    }
}
