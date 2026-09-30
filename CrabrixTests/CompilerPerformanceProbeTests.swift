import Foundation
import XCTest
@testable import Crabrix

/// An opt-in raw observation, not a pass/fail speed claim. Run this with the
/// CrabrixCompilerGate scheme on the same device for each candidate revision.
final class CompilerPerformanceProbeTests: XCTestCase {
    func testColdEngineAndUnchangedWarningCheck() async throws {
        guard ProcessInfo.processInfo.environment["CRABRIX_RUN_COMPILER_GATE"] == "1" else {
            throw XCTSkip("Use the CrabrixCompilerGate scheme for the compiler probe.")
        }

        let compiler = WasmRustCompiler(bundle: .main)
        let source = """
        fn main() {
            let unused = 1;
            println!("hello");
        }
        """
        let first = await compiler.check(source: source)
        let unchanged = await compiler.check(source: source)
        XCTAssertTrue(first.succeeded, first.detail)
        XCTAssertTrue(unchanged.succeeded, unchanged.detail)
        XCTAssertFalse(first.diagnostics.filter { $0.level == "warning" }.isEmpty)
        XCTAssertEqual(unchanged.diagnostics, first.diagnostics)
        XCTAssertEqual(unchanged.stdout, first.stdout)
        XCTAssertEqual(unchanged.stderr, first.stderr)

        for (phase, result) in [("first", first), ("unchanged", unchanged)] {
            let parts = result.duration.components
            let milliseconds = Double(parts.seconds) * 1_000
                + Double(parts.attoseconds) / 1_000_000_000_000_000
            let observation: [String: Any] = [
                "workload": "warning-check-v1",
                "phase": phase,
                "milliseconds": milliseconds,
                "warningCount": result.diagnostics.filter { $0.level == "warning" }.count,
                "toolchainID": CargoToolchain.artifactIdentity,
            ]
            let data = try JSONSerialization.data(withJSONObject: observation, options: [.sortedKeys])
            print("CRABRIX_PERF \(String(decoding: data, as: UTF8.self))")
        }
    }
}
