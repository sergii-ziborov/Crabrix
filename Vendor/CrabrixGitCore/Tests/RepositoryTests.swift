import XCTest
import Foundation
@testable import CrabrixGit

@MainActor
final class RepositoryTests: XCTestCase {
    func testStandardCommitsSelectionDiffHistoryAndBranches() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "CrabrixGitTest-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GitRepositoryStore(root: root)
        let id = UUID()
        var files = ["main.rs": "fn main(){println!(\"first\");}\n", ".rustfmt.toml": "max_width=100\n", "script.sh": "echo crab\n"]
        var state = try await store.initialize(id, files: files)
        XCTAssertNil(state.head)
        XCTAssertEqual(state.changes.count, 3)
        let first = try await store.commit(id, files: files, selected: ["main.rs"], author: "Crabrix Test", email: "test@example.invalid", message: "First selected file", expectedHead: nil, expectedRevision: state.revision)
        state = first.state
        XCTAssertEqual(state.changes.map(\.path), [".rustfmt.toml", "script.sh"])
        state = try await store.createBranch(id, name: "practice", expectedHead: first.commit.id, expectedRevision: state.revision)
        let binary = Data([0, 255, 128, 65, 0, 13])
        let worktree = root.appending(path: id.uuidString.lowercased() + "/worktree")
        try binary.write(to: worktree.appending(path: "asset.bin"))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: worktree.appending(path: "script.sh").path)
        state = try await store.status(id, files: files, expectedRevision: state.revision)
        let all = try await store.commit(id, files: files, selected: state.changes.map(\.path), author: "Crabrix Test", email: "test@example.invalid", message: "Complete tree", expectedHead: state.head, expectedRevision: state.revision)
        state = all.state
        XCTAssertTrue(state.changes.isEmpty)
        files["main.rs"] = "fn main(){println!(\"second\");}\n"
        files.removeValue(forKey: ".rustfmt.toml")
        let diff = try await store.diff(id, files: files, path: "main.rs", expectedRevision: state.revision)
        state = diff.state
        XCTAssertTrue(diff.text.contains("-fn main(){println!(\"first\");}"))
        XCTAssertTrue(diff.text.contains("+fn main(){println!(\"second\");}"))
        XCTAssertEqual(try Data(contentsOf: worktree.appending(path: "asset.bin")), binary)
        let mode = try FileManager.default.attributesOfItem(atPath: worktree.appending(path: "script.sh").path)[.posixPermissions] as? Int
        XCTAssertEqual((mode ?? 0) & 0o111, 0o111)
        do {
            _ = try await store.checkout(id, branch: "practice", files: files, expectedHead: all.commit.id, expectedRevision: state.revision)
            XCTFail("Dirty checkout must be refused")
        } catch { XCTAssertTrue(error.localizedDescription.contains("local changes")) }
        let third = try await store.commit(id, files: files, selected: state.changes.map(\.path), author: "Crabrix Test", email: "test@example.invalid", message: "Changed and deleted", expectedHead: state.head, expectedRevision: state.revision)
        state = third.state
        let checkout = try await store.checkout(id, branch: "practice", files: files, expectedHead: third.commit.id, expectedRevision: state.revision)
        XCTAssertEqual(checkout.snapshot.files, ["main.rs": "fn main(){println!(\"first\");}\n"])
        let back = try await store.checkout(id, branch: "main", files: checkout.snapshot.files, expectedHead: first.commit.id, expectedRevision: checkout.state.revision)
        XCTAssertEqual(back.snapshot.files, files)
        XCTAssertEqual(back.snapshot.opaquePaths, ["asset.bin"])
        let historic = try await store.file(id, commit: all.commit.id, path: ".rustfmt.toml")
        XCTAssertEqual(historic, Data("max_width=100\n".utf8))
        let history = try await store.history(id)
        XCTAssertEqual(history.map(\.message), ["Changed and deleted", "Complete tree", "First selected file"])
        let binaryHistory = try await store.file(id, commit: all.commit.id, path: "asset.bin")
        XCTAssertEqual(binaryHistory, binary)
        #if os(macOS)
        try git(["-C", worktree.path, "fsck", "--full"])
        let clone = root.appending(path: "standard-git-clone")
        try git(["clone", worktree.path, clone.path])
        XCTAssertEqual(try Data(contentsOf: clone.appending(path: "asset.bin")), binary)
        #endif
    }

    func testRevisionCASFailedOperationAndCrashRecoveryKeepHistory() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "CrabrixGitTest-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = GitRepositoryStore(root: root), second = GitRepositoryStore(root: root)
        let id = UUID(), files = ["main.rs": "fn main(){}\n"]
        let initial = try await first.initialize(id, files: files)
        let committed = try await first.commit(id, files: files, selected: ["main.rs"], author: "Test", email: "test@example.invalid", message: "One", expectedHead: nil, expectedRevision: initial.revision)
        let observed = try await second.inspect(id)
        var changed = files; changed["main.rs"] = "fn main(){println!(\"newest\");}\n"
        let newest = try await first.status(id, files: changed, expectedRevision: observed.revision)
        do { _ = try await second.status(id, files: files, expectedRevision: observed.revision); XCTFail("Older editor operation must not replace the new mirror") }
        catch { XCTAssertTrue(error.localizedDescription.contains("workspace changed")) }
        let canonical = root.appending(path: id.uuidString.lowercased())
        XCTAssertEqual(try String(contentsOf: canonical.appending(path: "worktree/main.rs"), encoding: .utf8), changed["main.rs"])
        do {
            _ = try await first.commit(id, files: changed, selected: ["main.rs"], author: "Test", email: "test@example.invalid", message: "Stale head", expectedHead: String(repeating: "0", count: 40), expectedRevision: newest.revision)
            XCTFail("Moved HEAD must reject before installing its staged copy")
        } catch { XCTAssertTrue(error.localizedDescription.contains("branch moved")) }
        let still = try await first.inspect(id)
        XCTAssertEqual(still.head, committed.commit.id)
        XCTAssertEqual(still.revision, newest.revision)
        let previous = root.appending(path: ".previous-" + id.uuidString.lowercased())
        if FileManager.default.fileExists(atPath: previous.path) { try FileManager.default.removeItem(at: previous) }
        try FileManager.default.moveItem(at: canonical, to: previous)
        let recovered = try await second.inspect(id)
        XCTAssertEqual(recovered.head, committed.commit.id)
        XCTAssertEqual(recovered.revision, newest.revision)
        let history = try await second.history(id)
        XCTAssertEqual(history.count, 1)
    }

    func testUnsafeOrOverBudgetWorktreesNeverReplaceExistingSource() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "CrabrixGitTest-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GitRepositoryStore(root: root), id = UUID()
        let files = ["main.rs": "fn main(){}\n"]
        let state = try await store.initialize(id, files: files)
        let worktree = root.appending(path: id.uuidString.lowercased() + "/worktree")
        for extra in [["../outside":"bad"], [".git":"bad"], [".git\u{200c}":"bad"], ["A":"one", "a/x":"two"]] {
            let bad = files.merging(extra) { _, new in new }
            do { _ = try await store.status(id, files: bad, expectedRevision: state.revision); XCTFail("Unsafe tree was accepted") }
            catch { }
            XCTAssertEqual(try String(contentsOf: worktree.appending(path: "main.rs"), encoding: .utf8), files["main.rs"])
        }
        let oversized = worktree.appending(path: "oversized.bin")
        XCTAssertTrue(FileManager.default.createFile(atPath: oversized.path, contents: Data()))
        let handle = try FileHandle(forWritingTo: oversized); try handle.truncate(atOffset: UInt64(GitRepositoryStore.maximumFileBytes + 1)); try handle.close()
        var changed = files; changed["main.rs"] = "fn main(){println!(\"new\");}"
        do { _ = try await store.status(id, files: changed, expectedRevision: state.revision); XCTFail("Oversized opaque files must fail before tree replacement") }
        catch { XCTAssertTrue(error.localizedDescription.contains("8 MiB")) }
        XCTAssertEqual(try String(contentsOf: worktree.appending(path: "main.rs"), encoding: .utf8), files["main.rs"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: oversized.path))
        try FileManager.default.removeItem(at: oversized)
        let link = worktree.appending(path: "link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        do { _ = try await store.status(id, files: changed, expectedRevision: state.revision); XCTFail("Filesystem links must be rejected") }
        catch { XCTAssertTrue(error.localizedDescription.contains("link")) }
        XCTAssertEqual(try String(contentsOf: worktree.appending(path: "main.rs"), encoding: .utf8), files["main.rs"])
    }

    #if os(macOS)
    private func git(_ arguments: [String]) throws {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        let pipe = Pipe(); process.standardError = pipe; process.standardOutput = pipe
        try process.run(); process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, output)
    }
    #endif
}
