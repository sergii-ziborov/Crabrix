import XCTest
import ZIPFoundation
import CrabrixGit
@testable import Crabrix

@MainActor
final class GitTransferTests: XCTestCase {
    func testNativeArchiveRoundTripKeepsCommitIDsBinaryFilesAndMetadata() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "GitArchiveQA-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GitRepositoryStore(root: root), a = UUID(), b = UUID()
        let files = ["main.rs": "fn main(){println!(\"crab\");}\n", ".rustfmt.toml": "max_width=100\n", "run.sh": "echo crab\n"]
        let initialized = try await store.initialize(a, files: files)
        let worktree = root.appending(path: a.uuidString.lowercased() + "/worktree")
        let binary = Data([0,255,17,0,127])
        try binary.write(to: worktree.appending(path: "asset.bin"))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: worktree.appending(path: "run.sh").path)
        let committed = try await store.commit(a, files: files, selected: Array(files.keys) + ["asset.bin"], author: "QA", email: "qa@example.invalid", message: "Archive fixture", expectedHead: nil, expectedRevision: initialized.revision)
        let branch = try await store.createBranch(a, name: "lesson-copy", expectedHead: committed.commit.id, expectedRevision: committed.state.revision)
        let copy = try await store.exportCopy(a, files: files, expectedRevision: branch.revision)
        defer { try? FileManager.default.removeItem(at: copy.directory) }
        let project = CrabrixProject(id: a, name: "portable-crab", files: files, entryFile: "main.rs", provenance: nil,
            projectDescription: "Preserved metadata", tags: ["practice"], folder: "Learning", kind: .learning)
        let archive = try await GitRepositoryTransfer.create(copy: copy, project: project)
        defer { try? FileManager.default.removeItem(at: archive.deletingLastPathComponent()) }
        let prepared = try await GitRepositoryTransfer.unpack(archive)
        defer { try? FileManager.default.removeItem(at: prepared.directory) }
        XCTAssertEqual(prepared.envelope.project.projectDescription, "Preserved metadata")
        XCTAssertEqual(prepared.envelope.project.projectID, a)
        let imported = try await store.importCopy(b, directory: prepared.directory, origin: prepared.envelope.origin)
        XCTAssertEqual(imported.state.head, committed.commit.id)
        XCTAssertEqual(imported.snapshot.files, files)
        try ProjectFilePolicy.verify(prepared.envelope.project.fileDigests, files: imported.snapshot.files)
        let resources = try await store.resources(b, files: imported.snapshot.files)
        XCTAssertEqual(resources, ["asset.bin": binary])
        let branches = try await store.branches(b)
        XCTAssertEqual(branches, ["lesson-copy", "main"])
        let importedWorktree = root.appending(path: b.uuidString.lowercased() + "/worktree")
        let mode = try FileManager.default.attributesOfItem(atPath: importedWorktree.appending(path: "run.sh").path)[.posixPermissions] as? Int ?? 0
        XCTAssertNotEqual(mode & 0o111, 0)
        // Altering a file after manifest generation must fail the byte inventory.
        let altered = try Archive(url: archive, accessMode: .update)
        let bytes = Data("unlisted".utf8)
        try altered.addEntry(with: "worktree/unlisted.txt", type: .file, uncompressedSize: Int64(bytes.count)) { offset, size in
            bytes.subdata(in: Int(offset)..<min(bytes.count, Int(offset) + size))
        }
        do { let unexpected = try await GitRepositoryTransfer.unpack(archive); try? FileManager.default.removeItem(at: unexpected.directory); XCTFail("An unlisted file was accepted") }
        catch { XCTAssertTrue(error.localizedDescription.contains("inventory")) }
    }

    func testTraversalAndCaseCollisionAreRejectedBeforeExtraction() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "GitArchiveBadQA-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for (index, paths) in [["../escaped"], ["worktree/A.rs", "worktree/a.rs"], ["worktree/a", "worktree/a/file.rs"]].enumerated() {
            let archiveURL = root.appending(path: "bad-\(index).crabrixrepo")
            let archive = try Archive(url: archiveURL, accessMode: .create)
            for path in paths {
                let bytes = Data("invalid".utf8)
                try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(bytes.count)) { offset, size in
                    bytes.subdata(in: Int(offset)..<min(bytes.count, Int(offset) + size))
                }
            }
            do { let result = try await GitRepositoryTransfer.unpack(archiveURL); try? FileManager.default.removeItem(at: result.directory); XCTFail("An unsafe archive was extracted") }
            catch { XCTAssertTrue(error.localizedDescription.contains("path") || error.localizedDescription.contains("collision")) }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.deletingLastPathComponent().appending(path: "escaped").path))
    }

    func testCompilerUsesOpaqueBytesAndInvalidatesArtifactCacheWhenTheyChange() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "CompilerResourceQA-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let compiler = WasmRustCompiler(projectArtifactRoot: root)
        let source = "fn main(){let bytes=include_bytes!(\"asset.bin\");println!(\"{:?}\",bytes);}\n"
        let first = await compiler.run(source: source, resourceFiles: ["asset.bin": Data([0,255,7])])
        XCTAssertTrue(first.succeeded, first.stderr + first.detail)
        XCTAssertEqual(first.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "[0, 255, 7]")
        let second = await compiler.run(source: source, resourceFiles: ["asset.bin": Data([0,255,9])])
        XCTAssertTrue(second.succeeded, second.stderr + second.detail)
        XCTAssertEqual(second.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "[0, 255, 9]")
        let repeated = await compiler.run(source: source, resourceFiles: ["asset.bin": Data([0,255,9])])
        XCTAssertTrue(repeated.succeeded)
        XCTAssertTrue(repeated.detail.contains("cached"), repeated.detail)
        let unsafe = await compiler.run(source: source, resourceFiles: ["../outside": Data([0])])
        XCTAssertFalse(unsafe.succeeded)
        XCTAssertEqual(unsafe.phase, .setup)
    }

    func testAppSaveExportImportAndRunKeepOpaqueInputsAndInvalidateOldBuildEvidence() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "GitAppResourcesQA-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = ProjectLibrary(storageURL: root.appending(path: "recent.json"))
        let model = CompilerViewModel(projectLibrary: library)
        model.createProject(name: "resource-app", template: .hello)
        model.source = "fn main(){let data=include_bytes!(\"../asset.bin\");println!(\"{:?}\",data);}\n"
        var files = model.exportProject().files
        files["web/index.html"] = "<!doctype html><html><body><img src=\"pixel.png\" alt=\"Pixel\"></body></html>"
        XCTAssertTrue(model.replaceProjectFilesFromTerminal(files))
        model.initializeGit(); try await waitGit(model)
        let id = model.projectID, worktree = library.gitStorageURL.appending(path: id.uuidString.lowercased() + "/worktree")
        let png = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jDRkAAAAASUVORK5CYII="))
        try Data([1,0,255]).write(to: worktree.appending(path: "asset.bin"))
        try png.write(to: worktree.appending(path: "web/pixel.png"))
        model.refreshGit(); try await waitGit(model)
        model.commitGit(paths: model.gitState!.changes.map(\.path), author: "QA", email: "qa@example.invalid", message: "Resources")
        try await waitGit(model)
        model.run(); try await waitBuild(model)
        XCTAssertTrue(model.result?.succeeded == true, model.result?.detail ?? "missing result")
        XCTAssertEqual(model.result?.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "[1, 0, 255]")
        XCTAssertEqual(model.result?.webPreview?.assets["web/pixel.png"], png)
        XCTAssertNotNil(model.lastBuild?.resourceTreeHash)
        await model.retryProjectSave()
        let saved = try await library.project(id: id)
        XCTAssertTrue(saved?.currentBuild?.succeeded == true)
        try Data([2,0,255]).write(to: worktree.appending(path: "asset.bin"))
        model.refreshGit(); try await waitGit(model)
        model.commitGit(paths: ["asset.bin"], author: "QA", email: "qa@example.invalid", message: "Changed binary")
        try await waitGit(model)
        let invalidated = try await library.project(id: id)
        XCTAssertNil(invalidated?.currentBuild, "A changed binary must invalidate proof for identical Rust text")
        model.run(); try await waitBuild(model)
        XCTAssertEqual(model.result?.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "[2, 0, 255]")
        await model.retryProjectSave()
        model.exportGitRepository(); try await waitGit(model)
        let archive = try XCTUnwrap(model.gitArchiveURL, model.gitMessage)
        defer { try? FileManager.default.removeItem(at: archive.deletingLastPathComponent()) }
        XCTAssertTrue(model.gitArchiveIsCurrent)
        let originalHead = model.gitState?.head
        await model.importGitRepository(from: archive)
        XCTAssertNotEqual(model.projectID, id, model.gitMessage)
        XCTAssertEqual(model.gitState?.head, originalHead)
        model.run(); try await waitBuild(model)
        XCTAssertEqual(model.result?.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "[2, 0, 255]")
        XCTAssertEqual(model.result?.webPreview?.assets["web/pixel.png"], png)
        let original = try await library.project(id: id)
        XCTAssertNotNil(original, "Import must preserve the original project too")
    }

    private func waitGit(_ model: CompilerViewModel) async throws {
        let began = ContinuousClock.now
        while model.gitIsWorking {
            guard began.duration(to: .now) < .seconds(60) else { XCTFail("Git did not finish"); return }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
    private func waitBuild(_ model: CompilerViewModel) async throws {
        let began = ContinuousClock.now
        while model.isBusy || model.isCompilerDraining {
            guard began.duration(to: .now) < .seconds(60) else { XCTFail("Local compilation did not finish"); model.cancelBuild(); return }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
