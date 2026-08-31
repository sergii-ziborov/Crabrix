import Foundation

/// Reads the source of a crate that has been downloaded and extracted.
///
/// App Store guideline 2.5.2 allows an app that teaches or develops code to
/// download code, on the condition that the source is fully viewable by the
/// user. Crabrix downloads crates from the registry, so every textual source
/// file it extracts has to be viewable and vendorable from inside the app.
enum CrateSourceBrowser {
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

        var sizeLabel: String {
            ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
        }
    }

    /// Files large enough that showing them would only stall the view. The
    /// limit is generous: the largest file in a typical crate is far below it.
    static let maximumViewableBytes = 2 * 1_024 * 1_024

    /// Every file in an extracted crate, sorted so `src` comes first.
    static func entries(name: String, version: SemanticVersion) -> [Entry] {
        guard let root = CrateStorageLayout.sourceDirectory(name: name, version: version),
              FileManager.default.fileExists(atPath: root.path)
        else { return [] }

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
            let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
            found.append(Entry(path: relative, byteCount: values?.fileSize ?? 0))
        }

        return found.sorted { lhs, rhs in
            // src/ first, then everything else alphabetically: that is the
            // order someone reading a crate actually wants.
            let leftIsSource = lhs.path.hasPrefix("src/")
            let rightIsSource = rhs.path.hasPrefix("src/")
            if leftIsSource != rightIsSource { return leftIsSource }
            return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
        }
    }

    /// The text of one file, or nil when it is binary or too large to show.
    static func contents(
        name: String,
        version: SemanticVersion,
        path: String
    ) -> String? {
        guard let root = CrateStorageLayout.sourceDirectory(name: name, version: version) else { return nil }
        // The path comes from `entries`, but it is still joined defensively:
        // a traversal here would read outside the crate directory.
        let url = root.appending(path: path)
        guard url.path.hasPrefix(root.path + "/") else { return nil }

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

    /// Textual source copied into a project by Vendor & Edit. Binary assets are
    /// deliberately not duplicated; the compiler overlays these editable files
    /// onto a temporary copy of the immutable verified registry tree.
    static func vendorableFiles(
        name: String,
        version: SemanticVersion
    ) throws -> [String: String] {
        var candidates: [(entry: Entry, text: String)] = []
        for entry in entries(name: name, version: version) {
            guard let text = contents(name: name, version: version, path: entry.path) else {
                continue // binary asset, retained by the private registry overlay
            }
            guard entry.byteCount <= LocalProjectLoader.maximumFileBytes else {
                throw VendorError.sourceTooLarge(entry.path)
            }
            candidates.append((entry, text))
        }
        guard candidates.count <= LocalProjectLoader.maximumFileCount else {
            throw VendorError.tooManyEditableFiles
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
}
