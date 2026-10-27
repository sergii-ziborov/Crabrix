import XCTest
@testable import Crabrix

@MainActor
final class PlaygroundModelTests: XCTestCase {
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
    func testSourceLimitsAreUTF8AndTraversalIsRejected() throws {
        XCTAssertThrowsError(try PlaygroundDocument(name: "no", entryFile: "../main.rs", files: ["../main.rs": "fn main(){}"] ).validated())
        XCTAssertThrowsError(try PlaygroundDocument(name: "no", entryFile: "main.rs", files: ["main.rs": String(repeating: "🦀", count: 17000)] ).validated())
    }
}
