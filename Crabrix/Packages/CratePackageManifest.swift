import Foundation

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
    let rustVersion: String?
    /// A `links` key declares a native library Crabrix has no way to supply.
    let links: String?
    let buildScriptPath: String?
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

    func registryDependencies(for spec: RustTargetSpec) -> [ManifestDependency] {
        dependencies.filter { $0.kind == .normal && $0.applies(to: spec) }
    }

    static func parse(_ source: String) throws -> CratePackageManifest {
        let document = try TOMLParser.parse(source)
        let package = document["package"]?.tableValue
        let isVirtualWorkspace = package == nil && document["workspace"] != nil

        // `name.workspace = true` inheritance cannot be resolved from a published
        // crate alone; Cargo always rewrites those before publishing.
        let packageName = package?["name"]?.stringValue ?? ""
        let version = package?["version"]?.stringValue.flatMap(SemanticVersion.init)
        let edition = package?["edition"]?.stringValue ?? "2015"
        let rustVersion = package?["rust-version"]?.stringValue
        let links = package?["links"]?.stringValue

        var buildScriptPath: String?
        switch package?["build"] {
        case let .string(path): buildScriptPath = path
        case .boolean(false): buildScriptPath = nil
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
        dependencies += parseDependencyTable(document["dependencies"], kind: .normal, target: nil)
        dependencies += parseDependencyTable(document["dev-dependencies"], kind: .dev, target: nil)
        dependencies += parseDependencyTable(document["build-dependencies"], kind: .build, target: nil)
        for (rawTarget, value) in document["target"]?.tableValue ?? [:] {
            let expression = TargetCfgExpression.parse(rawTarget)
            dependencies += parseDependencyTable(
                value["dependencies"], kind: .normal, target: expression
            )
            dependencies += parseDependencyTable(
                value["dev-dependencies"], kind: .dev, target: expression
            )
            dependencies += parseDependencyTable(
                value["build-dependencies"], kind: .build, target: expression
            )
        }

        return CratePackageManifest(
            packageName: packageName,
            version: version,
            edition: edition,
            rustVersion: rustVersion,
            links: links,
            buildScriptPath: buildScriptPath,
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
    ) -> [ManifestDependency] {
        guard let table = value?.tableValue else { return [] }
        return table.compactMap { alias, entry in
            dependency(alias: alias, entry: entry, kind: kind, target: target)
        }
    }

    private static func dependency(
        alias: String,
        entry: TOMLValue,
        kind: RegistryDependency.Kind,
        target: TargetCfgExpression?
    ) -> ManifestDependency? {
        if let requirementText = entry.stringValue {
            return ManifestDependency(
                alias: alias,
                packageName: alias,
                requirementText: requirementText,
                requirement: VersionRequirement(requirementText),
                features: [],
                isOptional: false,
                usesDefaultFeatures: true,
                source: .registry,
                kind: kind,
                target: target
            )
        }
        guard let table = entry.tableValue else { return nil }

        let source: ManifestDependency.Source
        if let path = table["path"]?.stringValue {
            source = .path(path)
        } else if let git = table["git"]?.stringValue {
            source = .git(git)
        } else {
            source = .registry
        }
        let requirementText = table["version"]?.stringValue
        return ManifestDependency(
            alias: alias,
            packageName: table["package"]?.stringValue ?? alias,
            requirementText: requirementText,
            requirement: requirementText.flatMap(VersionRequirement.init),
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
