import Foundation
import CryptoKit
@preconcurrency import CLibgit2

public struct GitRepositoryFailure: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct GitChange: Identifiable, Sendable {
    public let path: String
    public let kind: String
    public let flags: UInt32
    public var id: String { path }
}

public struct GitState: Sendable {
    public let revision: String
    public let branch: String
    public let head: String?
    public let changes: [GitChange]
}

public struct GitDiff: Sendable { public let text: String; public let state: GitState }
public struct GitCommitReceipt: Sendable { public let commit: GitCommit; public let state: GitState }
public struct GitCheckout: Sendable { public let snapshot: GitTreeSnapshot; public let state: GitState }

public struct GitCommit: Identifiable, Sendable {
    public let id: String
    public let message: String
    public let author: String
    public let date: Date
}

public struct GitTreeSnapshot: Sendable {
    public let files: [String: String]
    public let opaquePaths: [String]
    public let opaqueBytes: Int
}

/// A complete, bounded worktree and standard Git store, separate from the app's
/// replaceable text snapshots. Every mutating operation runs in a disposable
/// copy. Git objects, index, refs, ownership metadata and worktree install
/// together, retaining the previous root until the next successful transaction.
public actor GitRepositoryStore {
    private static let lock = NSRecursiveLock()
    private static let initialized = git_libgit2_init()
    private let root: URL
    private let fm = FileManager.default
    private struct State: Codable { var editableDigests: [String: String]; var revision = UUID().uuidString }
    private struct File { let data: Data; let executable: Bool }
    public static let maximumRepositoryBytes = 192 * 1024 * 1024
    public static let maximumWorktreeBytes = 64 * 1024 * 1024
    public static let maximumFileBytes = 8 * 1024 * 1024

    public init(root: URL) { self.root = root.resolvingSymlinksInPath() }

    public func exists(_ project: UUID) throws -> Bool {
        try Self.lock.withLock {
            try recover(project)
            return fm.fileExists(atPath: location(project).appending(path: "repo/HEAD").path)
        }
    }

    public func initialize(_ project: UUID, files: [String: String]) throws -> GitState {
        try Self.lock.withLock {
            try recover(project)
            guard !fm.fileExists(atPath: location(project).path) else { throw GitRepositoryFailure("This project already has Git storage. Existing or damaged history was kept; refresh/recover it instead of initializing over it.") }
            try transaction(project, create: true) { stage in
                try fm.createDirectory(at: stage.appending(path: "worktree"), withIntermediateDirectories: true)
                var options = git_repository_init_options()
                try check(git_repository_init_options_init(&options, UInt32(GIT_REPOSITORY_INIT_OPTIONS_VERSION)))
                options.flags = UInt32(GIT_REPOSITORY_INIT_MKPATH.rawValue | GIT_REPOSITORY_INIT_NO_DOTGIT_DIR.rawValue)
                var repository: OpaquePointer?
                try stage.appending(path: "worktree").path.withCString { workdir in
                    try "main".withCString { branch in
                        options.workdir_path = workdir; options.initial_head = branch
                        try check(git_repository_init_ext(&repository, stage.appending(path: "repo").path, &options))
                    }
                }
                guard let repository else { throw GitRepositoryFailure("Git did not create a repository.") }
                defer { git_repository_free(repository) }
                var config: OpaquePointer?
                try check(git_repository_config(&config, repository))
                defer { git_config_free(config) }
                try check(git_config_set_string(config, "core.worktree", "../worktree"))
                try Data("gitdir: ../repo\n".utf8).write(to: stage.appending(path: "worktree/.git"))
                try writeState(State(editableDigests: [:]), stage)
                try reconcile(files, stage)
            }
            return try readStatus(project)
        }
    }

    public func inspect(_ project: UUID) throws -> GitState {
        try Self.lock.withLock { try readStatus(project) }
    }

    public func status(_ project: UUID, files: [String: String], expectedRevision: String) throws -> GitState {
        try Self.lock.withLock {
            try synchronize(project, files, expectedRevision: expectedRevision)
            return try readStatus(project)
        }
    }

    public func diff(_ project: UUID, files: [String: String], path: String, expectedRevision: String) throws -> GitDiff {
        try Self.lock.withLock {
            try Self.validatePath(path)
            try synchronize(project, files, expectedRevision: expectedRevision)
            let text = try withRepository(location(project)) { repository in
                var options = git_diff_options()
                try check(git_diff_options_init(&options, UInt32(GIT_DIFF_OPTIONS_VERSION)))
                options.flags = UInt32(GIT_DIFF_INCLUDE_UNTRACKED.rawValue | GIT_DIFF_SHOW_UNTRACKED_CONTENT.rawValue | GIT_DIFF_DISABLE_PATHSPEC_MATCH.rawValue)
                let string = strdup(path)!
                defer { free(string) }
                var pathPointer: UnsafeMutablePointer<CChar>? = string
                var diff: OpaquePointer?
                var tree: OpaquePointer?
                if let oid = try headOID(repository) {
                    var commit: OpaquePointer?
                    var id = oid
                    try check(git_commit_lookup(&commit, repository, &id))
                    defer { git_commit_free(commit) }
                    try check(git_commit_tree(&tree, commit))
                }
                defer { git_tree_free(tree); git_diff_free(diff) }
                try withUnsafeMutablePointer(to: &pathPointer) { paths in
                    options.pathspec = git_strarray(strings: paths, count: 1)
                    try check(git_diff_tree_to_workdir_with_index(&diff, repository, tree, &options))
                }
                var buffer = git_buf()
                defer { git_buf_dispose(&buffer) }
                try check(git_diff_to_buf(&buffer, diff, GIT_DIFF_FORMAT_PATCH))
                guard let pointer = buffer.ptr else { return "No text changes." }
                let bytes = UnsafeRawBufferPointer(start: pointer, count: min(buffer.size, 256 * 1024))
                return String(decoding: bytes, as: UTF8.self)
                    + (buffer.size > 256 * 1024 ? "\n[Diff preview limited to 256 KiB; repository content is unchanged.]" : "")
            }
            return GitDiff(text: text, state: try readStatus(project))
        }
    }

    public func commit(_ project: UUID, files: [String: String], selected: [String],
                       author: String, email: String, message: String, expectedHead: String?, expectedRevision: String) throws -> GitCommitReceipt {
        try Self.lock.withLock {
            guard !selected.isEmpty, Set(selected).count == selected.count else { throw GitRepositoryFailure("Select at least one distinct file to commit.") }
            for path in selected { try Self.validatePath(path) }
            guard !author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  author.utf8.count <= 256, email.utf8.count <= 320, message.utf8.count <= 4096,
                  !author.contains("\n"), !email.contains("\n") else { throw GitRepositoryFailure("Enter a bounded author, email and commit message.") }
            var created: GitCommit?
            try transaction(project, expectedRevision: expectedRevision) { stage in
                try reconcile(files, stage)
                try withRepository(stage) { repository in
                    let old = try headOID(repository)
                    guard old.map(Self.oidString) == expectedHead else { throw GitRepositoryFailure("The Git branch moved. Refresh Changes before committing.") }
                    var index: OpaquePointer?
                    try check(git_repository_index(&index, repository))
                    defer { git_index_free(index) }
                    // The initial profile has selection-at-commit, not an
                    // independent staging UI. Never silently replace an
                    // imported staged snapshot.
                    let state = try status(repository, revision: self.state(stage).revision)
                    let indexMask = UInt32(GIT_STATUS_INDEX_NEW.rawValue | GIT_STATUS_INDEX_MODIFIED.rawValue | GIT_STATUS_INDEX_DELETED.rawValue | GIT_STATUS_INDEX_RENAMED.rawValue | GIT_STATUS_INDEX_TYPECHANGE.rawValue)
                    guard !state.changes.contains(where: { $0.flags & indexMask != 0 }) else {
                        throw GitRepositoryFailure("This repository has a separate staged snapshot. Preserve/export it before using the initial selected-file commit profile.")
                    }
                    let changed = Set(state.changes.map(\.path))
                    guard Set(selected).isSubset(of: changed) else { throw GitRepositoryFailure("A selected file is no longer changed. Refresh Changes.") }
                    for path in selected {
                        if fm.fileExists(atPath: stage.appending(path: "worktree/" + path).path) {
                            try check(git_index_add_bypath(index, path))
                        } else { try check(git_index_remove_bypath(index, path)) }
                    }
                    var treeID = git_oid()
                    try check(git_index_write_tree(&treeID, index))
                    var tree: OpaquePointer?; var parent: OpaquePointer?
                    try check(git_tree_lookup(&tree, repository, &treeID))
                    defer { git_tree_free(tree); git_commit_free(parent) }
                    if var old { try check(git_commit_lookup(&parent, repository, &old)) }
                    var signature: UnsafeMutablePointer<git_signature>?
                    try check(git_signature_now(&signature, author, email))
                    defer { git_signature_free(signature) }
                    var id = git_oid()
                    var immutableParent = parent
                    try withUnsafeMutablePointer(to: &immutableParent) { parents in
                        try check(git_commit_create(&id, repository, "HEAD", signature, signature, nil,
                            message, tree, old == nil ? 0 : 1, parents))
                    }
                    try check(git_index_write(index))
                    created = GitCommit(id: Self.oidString(id), message: message, author: author, date: Date())
                }
            }
            return GitCommitReceipt(commit: created!, state: try readStatus(project))
        }
    }

    public func history(_ project: UUID, limit: Int = 50) throws -> [GitCommit] {
        try Self.lock.withLock {
            try withRepository(location(project)) { repository in
                guard var oid = try headOID(repository) else { return [] }
                var walker: OpaquePointer?
                try check(git_revwalk_new(&walker, repository))
                defer { git_revwalk_free(walker) }
                git_revwalk_sorting(walker, UInt32(GIT_SORT_TOPOLOGICAL.rawValue | GIT_SORT_TIME.rawValue))
                try check(git_revwalk_push(walker, &oid))
                var result: [GitCommit] = []
                while result.count < min(100, max(1, limit)) {
                    let next = git_revwalk_next(&oid, walker)
                    if next == GIT_ITEROVER.rawValue { break }
                    try check(next)
                    var commit: OpaquePointer?
                    try check(git_commit_lookup(&commit, repository, &oid))
                    defer { git_commit_free(commit) }
                    let signature = git_commit_author(commit)!.pointee
                    result.append(GitCommit(id: Self.oidString(oid), message: String(cString: git_commit_message(commit)),
                        author: String(cString: signature.name), date: Date(timeIntervalSince1970: TimeInterval(signature.when.time))))
                }
                return result
            }
        }
    }

    public func branches(_ project: UUID) throws -> [String] {
        try Self.lock.withLock {
            try withRepository(location(project)) { repository in
                var iterator: OpaquePointer?
                try check(git_branch_iterator_new(&iterator, repository, GIT_BRANCH_LOCAL))
                defer { git_branch_iterator_free(iterator) }
                var names: [String] = []
                while true {
                    var reference: OpaquePointer?; var kind = GIT_BRANCH_LOCAL
                    let next = git_branch_next(&reference, &kind, iterator)
                    if next == GIT_ITEROVER.rawValue { break }
                    try check(next)
                    defer { git_reference_free(reference) }
                    var name: UnsafePointer<CChar>?
                    try check(git_branch_name(&name, reference))
                    if let name { names.append(String(cString: name)) }
                    guard names.count <= 256 else { throw GitRepositoryFailure("The initial profile supports at most 256 local branches.") }
                }
                return names.sorted()
            }
        }
    }

    public func createBranch(_ project: UUID, name: String, expectedHead: String, expectedRevision: String) throws -> GitState {
        try Self.lock.withLock {
            try validateBranch(name)
            try transaction(project, expectedRevision: expectedRevision) { stage in
                try withRepository(stage) { repository in
                    guard var oid = try headOID(repository), Self.oidString(oid) == expectedHead else {
                        throw GitRepositoryFailure("The branch moved. Refresh before creating a branch.")
                    }
                    var commit: OpaquePointer?; var reference: OpaquePointer?
                    try check(git_commit_lookup(&commit, repository, &oid))
                    defer { git_commit_free(commit); git_reference_free(reference) }
                    try check(git_branch_create(&reference, repository, name, commit, 0))
                }
            }
            return try readStatus(project)
        }
    }

    public func checkout(_ project: UUID, branch: String, files: [String: String], expectedHead: String, expectedRevision: String) throws -> GitCheckout {
        try Self.lock.withLock {
            try validateBranch(branch)
            var snapshot: GitTreeSnapshot?
            try transaction(project, expectedRevision: expectedRevision) { stage in
                try reconcile(files, stage)
                try withRepository(stage) { repository in
                    let current = try status(repository, revision: self.state(stage).revision)
                    guard current.head == expectedHead else { throw GitRepositoryFailure("The branch moved. Refresh before checkout.") }
                    guard current.changes.isEmpty else { throw GitRepositoryFailure("Commit or explicitly restore local changes before switching branches. Your files were kept.") }
                    var reference: OpaquePointer?; var commit: OpaquePointer?; var tree: OpaquePointer?
                    try check(git_branch_lookup(&reference, repository, branch, GIT_BRANCH_LOCAL))
                    defer { git_reference_free(reference); git_commit_free(commit); git_tree_free(tree) }
                    guard let id = git_reference_target(reference) else { throw GitRepositoryFailure("The target branch has no commit.") }
                    try check(git_commit_lookup(&commit, repository, id))
                    try check(git_commit_tree(&tree, commit))
                    let treeFiles = try readTree(repository, tree!)
                    snapshot = try editableSnapshot(treeFiles)
                    guard !snapshot!.files.isEmpty else { throw GitRepositoryFailure("The target branch has no editable text files; its tree was not installed.") }
                    let worktree = stage.appending(path: "worktree")
                    try fm.removeItem(at: worktree)
                    try writeFiles(treeFiles, worktree)
                    try Data("gitdir: ../repo\n".utf8).write(to: worktree.appending(path: ".git"))
                    var index: OpaquePointer?
                    try check(git_repository_index(&index, repository)); defer { git_index_free(index) }
                    try check(git_index_read_tree(index, tree)); try check(git_index_write(index))
                    try check(git_repository_set_head(repository, "refs/heads/" + branch))
                    try writeState(State(editableDigests: digests(snapshot!.files)), stage)
                }
            }
            return GitCheckout(snapshot: snapshot!, state: try readStatus(project))
        }
    }

    public func file(_ project: UUID, commit: String, path: String) throws -> Data {
        try Self.lock.withLock {
            try Self.validatePath(path)
            guard commit.utf8.count == 40, commit.allSatisfy(\.isHexDigit) else { throw GitRepositoryFailure("Select an exact commit from History.") }
            return try withRepository(location(project)) { repository in
                var oid = git_oid(); try check(git_oid_fromstr(&oid, commit))
                var object: OpaquePointer?; var tree: OpaquePointer?; var entry: OpaquePointer?
                try check(git_commit_lookup(&object, repository, &oid)); defer { git_commit_free(object) }
                try check(git_commit_tree(&tree, object)); defer { git_tree_free(tree) }
                try check(git_tree_entry_bypath(&entry, tree, path)); defer { git_tree_entry_free(entry) }
                guard git_tree_entry_type(entry) == GIT_OBJECT_BLOB, git_tree_entry_filemode(entry) != GIT_FILEMODE_LINK else {
                    throw GitRepositoryFailure("This history entry is not a supported regular file.")
                }
                return try blob(repository, git_tree_entry_id(entry)!)
            }
        }
    }

    public func tree(_ project: UUID, commit: String) throws -> GitTreeSnapshot {
        try Self.lock.withLock {
            guard commit.utf8.count == 40, commit.allSatisfy(\.isHexDigit) else { throw GitRepositoryFailure("Select an exact commit from History.") }
            return try withRepository(location(project)) { repository in
                var oid = git_oid(); try check(git_oid_fromstr(&oid, commit))
                var object: OpaquePointer?; var tree: OpaquePointer?
                try check(git_commit_lookup(&object, repository, &oid)); defer { git_commit_free(object) }
                try check(git_commit_tree(&tree, object)); defer { git_tree_free(tree) }
                return try editableSnapshot(readTree(repository, tree!))
            }
        }
    }

    /// Called only by explicit project deletion. No automatic history eviction.
    public func delete(_ project: UUID) throws {
        try Self.lock.withLock {
            let paths = [location(project), root.appending(path: ".previous-" + project.uuidString.lowercased())]
            for path in paths where fm.fileExists(atPath: path.path) { try fm.removeItem(at: path) }
            if fm.fileExists(atPath: root.path) {
                for path in try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                    where path.lastPathComponent.hasPrefix(".stage-" + project.uuidString.lowercased() + "-") {
                    try fm.removeItem(at: path)
                }
            }
        }
    }

    private func location(_ project: UUID) -> URL { root.appending(path: project.uuidString.lowercased()) }

    private func check(_ result: Int32) throws {
        guard result >= 0 else {
            let message: String
            if let error = git_error_last(), let pointer = error.pointee.message { message = String(cString: pointer) }
            else { message = "Git operation failed" }
            throw GitRepositoryFailure(message)
        }
    }

    private func withRepository<T>(_ directory: URL, _ body: (OpaquePointer) throws -> T) throws -> T {
        _ = Self.initialized
        if let project = UUID(uuidString: directory.lastPathComponent),
           directory.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path == root.resolvingSymlinksInPath().standardizedFileURL.path {
            try recover(project)
        }
        var repository: OpaquePointer?
        try check(git_repository_open(&repository, directory.appending(path: "repo").path))
        guard let repository else { throw GitRepositoryFailure("This project has no local Git repository.") }
        defer { git_repository_free(repository) }
        return try body(repository)
    }

    private func headOID(_ repository: OpaquePointer) throws -> git_oid? {
        var reference: OpaquePointer?
        let result = git_repository_head(&reference, repository)
        if result == GIT_EUNBORNBRANCH.rawValue || result == GIT_ENOTFOUND.rawValue { return nil }
        try check(result); defer { git_reference_free(reference) }
        return git_reference_target(reference)?.pointee
    }

    private static func oidString(_ oid: git_oid) -> String {
        var oid = oid
        var buffer = [CChar](repeating: 0, count: 41)
        git_oid_tostr(&buffer, buffer.count, &oid)
        return String(cString: buffer)
    }

    private func readStatus(_ project: UUID) throws -> GitState {
        try withRepository(location(project)) { try status($0, revision: state(location(project)).revision) }
    }

    private func status(_ repository: OpaquePointer, revision: String) throws -> GitState {
        var list: OpaquePointer?
        var options = git_status_options()
        try check(git_status_options_init(&options, UInt32(GIT_STATUS_OPTIONS_VERSION)))
        options.flags = UInt32(GIT_STATUS_OPT_INCLUDE_UNTRACKED.rawValue | GIT_STATUS_OPT_RECURSE_UNTRACKED_DIRS.rawValue)
        try check(git_status_list_new(&list, repository, &options)); defer { git_status_list_free(list) }
        var changes: [GitChange] = []
        for index in 0..<git_status_list_entrycount(list) {
            guard let entry = git_status_byindex(list, index)?.pointee else { continue }
            let delta = entry.index_to_workdir ?? entry.head_to_index
            guard let path = delta?.pointee.new_file.path ?? delta?.pointee.old_file.path else { continue }
            guard let pathString = String(validatingUTF8: path) else { throw GitRepositoryFailure("Non-UTF-8 repository paths are unsupported and were kept unchanged.") }
            try Self.validatePath(pathString)
            let flags = entry.status.rawValue
            let deleted = flags & UInt32(GIT_STATUS_WT_DELETED.rawValue | GIT_STATUS_INDEX_DELETED.rawValue) != 0
            let new = flags & UInt32(GIT_STATUS_WT_NEW.rawValue | GIT_STATUS_INDEX_NEW.rawValue) != 0
            changes.append(GitChange(path: pathString, kind: deleted ? "deleted" : new ? "untracked" : "modified", flags: flags))
        }
        var head: OpaquePointer?
        let result = git_repository_head(&head, repository)
        var branch = "main"
        if result >= 0 {
            defer { git_reference_free(head) }
            if let name = git_reference_shorthand(head) { branch = String(cString: name) }
        } else if result != GIT_EUNBORNBRANCH.rawValue { try check(result) }
        return GitState(revision: revision, branch: branch, head: try headOID(repository).map(Self.oidString), changes: changes.sorted { $0.path < $1.path })
    }

    private func validateBranch(_ name: String) throws {
        var valid: Int32 = 0
        guard name.utf8.count <= 200, !name.isEmpty else { throw GitRepositoryFailure("Enter a branch name up to 200 bytes.") }
        try check(git_reference_name_is_valid(&valid, "refs/heads/" + name))
        guard valid == 1 else { throw GitRepositoryFailure("Invalid Git branch name.") }
    }

    private func digests(_ files: [String: String]) -> [String: String] {
        files.mapValues { SHA256.hash(data: Data($0.utf8)).map { String(format: "%02x", $0) }.joined() }
    }

    private func state(_ directory: URL) throws -> State {
        try JSONDecoder().decode(State.self, from: Data(contentsOf: directory.appending(path: "state.json")))
    }

    private func writeState(_ value: State, _ directory: URL) throws {
        try JSONEncoder().encode(value).write(to: directory.appending(path: "state.json"), options: .atomic)
    }

    private func synchronize(_ project: UUID, _ files: [String: String], expectedRevision: String) throws {
        guard try exists(project) else { throw GitRepositoryFailure("Initialize local Git for this project first.") }
        guard try state(location(project)).revision == expectedRevision else { throw GitRepositoryFailure("The repository workspace changed. Refresh before applying this editor snapshot.") }
        if try state(location(project)).editableDigests != digests(files) {
            try transaction(project, expectedRevision: expectedRevision) { try reconcile(files, $0) }
        }
    }

    private func reconcile(_ files: [String: String], _ stage: URL) throws {
        try validateEditable(files)
        let previous = try state(stage)
        var tree = try workingFiles(stage.appending(path: "worktree"))
        let modes = tree.mapValues(\.executable)
        for (path, hash) in previous.editableDigests {
            guard let data = tree[path]?.data,
                  SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == hash else {
                throw GitRepositoryFailure("The canonical worktree changed outside this editor snapshot. Refresh/recover it before replacing files: " + path)
            }
            tree.removeValue(forKey: path)
        }
        for (path, text) in files {
            if let opaque = tree[path], opaque.data != Data(text.utf8) {
                throw GitRepositoryFailure("An opaque/unowned repository file already exists at " + path)
            }
            tree[path] = File(data: Data(text.utf8), executable: modes[path] ?? false)
        }
        try validateTree(tree)
        let worktree = stage.appending(path: "worktree")
        try fm.removeItem(at: worktree)
        try writeFiles(tree, worktree)
        try Data("gitdir: ../repo\n".utf8).write(to: worktree.appending(path: ".git"))
        try writeState(State(editableDigests: digests(files)), stage)
    }

    private func workingFiles(_ worktree: URL) throws -> [String: File] {
        var files: [String: File] = [:]
        var enumerationFailure: Error?; var total = 0
        guard let enumerator = fm.enumerator(at: worktree, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey], errorHandler: { _, error in enumerationFailure = error; return false }) else {
            throw GitRepositoryFailure("Cannot enumerate the canonical worktree.")
        }
        let base = worktree.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isSymbolicLink != true else { throw GitRepositoryFailure("Symlinks are outside this repository profile: " + url.lastPathComponent) }
            let components = url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
            guard Array(components.prefix(base.count)) == base else { throw GitRepositoryFailure("A worktree entry escaped its root.") }
            let path = components.dropFirst(base.count).joined(separator: "/")
            if path == ".git" {
                guard values.isRegularFile == true, values.fileSize == 16,
                      try readBounded(url) == Data("gitdir: ../repo\n".utf8) else { throw GitRepositoryFailure("The internal Git pointer changed; it was kept for recovery.") }
                continue
            }
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true, let size = values.fileSize, size <= Self.maximumFileBytes else { throw GitRepositoryFailure("Repository file is not regular or exceeds 8 MiB: " + path) }
            let permissions = try fm.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int ?? 0
            let data = try readBounded(url)
            total += data.count
            guard total <= Self.maximumWorktreeBytes else { throw GitRepositoryFailure("Repository exceeds the 64 MiB worktree profile.") }
            files[path] = File(data: data, executable: permissions & 0o111 != 0)
            guard files.count <= 8192 else { throw GitRepositoryFailure("Repository exceeds 8,192 worktree files.") }
        }
        if let enumerationFailure { throw enumerationFailure }
        try validateTree(files)
        return files
    }

    private func validateEditable(_ files: [String: String]) throws {
        guard files.count <= 2048, files.values.reduce(0, { $0 + $1.utf8.count }) <= 16_000_000 else {
            throw GitRepositoryFailure("The editable Rust project exceeds its 2,048-file / 16 MB profile.")
        }
        for (path, text) in files {
            try Self.validatePath(path)
            guard text.utf8.count <= 2 * 1024 * 1024 else { throw GitRepositoryFailure("Editable file exceeds 2 MiB: " + path) }
        }
    }

    private static func validatePath(_ path: String) throws {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, path.utf8.count <= 1024, parts.count <= 32,
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.lowercased() != ".git" && $0.utf8.count <= 255 && !$0.hasSuffix(" ") && !$0.hasSuffix(".") }),
              parts.first?.lowercased() != ".crabrix", !path.contains("\\"),
              !path.contains(":"), !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || $0.properties.generalCategory == .format }) else {
            throw GitRepositoryFailure("Unsupported repository path: " + path)
        }
    }

    private func validateTree(_ files: [String: File]) throws {
        guard files.count <= 8192, files.values.reduce(0, { $0 + $1.data.count }) <= Self.maximumWorktreeBytes else {
            throw GitRepositoryFailure("Repository exceeds the 8,192-file / 64 MiB worktree profile.")
        }
        var identities: [String: String] = [:]
        var directories: [String: String] = [:]
        for path in files.keys.sorted() {
            try Self.validatePath(path)
            guard files[path]!.data.count <= Self.maximumFileBytes else { throw GitRepositoryFailure("Repository file exceeds 8 MiB: " + path) }
            let key = path.precomposedStringWithCanonicalMapping.lowercased()
            guard identities[key] == nil, directories[key] == nil else { throw GitRepositoryFailure("Case/Unicode or directory collision: " + path) }
            identities[key] = path
            let parts = path.split(separator: "/")
            for count in 1..<parts.count {
                let directory = parts.prefix(count).joined(separator: "/")
                let normalized = directory.precomposedStringWithCanonicalMapping.lowercased()
                guard identities[normalized] == nil, directories[normalized] == nil || directories[normalized] == directory else {
                    throw GitRepositoryFailure("Repository directory collision: " + directory)
                }
                directories[normalized] = directory
            }
        }
    }

    private func writeFiles(_ files: [String: File], _ directory: URL) throws {
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        for path in files.keys.sorted() {
            try Task.checkCancellation()
            let target = directory.appending(path: path)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try files[path]!.data.write(to: target, options: .atomic)
            if files[path]!.executable { try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path) }
        }
    }

    private func blob(_ repository: OpaquePointer, _ id: UnsafePointer<git_oid>) throws -> Data {
        var blob: OpaquePointer?
        try check(git_blob_lookup(&blob, repository, id)); defer { git_blob_free(blob) }
        let size = git_blob_rawsize(blob)
        guard size <= Self.maximumFileBytes else { throw GitRepositoryFailure("A repository blob exceeds 8 MiB.") }
        guard size > 0 else { return Data() }
        guard let bytes = git_blob_rawcontent(blob) else { throw GitRepositoryFailure("Git blob data is unavailable.") }
        return Data(bytes: bytes, count: Int(size))
    }

    private func readTree(_ repository: OpaquePointer, _ tree: OpaquePointer) throws -> [String: File] {
        var files: [String: File] = [:]
        var total = 0
        func visit(_ tree: OpaquePointer, _ prefix: String, depth: Int) throws {
            guard depth <= 32 else { throw GitRepositoryFailure("Repository tree is too deep.") }
            for index in 0..<git_tree_entrycount(tree) {
                try Task.checkCancellation()
                guard let entry = git_tree_entry_byindex(tree, index), let name = git_tree_entry_name(entry) else { throw GitRepositoryFailure("Invalid Git tree entry.") }
                guard let validName = String(validatingUTF8: name) else { throw GitRepositoryFailure("Non-UTF-8 repository paths are unsupported; no worktree was replaced.") }
                let path = prefix + validName
                try Self.validatePath(path)
                switch git_tree_entry_type(entry) {
                case GIT_OBJECT_TREE:
                    var child: OpaquePointer?
                    try check(git_tree_lookup(&child, repository, git_tree_entry_id(entry)))
                    defer { git_tree_free(child) }
                    try visit(child!, path + "/", depth: depth + 1)
                case GIT_OBJECT_BLOB:
                    let mode = git_tree_entry_filemode(entry)
                    guard mode == GIT_FILEMODE_BLOB || mode == GIT_FILEMODE_BLOB_EXECUTABLE else { throw GitRepositoryFailure("Symlinks are not supported: " + path) }
                    let data = try blob(repository, git_tree_entry_id(entry)!)
                    total += data.count
                    guard total <= Self.maximumWorktreeBytes, files.count < 8192 else { throw GitRepositoryFailure("The target tree exceeds the supported repository profile.") }
                    files[path] = File(data: data, executable: mode == GIT_FILEMODE_BLOB_EXECUTABLE)
                default: throw GitRepositoryFailure("Submodules and non-regular tree entries are not supported: " + path)
                }
            }
        }
        try visit(tree, "", depth: 0)
        try validateTree(files)
        return files
    }

    private func editableSnapshot(_ tree: [String: File]) throws -> GitTreeSnapshot {
        var files: [String: String] = [:]; var opaque: [String] = []; var bytes = 0
        for path in tree.keys.sorted() {
            let data = tree[path]!.data
            if data.count <= 2 * 1024 * 1024, !data.contains(0), let text = String(data: data, encoding: .utf8) { files[path] = text }
            else { opaque.append(path); bytes += data.count }
        }
        try validateEditable(files)
        return GitTreeSnapshot(files: files, opaquePaths: opaque, opaqueBytes: bytes)
    }

    private func transaction(_ project: UUID, create: Bool = false, expectedRevision: String? = nil, _ operation: (URL) throws -> Void) throws {
        _ = Self.initialized
        try Task.checkCancellation()
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let current = location(project)
        let stage = root.appending(path: ".stage-" + project.uuidString.lowercased() + "-" + UUID().uuidString)
        let previous = root.appending(path: ".previous-" + project.uuidString.lowercased())
        defer { try? fm.removeItem(at: stage) }
        if create { try fm.createDirectory(at: stage, withIntermediateDirectories: true) }
        else {
            guard try exists(project) else { throw GitRepositoryFailure("Initialize this project's local Git first.") }
            guard let expectedRevision, try state(current).revision == expectedRevision else { throw GitRepositoryFailure("The repository workspace changed. The older operation was rejected before replacement.") }
            try verifyRepositoryBudget(current)
            try fm.copyItem(at: current, to: stage)
        }
        try operation(stage)
        var updated = try state(stage); updated.revision = UUID().uuidString; try writeState(updated, stage)
        try verifyRepositoryBudget(stage)
        try Task.checkCancellation()
        if fm.fileExists(atPath: previous.path) { try fm.removeItem(at: previous) }
        if fm.fileExists(atPath: current.path) { try fm.moveItem(at: current, to: previous) }
        do { try fm.moveItem(at: stage, to: current) }
        catch {
            if fm.fileExists(atPath: previous.path), !fm.fileExists(atPath: current.path) { try fm.moveItem(at: previous, to: current) }
            throw error
        }
    }

    private func verifyRepositoryBudget(_ directory: URL) throws {
        let rootValues = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else { throw GitRepositoryFailure("Repository root is not a regular directory.") }
        var bytes = 0; var count = 0; var enumerationFailure: Error?
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey], errorHandler: { _, error in enumerationFailure = error; return false }) else {
            throw GitRepositoryFailure("Cannot read repository storage.")
        }
        for case let file as URL in enumerator {
            try Task.checkCancellation()
            let values = try file.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isSymbolicLink != true else { throw GitRepositoryFailure("Repository storage contains an unsupported filesystem link.") }
            count += 1
            if values.isDirectory != true {
                guard values.isRegularFile == true, let size = values.fileSize else { throw GitRepositoryFailure("Repository storage contains a non-regular file.") }
                bytes += size
            }
            guard bytes <= Self.maximumRepositoryBytes, count <= 32_768 else { throw GitRepositoryFailure("Repository storage exceeds 192 MiB / 32,768 entries. Existing history was kept.") }
        }
        if let enumerationFailure { throw enumerationFailure }
    }

    private func readBounded(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var result = Data()
        while let chunk = try handle.read(upToCount: min(64 * 1024, Self.maximumFileBytes + 1 - result.count)), !chunk.isEmpty {
            result.append(chunk)
            guard result.count <= Self.maximumFileBytes else { throw GitRepositoryFailure("Repository file exceeds 8 MiB: " + url.lastPathComponent) }
        }
        return result
    }

    private func recover(_ project: UUID) throws {
        let current = location(project)
        let previous = root.appending(path: ".previous-" + project.uuidString.lowercased())
        if !fm.fileExists(atPath: current.path), fm.fileExists(atPath: previous.path) {
            try fm.moveItem(at: previous, to: current)
        }
    }
}
