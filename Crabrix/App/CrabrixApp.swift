import SwiftUI

@main
struct CrabrixApp: App {
    /// Rating and achievements are earned everywhere, so the store is owned once
    /// at the root and handed to every feature that reports progress.
    @StateObject private var progress = CrabrixProgressStore()
    /// Health and energy live beside it, kept in step with rating because rank
    /// is what sets the size of both pools.
    @StateObject private var vitals = CrabrixVitalsStore()
    /// Identity and the global board, through Game Center. Optional everywhere:
    /// the app is fully usable without ever signing in.
    @StateObject private var gameCenter = GameCenterService()
    /// The public board on crabrix.com. Opt-in, and off until asked for.
    @StateObject private var leaderboard = LeaderboardClient()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(progress)
                .environmentObject(vitals)
                .environmentObject(gameCenter)
                .environmentObject(leaderboard)
                .achievementCelebrations(store: progress)
                .gameCenterAuthentication(gameCenter)
                .task {
                    vitals.refresh(points: progress.state.totalPoints)
                    gameCenter.authenticate()
                }
                .onReceive(progress.$state) { state in
                    vitals.refresh(points: state.totalPoints)
                    Task {
                        await gameCenter.submit(state: state)
                        await leaderboard.publish(state: state)
                    }
                }
        }
    }
}
