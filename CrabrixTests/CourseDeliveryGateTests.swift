import Foundation
import XCTest
@testable import Crabrix

final class CourseDeliveryGateTests: XCTestCase {
    func testPublicSignedCatalogAndCourseInstall() async throws {
        guard ProcessInfo.processInfo.environment["CRABRIX_RUN_COURSE_FETCH"] == "1" else {
            throw XCTSkip("Set CRABRIX_RUN_COURSE_FETCH=1 for the public course delivery gate.")
        }
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer {
            if FileManager.default.fileExists(atPath: root.path) {
                try? FileManager.default.removeItem(at: root)
            }
        }
        let bundle = Bundle.main
        let packs = try XCTUnwrap(bundle.url(forResource: "MigrationCoursePacks", withExtension: nil))
        let keyring = try JSONDecoder().decode(
            CourseKeyring.self,
            from: Data(contentsOf: packs.appending(path: "production-keyring.json"))
        )
        let client = CourseCatalogClient(
            stateURL: root.appending(path: "catalog-state.json"), keyring: keyring
        )
        let catalog = try await client.refresh()
        XCTAssertGreaterThanOrEqual(catalog.courses.count, 7)
        let basics = try XCTUnwrap(catalog.courses.first { $0.courseID == "basics" })
        let manager = try CourseDownloadManager(cacheRoot: root.appending(path: "downloads"))
        let asset = try await manager.download(basics)
        let installer = try CourseInstaller(
            root: root.appending(path: "installed"), appVersion: SemanticVersion("1.1")
        )
        _ = try await installer.install(
            descriptorBytes: asset.descriptor, downloadedArchive: asset.archive,
            keyring: keyring
        )
        let repository = try InstalledCourseRepository(
            root: root.appending(path: "installed"),
            records: await installer.installed(), keyring: keyring
        )
        XCTAssertEqual(repository.courses.map(\.id), ["basics"])
        XCTAssertNotNil(repository.lesson(id: "hello-rust"))
    }
}
