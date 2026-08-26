import SwiftUI
import UniformTypeIdentifiers

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
        let manifest = files["Cargo.toml"].flatMap(CargoManifest.parse)
        let entry = ["src/main.rs", "main.rs", "src/lib.rs", "lib.rs"]
            .first(where: { files[$0] != nil })
            ?? files.keys.sorted().first(where: { $0.hasSuffix(".rs") })
            ?? "main.rs"
        project = CrabrixProject(
            name: manifest?.name ?? "Crabrix Project",
            files: files,
            entryFile: entry,
            provenance: nil
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
        if let provenance = project.provenance {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try Self.add(
                data: encoder.encode(provenance),
                at: ".crabrix/project.json",
                to: root
            )
        }
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
}
