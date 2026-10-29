import XCTest
@testable import Crabrix

@MainActor
final class PlaygroundRuntimeProtocolTests: XCTestCase {
    private typealias Wire = PlaygroundRuntimeProtocol
    private let now: Int64 = 1_000_000
    private let room = String(repeating: "a", count: 24), target = String(repeating: "b", count: 64)
    // Public interoperability vector. This is an artificial capability, never a room credential.
    private let capability = String(repeating: "A", count: 43)
    private var fields: Wire.Fields { .init(kind: "command", room: room, target: target, requestID: "runtime-request-0001", operation: "check", revision: String(repeating: "c", count: 64)) }
    private var context: Wire.VerificationContext { .init(room: room, target: target, editCapability: capability, requireEditProof: true) }
    private let payload = Data("{\"text\":\"🦀 Привет\"}".utf8)
    private func signed(_ signer: PlaygroundRuntimeSigner, at time: Int64? = nil) throws -> Data {
        try signer.sign(fields, payload: payload, editCapability: capability, now: time ?? now)
    }
    private func altered(_ original: Data, _ edit: (inout [String: Any]) -> Void) throws -> Data {
        var value = try XCTUnwrap(try JSONSerialization.jsonObject(with: original) as? [String: Any]); edit(&value)
        return try JSONSerialization.data(withJSONObject: value)
    }

    func testActualWebCryptoVectorVerifiesInNativeCryptoKit() throws {
        let vector = Data(webCryptoVector.utf8)
        let frame = try Wire.verify(vector, context: context, clock: { now })
        XCTAssertEqual(String(data: frame.payload, encoding: .utf8), "{\"text\":\"WebCrypto → CryptoKit 🦀\"}")
        XCTAssertEqual(frame.header.operation, "check")
        XCTAssertEqual(frame.header.requestID, "signed-vector-0001")
        XCTAssertTrue(frame.editAccessProved)
        XCTAssertEqual(frame.header.issued, now)
        var wrong = context; wrong.editCapability = PlaygroundEncryption.newSecret()
        XCTAssertThrowsError(try Wire.verify(vector, context: wrong, clock: { now }))
    }

    func testNativeSignerUsesRawKeysSignaturesAndOwnedUnicodeBytes() throws {
        let signer = PlaygroundRuntimeSigner(), data = try signed(signer)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Data(base64URL: try XCTUnwrap(object["key"] as? String))?.count, 65)
        XCTAssertEqual(Data(base64URL: try XCTUnwrap(object["signature"] as? String))?.count, 64)
        XCTAssertEqual(Data(base64URL: try XCTUnwrap(object["editProof"] as? String))?.count, 32)
        let frame = try Wire.verify(data, context: context, clock: { now })
        XCTAssertEqual(frame.payload, payload); XCTAssertEqual(frame.header.sender, signer.fingerprint)
        XCTAssertTrue(frame.editAccessProved)
        let withoutProof = try signer.sign(fields, payload: payload, now: now)
        XCTAssertFalse(try Wire.verify(withoutProof, context: .init(room: room, target: target), clock: { now }).editAccessProved)
        signer.destroy()
        XCTAssertThrowsError(try signed(signer))
    }

    func testSignedRuntimePresenceRetainsSelectionsAndDoesNotChangeSourceSnapshots() throws {
        let source = PlaygroundDocument(name: "presence", entryFile: "main.rs", files: ["main.rs": "fn main() { println!(\"🦀\"); }"])
        let first = try PlaygroundCodec(), second = try PlaygroundCodec()
        _ = try first.initialize(source)
        let snapshot = try XCTUnwrap(try first.call(["type": "snapshot"]).snapshot)
        _ = try second.call(["type": "state", "snapshot": snapshot, "events": []])
        _ = try first.call(["type": "selection", "file": "main.rs", "anchor": 22, "head": 24])
        let signer = PlaygroundRuntimeSigner()
        let envelope = try signed(signer)
        let object = try JSONSerialization.jsonObject(with: envelope)
        let outgoing = try XCTUnwrap(try first.call(["type": "runtime-presence", "envelope": object]).presence)
        XCTAssertLessThanOrEqual(outgoing.count, 4_000)
        let received = try second.call(["type": "presence", "bytes": outgoing])
        let frame = try XCTUnwrap(received.runtimeFrames?.first)
        XCTAssertEqual(try Wire.verify(Data(frame.envelope.utf8), context: context, clock: { now }).payload, payload)
        XCTAssertTrue(received.selections?.contains(where: { $0.anchor == 22 && $0.head == 24 }) == true)
        XCTAssertEqual(try first.call(["type": "snapshot"]).snapshot, snapshot)
        XCTAssertEqual(try second.runtimeSourceIdentity(), try first.runtimeSourceIdentity())
        let cleared = try XCTUnwrap(try first.call(["type": "runtime-presence", "envelope": NSNull()]).presence)
        let after = try second.call(["type": "presence", "bytes": cleared])
        XCTAssertEqual(after.runtimeFrames, [])
        XCTAssertTrue(after.selections?.contains(where: { $0.anchor == 22 && $0.head == 24 }) == true)
        signer.destroy()
    }

    func testOversizedRuntimePresenceCannotReplaceAnExistingSelectionOrSource() throws {
        let codec = try PlaygroundCodec()
        let source = PlaygroundDocument(name: "retained", entryFile: "main.rs", files: ["main.rs": "fn main() {}"])
        _ = try codec.initialize(source)
        _ = try codec.call(["type": "selection", "file": "main.rs", "anchor": 0, "head": 3])
        XCTAssertThrowsError(try codec.call(["type": "runtime-presence", "envelope": ["oversized": String(repeating: "🦀", count: 1_000)]]))
        let after = try codec.call(["type": "document"])
        XCTAssertEqual(after.document, source)
        XCTAssertEqual(after.localSelection?.anchor, 0); XCTAssertEqual(after.localSelection?.head, 3)
        XCTAssertEqual(after.runtimeFrames, [])
    }

    func testWrongRoomTargetIdentityPayloadHeaderAndEditProofAreRefused() throws {
        let signer = PlaygroundRuntimeSigner(), original = try signed(signer)
        var wrong = context; wrong.target = String(repeating: "d", count: 64)
        XCTAssertThrowsError(try Wire.verify(original, context: wrong, clock: { now }))
        wrong = .init(room: String(repeating: "d", count: 24))
        XCTAssertThrowsError(try Wire.verify(original, context: wrong, clock: { now }))
        wrong = context; wrong.sender = String(repeating: "d", count: 64)
        XCTAssertThrowsError(try Wire.verify(original, context: wrong, clock: { now }))
        let other = PlaygroundRuntimeSigner()
        let changes: [(inout [String: Any]) -> Void] = [
            { $0["key"] = other.key }, { $0["payload"] = Data("{}".utf8).base64URL },
            { value in var h = value["header"] as! [Any]; h[6] = "run"; value["header"] = h },
            { $0.removeValue(forKey: "editProof") }, { $0["editProof"] = PlaygroundEncryption.newSecret() }
        ]
        for change in changes { XCTAssertThrowsError(try Wire.verify(try altered(original, change), context: context, clock: { now })) }
        signer.destroy(); other.destroy()
    }

    func testTimeAndProofAreRecheckedWithoutAcceptingBooleanOrUnsafeIntegers() throws {
        let signer = PlaygroundRuntimeSigner()
        let short = try signer.sign(fields, payload: payload, editCapability: capability, now: now, lifetime: 100)
        XCTAssertThrowsError(try Wire.verify(short, context: context, clock: { self.now + 100 }))
        var calls = 0
        XCTAssertThrowsError(try Wire.verify(short, context: context, clock: { calls += 1; return self.now + (calls == 1 ? 0 : 100) }))
        XCTAssertThrowsError(try Wire.verify(try signed(signer, at: now + 6_000), context: context, clock: { now }))
        XCTAssertThrowsError(try signer.sign(fields, payload: payload, now: now, lifetime: 15_001))
        XCTAssertThrowsError(try signer.sign(fields, payload: payload, now: Int64.max))
        let good = try signed(signer)
        for badTime: Any in [true, -1, 1.25, 9_007_199_254_740_992 as Int64] {
            let changed = try altered(good) { value in var h = value["header"] as! [Any]; h[10] = badTime; value["header"] = h }
            XCTAssertThrowsError(try Wire.verify(changed, context: context, clock: { now }))
        }
        signer.destroy()
    }

    func testStrictEnvelopeEncodingKindsAndPayloadBudget() throws {
        let signer = PlaygroundRuntimeSigner(), good = try signed(signer)
        let changes: [(inout [String: Any]) -> Void] = [
            { $0["v"] = true }, { $0["extra"] = "not allowed" }, { $0["key"] = 123 }, { $0["editProof"] = NSNull() },
            { $0["signature"] = ($0["signature"] as! String) + "=" },
            { value in var h = value["header"] as! [Any]; h[1] = "capabilities"; value["header"] = h },
            { value in var h = value["header"] as! [Any]; h[9] = String(repeating: "A", count: 42) + "B"; value["header"] = h }
        ]
        for change in changes { XCTAssertThrowsError(try Wire.verify(try altered(good, change), context: context, clock: { now })) }
        XCTAssertThrowsError(try Wire.verify(Data(repeating: 32, count: 2_401), context: context, clock: { now }))
        let exact = Data(("\"" + String(repeating: "a", count: 766) + "\"").utf8)
        XCTAssertEqual(exact.count, Wire.payloadBytes)
        _ = try signer.sign(fields, payload: exact, now: now)
        XCTAssertThrowsError(try signer.sign(fields, payload: Data(("\"" + String(repeating: "a", count: 767) + "\"").utf8), now: now))
        XCTAssertThrowsError(try signer.sign(fields, payload: Data("not JSON".utf8), now: now))
        signer.destroy()
    }

    func testDuplicateMessagesStayDuplicateUnderNonceFloodAndExpiredEntriesArePruned() throws {
        let signer = PlaygroundRuntimeSigner(), replay = PlaygroundRuntimeReplayWindow()
        let first = try Wire.verify(try signed(signer), context: context, clock: { now })
        XCTAssertEqual(try replay.consume(first, now: now), .new)
        XCTAssertEqual(try replay.consume(first, now: now), .duplicate)
        for _ in 1..<Wire.replayEntries {
            let next = try Wire.verify(try signed(signer), context: context, clock: { now })
            XCTAssertEqual(try replay.consume(next, now: now), .new)
        }
        let overflow = try Wire.verify(try signed(signer), context: context, clock: { now })
        XCTAssertThrowsError(try replay.consume(overflow, now: now))
        XCTAssertEqual(try replay.consume(first, now: now), .duplicate)
        let later = now + Wire.lifetimeMilliseconds + 1
        XCTAssertThrowsError(try replay.consume(first, now: later))
        let fresh = try Wire.verify(try signed(signer, at: later), context: context, clock: { later })
        XCTAssertEqual(try replay.consume(fresh, now: later), .new)
        signer.destroy()
    }

    private let webCryptoVector = #"{"v":1,"key":"BJklp5ciV6OfAJLYkAmofu35dfASqSXVngByHdaMIj7KUYkhtSFu4RpAe8hnuX3xPegYtc7SdqqH1ghBVBsBrk4","header":["crabrix-runtime-v1","command","aaaaaaaaaaaaaaaaaaaaaaaa","8834b55504e5ffc7122ee1bbf3f26d6c755110f534345b19ede9158379b9edb9","bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","signed-vector-0001","check","cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","","TnRKZvdXMKcpQIn-HNsM-MyWd_x5jE_TPEzsQ23Et-k",1000000,1015000,"228cf50113bec2fb43a9b0271348bd143365b99d218ee7d3d4e04d1c1c01689e"],"payload":"eyJ0ZXh0IjoiV2ViQ3J5cHRvIOKGkiBDcnlwdG9LaXQg8J-mgCJ9","signature":"5N2ETD5k1H90Zy_Uok19q3Kr0o4Hp4n6pcA7AvEls84sWPZDGu21VFRwoTY8_WUatT-XJAvtZsW6EMHx8t_XDA","editProof":"GMfY2NbnyiZAWmf0XuXpa6E6Fv8ZH8mfXeQ3eNCmqFM"}"#
}
