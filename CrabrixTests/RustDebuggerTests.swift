import Foundation
import XCTest
@testable import Crabrix

final class RustDebuggerTests: XCTestCase {
    private static let source = "fn add(a: i32, b: i32) -> i32 {\n let c = a + b;\n c\n}\nfn main() {\n let mut total = 0;\n for i in 0..3 {\n total += add(i,1);\n }\n println!(\"total={total}\");\n}\n"
    private final class Recorder: @unchecked Sendable {
        let lock = NSLock()
        weak var session: RustDebugSession?
        private var values: [RustDebugPause] = []
        var snapshots: [RustDebugPause] { lock.withLock { values } }
        func receive(_ value: RustDebugPause) {
            let index = lock.withLock { values.append(value); return values.count - 1 }
            let commands: [RustDebugSession.Command] = [.over,.continue,.into,.over,.out,.continue]
            if index == 5 { session?.updateBreakpoints([]) }
            if index >= commands.count { session?.stop(); return }
            // Release the compiler thread only after another queue has run.
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.03) { [weak self] in self?.session?.resume(commands[index]) }
        }
    }
    func testActualRustBreakpointsStepsFramesLocalsAndNormalRun() async throws {
        let recorder = Recorder()
        let session = RustDebugSession(breakpoints: [RustDebugBreakpoint(file: "main.rs", line: 8)], onPlan: { _ in }, onPause: recorder.receive)
        recorder.session = session
        let compiler = WasmRustCompiler()
        let value = await compiler.debug(source: Self.source, session: session)
        XCTAssertTrue(value.succeeded, value.detail + "\n" + value.stderr)
        XCTAssertEqual(value.stdout, "total=6\n")
        let stops = recorder.snapshots
        XCTAssertEqual(stops.map(\.site.line), [6,7,8,2,3,9])
        XCTAssertEqual(stops.map(\.site.function), ["main","main","main","add","add","main"])
        guard stops.count == 6 else { return }
        XCTAssertEqual(stops[2].reason, "breakpoint")
        XCTAssertEqual(stops[3].frames.count, 2)
        XCTAssertEqual(stops[4].frames.last?.locals.first(where: { $0.name == "c" })?.value, "1")
        XCTAssertEqual(stops[5].frames.last?.locals.first(where: { $0.name == "total" })?.value, "1")
        let normal = await compiler.run(source: Self.source)
        XCTAssertTrue(normal.succeeded, normal.detail)
        XCTAssertEqual(normal.stdout, "total=6\n", "Debug imports must not contaminate normal Run or its cache")
    }
    func testStopReleasesAPausedActualGuest() async throws {
        let paused = expectation(description: "actual guest paused")
        let session = RustDebugSession(onPlan: { _ in }, onPause: { _ in paused.fulfill() })
        let compiler = WasmRustCompiler()
        let task = Task { await compiler.debug(source: "fn main() { let mut n=0u32; loop { n=n.wrapping_add(1); std::hint::black_box(n); } }", session: session) }
        await fulfillment(of: [paused], timeout: 120)
        session.stop(); compiler.cancel()
        let value = await task.value
        XCTAssertFalse(value.succeeded)
        let next = await compiler.run(source: "fn main(){println!(\"after-stop\");}")
        XCTAssertTrue(next.succeeded, next.detail)
        XCTAssertEqual(next.stdout, "after-stop\n")
    }
    func testPausedTimeDoesNotConsumeRunningDeadline() async throws {
        let state = AtomicStopState()
        state.setDeadline(after: .milliseconds(50)); state.pauseDeadline()
        try await Task.sleep(for: .milliseconds(90))
        XCTAssertNil(state.reason)
        state.resumeDeadline(); XCTAssertNil(state.reason)
        try await Task.sleep(for: .milliseconds(90))
        XCTAssertEqual(state.reason, .wallClock)
        let cancelled = AtomicStopState(); cancelled.setDeadline(after: .seconds(1)); cancelled.pauseDeadline(); cancelled.cancel(reason: .userRequested)
        XCTAssertEqual(cancelled.reason, .userRequested)
    }
    func testOriginalBorrowSemanticsAndUninitializedLocalsStillCompile() async throws {
        let session = RustDebugSession(onPlan: { _ in }, onPause: { _ in })
        // The first run is an instrumenter gate; actual execution is covered by
        // the preceding tests. It must not add a borrow of x or read late early.
        let source = "fn main(){let mut x=1; let p=&mut x; *p+=2; let late:i32; late=4; println!(\"{} {}\",x,late); }"
        let plan = try RustDebugInstrumenter.instrument(files: ["main.rs": source], entryFile: "main.rs")
        session.prepare(plan)
        let compiler = WasmRustCompiler()
        let checked = await compiler.check(source: plan.files["main.rs"]!)
        XCTAssertTrue(checked.succeeded, checked.stderr)
    }
}
