import Foundation

enum CratePackageManifestError: LocalizedError, Equatable {
    case unsupportedEdition(String)
    case unsupportedResolver(String)
    case unsupportedWorkspaceInheritance(String)
    case invalidDependencyRequirement(alias: String, requirement: String)
    case missingRegistryDependencyVersion(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedEdition(edition):
            "Cargo edition \"\(edition)\" is unsupported. Crabrix supports 2015, 2018, 2021, and 2024."
        case let .unsupportedResolver(resolver):
            "Cargo resolver \"\(resolver)\" is unsupported. Crabrix recognizes resolver versions 1, 2, and 3."
        case let .unsupportedWorkspaceInheritance(field):
            "Cargo workspace inheritance for \"\(field)\" needs a selected workspace member and is not silently approximated."
        case let .invalidDependencyRequirement(alias, requirement):
            "Dependency \"\(alias)\" has an invalid version requirement \"\(requirement)\"."
        case let .missingRegistryDependencyVersion(alias):
            "Registry dependency \"\(alias)\" has no version requirement."
        }
    }
}

enum CargoResolverVersion: String, Sendable, Equatable, Codable {
    case v1 = "1"
    case v2 = "2"
    case v3 = "3"

    static func defaultVersion(forEdition edition: String) -> CargoResolverVersion {
        switch edition {
        case "2024": .v3
        case "2021": .v2
        default: .v1
        }
    }
}

/// A dependency as written in a `Cargo.toml`.
struct ManifestDependency: Sendable, Hashable, Identifiable {
    enum Source: Hashable, Sendable {
        case registry
        case path(String)
        case git(String)
    }

    /// The key used in the dependency table, which is also the name in code.
    let alias: String
    /// The published crate name, which differs from `alias` for a renamed dependency.
    let packageName: String
    let requirementText: String?
    let requirement: VersionRequirement?
    let features: [String]
    let isOptional: Bool
    let usesDefaultFeatures: Bool
    let source: Source
    let kind: RegistryDependency.Kind
    let target: TargetCfgExpression?

    var id: String { "\(kind.rawValue):\(alias)" }

    var isRegistry: Bool { source == .registry }

    func applies(to spec: RustTargetSpec) -> Bool {
        guard let target else { return true }
        return target.matches(spec)
    }

    func matchResult(for spec: RustTargetSpec) -> TargetMatchResult {
        target?.matchResult(spec) ?? .yes
    }
}

/// A crate's own `Cargo.toml`, reduced to what Crabrix needs to build it.
struct CratePackageManifest: Sendable, Equatable {
    struct LibraryTarget: Sendable, Equatable {
        var name: String?
        var path: String?
        var isProcMacro = false
        var crateTypes: [String] = []
    }

    let packageName: String
    let version: SemanticVersion?
    let edition: String
    let resolverVersion: CargoResolverVersion
    let rustVersion: String?
    /// A `links` key declares a native library Crabrix has no way to supply.
    let links: String?
    let buildScriptPath: String?
    /// Distinguishes `build = false` from an omitted key. Cargo treats an
    /// omitted key as an implicit `build.rs` when that file exists.
    let buildScriptDisabled: Bool
    let library: LibraryTarget
    let features: [String: [String]]
    let dependencies: [ManifestDependency]
    /// `[workspace]` without `[package]` means the manifest is a virtual root.
    let isVirtualWorkspace: Bool

    /// rustc's `--crate-name` form: hyphens are not valid Rust identifiers.
    static func crateIdentifier(for name: String) -> String {
        name.replacingOccurrences(of: "-", with: "_")
    }

    var libraryCrateName: String {
        library.name.map(Self.crateIdentifier(for:)) ?? Self.crateIdentifier(for: packageName)
    }

    var isProcMacro: Bool {
        library.isProcMacro || library.crateTypes.contains("proc-macro")
    }

    /// Crate types Crabrix cannot produce for `wasm32-wasip1` from an rlib build.
    var requiresUnsupportedCrateType: Bool {
        let unsupported: Set<String> = ["cdylib", "dylib", "staticlib", "proc-macro"]
        return library.crateTypes.contains { unsupported.contains($0) }
            && !library.crateTypes.contains { $0 == "lib" || $0 == "rlib" }
    }

    func detectingImplicitBuildScript(fileExists: Bool) -> CratePackageManifest {
        guard fileExists, buildScriptPath == nil, !buildScriptDisabled else { return self }
        return CratePackageManifest(
            packageName: packageName,
            version: version,
            edition: edition,
            resolverVersion: resolverVersion,
            rustVersion: rustVersion,
            links: links,
            buildScriptPath: "build.rs",
            buildScriptDisabled: false,
            library: library,
            features: features,
            dependencies: dependencies,
            isVirtualWorkspace: isVirtualWorkspace
        )
    }

    func registryDependencies(for spec: RustTargetSpec) -> [ManifestDependency] {
        dependencies.filter { $0.kind == .normal && $0.applies(to: spec) }
    }

    static func parse(_ source: String) throws -> CratePackageManifest {
        let document = try TOMLParser.parse(source)
        let package = document["package"]?.tableValue
        let isVirtualWorkspace = package == nil && document["workspace"] != nil

        for field in ["name", "version", "edition", "rust-version"] where
            package?[field]?.tableValue?["workspace"]?.boolValue == true
        {
            throw CratePackageManifestError.unsupportedWorkspaceInheritance("package.\(field)")
        }

        // `name.workspace = true` inheritance cannot be resolved from a published
        // crate alone; Cargo always rewrites those before publishing.
        let packageName = package?["name"]?.stringValue ?? ""
        let version = package?["version"]?.stringValue.flatMap(SemanticVersion.init)
        let edition = package?["edition"]?.stringValue ?? "2015"
        guard ["2015", "2018", "2021", "2024"].contains(edition) else {
            throw CratePackageManifestError.unsupportedEdition(edition)
        }
        let resolverText = package?["resolver"]?.stringValue
            ?? document["workspace"]?["resolver"]?.stringValue
        let resolverVersion: CargoResolverVersion
        if let resolverText {
            guard let parsed = CargoResolverVersion(rawValue: resolverText) else {
                throw CratePackageManifestError.unsupportedResolver(resolverText)
            }
            resolverVersion = parsed
        } else {
            resolverVersion = .defaultVersion(forEdition: edition)
        }
        let rustVersion = package?["rust-version"]?.stringValue
        let links = package?["links"]?.stringValue

        var buildScriptPath: String?
        var buildScriptDisabled = false
        switch package?["build"] {
        case let .string(path): buildScriptPath = path
        case .boolean(false):
            buildScriptPath = nil
            buildScriptDisabled = true
        case .boolean(true): buildScriptPath = "build.rs"
        default: buildScriptPath = nil
        }

        var library = LibraryTarget()
        if let lib = document["lib"]?.tableValue {
            library.name = lib["name"]?.stringValue
            library.path = lib["path"]?.stringValue
            library.isProcMacro = lib["proc-macro"]?.boolValue
                ?? lib["proc_macro"]?.boolValue
                ?? false
            library.crateTypes = lib["crate-type"]?.stringArrayValue
                ?? lib["crate_type"]?.stringArrayValue
                ?? []
        }

        var features: [String: [String]] = [:]
        for (name, value) in document["features"]?.tableValue ?? [:] {
            features[name] = value.stringArrayValue ?? []
        }

        var dependencies: [ManifestDependency] = []
        dependencies += try parseDependencyTable(document["dependencies"], kind: .normal, target: nil)
        dependencies += try parseDependencyTable(document["dev-dependencies"], kind: .dev, target: nil)
        dependencies += try parseDependencyTable(document["build-dependencies"], kind: .build, target: nil)
        for (rawTarget, value) in document["target"]?.tableValue ?? [:] {
            let expression = TargetCfgExpression.parse(rawTarget)
            dependencies += try parseDependencyTable(
                value["dependencies"], kind: .normal, target: expression
            )
            dependencies += try parseDependencyTable(
                value["dev-dependencies"], kind: .dev, target: expression
            )
            dependencies += try parseDependencyTable(
                value["build-dependencies"], kind: .build, target: expression
            )
        }

        return CratePackageManifest(
            packageName: packageName,
            version: version,
            edition: edition,
            resolverVersion: resolverVersion,
            rustVersion: rustVersion,
            links: links,
            buildScriptPath: buildScriptPath,
            buildScriptDisabled: buildScriptDisabled,
            library: library,
            features: features,
            dependencies: dependencies.sorted {
                ($0.kind.rawValue, $0.alias) < ($1.kind.rawValue, $1.alias)
            },
            isVirtualWorkspace: isVirtualWorkspace
        )
    }

    private static func parseDependencyTable(
        _ value: TOMLValue?,
        kind: RegistryDependency.Kind,
        target: TargetCfgExpression?
    ) throws -> [ManifestDependency] {
        guard let table = value?.tableValue else { return [] }
        return try table.compactMap { alias, entry in
            try dependency(alias: alias, entry: entry, kind: kind, target: target)
        }
    }

    private static func dependency(
        alias: String,
        entry: TOMLValue,
        kind: RegistryDependency.Kind,
        target: TargetCfgExpression?
    ) throws -> ManifestDependency? {
        if let requirementText = entry.stringValue {
            guard let requirement = VersionRequirement(requirementText) else {
                throw CratePackageManifestError.invalidDependencyRequirement(
                    alias: alias,
                    requirement: requirementText
                )
            }
            return ManifestDependency(
                alias: alias,
                packageName: alias,
                requirementText: requirementText,
                requirement: requirement,
                features: [],
                isOptional: false,
                usesDefaultFeatures: true,
                source: .registry,
                kind: kind,
                target: target
            )
        }
        guard let table = entry.tableValue else { return nil }
        if table["workspace"]?.boolValue == true {
            throw CratePackageManifestError.unsupportedWorkspaceInheritance(
                "dependencies.\(alias)"
            )
        }

        let source: ManifestDependency.Source
        if let path = table["path"]?.stringValue {
            source = .path(path)
        } else if let git = table["git"]?.stringValue {
            source = .git(git)
        } else {
            source = .registry
        }
        let requirementText = table["version"]?.stringValue
        let requirement: VersionRequirement?
        if let requirementText {
            guard let parsed = VersionRequirement(requirementText) else {
                throw CratePackageManifestError.invalidDependencyRequirement(
                    alias: alias,
                    requirement: requirementText
                )
            }
            requirement = parsed
        } else {
            requirement = nil
        }
        if source == .registry, requirement == nil {
            throw CratePackageManifestError.missingRegistryDependencyVersion(alias)
        }
        return ManifestDependency(
            alias: alias,
            packageName: table["package"]?.stringValue ?? alias,
            requirementText: requirementText,
            requirement: requirement,
            features: table["features"]?.stringArrayValue ?? [],
            isOptional: table["optional"]?.boolValue ?? false,
            usesDefaultFeatures: table["default-features"]?.boolValue
                ?? table["default_features"]?.boolValue
                ?? true,
            source: source,
            kind: kind,
            target: target
        )
    }
}
