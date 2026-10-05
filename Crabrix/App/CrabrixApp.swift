import SwiftUI

@main
struct CrabrixApp: App {
    @Environment(\.scenePhase) private var scenePhase
    /// Rating and achievements are earned everywhere, so the store is owned once
    /// at the root and handed to every feature that reports progress.
    @StateObject private var progress: CrabrixProgressStore
    @StateObject private var academyContent: AcademyContentStore
    @StateObject private var appLock: AppLockController
    #if CRABRIX_SOCIAL
    /// Identity and the global board, through Game Center. Optional everywhere:
    /// the app is fully usable without ever signing in.
    @StateObject private var gameCenter: GameCenterService
    #endif

    init() {
        // Decide before CrabrixProgressStore can write its current schema to
        // UserDefaults. Otherwise a fresh install can look like an upgrade.
        let initialInstallMode = CourseLaunchPolicy.resolve()
        _progress = StateObject(wrappedValue: CrabrixProgressStore())
        _academyContent = StateObject(wrappedValue: AcademyContentStore(
            initialInstallMode: initialInstallMode
        ))
        _appLock = StateObject(wrappedValue: AppLockController())
        #if CRABRIX_SOCIAL
        _gameCenter = StateObject(wrappedValue: GameCenterService())
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                socialEnvironment(
                    ContentView()
                        .environmentObject(progress)
                        .environmentObject(academyContent)
                        .environmentObject(appLock)
                        .achievementCelebrations(store: progress)
                )
                .allowsHitTesting(!appLock.isLocked)
                .accessibilityHidden(appLock.isLocked)

                if appLock.isLocked || (appLock.isEnabled && scenePhase != .active) {
                    AppLockScreen(controller: appLock)
                }
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                appLock.scenePhaseChanged(phase)
            }
            .task {
                await academyContent.prepare()
                #if CRABRIX_SOCIAL
                gameCenter.authenticate()
                #endif
            }
            .onReceive(progress.$state) { state in
                #if CRABRIX_SOCIAL
                Task { await gameCenter.submit(state: state) }
                #endif
            }
            #if CRABRIX_SOCIAL
            .onReceive(gameCenter.$status) { status in
                if status.isSignedIn {
                    Task { await gameCenter.submit(state: progress.state) }
                }
            }
            #endif
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
