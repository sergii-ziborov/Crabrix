import XCTest
@testable import Crabrix

@MainActor
final class PlaygroundModelTests: XCTestCase {
    func testNearbyParticipantBadgesStayInsideCanvasWithoutCoveringEachOther() throws {
        for width in [CGFloat(240), 402, 1024] {
            let bounds = CGRect(x: 0, y: 0, width: width, height: 200)
            var frames: [CGRect] = []
            for nameWidth in [CGFloat(95), 130, 170] {
                let frame = try XCTUnwrap(PlaygroundSelectionOverlay.badgeFrame(
                    preferred: CGRect(x: width - 60, y: 0, width: nameWidth, height: 16), inside: bounds, occupied: frames))
                XCTAssertTrue(bounds.contains(frame))
                XCTAssertTrue(frames.allSatisfy { !$0.intersects(frame) })
                frames.append(frame)
            }
        }
        XCTAssertNil(PlaygroundSelectionOverlay.badgeFrame(preferred: CGRect(x: 0, y: 0, width: 120, height: 16), inside: .zero, occupied: []))
    }
    func testFragmentsStayOutOfHTTPAndNativeCodecRoundTripsUnicode() throws {
        let link = PlaygroundLink(id: String(repeating: "a", count: 24), key: PlaygroundEncryption.newSecret(), access: PlaygroundEncryption.newSecret(), expiresAt: Date(timeIntervalSince1970: 1793200000), isReadOnly: true)
        XCTAssertEqual(try PlaygroundLink.parse(link.url.absoluteString), link)
        XCTAssertNil(URLComponents(url: link.url, resolvingAgainstBaseURL: false)?.query)
        XCTAssertThrowsError(try PlaygroundLink.parse("https://evil.example/playground/room/" + link.id + "/#" + (link.url.fragment ?? "")))
        let source = try PlaygroundDocument(name: "Unicode", entryFile: "main.rs", files: ["main.rs": "fn main() { println!(\"🦀 Привет\"); }"]).validated()
        let codec = try PlaygroundCodec(); _ = try codec.initialize(source)
        let snapshot = try XCTUnwrap(try codec.call(["type": "snapshot"]).snapshot)
        let packet = try PlaygroundEncryption.seal(Data(snapshot), secret: link.key)
        let restored = try PlaygroundEncryption.open(packet, secret: link.key)
        let other = try PlaygroundCodec()
        XCTAssertEqual(try other.call(["type": "state", "snapshot": Array(restored), "events": []]).document, source)
        XCTAssertThrowsError(try PlaygroundEncryption.open(packet, secret: PlaygroundEncryption.newSecret()))
    }

    func testNativeCodecKeepsSourceOriginsWithoutBrowserGlobalsAndRejectsCredentials() throws {
        for url in ["https://github.com/octocat/Hello-World", "https://gist.github.com/example/0123456789abcdef", "https://play.rust-lang.org/?version=stable&edition=2024"] {
            let source = PlaygroundDocument(name: "origin", entryFile: "main.rs", files: ["main.rs": "fn main() {}"], origin: .init(url: url))
            let first = try PlaygroundCodec()
            XCTAssertEqual(try first.initialize(source).document?.origin, source.origin)
            let snapshot = try XCTUnwrap(try first.call(["type": "snapshot"]).snapshot)
            let second = try PlaygroundCodec()
            XCTAssertEqual(try second.call(["type": "state", "snapshot": snapshot, "events": []]).document?.origin, source.origin)
        }
        let codec = try PlaygroundCodec()
        let invalid: [String: Any] = ["schemaVersion": 1, "name": "invalid", "entryFile": "main.rs", "edition": "2024", "files": ["main.rs": "fn main() {}"]]
        for origin in ["https://user:password@github.com/repository", "https://evil.example/repository", "http://github.com/repository"] {
            var document = invalid; document["origin"] = ["url": origin]
            XCTAssertThrowsError(try codec.call(["type": "initialize", "document": document]))
        }
    }
    func testConcurrentEditsAndSelectionsUseStableTextPositions() throws {
        let first = try PlaygroundCodec(), second = try PlaygroundCodec()
        _ = try first.initialize(PlaygroundDocument(name: "merge", entryFile: "main.rs", files: ["main.rs": "hello 🦀 world"]))
        let snapshot = try XCTUnwrap(try first.call(["type": "snapshot"]).snapshot)
        _ = try second.call(["type": "state", "snapshot": snapshot, "events": []])
        let selection = try XCTUnwrap(try second.call(["type": "selection", "file": "main.rs", "anchor": 6, "head": 8]).presence)
        _ = try first.call(["type": "presence", "bytes": selection])
        let left = try XCTUnwrap(try first.call(["type": "file", "path": "main.rs", "text": "prefix hello 🦀 world"]).update)
        let right = try XCTUnwrap(try second.call(["type": "file", "path": "main.rs", "text": "hello 🦀 world suffix"]).update)
        let a = try first.call(["type": "update", "bytes": right])
        let b = try second.call(["type": "update", "bytes": left])
        XCTAssertEqual(a.document, b.document)
        XCTAssertEqual(a.document?.files["main.rs"], "prefix hello 🦀 world suffix")
        XCTAssertEqual(a.selections?.first?.anchor, 13)
        XCTAssertEqual(a.selections?.first?.head, 15)
    }
    func testChangingAnEmojiDoesNotSplitItsUTF16Pair() throws {
        let codec = try PlaygroundCodec()
        _ = try codec.initialize(PlaygroundDocument(name: "emoji", entryFile: "main.rs", files: ["main.rs": "🦀 Rust 🦀"]))
        let changed = try codec.call(["type": "file", "path": "main.rs", "text": "🦁 Rust 🦑"])
        XCTAssertEqual(changed.document?.files["main.rs"], "🦁 Rust 🦑")
    }
    func testNativeCopyKeepsA2021SnippetsEditionWithoutChangingRoomFiles() throws {
        let document = try PlaygroundDocument(name: "edition", entryFile: "src/main.rs", files: ["src/main.rs": "fn main() { let gen = 1; println!(\"{gen}\"); }"], edition: "2021").validated()
        XCTAssertNil(document.files["Cargo.toml"])
        let local = document.nativeFiles
        XCTAssertEqual(local["src/main.rs"], document.files["src/main.rs"])
        XCTAssertTrue(local["Cargo.toml"]?.contains("edition = \"2021\"") == true)
        XCTAssertEqual(local["Cargo.toml"].flatMap(CargoManifest.parse)?.edition, "2021")
        XCTAssertTrue(local["Cargo.toml"]?.contains("path = \"src/main.rs\"") == true)
        let existing = PlaygroundDocument(name: "existing", entryFile: "main.rs", files: ["main.rs": "fn main(){}", "Cargo.toml": "original manifest"], edition: "2021")
        XCTAssertEqual(existing.nativeFiles["Cargo.toml"], "original manifest")
    }
    func testSourceLimitsAreUTF8AndTraversalIsRejected() throws {
        XCTAssertThrowsError(try PlaygroundDocument(name: "no", entryFile: "../main.rs", files: ["../main.rs": "fn main(){}"] ).validated())
        XCTAssertThrowsError(try PlaygroundDocument(name: "no", entryFile: "main.rs", files: ["main.rs": String(repeating: "🦀", count: 17000)] ).validated())
    }

    func testSharedEditAndDeletionRetainLocalConfigurationPreparedPackagesAndUnicode() throws {
        let privateFiles = [".cargo/config.toml": "[alias]\nc = 'check'\n", "vendor/parser/src/lib.rs": "pub const LOCAL: &str = \"private 🦀\";",
                            "node_modules/types/index.d.ts": "export type Local = string;", ".github/workflows/test.yml": "name: local"]
        var local = privateFiles
        local["main.rs"] = "fn main() {}"; local["old.rs"] = "old shared source"
        let shared = PlaygroundDocument(name: "updated", entryFile: "main.rs", files: ["main.rs": "fn main() { println!(\"new 🦀\"); }"])
        let merged = try PlaygroundLocalFiles.merging(shared, into: local)
        for (path, text) in privateFiles { XCTAssertEqual(merged[path], text) }
        XCTAssertEqual(merged["main.rs"], shared.files["main.rs"])
        XCTAssertNil(merged["old.rs"], "An actual deletion in the shared tree still applies")
        XCTAssertEqual(PlaygroundLocalFiles.sharedFiles(in: merged), shared.files)
        XCTAssertEqual(local["old.rs"], "old shared source", "Constructing the replacement cannot mutate the old snapshot")
    }

    func testSharedMergeKeepsEditionAndDoesNotMistakeSimilarRootNamesForPrivateFiles() throws {
        let shared = PlaygroundDocument(name: "edition", entryFile: "src/main.rs", files: ["src/main.rs": "fn main() {}"], edition: "2021")
        let merged = try PlaygroundLocalFiles.merging(shared, into: [".cargo/config.toml": "[alias]", "vendor-notes.txt": "old shared note", "src/main.rs": "old"])
        XCTAssertEqual(merged[".cargo/config.toml"], "[alias]")
        XCTAssertNil(merged["vendor-notes.txt"])
        XCTAssertTrue(merged["Cargo.toml"]?.contains("edition = \"2021\"") == true)
    }

    func testOverBudgetSharedMergeLeavesAllExistingLocalFilesAvailable() throws {
        var local = Dictionary(uniqueKeysWithValues: (0..<2047).map { ("vendor/local/file\($0).txt", "local \($0)") })
        local["main.rs"] = "fn main() {}"
        let before = local
        let shared = PlaygroundDocument(name: "new", entryFile: "main.rs", files: ["main.rs": "fn main() { println!(\"new\"); }", "extra.rs": "pub const N: u8 = 1;"])
        try ProjectFilePolicy.validate(local)
        XCTAssertThrowsError(try PlaygroundLocalFiles.merging(shared, into: local))
        XCTAssertEqual(local, before)
    }

    func testRealCodecRemoteEditRetainsPrivateFilesAfterStoreReopenAndEditableExport() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var project = CrabrixProject(name: "shared-local", files: ["main.rs": "fn main() {}", ".cargo/config.toml": "[alias]\nc = 'check'\n",
            "vendor/parser/src/lib.rs": "pub const LOCAL: u8 = 7;", "node_modules/types/index.d.ts": "export type Local = string;"], entryFile: "main.rs", provenance: nil)
        let before = project.files
        let store = ProjectStore(rootURL: root)
        _ = try await store.save(project: project, lastBuild: nil)
        let local = try PlaygroundCodec(), remote = try PlaygroundCodec()
        _ = try local.initialize(PlaygroundDocument(name: project.name, entryFile: project.entryFile, files: PlaygroundLocalFiles.sharedFiles(in: before)))
        let snapshot = try XCTUnwrap(try local.call(["type": "snapshot"]).snapshot)
        _ = try remote.call(["type": "state", "snapshot": snapshot, "events": []])
        let delta = try XCTUnwrap(try remote.call(["type": "file", "path": "main.rs", "text": "fn main() { println!(\"received 🦀\"); }"]).update)
        let received = try XCTUnwrap(try local.call(["type": "update", "bytes": delta]).document)
        XCTAssertEqual(Set(received.files.keys), ["main.rs"], "Private source must never enter the shared codec")
        project.files = try PlaygroundLocalFiles.merging(received, into: before)
        _ = try await store.save(project: project, lastBuild: nil)
        let reopened = try await ProjectStore(rootURL: root).project(id: project.id)
        XCTAssertEqual(reopened?.project, project)
        let package = root.appending(path: "copy.crabrixproject")
        try CrabrixProjectDocument(project: project).packageWrapper().write(to: package, options: .atomic, originalContentsURL: nil)
        let copy = try LocalProjectLoader.load(from: package)
        XCTAssertEqual(copy.files, project.files)
        XCTAssertEqual(copy.files[".cargo/config.toml"], before[".cargo/config.toml"])
        XCTAssertEqual(copy.files["vendor/parser/src/lib.rs"], before["vendor/parser/src/lib.rs"])
        XCTAssertEqual(copy.files["node_modules/types/index.d.ts"], before["node_modules/types/index.d.ts"])
        XCTAssertEqual(copy.files["main.rs"], received.files["main.rs"])
    }
}
