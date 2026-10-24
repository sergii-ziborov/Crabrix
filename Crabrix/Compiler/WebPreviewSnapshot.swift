import Foundation
import CryptoKit

/// Immutable, bounded preview input. The web process receives only these assets,
/// never a file URL or access to the project's directory or app container.
struct WebPreviewSnapshot: Sendable, Equatable, Identifiable {
    static let maximumBytes = 8 * 1024 * 1024
    static let maximumAssetBytes = 2 * 1024 * 1024
    static let maximumAssets = 256
    let entryPath: String
    let assets: [String: Data]
    let id: String

    init?(files: [String: Data], preferredEntry: String? = nil) {
        let usable = files.filter { Self.isSafePath($0.key) && Self.mimeType(for: $0.key) != nil }
        guard !usable.isEmpty, usable.count <= Self.maximumAssets,
              usable.values.allSatisfy({ $0.count <= Self.maximumAssetBytes }),
              usable.values.reduce(0, { $0 + $1.count }) <= Self.maximumBytes
        else { return nil }
        let html = usable.keys.filter { SourceLanguage(filePath: $0) == .html }.sorted {
            let a = $0.split(separator: "/").count, b = $1.split(separator: "/").count
            return a == b ? $0 < $1 : a < b
        }
        let entry = preferredEntry.flatMap { usable[$0] != nil && SourceLanguage(filePath: $0) == .html ? $0 : nil }
            ?? (usable["index.html"] != nil ? "index.html" : html.first)
        guard let entry else { return nil }
        entryPath = entry
        assets = usable
        var hash = SHA256()
        hash.update(data: Data(entry.utf8))
        for path in usable.keys.sorted() {
            hash.update(data: Data([0]))
            hash.update(data: Data(path.utf8))
            hash.update(data: Data([0]))
            hash.update(data: usable[path]!)
        }
        id = hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    init?(textFiles: [String: String], preferredEntry: String? = nil) {
        self.init(files: textFiles.filter { Self.mimeType(for: $0.key) != nil }.mapValues { Data($0.utf8) }, preferredEntry: preferredEntry)
    }

    static func isSafePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/")
            && !path.contains("\\") && !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) && !path.contains("%")
            && path.split(separator: "/", omittingEmptySubsequences: false)
                .allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    static func mimeType(for path: String) -> String? {
        switch (path as NSString).pathExtension.lowercased() {
        case "html", "htm": "text/html"
        case "css": "text/css"
        case "js", "mjs", "cjs": "text/javascript"
        case "json": "application/json"
        case "svg": "image/svg+xml"
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "gif": "image/gif"
        case "webp": "image/webp"
        case "txt": "text/plain"
        case "woff": "font/woff"
        case "woff2": "font/woff2"
        default: nil
        }
    }

    /// Generated output is copied before the compiler job's temporary directory
    /// is removed. Source inputs remain separate, and generated paths win.
    static func generated(in directory: URL) -> [String: Data] {
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        else { return [:] }
        var result: [String: Data] = [:]
        var total = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  let bytes = values.fileSize, bytes <= maximumAssetBytes
            else { continue }
            let path = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard path.hasPrefix(root.path + "/") else { continue }
            let relative = String(path.dropFirst(root.path.count + 1))
            guard isSafePath(relative), mimeType(for: relative) != nil else { continue }
            guard result.count < maximumAssets, total + bytes <= maximumBytes else { return [:] }
            guard let data = try? Data(contentsOf: url) else { continue }
            result[relative] = data
            total += data.count
        }
        return result
    }
}
