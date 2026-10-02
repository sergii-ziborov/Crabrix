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

/// Where rustc reads one dependency's source.
///
/// Registry sources stay immutable and checksum-backed. `projectPatch` points
/// at an editable `vendor/<name>-<version>` overlay inside the user's project;
/// the compiler merges that overlay onto a private copy of the verified source
/// before invoking rustc, so assets the editor cannot represent remain intact.
enum CargoBuildSource: Sendable, Equatable {
    case registry(directoryName: String)
    case projectPatch(relativeDirectory: String, registryDirectoryName: String)
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
    let source: CargoBuildSource
    let externs: [CargoExtern]
    let authors: String
    let description: String
    let repository: String
    let license: String
    let homepage: String

    var id: String { fingerprint }
    var sourceDirectoryName: String { "\(package.name)-\(package.version)" }

    var guestSourceDirectory: String {
        switch source {
        case let .registry(directoryName): "/registry/\(directoryName)"
        case .projectPatch: "/patches/\(fingerprint)"
        }
    }

    var isLocallyPatched: Bool {
        if case .projectPatch = source { return true }
        return false
    }
}

/// A topologically ordered dependency build, dependencies first.
struct CargoBuildPlan: Sendable, Equatable {
    let units: [CargoBuildUnit]
    /// The externs the root project itself compiles against.
    let rootExterns: [CargoExtern]
    /// The root package's own active features, sorted. rustc receives one
    /// `--cfg feature="…"` per entry and `CARGO_FEATURE_…` for each, so a
    /// project's own feature gates compile the way its manifest says.
    let rootFeatures: [String]

    var isEmpty: Bool { units.isEmpty }

    static let empty = CargoBuildPlan(units: [], rootExterns: [], rootFeatures: [])

    func unit(withFingerprint fingerprint: String) -> CargoBuildUnit? {
        units.first { $0.fingerprint == fingerprint }
    }
}

enum CargoToolchain {
    /// Build scripts, the app bundle, Cargo fingerprints, and About read the
    /// same checked release input. An invalid bundle fails closed at probe.
    static let release = AppToolchainRelease.load()
    static let bundledVersion = release?.toolchainID ?? "unavailable"
    static let semanticVersionLabel = release?.rustVersion ?? "unavailable"
    static let semanticVersion = SemanticVersion(
        major: release?.rustVersionComponents.major ?? 0,
        minor: release?.rustVersionComponents.minor ?? 0,
        patch: release?.rustVersionComponents.patch ?? 0
    )
    static let rustcSHA256 = release?.rustcSHA256 ?? "unavailable"
    static let sysrootManifestSHA256 = release?.sysrootManifestSHA256 ?? "unavailable"
    static let artifactIdentity = rustcSHA256 + ":" + sysrootManifestSHA256
}

enum CargoFingerprint {
    /// Bumped whenever the compiler flags or artefact layout change, so stale
    /// artefacts are never reused across an app update.
    static let schemaVersion = "cargo-units-3"
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
