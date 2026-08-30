import Foundation
import CryptoKit

/// Where every Cargo artefact lives inside the app container.
///
/// Sources and archives are caches: iOS may evict them, and the package manager
/// re-downloads on demand. Nothing here is user data.
enum CrateStorageLayout {
    static var root: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: "CrabrixCargo", directoryHint: .isDirectory)
    }

    /// The registry index lives outside Caches on purpose: it is small, and it
    /// is what lets a resolved project rebuild with the network off even after
    /// iOS reclaims the much larger source and artifact caches.
    static var indexCacheDirectory: URL? {
        guard let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else {
            return root?.appending(path: "index", directoryHint: .isDirectory)
        }
        var directory = support
            .appending(path: "Crabrix", directoryHint: .isDirectory)
            .appending(path: "registry-index", directoryHint: .isDirectory)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? directory.setResourceValues(values)
        }
        return directory
    }
    static var archiveDirectory: URL? { root?.appending(path: "archives", directoryHint: .isDirectory) }
    static var sourceDirectory: URL? { root?.appending(path: "src", directoryHint: .isDirectory) }
    static var artifactDirectory: URL? { root?.appending(path: "artifacts", directoryHint: .isDirectory) }
    /// Root-program Wasm files are cached separately from dependency rlibs.
    /// Keep the location in the shared layout so Settings measures the same
    /// bytes that the compiler writes and the clear action removes.
    static var projectArtifactDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: "CrabrixCompiler", directoryHint: .isDirectory)
    }

    static func sourceDirectory(name: String, version: SemanticVersion) -> URL? {
        sourceDirectory?.appending(path: "\(name)-\(version)", directoryHint: .isDirectory)
    }

    static func archiveURL(name: String, version: SemanticVersion) -> URL? {
        archiveDirectory?.appending(path: "\(name)-\(version).crate")
    }
}

/// A byte breakdown of the Cargo caches, for the storage screen in Settings.
struct CrateStorageUsage: Equatable, Sendable {
    var archiveBytes: Int64 = 0
    var sourceBytes: Int64 = 0
    /// Compiled dependency metadata and libraries under CrabrixCargo.
    var artifactBytes: Int64 = 0
    /// Compiled root-program Wasm files under CrabrixCompiler.
    var projectArtifactBytes: Int64 = 0
    var indexBytes: Int64 = 0
    var packageCount = 0

    var buildArtifactBytes: Int64 { artifactBytes + projectArtifactBytes }
    var totalBytes: Int64 {
        archiveBytes + sourceBytes + buildArtifactBytes + indexBytes
    }

    static func measure() -> CrateStorageUsage {
        measure(
            archiveDirectory: CrateStorageLayout.archiveDirectory,
            sourceDirectory: CrateStorageLayout.sourceDirectory,
            artifactDirectory: CrateStorageLayout.artifactDirectory,
            projectArtifactDirectory: CrateStorageLayout.projectArtifactDirectory,
            indexDirectory: CrateStorageLayout.indexCacheDirectory
        )
    }

    /// Injectable directories keep the accounting independently testable and
    /// prevent the Settings screen from drifting away from the real layout.
    static func measure(
        archiveDirectory: URL?,
        sourceDirectory: URL?,
        artifactDirectory: URL?,
        projectArtifactDirectory: URL?,
        indexDirectory: URL?
    ) -> CrateStorageUsage {
        var usage = CrateStorageUsage()
        usage.archiveBytes = directorySize(archiveDirectory)
        usage.sourceBytes = directorySize(sourceDirectory)
        usage.artifactBytes = directorySize(artifactDirectory)
        usage.projectArtifactBytes = directorySize(projectArtifactDirectory)
        usage.indexBytes = directorySize(indexDirectory)
        if let sources = sourceDirectory,
           let entries = try? FileManager.default.contentsOfDirectory(
               at: sources,
               includingPropertiesForKeys: [.isDirectoryKey]
           ) {
            usage.packageCount = entries.filter {
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                    && !$0.lastPathComponent.hasPrefix(".")
            }.count
        }
        return usage
    }

    private static func directorySize(_ url: URL?) -> Int64 {
        guard let url,
              let enumerator = FileManager.default.enumerator(
                  at: url,
                  includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
              )
        else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true, let size = values?.fileSize else { continue }
            total += Int64(size)
        }
        return total
    }
}

enum CrateDownloadError: LocalizedError, Equatable {
    case storageUnavailable
    case transport(String)
    case server(Int)
    case tooLarge
    case missingManifest(String)
    case offlineCacheMiss(String)

    var errorDescription: String? {
        switch self {
        case .storageUnavailable: "Crabrix could not open its package cache."
        case let .transport(detail): "The package download failed: \(detail)"
        case let .server(code): "The package registry returned HTTP \(code)."
        case .tooLarge: "The package archive is larger than Crabrix downloads."
        case let .missingManifest(name): "\(name) does not contain a Cargo.toml."
        case let .offlineCacheMiss(package):
            "Offline build is missing verified source or archive for \(package)."
        }
    }
}

/// A crate whose source is present on disk and whose checksum was verified.
struct MaterializedCrate: Sendable, Equatable {
    let name: String
    let version: SemanticVersion
    let sourceDirectory: URL
    let manifest: CratePackageManifest
}

private struct CrateSourceCompletion: Codable, Equatable {
    static let fileName = ".crabrix-complete.json"
    let package: String
    let version: String
    let checksum: String
    let fileCount: Int
    let expandedBytes: Int64
    let sourceTreeHash: String
    let completed: Bool
}

/// Downloads, verifies, and extracts `.crate` archives.
actor CrateStore {
    private let session: URLSession
    private let downloadBase: URL
    private let limits: CrateArchiveLimits
    private let fileManager = FileManager.default

    /// crates.io publishes this as `dl` in the registry `config.json`; the
    /// download URL is `<dl>/<name>/<version>/download`.
    static let cratesIODownloadBase = URL(string: "https://static.crates.io/crates")!

    init(
        session: URLSession = CrateNetworking.session,
        downloadBase: URL = CrateStore.cratesIODownloadBase,
        limits: CrateArchiveLimits = .default
    ) {
        self.session = session
        self.downloadBase = downloadBase
        self.limits = limits
    }

    /// Returns the on-disk crate, downloading it only when the cache misses.
    func materialize(
        name: String,
        version: SemanticVersion,
        checksum: String,
        allowNetwork: Bool = true
    ) async throws -> MaterializedCrate {
        guard let sourceURL = CrateStorageLayout.sourceDirectory(name: name, version: version) else {
            throw CrateDownloadError.storageUnavailable
        }
        try recoverInterruptedSwap(
            at: sourceURL,
            name: name,
            version: version,
            checksum: checksum
        )

        if Self.hasValidCompletedSource(
            at: sourceURL,
            name: name,
            version: version,
            checksum: checksum
        ), let manifest = try? loadManifest(at: sourceURL, name: name) {
            return MaterializedCrate(
                name: name,
                version: version,
                sourceDirectory: sourceURL,
                manifest: manifest
            )
        }

        let archive = try await archiveData(
            name: name,
            version: version,
            checksum: checksum,
            allowNetwork: allowNetwork
        )
        try extract(
            archive,
            name: name,
            version: version,
            checksum: checksum,
            into: sourceURL
        )
        let manifest = try loadManifest(at: sourceURL, name: name)
        return MaterializedCrate(
            name: name,
            version: version,
            sourceDirectory: sourceURL,
            manifest: manifest
        )
    }

    /// True when the crate's source is already extracted, i.e. usable offline.
    nonisolated func isMaterialized(
        name: String,
        version: SemanticVersion,
        checksum: String
    ) -> Bool {
        guard let sourceURL = CrateStorageLayout.sourceDirectory(name: name, version: version) else {
            return false
        }
        return Self.hasValidCompletedSource(
            at: sourceURL,
            name: name,
            version: version,
            checksum: checksum
        )
    }

    func removeAllSources() throws {
        for directory in [CrateStorageLayout.sourceDirectory, CrateStorageLayout.archiveDirectory] {
            guard let directory, fileManager.fileExists(atPath: directory.path) else { continue }
            try fileManager.removeItem(at: directory)
        }
    }

    func removeCachedArchives() throws {
        guard let directory = CrateStorageLayout.archiveDirectory,
              fileManager.fileExists(atPath: directory.path)
        else {
            return
        }
        try fileManager.removeItem(at: directory)
    }

    // MARK: - Download

    private func archiveData(
        name: String,
        version: SemanticVersion,
        checksum: String,
        allowNetwork: Bool
    ) async throws -> Data {
        if let cached = cachedArchive(name: name, version: version),
           Self.sha256(cached) == checksum.lowercased() {
            return cached
        }
        guard allowNetwork else {
            throw CrateDownloadError.offlineCacheMiss("\(name) \(version)")
        }

        let url = downloadBase
            .appending(path: name)
            .appending(path: version.description)
            .appending(path: "download")
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        CrateNetworking.decorate(&request)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw CrateDownloadError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw CrateDownloadError.transport("Unreadable download response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw CrateDownloadError.server(http.statusCode)
        }
        guard data.count <= limits.maximumCompressedBytes else {
            throw CrateDownloadError.tooLarge
        }

        // Never trust archive bytes because HTTPS succeeded.
        let actual = Self.sha256(data)
        guard actual == checksum.lowercased() else {
            throw CrateArchiveError.checksumMismatch(expected: checksum, actual: actual)
        }
        storeArchive(data, name: name, version: version)
        return data
    }

    private func cachedArchive(name: String, version: SemanticVersion) -> Data? {
        guard let url = CrateStorageLayout.archiveURL(name: name, version: version) else { return nil }
        return try? Data(contentsOf: url)
    }

    private func storeArchive(_ data: Data, name: String, version: SemanticVersion) {
        guard let directory = CrateStorageLayout.archiveDirectory,
              let url = CrateStorageLayout.archiveURL(name: name, version: version)
        else {
            return
        }
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Extraction

    private func extract(
        _ archive: Data,
        name: String,
        version: SemanticVersion,
        checksum: String,
        into destination: URL
    ) throws {
        let tar = try GzipDecoder.decompress(archive, limit: limits.maximumExpandedBytes)
        let entries = try TarArchiveReader.entries(in: tar, limits: limits)
        let root = "\(name)-\(version)"

        // Stage into a sibling directory so an interrupted extract never leaves a
        // half-written crate that later looks cached.
        let staging = destination.deletingLastPathComponent()
            .appending(path: ".staging-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        var wroteManifest = false
        var normalizedPaths: Set<String> = []
        for entry in entries {
            guard let relative = try TarArchiveReader.normalizedRelativePath(
                entry.path,
                strippingRoot: root,
                limits: limits
            ) else {
                continue
            }
            let collisionKey = relative
                .precomposedStringWithCanonicalMapping
                .lowercased()
            guard normalizedPaths.insert(collisionKey).inserted else {
                throw CrateArchiveError.duplicatePath(relative)
            }
            let fileURL = staging.appending(path: relative)
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try entry.contents.write(to: fileURL, options: .atomic)
            if relative == "Cargo.toml" { wroteManifest = true }
        }
        guard wroteManifest else { throw CrateDownloadError.missingManifest(name) }

        let evidence = Self.sourceTreeEvidence(at: staging)
        let completion = CrateSourceCompletion(
            package: name,
            version: version.description,
            checksum: checksum.lowercased(),
            fileCount: evidence.fileCount,
            expandedBytes: evidence.expandedBytes,
            sourceTreeHash: evidence.sourceTreeHash,
            completed: true
        )
        let completionData = try JSONEncoder().encode(completion)
        try completionData.write(
            to: staging.appending(path: CrateSourceCompletion.fileName),
            options: .atomic
        )

        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let backup = Self.backupURL(for: destination)
        if fileManager.fileExists(atPath: backup.path) {
            try fileManager.removeItem(at: backup)
        }
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.moveItem(at: destination, to: backup)
        }
        do {
            try fileManager.moveItem(at: staging, to: destination)
            if fileManager.fileExists(atPath: backup.path) {
                try fileManager.removeItem(at: backup)
            }
        } catch {
            if !fileManager.fileExists(atPath: destination.path),
               fileManager.fileExists(atPath: backup.path) {
                try? fileManager.moveItem(at: backup, to: destination)
            }
            throw error
        }
    }

    private func recoverInterruptedSwap(
        at destination: URL,
        name: String,
        version: SemanticVersion,
        checksum: String
    ) throws {
        let backup = Self.backupURL(for: destination)
        guard fileManager.fileExists(atPath: backup.path) else { return }
        if Self.hasValidCompletedSource(
            at: destination,
            name: name,
            version: version,
            checksum: checksum
        ) {
            try fileManager.removeItem(at: backup)
            return
        }
        guard Self.hasValidCompletedSource(
            at: backup,
            name: name,
            version: version,
            checksum: checksum
        ) else { return }
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: backup, to: destination)
    }

    private nonisolated static func backupURL(for destination: URL) -> URL {
        destination.deletingLastPathComponent()
            .appending(path: ".backup-\(destination.lastPathComponent)", directoryHint: .isDirectory)
    }

    private nonisolated static func hasValidCompletedSource(
        at sourceURL: URL,
        name: String,
        version: SemanticVersion,
        checksum: String
    ) -> Bool {
        let completionURL = sourceURL.appending(path: CrateSourceCompletion.fileName)
        guard let data = try? Data(contentsOf: completionURL),
              let completion = try? JSONDecoder().decode(CrateSourceCompletion.self, from: data),
              completion.completed,
              completion.package == name,
              completion.version == version.description,
              completion.checksum == checksum.lowercased(),
              FileManager.default.fileExists(
                  atPath: sourceURL.appending(path: "Cargo.toml").path
              )
        else { return false }
        let actual = sourceTreeEvidence(at: sourceURL)
        return actual.fileCount == completion.fileCount
            && actual.expandedBytes == completion.expandedBytes
            && actual.sourceTreeHash == completion.sourceTreeHash
    }

    private nonisolated static func sourceTreeEvidence(
        at directory: URL
    ) -> (fileCount: Int, expandedBytes: Int64, sourceTreeHash: String) {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsPackageDescendants]
        ) else { return (0, 0, Self.sha256(Data())) }
        var regularFiles: [URL] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent != CrateSourceCompletion.fileName,
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true
            else { continue }
            regularFiles.append(url)
        }
        regularFiles.sort {
            $0.path.replacingOccurrences(of: directory.path, with: "")
                < $1.path.replacingOccurrences(of: directory.path, with: "")
        }

        var count = 0
        var bytes: Int64 = 0
        var hasher = SHA256()
        for url in regularFiles {
            guard let data = try? Data(contentsOf: url) else {
                return (-1, -1, "unreadable")
            }
            let relativePath = String(url.path.dropFirst(directory.path.count))
            hasher.update(data: Data(relativePath.utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: data)
            hasher.update(data: Data([0]))
            count += 1
            bytes += Int64(data.count)
        }
        return (
            count,
            bytes,
            hasher.finalize().map { String(format: "%02x", $0) }.joined()
        )
    }

    private func loadManifest(at directory: URL, name: String) throws -> CratePackageManifest {
        let manifestURL = directory.appending(path: "Cargo.toml")
        guard let data = try? Data(contentsOf: manifestURL) else {
            throw CrateDownloadError.missingManifest(name)
        }
        let manifest = try CratePackageManifest.parse(String(decoding: data, as: UTF8.self))
        return manifest.detectingImplicitBuildScript(
            fileExists: fileManager.fileExists(
                atPath: directory.appending(path: "build.rs").path
            )
        )
    }
}
