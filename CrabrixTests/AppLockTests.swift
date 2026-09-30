import XCTest
@testable import Crabrix

@MainActor
final class AppLockTests: XCTestCase {
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
