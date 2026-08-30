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

    func testEveryGuidedShowcasePassesBundledRustcCheck() async throws {
        guard ProcessInfo.processInfo.environment["CRABRIX_RUN_COMPILER_GATE"] == "1" else {
            throw XCTSkip("Set CRABRIX_RUN_COMPILER_GATE=1 for the guided-project gate.")
        }

        let compiler = WasmRustCompiler(bundle: .main)
        for showcase in RustShowcaseExpansionCatalog.projects {
            var supporting = showcase.project.files
            let source = try XCTUnwrap(
                supporting.removeValue(forKey: showcase.project.entryFile),
                showcase.id
            )
            let result = await compiler.check(
                source: source,
                sourcePath: showcase.project.entryFile,
                supportingFiles: supporting
            )
            XCTAssertTrue(
                result.succeeded,
                "\(showcase.id): \(result.detail)\n\(result.stderr)"
            )
        }
    }

    func testVisualPixelSunsetRendersAValidatedCanvas() async throws {
        try await Self.assertVisualShowcase("pixel-sunset")
    }

    func testVisualCellularGardenRendersAValidatedCanvas() async throws {
        try await Self.assertVisualShowcase("cellular-garden")
    }

    func testVisualMandelbrotRendersAValidatedCanvas() async throws {
        try await Self.assertVisualShowcase("mandelbrot-canvas")
    }

    func testVisualConstellationRendersAValidatedCanvas() async throws {
        try await Self.assertVisualShowcase("constellation-map")
    }

    func testVisualTerrainRendersAValidatedCanvas() async throws {
        try await Self.assertVisualShowcase("terrain-map")
    }

    func testVisualColorWavesRendersAValidatedCanvas() async throws {
        try await Self.assertVisualShowcase("color-waves")
    }

    @MainActor
    func testVisualCreateTemplateRendersAValidatedCanvas() async throws {
        try Self.requireCompilerGate()
        let defaults = UserDefaults(
            suiteName: "crabrix.tests.\(UUID().uuidString)"
        )!
        let model = CompilerViewModel(userDefaults: defaults)
        model.createProject(name: "visual-gate", template: .visual)
        try await Self.assertCanvas(
            project: model.exportProject(),
            id: "visual-template"
        )
    }

    private static func assertVisualShowcase(_ id: String) async throws {
        try requireCompilerGate()
        let showcase = try XCTUnwrap(
            RustVisualShowcaseCatalog.projects.first { $0.id == id }
        )
        try await assertCanvas(project: showcase.project, id: id)
    }

    private static func assertCanvas(
        project: CrabrixProject,
        id: String
    ) async throws {
        var supporting = project.files
        let source = try XCTUnwrap(
            supporting.removeValue(forKey: project.entryFile),
            id
        )
        let result = await WasmRustCompiler(bundle: .main).run(
            source: source,
            sourcePath: project.entryFile,
            supportingFiles: supporting
        )
        XCTAssertTrue(
            result.succeeded,
            "\(id): \(result.detail)\n\(result.stderr)"
        )
        let parsed = RustCanvasOutput.parse(result.stdout)
        XCTAssertNotNil(parsed.frame, "\(id): \(result.stdout)")
    }

    private static func requireCompilerGate() throws {
        guard ProcessInfo.processInfo.environment["CRABRIX_RUN_COMPILER_GATE"] == "1" else {
            throw XCTSkip(
                "Set CRABRIX_RUN_COMPILER_GATE=1 for the visual-project gate."
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

    @MainActor
    func testViewModelStopReenablesBuildAfterWorkerDrains() async throws {
        guard ProcessInfo.processInfo.environment["CRABRIX_RUN_COMPILER_GATE"] == "1" else {
            throw XCTSkip("Run the CrabrixCompilerGate scheme for the UI stop-state gate.")
        }

        let identifier = UUID().uuidString
        let storageRoot = FileManager.default.temporaryDirectory
            .appending(path: "CrabrixStopStateGate-\(identifier)", directoryHint: .isDirectory)
        let defaultsName = "CrabrixStopStateGate.\(identifier)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer {
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: storageRoot)
        }

        let model = CompilerViewModel(
            projectLibrary: ProjectLibrary(
                storageURL: storageRoot.appending(path: "recent-projects.json")
            ),
            userDefaults: defaults
        )
        model.source = "fn main() { println!(\"stop-state-\(identifier)\"); }"
        model.check()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(model.isBusy, "The compiler finished before the stop gate could exercise it.")

        model.cancelBuild()
        XCTAssertTrue(model.isCompilerDraining)
        XCTAssertFalse(model.canStartBuild)

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(10))
        while model.isCompilerDraining, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertFalse(model.isCompilerDraining, "The cancelled worker never released the Run gate.")
        XCTAssertTrue(model.canStartBuild, "Run stayed disabled after the compiler worker exited.")
    }
}
