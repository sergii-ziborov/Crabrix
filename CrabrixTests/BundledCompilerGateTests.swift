import Foundation
import XCTest
@testable import Crabrix

final class BundledCompilerGateTests: XCTestCase {
    @MainActor
    func testSuccessfulLessonRunClearsPreviousErrorWithoutCompletingLesson() async throws {
        try Self.requireCompilerGate()
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try await CourseBootstrap(
            bundle: .main, root: root, appVersion: SemanticVersion("1.1")
        ).activateBundledBaseline()
        let session = try XCTUnwrap(CourseSession(lessonID: "borrowing", repository: repository))
        let lesson = try XCTUnwrap(repository.lesson(id: "borrowing"))
        let content = try XCTUnwrap(CourseLessonExecution(lesson: lesson, session: session))
        let model = makeRegressionModel()
        model.loadBorrowDiagnosticSample()
        model.beginLesson("borrowing", content: content)
        model.run()
        try await waitForBuild(model)
        XCTAssertEqual(model.primaryDiagnostic?.code, "E0502")

        model.source = "fn main() { println!(\"different output\"); }"
        model.run()
        XCTAssertNil(model.primaryDiagnostic, "A new build must not display a stale repair prompt")
        try await waitForBuild(model)
        XCTAssertTrue(model.result?.succeeded == true, model.result?.detail ?? "No result")
        XCTAssertNil(model.primaryDiagnostic, "A successful run must clear the previous compiler error")
        XCTAssertEqual(model.diagnosticAdviceState, .idle)
        XCTAssertFalse(model.completedLessonIDs.contains("borrowing"))
        XCTAssertTrue(model.lessonEvidenceMessage?.contains("repair removed required behavior") == true)
        let identity = try XCTUnwrap(model.lessonAttemptEvidence.last?.identity)
        XCTAssertEqual(identity.courseID, session.courseID)
        XCTAssertEqual(identity.language, session.language)
        XCTAssertEqual(identity.contentVersion, session.contentVersion)
        XCTAssertEqual(identity.lessonID, session.lessonID)
        XCTAssertEqual(identity.exerciseID, session.lessonID)
        XCTAssertEqual(identity.validatorVersion, LessonAttemptEvidence.validatorVersion)
        XCTAssertEqual(identity.projectID, model.projectID)
        XCTAssertEqual(identity.projectRevision, model.workspaceRevision.sourceTreeHash)
        XCTAssertEqual(identity.toolchainID, model.workspaceRevision.toolchainID)
    }

    @MainActor
    func testSwitchingFilesDuringCompilationKeepsItsResult() async throws {
        try Self.requireCompilerGate()
        let model = makeRegressionModel()
        model.createProject(name: "navigation-gate", template: .modules)
        model.source += "\n// \(UUID())"
        let revision = model.workspaceRevision
        let files = model.exportProject().files
        model.run()
        XCTAssertTrue(model.isBusy)
        model.selectFile("src/greeter.rs")
        XCTAssertEqual(model.selectedFile, "src/greeter.rs")
        XCTAssertEqual(model.source, files["src/greeter.rs"])
        XCTAssertEqual(model.workspaceRevision, revision)
        await Task.yield()
        model.selectFile("Cargo.toml")
        XCTAssertEqual(model.selectedFile, "Cargo.toml")
        XCTAssertEqual(model.workspaceRevision, revision)
        try await waitForBuild(model)
        XCTAssertTrue(model.result?.succeeded == true, model.result?.detail ?? "Compilation result was discarded")
        XCTAssertEqual(model.result?.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "Hello from a Rust module!")
        XCTAssertEqual(model.selectedFile, "Cargo.toml")
        XCTAssertEqual(model.exportProject().files, files)
    }

    func testHashbrownFromDeviceReportResolvesAndRuns() async throws {
        try Self.requireCompilerGate()
        let manifest = """
        [package]
        name = "hashbrown-device-regression"
        version = "0.1.0"
        edition = "2024"
        [dependencies]
        hashbrown = "=0.17.1"
        """
        let snapshot = try await CargoPackageManager().prepare(manifestSource: manifest)
        XCTAssertTrue(snapshot.blockingPackages.isEmpty, snapshot.blockingPackages.map {
            "\($0.name): \($0.compatibility.detail ?? "")"
        }.joined(separator: "\n"))
        XCTAssertTrue(snapshot.packages.contains { $0.name == "hashbrown" && $0.version.description == "0.17.1" })
        let source = """
        // \(UUID())
        use hashbrown::HashMap;
        fn main() {
            let mut values = HashMap::new();
            values.insert("answer", 42);
            println!("{}", values["answer"]);
        }
        """
        let result = await WasmRustCompiler(bundle: .main).run(
            source: source, sourcePath: "src/main.rs", supportingFiles: ["Cargo.toml": manifest], plan: snapshot.plan
        )
        XCTAssertTrue(result.succeeded, "\(result.detail)\n\(result.stderr)")
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "42")
    }

    @MainActor
    private func makeRegressionModel() -> CompilerViewModel {
        let identifier = UUID().uuidString
        let defaultsName = "crabrix.regression.\(identifier)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defaults.set(false, forKey: "crabrix.appleIntelligenceDiagnostics")
        let root = FileManager.default.temporaryDirectory.appending(path: defaultsName)
        addTeardownBlock {
            UserDefaults(suiteName: defaultsName)?.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: root)
        }
        return CompilerViewModel(
            projectLibrary: ProjectLibrary(storageURL: root.appending(path: "projects.json")), userDefaults: defaults
        )
    }

    @MainActor
    private func waitForBuild(_ model: CompilerViewModel) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(180))
        while model.isBusy, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertFalse(model.isBusy, "Build did not finish within three minutes")
        if model.isBusy { model.cancelBuild() }
        XCTAssertNotNil(model.result)
    }

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

    func testFreshRevisionCompilesAndRunsWithoutArtifactCache() async throws {
        guard ProcessInfo.processInfo.environment["CRABRIX_RUN_COMPILER_GATE"] == "1" else {
            throw XCTSkip("Run the CrabrixCompilerGate scheme for the fresh compiler gate.")
        }

        // A unique source body forces the real compiler and program paths on
        // every invocation, even when the simulator's artifact cache is warm.
        let marker = UUID().uuidString
        let source = """
        fn main() {
            let marker = "\(marker)";
            println!("{}", marker);
        }
        """
        let result = await WasmRustCompiler(bundle: .main).run(source: source)
        XCTAssertTrue(result.succeeded, "\(result.detail)\n\(result.stderr)")
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), marker)
    }

    func testUserProgramOutputStopsAtWASIWriteBudget() async throws {
        guard ProcessInfo.processInfo.environment["CRABRIX_RUN_COMPILER_GATE"] == "1" else {
            throw XCTSkip("Run the CrabrixCompilerGate scheme for the output stress gate.")
        }

        let result = await WasmRustCompiler(bundle: .main).run(
            source: #"fn main() { print!("{}", "x".repeat(1_048_577)); }"#
        )

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.phase, .run, "\(result.detail)\n\(result.stderr)")
        XCTAssertTrue(result.detail.contains("output limit"), result.detail)
        XCTAssertLessThanOrEqual(
            result.stdout.utf8.count,
            WasmSandboxPolicy.userProgramOutputLimitBytes
        )
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

    func testRootCargoPackageEnvironmentComesFromTheManifest() async throws {
        guard ProcessInfo.processInfo.environment["CRABRIX_RUN_COMPILER_GATE"] == "1" else {
            throw XCTSkip("Run the CrabrixCompilerGate scheme for the root Cargo env gate.")
        }
        let manifest = """
        [package]
        name = "root-env-gate"
        version = "2.3.4"
        edition = "2024"
        rust-version = "1.90"
        """
        let source = """
        fn main() {
            println!("{}:{}:{}", env!("CARGO_PKG_NAME"), env!("CARGO_PKG_VERSION"), env!("CARGO_PKG_RUST_VERSION"));
        }
        """

        let result = await WasmRustCompiler(bundle: .main).run(
            source: source,
            sourcePath: "src/main.rs",
            supportingFiles: ["Cargo.toml": manifest]
        )

        XCTAssertTrue(result.succeeded, "\(result.detail)\n\(result.stderr)")
        XCTAssertEqual(
            result.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
            "root-env-gate:2.3.4:1.90"
        )
    }

    func testRootFeaturesReachTheRootCrate() async throws {
        guard ProcessInfo.processInfo.environment["CRABRIX_RUN_COMPILER_GATE"] == "1" else {
            throw XCTSkip("Run the CrabrixCompilerGate scheme for the root feature gate.")
        }
        let manifest = """
        [package]
        name = "root-feature-gate"
        version = "0.1.0"
        edition = "2024"

        [features]
        default = ["fancy"]
        fancy = []
        """
        let source = """
        #[cfg(feature = "fancy")]
        fn mode() -> &'static str { "fancy" }

        #[cfg(not(feature = "fancy"))]
        fn mode() -> &'static str { "plain" }

        fn main() {
            println!("{}:{}", mode(), env!("CARGO_FEATURE_FANCY"));
        }
        """

        let snapshot = try await CargoPackageManager().prepare(manifestSource: manifest)
        XCTAssertEqual(snapshot.plan.rootFeatures, ["default", "fancy"])

        let result = await WasmRustCompiler(bundle: .main).run(
            source: source,
            sourcePath: "src/main.rs",
            supportingFiles: ["Cargo.toml": manifest],
            plan: snapshot.plan
        )

        XCTAssertTrue(result.succeeded, "\(result.detail)\n\(result.stderr)")
        XCTAssertEqual(
            result.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
            "fancy:1"
        )
    }

    func testAlgorithmSolutionRunsOnlyThroughThePrivateHarness() async throws {
        guard ProcessInfo.processInfo.environment["CRABRIX_RUN_COMPILER_GATE"] == "1" else {
            throw XCTSkip("Run the CrabrixCompilerGate scheme for the algorithm harness gate.")
        }

        let pattern = try XCTUnwrap(AlgorithmCourseCatalog.patterns.first)
        let challenge = try XCTUnwrap(
            AlgorithmCourseCatalog.challenge(for: pattern.lessonID(.challenge))
        )
        let solution = challenge.source.replacingOccurrences(
            of: "let _ = input;\n    todo!(\"implement \(pattern.title)\")",
            with: """
            let values: Vec<i32> = input
                .trim()
                .trim_matches(['[', ']'])
                .split(',')
                .map(|part| part.trim().parse().unwrap())
                .collect();
            values.iter().position(|value| *value < 0)
                .map(|index| index.to_string())
                .unwrap_or_else(|| (-1).to_string())
            """
        )

        let result = await WasmRustCompiler(bundle: .main).run(
            source: challenge.verificationSource,
            sourcePath: "main.rs",
            supportingFiles: ["solution.rs": solution]
        )

        XCTAssertTrue(result.succeeded, "\(result.detail)\n\(result.stderr)")
        XCTAssertEqual(result.stdout, challenge.expectedOutput)
        XCTAssertFalse(challenge.source.contains("assert_eq!"))
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

    func testSourceBuiltCompilerCheckedI64Multiplication() async throws {
        try Self.requireCompilerGate()
        let source = """
        // fresh revision: \(UUID())
        fn main() {
            let signed: [(i64, i64); 5] = [
                (i64::MIN, -1), (i64::MAX, 1), (-2, 3),
                (i64::MAX, 2), (-1, -1),
            ];
            let unsigned: [(u64, u64); 4] = [
                (u64::MAX, 2), (1 << 63, 1), (1 << 63, 2), (u64::MAX, 1),
            ];
            let signed_results: String = signed.into_iter().map(|(a, b)| {
                if std::hint::black_box(a).checked_mul(std::hint::black_box(b)).is_some() {
                    '1'
                } else {
                    '0'
                }
            }).collect();
            let unsigned_results: String = unsigned.into_iter().map(|(a, b)| {
                if std::hint::black_box(a).checked_mul(std::hint::black_box(b)).is_some() {
                    '1'
                } else {
                    '0'
                }
            }).collect();
            println!("s={signed_results};u={unsigned_results}");
        }
        """
        let result = await WasmRustCompiler(bundle: .main).run(source: source)
        XCTAssertTrue(result.succeeded, "\(result.detail)\n\(result.stderr)")
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
                       "s=01101;u=0101")
    }

    func testSourceBuiltCompilerI128ByteSwap() async throws {
        try Self.requireCompilerGate()
        let source = """
        // fresh revision: \(UUID())
        fn main() {
            let value = std::hint::black_box(0x00112233445566778899aabbccddeeffu128);
            let swapped = value.swap_bytes();
            println!("{}", swapped == 0xffeeddccbbaa99887766554433221100u128);
        }
        """
        let result = await WasmRustCompiler(bundle: .main).run(source: source)
        XCTAssertTrue(result.succeeded, "\(result.detail)\n\(result.stderr)")
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "true")
    }

    func testEveryInstalledAcademyExampleBuildsAndRuns() async throws {
        guard ProcessInfo.processInfo.environment["CRABRIX_RUN_COMPILER_GATE"] == "1" else {
            throw XCTSkip("Set CRABRIX_RUN_COMPILER_GATE=1 for the Academy example gate.")
        }

        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try await CourseBootstrap(
            bundle: .main, root: root, appVersion: SemanticVersion("1.1")
        ).activateBundledBaseline()
        XCTAssertEqual(repository.showcaseProjects().count, 46)
        let compiler = WasmRustCompiler(bundle: .main)
        for showcase in repository.showcaseProjects() {
            var supporting = showcase.project.files
            let originalSource = try XCTUnwrap(
                supporting.removeValue(forKey: showcase.project.entryFile),
                showcase.id
            )
            // A new revision makes this a compiler gate even after a previous
            // simulator run populated all 46 cached program artifacts.
            let source = originalSource + "\n// academy-example-gate-\(UUID().uuidString)\n"
            let result = await compiler.run(
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
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try await CourseBootstrap(
            bundle: .main, root: root, appVersion: SemanticVersion("1.1")
        ).activateBundledBaseline()
        let showcase = try XCTUnwrap(
            repository.showcaseProjects().first { $0.id == id }
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
        // A unique marker keeps the artifact cache from serving a program an
        // earlier run compiled. Without it this gate could pass while rustc
        // never ran, and then assert things about dependency artifacts the run
        // had not produced.
        let source = """
        // gate \(UUID().uuidString)
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

    func testMultiCrateCollectionsAndJSONApplicationBuildsAndRuns() async throws {
        try Self.requireCompilerGate()
        guard ProcessInfo.processInfo.environment["CRABRIX_RUN_UNSUPPORTED_CRATE_PROBE"] == "1" else {
            throw XCTSkip("The pinned compiler backend cannot lower itoa 1.x; see docs/compiler-complex-gate-2026-10-01.md.")
        }
        let manifest = """
        [package]
        name = "event-analyzer-gate"
        version = "0.1.0"
        edition = "2024"

        [dependencies]
        hashbrown = "=0.17.1"
        smallvec = "=1.15.1"
        serde_json = "=1.0.151"
        """
        let source = """
        // fresh application revision: \(UUID())
        use hashbrown::HashMap;
        use serde_json::Value;
        use smallvec::SmallVec;

        fn main() {
            let input = r#"[{"kind":"warn","message":"cache"},{"kind":"info","message":"start"},{"kind":"warn","message":"timeout"}]"#;
            let events: Value = serde_json::from_str(input).unwrap();
            let mut counts: HashMap<&str, usize> = HashMap::new();
            let mut warnings: SmallVec<[String; 4]> = SmallVec::new();
            for event in events.as_array().unwrap() {
                if let (Some(kind), Some(message)) =
                    (event["kind"].as_str(), event["message"].as_str()) {
                    *counts.entry(kind).or_default() += 1;
                    if kind == "warn" { warnings.push(message.to_owned()); }
                }
            }
            println!("{}:{}", counts["warn"], warnings.join(","));
        }
        """

        let snapshot = try await CargoPackageManager().prepare(manifestSource: manifest)
        XCTAssertTrue(snapshot.isOfflineReady, "resolved source archives must be available locally")
        XCTAssertGreaterThanOrEqual(snapshot.plan.units.count, 6, "exercise a real dependency graph")
        XCTAssertTrue(
            snapshot.blockingPackages.isEmpty,
            snapshot.blockingPackages.map { "\($0.name): \($0.compatibility.detail ?? "")" }
                .joined(separator: "\n")
        )
        XCTAssertEqual(Set(snapshot.plan.rootExterns.map(\.alias)), ["hashbrown", "smallvec", "serde_json"])
        XCTAssertNotNil(snapshot.lockfile)

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
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "2:cache,timeout")
        XCTAssertTrue(compiler.isPlanCached(snapshot.plan, emit: .link))
    }

    func testRegexAndJSONLogAnalyzerBuildsAndRuns() async throws {
        try Self.requireCompilerGate()
        guard ProcessInfo.processInfo.environment["CRABRIX_RUN_UNSUPPORTED_CRATE_PROBE"] == "1" else {
            throw XCTSkip("The pinned compiler fails in the regex dependency graph; see docs/compiler-complex-gate-2026-10-01.md.")
        }
        let manifest = """
        [package]
        name = "log-analyzer-gate"
        version = "0.1.0"
        edition = "2024"

        [dependencies]
        regex = "=1.13.1"
        serde_json = "=1.0.151"
        """
        let source = """
        // fresh application revision: \(UUID())
        use regex::Regex;
        use serde_json::Value;

        fn main() {
            let input = r#"[{"line":"WARN disk almost full"},{"line":"INFO started"},{"line":"WARN retrying"}]"#;
            let records: Value = serde_json::from_str(input).unwrap();
            let warning = Regex::new(r"^WARN\\s+(.+)$").unwrap();
            let mut messages = Vec::new();
            for record in records.as_array().unwrap() {
                let line = record["line"].as_str().unwrap();
                if let Some(captures) = warning.captures(line) {
                    messages.push(captures[1].to_owned());
                }
            }
            println!("{}:{}", messages.len(), messages.join(","));
        }
        """

        let snapshot = try await CargoPackageManager().prepare(manifestSource: manifest)
        XCTAssertTrue(snapshot.isOfflineReady)
        XCTAssertTrue(snapshot.blockingPackages.isEmpty, snapshot.blockingPackages.map(\.id).joined(separator: ", "))
        XCTAssertGreaterThanOrEqual(snapshot.plan.units.count, 8)
        XCTAssertEqual(Set(snapshot.plan.rootExterns.map(\.alias)), ["regex", "serde_json"])
        XCTAssertNotNil(snapshot.lockfile)

        let compiler = WasmRustCompiler(bundle: .main)
        let result = await compiler.run(
            source: source,
            sourcePath: "src/main.rs",
            supportingFiles: ["Cargo.toml": manifest],
            plan: snapshot.plan
        )
        XCTAssertTrue(result.succeeded, "phase: \(result.phase.rawValue)\ndetail: \(result.detail)\nstderr: \(result.stderr)")
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "2:disk almost full,retrying")
        XCTAssertTrue(compiler.isPlanCached(snapshot.plan, emit: .link))
    }

    func testMultiFileDependencyRichLogMonitorBuildsAndRuns() async throws {
        try Self.requireCompilerGate()
        guard ProcessInfo.processInfo.environment["CRABRIX_RUN_UNSUPPORTED_CRATE_PROBE"] == "1" else {
            throw XCTSkip("The pinned compiler has unresolved multi-crate backend failures; see docs/compiler-complex-gate-2026-10-01.md.")
        }
        let manifest = """
        [package]
        name = "log-monitor-gate"
        version = "0.1.0"
        edition = "2024"

        [dependencies]
        regex = "=1.13.1"
        serde_json = "=1.0.151"
        hashbrown = "=0.17.1"
        smallvec = "=1.15.1"
        """
        let source = """
        // fresh application revision: \(UUID())
        mod ingest;
        mod report;

        fn main() {
            let input = r#"[
              {"source":"api","line":"WARN cache miss"},
              {"source":"worker","line":"INFO started"},
              {"source":"api","line":"WARN timeout"},
              {"source":"worker","line":"WARN cache miss"}
            ]"#;
            let incidents = ingest::read(input);
            println!("{}", report::summarize(&incidents));
        }
        """
        let ingest = """
        use regex::Regex;
        use serde_json::Value;

        pub struct Incident {
            pub source: String,
            pub message: String,
        }

        pub fn read(input: &str) -> Vec<Incident> {
            let rows: Value = serde_json::from_str(input).unwrap();
            let warning = Regex::new(r"^WARN\\s+(.+)$").unwrap();
            rows.as_array().unwrap().iter().filter_map(|row| {
                let source = row.get("source")?.as_str()?;
                let line = row.get("line")?.as_str()?;
                let captures = warning.captures(line)?;
                Some(Incident {
                    source: source.to_owned(),
                    message: captures[1].to_owned(),
                })
            }).collect()
        }
        """
        let report = """
        use hashbrown::HashMap;
        use smallvec::SmallVec;
        use crate::ingest::Incident;

        pub fn summarize(events: &[Incident]) -> String {
            let mut counts: HashMap<&str, usize> = HashMap::new();
            let mut issues: SmallVec<[String; 4]> = SmallVec::new();
            for event in events {
                *counts.entry(event.source.as_str()).or_default() += 1;
                if !issues.iter().any(|existing| existing == &event.message) {
                    issues.push(event.message.clone());
                }
            }
            issues.sort();
            format!("api={},worker={};issues={}",
                counts["api"], counts["worker"], issues.join(","))
        }
        """

        let snapshot = try await CargoPackageManager().prepare(manifestSource: manifest)
        XCTAssertTrue(snapshot.isOfflineReady)
        XCTAssertTrue(snapshot.blockingPackages.isEmpty, snapshot.blockingPackages.map(\.id).joined(separator: ", "))
        XCTAssertGreaterThanOrEqual(snapshot.plan.units.count, 8)
        XCTAssertEqual(Set(snapshot.plan.rootExterns.map(\.alias)), ["regex", "serde_json", "hashbrown", "smallvec"])
        XCTAssertNotNil(snapshot.lockfile)

        let compiler = WasmRustCompiler(bundle: .main)
        let result = await compiler.run(
            source: source,
            sourcePath: "src/main.rs",
            supportingFiles: [
                "Cargo.toml": manifest,
                "src/ingest.rs": ingest,
                "src/report.rs": report,
            ],
            plan: snapshot.plan
        )
        XCTAssertTrue(result.succeeded, "phase: \(result.phase.rawValue)\ndetail: \(result.detail)\nstderr: \(result.stderr)")
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
                       "api=2,worker=1;issues=cache miss,timeout")
        XCTAssertTrue(compiler.isPlanCached(snapshot.plan, emit: .link))
    }

    func testMultiFileClapRegexCollectionsAppBuildsAndRuns() async throws {
        try Self.requireCompilerGate()
        guard ProcessInfo.processInfo.environment["CRABRIX_RUN_UNSUPPORTED_CRATE_PROBE"] == "1" else {
            throw XCTSkip("Run the opt-in source-built toolchain gate for the dependency-rich CLI.")
        }
        let manifest = """
        [package]
        name = "logscan-multifile-gate"
        version = "0.1.0"
        edition = "2024"

        [dependencies]
        clap = "=4.5.50"
        regex = "=1.13.1"
        hashbrown = "=0.17.1"
        smallvec = "=1.15.1"
        """
        let source = """
        // fresh application revision: \(UUID())
        mod ingest;
        mod report;
        use clap::{Arg, Command};

        fn main() {
            let args = Command::new("logscan")
                .arg(Arg::new("pattern").long("pattern").required(true).num_args(1))
                .try_get_matches_from(["logscan", "--pattern", r"^WARN\\s+(.+)$"])
                .unwrap();
            let pattern = args.get_one::<String>("pattern").unwrap();
            let input = "api WARN cache miss\nworker INFO started\napi WARN timeout\nworker WARN cache miss";
            let incidents = ingest::scan(input, pattern);
            println!("{}", report::summarize(&incidents));
        }
        """
        let ingest = """
        use regex::Regex;

        pub struct Incident {
            pub source: String,
            pub message: String,
        }

        pub fn scan(input: &str, pattern: &str) -> Vec<Incident> {
            let warning = Regex::new(pattern).unwrap();
            input.lines().filter_map(|line| {
                let (source, message) = line.split_once(' ')?;
                let captures = warning.captures(message)?;
                Some(Incident {
                    source: source.to_owned(),
                    message: captures[1].to_owned(),
                })
            }).collect()
        }
        """
        let report = """
        use hashbrown::HashMap;
        use smallvec::SmallVec;
        use crate::ingest::Incident;

        pub fn summarize(events: &[Incident]) -> String {
            let mut counts: HashMap<&str, usize> = HashMap::new();
            let mut issues: SmallVec<[String; 4]> = SmallVec::new();
            for event in events {
                *counts.entry(event.source.as_str()).or_default() += 1;
                if !issues.iter().any(|existing| existing == &event.message) {
                    issues.push(event.message.clone());
                }
            }
            issues.sort();
            format!("api={},worker={};issues={}",
                counts["api"], counts["worker"], issues.join(","))
        }
        """

        let snapshot = try await CargoPackageManager().prepare(manifestSource: manifest)
        XCTAssertTrue(snapshot.isOfflineReady)
        XCTAssertTrue(snapshot.blockingPackages.isEmpty, snapshot.blockingPackages.map(\.id).joined(separator: ", "))
        XCTAssertGreaterThanOrEqual(snapshot.plan.units.count, 10)
        XCTAssertEqual(Set(snapshot.plan.rootExterns.map(\.alias)),
                       ["clap", "regex", "hashbrown", "smallvec"])
        XCTAssertNotNil(snapshot.lockfile)

        let compiler = WasmRustCompiler(bundle: .main)
        let result = await compiler.run(
            source: source,
            sourcePath: "src/main.rs",
            supportingFiles: [
                "Cargo.toml": manifest,
                "src/ingest.rs": ingest,
                "src/report.rs": report,
            ],
            plan: snapshot.plan
        )
        XCTAssertTrue(result.succeeded,
                      "phase: \(result.phase.rawValue)\ndetail: \(result.detail)\nstderr: \(result.stderr)")
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
                       "api=2,worker=1;issues=cache miss,timeout")
        XCTAssertTrue(compiler.isPlanCached(snapshot.plan, emit: .link))
    }

    func testClapRegexJSONCommandLineAppBuildsAndRuns() async throws {
        try Self.requireCompilerGate()
        guard ProcessInfo.processInfo.environment["CRABRIX_RUN_UNSUPPORTED_CRATE_PROBE"] == "1" else {
            throw XCTSkip("The pinned compiler has not passed this dependency-heavy CLI gate.")
        }
        let manifest = """
        [package]
        name = "logscan-cli-gate"
        version = "0.1.0"
        edition = "2024"

        [dependencies]
        clap = "=4.5.50"
        regex = "=1.13.1"
        serde_json = "=1.0.151"
        """
        let source = """
        // fresh application revision: \(UUID())
        use clap::{Arg, Command};
        use regex::Regex;
        use serde_json::Value;

        fn main() {
            let args = Command::new("logscan")
                .arg(Arg::new("pattern").long("pattern").required(true).num_args(1))
                .try_get_matches_from(["logscan", "--pattern", r"^WARN\\s+(.+)$"])
                .unwrap();
            let warning = Regex::new(args.get_one::<String>("pattern").unwrap()).unwrap();
            let rows: Value = serde_json::from_str(
                r#"[{"line":"WARN cache"},{"line":"INFO ready"},{"line":"WARN timeout"}]"#
            ).unwrap();
            let messages: Vec<String> = rows.as_array().unwrap().iter().filter_map(|row| {
                let line = row.get("line")?.as_str()?;
                Some(warning.captures(line)?[1].to_owned())
            }).collect();
            println!("{}:{}", messages.len(), messages.join(","));
        }
        """

        let snapshot = try await CargoPackageManager().prepare(manifestSource: manifest)
        XCTAssertTrue(snapshot.isOfflineReady)
        XCTAssertTrue(snapshot.blockingPackages.isEmpty, snapshot.blockingPackages.map(\.id).joined(separator: ", "))
        XCTAssertGreaterThanOrEqual(snapshot.plan.units.count, 10)
        XCTAssertEqual(Set(snapshot.plan.rootExterns.map(\.alias)), ["clap", "regex", "serde_json"])
        XCTAssertNotNil(snapshot.lockfile)

        let compiler = WasmRustCompiler(bundle: .main)
        let result = await compiler.run(
            source: source,
            sourcePath: "src/main.rs",
            supportingFiles: ["Cargo.toml": manifest],
            plan: snapshot.plan
        )
        XCTAssertTrue(result.succeeded,
                      "phase: \(result.phase.rawValue)\ndetail: \(result.detail)\nstderr: \(result.stderr)")
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
                       "2:cache,timeout")
        XCTAssertTrue(compiler.isPlanCached(snapshot.plan, emit: .link))
    }

    func testVendoredCrateBuildsFromAProjectLocalPatch() async throws {
        guard ProcessInfo.processInfo.environment["CRABRIX_RUN_COMPILER_GATE"] == "1" else {
            throw XCTSkip("Run the CrabrixCompilerGate scheme for the Vendor & Edit gate.")
        }

        let manifest = """
        [package]
        name = "vendor-gate"
        version = "0.1.0"
        edition = "2024"

        [dependencies]
        smallvec = "1"
        """
        let source = """
        use smallvec::SmallVec;

        fn main() {
            let values: SmallVec<[u32; 4]> = [4, 8, 15].into_iter().collect();
            println!("{}", values.iter().sum::<u32>());
        }
        """
        let manager = CargoPackageManager()
        let registry = try await manager.prepare(manifestSource: manifest)
        let registryUnit = try XCTUnwrap(
            registry.plan.units.first { $0.package.name == "smallvec" }
        )
        let package = registryUnit.package
        let vendorRoot = "vendor/\(package.name)-\(package.version)"
        let editable = try CrateSourceBrowser.vendorableFiles(
            name: package.name,
            version: package.version
        )
        var projectFiles: [String: String] = Dictionary(
            uniqueKeysWithValues: editable.map { ("\(vendorRoot)/\($0.key)", $0.value) }
        )
        let patchedLibrary = "\(vendorRoot)/src/lib.rs"
        projectFiles[patchedLibrary, default: ""] += "\n// Crabrix local patch gate.\n"

        let patched = try await manager.prepare(
            manifestSource: manifest,
            projectFiles: projectFiles
        )
        let patchedUnit = try XCTUnwrap(
            patched.plan.units.first { $0.package == package }
        )

        XCTAssertTrue(patchedUnit.isLocallyPatched)
        XCTAssertNotEqual(patchedUnit.fingerprint, registryUnit.fingerprint)
        XCTAssertTrue(
            patched.packages.first { $0.package == package }?.isLocallyPatched == true
        )

        let result = await WasmRustCompiler(bundle: .main).run(
            source: source,
            sourcePath: "src/main.rs",
            supportingFiles: projectFiles.merging(["Cargo.toml": manifest]) { current, _ in current },
            plan: patched.plan
        )
        XCTAssertTrue(result.succeeded, "\(result.detail)\n\(result.stderr)")
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "27")
    }

    func testOfflinePinRehydratesSourcesAfterPurgeableCacheEviction() async throws {
        guard ProcessInfo.processInfo.environment["CRABRIX_RUN_COMPILER_GATE"] == "1" else {
            throw XCTSkip("Run the CrabrixCompilerGate scheme for the durable offline gate.")
        }
        let manifest = """
        [package]
        name = "offline-pin-gate"
        version = "0.1.0"
        edition = "2024"

        [dependencies]
        smallvec = "1"
        """
        let manager = CargoPackageManager()

        do {
            let fetched = try await manager.prepare(manifestSource: manifest)
            let package = try XCTUnwrap(
                fetched.packages.first { $0.name == "smallvec" }
            )
            let lockfile = try XCTUnwrap(fetched.lockfile)
            try await manager.pinForOffline(fetched.packages)

            let pinned = try await manager.prepare(
                manifestSource: manifest,
                lockfileSource: lockfile,
                mode: .frozen
            )
            XCTAssertTrue(pinned.isOfflinePinned)

            let indexSentinel = try XCTUnwrap(CrateStorageLayout.indexCacheDirectory)
                .appending(path: ".offline-pin-gate-\(UUID().uuidString)")
            try Data("index survives cache clear".utf8).write(to: indexSentinel, options: .atomic)
            defer { try? FileManager.default.removeItem(at: indexSentinel) }

            try await manager.clearPackageCache()
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: indexSentinel.path),
                "clearing purgeable package data must retain the registry index"
            )
            XCTAssertFalse(
                CrateStorageLayout.sourceDirectory(
                    name: package.name,
                    version: package.version
                ).map { FileManager.default.fileExists(atPath: $0.path) } ?? true
            )
            XCTAssertFalse(
                CrateStorageLayout.archiveURL(
                    name: package.name,
                    version: package.version
                ).map { FileManager.default.fileExists(atPath: $0.path) } ?? true
            )

            let rehydrated = try await manager.prepare(
                manifestSource: manifest,
                lockfileSource: lockfile,
                mode: .frozen
            )
            XCTAssertTrue(rehydrated.isOfflineReady)
            XCTAssertTrue(rehydrated.isOfflinePinned)
            XCTAssertTrue(
                CrateStorageLayout.sourceDirectory(
                    name: package.name,
                    version: package.version
                ).map { FileManager.default.fileExists(atPath: $0.path) } == true
            )
            try await manager.clearOfflinePins()
        } catch {
            try? await manager.clearOfflinePins()
            throw error
        }
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
        // Optimised Release checks can finish before three seconds. Request
        // Stop early, as the view-model drain gate below does, so this tests
        // cancellation rather than cancelling an already completed compile.
        try await Task.sleep(for: .milliseconds(100))
        compiler.cancel()

        let value = await result
        let elapsed = ContinuousClock.now - started

        XCTAssertFalse(value.succeeded)
        XCTAssertTrue(
            value.detail.contains("stopped"),
            "expected a stop result, got: \(value.detail)"
        )
        // Includes the initial module parse, which is not interruptible.
        // The stopped result above distinguishes cancellation from completion.
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

        // The first stop of a session may have to wait out one uninterruptible
        // phase: reading and parsing the bundled rustc module. That happens
        // once per compiler instance, so it is given room rather than pretended
        // away.
        let firstDrain = try await stopAndMeasureDrain(model: model, allowing: .seconds(120))
        XCTAssertNotNil(firstDrain, "The cancelled worker never released the Run gate.")
        XCTAssertTrue(model.canStartBuild, "Run stayed disabled after the compiler worker exited.")

        // Every stop after it is the one users actually repeat, and it has to
        // be prompt: the module is parsed, so only the guest has to trap.
        let secondDrain = try await stopAndMeasureDrain(model: model, allowing: .seconds(10))
        let warm = try XCTUnwrap(secondDrain, "A warm stop left Run disabled past 10 seconds.")
        XCTAssertLessThan(warm, .seconds(5), "A warm stop should free Run in seconds, not tens")
        XCTAssertTrue(model.canStartBuild)
    }

    /// Starts a check, stops it, and reports how long Run stayed disabled.
    /// Returns nil when the worker never drained inside `budget`.
    @MainActor
    private func stopAndMeasureDrain(
        model: CompilerViewModel,
        allowing budget: Duration
    ) async throws -> Duration? {
        model.check()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(model.isBusy, "The compiler finished before the stop gate could exercise it.")

        model.cancelBuild()
        XCTAssertTrue(model.isCompilerDraining)
        XCTAssertFalse(model.canStartBuild)

        let clock = ContinuousClock()
        let started = clock.now
        let deadline = started.advanced(by: budget)
        while model.isCompilerDraining, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        return model.isCompilerDraining ? nil : started.duration(to: clock.now)
    }
}
