import CryptoKit
import Foundation
import XCTest
import ZIPFoundation
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
        let staging = root.appending(path: ".staging/\(UUID().uuidString)")
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

    func testRecoveryRejectsJournalThatTargetsAnotherActiveCourse() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = try CourseInstaller(root: root, appVersion: SemanticVersion("1.1"))
        let keys = try JSONDecoder().decode(CourseKeyring.self,
                                            from: Data(contentsOf: fixture("production-keyring.json")))
        _ = try await installer.install(
            descriptorBytes: Data(contentsOf: fixture("basics.descriptor.json")),
            downloadedArchive: fixture("basics-1.0.1.zip"), keyring: keys
        )
        let active = root.appending(path: "basics/en/1.0.1/course.json")
        let malicious: [String: String] = [
            "key": "ownership|en",
            "targetPath": active.deletingLastPathComponent().path,
            "stagingPath": root.appending(path: ".staging/\(UUID().uuidString)").path,
            "archiveSHA256": String(repeating: "0", count: 64)
        ]
        try JSONSerialization.data(withJSONObject: malicious).write(
            to: root.appending(path: "journal.json"), options: .atomic
        )

        do {
            _ = try await installer.installed()
            XCTFail("A mismatched journal was accepted")
        } catch CoursePackError.unsafeArchive {
            XCTAssertTrue(FileManager.default.fileExists(atPath: active.path))
            XCTAssertNotNil(try JSONSerialization.jsonObject(with: Data(contentsOf: active)))
        }
    }

    func testRecoveryKeepsCommittedVersionAfterIndexWrite() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = try CourseInstaller(root: root, appVersion: SemanticVersion("1.1"))
        let keys = try JSONDecoder().decode(CourseKeyring.self,
                                            from: Data(contentsOf: fixture("production-keyring.json")))
        let record = try await installer.install(
            descriptorBytes: Data(contentsOf: fixture("basics.descriptor.json")),
            downloadedArchive: fixture("basics-1.0.1.zip"), keyring: keys
        )
        let target = root.appending(path: "basics/en/1.0.1")
        let staging = root.appending(path: ".staging/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let journal: [String: String] = [
            "key": "basics|en", "targetPath": target.path,
            "stagingPath": staging.path, "archiveSHA256": record.archiveSHA256
        ]
        try JSONSerialization.data(withJSONObject: journal).write(
            to: root.appending(path: "journal.json"), options: .atomic
        )

        let afterRelaunch = try CourseInstaller(root: root, appVersion: SemanticVersion("1.1"))
        let active = try await afterRelaunch.installed()
        XCTAssertEqual(active.map(\.contentVersion), ["1.0.1"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appending(path: "course.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "journal.json").path))
    }

    func testRecoveryRejectsJournalThroughCourseDirectorySymlink() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let outside = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        let installer = try CourseInstaller(root: root, appVersion: SemanticVersion("1.1"))
        let externalVersion = outside.appending(path: "9.9.9")
        try FileManager.default.createDirectory(at: externalVersion, withIntermediateDirectories: true)
        let evidence = externalVersion.appending(path: "proof.txt")
        try Data("keep".utf8).write(to: evidence)
        try FileManager.default.createDirectory(
            at: root.appending(path: "ownership"), withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: root.appending(path: "ownership/en"), withDestinationURL: outside
        )
        let malicious: [String: String] = [
            "key": "ownership|en",
            "targetPath": root.appending(path: "ownership/en/9.9.9").path,
            "stagingPath": root.appending(path: ".staging/\(UUID().uuidString)").path,
            "archiveSHA256": String(repeating: "0", count: 64)
        ]
        try JSONSerialization.data(withJSONObject: malicious).write(
            to: root.appending(path: "journal.json"), options: .atomic
        )

        do {
            _ = try await installer.installed()
            XCTFail("A symlinked journal target was accepted")
        } catch CoursePackError.unsafeArchive {
            XCTAssertEqual(try Data(contentsOf: evidence), Data("keep".utf8))
        }
    }

    private func productionKeys() throws -> CourseKeyring {
        try JSONDecoder().decode(CourseKeyring.self, from: Data(contentsOf: fixture("production-keyring.json")))
    }

    private func installBundled(_ names: [String], root: URL) async throws -> CourseInstaller {
        let installer = try CourseInstaller(root: root, appVersion: SemanticVersion("1.1"))
        for name in names {
            _ = try await installer.install(
                descriptorBytes: Data(contentsOf: fixture("\(name).descriptor.json")),
                downloadedArchive: fixture("\(name)-1.0.1.zip"), keyring: productionKeys()
            )
        }
        return installer
    }

    func testOneDamagedCourseLeavesTheOthersUsableAndCanBeReplaced() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = try await installBundled(["basics", "ownership"], root: root)
        let keys = try productionKeys()
        try Data("{}".utf8).write(to: root.appending(path: "basics/en/1.0.1/course.json"))

        let repository = try await installer.loadRepository(keyring: keys)
        XCTAssertEqual(repository.courses.map(\.id), ["ownership"])
        XCTAssertEqual(repository.unavailable.map(\.courseID), ["basics"])
        XCTAssertEqual(repository.unavailable.first?.contentVersion, "1.0.1")
        XCTAssertNil(repository.lesson(id: "variables"))
        XCTAssertNotNil(repository.lesson(id: "borrowing"))

        // Removing it clears the failure and keeps everything else.
        try await installer.uninstall(courseID: "basics", language: "en")
        let removed = try await installer.loadRepository(keyring: keys)
        XCTAssertTrue(removed.unavailable.isEmpty)
        XCTAssertEqual(removed.courses.map(\.id), ["ownership"])

        // Downloading it again brings the course back.
        _ = try await installer.install(
            descriptorBytes: Data(contentsOf: fixture("basics.descriptor.json")),
            downloadedArchive: fixture("basics-1.0.1.zip"), keyring: keys
        )
        let restored = try await installer.loadRepository(keyring: keys)
        XCTAssertTrue(restored.unavailable.isEmpty)
        XCTAssertEqual(Set(restored.courses.map(\.id)), ["basics", "ownership"])
    }

    /// A pack signed by a throwaway key, so a test can publish content the real
    /// publisher never would.
    private struct SignedPack {
        let descriptor: Data
        let archive: URL

        init(courseID: String, version: String, theme: String, directory: URL, key: Curve25519.Signing.PrivateKey) throws {
            let course = try JSONSerialization.data(withJSONObject: [
                "id": courseID, "language": "en", "contentVersion": version, "order": 0, "level": "1",
                "title": courseID, "subtitle": "test", "systemImage": "book", "theme": theme, "unitIDs": []
            ] as [String: Any])
            let terms = Data("[]".utf8)
            func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
            let manifest = try JSONSerialization.data(withJSONObject: [
                "schemaVersion": 1, "courseID": courseID, "language": "en", "contentVersion": version,
                "files": [
                    ["path": "course.json", "bytes": course.count, "sha256": digest(course)],
                    ["path": "terms.json", "bytes": terms.count, "sha256": digest(terms)],
                ]
            ] as [String: Any])
            let name = "\(courseID)-\(version).zip"
            archive = directory.appending(path: name)
            let zip = try Archive(url: archive, accessMode: .create)
            for (path, bytes) in [("manifest.json", manifest), ("course.json", course), ("terms.json", terms)] {
                try zip.addEntry(with: path, type: .file, uncompressedSize: Int64(bytes.count)) { position, size in
                    bytes.subdata(in: Int(position)..<Int(position) + size)
                }
            }
            let zipped = try Data(contentsOf: archive)
            let payload = try JSONSerialization.data(withJSONObject: [
                "schemaVersion": 1, "courseID": courseID, "language": "en", "contentVersion": version,
                "archiveName": name, "archiveBytes": zipped.count, "archiveSHA256": digest(zipped),
                "courseDigest": digest(course), "minimumAppVersion": "1.0", "requiredCapabilities": ["coursepack-v1"]
            ] as [String: Any])
            descriptor = try JSONEncoder().encode(CourseEnvelope(
                keyID: "test-key",
                payloadBase64: payload.base64EncodedString(),
                signatureBase64: try key.signature(for: CoursePackVerifier.descriptorDomain + payload).base64EncodedString()
            ))
        }
    }

    func testSignedUpdateThisAppCannotReadKeepsTheWorkingVersion() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let work = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: work)
        }
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let key = Curve25519.Signing.PrivateKey()
        let keys = CourseKeyring(keys: ["test-key": key.publicKey.rawRepresentation.base64EncodedString()])
        let installer = try CourseInstaller(root: root, appVersion: SemanticVersion("1.1"))

        let working = try SignedPack(courseID: "custom", version: "1.0.0", theme: "basics", directory: work, key: key)
        _ = try await installer.install(descriptorBytes: working.descriptor, downloadedArchive: working.archive, keyring: keys)
        // The same failure as an unknown exercise kind: signed, but undecodable here.
        let unreadable = try SignedPack(courseID: "custom", version: "2.0.0", theme: "from-the-future", directory: work, key: key)
        do {
            _ = try await installer.install(descriptorBytes: unreadable.descriptor, downloadedArchive: unreadable.archive, keyring: keys)
            XCTFail("An update this app cannot read became active")
        } catch CoursePackError.manifestMismatch {}

        let installed = try await installer.installed()
        XCTAssertEqual(installed.map(\.contentVersion), ["1.0.0"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "custom/en/2.0.0").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "journal.json").path))
        let repository = try await installer.loadRepository(keyring: keys)
        XCTAssertEqual(repository.courses.map(\.id), ["custom"])
        XCTAssertTrue(repository.unavailable.isEmpty)
    }

    func testOrphanTreeDoesNotBlockReinstallingThatVersion() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = try await installBundled(["basics"], root: root)
        try await installer.uninstall(courseID: "basics", language: "en")
        // A kill between the index write and the tree removal leaves this behind.
        let orphan = root.appending(path: "basics/en/1.0.1")
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        try Data("stale".utf8).write(to: orphan.appending(path: "leftover.txt"))

        _ = try await installer.install(
            descriptorBytes: Data(contentsOf: fixture("basics.descriptor.json")),
            downloadedArchive: fixture("basics-1.0.1.zip"), keyring: productionKeys()
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.appending(path: "leftover.txt").path))
        let repository = try await installer.loadRepository(keyring: productionKeys())
        XCTAssertEqual(repository.courses.map(\.id), ["basics"])
    }

    func testReplacedVersionTreesAreRemovedAndTheActiveOneKept() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = try await installBundled(["basics"], root: root)
        let manager = FileManager.default
        for orphan in ["basics/en/0.9.0", "basics/en/1.0.0", "ghost/en/1.0.0"] {
            try manager.createDirectory(at: root.appending(path: orphan), withIntermediateDirectories: true)
        }
        let marker = root.appending(path: "baseline-activation-v1.json")
        try Data("{}".utf8).write(to: marker)

        try await installer.removeReplacedVersions()

        XCTAssertFalse(manager.fileExists(atPath: root.appending(path: "basics/en/0.9.0").path))
        XCTAssertFalse(manager.fileExists(atPath: root.appending(path: "basics/en/1.0.0").path))
        XCTAssertFalse(manager.fileExists(atPath: root.appending(path: "ghost/en/1.0.0").path))
        XCTAssertTrue(manager.fileExists(atPath: marker.path))
        let repository = try await installer.loadRepository(keyring: productionKeys())
        XCTAssertEqual(repository.courses.map(\.id), ["basics"])
    }

    func testJournalWrittenInAnOlderContainerPathStillRecovers() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = try await installBundled(["basics"], root: root)
        let orphan = root.appending(path: "basics/en/9.9.9")
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        let identifier = UUID().uuidString
        let staging = root.appending(path: ".staging/\(identifier)")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let oldContainer = "/var/mobile/Containers/Data/Application/OLD/Library/Application Support/Crabrix/Courses"
        let journal: [String: String] = [
            "key": "basics|en", "targetPath": "\(oldContainer)/basics/en/9.9.9",
            "stagingPath": "\(oldContainer)/.staging/\(identifier)",
            "archiveSHA256": String(repeating: "0", count: 64)
        ]
        try JSONSerialization.data(withJSONObject: journal).write(to: root.appending(path: "journal.json"))

        let active = try await installer.installed()

        XCTAssertEqual(active.map(\.contentVersion), ["1.0.1"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "journal.json").path))
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
