import Foundation
import CryptoKit

/// The editable snapshot contract. Cargo's package count and Playground's
/// smaller guest limits are separate contracts, never aliases for this one.
enum ProjectFilePolicy {
    static let maximumFileCount = 2_048
    static let maximumFileBytes = 2 * 1_024 * 1_024
    static let maximumProjectBytes = 16_000_000
    static let maximumMetadataBytes = 8_000_000
    static let maximumPathDepth = 32

    enum Failure: LocalizedError, Equatable {
        case unsafePath(String), fileTooLarge(String), tooManyFiles, projectTooLarge
        case unreadable(String), snapshotMismatch(String), metadataTooLarge
        var errorDescription: String? {
            switch self {
            case let .unsafePath(path): "Unsupported or conflicting project path: \(path). Files are kept unchanged."
            case let .fileTooLarge(path): "\(path) exceeds the 2 MiB editable-file limit. Keep or export the current text, then reduce it and retry."
            case .tooManyFiles: "The editable project exceeds 2,048 files. No files were replaced."
            case .projectTooLarge: "The editable project exceeds 16,000,000 UTF-8 bytes. No files were replaced."
            case let .unreadable(path): "Cannot read \(path) as a regular UTF-8 file. The stored files are kept unchanged."
            case let .snapshotMismatch(path): "The saved snapshot is incomplete or changed at \(path). The stored files are kept for recovery."
            case .metadataTooLarge: "Project metadata exceeds 8,000,000 bytes. The current data is kept unchanged."
            }
        }
    }

    static func validatePath(_ path: String) throws {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0"),
              path.utf8.count <= 1_024, parts.count <= maximumPathDepth,
              !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." || $0.utf8.count > 255 }),
              !parts.contains(where: { $0.lowercased() == ".git" }), parts.first?.lowercased() != ".crabrix"
        else { throw Failure.unsafePath(path) }
    }

    static func validate(_ files: [String: String], entryFile: String? = nil) throws {
        guard files.count <= maximumFileCount else { throw Failure.tooManyFiles }
        var total = 0
        var canonical: Set<String> = []
        var directorySpellings: [String: String] = [:]
        let paths = Set(files.keys)
        for path in files.keys.sorted() {
            try validatePath(path)
            let key = path.precomposedStringWithCanonicalMapping.lowercased()
            guard canonical.insert(key).inserted else { throw Failure.unsafePath(path) }
            var parent = (path as NSString).deletingLastPathComponent
            while !parent.isEmpty {
                guard !paths.contains(parent) else { throw Failure.unsafePath(path) }
                let directoryKey = parent.precomposedStringWithCanonicalMapping.lowercased()
                if let existing = directorySpellings[directoryKey], existing != parent { throw Failure.unsafePath(path) }
                directorySpellings[directoryKey] = parent
                parent = (parent as NSString).deletingLastPathComponent
            }
            let bytes = files[path]!.utf8.count
            guard bytes <= maximumFileBytes else { throw Failure.fileTooLarge(path) }
            total += bytes
            guard total <= maximumProjectBytes else { throw Failure.projectTooLarge }
        }
        // Check case/normalisation aliases between a file and a directory too.
        for path in files.keys {
            var parent = (path as NSString).deletingLastPathComponent
            while !parent.isEmpty {
                guard !canonical.contains(parent.precomposedStringWithCanonicalMapping.lowercased()) else { throw Failure.unsafePath(path) }
                parent = (parent as NSString).deletingLastPathComponent
            }
        }
        if let entryFile, files[entryFile] == nil { throw Failure.snapshotMismatch(entryFile) }
    }

    static func digests(_ files: [String: String]) -> [String: String] {
        files.mapValues { SHA256.hash(data: Data($0.utf8)).map { String(format: "%02x", $0) }.joined() }
    }

    static func verify(_ expected: [String: String]?, files: [String: String]) throws {
        guard let expected else { return } // Version 0–2 snapshots have no inventory.
        guard Set(expected.keys) == Set(files.keys) else {
            throw Failure.snapshotMismatch(Set(expected.keys).symmetricDifference(files.keys).sorted().first ?? "files")
        }
        let actual = digests(files)
        for path in expected.keys.sorted() where expected[path] != actual[path] { throw Failure.snapshotMismatch(path) }
    }
}

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
            case academy
        }

        struct CourseOrigin: Codable, Equatable, Sendable {
            struct Recording: Codable, Equatable, Sendable {
                let key: String
                let sourceHash: String
                let input: String
                let packVersion: String
                let packDigest: String
                let courseContentVersion: String
            }
            let courseID: String
            let contentVersion: String
            let lessonID: String
            let templateHash: String
            var recording: Recording? = nil
        }

        let source: Source
        let owner: String?
        let repository: String?
        let reference: String?
        let commit: String?
        let importedAt: Date
        var course: CourseOrigin? = nil

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

        static func academy(session: CourseSession, templateHash: String) -> Provenance {
            Provenance(
                source: .academy, owner: nil, repository: nil,
                reference: nil, commit: nil, importedAt: Date(),
                course: CourseOrigin(
                    courseID: session.courseID,
                    contentVersion: session.contentVersion,
                    lessonID: session.lessonID,
                    templateHash: templateHash
                )
            )
        }

        static func academyExample(id: String, courseID: String = "projects",
                                   contentVersion: String, templateHash: String) -> Provenance {
            Provenance(
                source: .academy, owner: nil, repository: nil,
                reference: nil, commit: nil, importedAt: Date(),
                course: CourseOrigin(
                    courseID: courseID, contentVersion: contentVersion,
                    lessonID: "example/\(id)", templateHash: templateHash
                )
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
        static let currentVersion = 3

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
        let fileDigests: [String: String]?

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
            isFavorite: Bool? = nil,
            fileDigests: [String: String]? = nil
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
            self.fileDigests = fileDigests
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
            fileDigests = ProjectFilePolicy.digests(project.files)
        }
    }

    var manifest: CargoManifest? {
        files["Cargo.toml"].flatMap(CargoManifest.parse)
    }

    var rustFileCount: Int {
        files.keys.filter { $0.hasSuffix(".rs") }.count
    }
}

enum ProjectVerifiedOperation: String, CaseIterable, Sendable {
    case check, build, run, debug
}

struct ProjectBuildRecord: Codable, Equatable, Sendable {
    let succeeded: Bool
    let phase: CompilationResult.Phase
    let durationMilliseconds: Int
    let finishedAt: Date
    let sourceTreeHash: String?
    let toolchainID: String?
    let resourceTreeHash: String?
    /// Older records did not distinguish ordinary execution from source Debug.
    /// Nil deliberately retains that ambiguity during migration.
    let isDebugExecution: Bool?

    init(result: CompilationResult, finishedAt: Date = Date(), sourceTreeHash: String? = nil, toolchainID: String? = nil, resourceTreeHash: String? = nil, isDebugExecution: Bool? = nil) {
        succeeded = result.succeeded
        phase = result.phase
        let parts = result.duration.components
        let milliseconds = Double(parts.seconds) * 1_000
            + Double(parts.attoseconds) / 1_000_000_000_000_000
        durationMilliseconds = max(0, Int(milliseconds))
        self.finishedAt = finishedAt
        self.sourceTreeHash = sourceTreeHash
        self.toolchainID = toolchainID
        self.resourceTreeHash = resourceTreeHash
        self.isDebugExecution = isDebugExecution
    }

    /// Historical evidence for identical source/resources and compiler profile.
    /// It never authorizes editing or an operation against a stale generation.
    func verifies(_ operation: ProjectVerifiedOperation, revision: WorkspaceRevision) -> Bool {
        guard succeeded, let sourceTreeHash, sourceTreeHash == revision.sourceTreeHash,
              let toolchainID, toolchainID == revision.toolchainID,
              resourceTreeHash == revision.resourceTreeHash else { return false }
        switch phase {
        case .check:
            return operation == .check && isDebugExecution != true
        case .compile:
            return (operation == .check || operation == .build) && isDebugExecution != true
        case .run:
            if isDebugExecution == true { return operation == .debug }
            guard isDebugExecution == false else { return false }
            return operation != .debug
        case .setup, .test, .format:
            return false
        }
    }
}

struct ProjectLibraryItem: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var project: CrabrixProject
    var lastOpenedAt: Date
    var lastBuild: ProjectBuildRecord?
    var recoveryMessage: String?
    let sourceTreeHash: String?
    let storageVersion: Int?
    var resourceTreeHash: String? = nil
    var currentBuild: ProjectBuildRecord? {
        guard let lastBuild, let sourceTreeHash, sourceTreeHash == lastBuild.sourceTreeHash,
              lastBuild.resourceTreeHash == resourceTreeHash,
              lastBuild.toolchainID == WasmRustCompiler.executionIdentity else { return nil }
        return lastBuild
    }

    init(
        project: CrabrixProject,
        lastOpenedAt: Date,
        lastBuild: ProjectBuildRecord?,
        storageVersion: Int? = 3
    ) {
        id = project.id
        self.project = project
        self.lastOpenedAt = lastOpenedAt
        self.lastBuild = lastBuild
        recoveryMessage = nil
        sourceTreeHash = WorkspaceRevision.capture(project: project, generation: 0, toolchainID: WasmRustCompiler.executionIdentity).sourceTreeHash
        self.storageVersion = storageVersion
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
            notes.append("Std-only WASI build scripts can run locally. Scripts needing host subprocesses, native linking or separate build dependencies require a different profile.")
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
