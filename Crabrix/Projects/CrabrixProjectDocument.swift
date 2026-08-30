import SwiftUI
import UniformTypeIdentifiers
import ZIPFoundation

extension UTType {
    static let crabrixProject = UTType(
        exportedAs: "com.sergiiziborov.crabrix.project",
        conformingTo: .package
    )
}

struct CrabrixProjectDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.crabrixProject] }
    static var writableContentTypes: [UTType] { [.crabrixProject] }

    let project: CrabrixProject

    init(project: CrabrixProject) {
        self.project = project
    }

    init(configuration: ReadConfiguration) throws {
        guard configuration.file.isDirectory else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let files = try Self.readFiles(from: configuration.file)
        guard !files.isEmpty else { throw LocalProjectLoader.ProjectError.noReadableSource }
        let metadata = try Self.readMetadata(from: configuration.file)
        let manifest = files["Cargo.toml"].flatMap(CargoManifest.parse)
        let inferredEntry = ["src/main.rs", "main.rs", "src/lib.rs", "lib.rs"]
            .first(where: { files[$0] != nil })
            ?? files.keys.sorted().first(where: { $0.hasSuffix(".rs") })
            ?? "main.rs"
        project = CrabrixProject(
            id: metadata?.projectID ?? UUID(),
            name: metadata.flatMap { $0.name.isEmpty ? nil : $0.name }
                ?? manifest?.name
                ?? "Crabrix Project",
            files: files,
            entryFile: metadata.flatMap { files[$0.entryFile] == nil ? nil : $0.entryFile }
                ?? inferredEntry,
            provenance: metadata?.provenance,
            projectDescription: metadata?.projectDescription ?? "",
            tags: metadata?.tags ?? [],
            folder: metadata?.folder,
            kind: metadata?.kind ?? .general,
            isFavorite: metadata?.isFavorite ?? false
        )
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try packageWrapper()
    }

    func packageWrapper() throws -> FileWrapper {
        let root = FileWrapper(directoryWithFileWrappers: [:])
        for (path, source) in project.files.sorted(by: { $0.key < $1.key }) {
            try Self.add(data: Data(source.utf8), at: path, to: root)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try Self.add(
            data: encoder.encode(CrabrixProject.PackageMetadata(project: project)),
            at: ".crabrix/project.json",
            to: root
        )
        return root
    }

    private static func add(data: Data, at path: String, to root: FileWrapper) throws {
        let components = path.split(separator: "/").map(String.init)
        guard let fileName = components.last, !fileName.isEmpty else { return }
        var directory = root
        for component in components.dropLast() {
            if let existing = directory.fileWrappers?[component], existing.isDirectory {
                directory = existing
            } else {
                let child = FileWrapper(directoryWithFileWrappers: [:])
                child.preferredFilename = component
                directory.addFileWrapper(child)
                directory = child
            }
        }
        let file = FileWrapper(regularFileWithContents: data)
        file.preferredFilename = fileName
        directory.addFileWrapper(file)
    }

    private static func readFiles(from root: FileWrapper, prefix: String = "") throws -> [String: String] {
        var result: [String: String] = [:]
        for (name, child) in root.fileWrappers ?? [:] {
            if name == ".crabrix" { continue }
            let path = prefix.isEmpty ? name : "\(prefix)/\(name)"
            if child.isDirectory {
                result.merge(try readFiles(from: child, prefix: path)) { _, new in new }
            } else if child.isRegularFile,
                      let data = child.regularFileContents,
                      data.count <= LocalProjectLoader.maximumFileBytes,
                      let source = String(data: data, encoding: .utf8) {
                result[path] = source
            }
        }
        return result
    }

    private static func readMetadata(
        from root: FileWrapper
    ) throws -> CrabrixProject.PackageMetadata? {
        guard let metadataDirectory = root.fileWrappers?[".crabrix"],
              let metadataFile = metadataDirectory.fileWrappers?["project.json"],
              let data = metadataFile.regularFileContents
        else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let metadata = try? decoder.decode(CrabrixProject.PackageMetadata.self, from: data) {
            return metadata
        }

        // Version 0 contained provenance directly and no identity.
        if let provenance = try? decoder.decode(CrabrixProject.Provenance.self, from: data) {
            return CrabrixProject.PackageMetadata(
                projectID: UUID(),
                name: "Crabrix Project",
                entryFile: "",
                provenance: provenance,
                projectDescription: nil,
                tags: nil,
                folder: nil,
                kind: nil,
                isFavorite: nil
            )
        }
        throw CocoaError(.fileReadCorruptFile)
    }
}

enum CrabrixProjectArchive {
    enum ArchiveError: LocalizedError {
        case archiveTooLarge
        case unsafePath(String)

        var errorDescription: String? {
            switch self {
            case .archiveTooLarge:
                "The expanded project archive exceeds Crabrix's safe import limit."
            case let .unsafePath(path):
                "The archive contains an unsafe path: \(path)"
            }
        }
    }

    private static let maximumArchiveBytes: UInt64 = 32_000_000
    private static let maximumArchiveEntries = 1_024

    static func create(project: CrabrixProject) throws -> URL {
        let fileManager = FileManager.default
        let workURL = fileManager.temporaryDirectory
            .appending(path: "CrabrixShare-\(UUID().uuidString)", directoryHint: .isDirectory)
        let projectURL = workURL
            .appending(path: safeFilename(project.name), directoryHint: .isDirectory)
        let archiveURL = workURL.appending(path: "\(safeFilename(project.name)).zip")

        try fileManager.createDirectory(at: workURL, withIntermediateDirectories: true)
        do {
            let wrapper = try CrabrixProjectDocument(project: project).packageWrapper()
            try wrapper.write(to: projectURL, options: .atomic, originalContentsURL: nil)
            try fileManager.zipItem(at: projectURL, to: archiveURL, shouldKeepParent: true)
            return archiveURL
        } catch {
            try? fileManager.removeItem(at: workURL)
            throw error
        }
    }

    static func load(from archiveURL: URL) throws -> CrabrixProject {
        let accessGranted = archiveURL.startAccessingSecurityScopedResource()
        defer {
            if accessGranted { archiveURL.stopAccessingSecurityScopedResource() }
        }

        try validate(archiveURL)
        let fileManager = FileManager.default
        let workURL = fileManager.temporaryDirectory
            .appending(path: "CrabrixArchiveImport-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: workURL) }
        try fileManager.createDirectory(at: workURL, withIntermediateDirectories: true)
        try fileManager.unzipItem(at: archiveURL, to: workURL)
        return try LocalProjectLoader.load(from: workURL, provenance: .files())
    }

    static func removeTemporaryArchive(at archiveURL: URL) {
        let temporaryRoot = FileManager.default.temporaryDirectory.standardizedFileURL.path
        let parent = archiveURL.deletingLastPathComponent().standardizedFileURL
        guard parent.path.hasPrefix(temporaryRoot),
              parent.lastPathComponent.hasPrefix("CrabrixShare-")
        else { return }
        try? FileManager.default.removeItem(at: parent)
    }

    private static func validate(_ url: URL) throws {
        let archive = try Archive(url: url, accessMode: .read)
        var totalBytes: UInt64 = 0
        var entryCount = 0
        for entry in archive {
            entryCount += 1
            guard entryCount <= maximumArchiveEntries else { throw ArchiveError.archiveTooLarge }
            totalBytes += UInt64(entry.uncompressedSize)
            guard totalBytes <= maximumArchiveBytes else { throw ArchiveError.archiveTooLarge }

            let path = entry.path.replacingOccurrences(of: "\\", with: "/")
            let components = path.split(separator: "/", omittingEmptySubsequences: false)
            guard !path.hasPrefix("/"),
                  !components.contains(".."),
                  entry.type != .symlink
            else {
                throw ArchiveError.unsafePath(entry.path)
            }
        }
    }

    private static func safeFilename(_ rawValue: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let value = rawValue.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        let normalized = String(value).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return normalized.isEmpty ? "Crabrix-Project" : normalized
    }
}
