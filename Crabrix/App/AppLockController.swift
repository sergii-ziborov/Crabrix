import LocalAuthentication
import SwiftUI

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
    private var isActive = false
    private var autoPromptedThisForeground = false
    private var activeContext: LAContext?
    private var currentAttempt: UUID?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
        switch phase {
        case .background:
            isActive = false
            autoPromptedThisForeground = false
            if isEnabled { isLocked = true }
            activeContext?.invalidate()
            activeContext = nil
            currentAttempt = nil
            isAuthenticating = false
        case .active:
            isActive = true
            if isEnabled && isLocked && !autoPromptedThisForeground {
                autoPromptedThisForeground = true
                Task { await unlock() }
            }
        case .inactive:
            // The system authentication sheet can make a scene inactive while
            // it is still in the foreground. Only background invalidates it.
            break
        @unknown default:
            isActive = false
        }
    }

    func setEnabled(_ enabled: Bool) async {
        guard enabled != isEnabled else { return }
        let reason = enabled
            ? "Protect your projects when the app is reopened"
            : "Turn off protection for your projects"
        guard await authorize(reason: reason) else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
        isLocked = false
        errorMessage = nil
    }

    func unlock() async {
        guard isEnabled && isLocked else { return }
        guard await authorize(reason: "Open your Rust projects and courses") else { return }
        isLocked = false
        errorMessage = nil
    }

    private func authorize(reason: String) async -> Bool {
        guard !isAuthenticating && isActive else { return false }
        errorMessage = nil
        let context = LAContext()
        var availabilityError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &availabilityError) else {
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
            }
        }

        do {
            let approved = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
            return approved && currentAttempt == attempt && isActive
        } catch {
            guard currentAttempt == attempt && isActive else { return false }
            let code = (error as? LAError)?.code
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
