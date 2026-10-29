import XCTest
@testable import Crabrix

@MainActor
final class PlaygroundRuntimeTransportTests: XCTestCase {
    func testActualNativeHTTPRoleProofAndRuntimePresenceKeepSourceAndUnicodeSelectionUnchanged() async throws {
        guard ProcessInfo.processInfo.environment["CRABRIX_RUN_SHARED_RUNTIME_GATE"] == "1" else {
            throw XCTSkip("Start scripts/probes/playground/runtime-relay.ts and enable the explicit Shared runtime qualification.")
        }
        let origin = URL(string: "http://127.0.0.1:3398")!
        let source = "fn main(){println!(\"private-runtime-sentinel 🦀\");}\n"
        let owner = try await PlaygroundLiveSession.create(document: .init(name: "native-role-proof", entryFile: "main.rs", files: ["main.rs": source]), lifetimeSeconds: 60, origin: origin)
        let tamperedView = PlaygroundLink(id: owner.link.id, key: owner.link.key, access: try XCTUnwrap(owner.viewAccess), expiresAt: owner.link.expiresAt, isReadOnly: false)
        let viewer = try PlaygroundLiveSession(link: tamperedView, origin: origin)
        defer { owner.stop(); viewer.stop() }
        owner.start(); viewer.start()
        try await wait { owner.status.hasPrefix("Connected") && viewer.status.hasPrefix("Connected") }
        let before = try owner.runtimeSourceIdentity()
        XCTAssertFalse(owner.runtimeEditConfirmed); XCTAssertFalse(viewer.runtimeEditConfirmed)
        try await owner.confirmRuntimeEditAccess()
        XCTAssertTrue(owner.runtimeEditConfirmed)
        do { try await viewer.confirmRuntimeEditAccess(); XCTFail("Changing a view URL's mode must never confirm edit access.") }
        catch {
            XCTAssertFalse(viewer.runtimeEditConfirmed)
            XCTAssertEqual((error as? PlaygroundFailure)?.message, "This Playground link is not authorized.", "An unrelated network error must not pass the view-access refusal check.")
        }
        XCTAssertEqual(try owner.runtimeSourceIdentity(), before)
        XCTAssertEqual(try viewer.runtimeSourceIdentity(), before)

        let signer = PlaygroundRuntimeSigner()
        let payload = Data("{\"role\":\"host\",\"name\":\"Crabrix\",\"permissions\":\"off\"}".utf8)
        let envelope = try signer.sign(.init(kind: "capabilities", room: owner.link.id, target: "", requestID: "native-transport-request-01", operation: "discover", revision: before.revision), payload: payload)
        var frames: [PlaygroundCodec.RuntimePresenceFrame] = []
        viewer.onRuntimeFrames = { frames = $0 }
        let crab = (source as NSString).range(of: "🦀")
        owner.select(file: "main.rs", range: crab)
        try owner.publishRuntimePresence(envelope)
        try await wait { !frames.isEmpty && viewer.selections.contains { $0.range == crab } }
        let received = try XCTUnwrap(frames.first)
        let frame = try PlaygroundRuntimeProtocol.verify(Data(received.envelope.utf8), context: .init(room: owner.link.id, sender: signer.fingerprint))
        XCTAssertEqual(frame.payload, payload)
        XCTAssertEqual(try owner.runtimeSourceIdentity(), before)
        XCTAssertEqual(try viewer.runtimeSourceIdentity(), before)
        try owner.publishRuntimePresence(envelope)
        try await wait { frames.first?.clock != received.clock }
        XCTAssertEqual(frames.first?.envelope, received.envelope)
        try await owner.closeRoom()
        XCTAssertFalse(owner.runtimeEditConfirmed)
        try await wait { viewer.expired }
        signer.destroy()
    }

    private func wait(_ predicate: () -> Bool) async throws {
        let limit = Date().addingTimeInterval(20)
        while !predicate() {
            guard Date() < limit else { throw PlaygroundFailure("Timed out waiting for actual native HTTP runtime transport.") }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
}
