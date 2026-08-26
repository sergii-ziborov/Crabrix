import Foundation

struct CrabrixProject: Codable, Equatable, Sendable {
    struct Provenance: Codable, Equatable, Sendable {
        enum Source: String, Codable, Sendable {
            case files
            case github
            case crabrixPackage
        }

        let source: Source
        let owner: String?
        let repository: String?
        let reference: String?
        let commit: String?
        let importedAt: Date

        static func files() -> Provenance {
            Provenance(
                source: .files,
                owner: nil,
                repository: nil,
                reference: nil,
                commit: nil,
                importedAt: Date()
            )
        }
    }

    let name: String
    let files: [String: String]
    let entryFile: String
    let provenance: Provenance?

    var manifest: CargoManifest? {
        files["Cargo.toml"].flatMap(CargoManifest.parse)
    }

    var rustFileCount: Int {
        files.keys.filter { $0.hasSuffix(".rs") }.count
    }
}

struct ProjectBuildRecord: Codable, Equatable, Sendable {
    let succeeded: Bool
    let phase: CompilationResult.Phase
    let durationMilliseconds: Int
    let finishedAt: Date

    init(result: CompilationResult, finishedAt: Date = Date()) {
        succeeded = result.succeeded
        phase = result.phase
        let parts = result.duration.components
        let milliseconds = Double(parts.seconds) * 1_000
            + Double(parts.attoseconds) / 1_000_000_000_000_000
        durationMilliseconds = max(0, Int(milliseconds))
        self.finishedAt = finishedAt
    }
}

struct ProjectLibraryItem: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var project: CrabrixProject
    var lastOpenedAt: Date
    var lastBuild: ProjectBuildRecord?
}

struct ProjectCompatibilityReport: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case ready
        case inspect
    }

    let status: Status
    let rustFiles: Int
    let dependencies: Int
    let notes: [String]

    static func scan(_ project: CrabrixProject) -> ProjectCompatibilityReport {
        var notes: [String] = []
        let manifests = project.files
            .filter { $0.key == "Cargo.toml" || $0.key.hasSuffix("/Cargo.toml") }
            .compactMap { CargoManifest.parse($0.value) }
        let dependencyCount = manifests.reduce(0) { $0 + $1.dependencies.count }

        if dependencyCount > 0 {
            notes.append("Cargo dependency resolution is not enabled in this build.")
        }
        if project.files.keys.contains(where: { $0 == "build.rs" || $0.hasSuffix("/build.rs") }) {
            notes.append("build.rs requires compatibility review.")
        }
        if project.files["Cargo.toml"]?.contains("[workspace]") == true {
            notes.append("Workspace detected; Crabrix opened the discovered root.")
        }
        if project.entryFile.hasSuffix("lib.rs") {
            notes.append("Library crate detected; local Run still expects a binary entry point.")
        }

        return ProjectCompatibilityReport(
            status: notes.isEmpty ? .ready : .inspect,
            rustFiles: project.rustFileCount,
            dependencies: dependencyCount,
            notes: notes
        )
    }
}
