import Foundation
import XCTest
@testable import Crabrix

final class CourseDeliveryGateTests: XCTestCase {
    func testPublicArchiveResumesFromPersistedRange() async throws {
        guard ProcessInfo.processInfo.environment["CRABRIX_RUN_COURSE_FETCH"] == "1" else {
            throw XCTSkip("Set CRABRIX_RUN_COURSE_FETCH=1 for the public course delivery gate.")
        }
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let packs = try XCTUnwrap(Bundle.main.url(
            forResource: "MigrationCoursePacks", withExtension: nil
        ))
        let keyring = try JSONDecoder().decode(CourseKeyring.self,
            from: Data(contentsOf: packs.appending(path: "production-keyring.json")))
        let catalog = try CoursePackVerifier.catalog(
            bytes: Data(contentsOf: packs.appending(path: "catalog.v1.json")),
            keyring: keyring, lastAcceptedSequence: 0
        )
        let basics = try XCTUnwrap(catalog.courses.first { $0.courseID == "basics" })
        let archive = try Data(contentsOf: packs.appending(path: "basics-1.0.1.zip"))
        XCTAssertEqual(archive.count, basics.archiveBytes)

        let cache = root.appending(path: "downloads")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let partial = cache.appending(path: "\(basics.archiveSHA256).partial")
        try Data(archive.prefix(70_000)).write(to: partial)
        let transfer: [String: Any] = [
            "archiveSHA256": basics.archiveSHA256,
            "archiveBytes": basics.archiveBytes,
            "strongETag": NSNull()
        ]
        try JSONSerialization.data(withJSONObject: transfer).write(
            to: cache.appending(path: "\(basics.archiveSHA256).transfer.json"), options: .atomic
        )

        let manager = try CourseDownloadManager(cacheRoot: cache)
        let asset = try await manager.download(basics)
        XCTAssertEqual(try Data(contentsOf: asset.archive), archive)
        XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
    }

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
        XCTAssertGreaterThanOrEqual(catalog.courses.count, 8)
        let basics = try XCTUnwrap(catalog.courses.first { $0.courseID == "basics" })
        let projects = try XCTUnwrap(catalog.courses.first { $0.courseID == "projects" })
        let examples = try XCTUnwrap(catalog.courses.first { $0.courseID == "examples" })
        let manager = try CourseDownloadManager(cacheRoot: root.appending(path: "downloads"))
        let asset = try await manager.download(basics)
        let projectsAsset = try await manager.download(projects)
        let examplesAsset = try await manager.download(examples)
        let installer = try CourseInstaller(
            root: root.appending(path: "installed"), appVersion: SemanticVersion("1.1")
        )
        _ = try await installer.install(
            descriptorBytes: asset.descriptor, downloadedArchive: asset.archive,
            keyring: keyring
        )
        _ = try await installer.install(
            descriptorBytes: projectsAsset.descriptor,
            downloadedArchive: projectsAsset.archive, keyring: keyring
        )
        _ = try await installer.install(
            descriptorBytes: examplesAsset.descriptor,
            downloadedArchive: examplesAsset.archive, keyring: keyring
        )
        let repository = try InstalledCourseRepository(
            root: root.appending(path: "installed"),
            records: await installer.installed(), keyring: keyring
        )
        XCTAssertEqual(repository.courses.map(\.id), ["basics", "projects", "examples"])
        XCTAssertNotNil(repository.lesson(id: "hello-rust"))
        XCTAssertEqual(repository.showcaseProjects().count, 46)
        XCTAssertTrue(repository.showcaseProjects().allSatisfy(\.isGuided))
        XCTAssertTrue(repository.loaded["projects"]?.showcases.isEmpty == true)
    }
}
