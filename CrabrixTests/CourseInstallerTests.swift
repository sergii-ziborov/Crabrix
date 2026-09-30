import Foundation
import XCTest
@testable import Crabrix

final class CourseInstallerTests: XCTestCase {
    private func fixture(_ name: String) throws -> URL {
        let packs = try XCTUnwrap(Bundle.main.url(
            forResource: "MigrationCoursePacks", withExtension: nil
        ))
        let url = packs.appending(path: name)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        return url
    }

    func testInstallPreservesActiveVersionAfterTamperedDownload() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = try CourseInstaller(root: root, appVersion: SemanticVersion("1.1"))
        let descriptor = try Data(contentsOf: fixture("basics.descriptor.json"))
        let keys = try JSONDecoder().decode(CourseKeyring.self,
                                            from: Data(contentsOf: fixture("production-keyring.json")))
        let installed = try await installer.install(
            descriptorBytes: descriptor,
            downloadedArchive: fixture("basics-1.0.1.zip"),
            keyring: keys
        )
        XCTAssertEqual(installed.contentVersion, "1.0.1")
        let course = root.appending(path: "basics/en/1.0.1/course.json")
        XCTAssertEqual(try JSONSerialization.jsonObject(with: Data(contentsOf: course)) as? [String: Any] != nil,
                       true)

        var tampered = try Data(contentsOf: fixture("basics-1.0.1.zip"))
        tampered[tampered.count - 1] ^= 1
        let badArchive = root.appending(path: "basics-1.0.1.zip")
        try tampered.write(to: badArchive)
        XCTAssertThrowsError(try CoursePackVerifier.verify(
            descriptorBytes: descriptor, archiveURL: badArchive, keyring: keys
        ))
        let stillInstalled = try await installer.installed()
        XCTAssertEqual(stillInstalled.map(\.contentVersion), ["1.0.1"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: course.path))
    }

    func testRecoveryDiscardsUncommittedVersionAndKeepsOldPointer() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = try CourseInstaller(root: root, appVersion: SemanticVersion("1.1"))
        let keys = try JSONDecoder().decode(CourseKeyring.self,
                                            from: Data(contentsOf: fixture("production-keyring.json")))
        _ = try await installer.install(
            descriptorBytes: Data(contentsOf: fixture("basics.descriptor.json")),
            downloadedArchive: fixture("basics-1.0.1.zip"), keyring: keys
        )
        let orphan = root.appending(path: "basics/en/9.9.9")
        let staging = root.appending(path: ".staging/interrupted")
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let journal: [String: String] = [
            "key": "basics|en", "targetPath": orphan.path,
            "stagingPath": staging.path, "archiveSHA256": String(repeating: "0", count: 64)
        ]
        try JSONSerialization.data(withJSONObject: journal).write(
            to: root.appending(path: "journal.json"), options: .atomic
        )
        let active = try await installer.installed()
        XCTAssertEqual(active.map(\.contentVersion), ["1.0.1"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "basics/en/1.0.1/course.json").path))
    }

    func testRecoveryRemovesPreJournalStagingAndKeepsInstalledCourse() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = try CourseInstaller(root: root, appVersion: SemanticVersion("1.1"))
        let keys = try JSONDecoder().decode(CourseKeyring.self,
                                            from: Data(contentsOf: fixture("production-keyring.json")))
        _ = try await installer.install(
            descriptorBytes: Data(contentsOf: fixture("basics.descriptor.json")),
            downloadedArchive: fixture("basics-1.0.1.zip"), keyring: keys
        )
        let interrupted = root.appending(path: ".staging/interrupted/payload")
        try FileManager.default.createDirectory(at: interrupted, withIntermediateDirectories: true)
        try Data("partial archive".utf8).write(to: interrupted.appending(path: "course.json"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "journal.json").path))

        let afterRelaunch = try CourseInstaller(root: root, appVersion: SemanticVersion("1.1"))
        let active = try await afterRelaunch.installed()

        XCTAssertEqual(active.map(\.contentVersion), ["1.0.1"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: ".staging").path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appending(path: "basics/en/1.0.1/course.json").path
        ))
    }

    func testMinimumAppVersionRejectsBeforeStaging() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = try CourseInstaller(root: root, appVersion: SemanticVersion("1.0"))
        let keys = try JSONDecoder().decode(CourseKeyring.self,
                                            from: Data(contentsOf: fixture("production-keyring.json")))
        do {
            _ = try await installer.install(
                descriptorBytes: Data(contentsOf: fixture("basics.descriptor.json")),
                downloadedArchive: fixture("basics-1.0.1.zip"), keyring: keys
            )
            XCTFail("An incompatible course became installed")
        } catch CoursePackError.incompatibleCapability {
            let installed = try await installer.installed()
            XCTAssertTrue(installed.isEmpty)
        }
    }

    func testOversizedCachedArchiveRejectsBeforeStaging() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = try CourseInstaller(root: root, appVersion: SemanticVersion("1.1"))
        let archive = root.appending(path: "oversized.zip")
        XCTAssertTrue(FileManager.default.createFile(atPath: archive.path, contents: nil))
        let handle = try FileHandle(forWritingTo: archive)
        try handle.truncate(atOffset: UInt64(CoursePackVerifier.maximumArchiveBytes + 1))
        try handle.close()
        let keys = try JSONDecoder().decode(CourseKeyring.self,
                                            from: Data(contentsOf: fixture("production-keyring.json")))

        do {
            _ = try await installer.install(
                descriptorBytes: Data(contentsOf: fixture("basics.descriptor.json")),
                downloadedArchive: archive, keyring: keys
            )
            XCTFail("An oversized cache file was accepted")
        } catch CoursePackError.sizeLimit {
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: root.appending(path: ".staging").path
            ))
            let installed = try await installer.installed()
            XCTAssertTrue(installed.isEmpty)
        }
    }

    func testSeparateInstallersKeepEveryConcurrentCourseActive() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let names = [
            "algorithms", "basics", "concurrency", "interview",
            "ownership", "projects", "systems"
        ]
        let inputs = try names.map { name in
            (try Data(contentsOf: fixture("\(name).descriptor.json")),
             try fixture("\(name)-1.0.1.zip"))
        }
        let keys = try JSONDecoder().decode(CourseKeyring.self,
                                            from: Data(contentsOf: fixture("production-keyring.json")))

        try await withThrowingTaskGroup(of: Void.self) { group in
            for (descriptor, archive) in inputs {
                group.addTask {
                    let installer = try CourseInstaller(
                        root: root, appVersion: SemanticVersion("1.1")
                    )
                    _ = try await installer.install(
                        descriptorBytes: descriptor, downloadedArchive: archive, keyring: keys
                    )
                }
            }
            try await group.waitForAll()
        }

        let installer = try CourseInstaller(root: root, appVersion: SemanticVersion("1.1"))
        let active = try await installer.installed()
        XCTAssertEqual(Set(active.map(\.courseID)), Set(names))
        let repository = try await installer.loadRepository(keyring: keys)
        XCTAssertEqual(repository.courses.count, names.count)
        XCTAssertEqual(repository.courses.flatMap { $0.units.flatMap(\.lessons) }.count, 742)
    }
}
