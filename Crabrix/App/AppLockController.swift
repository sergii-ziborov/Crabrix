import LocalAuthentication
import SwiftUI

@MainActor
protocol AppLockAuthenticationContext: AnyObject {
    func canAuthenticate() -> Bool
    func authenticate(reason: String) async throws -> Bool
    func invalidate()
}

@MainActor
private final class DeviceOwnerAuthenticationContext: AppLockAuthenticationContext {
    private let context = LAContext()

    func canAuthenticate() -> Bool {
        context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    func authenticate(reason: String) async throws -> Bool {
        try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
    }

    func invalidate() { context.invalidate() }
}

/// Optional local screen lock. It does not upload biometrics or replace iOS
/// file protection; LocalAuthentication owns the Face ID/passcode prompt.
@MainActor
final class AppLockController: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var isLocked: Bool
    @Published private(set) var isAuthenticating = false
    @Published var errorMessage: String?

    private static let enabledKey = "crabrix.privacy.appLockEnabled"
    private let defaults: UserDefaults
    private let makeContext: @MainActor () -> any AppLockAuthenticationContext
    private var scenePhase: ScenePhase = .inactive
    private var autoPromptedThisForeground = false
    private var canRetrySystemInterruption = true
    private var activeContext: (any AppLockAuthenticationContext)?
    private var currentAttempt: UUID?

    init(
        defaults: UserDefaults = .standard,
        makeContext: (@MainActor () -> any AppLockAuthenticationContext)? = nil
    ) {
        self.defaults = defaults
        self.makeContext = makeContext ?? { DeviceOwnerAuthenticationContext() }
        let enabled = defaults.bool(forKey: Self.enabledKey)
        isEnabled = enabled
        isLocked = enabled
    }

    var methodName: String {
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        switch context.biometryType {
        case .faceID: return "Face ID or device passcode"
        case .touchID: return "Touch ID or device passcode"
        default: return "Device passcode"
        }
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        scenePhase = phase
        switch phase {
        case .background:
            autoPromptedThisForeground = false
            canRetrySystemInterruption = true
            if isEnabled { isLocked = true }
            let context = activeContext
            activeContext = nil
            currentAttempt = nil
            isAuthenticating = false
            context?.invalidate()
        case .active:
            promptIfNeeded()
        case .inactive:
            // The system authentication sheet can make a scene inactive while
            // it is still in the foreground. Only background invalidates it.
            break
        @unknown default:
            break
        }
    }

    private func promptIfNeeded() {
        guard scenePhase == .active, isEnabled, isLocked,
              !isAuthenticating, !autoPromptedThisForeground else { return }
        autoPromptedThisForeground = true
        Task { await unlock() }
    }

    func setEnabled(_ enabled: Bool) async {
        guard enabled != isEnabled else { return }
        let reason = enabled
            ? "Protect your projects when the app is reopened"
            : "Turn off protection for your projects"
        guard await authorize(reason: reason), scenePhase != .background else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
        isLocked = false
        errorMessage = nil
    }

    func unlock() async {
        guard isEnabled && isLocked else { return }
        guard await authorize(reason: "Open your Rust projects and courses"),
              scenePhase != .background else { return }
        isLocked = false
        errorMessage = nil
    }

    private func authorize(reason: String) async -> Bool {
        guard !isAuthenticating && scenePhase == .active else { return false }
        errorMessage = nil
        let context = makeContext()
        guard context.canAuthenticate() else {
            errorMessage = "Set a device passcode in iOS Settings to use app protection."
            return false
        }

        let attempt = UUID()
        currentAttempt = attempt
        activeContext = context
        isAuthenticating = true
        defer {
            if currentAttempt == attempt {
                currentAttempt = nil
                activeContext = nil
                isAuthenticating = false
                // A cancellation callback may arrive before or after .active.
                // Both orders must create a fresh prompt, without overlapping it.
                promptIfNeeded()
            }
        }

        do {
            let approved = try await context.authenticate(reason: reason)
            // Face ID's own sheet can still be making the scene inactive here.
            return approved && currentAttempt == attempt && scenePhase != .background
        } catch {
            guard currentAttempt == attempt && scenePhase != .background else { return false }
            let code = (error as? LAError)?.code
            if (code == .systemCancel || code == .notInteractive) && canRetrySystemInterruption {
                canRetrySystemInterruption = false
                autoPromptedThisForeground = false
            }
            if code != .userCancel && code != .systemCancel && code != .appCancel {
                errorMessage = "Authentication failed. Try again or use your device passcode."
            }
            return false
        }
    }
}

struct AppLockScreen: View {
    @ObservedObject var controller: AppLockController

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 52))
                .foregroundStyle(CrabrixTheme.coral)
            Text("Crabrix is locked")
                .font(.title2.bold())
            Text("Use \(controller.methodName) to continue.")
                .font(.subheadline)
                .foregroundStyle(CrabrixTheme.muted)
                .multilineTextAlignment(.center)
            Button {
                Task { await controller.unlock() }
            } label: {
                if controller.isAuthenticating {
                    ProgressView().frame(minWidth: 180)
                } else {
                    Label("Unlock", systemImage: "faceid")
                        .frame(minWidth: 180)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(CrabrixTheme.coral)
            .disabled(controller.isAuthenticating)

            if let errorMessage = controller.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(CrabrixTheme.amber)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CrabrixTheme.background.ignoresSafeArea())
        .foregroundStyle(CrabrixTheme.primary)
        .accessibilityAddTraits(.isModal)
    }
}
