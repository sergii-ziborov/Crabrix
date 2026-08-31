import CryptoKit
import Foundation

/// How well Crabrix expects a crate to build against the bundled toolchain.
enum CrateCompatibility: Sendable, Equatable, Comparable {
    /// A linkable library was built successfully at least once.
    case verified
    /// rustc emitted metadata successfully, but code generation/linking has not
    /// yet been proved for this exact package fingerprint.
    case checkVerified
    /// Pure Rust with nothing Crabrix cannot handle. Not yet proven.
    case expected
    /// Builds, but something about it may need review, e.g. a build script.
    case review(String)
    /// Cannot build locally at all.
    case unsupported(String)

    var rank: Int {
        switch self {
        case .verified: 0
        case .checkVerified: 1
        case .expected: 2
        case .review: 3
        case .unsupported: 4
        }
    }

    var isBlocking: Bool {
        if case .unsupported = self { return true }
        return false
    }

    var detail: String? {
        switch self {
        case .verified, .checkVerified, .expected: nil
        case let .review(reason), let .unsupported(reason): reason
        }
    }

    var label: String {
        switch self {
        case .verified: "Link verified"
        case .checkVerified: "Check verified"
        case .expected: "Expected compatible"
        case .review: "Needs review"
        case .unsupported: "Unsupported"
        }
    }

    static func < (lhs: CrateCompatibility, rhs: CrateCompatibility) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// One resolved package as the UI shows it.
struct CratePackageStatus: Sendable, Equatable, Identifiable {
    let package: PackageID
    /// crates.io checksum for the exact archive; also proves an offline pin.
    let checksum: String
    let features: [String]
    let compatibility: CrateCompatibility
    let isDownloaded: Bool
    /// The compiler is using an editable project-local overlay instead of the
    /// immutable registry tree for this exact package version.
    let isLocallyPatched: Bool
    /// Direct dependency of the project, as opposed to a transitive one.
    let isDirect: Bool

    var id: String { package.description }
    var name: String { package.name }
    var version: SemanticVersion { package.version }
}

/// What the package manager is doing right now.
enum CargoPreparationStage: Sendable, Equatable {
    case idle
    case resolving
    case downloading(name: String, index: Int, total: Int)
    case building(name: String, index: Int, total: Int)
    case ready
    case failed(String)

    var isWorking: Bool {
        switch self {
        case .resolving, .downloading, .building: true
        case .idle, .ready, .failed: false
        }
    }

    var label: String {
        switch self {
        case .idle: "No dependencies resolved yet"
        case .resolving: "Resolving dependencies…"
        case let .downloading(name, index, total): "Downloading \(name) (\(index)/\(total))…"
        case let .building(name, index, total): "Building \(name) (\(index)/\(total))…"
        case .ready: "Dependencies ready"
        case let .failed(message): message
        }
    }
}

/// The resolved state of a project's dependencies.
struct CargoWorkspaceSnapshot: Sendable, Equatable {
    var packages: [CratePackageStatus] = []
    var plan: CargoBuildPlan = .empty
    var warnings: [String] = []
    var lockfile: String?
    /// True when every package's source is extracted, so a build needs no network.
    var isOfflineReady = false
    /// True when every exact archive is durable outside purgeable Caches.
    var isOfflinePinned = false
    /// Manifest declared dependencies Crabrix will not resolve, e.g. git ones.
    var unresolvedDependencies: [String] = []

    static let empty = CargoWorkspaceSnapshot()

    var isEmpty: Bool { packages.isEmpty && unresolvedDependencies.isEmpty }
    var blockingPackages: [CratePackageStatus] { packages.filter(\.compatibility.isBlocking) }
    var reviewPackages: [CratePackageStatus] {
        packages.filter { if case .review = $0.compatibility { return true } else { return false } }
    }
    var linkVerifiedCount: Int { packages.filter { $0.compatibility == .verified }.count }
    var checkVerifiedCount: Int { packages.filter { $0.compatibility == .checkVerified }.count }

    /// A one-line summary for the workspace sidebar.
    var summary: String {
        guard !packages.isEmpty else { return "No registry dependencies" }
        var parts = ["\(packages.count) packages"]
        if linkVerifiedCount > 0 { parts.append("\(linkVerifiedCount) link verified") }
        if checkVerifiedCount > 0 { parts.append("\(checkVerifiedCount) check verified") }
        if !blockingPackages.isEmpty { parts.append("\(blockingPackages.count) unsupported") }
        return parts.joined(separator: " · ")
    }
}

enum CargoPackageManagerError: LocalizedError {
    case noManifest
    case offlineWithoutLockfile
    case virtualWorkspace
    case rootRustVersionTooNew(required: String, bundled: String)
    case invalidLocalPatch(String)

    var errorDescription: String? {
        switch self {
        case .noManifest: "This project has no Cargo.toml to resolve."
        case .offlineWithoutLockfile:
            "Crabrix could not reach crates.io and this project has no cached packages to build from."
        case .virtualWorkspace:
            "This Cargo.toml is a virtual workspace. Choose a package member before building."
        case let .rootRustVersionTooNew(required, bundled):
            "This project requires Rust \(required), newer than bundled rustc \(bundled)."
        case let .invalidLocalPatch(detail):
            "The local package patch is invalid: \(detail)"
        }
    }
}

private struct ProjectCratePatch: Sendable {
    let relativeDirectory: String
    let manifest: CratePackageManifest
    let sourceTreeHash: String
    let files: [String: String]
}

private struct PreparedCrate: Sendable {
    let registry: MaterializedCrate
    let patch: ProjectCratePatch?

    var manifest: CratePackageManifest { patch?.manifest ?? registry.manifest }
}

/// Resolves, downloads and plans a project's Cargo dependencies.
actor CargoPackageManager {
    private let index: any CrateIndexProviding
    private let store: CrateStore
    private let target: RustTargetSpec
    private let toolchainVersion: String
    private let ledger: CrateCompatibilityLedger

    init(
        index: any CrateIndexProviding = SparseRegistryIndex(),
        store: CrateStore = CrateStore(),
        target: RustTargetSpec = .wasm32WasiP1,
        toolchainVersion: String = CargoToolchain.bundledVersion,
        ledger: CrateCompatibilityLedger = .shared
    ) {
        self.index = index
        self.store = store
        self.target = target
        self.toolchainVersion = toolchainVersion
        self.ledger = ledger
    }

    /// Resolves the graph, downloads what is missing, and produces a build plan.
    func prepare(
        manifestSource: String,
        lockfileSource: String? = nil,
        mode: CargoResolutionMode = .normal,
        projectFiles: [String: String] = [:],
        onStage: (@Sendable (CargoPreparationStage) -> Void)? = nil
    ) async throws -> CargoWorkspaceSnapshot {
        let manifest = try CratePackageManifest.parse(manifestSource)
        guard !manifest.isVirtualWorkspace else {
            throw CargoPackageManagerError.virtualWorkspace
        }
        if let rustVersion = manifest.rustVersion {
            guard let required = SemanticVersion(rustVersion),
                  required <= CargoToolchain.semanticVersion
            else {
                throw CargoPackageManagerError.rootRustVersionTooNew(
                    required: rustVersion,
                    bundled: CargoToolchain.semanticVersionLabel
                )
            }
        }
        let parsedLockfile: CargoLockfile?
        if mode == .update {
            parsedLockfile = nil
        } else if let lockfileSource {
            parsedLockfile = try CargoLockfile.parseValidated(lockfileSource)
        } else {
            if mode.requiresLockfile { throw CargoLockfileError.missing }
            parsedLockfile = nil
        }
        let unresolved = manifest.dependencies
            .filter { $0.kind == .normal && !$0.isRegistry }
            .map { dependency -> String in
                switch dependency.source {
                case let .path(path): "\(dependency.alias) (path: \(path))"
                case let .git(url): "\(dependency.alias) (git: \(url))"
                case .registry: dependency.alias
                }
            }

        onStage?(.resolving)
        let resolver = CargoResolver(index: index, target: target)
        let rootName = manifest.packageName.isEmpty ? "project" : manifest.packageName
        let rootVersion = manifest.version ?? SemanticVersion(major: 0, minor: 1, patch: 0)
        let graph = try await resolver.resolve(
            rootDependencies: manifest.dependencies,
            rootFeatures: manifest.features,
            rootPackageName: rootName,
            rootPackageVersion: rootVersion,
            lockfile: parsedLockfile,
            mode: mode
        )

        var materialized: [PackageID: MaterializedCrate] = [:]
        let ordered = graph.buildOrder
        for (offset, id) in ordered.enumerated() {
            guard let package = graph.packages[id] else { continue }
            let alreadyOnDisk = store.isMaterialized(
                name: id.name,
                version: id.version,
                checksum: package.checksum
            )
            if !alreadyOnDisk {
                onStage?(
                    .downloading(name: id.name, index: offset + 1, total: ordered.count)
                )
            }
            materialized[id] = try await store.materialize(
                name: id.name,
                version: id.version,
                checksum: package.checksum,
                allowNetwork: !mode.prohibitsNetwork
            )
        }

        let prepared = try preparedCrates(
            graph: graph,
            materialized: materialized,
            projectFiles: projectFiles
        )
        let plan = buildPlan(
            graph: graph,
            prepared: prepared,
            resolverVersion: manifest.resolverVersion
        )
        let statuses = self.statuses(
            graph: graph,
            prepared: prepared,
            plan: plan
        )
        let lockfile = CargoLockfile(
            graph: graph,
            rootName: rootName,
            rootVersion: rootVersion.description
        ).render()

        onStage?(.ready)
        return CargoWorkspaceSnapshot(
            packages: statuses,
            plan: plan,
            warnings: graph.warnings.map(\.message),
            lockfile: lockfile,
            isOfflineReady: statuses.allSatisfy(\.isDownloaded),
            isOfflinePinned: !statuses.isEmpty && statuses.allSatisfy {
                store.isPinned(
                    name: $0.name,
                    version: $0.version,
                    checksum: $0.checksum
                )
            },
            unresolvedDependencies: unresolved
        )
    }

    // MARK: - Planning

    private func buildPlan(
        graph: ResolvedGraph,
        prepared: [PackageID: PreparedCrate],
        resolverVersion: CargoResolverVersion
    ) -> CargoBuildPlan {
        var fingerprints: [PackageID: String] = [:]
        var units: [CargoBuildUnit] = []

        for id in graph.buildOrder {
            guard let package = graph.packages[id], let crate = prepared[id] else { continue }
            // A crate Crabrix cannot compile also cannot be a build unit; its
            // dependents will be reported as blocked rather than mis-built.
            guard let libraryPath = libraryPath(for: crate) else { continue }

            let externs: [CargoExtern] = package.dependencies
                .compactMap { alias, dependencyID in
                    guard let fingerprint = fingerprints[dependencyID],
                          let dependencyCrate = prepared[dependencyID]
                    else {
                        return nil
                    }
                    return CargoExtern(
                        alias: CratePackageManifest.crateIdentifier(for: alias),
                        crateName: dependencyCrate.manifest.libraryCrateName,
                        fingerprint: fingerprint
                    )
                }
                .sorted { $0.alias < $1.alias }

            let fingerprint = CargoFingerprint.compute(
                toolchainID: toolchainVersion,
                toolchainArtifactHash: CargoToolchain.artifactIdentity,
                toolchainSemanticVersion: CargoToolchain.semanticVersionLabel,
                compilerFlags: CargoFingerprint.dependencyCompilerFlags,
                targetTriple: target.triple,
                resolverVersion: resolverVersion,
                packageSource: crate.patch.map { "project-patch:\($0.sourceTreeHash)" }
                    ?? CargoLockfile.registrySource,
                package: id,
                checksum: package.checksum,
                crateName: crate.manifest.libraryCrateName,
                edition: crate.manifest.edition,
                features: package.sortedFeatures,
                libraryPath: libraryPath,
                dependencies: externs
            )
            fingerprints[id] = fingerprint

            units.append(
                CargoBuildUnit(
                    package: id,
                    fingerprint: fingerprint,
                    crateName: crate.manifest.libraryCrateName,
                    edition: crate.manifest.edition,
                    features: package.sortedFeatures,
                    libraryPath: libraryPath,
                    source: crate.patch.map {
                        .projectPatch(
                            relativeDirectory: $0.relativeDirectory,
                            registryDirectoryName: "\(id.name)-\(id.version)"
                        )
                    } ?? .registry(directoryName: "\(id.name)-\(id.version)"),
                    externs: externs,
                    authors: "",
                    description: "",
                    repository: "",
                    license: "",
                    homepage: ""
                )
            )
        }

        let rootExterns: [CargoExtern] = graph.rootDependencies
            .compactMap { alias, id in
                guard let fingerprint = fingerprints[id], let crate = prepared[id] else {
                    return nil
                }
                return CargoExtern(
                    alias: CratePackageManifest.crateIdentifier(for: alias),
                    crateName: crate.manifest.libraryCrateName,
                    fingerprint: fingerprint
                )
            }
            .sorted { $0.alias < $1.alias }

        return CargoBuildPlan(units: units, rootExterns: rootExterns)
    }

    /// Cargo's default library target is `src/lib.rs` unless `[lib] path` says
    /// otherwise. A crate with neither has no library to link.
    private func libraryPath(for crate: PreparedCrate) -> String? {
        if crate.manifest.isProcMacro || crate.manifest.requiresUnsupportedCrateType {
            return nil
        }
        if let explicit = crate.manifest.library.path {
            let normalized = explicit.replacingOccurrences(of: "\\", with: "/")
            guard isSafeRelativePath(normalized),
                  sourceFileExists(normalized, in: crate)
            else {
                return nil
            }
            return normalized
        }
        let standard = "src/lib.rs"
        guard sourceFileExists(standard, in: crate) else {
            return nil
        }
        return standard
    }

    private func sourceFileExists(_ path: String, in crate: PreparedCrate) -> Bool {
        if crate.patch?.files[path] != nil { return true }
        return FileManager.default.fileExists(
            atPath: crate.registry.sourceDirectory.appending(path: path).path
        )
    }

    private func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.hasPrefix("/") else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.isEmpty, components.count <= 16 else { return false }
        return components.allSatisfy { $0 != "." && $0 != ".." }
    }

    // MARK: - Compatibility

    private func statuses(
        graph: ResolvedGraph,
        prepared: [PackageID: PreparedCrate],
        plan: CargoBuildPlan
    ) -> [CratePackageStatus] {
        let directIDs = Set(graph.rootDependencies.values)
        let plannedByPackage = Dictionary(
            plan.units.map { ($0.package, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return graph.buildOrder.compactMap { id -> CratePackageStatus? in
            guard let package = graph.packages[id] else { return nil }
            let crate = prepared[id]
            let compatibility = self.compatibility(
                package: package,
                crate: crate,
                unit: plannedByPackage[id]
            )
            return CratePackageStatus(
                package: id,
                checksum: package.checksum,
                features: package.sortedFeatures,
                compatibility: compatibility,
                isDownloaded: crate != nil,
                isLocallyPatched: crate?.patch != nil,
                isDirect: directIDs.contains(id)
            )
        }
        .sorted {
            $0.isDirect == $1.isDirect ? $0.package < $1.package : ($0.isDirect && !$1.isDirect)
        }
    }

    private func compatibility(
        package: ResolvedPackage,
        crate: PreparedCrate?,
        unit: CargoBuildUnit?
    ) -> CrateCompatibility {
        if let links = package.links, !links.isEmpty {
            return .unsupported("links the native library \"\(links)\"")
        }
        guard let crate else { return .expected }
        if crate.manifest.isProcMacro {
            return .unsupported("procedural macros need a host compiler Crabrix does not bundle")
        }
        if crate.manifest.requiresUnsupportedCrateType {
            return .unsupported(
                "builds only as \(crate.manifest.library.crateTypes.joined(separator: ", "))"
            )
        }
        guard let unit else { return .unsupported("has no library target to link") }
        // A real build result always outranks static inspection.
        switch ledger.outcome(forFingerprint: unit.fingerprint) {
        case .checked: return .checkVerified
        case .built: return .verified
        case let .failed(reason): return .unsupported(reason)
        case nil: break
        }
        if let evidence = artifactEvidence(for: unit) { return evidence }
        if let buildScript = crate.manifest.buildScriptPath {
            return .review("runs \(buildScript), which Crabrix does not execute")
        }
        return .expected
    }

    // MARK: - Editable local package overlays

    private func preparedCrates(
        graph: ResolvedGraph,
        materialized: [PackageID: MaterializedCrate],
        projectFiles: [String: String]
    ) throws -> [PackageID: PreparedCrate] {
        var result: [PackageID: PreparedCrate] = [:]
        for id in graph.buildOrder {
            guard let registry = materialized[id] else { continue }
            let patch = try projectPatch(
                for: id,
                registryManifest: registry.manifest,
                projectFiles: projectFiles
            )
            result[id] = PreparedCrate(registry: registry, patch: patch)
        }
        return result
    }

    private func projectPatch(
        for id: PackageID,
        registryManifest: CratePackageManifest,
        projectFiles: [String: String]
    ) throws -> ProjectCratePatch? {
        let root = "vendor/\(id.name)-\(id.version)"
        let prefix = root + "/"
        let patchFiles: [String: String] = Dictionary(
            uniqueKeysWithValues: projectFiles.compactMap { path, contents in
                guard path.hasPrefix(prefix) else { return nil }
                return (String(path.dropFirst(prefix.count)), contents)
            }
        )
        guard let manifestSource = patchFiles["Cargo.toml"] else { return nil }

        var manifest: CratePackageManifest
        do {
            manifest = try CratePackageManifest.parse(manifestSource)
                .detectingImplicitBuildScript(fileExists: patchFiles["build.rs"] != nil)
        } catch {
            throw CargoPackageManagerError.invalidLocalPatch(
                "\(id.name) \(id.version) Cargo.toml: \(error.localizedDescription)"
            )
        }
        guard manifest.packageName == id.name, manifest.version == id.version else {
            throw CargoPackageManagerError.invalidLocalPatch(
                "vendor/\(id.name)-\(id.version) must keep package name and version unchanged"
            )
        }
        guard manifest.dependencies == registryManifest.dependencies,
              manifest.features == registryManifest.features,
              manifest.edition == registryManifest.edition
        else {
            throw CargoPackageManagerError.invalidLocalPatch(
                "\(id.name) may edit source locally, but dependency, feature, and edition changes are not yet supported"
            )
        }

        return ProjectCratePatch(
            relativeDirectory: root,
            manifest: manifest,
            sourceTreeHash: sourceTreeHash(patchFiles),
            files: patchFiles
        )
    }

    private func sourceTreeHash(_ files: [String: String]) -> String {
        var hasher = SHA256()
        for path in files.keys.sorted() {
            for value in [path, files[path] ?? ""] {
                let data = Data(value.utf8)
                var count = UInt64(data.count).bigEndian
                withUnsafeBytes(of: &count) { hasher.update(bufferPointer: $0) }
                hasher.update(data: data)
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func artifactEvidence(for unit: CargoBuildUnit) -> CrateCompatibility? {
        guard let directory = CrateStorageLayout.artifactDirectory?
            .appending(path: toolchainVersion, directoryHint: .isDirectory)
            .appending(path: CargoFingerprint.schemaVersion, directoryHint: .isDirectory)
        else {
            return nil
        }
        let base = "lib\(unit.crateName)-\(unit.fingerprint)"
        if FileManager.default.fileExists(
            atPath: directory.appending(path: "\(base).rlib").path
        ) {
            return .verified
        }
        if FileManager.default.fileExists(
            atPath: directory.appending(path: "\(base).rmeta").path
        ) {
            return .checkVerified
        }
        return nil
    }

    // MARK: - Storage

    func storageUsage() -> CrateStorageUsage { CrateStorageUsage.measure() }

    /// Makes the exact resolved graph resilient to iOS cache eviction by
    /// persisting every checksum-verified `.crate` archive in Application
    /// Support. Cargo.lock remains the graph identity inside the project.
    func pinForOffline(_ packages: [CratePackageStatus]) async throws {
        for package in packages {
            try await store.pinForOffline(
                name: package.name,
                version: package.version,
                checksum: package.checksum
            )
        }
    }

    func clearOfflinePins() async throws {
        try await store.removeOfflinePins()
    }

    func clearBuildArtifacts() throws {
        ledger.removeAll()
        guard let directory = CrateStorageLayout.artifactDirectory,
              FileManager.default.fileExists(atPath: directory.path)
        else {
            return
        }
        try FileManager.default.removeItem(at: directory)
    }

    func clearPackageCache() async throws {
        // Keep the compact registry index and explicit offline pins. They live
        // in Application Support rather than Caches and have their own
        // lifecycle; retaining the index lets a pinned lockfile graph resolve
        // and rehydrate without contacting the registry.
        try await store.removeAllSources()
        try clearBuildArtifacts()
    }

    func clearDownloadedArchives() async throws {
        try await store.removeCachedArchives()
    }
}
