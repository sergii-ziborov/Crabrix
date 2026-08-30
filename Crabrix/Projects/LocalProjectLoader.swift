import Foundation

enum LocalProjectLoader {
    enum ProjectError: LocalizedError, Equatable {
        case notDirectory
        case noReadableSource
        case tooManyFiles(Int)
        case fileTooLarge(String)
        case projectTooLarge

        var errorDescription: String? {
            switch self {
            case .notDirectory:
                "Choose a Cargo project folder or a saved Crabrix project."
            case .noReadableSource:
                "No readable Rust or Cargo files were found in this project."
            case let .tooManyFiles(limit):
                "This snapshot contains more than \(limit) readable files."
            case let .fileTooLarge(path):
                "\(path) is too large to open safely."
            case .projectTooLarge:
                "The readable project snapshot exceeds the local import limit."
            }
        }
    }

    static let maximumFileCount = 512
    static let maximumFileBytes = 1_500_000
    static let maximumProjectBytes = 16_000_000

    private static let ignoredDirectories: Set<String> = [
        ".git", ".build", ".swiftpm", "DerivedData", "node_modules", "target",
    ]
    private static let readableExtensions: Set<String> = [
        "json", "lock", "md", "rs", "toml", "txt", "yaml", "yml",
    ]
    private static let readableNames: Set<String> = [
        ".gitignore", ".rustfmt.toml", "LICENSE", "Makefile",
    ]

    static func load(from projectURL: URL, provenance: CrabrixProject.Provenance? = nil) throws -> CrabrixProject {
        let accessGranted = projectURL.startAccessingSecurityScopedResource()
        defer {
            if accessGranted { projectURL.stopAccessingSecurityScopedResource() }
        }

        let values = try projectURL.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else { throw ProjectError.notDirectory }

        let rootURL = try discoverCargoRoot(in: projectURL)
        let files = try readFiles(in: rootURL)
        guard !files.isEmpty, files.keys.contains(where: { $0.hasSuffix(".rs") || $0 == "Cargo.toml" }) else {
            throw ProjectError.noReadableSource
        }

        // ZIP imports commonly contain one parent directory. Metadata belongs
        // to the discovered Cargo root, not necessarily to the picker URL.
        let storedMetadata = try readStoredMetadata(in: rootURL)
        let manifest = files["Cargo.toml"].flatMap(CargoManifest.parse)
        let name = storedMetadata.flatMap { $0.name.isEmpty ? nil : $0.name }
            ?? manifest?.name
            ?? provenance?.repository
            ?? rootURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "-main", with: "")
            .replacingOccurrences(of: "-master", with: "")
        let entryFile = storedMetadata.flatMap { files[$0.entryFile] == nil ? nil : $0.entryFile }
            ?? preferredEntryFile(in: files)
        let storedProvenance = storedMetadata?.provenance ?? provenance

        return CrabrixProject(
            id: storedMetadata?.projectID ?? UUID(),
            name: name.isEmpty ? "imported-project" : name,
            files: files,
            entryFile: entryFile,
            provenance: storedProvenance,
            projectDescription: storedMetadata?.projectDescription ?? "",
            tags: storedMetadata?.tags ?? [],
            folder: storedMetadata?.folder,
            kind: storedMetadata?.kind ?? .general,
            isFavorite: storedMetadata?.isFavorite ?? false
        )
    }

    private static func discoverCargoRoot(in importedURL: URL) throws -> URL {
        if FileManager.default.fileExists(atPath: importedURL.appending(path: "Cargo.toml").path) {
            return importedURL
        }

        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: importedURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return importedURL
        }

        var candidates: [URL] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isDirectory == true, ignoredDirectories.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            if values.isSymbolicLink == true {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            if values.isRegularFile == true, url.lastPathComponent == "Cargo.toml" {
                candidates.append(url.deletingLastPathComponent())
            }
        }

        return candidates.min {
            $0.pathComponents.count < $1.pathComponents.count
        } ?? importedURL
    }

    private static func readFiles(in rootURL: URL) throws -> [String: String] {
        let keys: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw ProjectError.noReadableSource
        }

        var files: [String: String] = [:]
        var totalBytes = 0
        let rootPath = rootURL.standardizedFileURL.path

        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isDirectory == true, ignoredDirectories.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            if values.isSymbolicLink == true {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            guard values.isRegularFile == true, isReadableProjectFile(url) else { continue }

            let fileSize = values.fileSize ?? 0
            let relativePath = String(url.standardizedFileURL.path.dropFirst(rootPath.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard fileSize <= maximumFileBytes else { throw ProjectError.fileTooLarge(relativePath) }
            guard files.count < maximumFileCount else { throw ProjectError.tooManyFiles(maximumFileCount) }
            totalBytes += fileSize
            guard totalBytes <= maximumProjectBytes else { throw ProjectError.projectTooLarge }

            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard let source = String(data: data, encoding: .utf8) else { continue }
            files[relativePath] = source
        }
        return files
    }

    private static func isReadableProjectFile(_ url: URL) -> Bool {
        readableNames.contains(url.lastPathComponent)
            || readableExtensions.contains(url.pathExtension.lowercased())
    }

    private static func preferredEntryFile(in files: [String: String]) -> String {
        for candidate in ["src/main.rs", "main.rs", "src/lib.rs", "lib.rs"] where files[candidate] != nil {
            return candidate
        }
        let rustFiles = files.keys.filter { $0.hasSuffix(".rs") }
        for suffix in ["/src/main.rs", "/src/lib.rs", "/main.rs", "/lib.rs"] {
            if let candidate = rustFiles
                .filter({ $0.hasSuffix(suffix) })
                .min(by: {
                    $0.split(separator: "/").count < $1.split(separator: "/").count
                }) {
                return candidate
            }
        }
        return rustFiles
            .filter { !$0.hasSuffix("/build.rs") && $0 != "build.rs" }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .first ?? rustFiles.sorted().first ?? "main.rs"
    }

    private static func readStoredMetadata(
        in rootURL: URL
    ) throws -> CrabrixProject.PackageMetadata? {
        let metadataURL = rootURL.appending(path: ".crabrix/project.json")
        guard FileManager.default.fileExists(atPath: metadataURL.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: metadataURL)
        if let metadata = try? decoder.decode(CrabrixProject.PackageMetadata.self, from: data) {
            return metadata
        }
        // Version 0 saved provenance as the whole metadata document.
        let provenance = try decoder.decode(CrabrixProject.Provenance.self, from: data)
        return CrabrixProject.PackageMetadata(
            projectID: UUID(),
            name: "",
            entryFile: "",
            provenance: provenance
        )
    }
}
