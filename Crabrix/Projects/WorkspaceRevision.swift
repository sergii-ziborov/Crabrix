import CryptoKit
import Foundation

/// Immutable identity for an asynchronous operation started from a workspace.
///
/// `generation` prevents ABA races (edit, then restore the same bytes), while
/// the hashes independently prove which source tree and Cargo inputs were used.
struct WorkspaceRevision: Hashable, Sendable {
    let projectID: UUID
    let generation: UInt64
    let sourceTreeHash: String
    let manifestHash: String?
    let lockfileHash: String?
    let toolchainID: String

    static func capture(
        project: CrabrixProject,
        generation: UInt64,
        toolchainID: String
    ) -> WorkspaceRevision {
        WorkspaceRevision(
            projectID: project.id,
            generation: generation,
            sourceTreeHash: sourceTreeHash(project.files),
            manifestHash: project.files["Cargo.toml"].map(contentHash),
            lockfileHash: project.files["Cargo.lock"].map(contentHash),
            toolchainID: toolchainID
        )
    }

    private static func sourceTreeHash(_ files: [String: String]) -> String {
        var hasher = SHA256()
        for path in files.keys.sorted() {
            absorb(path, into: &hasher)
            absorb(files[path] ?? "", into: &hasher)
        }
        return hex(hasher.finalize())
    }

    static func contentHash(_ content: String) -> String {
        hex(SHA256.hash(data: Data(content.utf8)))
    }

    /// Length-prefixing makes the canonical stream unambiguous even when file
    /// names or source text contain separators or embedded zero bytes.
    private static func absorb(_ value: String, into hasher: inout SHA256) {
        let data = Data(value.utf8)
        var count = UInt64(data.count).bigEndian
        withUnsafeBytes(of: &count) { hasher.update(bufferPointer: $0) }
        hasher.update(data: data)
    }

    private static func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
