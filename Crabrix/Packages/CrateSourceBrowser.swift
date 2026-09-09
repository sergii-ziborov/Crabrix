import Foundation

/// Reads the source of a crate that has been downloaded and extracted.
///
/// App Store guideline 2.5.2 allows an app that teaches or develops code to
/// download code, on the condition that the source is fully viewable by the
/// user. Crabrix downloads crates from the registry, so every textual source
/// file it extracts has to be viewable and vendorable from inside the app.
enum CrateSourceBrowser {
    enum SourceAccessIssue: LocalizedError, Equatable, Sendable {
        case sourceTooLarge(path: String, byteCount: Int, limit: Int)
        case sourceIsNotUTF8(String)
        case tooManySourceFiles(count: Int, limit: Int)
        case sourceTreeTooLarge(byteCount: Int, limit: Int)

        var errorDescription: String? {
            switch self {
            case let .sourceTooLarge(path, byteCount, limit):
                "\(path) is \(Self.size(byteCount)); Crabrix's complete view/edit limit is \(Self.size(limit))."
            case let .sourceIsNotUTF8(path):
                "\(path) is programming source but is not valid UTF-8, so Crabrix cannot show and edit it completely."
            case let .tooManySourceFiles(count, limit):
                "The package contains \(count) editable text files; Crabrix can completely edit at most \(limit)."
            case let .sourceTreeTooLarge(byteCount, limit):
                "The package's editable text is \(Self.size(byteCount)); Crabrix can completely edit at most \(Self.size(limit))."
            }
        }

        private static func size(_ byteCount: Int) -> String {
            ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
        }
    }

    enum VendorError: LocalizedError {
        case missingManifest
        case sourceTooLarge(String)
        case tooManyEditableFiles
        case editableTreeTooLarge

        var errorDescription: String? {
            switch self {
            case .missingManifest:
                "The verified package has no editable Cargo.toml."
            case let .sourceTooLarge(path):
                "\(path) is too large to vendor safely."
            case .tooManyEditableFiles:
                "This package has more editable files than one Crabrix project supports."
            case .editableTreeTooLarge:
                "This package's editable source exceeds the project size limit."
            }
        }
    }

    /// One file inside an extracted crate.
    struct Entry: Identifiable, Hashable, Sendable {
        /// Path relative to the crate root, e.g. `src/lib.rs`.
        let path: String
        let byteCount: Int

        var id: String { path }
        var name: String { (path as NSString).lastPathComponent }
        var isRust: Bool { path.hasSuffix(".rs") }

        /// Code/configuration that participates in the programming environment
        /// rather than an opaque binary fixture. Supported registry packages
        /// must be able to expose every such file through View and Vendor.
        var isProgrammingSource: Bool {
            let lowercasedPath = path.lowercased()
            return isRust
                || lowercasedPath.hasSuffix(".toml")
                || lowercasedPath.hasSuffix("cargo.lock")
                || lowercasedPath.hasSuffix("/.cargo/config")
                || lowercasedPath == ".cargo/config"
        }

        var sizeLabel: String {
            ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
        }
    }

    /// Files large enough that showing them would only stall the view. The
    /// limit is generous: the largest file in a typical crate is far below it.
    static let maximumViewableBytes = 2 * 1_024 * 1_024

    /// The editor/project model is intentionally more conservative than the
    /// read-only viewer. A package may build only when every programming-source
    /// file fits this complete editable representation.
    static let maximumEditableSourceBytes = LocalProjectLoader.maximumFileBytes

    /// Every file in an extracted crate, sorted so `src` comes first.
    static func entries(name: String, version: SemanticVersion) -> [Entry] {
        guard let root = CrateStorageLayout.sourceDirectory(name: name, version: version),
              FileManager.default.fileExists(atPath: root.path)
        else { return [] }
        return entries(in: root)
    }

    /// The text of one file, or nil when it is binary or too large to show.
    static func contents(
        name: String,
        version: SemanticVersion,
        path: String
    ) -> String? {
        guard let root = CrateStorageLayout.sourceDirectory(name: name, version: version) else { return nil }
        return contents(in: root, path: path)
    }

    static func contents(in root: URL, path: String) -> String? {
        // The path comes from `entries`, but it is still joined defensively:
        // a traversal here would read outside the crate directory.
        guard !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else { return nil }
        let root = root.resolvingSymlinksInPath().standardizedFileURL
        let url = root.appending(path: path).resolvingSymlinksInPath().standardizedFileURL
        guard relativePath(of: url, in: root) != nil else { return nil }

        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              (values.fileSize ?? 0) <= maximumViewableBytes,
              let data = try? Data(contentsOf: url)
        else { return nil }

        return String(data: data, encoding: .utf8)
    }

    /// A short description of what was downloaded, for the package row.
    static func summary(name: String, version: SemanticVersion) -> String? {
        let files = entries(name: name, version: version)
        guard !files.isEmpty else { return nil }
        let rust = files.filter(\.isRust).count
        let bytes = files.reduce(0) { $0 + $1.byteCount }
        let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        return "\(files.count) files · \(rust) Rust · \(size)"
    }

    /// Returns why a downloaded package cannot satisfy Crabrix's complete
    /// source View/Edit contract. The build path uses the same audit as Vendor
    /// & Edit, so a crate is never compiled first and revealed as uneditable
    /// only afterwards.
    static func sourceAccessIssue(
        name: String,
        version: SemanticVersion
    ) -> SourceAccessIssue? {
        guard let root = CrateStorageLayout.sourceDirectory(name: name, version: version) else {
            return nil
        }
        return sourceAccessIssue(in: root)
    }

    static func sourceAccessIssue(in root: URL) -> SourceAccessIssue? {
        let entries = entries(in: root)
        var requiredPaths = Set(entries.filter(\.isProgrammingSource).map(\.path))
        let manifestURL = root.appending(path: "Cargo.toml")
        // Do not map an oversized manifest merely to discover that the normal
        // source audit must reject it. The extracted archive is bounded, but
        // the editor's tighter per-file contract is the relevant limit here.
        if let manifestEntry = entries.first(where: { $0.path == "Cargo.toml" }),
           manifestEntry.byteCount <= maximumEditableSourceBytes,
           let data = try? Data(contentsOf: manifestURL, options: [.mappedIfSafe]),
           let source = String(data: data, encoding: .utf8),
           let manifest = try? CratePackageManifest.parse(source) {
            if let libraryPath = manifest.library.path {
                requiredPaths.insert(libraryPath.replacingOccurrences(of: "\\", with: "/"))
            } else {
                requiredPaths.insert("src/lib.rs")
            }
            if let buildScriptPath = manifest.buildScriptPath {
                requiredPaths.insert(buildScriptPath.replacingOccurrences(of: "\\", with: "/"))
            } else if !manifest.buildScriptDisabled {
                requiredPaths.insert("build.rs")
            }
        }
        // Rust can load source using include! or #[path] with any extension,
        // including paths produced by macros. Auditing only .rs files or parsing
        // literal includes cannot prove completeness. Treat every UTF-8 file as
        // potentially executable source; only non-source binary assets may stay
        // outside the editable overlay. This deliberately also bounds docs.
        var sourceEntries: [Entry] = []
        for entry in entries {
            let url = root.appending(path: entry.path)
            guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
                return .sourceIsNotUTF8(entry.path)
            }
            if String(data: data, encoding: .utf8) != nil {
                sourceEntries.append(entry)
            } else if requiredPaths.contains(entry.path) {
                return .sourceIsNotUTF8(entry.path)
            }
        }
        if sourceEntries.count > LocalProjectLoader.maximumFileCount {
            return .tooManySourceFiles(
                count: sourceEntries.count,
                limit: LocalProjectLoader.maximumFileCount
            )
        }

        var totalBytes = 0
        for entry in sourceEntries {
            guard entry.byteCount <= maximumEditableSourceBytes else {
                return .sourceTooLarge(
                    path: entry.path,
                    byteCount: entry.byteCount,
                    limit: maximumEditableSourceBytes
                )
            }
            totalBytes += entry.byteCount
            guard totalBytes <= LocalProjectLoader.maximumProjectBytes else {
                return .sourceTreeTooLarge(
                    byteCount: totalBytes,
                    limit: LocalProjectLoader.maximumProjectBytes
                )
            }
            let url = root.appending(path: entry.path)
            guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
                  String(data: data, encoding: .utf8) != nil
            else {
                return .sourceIsNotUTF8(entry.path)
            }
        }
        return nil
    }

    /// Textual source copied into a project by Vendor & Edit. Binary assets are
    /// deliberately not duplicated; the compiler overlays these editable files
    /// onto a temporary copy of the immutable verified registry tree.
    static func vendorableFiles(
        name: String,
        version: SemanticVersion
    ) throws -> [String: String] {
        if let issue = sourceAccessIssue(name: name, version: version) {
            throw issue
        }

        var candidates: [(entry: Entry, text: String)] = []
        let allEntries = entries(name: name, version: version)
        // The audit bounds ALL UTF-8 files, including nonstandard include!
        // inputs. Never silently omit a text file from the editable overlay.
        for entry in allEntries {
            guard let text = contents(name: name, version: version, path: entry.path) else {
                continue // non-UTF-8 binary asset, retained by the registry overlay
            }
            if entry.byteCount > LocalProjectLoader.maximumFileBytes {
                throw VendorError.sourceTooLarge(entry.path)
            }
            if candidates.count >= LocalProjectLoader.maximumFileCount {
                throw VendorError.tooManyEditableFiles
            }
            let nextTotal = candidates.reduce(0) { $0 + $1.entry.byteCount } + entry.byteCount
            if nextTotal > LocalProjectLoader.maximumProjectBytes {
                throw VendorError.editableTreeTooLarge
            }
            candidates.append((entry, text))
        }

        var result: [String: String] = [:]
        var totalBytes = 0
        for candidate in candidates {
            let entry = candidate.entry
            totalBytes += entry.byteCount
            guard totalBytes <= LocalProjectLoader.maximumProjectBytes else {
                throw VendorError.editableTreeTooLarge
            }
            result[entry.path] = candidate.text
        }
        guard result["Cargo.toml"] != nil else { throw VendorError.missingManifest }
        return result
    }

    static func entries(in root: URL) -> [Entry] {
        let root = root.resolvingSymlinksInPath().standardizedFileURL
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: []
        ) else { return [] }

        var found: [Entry] = []
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true,
                  url.lastPathComponent != ".crabrix-complete.json"
            else { continue }
            guard let relative = relativePath(of: url, in: root) else { continue }
            found.append(Entry(path: relative, byteCount: values?.fileSize ?? 0))
        }
        return found.sorted { lhs, rhs in
            let leftIsSource = lhs.path.hasPrefix("src/")
            let rightIsSource = rhs.path.hasPrefix("src/")
            if leftIsSource != rightIsSource { return leftIsSource }
            return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
        }
    }

    static func relativePath(of file: URL, in root: URL) -> String? {
        // On devices the cache URL may start with /var while enumeration
        // returns /private/var. Normalize both sides before removing a prefix;
        // replacing a substring used to produce /private/.cargo_vcs_info.json.
        let prefix = root.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        let path = file.resolvingSymlinksInPath().standardizedFileURL.path
        guard path.hasPrefix(prefix) else { return nil }
        return String(path.dropFirst(prefix.count))
    }
}
