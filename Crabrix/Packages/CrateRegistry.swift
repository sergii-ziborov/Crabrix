import Foundation

/// One dependency edge as published in the registry index.
struct RegistryDependency: Sendable, Hashable {
    enum Kind: String, Sendable, Codable {
        case normal
        case build
        case dev
    }

    /// The name the depending crate uses in code. For a renamed dependency this
    /// is the alias, and `packageName` carries the published crate name.
    let alias: String
    let packageName: String
    let requirement: VersionRequirement
    let features: [String]
    let isOptional: Bool
    let usesDefaultFeatures: Bool
    let target: TargetCfgExpression?
    let kind: Kind

    func applies(to spec: RustTargetSpec) -> Bool {
        guard let target else { return true }
        return target.matches(spec)
    }

    func matchResult(for spec: RustTargetSpec) -> TargetMatchResult {
        target?.matchResult(spec) ?? .yes
    }
}

/// One version line of a sparse-index file.
struct RegistryIndexEntry: Sendable, Hashable {
    let name: String
    let version: SemanticVersion
    let dependencies: [RegistryDependency]
    let checksum: String
    let features: [String: [String]]
    let isYanked: Bool
    let rustVersion: String?
    /// A `links` key means the crate claims a native library, which Crabrix
    /// cannot provide.
    let links: String?

    /// Registry entries are attacker-influenced data. Reject anything whose
    /// checksum is not a plain 64-character SHA-256 before it reaches disk.
    var hasWellFormedChecksum: Bool {
        checksum.count == 64 && checksum.allSatisfy(\.isHexDigit)
    }
}

/// A crate's full index file: every published version, newest last.
struct RegistryIndexFile: Sendable {
    let name: String
    let entries: [RegistryIndexEntry]

    var versions: [SemanticVersion] { entries.map(\.version) }

    func entry(for version: SemanticVersion) -> RegistryIndexEntry? {
        entries.first { $0.version == version }
    }

    /// Yanked versions stay resolvable only when a lockfile already pinned them.
    func selectableVersions(allowingYanked: Bool = false) -> [SemanticVersion] {
        entries.filter { allowingYanked || !$0.isYanked }.map(\.version)
    }
}

enum CrateRegistryError: LocalizedError, Equatable {
    case invalidCrateName(String)
    case crateNotFound(String)
    case transport(String)
    case malformedIndex(String)
    case indexTooLarge(String)
    case offlineCacheMiss(String)

    var errorDescription: String? {
        switch self {
        case let .invalidCrateName(name):
            "\"\(name)\" is not a valid crate name."
        case let .crateNotFound(name):
            "crates.io has no crate named \(name)."
        case let .transport(detail):
            "The registry request failed: \(detail)"
        case let .malformedIndex(name):
            "The registry index entry for \(name) could not be read."
        case let .indexTooLarge(name):
            "The registry index entry for \(name) is larger than Crabrix downloads."
        case let .offlineCacheMiss(name):
            "Offline build is missing the cached registry index for \(name)."
        }
    }
}

/// Everything the resolver needs from a registry, so tests can supply a fixture
/// index instead of reaching the network.
protocol CrateIndexProviding: Sendable {
    func indexFile(for crate: String) async throws -> RegistryIndexFile
    func cachedIndexFile(for crate: String) async throws -> RegistryIndexFile
}

extension CrateIndexProviding {
    /// Fixture/custom providers are already deterministic local sources. The
    /// production sparse provider overrides this to prohibit HTTP completely.
    func cachedIndexFile(for crate: String) async throws -> RegistryIndexFile {
        try await indexFile(for: crate)
    }
}

/// A sparse (HTTP) registry index client.
///
/// The sparse protocol is what makes a mobile package manager practical: each
/// crate is one small file, so Crabrix never clones the multi-hundred-megabyte
/// git index.
actor SparseRegistryIndex: CrateIndexProviding {
    static let cratesIOIndexBase = URL(string: "https://index.crates.io")!
    static let maximumIndexBytes = 16 * 1024 * 1024

    private let base: URL
    private let session: URLSession
    private var memoryCache: [String: RegistryIndexFile] = [:]
    private let diskCacheURL: URL?

    init(
        base: URL = SparseRegistryIndex.cratesIOIndexBase,
        session: URLSession = CrateNetworking.session,
        diskCacheURL: URL? = CrateStorageLayout.indexCacheDirectory
    ) {
        self.base = base
        self.session = session
        self.diskCacheURL = diskCacheURL
    }

    /// crates.io lays the index out by name length: `1/a`, `2/ab`, `3/a/abc`,
    /// and `ab/cd/abcdef` for everything longer.
    nonisolated static func indexPath(for crate: String) -> String? {
        let lowered = crate.lowercased()
        guard isValidCrateName(lowered) else { return nil }
        switch lowered.count {
        case 1: return "1/\(lowered)"
        case 2: return "2/\(lowered)"
        case 3: return "3/\(lowered.prefix(1))/\(lowered)"
        default:
            let first = lowered.prefix(2)
            let second = lowered.dropFirst(2).prefix(2)
            return "\(first)/\(second)/\(lowered)"
        }
    }

    nonisolated static func isValidCrateName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 64 else { return false }
        guard let first = name.first, first.isLetter || first.isNumber else { return false }
        return name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    func indexFile(for crate: String) async throws -> RegistryIndexFile {
        let key = crate.lowercased()
        if let cached = memoryCache[key] { return cached }
        guard let path = Self.indexPath(for: key) else {
            throw CrateRegistryError.invalidCrateName(crate)
        }

        let data: Data
        do {
            data = try await fetch(path: path, crate: key)
        } catch let error as CrateRegistryError {
            // Offline is survivable when the index was cached on an earlier run.
            if case .transport = error, let cached = loadDiskCache(for: key) {
                let file = try Self.parse(cached, name: key)
                memoryCache[key] = file
                return file
            }
            throw error
        }

        let file = try Self.parse(data, name: key)
        memoryCache[key] = file
        storeDiskCache(data, for: key)
        return file
    }

    func cachedIndexFile(for crate: String) async throws -> RegistryIndexFile {
        let key = crate.lowercased()
        if let cached = memoryCache[key] { return cached }
        guard let cached = loadDiskCache(for: key) else {
            throw CrateRegistryError.offlineCacheMiss(key)
        }
        let file = try Self.parse(cached, name: key)
        memoryCache[key] = file
        return file
    }

    private func fetch(path: String, crate: String) async throws -> Data {
        let url = base.appending(path: path)
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        CrateNetworking.decorate(&request)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw CrateRegistryError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw CrateRegistryError.transport("Unreadable registry response.")
        }
        if http.statusCode == 404 { throw CrateRegistryError.crateNotFound(crate) }
        guard (200..<300).contains(http.statusCode) else {
            throw CrateRegistryError.transport("HTTP \(http.statusCode)")
        }
        guard data.count <= Self.maximumIndexBytes else {
            throw CrateRegistryError.indexTooLarge(crate)
        }
        return data
    }

    private func diskCacheFile(for crate: String) -> URL? {
        diskCacheURL?.appending(path: "\(crate).json")
    }

    private func loadDiskCache(for crate: String) -> Data? {
        guard let url = diskCacheFile(for: crate) else { return nil }
        return try? Data(contentsOf: url)
    }

    private func storeDiskCache(_ data: Data, for crate: String) {
        guard let directory = diskCacheURL, let url = diskCacheFile(for: crate) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// Sparse index files are newline-delimited JSON, oldest version first.
    nonisolated static func parse(_ data: Data, name: String) throws -> RegistryIndexFile {
        var entries: [RegistryIndexEntry] = []
        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard !line.isEmpty else { continue }
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
            else {
                throw CrateRegistryError.malformedIndex(name)
            }
            guard let entry = entry(from: object) else { continue }
            entries.append(entry)
        }
        guard !entries.isEmpty else { throw CrateRegistryError.malformedIndex(name) }
        return RegistryIndexFile(name: entries[0].name, entries: entries)
    }

    private nonisolated static func entry(from object: [String: Any]) -> RegistryIndexEntry? {
        guard let name = object["name"] as? String,
              let versionText = object["vers"] as? String,
              let version = SemanticVersion(versionText),
              let checksum = object["cksum"] as? String
        else {
            return nil
        }

        var features: [String: [String]] = [:]
        for table in ["features", "features2"] {
            guard let raw = object[table] as? [String: Any] else { continue }
            for (feature, values) in raw {
                let list = (values as? [Any])?.compactMap { $0 as? String } ?? []
                features[feature, default: []].append(contentsOf: list)
            }
        }

        var dependencies: [RegistryDependency] = []
        for raw in (object["deps"] as? [[String: Any]]) ?? [] {
            guard let alias = raw["name"] as? String else { continue }
            let requirementText = (raw["req"] as? String) ?? "*"
            let requirement = VersionRequirement(requirementText) ?? .any
            let packageName = (raw["package"] as? String) ?? alias
            let kind = RegistryDependency.Kind(rawValue: (raw["kind"] as? String) ?? "normal")
                ?? .normal
            let target = (raw["target"] as? String).map(TargetCfgExpression.parse)
            dependencies.append(
                RegistryDependency(
                    alias: alias,
                    packageName: packageName,
                    requirement: requirement,
                    features: (raw["features"] as? [Any])?.compactMap { $0 as? String } ?? [],
                    isOptional: (raw["optional"] as? Bool) ?? false,
                    usesDefaultFeatures: (raw["default_features"] as? Bool) ?? true,
                    target: target,
                    kind: kind
                )
            )
        }

        return RegistryIndexEntry(
            name: name,
            version: version,
            dependencies: dependencies,
            checksum: checksum.lowercased(),
            features: features,
            isYanked: (object["yanked"] as? Bool) ?? false,
            rustVersion: object["rust_version"] as? String,
            links: object["links"] as? String
        )
    }
}

/// Shared HTTP configuration for every registry request.
enum CrateNetworking {
    static let userAgent = "Crabrix/0.2 (https://github.com/sergii-ziborov/Crabrix)"

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 300
        configuration.httpAdditionalHeaders = ["User-Agent": userAgent]
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    static func decorate(_ request: inout URLRequest) {
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("gzip, deflate", forHTTPHeaderField: "Accept-Encoding")
    }
}
