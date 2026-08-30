import Foundation

struct PackageID: Hashable, Sendable, Comparable, CustomStringConvertible, Codable {
    let name: String
    let version: SemanticVersion

    var description: String { "\(name) \(version)" }

    static func < (lhs: PackageID, rhs: PackageID) -> Bool {
        lhs.name == rhs.name ? lhs.version < rhs.version : lhs.name < rhs.name
    }
}

/// One resolved node of the dependency graph.
struct ResolvedPackage: Sendable, Hashable, Identifiable {
    let id: PackageID
    let checksum: String
    var features: Set<String>
    /// Direct normal dependencies, keyed by the alias used in source code.
    var dependencies: [String: PackageID]
    let isYanked: Bool
    let rustVersion: String?
    let links: String?

    var name: String { id.name }
    var version: SemanticVersion { id.version }
    var sortedFeatures: [String] { features.sorted() }
}

enum ResolutionWarning: Hashable, Sendable, Identifiable {
    case yanked(PackageID)
    case nativeLibrary(PackageID, links: String)
    case unsupportedSource(alias: String, detail: String)
    case rustVersionTooNew(PackageID, required: String)

    var id: String {
        switch self {
        case let .yanked(package): "yanked:\(package)"
        case let .nativeLibrary(package, links): "links:\(package):\(links)"
        case let .unsupportedSource(alias, detail): "source:\(alias):\(detail)"
        case let .rustVersionTooNew(package, required): "msrv:\(package):\(required)"
        }
    }

    var message: String {
        switch self {
        case let .yanked(package):
            "\(package.name) \(package.version) is yanked on crates.io."
        case let .nativeLibrary(package, links):
            "\(package.name) links the native library \"\(links)\", which Crabrix cannot provide."
        case let .unsupportedSource(alias, detail):
            "\(alias) uses \(detail), which Crabrix does not resolve yet."
        case let .rustVersionTooNew(package, required):
            "\(package.name) needs Rust \(required), which is newer than the bundled toolchain."
        }
    }
}

/// The fully resolved graph plus the build order the compiler should follow.
struct ResolvedGraph: Sendable {
    let packages: [PackageID: ResolvedPackage]
    /// The root project's direct dependencies, keyed by alias.
    let rootDependencies: [String: PackageID]
    /// Dependencies first, dependents last.
    let buildOrder: [PackageID]
    let warnings: [ResolutionWarning]

    var isEmpty: Bool { packages.isEmpty }

    func package(_ id: PackageID) -> ResolvedPackage? { packages[id] }
}

enum CargoResolutionError: LocalizedError, Equatable {
    case noMatchingVersion(crate: String, requirement: String)
    case conflict(crate: String, requirements: [String])
    case unknownFeature(package: String, feature: String)
    case unknownFeatureDependency(package: String, dependency: String)
    case unknownTargetPredicate(String)
    case requiresNewerRust(crate: String, required: String, bundled: String)
    case didNotConverge

    var errorDescription: String? {
        switch self {
        case let .noMatchingVersion(crate, requirement):
            "No published version of \(crate) satisfies \(requirement)."
        case let .conflict(crate, requirements):
            "Cannot satisfy every requirement on \(crate): \(requirements.joined(separator: ", "))."
        case let .unknownFeature(package, feature):
            "\(package) does not define the requested Cargo feature \"\(feature)\"."
        case let .unknownFeatureDependency(package, dependency):
            "\(package) references unknown feature dependency \"\(dependency)\"."
        case let .unknownTargetPredicate(detail):
            detail
        case let .requiresNewerRust(crate, required, bundled):
            "\(crate) requires Rust \(required), newer than bundled rustc \(bundled)."
        case .didNotConverge:
            "Dependency resolution did not settle. The graph may contain a cycle."
        }
    }
}

/// Resolves a Cargo dependency graph against a registry index.
///
/// This mirrors Cargo closely enough for the pure-Rust tier Crabrix compiles:
/// SemVer selection with compatibility buckets, feature unification including
/// `dep:` and weak `dep?/feature` syntax, and target-predicate filtering.
actor CargoResolver {
    private let index: any CrateIndexProviding
    private let target: RustTargetSpec
    private let toolchainRustVersion: SemanticVersion
    private let maximumPasses = 16

    /// Cargo keeps one version per SemVer-compatible range but allows several
    /// incompatible ranges of the same crate to coexist.
    private struct Bucket {
        var version: SemanticVersion
        var requirements: [VersionRequirement]
    }

    private var buckets: [String: [Bucket]] = [:]
    private var featureRequests: [PackageID: Set<String>] = [:]
    private var indexCache: [String: RegistryIndexFile] = [:]
    private var warnings: Set<ResolutionWarning> = []
    private var lockfile: CargoLockfile?
    private var resolutionMode: CargoResolutionMode = .normal
    private var rootLockEntry: CargoLockfile.Entry?

    init(
        index: any CrateIndexProviding,
        target: RustTargetSpec = .wasm32WasiP1,
        toolchainRustVersion: SemanticVersion = CargoToolchain.semanticVersion
    ) {
        self.index = index
        self.target = target
        self.toolchainRustVersion = toolchainRustVersion
    }

    func resolve(
        rootDependencies: [ManifestDependency],
        rootFeatures: [String: [String]] = [:],
        enabledRootFeatures: Set<String> = ["default"],
        rootPackageName: String = "root",
        rootPackageVersion: SemanticVersion = SemanticVersion(major: 0, minor: 1, patch: 0),
        lockfile: CargoLockfile? = nil,
        mode: CargoResolutionMode = .normal
    ) async throws -> ResolvedGraph {
        if mode.requiresLockfile, lockfile == nil { throw CargoLockfileError.missing }
        buckets = [:]
        featureRequests = [:]
        warnings = []
        self.lockfile = lockfile
        resolutionMode = mode
        rootLockEntry = lockfile?.rootEntry(name: rootPackageName, version: rootPackageVersion)
        if mode.requiresExactPins, rootLockEntry == nil {
            throw CargoLockfileError.graphWouldChange
        }

        var normalRootDependencies: [ManifestDependency] = []
        for dependency in rootDependencies where dependency.kind == .normal {
            switch dependency.matchResult(for: target) {
            case .yes: normalRootDependencies.append(dependency)
            case .no: continue
            case let .unknown(reason): throw CargoResolutionError.unknownTargetPredicate(reason)
            }
        }
        for dependency in normalRootDependencies where !dependency.isRegistry {
            let detail: String
            switch dependency.source {
            case let .path(path): detail = "a path dependency (\(path))"
            case let .git(url): detail = "a git dependency (\(url))"
            case .registry: continue
            }
            warnings.insert(.unsupportedSource(alias: dependency.alias, detail: detail))
        }
        let registryRootEdges = try FeatureResolver.rootEdges(
            for: normalRootDependencies.filter(\.isRegistry),
            featureTable: rootFeatures,
            enabledFeatures: enabledRootFeatures,
            packageName: rootPackageName
        )

        var packages: [PackageID: ResolvedPackage] = [:]
        var rootMap: [String: PackageID] = [:]
        var pass = 0
        var converged = false

        while pass < maximumPasses {
            pass += 1
            let previousBuckets = snapshot()
            let previousFeatures = featureRequests
            (packages, rootMap) = try await runPass(rootEdges: registryRootEdges)
            if snapshot() == previousBuckets, featureRequests == previousFeatures {
                converged = true
                break
            }
        }
        guard converged else { throw CargoResolutionError.didNotConverge }

        for package in packages.values {
            if package.isYanked { warnings.insert(.yanked(package.id)) }
            if let links = package.links, !links.isEmpty {
                warnings.insert(.nativeLibrary(package.id, links: links))
            }
        }

        let graph = ResolvedGraph(
            packages: packages,
            rootDependencies: rootMap,
            buildOrder: Self.topologicalOrder(packages: packages, roots: Array(rootMap.values)),
            warnings: warnings.sorted { $0.id < $1.id }
        )
        if mode.requiresExactPins {
            try lockfile?.validate(
                graph: graph,
                rootName: rootPackageName,
                rootVersion: rootPackageVersion
            )
        }
        return graph
    }

    // MARK: - Passes

    private func snapshot() -> [String: [SemanticVersion]] {
        buckets.mapValues { $0.map(\.version) }
    }

    private func runPass(
        rootEdges: [FeatureResolver.Edge]
    ) async throws -> ([PackageID: ResolvedPackage], [String: PackageID]) {
        var packages: [PackageID: ResolvedPackage] = [:]
        var rootMap: [String: PackageID] = [:]
        var queue: [(PackageID, RegistryIndexEntry)] = []
        var visited: Set<PackageID> = []

        for edge in rootEdges {
            let lockedID = lockfile?.dependencyID(packageName: edge.packageName, from: rootLockEntry)
            let (id, entry) = try await select(edge: edge, lockedID: lockedID)
            rootMap[edge.alias] = id
            request(features: edge.requestedFeatures, for: id)
            if visited.insert(id).inserted { queue.append((id, entry)) }
        }

        var cursor = 0
        while cursor < queue.count {
            let (id, entry) = queue[cursor]
            cursor += 1

            let requested = featureRequests[id] ?? []
            let expansion = try FeatureResolver.expand(
                requested: requested,
                featureTable: entry.features,
                optionalDependencyAliases: Set(entry.dependencies.filter(\.isOptional).map(\.alias)),
                dependencyAliases: Set(entry.dependencies.map(\.alias)),
                packageName: id.name
            )
            var activeDependencies: [RegistryDependency] = []
            for dependency in entry.dependencies where dependency.kind == .normal {
                switch dependency.matchResult(for: self.target) {
                case .yes: activeDependencies.append(dependency)
                case .no: continue
                case let .unknown(reason): throw CargoResolutionError.unknownTargetPredicate(reason)
                }
            }
            let edges = FeatureResolver.edges(
                for: activeDependencies,
                expansion: expansion
            )

            var dependencies: [String: PackageID] = [:]
            let parentLockEntry = lockfile?.pin(for: id)
            for edge in edges {
                let lockedID = lockfile?.dependencyID(
                    packageName: edge.packageName,
                    from: parentLockEntry
                )
                let (childID, childEntry) = try await select(edge: edge, lockedID: lockedID)
                dependencies[edge.alias] = childID
                request(features: edge.requestedFeatures, for: childID)
                if visited.insert(childID).inserted { queue.append((childID, childEntry)) }
            }

            packages[id] = ResolvedPackage(
                id: id,
                checksum: entry.checksum,
                features: expansion.features,
                dependencies: dependencies,
                isYanked: entry.isYanked,
                rustVersion: entry.rustVersion,
                links: entry.links
            )
        }
        return (packages, rootMap)
    }

    private func request(features: Set<String>, for id: PackageID) {
        featureRequests[id, default: []].formUnion(features)
    }

    // MARK: - Version selection

    private func select(
        edge: FeatureResolver.Edge,
        lockedID: PackageID?
    ) async throws -> (PackageID, RegistryIndexEntry) {
        let name = edge.packageName
        let requirement = edge.requirement
        let file = try await indexFile(for: name)

        if resolutionMode.preservesPins, let lockedID {
            guard requirement.isSatisfied(by: lockedID.version) else {
                if resolutionMode.requiresExactPins {
                    throw CargoLockfileError.incompatible(
                        crate: name,
                        requirement: requirement.source
                    )
                }
                return try await selectUnpinned(
                    name: name,
                    requirement: requirement,
                    file: file
                )
            }
            return try await selectPinned(
                id: lockedID,
                requirement: requirement,
                file: file
            )
        }
        if resolutionMode.requiresExactPins {
            throw CargoLockfileError.missingPackage(name)
        }
        return try await selectUnpinned(name: name, requirement: requirement, file: file)
    }

    private func selectPinned(
        id: PackageID,
        requirement: VersionRequirement,
        file: RegistryIndexFile
    ) async throws -> (PackageID, RegistryIndexEntry) {
        guard id.name == file.name, let entry = file.entry(for: id.version) else {
            throw CargoLockfileError.missingPackage(id.description)
        }
        guard let pin = lockfile?.pin(for: id) else {
            throw CargoLockfileError.missingPackage(id.description)
        }
        guard pin.source == CargoLockfile.registrySource else {
            throw CargoLockfileError.sourceMismatch(package: id.description)
        }
        guard pin.checksum == entry.checksum.lowercased() else {
            throw CargoLockfileError.checksumMismatch(package: id.description)
        }
        try validateMSRV(entry, package: id)

        if let existingIndex = buckets[id.name]?.firstIndex(where: {
            $0.version.isCaretCompatible(with: id.version)
        }) {
            let existing = buckets[id.name]![existingIndex]
            if existing.version == id.version {
                appendRequirement(requirement, to: id.version, of: id.name)
                return (id, entry)
            }
            if resolutionMode.requiresExactPins { throw CargoLockfileError.graphWouldChange }
            // A stale normal-mode pin cannot create a second SemVer-compatible
            // copy. Re-run ordinary unification against every requirement.
            return try await selectUnpinned(
                name: id.name,
                requirement: requirement,
                file: file
            )
        }

        buckets[id.name, default: []].append(
            Bucket(version: id.version, requirements: [requirement])
        )
        return (id, entry)
    }

    private func selectUnpinned(
        name: String,
        requirement: VersionRequirement,
        file: RegistryIndexFile
    ) async throws -> (PackageID, RegistryIndexEntry) {
        if let existing = buckets[name],
           let match = existing.first(where: { requirement.isSatisfied(by: $0.version) }) {
            appendRequirement(requirement, to: match.version, of: name)
            guard let entry = file.entry(for: match.version) else {
                throw CargoResolutionError.noMatchingVersion(
                    crate: name,
                    requirement: requirement.source
                )
            }
            return (PackageID(name: name, version: match.version), entry)
        }

        let publishedCandidates = file.selectableVersions()
        let candidates = publishedCandidates.filter { version in
            guard let rustVersion = file.entry(for: version)?.rustVersion else { return true }
            guard let required = SemanticVersion(rustVersion) else { return false }
            return required <= toolchainRustVersion
        }
        guard let candidate = requirement.bestMatch(in: candidates) else {
            let newerCandidates = publishedCandidates.filter(requirement.isSatisfied(by:))
            if let required = newerCandidates.compactMap({ version in
                file.entry(for: version)?.rustVersion.flatMap(SemanticVersion.init)
            }).min() {
                throw CargoResolutionError.requiresNewerRust(
                    crate: name,
                    required: required.description,
                    bundled: CargoToolchain.semanticVersionLabel
                )
            }
            throw CargoResolutionError.noMatchingVersion(
                crate: name,
                requirement: requirement.source
            )
        }

        // A candidate that is SemVer-compatible with an existing selection has to
        // collapse into that bucket; Cargo never links two compatible copies.
        if let index = buckets[name]?.firstIndex(where: {
            $0.version.isCaretCompatible(with: candidate)
        }) {
            var bucket = buckets[name]![index]
            bucket.requirements.append(requirement)
            let feasible = candidates.filter { version in
                bucket.requirements.allSatisfy { $0.isSatisfied(by: version) }
            }
            guard let unified = feasible.max() else {
                throw CargoResolutionError.conflict(
                    crate: name,
                    requirements: bucket.requirements.map(\.source)
                )
            }
            bucket.version = unified
            buckets[name]![index] = bucket
            guard let entry = file.entry(for: unified) else {
                throw CargoResolutionError.noMatchingVersion(
                    crate: name,
                    requirement: requirement.source
                )
            }
            return (PackageID(name: name, version: unified), entry)
        }

        buckets[name, default: []].append(
            Bucket(version: candidate, requirements: [requirement])
        )
        guard let entry = file.entry(for: candidate) else {
            throw CargoResolutionError.noMatchingVersion(
                crate: name,
                requirement: requirement.source
            )
        }
        return (PackageID(name: name, version: candidate), entry)
    }

    private func validateMSRV(_ entry: RegistryIndexEntry, package: PackageID) throws {
        guard let rustVersion = entry.rustVersion else { return }
        guard let required = SemanticVersion(rustVersion), required <= toolchainRustVersion else {
            throw CargoResolutionError.requiresNewerRust(
                crate: package.name,
                required: rustVersion,
                bundled: CargoToolchain.semanticVersionLabel
            )
        }
    }

    private func appendRequirement(
        _ requirement: VersionRequirement,
        to version: SemanticVersion,
        of name: String
    ) {
        guard let index = buckets[name]?.firstIndex(where: { $0.version == version }) else { return }
        guard !buckets[name]![index].requirements.contains(requirement) else { return }
        buckets[name]![index].requirements.append(requirement)
    }

    private func indexFile(for name: String) async throws -> RegistryIndexFile {
        if let cached = indexCache[name] { return cached }
        let file = resolutionMode.prohibitsNetwork
            ? try await index.cachedIndexFile(for: name)
            : try await index.indexFile(for: name)
        indexCache[name] = file
        return file
    }

    // MARK: - Ordering

    static func topologicalOrder(
        packages: [PackageID: ResolvedPackage],
        roots: [PackageID]
    ) -> [PackageID] {
        var order: [PackageID] = []
        var state: [PackageID: Int] = [:] // 1 = visiting, 2 = done

        func visit(_ id: PackageID) {
            // A cycle can only come from bad index data; stop rather than recurse.
            guard state[id] == nil else { return }
            state[id] = 1
            for child in (packages[id]?.dependencies.values.sorted()) ?? [] {
                visit(child)
            }
            state[id] = 2
            order.append(id)
        }

        for root in roots.sorted() { visit(root) }
        for id in packages.keys.sorted() { visit(id) }
        return order
    }
}
