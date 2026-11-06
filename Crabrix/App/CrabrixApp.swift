import SwiftUI

@main
struct CrabrixApp: App {
    @Environment(\.scenePhase) private var scenePhase
    /// Rating and achievements are earned everywhere, so the store is owned once
    /// at the root and handed to every feature that reports progress.
    @StateObject private var progress: CrabrixProgressStore
    @StateObject private var academyContent: AcademyContentStore
    @StateObject private var appLock: AppLockController
    @StateObject private var learningBackup: LearningBackupCoordinator
    #if CRABRIX_SOCIAL
    /// Identity and the global board, through Game Center. Optional everywhere:
    /// the app is fully usable without ever signing in.
    @StateObject private var gameCenter: GameCenterService
    #endif

    init() {
        // Decide before CrabrixProgressStore can write its current schema to
        // UserDefaults. Otherwise a fresh install can look like an upgrade.
        let initialInstallMode = CourseLaunchPolicy.resolve()
        var recoveryError: String?
        if let domain = Bundle.main.bundleIdentifier {
            do { try LearningProgressArchive.recoverPendingRestore(defaults: .standard, domain: domain) }
            catch { recoveryError = error.localizedDescription }
        }
        _learningBackup = StateObject(wrappedValue: LearningBackupCoordinator(recoveryError: recoveryError))
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
                        .environmentObject(learningBackup)
                        .achievementCelebrations(store: progress)
                )
                .allowsHitTesting(!appLock.isLocked && !learningBackup.recoveryRequired)
                .accessibilityHidden(appLock.isLocked || learningBackup.recoveryRequired)

                if learningBackup.recoveryRequired, !appLock.isLocked {
                    LearningRecoveryView(backup: learningBackup)
                }

                if appLock.isLocked || (appLock.isEnabled && scenePhase != .active) {
                    AppLockScreen(controller: appLock)
                }
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                appLock.scenePhaseChanged(phase)
                if phase == .background { learningBackup.saveNow() }
            }
            .task {
                learningBackup.start()
                await academyContent.prepare()
            }
            .onReceive(progress.$state) { state in
                guard !learningBackup.recoveryRequired else { return }
                #if CRABRIX_SOCIAL
                Task { await gameCenter.submit(state: state) }
                #endif
            }
            #if CRABRIX_SOCIAL
            .onReceive(gameCenter.$status) { status in
                if status.isSignedIn && !learningBackup.recoveryRequired {
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
        #else
        content
        #endif
    }
}
