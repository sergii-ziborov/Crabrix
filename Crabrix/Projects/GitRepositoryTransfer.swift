import Foundation
import CryptoKit
import ZIPFoundation
import CrabrixGit

enum GitRepositoryTransfer {
    private static let manifestName = "transfer.json"
    private static let maximumMetadata = 16 * 1024 * 1024
    private static let maximumArchive = 224 * 1024 * 1024

    struct Record: Codable, Sendable { let bytes: Int; let sha256: String; let executable: Bool }
    struct Envelope: Codable, Sendable {
        let version: Int
        let engine: String
        let project: CrabrixProject.PackageMetadata
        let origin: String?
        let files: [String: Record]
    }
    struct Prepared: Sendable { let directory: URL; let envelope: Envelope }

    static func create(copy: GitPortableCopy, project: CrabrixProject) async throws -> URL {
        let progress = Progress(totalUnitCount: 0)
        let job = Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let share = fm.temporaryDirectory.appending(path: "CrabrixGitShare-" + UUID().uuidString)
            try fm.createDirectory(at: share, withIntermediateDirectories: true)
            do {
                var sourceProject = project; sourceProject.files = copy.snapshot.files
                if sourceProject.files[sourceProject.entryFile] == nil {
                    sourceProject.entryFile = LocalProjectLoader.preferredEntryFile(in: sourceProject.files)
                }
                var records: [String: Record] = [:]
                var enumerationFailure: Error?
                guard let enumerator = fm.enumerator(at: copy.directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey], errorHandler: { _, error in enumerationFailure = error; return false }) else { throw failure("Cannot enumerate the repository export.") }
                while let file = enumerator.nextObject() as? URL {
                    try Task.checkCancellation()
                    let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey])
                    guard values.isSymbolicLink != true else { throw failure("Repository export contains a filesystem link.") }
                    if values.isDirectory == true { continue }
                    guard values.isRegularFile == true else { throw failure("Repository export contains a non-regular file.") }
                    let base = copy.directory.standardizedFileURL.pathComponents
                    let components = file.standardizedFileURL.pathComponents
                    guard Array(components.prefix(base.count)) == base else { throw failure("Repository export escaped its root.") }
                    let path = components.dropFirst(base.count).joined(separator: "/")
                    try validatePath(path)
                    let digest = try hashFile(file)
                    let mode = try fm.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int ?? 0
                    records[path] = Record(bytes: digest.bytes, sha256: digest.hash, executable: mode & 0o111 != 0)
                }
                if let enumerationFailure { throw enumerationFailure }
                let envelope = Envelope(version: 1, engine: "libgit2-sha1", project: .init(project: sourceProject), origin: copy.origin, files: records)
                let data = try JSONEncoder().encode(envelope)
                guard data.count <= maximumMetadata else { throw failure("The repository transfer inventory exceeds 16 MiB.") }
                let metadata = share.appending(path: manifestName)
                try data.write(to: metadata, options: .atomic)
                let name = project.name.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
                let destination = share.appending(path: String((name.isEmpty ? "CrabrixRepository" : name).prefix(80)) + ".crabrixrepo")
                let archive = try Archive(url: destination, accessMode: .create)
                for path in records.keys.sorted() {
                    try Task.checkCancellation()
                    try archive.addEntry(with: path, relativeTo: copy.directory, compressionMethod: .deflate, progress: progress)
                }
                try archive.addEntry(with: manifestName, fileURL: metadata, compressionMethod: .deflate, progress: progress)
                guard (try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= maximumArchive else { throw failure("The compressed repository transfer exceeds 224 MiB.") }
                try fm.removeItem(at: metadata)
                return destination
            } catch { try? fm.removeItem(at: share); throw error }
        }
        return try await withTaskCancellationHandler { try await job.value } onCancel: { job.cancel(); progress.cancel() }
    }

    static func unpack(_ url: URL) async throws -> Prepared {
        let progress = Progress(totalUnitCount: 0)
        let job = Task.detached(priority: .userInitiated) {
            let granted = url.startAccessingSecurityScopedResource()
            defer { if granted { url.stopAccessingSecurityScopedResource() } }
            let fm = FileManager.default
            let directory = fm.temporaryDirectory.appending(path: "CrabrixGitImport-" + UUID().uuidString)
            do {
                guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= maximumArchive else { throw failure("The repository transfer exceeds 224 MiB.") }
                let archive = try Archive(url: url, accessMode: .read)
                var entries: [String: Entry] = [:], nodes: [String: (String, Bool)] = [:]
                var total: UInt64 = 0, count = 0
                for entry in archive {
                    try Task.checkCancellation(); count += 1
                    guard count <= 32_769, entry.type != .symlink else { throw failure("The repository archive has too many entries or contains a link.") }
                    let path = entry.type == .directory && entry.path.hasSuffix("/") ? String(entry.path.dropLast()) : entry.path
                    try validatePath(path)
                    guard entries[path] == nil else { throw failure("Duplicate repository archive path: " + path) }
                    let key = path.precomposedStringWithCanonicalMapping.lowercased()
                    if let node = nodes[key] { guard node.0 == path, node.1 && entry.type == .directory else { throw failure("Repository path collision: " + path) } }
                    nodes[key] = (path, entry.type == .directory)
                    let parts = path.split(separator: "/")
                    for length in 1..<parts.count {
                        let parent = parts.prefix(length).joined(separator: "/"), normalized = parent.precomposedStringWithCanonicalMapping.lowercased()
                        if let node = nodes[normalized] { guard node.0 == parent, node.1 else { throw failure("Repository directory collision: " + parent) } }
                        nodes[normalized] = (parent, true)
                    }
                    guard entry.uncompressedSize <= UInt64(maximumArchive) else { throw failure("A repository archive entry exceeds 224 MiB.") }
                    total += UInt64(entry.uncompressedSize)
                    guard total <= UInt64(maximumArchive) else { throw failure("The expanded repository archive exceeds 224 MiB.") }
                    entries[path] = entry
                }
                guard let metadata = entries[manifestName], metadata.type == .file, metadata.uncompressedSize <= maximumMetadata else { throw failure("The repository transfer inventory is missing or too large.") }
                var data = Data()
                let checksum = try archive.extract(metadata, progress: progress) { chunk in
                    data.append(chunk)
                    guard data.count <= maximumMetadata else { throw failure("The repository transfer inventory exceeds its limit.") }
                }
                guard checksum == metadata.checksum, data.count == metadata.uncompressedSize else { throw failure("The transfer inventory checksum differs.") }
                let envelope = try JSONDecoder().decode(Envelope.self, from: data)
                guard envelope.version == 1, envelope.engine == "libgit2-sha1", envelope.project.version <= CrabrixProject.PackageMetadata.currentVersion,
                      Set(envelope.files.keys) == Set(entries.filter { $0.value.type == .file && $0.key != manifestName }.keys) else {
                    throw failure("Unsupported or incomplete repository transfer inventory.")
                }
                if let origin = envelope.origin { _ = try GitHTTPSAddress.canonical(origin) }
                try fm.createDirectory(at: directory, withIntermediateDirectories: true)
                for path in envelope.files.keys.sorted() {
                    try Task.checkCancellation(); try validatePath(path)
                    guard let record = envelope.files[path], record.bytes >= 0, record.sha256.count == 64,
                          let entry = entries[path], record.bytes == entry.uncompressedSize else { throw failure("Repository inventory size differs: " + path) }
                    let destination = directory.appending(path: path)
                    try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    guard fm.createFile(atPath: destination.path, contents: nil) else { throw failure("Cannot create repository import file.") }
                    let handle = try FileHandle(forWritingTo: destination)
                    var hasher = SHA256(), bytes = 0
                    do {
                        let crc = try archive.extract(entry, progress: progress) { chunk in
                            try Task.checkCancellation(); bytes += chunk.count
                            guard bytes <= record.bytes else { throw failure("Repository entry expanded beyond its declared size: " + path) }
                            hasher.update(data: chunk); try handle.write(contentsOf: chunk)
                        }
                        try handle.close()
                        let hash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
                        guard bytes == record.bytes, crc == entry.checksum, hash == record.sha256 else { throw failure("Repository entry checksum differs: " + path) }
                    } catch { try? handle.close(); throw error }
                    try fm.setAttributes([.posixPermissions: record.executable ? 0o755 : 0o644], ofItemAtPath: destination.path)
                }
                return Prepared(directory: directory, envelope: envelope)
            } catch { try? fm.removeItem(at: directory); throw error }
        }
        return try await withTaskCancellationHandler { try await job.value } onCancel: { job.cancel(); progress.cancel() }
    }

    private static func validatePath(_ path: String) throws {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard path.utf8.count <= 2048, parts.count <= 64,
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.utf8.count <= 255 && !$0.hasSuffix(" ") && !$0.hasSuffix(".") }),
              !path.contains("\\"), !path.contains(":"), !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || $0.properties.generalCategory == .format }),
              ["repo", "worktree"].contains(String(parts.first ?? "")) || ["state.json", manifestName].contains(path) else {
            throw failure("Unsafe repository transfer path: " + path)
        }
    }

    private static func hashFile(_ file: URL) throws -> (bytes: Int, hash: String) {
        let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
        var hasher = SHA256(), bytes = 0
        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            try Task.checkCancellation(); bytes += chunk.count
            guard bytes <= maximumArchive else { throw failure("A repository file exceeds the transfer profile.") }
            hasher.update(data: chunk)
        }
        return (bytes, hasher.finalize().map { String(format: "%02x", $0) }.joined())
    }
    private static func failure(_ message: String) -> GitRepositoryFailure { GitRepositoryFailure(message) }
}
