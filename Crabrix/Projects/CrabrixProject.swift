import Foundation

struct CrabrixProject: Codable, Equatable, Sendable {
    enum Kind: String, CaseIterable, Codable, Identifiable, Sendable {
        case general
        case learning
        case commandLine
        case library
        case application
        case experiment
        case visual

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: "General"
            case .learning: "Learning"
            case .commandLine: "Command Line"
            case .library: "Library / Crate"
            case .application: "Application"
            case .experiment: "Experiment"
            case .visual: "Visual"
            }
        }

        var systemImage: String {
            switch self {
            case .general: "shippingbox.fill"
            case .learning: "graduationcap.fill"
            case .commandLine: "apple.terminal.fill"
            case .library: "books.vertical.fill"
            case .application: "app.fill"
            case .experiment: "flask.fill"
            case .visual: "paintpalette.fill"
            }
        }
    }

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

    /// Durable identity. Names, GitHub refs, and paths may all change without
    /// turning the workspace into a different project.
    let id: UUID
    var name: String
    var files: [String: String]
    var entryFile: String
    var provenance: Provenance?
    var projectDescription: String
    var tags: [String]
    var folder: String?
    var kind: Kind
    var isFavorite: Bool

    init(
        id: UUID = UUID(),
        name: String,
        files: [String: String],
        entryFile: String,
        provenance: Provenance?,
        projectDescription: String = "",
        tags: [String] = [],
        folder: String? = nil,
        kind: Kind = .general,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.name = name
        self.files = files
        self.entryFile = entryFile
        self.provenance = provenance
        self.projectDescription = projectDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.tags = Self.normalizedTags(tags)
        self.folder = Self.normalizedFolder(folder)
        self.kind = kind
        self.isFavorite = isFavorite
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case files
        case entryFile
        case provenance
        case projectDescription
        case tags
        case folder
        case kind
        case isFavorite
    }

    /// Projects exported before durable identity existed remain readable. A
    /// missing id is assigned once and is persisted on the next save.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        files = try container.decode([String: String].self, forKey: .files)
        entryFile = try container.decode(String.self, forKey: .entryFile)
        provenance = try container.decodeIfPresent(Provenance.self, forKey: .provenance)
        projectDescription = try container.decodeIfPresent(
            String.self,
            forKey: .projectDescription
        ) ?? ""
        tags = Self.normalizedTags(
            try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        )
        folder = Self.normalizedFolder(
            try container.decodeIfPresent(String.self, forKey: .folder)
        )
        kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .general
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
    }

    func replacingID(_ id: UUID) -> CrabrixProject {
        CrabrixProject(
            id: id,
            name: name,
            files: files,
            entryFile: entryFile,
            provenance: provenance,
            projectDescription: projectDescription,
            tags: tags,
            folder: folder,
            kind: kind,
            isFavorite: isFavorite
        )
    }

    mutating func updateOrganization(
        description: String,
        tags: [String],
        folder: String?,
        kind: Kind,
        isFavorite: Bool
    ) {
        projectDescription = description
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.tags = Self.normalizedTags(tags)
        self.folder = Self.normalizedFolder(folder)
        self.kind = kind
        self.isFavorite = isFavorite
    }

    var folderLabel: String { folder ?? "Unfiled" }

    var searchHaystack: String {
        ([name, projectDescription, folder ?? "", kind.title] + tags)
            .joined(separator: " ")
            .lowercased()
    }

    static func normalizedTags(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values
            .flatMap { $0.split(separator: ",").map(String.init) }
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
            }
            .filter { !$0.isEmpty && $0.count <= 24 }
            .filter { seen.insert($0).inserted }
            .prefix(8)
            .map { $0 }
    }

    static func normalizedFolder(_ value: String?) -> String? {
        guard let trimmed = value?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return String(trimmed.prefix(48))
    }

    /// Metadata embedded in an exported package. Source files stay ordinary
    /// files, while identity and provenance round-trip outside the app.
    struct PackageMetadata: Codable, Equatable, Sendable {
        static let currentVersion = 2

        let version: Int
        let projectID: UUID
        let name: String
        let entryFile: String
        let provenance: Provenance?
        let projectDescription: String?
        let tags: [String]?
        let folder: String?
        let kind: Kind?
        let isFavorite: Bool?

        init(
            version: Int = Self.currentVersion,
            projectID: UUID,
            name: String,
            entryFile: String,
            provenance: Provenance?,
            projectDescription: String? = nil,
            tags: [String]? = nil,
            folder: String? = nil,
            kind: Kind? = nil,
            isFavorite: Bool? = nil
        ) {
            self.version = version
            self.projectID = projectID
            self.name = name
            self.entryFile = entryFile
            self.provenance = provenance
            self.projectDescription = projectDescription
            self.tags = tags
            self.folder = folder
            self.kind = kind
            self.isFavorite = isFavorite
        }

        init(project: CrabrixProject) {
            version = Self.currentVersion
            projectID = project.id
            name = project.name
            entryFile = project.entryFile
            provenance = project.provenance
            projectDescription = project.projectDescription
            tags = project.tags
            folder = project.folder
            kind = project.kind
            isFavorite = project.isFavorite
        }
    }

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

    init(
        project: CrabrixProject,
        lastOpenedAt: Date,
        lastBuild: ProjectBuildRecord?
    ) {
        id = project.id
        self.project = project
        self.lastOpenedAt = lastOpenedAt
        self.lastBuild = lastBuild
    }
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

        if project.files.keys.contains(where: { $0 == "build.rs" || $0.hasSuffix("/build.rs") }) {
            notes.append("build.rs is not executed by the local build.")
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
