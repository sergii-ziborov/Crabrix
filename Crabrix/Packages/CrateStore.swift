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
    var artifactBytes: Int64 = 0
    var indexBytes: Int64 = 0
    var packageCount = 0

    var totalBytes: Int64 { archiveBytes + sourceBytes + artifactBytes + indexBytes }

    static func measure() -> CrateStorageUsage {
        var usage = CrateStorageUsage()
        usage.archiveBytes = directorySize(CrateStorageLayout.archiveDirectory)
        usage.sourceBytes = directorySize(CrateStorageLayout.sourceDirectory)
        usage.artifactBytes = directorySize(CrateStorageLayout.artifactDirectory)
        usage.indexBytes = directorySize(CrateStorageLayout.indexCacheDirectory)
        if let sources = CrateStorageLayout.sourceDirectory,
           let entries = try? FileManager.default.contentsOfDirectory(
               at: sources,
               includingPropertiesForKeys: nil
           ) {
            usage.packageCount = entries.count
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

    var errorDescription: String? {
        switch self {
        case .storageUnavailable: "Crabrix could not open its package cache."
        case let .transport(detail): "The package download failed: \(detail)"
        case let .server(code): "The package registry returned HTTP \(code)."
        case .tooLarge: "The package archive is larger than Crabrix downloads."
        case let .missingManifest(name): "\(name) does not contain a Cargo.toml."
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
        checksum: String
    ) async throws -> MaterializedCrate {
        guard let sourceURL = CrateStorageLayout.sourceDirectory(name: name, version: version) else {
            throw CrateDownloadError.storageUnavailable
        }

        if let manifest = try? loadManifest(at: sourceURL, name: name) {
            return MaterializedCrate(
                name: name,
                version: version,
                sourceDirectory: sourceURL,
                manifest: manifest
            )
        }

        let archive = try await archiveData(name: name, version: version, checksum: checksum)
        try extract(archive, name: name, version: version, into: sourceURL)
        let manifest = try loadManifest(at: sourceURL, name: name)
        return MaterializedCrate(
            name: name,
            version: version,
            sourceDirectory: sourceURL,
            manifest: manifest
        )
    }

    /// True when the crate's source is already extracted, i.e. usable offline.
    nonisolated func isMaterialized(name: String, version: SemanticVersion) -> Bool {
        guard let sourceURL = CrateStorageLayout.sourceDirectory(name: name, version: version) else {
            return false
        }
        return FileManager.default.fileExists(
            atPath: sourceURL.appending(path: "Cargo.toml").path
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
        checksum: String
    ) async throws -> Data {
        if let cached = cachedArchive(name: name, version: version),
           Self.sha256(cached) == checksum.lowercased() {
            return cached
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
        for entry in entries {
            guard let relative = try TarArchiveReader.normalizedRelativePath(
                entry.path,
                strippingRoot: root,
                limits: limits
            ) else {
                continue
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

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.moveItem(at: staging, to: destination)
    }

    private func loadManifest(at directory: URL, name: String) throws -> CratePackageManifest {
        let manifestURL = directory.appending(path: "Cargo.toml")
        guard let data = try? Data(contentsOf: manifestURL) else {
            throw CrateDownloadError.missingManifest(name)
        }
        return try CratePackageManifest.parse(String(decoding: data, as: UTF8.self))
    }
}
