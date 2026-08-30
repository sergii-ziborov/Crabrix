import Foundation
import CryptoKit

/// An already-built dependency the compiler passes to rustc with `--extern`.
struct CargoExtern: Sendable, Equatable, Hashable {
    /// The name the dependent crate uses in code.
    let alias: String
    /// The rustc crate name of the dependency itself.
    let crateName: String
    let fingerprint: String

    func fileName(emit: CargoEmitKind) -> String {
        "lib\(crateName)-\(fingerprint).\(emit.fileExtension)"
    }
}

/// Which artefact a build produces.
///
/// `check` only needs metadata, which is how `cargo check` stays much cheaper
/// than a full build; `link` produces the rlib the final binary links against.
enum CargoEmitKind: String, Sendable, Equatable {
    case metadata
    case link

    var fileExtension: String {
        switch self {
        case .metadata: "rmeta"
        case .link: "rlib"
        }
    }

    var rustcEmitValue: String {
        switch self {
        case .metadata: "metadata"
        case .link: "link"
        }
    }
}

/// Everything the compiler needs to build one dependency crate.
struct CargoBuildUnit: Sendable, Equatable, Identifiable {
    let package: PackageID
    /// Stable 16-hex identity covering source, features, and dependency identity.
    let fingerprint: String
    let crateName: String
    let edition: String
    /// Sorted, so the fingerprint is stable.
    let features: [String]
    /// The crate's library entry point, relative to its source directory.
    let libraryPath: String
    let externs: [CargoExtern]
    let authors: String
    let description: String
    let repository: String
    let license: String
    let homepage: String

    var id: String { fingerprint }
    var sourceDirectoryName: String { "\(package.name)-\(package.version)" }
}

/// A topologically ordered dependency build, dependencies first.
struct CargoBuildPlan: Sendable, Equatable {
    let units: [CargoBuildUnit]
    /// The externs the root project itself compiles against.
    let rootExterns: [CargoExtern]

    var isEmpty: Bool { units.isEmpty }

    static let empty = CargoBuildPlan(units: [], rootExterns: [])

    func unit(withFingerprint fingerprint: String) -> CargoBuildUnit? {
        units.first { $0.fingerprint == fingerprint }
    }
}

enum CargoToolchain {
    /// The pinned WASI rustc build the app ships and every artefact is keyed to.
    static let bundledVersion = "artifacts-test-7"
    /// Captured from the bundled module itself (`rustc --version`).
    static let semanticVersionLabel = "1.96.0-dev"
    /// Cargo's `rust-version` comparison uses the release components; the
    /// bundled development compiler implements the 1.96 language surface.
    static let semanticVersion = SemanticVersion(major: 1, minor: 96, patch: 0)
    static let rustcSHA256 = "41412081eefc3e08ec5664ed0748902a7e575e1f267898dcc64d412702df7e83"
    static let sysrootManifestSHA256 = "a89ba732c649a983126750112268614c80b6e7d6bba8c60980cbfd32e04d9892"
    static let artifactIdentity = rustcSHA256 + ":" + sysrootManifestSHA256
}

enum CargoFingerprint {
    /// Bumped whenever the compiler flags or artefact layout change, so stale
    /// artefacts are never reused across an app update.
    static let schemaVersion = "cargo-units-2"
    static let dependencyCompilerFlags = [
        "--crate-type=lib",
        "-Copt-level=0",
        "--cap-lints=allow",
        "-Zunstable-options",
    ]

    static func compute(
        toolchainID: String,
        toolchainArtifactHash: String,
        toolchainSemanticVersion: String,
        compilerFlags: [String],
        targetTriple: String,
        resolverVersion: CargoResolverVersion,
        packageSource: String,
        package: PackageID,
        checksum: String,
        crateName: String,
        edition: String,
        features: [String],
        libraryPath: String,
        dependencies: [CargoExtern]
    ) -> String {
        var hasher = SHA256()
        func absorb(_ value: String) {
            hasher.update(data: Data(value.utf8))
            hasher.update(data: Data([0]))
        }
        absorb(schemaVersion)
        absorb(toolchainID)
        absorb(toolchainArtifactHash)
        absorb(toolchainSemanticVersion)
        absorb(targetTriple)
        absorb(resolverVersion.rawValue)
        absorb(packageSource)
        absorb(package.name)
        absorb(package.version.description)
        absorb(checksum)
        absorb(crateName)
        absorb(edition)
        absorb(libraryPath)
        for flag in compilerFlags { absorb(flag) }
        for feature in features.sorted() { absorb(feature) }
        absorb("|")
        for dependency in dependencies.sorted(by: { $0.alias < $1.alias }) {
            absorb(dependency.alias)
            absorb(dependency.crateName)
            absorb(dependency.fingerprint)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined().prefix(16).description
    }
}
