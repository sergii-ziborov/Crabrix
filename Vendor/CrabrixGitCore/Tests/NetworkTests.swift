import XCTest
import Foundation
@testable import CrabrixGit

@MainActor
final class NetworkTests: XCTestCase {
    func testHTTPSAddressRejectsSecretsAndOtherTransports() throws {
        XCTAssertEqual(try GitHTTPSAddress.canonical("https://github.com/octocat/Hello-World"), "https://github.com/octocat/Hello-World.git")
        for value in ["http://github.com/a/b", "ssh://github.com/a/b", "file:///tmp/repo", "https://token@github.com/a/b", "https://github.com/a/b?token=secret", "https://github.com/a/b#secret", "https://evil.example/a/b", "https://github.com/a/%2e%2e/b", "https://github.com:8443/a/b"] {
            XCTAssertThrowsError(try GitHTTPSAddress.canonical(value))
        }
    }

    func testRealPublicHTTPSCloneAndFetchDoNotExecuteOrReplaceSource() async throws {
        guard ProcessInfo.processInfo.environment["CRABRIX_GIT_NETWORK_QA"] == "1" else { throw XCTSkip("Explicit real-network qualification only") }
        let root = FileManager.default.temporaryDirectory.appending(path: "GitHTTPS-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GitRepositoryStore(root: root), id = UUID()
        let clone = try await store.clone(id, url: "https://github.com/octocat/Hello-World.git")
        XCTAssertFalse(clone.snapshot.files.isEmpty)
        XCTAssertNotNil(clone.state.head)
        let fetched = try await store.fetch(id, expectedRevision: clone.state.revision)
        XCTAssertEqual(fetched.head, clone.state.head)
        let tree = try await store.tree(id, commit: fetched.head!)
        XCTAssertEqual(tree.files, clone.snapshot.files)
        let remote = try await store.remoteState(id)
        XCTAssertEqual(remote?.ahead, 0); XCTAssertEqual(remote?.behind, 0)
    }

    func testCancellationDuringRealHTTPSLeavesNoPartialRepositoryAndAllowsNextClone() async throws {
        guard ProcessInfo.processInfo.environment["CRABRIX_GIT_NETWORK_QA"] == "1" else { throw XCTSkip("Explicit real-network qualification only") }
        let root = FileManager.default.temporaryDirectory.appending(path: "GitCancel-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GitRepositoryStore(root: root), cancelledID = UUID()
        let started = ContinuousClock.now
        let job = Task { try await store.clone(cancelledID, url: "https://github.com/tokio-rs/tokio.git") }
        try await Task.sleep(for: .milliseconds(100)); job.cancel()
        do { _ = try await job.value; XCTFail("In-flight clone must stop") } catch { }
        XCTAssertLessThan(started.duration(to: .now), .seconds(12))
        let exists = try await store.exists(cancelledID)
        XCTAssertFalse(exists)
        let next = try await store.clone(UUID(), url: "https://github.com/octocat/Hello-World.git")
        XCTAssertNotNil(next.state.head)
    }

    func testPrivateHTTPSRoundTripAndRejectedOperationsPreserveHistory() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let url = environment["CRABRIX_GIT_QA_URL"], let username = environment["CRABRIX_GIT_QA_USER"], let token = environment["CRABRIX_GIT_QA_TOKEN"] else { throw XCTSkip("Temporary private GitHub fixture credentials required") }
        let credential = try GitHTTPSCredential(username: username, token: token)
        XCTAssertFalse(String(reflecting: credential).contains(token))
        let root = FileManager.default.temporaryDirectory.appending(path: "GitPrivate-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GitRepositoryStore(root: root), a = UUID(), b = UUID()
        let originalA = try await store.clone(a, url: url, credential: credential)
        let originalB = try await store.clone(b, url: url, credential: credential)
        var aFiles = originalA.snapshot.files
        aFiles["main.rs"] = "fn main(){println!(\"private native Git \(UUID().uuidString)\");}\n"
        aFiles[".rustfmt.toml"] = "max_width=100\n"
        let binary = Data([0, 255, 128, UInt8.random(in: 0...255), 0])
        try binary.write(to: root.appending(path: a.uuidString.lowercased() + "/worktree/asset.bin"))
        let preparedA = try await store.status(a, files: aFiles, expectedRevision: originalA.state.revision)
        let aCommit = try await store.commit(a, files: aFiles, selected: preparedA.changes.map(\.path), author: "Crabrix QA", email: "qa@example.invalid", message: "Offline client A", expectedHead: originalA.state.head, expectedRevision: preparedA.revision)
        var aState = try await store.push(a, credential: credential, expectedHead: aCommit.commit.id, expectedRevision: aCommit.state.revision)
        let bFetched = try await store.fetch(b, credential: credential, expectedRevision: originalB.state.revision)
        XCTAssertEqual(bFetched.head, originalB.state.head, "Fetch cannot move the local branch")
        let bWorktree = root.appending(path: b.uuidString.lowercased() + "/worktree")
        XCTAssertEqual(try? Data(contentsOf: bWorktree.appending(path: "main.rs")), originalB.snapshot.files["main.rs"].map { Data($0.utf8) }, "Fetch must preserve existing file bytes too")
        var dirty = originalB.snapshot.files; dirty["private-notes.txt"] = "Keep me"
        do { _ = try await store.fastForward(b, files: dirty, expectedHead: originalB.state.head!, expectedRevision: bFetched.revision); XCTFail("Dirty fast-forward was accepted") }
        catch { XCTAssertTrue(error.localizedDescription.contains("clean")) }
        let bUpdated = try await store.fastForward(b, files: originalB.snapshot.files, expectedHead: originalB.state.head!, expectedRevision: bFetched.revision)
        XCTAssertEqual(bUpdated.state.head, aCommit.commit.id)
        XCTAssertEqual(bUpdated.snapshot.files, aFiles)
        XCTAssertEqual(try Data(contentsOf: bWorktree.appending(path: "asset.bin")), binary)
        var bFiles = bUpdated.snapshot.files; bFiles["main.rs"] = "fn main(){println!(\"client B\");}\n"
        let bCommit = try await store.commit(b, files: bFiles, selected: ["main.rs"], author: "Crabrix QA", email: "qa@example.invalid", message: "Client B continuation", expectedHead: bUpdated.state.head, expectedRevision: bUpdated.state.revision)
        _ = try await store.push(b, credential: credential, expectedHead: bCommit.commit.id, expectedRevision: bCommit.state.revision)
        aFiles["main.rs"] = "fn main(){println!(\"offline divergent A\");}\n"
        let divergent = try await store.commit(a, files: aFiles, selected: ["main.rs"], author: "Crabrix QA", email: "qa@example.invalid", message: "Divergent A", expectedHead: aState.head, expectedRevision: aState.revision)
        aState = try await store.fetch(a, credential: credential, expectedRevision: divergent.state.revision)
        let relation = try await store.remoteState(a)
        XCTAssertEqual(relation?.ahead, 1); XCTAssertEqual(relation?.behind, 1)
        do { _ = try await store.fastForward(a, files: aFiles, expectedHead: divergent.commit.id, expectedRevision: aState.revision); XCTFail("Divergent history must not merge/overwrite") }
        catch { XCTAssertTrue(error.localizedDescription.contains("diverged")) }
        do { _ = try await store.push(a, credential: credential, expectedHead: divergent.commit.id, expectedRevision: aState.revision); XCTFail("Non-fast-forward push must fail") }
        catch { XCTAssertFalse(error.localizedDescription.contains(token)) }
        let intact = try await store.inspect(a)
        XCTAssertEqual(intact.head, divergent.commit.id)
        XCTAssertEqual(intact.revision, aState.revision)
        let invalid = try GitHTTPSCredential(username: username, token: "crabrix-invalid-qa-token")
        let denied = UUID()
        do { _ = try await store.clone(denied, url: url, credential: invalid); XCTFail("Invalid private access was accepted") }
        catch { XCTAssertFalse(error.localizedDescription.contains(token)) }
        let installed = try await store.exists(denied)
        XCTAssertFalse(installed)
        let cancellation = Task { try await store.fetch(a, credential: credential, expectedRevision: aState.revision) }
        cancellation.cancel()
        do { _ = try await cancellation.value; XCTFail("Pre-cancelled fetch must stop") } catch { }
        let afterCancel = try await store.inspect(a)
        XCTAssertEqual(afterCancel.head, divergent.commit.id)
        let config = try String(contentsOf: root.appending(path: a.uuidString.lowercased() + "/repo/config"), encoding: .utf8)
        XCTAssertFalse(config.contains(token)); XCTAssertFalse(config.contains("crabrix-invalid-qa-token"))
    }
}
