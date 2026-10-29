import Foundation

struct PlaygroundDocument: Codable, Equatable, Sendable {
    struct Origin: Codable, Equatable, Sendable { let url: String; var commit: String? }
    var schemaVersion = 1
    var name: String
    var entryFile: String
    var files: [String: String]
    var edition = "2024"
    var origin: Origin?

    /// The native project format carries edition in Cargo.toml. Preserve a
    /// manifest-free 2021 snippet when saving a durable device copy.
    var nativeFiles: [String: String] {
        guard edition == "2021", files["Cargo.toml"] == nil else { return files }
        var result = files
        let path = entryFile.replacingOccurrences(of: "\"", with: "\\\"")
        result["Cargo.toml"] = """
        [package]
        name = "playground"
        version = "0.1.0"
        edition = "2021"

        [[bin]]
        name = "playground"
        path = "\(path)"

        """
        return result
    }

    func validated() throws -> Self {
        guard schemaVersion == 1, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.utf16.count <= 80, !name.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
              ["2021", "2024"].contains(edition), (1...16).contains(files.count), files[entryFile] != nil, entryFile.hasSuffix(".rs") else { throw PlaygroundFailure("Invalid text-only Playground project.") }
        let forbidden: Set<String> = ["node_modules", "target", ".git", ".github", ".cargo", "vendor", "__proto__", "constructor", "prototype", ".", "..", ""]
        var total = 0
        for (path, text) in files {
            let suffix = URL(fileURLWithPath: path).pathExtension.lowercased()
            guard path.utf16.count <= 180, !path.hasPrefix("/"), !path.contains("\\"), !path.contains(":"),
                  !path.components(separatedBy: "/").contains(where: { forbidden.contains($0.lowercased()) }),
                  !path.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
                  ["rs", "toml", "lock", "md", "txt"].contains(suffix) || ["LICENSE", "NOTICE"].contains(path.uppercased()),
                  !text.contains("\0"), text.utf8.count <= 65536 else { throw PlaygroundFailure("Playgrounds accept source text only, at most 64 KiB per file. Packages, generated files and images are excluded.") }
            total += text.utf8.count
        }
        guard total <= 131072 else { throw PlaygroundFailure("The Playground source exceeds 128 KiB. Export a smaller source project.") }
        if let origin {
            guard let url = URL(string: origin.url), url.scheme == "https", ["github.com", "gist.github.com", "play.rust-lang.org"].contains(url.host), url.user == nil, url.password == nil else { throw PlaygroundFailure("Invalid project origin.") }
        }
        return self
    }
}

/// Private local configuration/prepared sources are outside the shared tree.
/// A remote root-file deletion must not delete those local files, and retaining
/// them must not turn them into room content or an execution permission.
enum PlaygroundLocalFiles {
    private static let privateRoots: Set<String> = ["target", "node_modules", ".git", ".github", ".cargo", "vendor"]

    private static func isPrivate(_ path: String) -> Bool {
        privateRoots.contains((path.components(separatedBy: "/").first ?? "").lowercased())
    }

    static func sharedFiles(in files: [String: String]) -> [String: String] {
        files.filter { !isPrivate($0.key) }
    }

    static func merging(_ document: PlaygroundDocument, into local: [String: String]) throws -> [String: String] {
        var result = local.filter { isPrivate($0.key) }
        for (path, text) in try document.validated().nativeFiles { result[path] = text }
        // Shared and local budgets differ. Refuse the whole incoming merge
        // before changing editor/storage rather than dropping private files.
        try ProjectFilePolicy.validate(result)
        return result
    }
}
struct PlaygroundFailure: LocalizedError, Sendable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
struct PlaygroundRemoteSelection: Codable, Equatable, Sendable, Identifiable {
    let clientID: UInt64
    let name: String
    let color: String
    let file: String
    let anchor: Int
    let head: Int
    var id: UInt64 { clientID }
    var range: NSRange { NSRange(location: min(anchor, head), length: abs(anchor - head)) }
}
