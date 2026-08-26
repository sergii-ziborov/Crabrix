import XCTest
@testable import Crabrix

final class BundledCompilerGateTests: XCTestCase {
    func testBundledRustcProducesE0502() async throws {
        guard ProcessInfo.processInfo.environment["CRABRIX_RUN_COMPILER_GATE"] == "1" else {
            throw XCTSkip("Set CRABRIX_RUN_COMPILER_GATE=1 for the expensive bundled compiler gate.")
        }

        let compiler = WasmRustCompiler(bundle: .main)
        XCTAssertTrue(compiler.probe().isReady)

        let result = await compiler.check(source: RustSamples.broken)

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(
            result.diagnostics.first?.code,
            "E0502",
            "detail: \(result.detail)\nstderr: \(result.stderr)\nstdout: \(result.stdout)"
        )
    }

    func testBundledRustcCompilesAndRunsRepairedProgram() async throws {
        guard ProcessInfo.processInfo.environment["CRABRIX_RUN_COMPILER_GATE"] == "1" else {
            throw XCTSkip("Run the CrabrixCompilerGate scheme for the expensive bundled compiler gate.")
        }

        let compiler = WasmRustCompiler(bundle: .main)
        let result = await compiler.run(source: RustSamples.runnable)

        XCTAssertTrue(
            result.succeeded,
            "phase: \(result.phase.rawValue)\ndetail: \(result.detail)\nstderr: \(result.stderr)"
        )
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "crab")
    }

    func testBundledRustcCompilesMultiFileProject() async throws {
        guard ProcessInfo.processInfo.environment["CRABRIX_RUN_COMPILER_GATE"] == "1" else {
            throw XCTSkip("Run the CrabrixCompilerGate scheme for the expensive multi-file gate.")
        }

        let compiler = WasmRustCompiler(bundle: .main)
        let result = await compiler.run(
            source: RustSamples.multiFileMain,
            sourcePath: "src/main.rs",
            supportingFiles: [
                "Cargo.toml": RustSamples.cargoManifest,
                "src/greeter.rs": RustSamples.multiFileGreeter,
            ]
        )

        XCTAssertTrue(
            result.succeeded,
            "phase: \(result.phase.rawValue)\ndetail: \(result.detail)\nstderr: \(result.stderr)"
        )
        XCTAssertEqual(
            result.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
            "hello from two Rust files"
        )
    }

    func testBundledRustcSurvivesRepeatedBuilds() async throws {
        guard ProcessInfo.processInfo.environment["CRABRIX_RUN_COMPILER_GATE"] == "1" else {
            throw XCTSkip("Run the CrabrixCompilerGate scheme for the repeated-build gate.")
        }

        let compiler = WasmRustCompiler(bundle: .main)
        for attempt in 1...3 {
            let result = await compiler.run(source: RustSamples.runnable)
            XCTAssertTrue(
                result.succeeded,
                "attempt \(attempt), phase: \(result.phase.rawValue), detail: \(result.detail)"
            )
            XCTAssertEqual(
                result.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
                "crab",
                "attempt \(attempt)"
            )
        }
    }

    func testUserProgramCannotGrowPastSandboxMemoryLimit() async throws {
        guard ProcessInfo.processInfo.environment["CRABRIX_RUN_COMPILER_GATE"] == "1" else {
            throw XCTSkip("Run the CrabrixCompilerGate scheme for the sandbox memory gate.")
        }

        let compiler = WasmRustCompiler(bundle: .main)
        let result = await compiler.run(source: RustSamples.memoryPressure)

        XCTAssertFalse(result.succeeded, "The 80 MiB guest unexpectedly escaped the 64 MiB limit.")
        XCTAssertEqual(result.phase, .run)
        XCTAssertEqual(
            result.detail,
            "Program stopped at the \(WasmSandboxPolicy.memoryLimitLabel) sandbox memory limit."
        )
    }
}
