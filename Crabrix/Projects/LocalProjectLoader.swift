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
                "No readable Rust, Cargo, HTML or package.json source was found in this project."
            case let .tooManyFiles(limit):
                "This snapshot contains more than \(limit) readable files."
            case let .fileTooLarge(path):
                "\(path) is too large to open safely."
            case .projectTooLarge:
                "The readable project snapshot exceeds the local import limit."
            }
        }
    }

    // Tokio's published source includes more than 512 small text files.
    // Keep the byte budgets independent so complete source remains editable
    // without allowing a large package to consume unbounded memory.
    static let maximumFileCount = 2_048
    // Match CrateSourceBrowser's 2 MiB viewing cap. Published crates can
    // contain a large text fixture even when their library source is small;
    // keep that file viewable and editable under the existing 16 MB tree cap.
    static let maximumFileBytes = 2 * 1_024 * 1_024
    static let maximumProjectBytes = 16_000_000

    private static let ignoredDirectories: Set<String> = [
        ".git", ".build", ".swiftpm", "DerivedData", "node_modules", "target",
    ]
    private static let readableExtensions: Set<String> = [
        "json", "lock", "md", "rs", "toml", "txt", "yaml", "yml",
        "html", "htm", "css", "js", "mjs", "cjs", "jsx", "ts", "tsx", "svg",
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
        guard !files.isEmpty, files.keys.contains(where: {
            $0.hasSuffix(".rs") || $0 == "Cargo.toml" || ($0 as NSString).lastPathComponent == "package.json" || SourceLanguage(filePath: $0) == .html
        }) else {
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
        if ["Cargo.toml", "package.json", "index.html"].contains(where: { FileManager.default.fileExists(atPath: importedURL.appending(path: $0).path) }) {
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
            if values.isRegularFile == true, ["Cargo.toml", "package.json", "index.html"].contains(url.lastPathComponent) {
                candidates.append(url.deletingLastPathComponent())
            }
        }

        return candidates.sorted {
            $0.pathComponents.count == $1.pathComponents.count ? $0.path < $1.path : $0.pathComponents.count < $1.pathComponents.count
        }.first ?? importedURL
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
            let isPreparedSource = url.lastPathComponent == "node_modules"
                && hasPreparedBrowserSources(in: url.deletingLastPathComponent(), root: rootURL)
            if values.isDirectory == true, ignoredDirectories.contains(url.lastPathComponent), !isPreparedSource {
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

    private static func hasPreparedBrowserSources(in directory: URL, root: URL) -> Bool {
        var current = directory.standardizedFileURL
        let rootPath = root.standardizedFileURL.path
        while current.path == rootPath || current.path.hasPrefix(rootPath + "/") {
            let lock = current.appending(path: "crabrix-web.lock.json")
            if let size = try? lock.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= maximumFileBytes,
               let data = try? Data(contentsOf: lock),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               object["schemaVersion"] as? Int == 1 { return true }
            if current.path == rootPath { break }
            current.deleteLastPathComponent()
        }
        return false
    }

    private static func isReadableProjectFile(_ url: URL) -> Bool {
        readableNames.contains(url.lastPathComponent)
            || url.lastPathComponent.uppercased().hasPrefix("LICENSE")
            || url.lastPathComponent.uppercased().hasPrefix("LICENCE")
            || ["NOTICE", "COPYING"].contains(url.lastPathComponent.uppercased())
            || readableExtensions.contains(url.pathExtension.lowercased())
    }

    private static func preferredEntryFile(in files: [String: String]) -> String {
        for candidate in ["src/main.rs", "main.rs", "src/lib.rs", "lib.rs"] where files[candidate] != nil {
            return candidate
        }
        let rustFiles = files.keys.filter { $0.hasSuffix(".rs") }
        if rustFiles.isEmpty {
            if files["index.html"] != nil { return "index.html" }
            if let html = files.keys.filter({ !$0.contains("node_modules/") && SourceLanguage(filePath: $0) == .html }).sorted().first { return html }
            if files["package.json"] != nil { return "package.json" }
        }
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
