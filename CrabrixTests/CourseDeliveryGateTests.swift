import Foundation
import XCTest
import UIKit
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

    func testPublicAtlasUpgradeLoadsRevisedStepsAndIllustrations() async throws {
        guard ProcessInfo.processInfo.environment["CRABRIX_RUN_COURSE_FETCH"] == "1" else {
            throw XCTSkip("Set CRABRIX_RUN_COURSE_FETCH=1 for the public Atlas upgrade gate.")
        }
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let packs = try XCTUnwrap(Bundle.main.url(
            forResource: "MigrationCoursePacks", withExtension: nil
        ))
        let keyring = try JSONDecoder().decode(CourseKeyring.self,
            from: Data(contentsOf: packs.appending(path: "production-keyring.json")))
        let installer = try CourseInstaller(
            root: root.appending(path: "installed"), appVersion: SemanticVersion("1.1")
        )
        _ = try await installer.install(
            descriptorBytes: Data(contentsOf: packs.appending(path: "algorithms.descriptor.json")),
            downloadedArchive: packs.appending(path: "algorithms-1.0.1.zip"),
            keyring: keyring
        )
        let old = try await installer.loadRepository(keyring: keyring)
        let oldAtlas = try XCTUnwrap(old.course(id: "algorithms"))
        let stepID = try XCTUnwrap(oldAtlas.units.first?.lessons.first?.id)
        let oldSession = try XCTUnwrap(CourseSession(lessonID: stepID, repository: old))
        let oldText = try XCTUnwrap(oldSession.repository.writing(for: stepID)).explanation

        let client = CourseCatalogClient(
            stateURL: root.appending(path: "catalog-state.json"), keyring: keyring
        )
        let catalog = try await client.refresh()
        let latest = CourseUpdatePlanner.latestCompatible(
            in: catalog, appVersion: try XCTUnwrap(SemanticVersion("1.1"))
        )
        let entry = try XCTUnwrap(latest["algorithms|en"])
        let manager = try CourseDownloadManager(cacheRoot: root.appending(path: "downloads"))
        let downloaded = try await manager.download(entry)
        _ = try await installer.install(
            descriptorBytes: downloaded.descriptor, downloadedArchive: downloaded.archive,
            keyring: keyring
        )
        let updated = try await installer.loadRepository(keyring: keyring)
        XCTAssertEqual(updated.loaded["algorithms"]?.contentVersion, entry.contentVersion)
        XCTAssertEqual(updated.course(id: "algorithms")?.units.flatMap(\.lessons).count, 600)
        XCTAssertNotEqual(updated.writing(for: stepID)?.explanation, oldText)
        XCTAssertNotNil(updated.illustration(for: stepID))
        XCTAssertEqual(oldSession.repository.writing(for: stepID)?.explanation, oldText)
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

    func testPublicExamplesUpgradeKeepsEditedProjectAndLoadsEveryInfographic() async throws {
        guard ProcessInfo.processInfo.environment["CRABRIX_RUN_COURSE_FETCH"] == "1" else {
            throw XCTSkip("Set CRABRIX_RUN_COURSE_FETCH=1 for the public Examples upgrade gate.")
        }
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let packs = try XCTUnwrap(Bundle.main.url(forResource: "MigrationCoursePacks", withExtension: nil))
        let keyring = try JSONDecoder().decode(CourseKeyring.self,
            from: Data(contentsOf: packs.appending(path: "production-keyring.json")))
        // Freeze the preceding production pack so bootstrap's live catalog cannot erase the upgrade case.
        let old = CourseCatalogPayload.Entry(
            courseID: "examples", language: "en", contentVersion: "1.0.2",
            descriptorURL: URL(string: "https://github.com/sergii-ziborov/crabrix-courses/releases/download/coursepack-v1.0.5/examples.descriptor.json")!,
            descriptorSHA256: "8757e74c6586194e45745798842bda6a688b46ac91d5223f9c8ed2ba53e821d1",
            archiveURL: URL(string: "https://github.com/sergii-ziborov/crabrix-courses/releases/download/coursepack-v1.0.5/examples-1.0.2.zip")!,
            archiveSHA256: "1ee0d024f47935fb17a1e3c9a4751c00a13cffc7a68283ad03841350b5172458",
            archiveBytes: 5_420_774, minimumAppVersion: "1.1",
            requiredCapabilities: ["coursepack-v1", "examples-gallery-v1"]
        )
        let manager = try CourseDownloadManager(cacheRoot: root.appending(path: "downloads"))
        let installer = try CourseInstaller(root: root.appending(path: "installed"), appVersion: SemanticVersion("1.1"))
        let oldAsset = try await manager.download(old)
        _ = try await installer.install(descriptorBytes: oldAsset.descriptor,
            downloadedArchive: oldAsset.archive, keyring: keyring)
        let previous = try await installer.loadRepository(keyring: keyring)
        XCTAssertEqual(previous.showcaseProjects().filter { $0.illustration != nil }.count, 4)
        let example = try XCTUnwrap(previous.showcaseProjects().first { $0.id == "unit-converter" })
        var edited = example.project
        edited.provenance = .academyExample(id: example.id, courseID: "examples",
            contentVersion: "1.0.2", templateHash: example.contentDigest)
        edited.files[edited.entryFile, default: ""] += "\n// retained learner edit\n"
        let libraryURL = root.appending(path: "library/recent-projects.json")
        let library = ProjectLibrary(storageURL: libraryURL)
        _ = try await library.record(project: edited, lastBuild: nil)

        let client = CourseCatalogClient(stateURL: root.appending(path: "catalog-state.json"), keyring: keyring)
        let catalog = try await client.refresh()
        let latest = CourseUpdatePlanner.latestCompatible(in: catalog,
            appVersion: try XCTUnwrap(SemanticVersion("1.1")))
        let entry = try XCTUnwrap(latest["examples|en"])
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(SemanticVersion(entry.contentVersion)),
            try XCTUnwrap(SemanticVersion("1.0.3")))
        XCTAssertEqual(CourseUpdatePlanner.updates(latest: latest,
            installedVersions: ["examples|en": "1.0.2"]).filter { $0.courseID == "examples" }.count, 1)
        let asset = try await manager.download(entry)
        _ = try await installer.install(descriptorBytes: asset.descriptor,
            downloadedArchive: asset.archive, keyring: keyring)
        let updated = try await installer.loadRepository(keyring: keyring)
        XCTAssertEqual(Set(updated.showcaseProjects().map(\.id)), Set(previous.showcaseProjects().map(\.id)))
        XCTAssertEqual(updated.showcaseProjects().count, 46)
        for item in updated.showcaseProjects() {
            let illustration = try XCTUnwrap(item.illustration, item.id)
            let image = try XCTUnwrap(UIImage(contentsOfFile: illustration.url.path), item.id)
            XCTAssertNotNil(image.cgImage, item.id)
            XCTAssertFalse(illustration.alt.isEmpty, item.id)
            XCTAssertFalse(illustration.caption.isEmpty, item.id)
            let prior = try XCTUnwrap(previous.showcaseProjects().first { $0.id == item.id })
            XCTAssertEqual(item.project.files.filter { $0.key.hasSuffix(".rs") },
                prior.project.files.filter { $0.key.hasSuffix(".rs") }, item.id)
        }
        let reopened = try await ProjectLibrary(storageURL: libraryURL).allItems()
        XCTAssertEqual(reopened.count, 1)
        XCTAssertEqual(reopened.first?.project.id, edited.id)
        XCTAssertEqual(reopened.first?.project.files, edited.files)
        XCTAssertEqual(reopened.first?.project.provenance?.course?.contentVersion, "1.0.2")
        // An already open guide retains its old snapshot until the user reopens it.
        XCTAssertNil(example.illustration)
        XCTAssertNotNil(updated.showcaseProjects().first { $0.id == example.id }?.illustration)
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
