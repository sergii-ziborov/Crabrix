import Foundation

/// The dependency shape feature resolution needs, shared by manifest
/// dependencies and registry index dependencies.
protocol FeatureResolvableDependency: Sendable {
    var alias: String { get }
    var packageName: String { get }
    var resolvedRequirement: VersionRequirement { get }
    var requestedFeatures: [String] { get }
    var isOptional: Bool { get }
    var usesDefaultFeatures: Bool { get }
}

extension ManifestDependency: FeatureResolvableDependency {
    var resolvedRequirement: VersionRequirement { requirement ?? .any }
    var requestedFeatures: [String] { features }
}

extension RegistryDependency: FeatureResolvableDependency {
    var resolvedRequirement: VersionRequirement { requirement }
    var requestedFeatures: [String] { features }
}

/// Cargo's feature unification, including `dep:`, `dep/feature`, and the weak
/// `dep?/feature` forms.
enum FeatureResolver {
    /// One dependency edge with the feature set its parent asks for.
    struct Edge: Sendable {
        let alias: String
        let packageName: String
        let requirement: VersionRequirement
        let requestedFeatures: Set<String>
    }

    struct Expansion: Sendable, Equatable {
        /// Features enabled on the package itself.
        var features: Set<String> = []
        /// Optional dependencies switched on by those features.
        var activatedAliases: Set<String> = []
        /// Extra features requested on a dependency, keyed by alias.
        var dependencyFeatures: [String: Set<String>] = [:]
    }

    /// Expands a requested feature set to its transitive closure.
    ///
    /// - Parameters:
    ///   - requested: features the parent asked for, `default` included.
    ///   - featureTable: the package's own `[features]` table.
    ///   - optionalDependencyAliases: aliases declared `optional = true`, which
    ///     may double as implicit feature names.
    static func expand(
        requested: Set<String>,
        featureTable: [String: [String]],
        optionalDependencyAliases: Set<String>,
        dependencyAliases: Set<String>,
        packageName: String
    ) throws -> Expansion {
        var expansion = Expansion()
        /// `dep?/feature` only applies once the dependency is active, so those
        /// requests are held back until the fixed point settles.
        var weakRequests: [(alias: String, feature: String)] = []
        var pending = Array(requested)

        // A feature name that appears as `dep:name` anywhere stops being an
        // implicit feature, which is exactly Cargo's rule.
        let explicitlyReferencedDependencies = Set(
            featureTable.values.flatMap { $0 }
                .filter { $0.hasPrefix("dep:") }
                .map { String($0.dropFirst(4)) }
        )

        var seen: Set<String> = []
        while let feature = pending.popLast() {
            guard seen.insert(feature).inserted else { continue }

            if feature.hasPrefix("dep:") {
                let alias = String(feature.dropFirst(4))
                guard optionalDependencyAliases.contains(alias) else {
                    throw CargoResolutionError.unknownFeatureDependency(
                        package: packageName,
                        dependency: alias
                    )
                }
                expansion.activatedAliases.insert(alias)
                continue
            }
            if let slash = feature.firstIndex(of: "/") {
                var alias = String(feature[..<slash])
                let child = String(feature[feature.index(after: slash)...])
                let isWeak = alias.hasSuffix("?")
                if isWeak { alias.removeLast() }
                guard dependencyAliases.contains(alias), !child.isEmpty else {
                    throw CargoResolutionError.unknownFeatureDependency(
                        package: packageName,
                        dependency: alias
                    )
                }
                if isWeak {
                    weakRequests.append((alias, child))
                } else {
                    expansion.dependencyFeatures[alias, default: []].insert(child)
                    if optionalDependencyAliases.contains(alias) {
                        expansion.activatedAliases.insert(alias)
                    }
                }
                continue
            }

            if let values = featureTable[feature] {
                expansion.features.insert(feature)
                pending.append(contentsOf: values)
            } else if optionalDependencyAliases.contains(feature),
                      !explicitlyReferencedDependencies.contains(feature) {
                // An optional dependency with no `dep:` reference implies a
                // feature of the same name that turns it on.
                expansion.features.insert(feature)
                expansion.activatedAliases.insert(feature)
            } else if feature != "default" {
                throw CargoResolutionError.unknownFeature(
                    package: packageName,
                    feature: feature
                )
            }
        }

        for request in weakRequests where expansion.activatedAliases.contains(request.alias) {
            expansion.dependencyFeatures[request.alias, default: []].insert(request.feature)
        }
        return expansion
    }

    /// Builds the outgoing edges of a package from its expanded feature set.
    static func edges(
        for dependencies: [some FeatureResolvableDependency],
        expansion: Expansion
    ) -> [Edge] {
        dependencies.compactMap { dependency in
            guard !dependency.isOptional || expansion.activatedAliases.contains(dependency.alias)
            else {
                return nil
            }
            var features = Set(dependency.requestedFeatures)
            features.formUnion(expansion.dependencyFeatures[dependency.alias] ?? [])
            if dependency.usesDefaultFeatures { features.insert("default") }
            return Edge(
                alias: dependency.alias,
                packageName: dependency.packageName,
                requirement: dependency.resolvedRequirement,
                requestedFeatures: features
            )
        }
        .sorted { $0.alias < $1.alias }
    }

    /// Convenience for the root project, whose own feature table can activate
    /// optional dependencies too.
    static func rootEdges(
        for dependencies: [ManifestDependency],
        featureTable: [String: [String]],
        enabledFeatures: Set<String>,
        packageName: String
    ) throws -> [Edge] {
        let expansion = try expand(
            requested: enabledFeatures,
            featureTable: featureTable,
            optionalDependencyAliases: Set(dependencies.filter(\.isOptional).map(\.alias)),
            dependencyAliases: Set(dependencies.map(\.alias)),
            packageName: packageName
        )
        return edges(for: dependencies, expansion: expansion)
    }
}
