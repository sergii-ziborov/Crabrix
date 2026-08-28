import Foundation

/// Reads the source of a crate that has been downloaded and extracted.
///
/// App Store guideline 2.5.2 allows an app that teaches or develops code to
/// download code, on the condition that the source is fully viewable by the
/// user. Crabrix downloads crates from the registry, so every file it extracts
/// has to be readable from inside the app — this is what makes that true.
enum CrateSourceBrowser {
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
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var found: [Entry] = []
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
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
}
