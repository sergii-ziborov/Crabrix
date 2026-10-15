import XCTest
import LocalAuthentication
@testable import Crabrix

@MainActor
final class AppLockTests: XCTestCase {
    @MainActor private final class FakeContext: AppLockAuthenticationContext {
        private var reply: CheckedContinuation<Bool, Error>?
        private(set) var invalidated = false
        var isPending: Bool { reply != nil }

        func canAuthenticate() -> Bool { true }
        func authenticate(reason: String) async throws -> Bool {
            try await withCheckedThrowingContinuation { reply = $0 }
        }
        func invalidate() { invalidated = true }
        func complete(_ result: Result<Bool, Error>) {
            let pending = reply
            reply = nil
            pending?.resume(with: result)
        }
    }

    @MainActor private final class Harness {
        let suite = "crabrix.lock.race.tests.\(UUID().uuidString)"
        let defaults: UserDefaults
        var contexts: [FakeContext] = []

        init() {
            defaults = UserDefaults(suiteName: suite)!
            defaults.set(true, forKey: "crabrix.privacy.appLockEnabled")
        }
        func makeLock() -> AppLockController {
            AppLockController(defaults: defaults) {
                let context = FakeContext()
                self.contexts.append(context)
                return context
            }
        }
        func cleanup() { defaults.removePersistentDomain(forName: suite) }
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !condition(), Date() < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(condition(), "Authentication state did not settle", file: file, line: line)
    }

    func testLosingActivationBeforePromptStartsDoesNotConsumeNextUnlock() async throws {
        let harness = Harness()
        defer { harness.cleanup() }
        let lock = harness.makeLock()
        lock.scenePhaseChanged(.active)
        lock.scenePhaseChanged(.inactive)
        // Let the queued automatic task observe inactivity before resuming.
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(harness.contexts.isEmpty)
        lock.scenePhaseChanged(.active)
        try await waitUntil { harness.contexts.first?.isPending == true }
        harness.contexts[0].complete(.success(true))
        try await waitUntil { !lock.isLocked }
    }

    func testSystemInterruptionBeforeReactivationRetriesWithFreshContext() async throws {
        let harness = Harness()
        defer { harness.cleanup() }
        let lock = harness.makeLock()
        lock.scenePhaseChanged(.active)
        try await waitUntil { harness.contexts.first?.isPending == true }
        lock.scenePhaseChanged(.inactive)
        harness.contexts[0].complete(.failure(LAError(.systemCancel)))
        try await waitUntil { !lock.isAuthenticating }
        XCTAssertTrue(lock.isLocked)
        XCTAssertEqual(harness.contexts.count, 1)
        lock.scenePhaseChanged(.active)
        try await waitUntil { harness.contexts.count == 2 && harness.contexts[1].isPending }
        harness.contexts[1].complete(.success(true))
        try await waitUntil { !lock.isLocked }
        XCTAssertFalse(lock.isAuthenticating)
    }

    func testCancellationCallbackAfterReactivationAlsoRetries() async throws {
        let harness = Harness()
        defer { harness.cleanup() }
        let lock = harness.makeLock()
        lock.scenePhaseChanged(.active)
        try await waitUntil { harness.contexts.first?.isPending == true }
        lock.scenePhaseChanged(.inactive)
        lock.scenePhaseChanged(.active)
        harness.contexts[0].complete(.failure(LAError(.systemCancel)))
        try await waitUntil { harness.contexts.count == 2 && harness.contexts[1].isPending }
        harness.contexts[1].complete(.success(true))
        try await waitUntil { !lock.isLocked }
    }

    func testUserCancelStaysLockedAndManualUnlockStillWorks() async throws {
        let harness = Harness()
        defer { harness.cleanup() }
        let lock = harness.makeLock()
        lock.scenePhaseChanged(.active)
        try await waitUntil { harness.contexts.first?.isPending == true }
        harness.contexts[0].complete(.failure(LAError(.userCancel)))
        try await waitUntil { !lock.isAuthenticating }
        lock.scenePhaseChanged(.inactive)
        lock.scenePhaseChanged(.active)
        await Task.yield()
        XCTAssertEqual(harness.contexts.count, 1)
        XCTAssertTrue(lock.isLocked)
        let manual = Task { await lock.unlock() }
        try await waitUntil { harness.contexts.count == 2 && harness.contexts[1].isPending }
        harness.contexts[1].complete(.success(true))
        await manual.value
        XCTAssertFalse(lock.isLocked)
    }

    func testBackgroundRejectsLateSuccessAndNextForegroundCanUnlock() async throws {
        let harness = Harness()
        defer { harness.cleanup() }
        let lock = harness.makeLock()
        lock.scenePhaseChanged(.active)
        try await waitUntil { harness.contexts.first?.isPending == true }
        lock.scenePhaseChanged(.background)
        XCTAssertTrue(harness.contexts[0].invalidated)
        lock.scenePhaseChanged(.active)
        try await waitUntil { harness.contexts.count == 2 && harness.contexts[1].isPending }
        harness.contexts[0].complete(.success(true))
        await Task.yield()
        XCTAssertTrue(lock.isLocked)
        XCTAssertTrue(lock.isAuthenticating)
        harness.contexts[1].complete(.success(true))
        try await waitUntil { !lock.isLocked }
    }

    func testSuccessWhileFaceIDSheetIsInactiveIsAccepted() async throws {
        let harness = Harness()
        defer { harness.cleanup() }
        let lock = harness.makeLock()
        lock.scenePhaseChanged(.active)
        try await waitUntil { harness.contexts.first?.isPending == true }
        lock.scenePhaseChanged(.inactive)
        harness.contexts[0].complete(.success(true))
        try await waitUntil { !lock.isLocked }
        lock.scenePhaseChanged(.active)
        XCTAssertEqual(harness.contexts.count, 1)
    }

    func testRepeatedSystemCancellationDoesNotCreatePromptLoop() async throws {
        let harness = Harness()
        defer { harness.cleanup() }
        let lock = harness.makeLock()
        lock.scenePhaseChanged(.active)
        try await waitUntil { harness.contexts.first?.isPending == true }
        harness.contexts[0].complete(.failure(LAError(.notInteractive)))
        try await waitUntil { harness.contexts.count == 2 && harness.contexts[1].isPending }
        harness.contexts[1].complete(.failure(LAError(.systemCancel)))
        try await waitUntil { !lock.isAuthenticating }
        lock.scenePhaseChanged(.inactive)
        lock.scenePhaseChanged(.active)
        await Task.yield()
        XCTAssertEqual(harness.contexts.count, 2)
        XCTAssertTrue(lock.isLocked)
    }

    func testEnabledLockStartsClosedBeforeTheFirstSceneEvent() {
        let suite = "crabrix.lock.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "crabrix.privacy.appLockEnabled")

        let lock = AppLockController(defaults: defaults)
        XCTAssertTrue(lock.isEnabled)
        XCTAssertTrue(lock.isLocked)

        lock.scenePhaseChanged(.background)
        XCTAssertTrue(lock.isLocked)
    }

    func testProtectionIsOptionalByDefault() {
        let suite = "crabrix.lock.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let lock = AppLockController(defaults: defaults)
        XCTAssertFalse(lock.isEnabled)
        XCTAssertFalse(lock.isLocked)
    }
}
