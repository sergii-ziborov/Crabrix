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

    func testResolvesDownloadsAndLinksARealCratesIOPackage() async throws {
        guard ProcessInfo.processInfo.environment["CRABRIX_RUN_COMPILER_GATE"] == "1" else {
            throw XCTSkip("Run the CrabrixCompilerGate scheme for the registry dependency gate.")
        }

        let manifest = """
        [package]
        name = "package-gate"
        version = "0.1.0"
        edition = "2024"

        [dependencies]
        smallvec = "1"
        """
        let source = """
        use smallvec::SmallVec;

        fn main() {
            let mut values: SmallVec<[u32; 4]> = SmallVec::new();
            for value in 1..=3 { values.push(value * 10); }
            println!("{}", values.iter().map(|v| v.to_string()).collect::<Vec<_>>().join("-"));
        }
        """

        let snapshot = try await CargoPackageManager().prepare(manifestSource: manifest)
        XCTAssertFalse(snapshot.plan.isEmpty, "smallvec should produce at least one build unit")
        XCTAssertTrue(snapshot.isOfflineReady, "every resolved package should be extracted on disk")
        XCTAssertTrue(
            snapshot.blockingPackages.isEmpty,
            "unexpected unsupported packages: \(snapshot.blockingPackages.map(\.id))"
        )
        XCTAssertEqual(snapshot.plan.rootExterns.map(\.alias), ["smallvec"])

        let compiler = WasmRustCompiler(bundle: .main)
        let result = await compiler.run(
            source: source,
            sourcePath: "src/main.rs",
            supportingFiles: ["Cargo.toml": manifest],
            plan: snapshot.plan
        )

        XCTAssertTrue(
            result.succeeded,
            "phase: \(result.phase.rawValue)\ndetail: \(result.detail)\nstderr: \(result.stderr)"
        )
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "10-20-30")
        XCTAssertTrue(
            compiler.isPlanCached(snapshot.plan, emit: .link),
            "dependency artifacts should be reusable after a successful build"
        )
    }

    func testStopInterruptsARunningCompile() async throws {
        guard ProcessInfo.processInfo.environment["CRABRIX_RUN_COMPILER_GATE"] == "1" else {
            throw XCTSkip("Run the CrabrixCompilerGate scheme for the interruption gate.")
        }

        let compiler = WasmRustCompiler(bundle: .main)
        // A unique body defeats the artifact cache so rustc really runs.
        let source = """
        fn main() {
            println!("interrupt gate \(UUID().uuidString)");
        }
        """

        let started = ContinuousClock.now
        async let result = compiler.check(source: source)
        try await Task.sleep(for: .seconds(3))
        compiler.cancel()

        let value = await result
        let elapsed = ContinuousClock.now - started

        XCTAssertFalse(value.succeeded)
        XCTAssertTrue(
            value.detail.contains("stopped"),
            "expected a stop result, got: \(value.detail)"
        )
        // The bare compile takes far longer than this; a real interruption is
        // the only way the call returns inside the window.
        XCTAssertLessThan(elapsed, .seconds(40), "Stop did not interrupt the guest promptly")
    }
}
