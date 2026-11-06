import XCTest
@testable import Crabrix

@MainActor
final class LearningCloudBackupTests: XCTestCase {
    private final class Cloud: LearningCloudStorage {
        var values: [String: Any] = [:]
        var notificationObject: AnyObject? { nil }
        var writes = 0
        func set(_ data: Data, forKey key: String) { values[key] = data; writes += 1 }
        func synchronize() {}
    }

    func testFreshInstallationKeepsPreviousCopyAndDoesNotUploadEmptyProgress() throws {
        let domain = "CrabrixCloudTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        let root = FileManager.default.temporaryDirectory.appending(path: domain)
        defer { defaults.removePersistentDomain(forName: domain); try? FileManager.default.removeItem(at: root) }
        let cloud = Cloud()
        let previousKey = "crabrix.learning.backup.v1.\(UUID())"
        // A previous installation's encrypted-by-Apple storage value must not
        // be replaced by a new device's empty default state.
        let previous = Data("previous installation value".utf8)
        cloud.values[previousKey] = previous
        let coordinator = LearningBackupCoordinator(defaults: defaults, cloud: cloud,
            archiveDirectory: root, iCloudAvailable: { true })
        coordinator.setAutomatic(true)
        coordinator.saveNow()
        XCTAssertEqual(cloud.writes, 0)
        XCTAssertEqual(cloud.values[previousKey] as? Data, previous)
        defaults.set(["hello-rust"], forKey: LearningProgressKeys.completed)
        defaults.set("a secret unrelated to learning", forKey: "repository-access")
        coordinator.saveNow()
        XCTAssertEqual(cloud.writes, 1)
        XCTAssertEqual(cloud.values.count, 2)
        XCTAssertEqual(cloud.values[previousKey] as? Data, previous)
        let newKey = try XCTUnwrap(cloud.values.keys.first { $0 != previousKey })
        let snapshot = try LearningBackupCodec.decode(XCTUnwrap(cloud.values[newKey] as? Data))
        XCTAssertEqual(snapshot.completedLessonIDs, ["hello-rust"])
        XCTAssertFalse(String(decoding: try LearningBackupCodec.json(snapshot), as: UTF8.self).contains("repository-access"))
        coordinator.saveNow()
        XCTAssertEqual(cloud.writes, 1, "A metadata-only timestamp change must not cause another cloud write")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "Latest.crabrixprogress").path))
    }

    func testUnavailableAccountAndFullQuotaKeepLocalFileUsable() throws {
        let domain = "CrabrixCloudLimits.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        let root = FileManager.default.temporaryDirectory.appending(path: domain)
        defer { defaults.removePersistentDomain(forName: domain); try? FileManager.default.removeItem(at: root) }
        defaults.set(["hello-rust"], forKey: LearningProgressKeys.completed)
        let cloud = Cloud()
        let offline = LearningBackupCoordinator(defaults: defaults, cloud: cloud,
            archiveDirectory: root, iCloudAvailable: { false })
        offline.setAutomatic(true)
        offline.saveNow()
        XCTAssertEqual(cloud.writes, 0)
        XCTAssertTrue(offline.status.contains("Sign in to iCloud"))
        XCTAssertEqual(try LearningBackupCodec.decode(offline.exportData()).completedLessonIDs, ["hello-rust"])
        cloud.values["another-apple-value"] = Data(repeating: 7, count: 850 * 1_024)
        let full = LearningBackupCoordinator(defaults: defaults, cloud: cloud,
            archiveDirectory: root, iCloudAvailable: { true })
        full.setAutomatic(true)
        full.saveNow()
        XCTAssertEqual(cloud.writes, 0)
        XCTAssertTrue(full.status.contains("space"))
        XCTAssertEqual(try LearningBackupCodec.decode(full.exportData()).completedLessonIDs, ["hello-rust"])
        full.canRestore = { false }
        XCTAssertThrowsError(try full.restore(LearningBackupCodec.decode(full.exportData())))
        full.canRestore = { true }
        full.beginReviewWrite()
        XCTAssertThrowsError(try full.restore(LearningBackupCodec.decode(full.exportData())))
        full.endReviewWrite()
        XCTAssertEqual(defaults.stringArray(forKey: LearningProgressKeys.completed), ["hello-rust"])
    }
}
