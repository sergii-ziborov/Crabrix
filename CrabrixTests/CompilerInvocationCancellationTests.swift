import XCTest
@testable import Crabrix

final class CompilerInvocationCancellationTests: XCTestCase {
    func testStopBeforeWorkAndBetweenDebugPhasesIsRemembered() {
        let token = CompilerInvocationCancellation()
        token.cancel()
        let checking = WasmInterrupter(); token.attach(checking)
        XCTAssertEqual(checking.stopReason, .userRequested)
        token.detach(checking)
        let running = WasmInterrupter(); token.attach(running)
        XCTAssertEqual(running.stopReason, .userRequested)
    }

    func testLateStopOnlyTouchesItsOwnedGuestAndStaleDetachCannotReleaseTheNextPhase() {
        let remote = CompilerInvocationCancellation(), ordinary = CompilerInvocationCancellation()
        let previous = WasmInterrupter(), next = WasmInterrupter(), local = WasmInterrupter()
        remote.attach(previous); remote.detach(previous)
        remote.attach(next); remote.detach(previous)
        ordinary.attach(local)
        remote.cancel()
        XCTAssertNil(previous.stopReason)
        XCTAssertEqual(next.stopReason, .userRequested)
        XCTAssertNil(local.stopReason)
        remote.detach(next); remote.cancel()
        XCTAssertNil(local.stopReason)
    }

    func testStoppedBeforeCompilerQueueDoesNotCompileOrPrepareAProgram() async {
        let compiler = WasmRustCompiler(), token = CompilerInvocationCancellation()
        token.cancel()
        let result = await compiler.check(source: "fn main() {}", cancellation: token)
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.detail.localizedCaseInsensitiveContains("stopped"), result.detail)
    }
}
