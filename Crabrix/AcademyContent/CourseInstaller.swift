import CryptoKit
import Foundation
import ZIPFoundation

/// The index is the activation pointer. Every course version on disk is immutable.
struct InstalledCourseRecord: Codable, Sendable {
    let courseID: String
    let language: String
    let contentVersion: String
    let archiveSHA256: String
    let keyID: String
    let descriptorBase64: String
}

private struct CourseInstallIndex: Codable {
    var active: [String: InstalledCourseRecord] = [:]
}

private struct CourseInstallJournal: Codable {
    let key: String
    let targetPath: String
    let stagingPath: String
    let archiveSHA256: String
}

/// Serializes installation and atomically changes only the active-version index.
/// Old versions remain on disk, so a pinned lesson session can keep using them.
actor CourseInstaller {
    /// Callers construct separate installer actors for downloads and bootstrap.
    /// Their index and journal still belong to the same on-disk transaction.
    private static let coordinationLock = NSRecursiveLock()
    private let root: URL
    private let fileManager = FileManager.default
    private let appVersion: SemanticVersion

    init(root: URL? = nil, appVersion: SemanticVersion? = nil) throws {
        if let root {
            self.root = root
        } else {
            guard let support = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first else { throw CoursePackError.invalidCatalog }
            self.root = support.appending(path: "Crabrix/Courses", directoryHint: .isDirectory)
        }
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var courseRoot = self.root
        try courseRoot.setResourceValues(values)
        let bundleVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        self.appVersion = appVersion ?? SemanticVersion(bundleVersion ?? "0")
            ?? SemanticVersion(major: 0, minor: 0, patch: 0)
    }

    func installed() throws -> [InstalledCourseRecord] {
        try Self.coordinationLock.withLock { try installedUnderLock() }
    }

    func loadRepository(keyring: CourseKeyring) throws -> InstalledCourseRepository {
        try Self.coordinationLock.withLock {
            try InstalledCourseRepository(
                root: root, records: installedUnderLock(), keyring: keyring
            )
        }
    }

    private func installedUnderLock() throws -> [InstalledCourseRecord] {
        try recover()
        return try readIndex().active.values.sorted {
            $0.courseID == $1.courseID ? $0.language < $1.language : $0.courseID < $1.courseID
        }
    }

    /// Removes replaceable course material only. The index is changed first so
    /// a crash cannot point to a partially deleted tree. Open CourseSession
    /// values retain a fully decoded snapshot, and user projects/progress are
    /// stored outside this root.
    func uninstall(courseID: String, language: String) throws {
        try Self.coordinationLock.withLock {
            try uninstallUnderLock(courseID: courseID, language: language)
        }
    }

    private func uninstallUnderLock(courseID: String, language: String) throws {
        try recover()
        let safeCourse = try component(courseID)
        let safeLanguage = try component(language)
        let key = "\(safeCourse)|\(safeLanguage)"
        var index = try readIndex()
        index.active.removeValue(forKey: key)
        try writeIndex(index)
        let directory = root.appending(path: "\(safeCourse)/\(safeLanguage)", directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
    }

    func install(descriptorBytes: Data, downloadedArchive: URL, keyring: CourseKeyring) throws
        -> InstalledCourseRecord {
        try Self.coordinationLock.withLock {
            try installUnderLock(descriptorBytes: descriptorBytes,
                                 downloadedArchive: downloadedArchive, keyring: keyring)
        }
    }

    private func installUnderLock(descriptorBytes: Data, downloadedArchive: URL,
                                  keyring: CourseKeyring) throws
        -> InstalledCourseRecord {
        try recover()
        let (payload, keyID) = try CoursePackVerifier.signedPayload(
            descriptorBytes, domain: CoursePackVerifier.descriptorDomain, keyring: keyring
        )
        guard let descriptor = try? JSONDecoder().decode(CourseDescriptorPayload.self, from: payload)
        else { throw CoursePackError.invalidEnvelope }
        try CourseCompatibility.requireSupported(descriptor, appVersion: appVersion)
        let courseID = try component(descriptor.courseID)
        let language = try component(descriptor.language)
        let version = try component(descriptor.contentVersion)
        let archiveName = try component(descriptor.archiveName)
        guard descriptor.archiveBytes > 0,
              descriptor.archiveBytes <= CoursePackVerifier.maximumArchiveBytes else {
            throw CoursePackError.sizeLimit
        }
        let key = "\(courseID)|\(language)"
        let target = root.appending(path: "\(courseID)/\(language)/\(version)", directoryHint: .isDirectory)
        let record = InstalledCourseRecord(
            courseID: courseID, language: language, contentVersion: version,
            archiveSHA256: descriptor.archiveSHA256, keyID: keyID,
            descriptorBase64: descriptorBytes.base64EncodedString()
        )
        let old = try readIndex()
        if let current = old.active[key], current.contentVersion == version {
            guard current.archiveSHA256 == descriptor.archiveSHA256 else {
                throw CoursePackError.immutableVersionConflict
            }
            return current
        }
        guard !fileManager.fileExists(atPath: target.path) else {
            throw CoursePackError.immutableVersionConflict
        }
        let source = try downloadedArchive.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        )
        guard source.isRegularFile == true, source.isSymbolicLink != true else {
            throw CoursePackError.unsafeArchive(downloadedArchive.lastPathComponent)
        }
        guard let sourceBytes = source.fileSize else { throw CoursePackError.archiveDigestMismatch }
        guard sourceBytes <= CoursePackVerifier.maximumArchiveBytes else {
            throw CoursePackError.sizeLimit
        }
        guard sourceBytes == descriptor.archiveBytes else {
            throw CoursePackError.archiveDigestMismatch
        }

        let staging = root.appending(path: ".staging/\(UUID().uuidString)", directoryHint: .isDirectory)
        let payloadRoot = staging.appending(path: "payload", directoryHint: .isDirectory)
        let cacheArchive = staging.appending(path: archiveName)
        try fileManager.createDirectory(at: payloadRoot, withIntermediateDirectories: true)
        do {
            try Task.checkCancellation()
            try copyVerifiedArchive(
                from: downloadedArchive, to: cacheArchive,
                expectedBytes: descriptor.archiveBytes, expectedSHA256: descriptor.archiveSHA256
            )
            let verified = try CoursePackVerifier.verify(
                descriptorBytes: descriptorBytes, archiveURL: cacheArchive, keyring: keyring
            )
            guard verified.descriptor.courseID == courseID,
                  verified.descriptor.contentVersion == version,
                  verified.keyID == keyID else { throw CoursePackError.invalidEnvelope }
            try extract(verified, to: payloadRoot)
            try Task.checkCancellation()

            let journal = CourseInstallJournal(
                key: key, targetPath: target.path, stagingPath: staging.path,
                archiveSHA256: descriptor.archiveSHA256
            )
            try writeJournal(journal)
            try fileManager.createDirectory(at: target.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
            try fileManager.moveItem(at: payloadRoot, to: target)
            var updated = old
            updated.active[key] = record
            try writeIndex(updated)
            try? fileManager.removeItem(at: staging)
            try? fileManager.removeItem(at: journalURL)
            return record
        } catch {
            // A failed activation never changes the old pointer. Recovery also handles a
            // process kill between the move and index write.
            try? recover()
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    /// Caps bytes as they arrive, even if the cache file changes after its size check.
    private func copyVerifiedArchive(from source: URL, to destination: URL,
                                     expectedBytes: Int, expectedSHA256: String) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        guard fileManager.createFile(atPath: destination.path, contents: nil) else {
            throw CoursePackError.archiveDigestMismatch
        }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        var received = 0
        var digest = SHA256()
        while let chunk = try input.read(upToCount: 64 * 1024), !chunk.isEmpty {
            try Task.checkCancellation()
            guard chunk.count <= expectedBytes - received else { throw CoursePackError.sizeLimit }
            received += chunk.count
            digest.update(data: chunk)
            try output.write(contentsOf: chunk)
        }
        guard received == expectedBytes, digest.finalize().hexString == expectedSHA256 else {
            throw CoursePackError.archiveDigestMismatch
        }
    }

    private func extract(_ pack: VerifiedCoursePack, to destination: URL) throws {
        let archive = try Archive(url: pack.archiveURL, accessMode: .read)
        let expected = Dictionary(uniqueKeysWithValues: pack.manifest.files.map { ($0.path, $0) })
        for entry in archive {
            try Task.checkCancellation()
            let path = try CoursePackVerifier.validatedPath(entry.path)
            let output = destination.appending(path: path)
            try fileManager.createDirectory(at: output.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
            guard fileManager.createFile(atPath: output.path, contents: nil) else {
                throw CoursePackError.unsafeArchive(path)
            }
            let handle = try FileHandle(forWritingTo: output)
            defer { try? handle.close() }
            var bytes = 0
            var digest = SHA256()
            _ = try archive.extract(entry, bufferSize: 64 * 1024) { chunk in
                try Task.checkCancellation()
                bytes += chunk.count
                guard bytes <= CoursePackVerifier.maximumFileBytes else { throw CoursePackError.sizeLimit }
                digest.update(data: chunk)
                try handle.write(contentsOf: chunk)
            }
            if path == "manifest.json" { continue }
            guard let file = expected[path],
                  bytes == file.bytes,
                  digest.finalize().hexString == file.sha256
            else { throw CoursePackError.manifestMismatch(path) }
        }
    }

    private func component(_ value: String) throws -> String {
        let safe = try CoursePackVerifier.validatedPath(value)
        guard !safe.contains("/"), safe.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]*$",
                                               options: .regularExpression) != nil
        else { throw CoursePackError.unsafeArchive(value) }
        return safe
    }

    private var indexURL: URL { root.appending(path: "index.json") }
    private var journalURL: URL { root.appending(path: "journal.json") }

    private func readIndex() throws -> CourseInstallIndex {
        guard fileManager.fileExists(atPath: indexURL.path) else { return CourseInstallIndex() }
        return try JSONDecoder().decode(CourseInstallIndex.self, from: Data(contentsOf: indexURL))
    }

    private func writeIndex(_ index: CourseInstallIndex) throws {
        try JSONEncoder().encode(index).write(to: indexURL, options: .atomic)
    }

    private func writeJournal(_ journal: CourseInstallJournal) throws {
        try JSONEncoder().encode(journal).write(to: journalURL, options: .atomic)
    }

    private func recover() throws {
        if fileManager.fileExists(atPath: journalURL.path) {
            let journal = try JSONDecoder().decode(
                CourseInstallJournal.self, from: Data(contentsOf: journalURL)
            )
            let (target, staging) = try validatedJournalPaths(journal)
            let active = try readIndex().active[journal.key]
            let activePath = active.map {
                root.appending(path: "\($0.courseID)/\($0.language)/\($0.contentVersion)").path
            }
            if activePath != target.path,
               fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
            if fileManager.fileExists(atPath: staging.path) {
                try fileManager.removeItem(at: staging)
            }
            try fileManager.removeItem(at: journalURL)
        }

        // A process can die during copy or extraction, before the activation
        // journal exists. The install lock guarantees no other installer actor
        // in this process is using staging while recovery runs.
        let stagingRoot = root.appending(path: ".staging", directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: stagingRoot.path) {
            try fileManager.removeItem(at: stagingRoot)
        }
    }

    /// A journal is local state, but corruption must never let recovery remove
    /// another course's active tree or follow a substituted directory symlink.
    private func validatedJournalPaths(_ journal: CourseInstallJournal) throws -> (URL, URL) {
        let parts = journal.key.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let course = try? component(String(parts[0])),
              let language = try? component(String(parts[1])),
              journal.archiveSHA256.count == 64,
              journal.archiveSHA256.allSatisfy({ "0123456789abcdef".contains($0) })
        else { throw CoursePackError.unsafeArchive("install journal") }

        let target = URL(fileURLWithPath: journal.targetPath)
        let targetParts = target.pathComponents
        guard let version = targetParts.last.flatMap({ try? component($0) }),
              target.standardizedFileURL.path == root.appending(
                path: "\(course)/\(language)/\(version)"
              ).standardizedFileURL.path
        else { throw CoursePackError.unsafeArchive("install journal") }

        let staging = URL(fileURLWithPath: journal.stagingPath)
        guard let identifier = UUID(uuidString: staging.lastPathComponent),
              staging.standardizedFileURL.path == root.appending(
                path: ".staging/\(identifier.uuidString)"
              ).standardizedFileURL.path
        else { throw CoursePackError.unsafeArchive("install journal") }

        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        guard target.resolvingSymlinksInPath().standardizedFileURL.path == canonicalRoot.appending(
                path: "\(course)/\(language)/\(version)"
              ).path,
              staging.resolvingSymlinksInPath().standardizedFileURL.path == canonicalRoot.appending(
                path: ".staging/\(identifier.uuidString)"
              ).path
        else { throw CoursePackError.unsafeArchive("install journal") }
        return (target, staging)
    }
}

private extension SHA256.Digest {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
