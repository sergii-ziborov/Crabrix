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
