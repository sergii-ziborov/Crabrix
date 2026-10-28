import XCTest
import CrabrixGit
@testable import Crabrix

@MainActor
final class GitWorkspaceTests: XCTestCase {
    func testNativeGitSurvivesProjectSavesAndRoundTripsBranchesAndRestore() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "GitWorkspace-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = ProjectLibrary(storageURL: root.appending(path: "recent.json"))
        let preferences = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let model = CompilerViewModel(projectLibrary: library, userDefaults: preferences)
        model.createProject(name: "git-workspace", template: .hello)
        model.source = "fn main(){println!(\"first\");}\n"
        let original = model.source, entry = model.selectedFile, projectID = model.projectID
        model.initializeGit(); try await wait(model)
        XCTAssertTrue(model.gitAvailable, model.gitMessage)
        model.commitGit(paths: model.exportProject().files.keys.sorted(), author: "Crabrix Test", email: "test@example.invalid", message: "First")
        try await wait(model)
        let first = try XCTUnwrap(model.gitState?.head, model.gitMessage)
        XCTAssertTrue(model.gitState?.changes.isEmpty == true)
        model.createGitBranch("practice"); try await wait(model)
        XCTAssertTrue(model.gitBranches.contains("practice"))
        model.source = "fn main(){println!(\"second\");}\n"
        model.refreshGit(); try await wait(model)
        XCTAssertEqual(model.gitState?.changes.map(\.path), [entry])
        model.showGitDiff(entry); try await wait(model)
        XCTAssertTrue(model.gitDiff?.text.contains("second") == true)
        model.commitGit(paths: [entry], author: "Crabrix Test", email: "test@example.invalid", message: "Second")
        try await wait(model)
        let second = try XCTUnwrap(model.gitState?.head)
        XCTAssertNotEqual(first, second)
        await model.retryProjectSave()
        let reopenedItem = try await library.project(id: projectID)
        let reopened = try XCTUnwrap(reopenedItem)
        XCTAssertEqual(reopened.project.files[entry], model.source)
        model.switchGitBranch("practice"); try await wait(model)
        XCTAssertEqual(model.source, original, model.gitMessage)
        XCTAssertEqual(model.gitState?.branch, "practice")
        let persistedItem = try await library.project(id: projectID)
        let persisted = try XCTUnwrap(persistedItem)
        XCTAssertEqual(persisted.project.files[entry], original)
        model.switchGitBranch("main"); try await wait(model)
        XCTAssertTrue(model.source.contains("second"), model.gitMessage)
        XCTAssertNil(model.result)
        XCTAssertNil(model.lastBuild)
        model.previewGitFile(commit: first, path: entry); try await wait(model)
        XCTAssertEqual(model.gitRestorePreview?.replacement, original)
        model.source += "// newer editor work\n"
        let newer = model.source
        model.restoreGitPreview(); try await wait(model)
        XCTAssertEqual(model.source, newer, "Stale restore preview must keep newer text")
        model.previewGitFile(commit: first, path: entry); try await wait(model)
        model.restoreGitPreview(); try await wait(model)
        XCTAssertEqual(model.source, original, model.gitMessage)
        model.refreshGit(); try await wait(model)
        XCTAssertEqual(model.gitState?.changes.map(\.path), [entry])
        XCTAssertEqual(model.gitHistory.map(\.message), ["Second", "First"])
        let store = GitRepositoryStore(root: library.gitStorageURL)
        let tree = try await store.tree(projectID, commit: second)
        XCTAssertTrue(tree.files[entry]?.contains("second") == true)
        _ = await model.deleteProject(projectID: projectID)
        let exists = try await store.exists(projectID)
        XCTAssertFalse(exists)
    }

    func testGitBackgroundSnapshotDoesNotBlockOrOverwriteTyping() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "GitWorkspace-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let preferences = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let model = CompilerViewModel(projectLibrary: ProjectLibrary(storageURL: root.appending(path: "recent.json")), userDefaults: preferences)
        model.createProject(name: "background-git", template: .hello)
        model.initializeGit()
        XCTAssertTrue(model.gitIsWorking)
        XCTAssertFalse(model.isProjectOperationInProgress, "Background Git reads/init must not freeze typing")
        model.source += "\n// typed while history was prepared"
        let newest = model.source
        try await wait(model)
        XCTAssertEqual(model.source, newest)
        XCTAssertTrue(model.gitNeedsRefresh)
        model.refreshGit(); try await wait(model)
        XCTAssertFalse(model.gitNeedsRefresh)
        model.performGitCommand(.identity(key: "user.name", value: "Terminal User"))
        model.performGitCommand(.identity(key: "user.email", value: "terminal@example.invalid"))
        model.performGitCommand(.commit(message: "From terminal", paths: model.exportProject().files.keys.sorted()))
        try await wait(model)
        XCTAssertEqual(model.gitHistory.first?.message, "From terminal", model.gitMessage)
        XCTAssertEqual(model.gitHistory.first?.author, "Terminal User")
        model.source += "\n// uncommitted"
        model.performGitCommand(.diff(model.selectedFile))
        XCTAssertTrue(model.gitConsoleEvent?.isError == true, "A stale terminal operation needs an explicit result")
        model.refreshGit(); try await wait(model)
        model.switchGitBranch("missing")
        XCTAssertTrue(model.gitMessage.contains("commit or restore"))
        XCTAssertTrue(model.source.contains("uncommitted"))
    }

    func testGitTerminalParserPreservesPathsAndRejectsUnimplementedCommands() throws {
        XCTAssertEqual(try ProjectGitCommand.parse(["commit", "-m", "Keep Case", "--", "src/MyFile.rs"]), .commit(message: "Keep Case", paths: ["src/MyFile.rs"]))
        XCTAssertEqual(try ProjectGitCommand.parse(["restore", "--source", String(repeating: "a", count: 40), "--", "src/MyFile.rs"]), .restore(commit: String(repeating: "a", count: 40), path: "src/MyFile.rs"))
        XCTAssertEqual(try ProjectGitCommand.parse(["config", "user.name", "My Name"]), .identity(key: "user.name", value: "My Name"))
        for args in [["clone", "https://example.invalid"], ["add", "."], ["commit", "-a"], ["status", "--porcelain"], ["config", "credential.helper", "exec"]] {
            XCTAssertThrowsError(try ProjectGitCommand.parse(args))
        }
    }

    func testDeletingDuringBackgroundInitializationCannotLeaveResurrectedHistory() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "GitWorkspace-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = ProjectLibrary(storageURL: root.appending(path: "recent.json"))
        let model = CompilerViewModel(projectLibrary: library)
        model.createProject(name: "delete-git", template: .hello)
        await model.retryProjectSave()
        let id = model.projectID
        model.initializeGit()
        let removed = await model.deleteProject(projectID: id)
        XCTAssertTrue(removed)
        try await Task.sleep(for: .milliseconds(700))
        let old = try await library.project(id: id)
        XCTAssertNil(old)
        let store = GitRepositoryStore(root: library.gitStorageURL)
        let remains = try await store.exists(id)
        XCTAssertFalse(remains)
    }

    private func wait(_ model: CompilerViewModel) async throws {
        let started = ContinuousClock.now
        while model.gitIsWorking {
            if started.duration(to: .now) > .seconds(60) { XCTFail("Git did not release its worker"); return }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
