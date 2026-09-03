import XCTest
@testable import Crabrix

/// A registry that answers from fixtures instead of the network.
private struct StubIndex: CrateIndexProviding {
    let files: [String: RegistryIndexFile]

    func indexFile(for crate: String) async throws -> RegistryIndexFile {
        guard let file = files[crate.lowercased()] else {
            throw CrateRegistryError.crateNotFound(crate)
        }
        return file
    }

    static func make(_ lines: [String: [String]]) throws -> StubIndex {
        var files: [String: RegistryIndexFile] = [:]
        for (name, entries) in lines {
            let data = Data(entries.joined(separator: "\n").utf8)
            files[name] = try SparseRegistryIndex.parse(data, name: name)
        }
        return StubIndex(files: files)
    }
}

/// Proves offline/frozen resolution cannot accidentally fall through to the
/// network-backed entry point.
private struct OfflineOnlyIndex: CrateIndexProviding {
    let files: [String: RegistryIndexFile]

    func indexFile(for crate: String) async throws -> RegistryIndexFile {
        throw CrateRegistryError.transport("network access is forbidden in this fixture")
    }

    func cachedIndexFile(for crate: String) async throws -> RegistryIndexFile {
        guard let file = files[crate.lowercased()] else {
            throw CrateRegistryError.offlineCacheMiss(crate)
        }
        return file
    }
}

private func indexLine(
    _ name: String,
    _ version: String,
    deps: String = "[]",
    features: String = "{}",
    yanked: Bool = false,
    links: String? = nil,
    rustVersion: String? = nil
) -> String {
    let linksField = links.map { ",\"links\":\"\($0)\"" } ?? ""
    let rustVersionField = rustVersion.map { ",\"rust_version\":\"\($0)\"" } ?? ""
    return """
    {"name":"\(name)","vers":"\(version)","deps":\(deps),"cksum":"\(String(repeating: "a", count: 64))","features":\(features),"yanked":\(yanked)\(linksField)\(rustVersionField)}
    """
}

private func dep(
    _ name: String,
    _ req: String,
    optional: Bool = false,
    defaultFeatures: Bool = true,
    features: [String] = [],
    kind: String = "normal",
    target: String? = nil,
    package: String? = nil
) -> String {
    let featureList = features.map { "\"\($0)\"" }.joined(separator: ",")
    let targetField = target.map { "\"\($0)\"" } ?? "null"
    let packageField = package.map { ",\"package\":\"\($0)\"" } ?? ""
    return """
    {"name":"\(name)","req":"\(req)","features":[\(featureList)],"optional":\(optional),"default_features":\(defaultFeatures),"target":\(targetField),"kind":"\(kind)"\(packageField)}
    """
}

private func manifest(_ body: String) throws -> CratePackageManifest {
    try CratePackageManifest.parse("""
    [package]
    name = "root"
    version = "0.1.0"
    edition = "2021"

    \(body)
    """)
}

final class CargoResolverTests: XCTestCase {
    func testSelectsHighestCompatibleVersionAndSkipsYanked() async throws {
        let index = try StubIndex.make([
            "alpha": [
                indexLine("alpha", "1.0.0"),
                indexLine("alpha", "1.4.0"),
                indexLine("alpha", "1.9.0", yanked: true),
                indexLine("alpha", "2.0.0"),
            ],
        ])
        let root = try manifest("[dependencies]\nalpha = \"1\"")
        let graph = try await CargoResolver(index: index).resolve(
            rootDependencies: root.dependencies,
            rootFeatures: root.features
        )

        XCTAssertEqual(graph.rootDependencies["alpha"]?.version.description, "1.4.0")
        XCTAssertEqual(graph.packages.count, 1)
    }

    func testTheRootsOwnActiveFeaturesAreReported() async throws {
        let index = try StubIndex.make([:])
        let root = try manifest("""
        [features]
        default = ["fancy"]
        fancy = ["shiny"]
        shiny = []
        unused = []
        """)
        let graph = try await CargoResolver(index: index).resolve(
            rootDependencies: root.dependencies,
            rootFeatures: root.features
        )

        // Exactly what Cargo would pass to rustc: `default` is itself a feature.
        XCTAssertEqual(graph.rootFeatures, ["default", "fancy", "shiny"])
    }

    func testAManifestWithoutFeaturesEnablesNone() async throws {
        let index = try StubIndex.make([:])
        let root = try manifest("[dependencies]")
        let graph = try await CargoResolver(index: index).resolve(
            rootDependencies: root.dependencies,
            rootFeatures: root.features
        )

        XCTAssertTrue(graph.rootFeatures.isEmpty, "no [features] table means no cfg flags")
    }

    func testResolvesTransitiveDependenciesInBuildOrder() async throws {
        let index = try StubIndex.make([
            "top": [indexLine("top", "1.0.0", deps: "[\(dep("mid", "^1"))]")],
            "mid": [indexLine("mid", "1.2.0", deps: "[\(dep("leaf", "^0.3"))]")],
            "leaf": [indexLine("leaf", "0.3.4")],
        ])
        let root = try manifest("[dependencies]\ntop = \"1\"")
        let graph = try await CargoResolver(index: index).resolve(
            rootDependencies: root.dependencies,
            rootFeatures: root.features
        )

        XCTAssertEqual(graph.packages.count, 3)
        let order = graph.buildOrder.map(\.name)
        XCTAssertLessThan(
            try XCTUnwrap(order.firstIndex(of: "leaf")),
            try XCTUnwrap(order.firstIndex(of: "mid"))
        )
        XCTAssertLessThan(
            try XCTUnwrap(order.firstIndex(of: "mid")),
            try XCTUnwrap(order.firstIndex(of: "top"))
        )
    }

    func testUnifiesRequirementsOntoOneCompatibleVersion() async throws {
        let index = try StubIndex.make([
            "shared": [
                indexLine("shared", "1.0.0"),
                indexLine("shared", "1.2.0"),
                indexLine("shared", "1.5.0"),
            ],
            "left": [indexLine("left", "1.0.0", deps: "[\(dep("shared", "^1.2"))]")],
        ])
        let root = try manifest("""
        [dependencies]
        left = "1"
        shared = "=1.2.0"
        """)
        let graph = try await CargoResolver(index: index).resolve(
            rootDependencies: root.dependencies,
            rootFeatures: root.features
        )

        // Both requirements land on one copy, which is what Cargo links.
        XCTAssertEqual(graph.packages.keys.filter { $0.name == "shared" }.count, 1)
        XCTAssertEqual(graph.rootDependencies["shared"]?.version.description, "1.2.0")
    }

    func testReportsUnsatisfiableRequirements() async throws {
        let index = try StubIndex.make([
            "shared": [indexLine("shared", "1.0.0"), indexLine("shared", "1.2.0")],
            "left": [indexLine("left", "1.0.0", deps: "[\(dep("shared", "=1.0.0"))]")],
        ])
        let root = try manifest("""
        [dependencies]
        left = "1"
        shared = "=1.2.0"
        """)
        do {
            _ = try await CargoResolver(index: index).resolve(
                rootDependencies: root.dependencies,
                rootFeatures: root.features
            )
            XCTFail("Expected a conflict")
        } catch let error as CargoResolutionError {
            guard case let .conflict(crate, _) = error else {
                return XCTFail("Unexpected error \(error)")
            }
            XCTAssertEqual(crate, "shared")
        }
    }

    func testKeepsIncompatibleMajorVersionsSideBySide() async throws {
        let index = try StubIndex.make([
            "shared": [indexLine("shared", "1.4.0"), indexLine("shared", "2.1.0")],
            "legacy": [indexLine("legacy", "1.0.0", deps: "[\(dep("shared", "^1"))]")],
        ])
        let root = try manifest("""
        [dependencies]
        legacy = "1"
        shared = "2"
        """)
        let graph = try await CargoResolver(index: index).resolve(
            rootDependencies: root.dependencies,
            rootFeatures: root.features
        )

        let versions = graph.packages.keys.filter { $0.name == "shared" }
            .map(\.version.description).sorted()
        XCTAssertEqual(versions, ["1.4.0", "2.1.0"])
    }

    func testTargetPredicatesFilterOutForeignPlatformDependencies() async throws {
        let index = try StubIndex.make([
            "portable": [
                indexLine(
                    "portable",
                    "1.0.0",
                    deps: "[\(dep("winapi", "^0.3", target: "cfg(windows)")),\(dep("wasi", "^0.11", target: "cfg(target_os = \\\"wasi\\\")"))]"
                ),
            ],
            "winapi": [indexLine("winapi", "0.3.9")],
            "wasi": [indexLine("wasi", "0.11.0")],
        ])
        let root = try manifest("[dependencies]\nportable = \"1\"")
        let graph = try await CargoResolver(index: index).resolve(
            rootDependencies: root.dependencies,
            rootFeatures: root.features
        )

        let names = Set(graph.packages.keys.map(\.name))
        XCTAssertTrue(names.contains("wasi"))
        XCTAssertFalse(names.contains("winapi"))
    }

    func testDevAndBuildDependenciesAreNotResolved() async throws {
        let index = try StubIndex.make([
            "lib": [
                indexLine(
                    "lib",
                    "1.0.0",
                    deps: "[\(dep("testkit", "^1", kind: "dev")),\(dep("autocfg", "^1", kind: "build"))]"
                ),
            ],
            "testkit": [indexLine("testkit", "1.0.0")],
            "autocfg": [indexLine("autocfg", "1.0.0")],
        ])
        let root = try manifest("[dependencies]\nlib = \"1\"")
        let graph = try await CargoResolver(index: index).resolve(
            rootDependencies: root.dependencies,
            rootFeatures: root.features
        )

        XCTAssertEqual(Set(graph.packages.keys.map(\.name)), ["lib"])
    }

    func testOptionalDependencyIsActivatedOnlyByItsFeature() async throws {
        let index = try StubIndex.make([
            "host": [
                indexLine(
                    "host",
                    "1.0.0",
                    deps: "[\(dep("extra", "^1", optional: true))]",
                    features: "{\"default\":[],\"fancy\":[\"extra\"]}"
                ),
            ],
            "extra": [indexLine("extra", "1.0.0")],
        ])

        let plain = try manifest("[dependencies]\nhost = \"1\"")
        let withoutFeature = try await CargoResolver(index: index).resolve(
            rootDependencies: plain.dependencies,
            rootFeatures: plain.features
        )
        XCTAssertFalse(withoutFeature.packages.keys.contains { $0.name == "extra" })

        let enabled = try manifest("""
        [dependencies]
        host = { version = "1", features = ["fancy"] }
        """)
        let withFeature = try await CargoResolver(index: index).resolve(
            rootDependencies: enabled.dependencies,
            rootFeatures: enabled.features
        )
        XCTAssertTrue(withFeature.packages.keys.contains { $0.name == "extra" })
    }

    func testFeaturesPropagateToDependenciesAndUnify() async throws {
        let index = try StubIndex.make([
            "front": [
                indexLine(
                    "front",
                    "1.0.0",
                    deps: "[\(dep("core", "^1", defaultFeatures: false, features: ["alloc"]))]",
                    features: "{\"default\":[\"std\"],\"std\":[\"core/std\"]}"
                ),
            ],
            "core": [
                indexLine(
                    "core",
                    "1.0.0",
                    features: "{\"default\":[],\"std\":[],\"alloc\":[]}"
                ),
            ],
        ])
        let root = try manifest("[dependencies]\nfront = \"1\"")
        let graph = try await CargoResolver(index: index).resolve(
            rootDependencies: root.dependencies,
            rootFeatures: root.features
        )

        let core = try XCTUnwrap(graph.packages.values.first { $0.name == "core" })
        XCTAssertEqual(core.sortedFeatures, ["alloc", "std"])
        let front = try XCTUnwrap(graph.packages.values.first { $0.name == "front" })
        XCTAssertEqual(front.sortedFeatures, ["default", "std"])
    }

    func testWeakFeatureOnlyAppliesWhenTheDependencyIsActive() async throws {
        let index = try StubIndex.make([
            "host": [
                indexLine(
                    "host",
                    "1.0.0",
                    deps: "[\(dep("extra", "^1", optional: true, defaultFeatures: false))]",
                    features: "{\"default\":[],\"std\":[\"extra?/std\"],\"with-extra\":[\"dep:extra\"]}"
                ),
            ],
            "extra": [indexLine("extra", "1.0.0", features: "{\"default\":[],\"std\":[]}")],
        ])

        let weakOnly = try manifest("""
        [dependencies]
        host = { version = "1", features = ["std"] }
        """)
        let graph = try await CargoResolver(index: index).resolve(
            rootDependencies: weakOnly.dependencies,
            rootFeatures: weakOnly.features
        )
        XCTAssertFalse(graph.packages.keys.contains { $0.name == "extra" })

        let both = try manifest("""
        [dependencies]
        host = { version = "1", features = ["std", "with-extra"] }
        """)
        let activated = try await CargoResolver(index: index).resolve(
            rootDependencies: both.dependencies,
            rootFeatures: both.features
        )
        let extra = try XCTUnwrap(activated.packages.values.first { $0.name == "extra" })
        XCTAssertTrue(extra.features.contains("std"))
    }

    func testRenamedDependencyResolvesThePublishedPackage() async throws {
        let index = try StubIndex.make([
            "real-crate": [indexLine("real-crate", "1.0.0")],
        ])
        let root = try manifest("""
        [dependencies]
        alias = { version = "1", package = "real-crate" }
        """)
        let graph = try await CargoResolver(index: index).resolve(
            rootDependencies: root.dependencies,
            rootFeatures: root.features
        )

        XCTAssertEqual(graph.rootDependencies["alias"]?.name, "real-crate")
    }

    func testWarnsAboutNativeLibraryAndUnsupportedSources() async throws {
        let index = try StubIndex.make([
            "native": [indexLine("native", "1.0.0", links: "z")],
        ])
        let root = try manifest("""
        [dependencies]
        native = "1"
        local = { path = "../local" }
        forked = { git = "https://example.com/forked.git" }
        """)
        let graph = try await CargoResolver(index: index).resolve(
            rootDependencies: root.dependencies,
            rootFeatures: root.features
        )

        let messages = graph.warnings.map(\.message).joined(separator: "\n")
        XCTAssertTrue(messages.contains("native library"))
        XCTAssertTrue(messages.contains("path dependency"))
        XCTAssertTrue(messages.contains("git dependency"))
    }

    func testMissingCrateSurfacesAsAResolutionError() async throws {
        let index = try StubIndex.make(["present": [indexLine("present", "1.0.0")]])
        let root = try manifest("[dependencies]\nabsent = \"1\"")
        do {
            _ = try await CargoResolver(index: index).resolve(
                rootDependencies: root.dependencies,
                rootFeatures: root.features
            )
            XCTFail("Expected a missing crate error")
        } catch let error as CrateRegistryError {
            XCTAssertEqual(error, .crateNotFound("absent"))
        }
    }

    func testUnknownRequestedFeatureIsAnError() async throws {
        let index = try StubIndex.make([
            "alpha": [indexLine("alpha", "1.0.0", features: "{\"default\":[]}")],
        ])
        let root = try manifest("""
        [dependencies]
        alpha = { version = "1", features = ["ghost"] }
        """)

        do {
            _ = try await CargoResolver(index: index).resolve(
                rootDependencies: root.dependencies,
                rootFeatures: root.features
            )
            XCTFail("Expected an unknown feature error")
        } catch let error as CargoResolutionError {
            XCTAssertEqual(error, .unknownFeature(package: "alpha", feature: "ghost"))
        }
    }

    func testRequestedFeatureSelectsNewestVersionThatStillDefinesIt() async throws {
        let index = try StubIndex.make([
            "alpha": [
                indexLine("alpha", "1.7.0", features: "{\"default\":[],\"legacy\":[]}"),
                indexLine("alpha", "1.8.0", features: "{\"default\":[],\"legacy\":[]}"),
                indexLine("alpha", "1.9.0", features: "{\"default\":[]}"),
            ],
        ])
        let root = try manifest("""
        [dependencies]
        alpha = { version = "1", features = ["legacy"] }
        """)

        let graph = try await CargoResolver(index: index).resolve(
            rootDependencies: root.dependencies,
            rootFeatures: root.features
        )

        XCTAssertEqual(graph.rootDependencies["alpha"]?.version.description, "1.8.0")
        XCTAssertEqual(graph.packages.values.first?.sortedFeatures, ["default", "legacy"])
    }

    func testLateFeatureUnificationCanReselectAnOlderCompatibleVersion() async throws {
        let index = try StubIndex.make([
            "left": [indexLine("left", "1.0.0", deps: "[\(dep("shared", "^1"))]")],
            "right": [
                indexLine(
                    "right",
                    "1.0.0",
                    deps: "[\(dep("shared", "^1", features: ["legacy"]))]"
                ),
            ],
            "shared": [
                indexLine("shared", "1.8.0", features: "{\"default\":[],\"legacy\":[]}"),
                indexLine("shared", "1.9.0", features: "{\"default\":[]}"),
            ],
        ])
        let root = try manifest("""
        [dependencies]
        left = "1"
        right = "1"
        """)

        let graph = try await CargoResolver(index: index).resolve(
            rootDependencies: root.dependencies,
            rootFeatures: root.features
        )

        let shared = try XCTUnwrap(graph.packages.values.first { $0.name == "shared" })
        XCTAssertEqual(shared.version.description, "1.8.0")
        XCTAssertTrue(shared.features.contains("legacy"))
    }

    func testResolverThreePrefersRootMSRVCompatibleRelease() async throws {
        let index = try StubIndex.make([
            "alpha": [
                indexLine("alpha", "1.0.0", rustVersion: "1.60"),
                indexLine("alpha", "1.5.0", rustVersion: "1.74"),
            ],
        ])
        let root = try manifest("[dependencies]\nalpha = \"1\"")

        let resolverTwo = try await CargoResolver(index: index).resolve(
            rootDependencies: root.dependencies,
            rootFeatures: root.features,
            resolverVersion: .v2,
            rootProjectRustVersion: SemanticVersion("1.62")
        )
        let resolverThree = try await CargoResolver(index: index).resolve(
            rootDependencies: root.dependencies,
            rootFeatures: root.features,
            resolverVersion: .v3,
            rootProjectRustVersion: SemanticVersion("1.62")
        )

        XCTAssertEqual(resolverTwo.rootDependencies["alpha"]?.version.description, "1.5.0")
        XCTAssertEqual(resolverThree.rootDependencies["alpha"]?.version.description, "1.0.0")
    }

    func testResolverThreeFallsBackWhenRequirementHasNoRootMSRVCompatibleRelease() async throws {
        let index = try StubIndex.make([
            "alpha": [indexLine("alpha", "1.5.0", rustVersion: "1.74")],
        ])
        let root = try manifest("[dependencies]\nalpha = \"1.5\"")

        let graph = try await CargoResolver(index: index).resolve(
            rootDependencies: root.dependencies,
            rootFeatures: root.features,
            resolverVersion: .v3,
            rootProjectRustVersion: SemanticVersion("1.62")
        )

        XCTAssertEqual(graph.rootDependencies["alpha"]?.version.description, "1.5.0")
    }

    func testResolverOneUnifiesInactiveTargetFeaturesButResolverTwoDoesNot() async throws {
        let index = try StubIndex.make([
            "front": [
                indexLine(
                    "front",
                    "1.0.0",
                    deps: "[\(dep("shared", "^1", features: ["alloc"])),\(dep("shared", "^1", features: ["windows"], target: "cfg(windows)"))]"
                ),
            ],
            "shared": [
                indexLine(
                    "shared",
                    "1.0.0",
                    features: "{\"default\":[],\"alloc\":[],\"windows\":[]}"
                ),
            ],
        ])
        let root = try manifest("[dependencies]\nfront = \"1\"")

        let legacy = try await CargoResolver(index: index).resolve(
            rootDependencies: root.dependencies,
            rootFeatures: root.features,
            resolverVersion: .v1
        )
        let modern = try await CargoResolver(index: index).resolve(
            rootDependencies: root.dependencies,
            rootFeatures: root.features,
            resolverVersion: .v2
        )

        let legacyShared = try XCTUnwrap(legacy.packages.values.first { $0.name == "shared" })
        let modernShared = try XCTUnwrap(modern.packages.values.first { $0.name == "shared" })
        XCTAssertEqual(legacyShared.sortedFeatures, ["alloc", "default", "windows"])
        XCTAssertEqual(modernShared.sortedFeatures, ["alloc", "default"])
    }

    func testMSRVSelectsNewestVersionSupportedByBundledRustc() async throws {
        let index = try StubIndex.make([
            "alpha": [
                indexLine("alpha", "1.0.0", rustVersion: "1.80"),
                indexLine("alpha", "1.1.0", rustVersion: "1.97"),
            ],
        ])
        let root = try manifest("[dependencies]\nalpha = \"1\"")
        let graph = try await CargoResolver(index: index).resolve(
            rootDependencies: root.dependencies,
            rootFeatures: root.features
        )

        XCTAssertEqual(graph.rootDependencies["alpha"]?.version.description, "1.0.0")
    }

    func testMSRVFailureNamesRequiredAndBundledVersions() async throws {
        let index = try StubIndex.make([
            "alpha": [indexLine("alpha", "1.0.0", rustVersion: "1.97")],
        ])
        let root = try manifest("[dependencies]\nalpha = \"1\"")

        do {
            _ = try await CargoResolver(index: index).resolve(
                rootDependencies: root.dependencies,
                rootFeatures: root.features
            )
            XCTFail("Expected an MSRV error")
        } catch let error as CargoResolutionError {
            XCTAssertEqual(
                error,
                .requiresNewerRust(crate: "alpha", required: "1.97.0", bundled: "1.96.0-dev")
            )
        }
    }

    func testNormalResolutionPreservesCompatibleCargoLockPin() async throws {
        let originalIndex = try StubIndex.make([
            "alpha": [indexLine("alpha", "1.0.0")],
        ])
        let root = try manifest("[dependencies]\nalpha = \"1\"")
        let original = try await CargoResolver(index: originalIndex).resolve(
            rootDependencies: root.dependencies,
            rootFeatures: root.features
        )
        let lockfile = CargoLockfile(graph: original, rootName: "root", rootVersion: "0.1.0")

        let newerIndex = try StubIndex.make([
            "alpha": [indexLine("alpha", "1.0.0"), indexLine("alpha", "1.9.0")],
        ])
        let rebuilt = try await CargoResolver(index: newerIndex).resolve(
            rootDependencies: root.dependencies,
            rootFeatures: root.features,
            lockfile: lockfile
        )

        XCTAssertEqual(rebuilt.rootDependencies["alpha"]?.version.description, "1.0.0")
    }

    func testLockedResolutionRejectsManifestThatWouldChangeLockfile() async throws {
        let index = try StubIndex.make([
            "alpha": [indexLine("alpha", "1.0.0"), indexLine("alpha", "2.0.0")],
        ])
        let oldRoot = try manifest("[dependencies]\nalpha = \"1\"")
        let original = try await CargoResolver(index: index).resolve(
            rootDependencies: oldRoot.dependencies,
            rootFeatures: oldRoot.features
        )
        let lockfile = CargoLockfile(graph: original, rootName: "root", rootVersion: "0.1.0")
        let changedRoot = try manifest("[dependencies]\nalpha = \"2\"")

        do {
            _ = try await CargoResolver(index: index).resolve(
                rootDependencies: changedRoot.dependencies,
                rootFeatures: changedRoot.features,
                lockfile: lockfile,
                mode: .locked
            )
            XCTFail("Expected --locked semantics to reject the manifest change")
        } catch let error as CargoLockfileError {
            XCTAssertEqual(error, .incompatible(crate: "alpha", requirement: "2"))
        }
    }

    func testUpdateModeIgnoresOldPin() async throws {
        let index = try StubIndex.make([
            "alpha": [indexLine("alpha", "1.0.0"), indexLine("alpha", "1.9.0")],
        ])
        let root = try manifest("[dependencies]\nalpha = \"1\"")
        let oldLock = CargoLockfile(entries: [
            .init(
                name: "root",
                version: SemanticVersion("0.1.0")!,
                checksum: nil,
                dependencies: ["alpha 1.0.0"]
            ),
            .init(
                name: "alpha",
                version: SemanticVersion("1.0.0")!,
                checksum: String(repeating: "a", count: 64),
                dependencies: []
            ),
        ])

        let updated = try await CargoResolver(index: index).resolve(
            rootDependencies: root.dependencies,
            rootFeatures: root.features,
            lockfile: oldLock,
            mode: .update
        )
        XCTAssertEqual(updated.rootDependencies["alpha"]?.version.description, "1.9.0")
    }

    func testOfflineResolutionUsesOnlyCachedIndexData() async throws {
        let file = try SparseRegistryIndex.parse(
            Data(indexLine("alpha", "1.2.0").utf8),
            name: "alpha"
        )
        let root = try manifest("[dependencies]\nalpha = \"1\"")
        let graph = try await CargoResolver(
            index: OfflineOnlyIndex(files: ["alpha": file])
        ).resolve(
            rootDependencies: root.dependencies,
            rootFeatures: root.features,
            mode: .offline
        )

        XCTAssertEqual(graph.rootDependencies["alpha"]?.version.description, "1.2.0")
    }

    func testFrozenResolutionRequiresCachedExactLockfileGraph() async throws {
        let originalIndex = try StubIndex.make([
            "alpha": [indexLine("alpha", "1.0.0")],
        ])
        let root = try manifest("[dependencies]\nalpha = \"1\"")
        let original = try await CargoResolver(index: originalIndex).resolve(
            rootDependencies: root.dependencies,
            rootFeatures: root.features
        )
        let lockfile = CargoLockfile(
            graph: original,
            rootName: "root",
            rootVersion: "0.1.0"
        )
        let cached = try SparseRegistryIndex.parse(
            Data([
                indexLine("alpha", "1.0.0"),
                indexLine("alpha", "1.9.0"),
            ].joined(separator: "\n").utf8),
            name: "alpha"
        )

        let graph = try await CargoResolver(
            index: OfflineOnlyIndex(files: ["alpha": cached])
        ).resolve(
            rootDependencies: root.dependencies,
            rootFeatures: root.features,
            lockfile: lockfile,
            mode: .frozen
        )

        XCTAssertEqual(graph.rootDependencies["alpha"]?.version.description, "1.0.0")
    }

    func testOfflineResolutionNamesMissingCachedIndex() async throws {
        let root = try manifest("[dependencies]\nalpha = \"1\"")
        do {
            _ = try await CargoResolver(
                index: OfflineOnlyIndex(files: [:])
            ).resolve(
                rootDependencies: root.dependencies,
                rootFeatures: root.features,
                mode: .offline
            )
            XCTFail("Expected an exact offline cache miss")
        } catch let error as CrateRegistryError {
            XCTAssertEqual(error, .offlineCacheMiss("alpha"))
        }
    }
}
