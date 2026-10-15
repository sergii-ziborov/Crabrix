import XCTest
@testable import Crabrix

final class BuildProblemsTests: XCTestCase {
    func testCargoPreparationFailureAppearsWithoutRustcEvidence() {
        let result = CompilationResult.failure(phase: .setup,
            detail: "syn cannot be built locally: proc-macro is unavailable")
        XCTAssertEqual(result.problemDiagnostics.count, 1)
        XCTAssertEqual(result.problemDiagnostics.first?.level, "error")
        XCTAssertTrue(result.problemDiagnostics.first?.message.contains("syn") == true)
        XCTAssertNil(result.problemDiagnostics.first?.primarySpan)
        XCTAssertTrue(result.diagnostics.isEmpty, "Setup errors must not become rustc repair or lesson evidence")
    }

    func testWarningsDoNotHideAnUnlocatedBuildFailure() {
        let warning = RustDiagnostic(level: "warning", message: "unused variable", code: nil,
                                     rendered: "", spans: [])
        let result = CompilationResult(succeeded: false, phase: .compile, exitCode: 1,
            diagnostics: [warning], stdout: "", stderr: "linker unavailable",
            duration: .zero, detail: "Linking failed")
        XCTAssertEqual(result.problemDiagnostics.map(\.level), ["error", "warning"])
    }

    func testRealRustcErrorsRetainTheirLocationsWithoutDuplicates() {
        let diagnostic = RustDiagnostic(level: "error", message: "cannot borrow", code: "E0502",
            rendered: "error[E0502]", spans: [.init(lineStart: 3, lineEnd: 3,
                columnStart: 1, columnEnd: 4, isPrimary: true, label: nil, sourceLine: "items.push(1);")])
        let result = CompilationResult(succeeded: false, phase: .compile, exitCode: 1,
            diagnostics: [diagnostic], stdout: "", stderr: "", duration: .zero, detail: "Compile failed")
        XCTAssertEqual(result.problemDiagnostics, [diagnostic])
    }

    func testUserStopIsNotReportedAsAnErrorButResourceLimitsAre() {
        for phase in [CompilationResult.Phase.setup, .compile, .run] {
            XCTAssertTrue(CompilationResult.failure(phase: phase,
                detail: "Build stopped. The Wasm guest was interrupted.").problemDiagnostics.isEmpty)
            XCTAssertEqual(CompilationResult.failure(phase: phase,
                detail: "Program stopped at the sandbox memory limit.").problemDiagnostics.count, 1)
        }
    }

    func testSuccessfulBuildDoesNotInventAProblem() {
        let result = CompilationResult(succeeded: true, phase: .run, exitCode: 0,
            diagnostics: [], stdout: "hello", stderr: "", duration: .zero, detail: "Done")
        XCTAssertTrue(result.problemDiagnostics.isEmpty)
    }

    func testWeatherStationCompilesAndRunsWithoutUnusedProcMacroDependency() async throws {
        guard ProcessInfo.processInfo.environment["CRABRIX_RUN_COMPILER_GATE"] == "1" else {
            throw XCTSkip("Use the manual CrabrixBuildProblemsGate scheme")
        }
        let source = """
        #[derive(Debug, Clone, Copy)]
        struct Sample {
            celsius: f64,
            humidity: u8,
        }

        fn main() {
            let samples = [
                Sample { celsius: 21.4, humidity: 58 },
                Sample { celsius: 22.1, humidity: 55 },
                Sample { celsius: 20.8, humidity: 61 },
                Sample { celsius: 23.0, humidity: 52 },
            ];
            let average = samples.iter()
                .map(|sample| sample.celsius)
                .sum::<f64>() / samples.len() as f64;
            let driest = samples.iter()
                .min_by_key(|sample| sample.humidity)
                .unwrap();
            println!("average {average:.1} C");
            println!("driest  {}%", driest.humidity);
        }
        """
        let manifest = """
        [package]
        name = "weather-station"
        version = "0.1.0"
        edition = "2024"
        [dependencies]
        """
        let snapshot = try await CargoPackageManager().prepare(manifestSource: manifest)
        XCTAssertTrue(snapshot.blockingPackages.isEmpty)
        XCTAssertTrue(snapshot.plan.units.isEmpty)
        let result = await WasmRustCompiler(bundle: .main).run(source: source,
            sourcePath: "src/main.rs", supportingFiles: ["Cargo.toml": manifest], plan: snapshot.plan)
        XCTAssertTrue(result.succeeded, "\(result.detail)\n\(result.stderr)")
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
                       "average 21.8 C\ndriest  52%")
        XCTAssertTrue(result.problemDiagnostics.isEmpty)
    }
}
