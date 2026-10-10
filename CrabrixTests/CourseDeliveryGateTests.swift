import Foundation
import XCTest
@testable import Crabrix

final class CourseDeliveryGateTests: XCTestCase {
    func testUpdatePlannerSelectsLatestCompatibleVersionWithoutDowngrading() throws {
        let packs = try XCTUnwrap(Bundle.main.url(
            forResource: "MigrationCoursePacks", withExtension: nil
        ))
        let keyring = try JSONDecoder().decode(CourseKeyring.self,
            from: Data(contentsOf: packs.appending(path: "production-keyring.json")))
        let bundled = try CoursePackVerifier.catalog(
            bytes: Data(contentsOf: packs.appending(path: "catalog.v1.json")),
            keyring: keyring, lastAcceptedSequence: 0
        )
        let old = try XCTUnwrap(bundled.courses.first { $0.courseID == "basics" })
        let update = CourseCatalogPayload.Entry(
            courseID: old.courseID, language: old.language, contentVersion: "1.0.2",
            descriptorURL: old.descriptorURL, descriptorSHA256: old.descriptorSHA256,
            archiveURL: old.archiveURL, archiveSHA256: old.archiveSHA256,
            archiveBytes: old.archiveBytes, minimumAppVersion: "1.1",
            requiredCapabilities: old.requiredCapabilities
        )
        let future = CourseCatalogPayload.Entry(
            courseID: old.courseID, language: old.language, contentVersion: "1.0.3",
            descriptorURL: old.descriptorURL, descriptorSHA256: old.descriptorSHA256,
            archiveURL: old.archiveURL, archiveSHA256: old.archiveSHA256,
            archiveBytes: old.archiveBytes, minimumAppVersion: "2.0",
            requiredCapabilities: old.requiredCapabilities
        )
        let catalog = CourseCatalogPayload(
            schemaVersion: 1, sequence: bundled.sequence + 1, releaseNotes: "",
            courses: [old, update, future]
        )
        let latest = CourseUpdatePlanner.latestCompatible(
            in: catalog, appVersion: try XCTUnwrap(SemanticVersion("1.1"))
        )
        XCTAssertEqual(latest["basics|en"]?.contentVersion, "1.0.2")
        XCTAssertEqual(CourseUpdatePlanner.updates(
            latest: latest, installedVersions: ["basics|en": old.contentVersion]
        ).map(\.contentVersion), ["1.0.2"])
        XCTAssertTrue(CourseUpdatePlanner.updates(
            latest: latest, installedVersions: ["basics|en": "1.0.3"]
        ).isEmpty)
    }

    func testPublicCourseUpgradeKeepsOpenLessonSnapshotAndStableIDs() async throws {
        guard ProcessInfo.processInfo.environment["CRABRIX_RUN_COURSE_FETCH"] == "1" else {
            throw XCTSkip("Set CRABRIX_RUN_COURSE_FETCH=1 for the public course upgrade gate.")
        }
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let packs = try XCTUnwrap(Bundle.main.url(
            forResource: "MigrationCoursePacks", withExtension: nil
        ))
        let keyring = try JSONDecoder().decode(CourseKeyring.self,
            from: Data(contentsOf: packs.appending(path: "production-keyring.json")))
        let installedRoot = root.appending(path: "installed")
        let installer = try CourseInstaller(root: installedRoot, appVersion: SemanticVersion("1.1"))
        _ = try await installer.install(
            descriptorBytes: Data(contentsOf: packs.appending(path: "basics.descriptor.json")),
            downloadedArchive: packs.appending(path: "basics-1.0.1.zip"), keyring: keyring
        )
        let oldRepository = try await installer.loadRepository(keyring: keyring)
        let oldSession = try XCTUnwrap(CourseSession(
            lessonID: "hello-rust", repository: oldRepository
        ))
        let oldExplanation = try XCTUnwrap(oldSession.repository.writing(for: "hello-rust"))
            .explanation
        XCTAssertEqual(oldSession.contentVersion, "1.0.1")

        let client = CourseCatalogClient(
            stateURL: root.appending(path: "catalog-state.json"), keyring: keyring
        )
        let publicCatalog = try await client.refresh()
        let cachedCatalog = try await client.current()
        XCTAssertEqual(cachedCatalog?.sequence, publicCatalog.sequence)
        let latest = CourseUpdatePlanner.latestCompatible(
            in: publicCatalog, appVersion: try XCTUnwrap(SemanticVersion("1.1"))
        )
        let entry = try XCTUnwrap(latest["basics|en"])
        XCTAssertGreaterThan(try XCTUnwrap(SemanticVersion(entry.contentVersion)),
                             try XCTUnwrap(SemanticVersion(oldSession.contentVersion)))
        let manager = try CourseDownloadManager(cacheRoot: root.appending(path: "downloads"))
        let downloaded = try await manager.download(entry)
        _ = try await installer.install(
            descriptorBytes: downloaded.descriptor,
            downloadedArchive: downloaded.archive, keyring: keyring
        )
        let updatedRepository = try await installer.loadRepository(keyring: keyring)
        XCTAssertEqual(updatedRepository.loaded["basics"]?.contentVersion, entry.contentVersion)
        XCTAssertNotEqual(updatedRepository.writing(for: "hello-rust")?.explanation,
                          oldExplanation)
        XCTAssertNotNil(updatedRepository.lesson(id: oldSession.lessonID))
        XCTAssertEqual(oldSession.repository.writing(for: oldSession.lessonID)?.explanation,
                       oldExplanation)
        XCTAssertTrue(FileManager.default.fileExists(atPath: installedRoot.appending(
            path: "basics/en/1.0.1/course.json"
        ).path))
    }

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
        if let version = SemanticVersion(examples.contentVersion),
           let minimum = SemanticVersion("1.0.1"), version >= minimum {
            let ferris = try XCTUnwrap(repository.showcaseProjects().first {
                $0.id == "ferris-pixel-art"
            })
            XCTAssertTrue(ferris.project.files["README.md"]?.contains("## What to notice") == true)
            let image = try XCTUnwrap(ferris.illustration)
            XCTAssertTrue(FileManager.default.fileExists(atPath: image.url.path))
            XCTAssertFalse(image.alt.isEmpty)
        }
    }
}
