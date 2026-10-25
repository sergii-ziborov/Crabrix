import Foundation
import Darwin
import CryptoKit
import UIKit
import XCTest
@_spi(Fuzzing) import WasmKit
@testable import Crabrix

final class BundledCompilerGateTests: XCTestCase {
    private var macroSysrootOverlays: [URL] = []
    private func measuredCompiler(dependencyArtifactRoot: URL? = nil,
                                  experimentalDirectOverride: Bool? = nil,
                                  candidateProfileOverride: Bool? = nil,
                                  candidateArtifactName: String? = nil) throws -> WasmRustCompiler {
        let direct = experimentalDirectOverride
            ?? (ProcessInfo.processInfo.environment["CRABRIX_EXPERIMENTAL_DIRECT_GATE"] == "1")
        print("MEASURED COMPILER DISPATCH", direct ? "experimental-direct" : "production-token")
        var candidate: BundledToolchain?
        if candidateProfileOverride ?? (ProcessInfo.processInfo.environment["CRABRIX_COMPILER_CANDIDATE_PROFILE"] == "1") {
            let artifactName = candidateArtifactName
                ?? ProcessInfo.processInfo.environment["CRABRIX_COMPILER_CANDIDATE_ARTIFACT"] ?? "Artifact"
            guard ["Artifact", "ArtifactO2", "ArtifactFat", "ArtifactMacro"].contains(artifactName)
            else { throw CocoaError(.fileReadCorruptFile) }
            let resources = try XCTUnwrap(Bundle(for: Self.self).resourceURL)
                .appending(path: "CompilerCandidate/" + artifactName)
            let provenance = try JSONSerialization.jsonObject(
                with: Data(contentsOf: resources.appending(path: "provenance.json"))) as? [String: Any]
            let compilerURL = resources.appending(path: "rustc.wasm")
            let bytes = try Data(contentsOf: compilerURL, options: [.mappedIfSafe])
            let sha = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            guard provenance?["candidate"] as? Bool == true,
                  provenance?["productionReplacement"] as? Bool == false,
                  provenance?["compilerSHA256"] as? String == sha,
                  provenance?["compilerBytes"] as? Int == bytes.count,
                  Array(bytes.prefix(8)) == [0, 97, 115, 109, 1, 0, 0, 0]
            else { throw CocoaError(.fileReadCorruptFile) }
            let baseline = try XCTUnwrap(BundledToolchain.locate(in: .main, version: CargoToolchain.bundledVersion))
            var sysroot = baseline.sysrootURL
            var identity = "candidate-" + sha
            if artifactName == "ArtifactMacro", let capture = provenance?["candidateSysroot"] as? [String: Any] {
                let inventoryURL = resources.appending(path: "sysroot-files.json")
                let inventoryBytes = try Data(contentsOf: inventoryURL)
                let inventory = try XCTUnwrap(try JSONSerialization.jsonObject(with: inventoryBytes) as? [String: Any])
                let files = try XCTUnwrap(inventory["files"] as? [[String: Any]])
                let inventorySHA = SHA256.hash(data: inventoryBytes).map { String(format: "%02x", $0) }.joined()
                let archiveSHA = SHA256.hash(data: try Data(contentsOf: resources.appending(path: "sysroot-wasip1.zip")))
                    .map { String(format: "%02x", $0) }.joined()
                guard capture["inventorySHA256"] as? String == inventorySHA,
                      capture["archiveSHA256"] as? String == archiveSHA,
                      capture["fileCount"] as? Int == files.count,
                      inventory["schemaVersion"] as? Int == 1, !files.isEmpty
                else { throw CocoaError(.fileReadCorruptFile) }
                let root = resources.resolvingSymlinksInPath()
                var names = Set<String>()
                for item in files {
                    let name = try XCTUnwrap(item["path"] as? String)
                    let parts = name.split(separator: "/", omittingEmptySubsequences: false)
                    guard parts.first == "sysroot-wasip1", parts.count > 1,
                          parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                          names.insert(name).inserted
                    else { throw CocoaError(.fileReadCorruptFile) }
                    let file = root.appending(path: name).resolvingSymlinksInPath()
                    guard file.path.hasPrefix(root.path + "/") else { throw CocoaError(.fileReadCorruptFile) }
                    let data = try Data(contentsOf: file)
                    guard data.count == item["bytes"] as? Int,
                          SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == item["sha256"] as? String
                    else { throw CocoaError(.fileReadCorruptFile) }
                }
                guard names.contains("sysroot-wasip1/manifest.json") else { throw CocoaError(.fileReadCorruptFile) }
                let tree = try XCTUnwrap(FileManager.default.enumerator(at: root.appending(path: "sysroot-wasip1"),
                    includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]))
                var actual = Set<String>()
                for case let file as URL in tree {
                    let kind = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                    guard kind.isSymbolicLink != true else { throw CocoaError(.fileReadCorruptFile) }
                    if kind.isRegularFile == true { actual.insert(String(file.path.dropFirst(root.path.count + 1))) }
                }
                guard actual == names else { throw CocoaError(.fileReadCorruptFile) }
                sysroot = resources.appending(path: "sysroot-wasip1")
                identity += "-sysroot-" + inventorySHA
                print("MACRO SYSROOT MODE source-built stage1", inventorySHA)
            } else if artifactName == "ArtifactMacro" {
                let supplementURL = resources.appending(path: "supplemental-sysroot.json")
                let supplementBytes = try Data(contentsOf: supplementURL)
                let supplement = try XCTUnwrap(try JSONSerialization.jsonObject(with: supplementBytes) as? [String: Any])
                let libraries = try XCTUnwrap(supplement["libraries"] as? [String: [String: Any]])
                guard supplement["candidate"] as? Bool == true,
                      supplement["productionReplacement"] as? Bool == false,
                      Set(libraries.keys) == Set(["libproc_macro.rlib", "librustc_literal_escaper.rlib"])
                else { throw CocoaError(.fileReadCorruptFile) }
                let overlay = FileManager.default.temporaryDirectory.appending(path: "MacroSysroot-\(UUID())")
                try FileManager.default.copyItem(at: baseline.sysrootURL, to: overlay)
                macroSysrootOverlays.append(overlay)
                for name in libraries.keys.sorted() {
                    let data = try Data(contentsOf: resources.appending(path: name))
                    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                    guard libraries[name]?["sha256"] as? String == digest,
                          libraries[name]?["bytes"] as? Int == data.count
                    else { throw CocoaError(.fileReadCorruptFile) }
                    try data.write(to: overlay.appending(path: "lib/rustlib/wasm32-wasip1/lib/" + name))
                }
                sysroot = overlay
                identity += "-" + SHA256.hash(data: supplementBytes).map { String(format: "%02x", $0) }.joined()
                print("MACRO SYSROOT MODE signed baseline with explicitly hashed prototype API overlay")
            }
            candidate = BundledToolchain(rustcURL: compilerURL, sysrootURL: sysroot,
                                         version: identity, supportsProceduralMacros: artifactName == "ArtifactMacro",
                                         compilerSHA256: sha)
            print("MEASURED COMPILER CANDIDATE SHA256", sha)
        }
        print("MEASURED COMPILER INPUT", candidate?.version ?? CargoToolchain.artifactIdentity)
        #if CRABRIX_NATIVE_COMPILER
        if ProcessInfo.processInfo.environment["CRABRIX_REQUIRE_NATIVE_COMPILER"] == "1" {
            guard let candidate, candidate.compilerSHA256 == NativeRustcSession.compilerSHA256 else {
                throw NSError(domain: "CrabrixNativeQualification", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "The requested native compiler is not linked to this exact candidate"])
            }
            print("MEASURED COMPILER BACKEND native-static", NativeRustcSession.compilerSHA256)
        }
        #else
        if ProcessInfo.processInfo.environment["CRABRIX_REQUIRE_NATIVE_COMPILER"] == "1" {
            throw NSError(domain: "CrabrixNativeQualification", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "This build has no enabled native compiler candidate"])
        }
        #endif
        return WasmRustCompiler(ledger: candidate == nil && dependencyArtifactRoot == nil
                                    ? .shared : CrateCompatibilityLedger(storageURL: nil),
                                runtime: RustcRuntime(experimentalSoftwareDirect: direct),
                                dependencyArtifactRoot: dependencyArtifactRoot,
                                toolchainOverride: candidate)
    }
    private var previousIdleTimerDisabled: Bool?

    private func requireProcMacroBridge() throws {
        try Self.requireCompilerGate()
        try XCTSkipIf(ProcessInfo.processInfo.environment["CRABRIX_RUN_PROC_MACRO_BRIDGE"] != "1")
    }

    func testMacroCandidateInputBindsCompilerAndCompleteSourceSysroot() throws {
        try requireProcMacroBridge()
        // The helper checks the compiler hash, source-build provenance, ZIP,
        // inventory and every sysroot byte before constructing this runtime.
        // The final signed app bundle has a separate AppToolchainRelease gate.
        _ = try measuredCompiler(experimentalDirectOverride: true,
            candidateProfileOverride: true, candidateArtifactName: "ArtifactMacro")
    }

    /// Diagnose RPC independently while the fixed in-compiler linker rebuilds.
    /// A manually linked reactor is never a cold-build acceptance result.
    func testPrelinkedIdentityRPCProbe() async throws {
        try requireProcMacroBridge()
        let mode = ProcessInfo.processInfo.environment["CRABRIX_PROC_MACRO_LINK_PROBE"]
        try XCTSkipUnless(mode == "emit" || mode == "consume")
        _ = try measuredCompiler(experimentalDirectOverride: true,
            candidateProfileOverride: true, candidateArtifactName: "ArtifactMacro")
        let resources = try XCTUnwrap(Bundle(for: Self.self).resourceURL)
        let candidate = resources.appending(path: "CompilerCandidate/ArtifactMacro")
        let fixture = resources.appending(path: "CompilerCandidate/Fixtures/ProcMacroIdentity")
        let work = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
            .appending(path: "CompilerBridgeLinkProbe")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let runtime = RustcRuntime(experimentalSoftwareDirect: true)
        let module = try runtime.rustcModule(at: candidate.appending(path: "rustc.wasm"))
        let common = ["--sysroot", "/sysroot", "--target", "wasm32-wasip1", "--edition", "2021", "-Copt-level=0", "-Cpanic=abort"]
        let args: [String]
        if mode == "emit" {
            args = ["/fixture/lib.rs", "--crate-type", "proc-macro", "--crate-name", "crabrix_proc_macro_identity",
                    "--emit=obj,metadata", "-Csave-temps", "--out-dir", "/work"] + common
        } else {
            args = ["/fixture/consumer/main.rs", "--extern", "crabrix_proc_macro_identity=/work/identity.wasm",
                    "-o", "/work/program.wasm"] + common
        }
        let result = try runtime.run(module: module, arguments: ["rustc"] + args,
            environment: ["CLIF2WASM_OBJECT": "1", "RUSTC_BOOTSTRAP": "1", "CRABRIX_WASM_PROC_MACROS": "1"],
            preopens: [.init(guestPath: "/work", hostPath: work.path),
                       .init(guestPath: "/tmp", hostPath: work.path),
                       .init(guestPath: "/fixture", hostPath: fixture.path, readOnly: true),
                       .init(guestPath: "/sysroot", hostPath: candidate.appending(path: "sysroot-wasip1").path, readOnly: true)],
            captureDirectory: work, capturePrefix: "probe-\(mode ?? "")",
            resourceLimiter: WasmSandboxResourceLimiter(memoryLimitBytes: CompilerHostPolicy.memoryLimitBytes,
                tableElementLimit: CompilerHostPolicy.tableElementLimit),
            fuelBudget: CompilerHostPolicy.fuelBudget, wallClockLimit: .seconds(240),
            interrupter: WasmInterrupter(), softwareMemoryReservationBytes: CompilerHostPolicy.memoryLimitBytes,
            capturedOutputLimitBytes: CompilerHostPolicy.outputLimitBytes, enableProceduralMacros: true)
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        if mode == "consume", result.exitCode == 0 {
            let program = try runtime.run(module: parseWasm(filePath: work.appending(path: "program.wasm").path),
                arguments: ["program"], environment: [:], preopens: [], captureDirectory: work, capturePrefix: "program",
                resourceLimiter: WasmSandboxResourceLimiter(), fuelBudget: WasmSandboxPolicy.userProgramInstructionBudget,
                wallClockLimit: .seconds(10), interrupter: WasmInterrupter(),
                capturedOutputLimitBytes: WasmSandboxPolicy.userProgramOutputLimitBytes)
            XCTAssertEqual(program.exitCode, 0, program.stderr)
            XCTAssertEqual(program.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "macro identity: 42")
        }
    }

    func testWASIProcMacroIdentityUsesTheUnchangedMacroSource() async throws {
        try requireProcMacroBridge()
        let fixture = try XCTUnwrap(Bundle(for: Self.self).resourceURL)
            .appending(path: "CompilerCandidate/Fixtures/ProcMacroIdentity")
        let source = try String(contentsOf: fixture.appending(path: "lib.rs"), encoding: .utf8)
        let consumer = try String(contentsOf: fixture.appending(path: "consumer/main.rs"), encoding: .utf8)
        let manifest = try String(contentsOf: fixture.appending(path: "consumer/Cargo.toml"), encoding: .utf8)
        let registry = try XCTUnwrap(CrateStorageLayout.sourceDirectory)
        let directoryName = "macro-identity-fixture-\(UUID())"
        let directory = registry.appending(path: directoryName)
        let artifacts = FileManager.default.temporaryDirectory.appending(path: "MacroArtifacts-\(UUID())")
        try FileManager.default.createDirectory(at: directory.appending(path: "src"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory); try? FileManager.default.removeItem(at: artifacts) }
        try source.write(to: directory.appending(path: "src/lib.rs"), atomically: true, encoding: .utf8)
        let fingerprint = SHA256.hash(data: Data(source.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        let unit = CargoBuildUnit(
            package: PackageID(name: "crabrix-proc-macro-identity", version: try XCTUnwrap(SemanticVersion("0.1.0"))),
            fingerprint: fingerprint, crateName: "crabrix_proc_macro_identity", edition: "2021", features: [],
            libraryPath: "src/lib.rs", source: .registry(directoryName: directoryName), externs: [],
            authors: "", description: "", repository: "", license: "", homepage: "",
            isProceduralMacro: true, requiresLink: true)
        let plan = CargoBuildPlan(units: [unit], rootExterns: [
            CargoExtern(alias: unit.crateName, crateName: unit.crateName, fingerprint: fingerprint,
                        isProceduralMacro: true, requiresLink: true)
        ], rootFeatures: [])
        let compiler = try measuredCompiler(dependencyArtifactRoot: artifacts, experimentalDirectOverride: true,
                                            candidateProfileOverride: true, candidateArtifactName: "ArtifactMacro")
        // Compiler/transport acceptance only: a local unchanged fixture is
        // injected into the plan. Registry resolution is covered separately.
        let checked = await compiler.check(source: consumer, sourcePath: "src/main.rs",
            supportingFiles: ["Cargo.toml": manifest], edition: "2021", plan: plan)
        XCTAssertTrue(checked.succeeded, checked.detail + "\n" + checked.stderr)
        let result = await compiler.run(source: consumer, sourcePath: "src/main.rs",
            supportingFiles: ["Cargo.toml": manifest], edition: "2021", plan: plan)
        print("MACRO IDENTITY DURATION", result.duration)
        XCTAssertTrue(result.succeeded, result.detail + "\n" + result.stderr)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "macro identity: 42")
    }

    func testSerdeDeriveRunsThroughTheOfflineWASIMacroBridge() async throws {
        try requireProcMacroBridge()
        let manifest = """
        [package]
        name = "offline-derive-gate"
        version = "0.1.0"
        edition = "2021"
        [dependencies]
        serde = { version = "=1.0.229", features = ["derive"] }
        serde_json = "=1.0.151"
        """
        let manager = CargoPackageManager(supportsProceduralMacros: true)
        let prepared = try await manager.prepare(manifestSource: manifest)
        XCTAssertTrue(prepared.blockingPackages.isEmpty, prepared.blockingPackages.description)
        try await manager.pinForOffline(prepared.packages)
        let lockfile = try XCTUnwrap(prepared.lockfile)
        let frozen = try await CargoPackageManager(supportsProceduralMacros: true).prepare(
            manifestSource: manifest, lockfileSource: lockfile, mode: .frozen)
        XCTAssertTrue(frozen.isOfflinePinned)
        XCTAssertTrue(frozen.plan.units.contains { $0.package.name == "serde_derive" && $0.isProceduralMacro })
        let artifacts = FileManager.default.temporaryDirectory.appending(path: "DeriveArtifacts-\(UUID())")
        defer { try? FileManager.default.removeItem(at: artifacts) }
        let result = try await measuredCompiler(dependencyArtifactRoot: artifacts,
            experimentalDirectOverride: true, candidateProfileOverride: true, candidateArtifactName: "ArtifactMacro").run(
                source: """
                // fresh derive compilation \(UUID())
                #[derive(serde::Serialize, serde::Deserialize, Debug, PartialEq)]
                struct Task { name: String, done: bool }
                fn main() {
                    let task: Task = serde_json::from_str(r#"{"name":"offline","done":true}"#).unwrap();
                    assert_eq!(task, Task { name: "offline".into(), done: true });
                    let json = serde_json::to_string(&task).unwrap();
                    assert_eq!(json, r#"{"name":"offline","done":true}"#);
                    println!("offline derive: ok");
                }
                """, sourcePath: "src/main.rs", supportingFiles: ["Cargo.toml": manifest, "Cargo.lock": lockfile],
                edition: "2021", plan: frozen.plan,
                onDependencyProgress: { progress in
                    print("DERIVE UNIT", progress)
                    XCTAssertFalse(progress.wasCached)
                }, onStage: { print("DERIVE STAGE", Date(), $0) })
        print("DERIVE COMPILER DURATION", result.duration)
        XCTAssertTrue(result.succeeded, result.detail + "\n" + result.stderr)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "offline derive: ok")
    }

    private func prepareKameoAcceptance() async throws -> (source: String, manifest: String, lock: String, plan: CargoBuildPlan) {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).resourceURL)
            .appending(path: "CompilerCandidate/Fixtures/KameoActors")
        let source = try String(contentsOf: fixture.appending(path: "main.rs"), encoding: .utf8)
        let manifest = try String(contentsOf: fixture.appending(path: "Cargo.toml"), encoding: .utf8)
        let lock = try String(contentsOf: fixture.appending(path: "Cargo.lock"), encoding: .utf8)
        let manager = CargoPackageManager(supportsProceduralMacros: true)
        let resolved = try await manager.prepare(manifestSource: manifest, lockfileSource: lock, mode: .locked)
        XCTAssertEqual(resolved.lockfile, lock, "Preserve the unchanged desktop lockfile byte for byte")
        XCTAssertTrue(resolved.blockingPackages.isEmpty, resolved.blockingPackages.description)
        try await manager.pinForOffline(resolved.packages)
        let frozen = try await CargoPackageManager(supportsProceduralMacros: true)
            .prepare(manifestSource: manifest, lockfileSource: lock, mode: .frozen)
        XCTAssertTrue(frozen.isOfflinePinned)
        XCTAssertEqual(frozen.lockfile, lock)
        XCTAssertEqual(frozen.packages.count + 1, 32, "Include the driver in Cargo's 32-package graph; do not substitute a smaller graph")
        XCTAssertEqual(Set(frozen.plan.units.filter(\.isProceduralMacro).map { $0.package.description }), Set([
            "futures-macro 0.3.34", "kameo_macros 0.21.1", "serde_derive 1.0.229",
            "tokio-macros 2.7.2", "tracing-attributes 0.1.31"
        ]))
        let kameo = try XCTUnwrap(frozen.packages.first { $0.name == "kameo" })
        XCTAssertTrue(kameo.features.contains("macros"))
        XCTAssertTrue(kameo.features.contains("tracing"))
        for (name, text) in [("manifest", manifest), ("lock", lock), ("source", source)] {
            print("KAMEO FIXTURE SHA256", name, SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined())
        }
        return (source, manifest, lock, frozen.plan)
    }

    func testUnchangedKameoGraphPreparesWithAllFiveMacroCrates() async throws {
        try requireProcMacroBridge()
        _ = try await prepareKameoAcceptance()
    }

    func testUnchangedKameoColdActorsAndChangedRootRunOffline() async throws {
        try requireProcMacroBridge()
        try requireColdComparison()
        let fixture = try await prepareKameoAcceptance()
        let artifacts = FileManager.default.temporaryDirectory.appending(path: "KameoColdArtifacts-\(UUID())")
        defer { try? FileManager.default.removeItem(at: artifacts) }
        let compiler = try measuredCompiler(dependencyArtifactRoot: artifacts, experimentalDirectOverride: true,
                                            candidateProfileOverride: true, candidateArtifactName: "ArtifactMacro")
        print("KAMEO COLD THERMAL BEGIN", ProcessInfo.processInfo.thermalState.rawValue)
        let cold = await compiler.run(source: fixture.source, sourcePath: "src/main.rs",
            supportingFiles: ["Cargo.toml": fixture.manifest, "Cargo.lock": fixture.lock], edition: "2024", plan: fixture.plan,
            onDependencyProgress: { progress in print("KAMEO COLD UNIT", progress); XCTAssertFalse(progress.wasCached) },
            onStage: { print("KAMEO COLD STAGE", Date(), $0) })
        print("KAMEO COLD DURATION", cold.duration)
        print("KAMEO COLD THERMAL END", ProcessInfo.processInfo.thermalState.rawValue)
        XCTAssertTrue(cold.succeeded, cold.detail + "\n" + cold.stderr)
        XCTAssertEqual(cold.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "kameo offline: actors=16 records=1024 sum=523776")
        guard cold.succeeded else { return }
        print("KAMEO CHANGED ROOT THERMAL BEGIN", ProcessInfo.processInfo.thermalState.rawValue)
        let changed = await compiler.run(source: "// changed root \(UUID())\n" + fixture.source, sourcePath: "src/main.rs",
            supportingFiles: ["Cargo.toml": fixture.manifest, "Cargo.lock": fixture.lock], edition: "2024", plan: fixture.plan,
            onDependencyProgress: { progress in print("KAMEO CHANGED ROOT UNIT", progress); XCTAssertTrue(progress.wasCached) })
        print("KAMEO CHANGED ROOT DURATION", changed.duration)
        print("KAMEO CHANGED ROOT THERMAL END", ProcessInfo.processInfo.thermalState.rawValue)
        XCTAssertTrue(changed.succeeded, changed.detail + "\n" + changed.stderr)
        XCTAssertEqual(changed.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "kameo offline: actors=16 records=1024 sum=523776")
        // Record real timings even above the requested goal. Functional success
        // does not imply the separate 30-second physical performance gate passed.
    }

    override func setUp() async throws {
        try await super.setUp()
        #if !targetEnvironment(simulator)
        previousIdleTimerDisabled = await MainActor.run {
            let previous = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
            return previous
        }
        #endif
    }

    override func tearDown() async throws {
        for overlay in macroSysrootOverlays { try? FileManager.default.removeItem(at: overlay) }
        macroSysrootOverlays.removeAll()
        if let previous = previousIdleTimerDisabled {
            await MainActor.run { UIApplication.shared.isIdleTimerDisabled = previous }
        }
        try await super.tearDown()
    }

    func testRustGeneratesAnOfflineHTMLCSSJavaScriptPreview() async throws {
        try Self.requireCompilerGate()
        var files = WebProjectSamples.files.reduce(into: [String: String]()) { $0["web/" + $1.key] = $1.value }
        files["Cargo.toml"] = "[package]\nname = \"offline_web\"\nversion = \"0.1.0\"\nedition = \"2021\"\n"
        let result = try await measuredCompiler().run(
            source: "// fresh generator \(UUID())\n" + WebProjectSamples.rustGenerator,
            sourcePath: "src/main.rs", supportingFiles: files, edition: "2021",
            onStage: { stage in print("GENERATOR STAGE", Date(), stage) })
        print("GENERATOR COMPILER DURATION", result.duration)
        XCTAssertTrue(result.succeeded, result.detail + "\n" + result.stderr)
        let preview = try XCTUnwrap(result.webPreview)
        XCTAssertEqual(preview.entryPath, "index.html")
        XCTAssertNotNil(preview.assets["app.js"])
        XCTAssertNotNil(preview.assets["styles.css"])
    }

    @MainActor
    func testRunKeepsMainActorResponsiveAtUserInitiatedPriority() async throws {
        try Self.requireCompilerGate()
        let compiler = try measuredCompiler()
        let source = "// fresh responsiveness probe \(UUID())\nfn main() { println!(\"responsive run\"); }"
        let clock = ContinuousClock()
        var running = true
        let task = Task {
            defer { running = false }
            return await compiler.run(source: source, onStage: { stage in
                XCTAssertFalse(Thread.isMainThread)
                XCTAssertGreaterThanOrEqual(qos_class_self().rawValue, QOS_CLASS_USER_INITIATED.rawValue)
                print("INTERACTIVE RUN STAGE", Date(), stage, "qos", qos_class_self().rawValue)
            })
        }
        var previous = clock.now
        var longestGap = Duration.zero
        while running {
            try await Task.sleep(for: .milliseconds(50))
            let now = clock.now
            longestGap = max(longestGap, previous.duration(to: now))
            previous = now
        }
        let result = await task.value
        print("INTERACTIVE MAIN ACTOR MAX GAP", longestGap)
        print("INTERACTIVE RUN DURATION", result.duration)
        XCTAssertLessThan(longestGap, .milliseconds(500), "Compilation stalled the UI actor")
        XCTAssertTrue(result.succeeded, result.detail + "\n" + result.stderr)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "responsive run")
    }

    func testProjectBuildScriptTracksInputsAndExposesGeneratedCodeAndCfg() async throws {
        try Self.requireCompilerGate()
        let manifest = """
        [package]
        name = "generated-project"
        version = "0.1.0"
        edition = "2021"
        """
        let script = #"""
        use std::{env, fs, path::PathBuf};
        fn main() {
            assert_eq!(env::var("RUSTC").unwrap(), "rustc");
            assert!(std::process::Command::new("rustc").arg("--version").output().is_err());
            let text = fs::read_to_string("settings/greeting.txt").unwrap();
            let out = PathBuf::from(env::var_os("OUT_DIR").unwrap());
            fs::write(out.join("greeting.rs"), format!("pub const GREETING: &str = {text:?};")).unwrap();
            println!("cargo::rustc-check-cfg=cfg(generated_greeting)");
            println!("cargo::rustc-cfg=generated_greeting");
            println!("cargo::rustc-env=GENERATED_KIND=offline");
            println!("cargo::rerun-if-changed=settings/greeting.txt");
        }
        """#
        let source = #"""
        include!(concat!(env!("OUT_DIR"), "/greeting.rs"));
        #[cfg(generated_greeting)]
        fn main() { println!("{}:{}", env!("GENERATED_KIND"), GREETING); }
        """#
        let compiler = try measuredCompiler()
        for greeting in ["hello", "changed"] {
            let result = await compiler.run(
                source: source, sourcePath: "src/main.rs",
                supportingFiles: ["Cargo.toml": manifest, "build.rs": script,
                                  "settings/greeting.txt": greeting], edition: "2021")
            XCTAssertTrue(result.succeeded, "\(result.detail)\n\(result.stderr)")
            XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "offline:\(greeting)")
        }
    }

    func testMarkdownAndTemplatesRenderARealHTMLPageOffline() async throws {
        try Self.requireCompilerGate()
        try await runOfflineWebFixture(name: "offline-static-page", dependencies: """
        pulldown-cmark = { version = "=0.13.5", default-features = false, features = ["html"] }
        minijinja = "=3.0.3"
        """, source: """
        use minijinja::{Environment, context};
        fn main() {
            let mut html = String::new();
            pulldown_cmark::html::push_html(&mut html,
                pulldown_cmark::Parser::new("# Offline Rust\\n\\nA **real** page."));
            assert!(html.contains("<strong>real</strong>"));
            let mut env = Environment::new();
            env.add_template("page.html", "<!doctype html><title>{{ title }}</title><main>{{ body|safe }}</main>").unwrap();
            let page = env.get_template("page.html").unwrap()
                .render(context!(title => "Rust & Web", body => html)).unwrap();
            assert!(page.contains("<title>Rust &amp; Web</title>"));
            assert!(page.contains("<h1>Offline Rust</h1>"));
            println!("offline static page: ok");
        }
        """, expected: "offline static page: ok")
    }

    func testAxumRoutesARealHTTPRequestWithoutATCPServer() async throws {
        try Self.requireCompilerGate()
        try await runAxumOfflineProbe(cold: false)
    }

    func testAxumColdRouterWithTokio() async throws {
        try requireColdComparison()
        try await runAxumOfflineProbe(cold: true)
    }

    private func runAxumOfflineProbe(cold: Bool) async throws {
        try await runOfflineWebFixture(name: "offline-axum-router", dependencies: """
        axum = { version = "=0.8.9", default-features = false }
        tower = { version = "=0.5.2", default-features = false, features = ["util"] }
        tokio = { version = "=1.54.1", default-features = false, features = ["rt"] }
        """, source: """
        use axum::{body::{Body, to_bytes}, http::{Request, StatusCode}, routing::get, Router};
        use tower::ServiceExt;
        fn main() {
            tokio::runtime::Builder::new_current_thread().build().unwrap().block_on(async {
                let app = Router::new().route("/hello/{name}",
                    get(|axum::extract::Path(name): axum::extract::Path<String>| async move {
                        format!("Hello, {name}!")
                    }));
                let response = app.oneshot(Request::builder().uri("/hello/Crabrix")
                    .body(Body::empty()).unwrap()).await.unwrap();
                assert_eq!(response.status(), StatusCode::OK);
                let body = to_bytes(response.into_body(), 1024).await.unwrap();
                assert_eq!(&body[..], b"Hello, Crabrix!");
                println!("offline axum route: ok");
            });
        }
        """, expected: "offline axum route: ok", cold: cold)
    }

    private func runOfflineWebFixture(
        name: String, dependencies: String, source: String, expected: String,
        cold: Bool = false
    ) async throws {
        let manifest = """
        [package]
        name = "\(name)"
        version = "0.1.0"
        edition = "2021"
        [dependencies]
        \(dependencies)
        """
        let snapshot = try await CargoPackageManager().prepare(manifestSource: manifest)
        XCTAssertTrue(snapshot.blockingPackages.isEmpty, snapshot.blockingPackages.description)
        try await CargoPackageManager().pinForOffline(snapshot.packages)
        let lock = try XCTUnwrap(snapshot.lockfile)
        let frozen = try await CargoPackageManager().prepare(
            manifestSource: manifest, lockfileSource: lock, mode: .frozen)
        XCTAssertTrue(frozen.isOfflinePinned)
        let artifacts = cold ? FileManager.default.temporaryDirectory
            .appending(path: "ColdWebArtifacts-\(UUID())", directoryHint: .isDirectory) : nil
        defer { if let artifacts { try? FileManager.default.removeItem(at: artifacts) } }
        print("OFFLINE WEB PROFILE", name, "cold", cold, "packages", frozen.packages.count)
        print("OFFLINE WEB THERMAL BEGIN", ProcessInfo.processInfo.thermalState.rawValue)
        let result = try await measuredCompiler(dependencyArtifactRoot: artifacts).run(
            source: "// fresh web fixture \(UUID())\n" + source,
            sourcePath: "src/main.rs", supportingFiles: ["Cargo.toml": manifest, "Cargo.lock": lock],
            edition: "2021", plan: frozen.plan,
            onDependencyProgress: { progress in
                print("OFFLINE UNIT", Date(), progress)
                if cold { XCTAssertFalse(progress.wasCached, "Cold web gate reused a dependency artifact") }
            },
            onStage: { stage in print("OFFLINE STAGE", Date(), stage); XCTAssertFalse(Thread.isMainThread, "Compiler work reached the UI thread") })
        print("OFFLINE WEB COMPILER DURATION", name, result.duration)
        print("OFFLINE WEB THERMAL END", ProcessInfo.processInfo.thermalState.rawValue)
        XCTAssertTrue(result.succeeded, "\(result.detail)\n\(result.stderr)")
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), expected)
    }

    func testSerdeJSONBuildScriptRunsInsideTheOfflineWASISandbox() async throws {
        try Self.requireCompilerGate()
        let manifest = """
        [package]
        name = "serde-offline-gate"
        version = "0.1.0"
        edition = "2021"
        [dependencies]
        serde_json = "=1.0.151"
        """
        let manager = CargoPackageManager()
        let prepared = try await manager.prepare(manifestSource: manifest)
        XCTAssertTrue(prepared.blockingPackages.isEmpty, prepared.blockingPackages.description)
        try await manager.pinForOffline(prepared.packages)
        let lockfile = try XCTUnwrap(prepared.lockfile)
        let offline = try await CargoPackageManager().prepare(
            manifestSource: manifest, lockfileSource: lockfile, mode: .frozen)
        let source = """
        // fresh serde build-script gate \(UUID())
        fn main() {
            let value: serde_json::Value = serde_json::from_str(r#"{"answer":42}"#).unwrap();
            assert_eq!(value["answer"].as_u64(), Some(42));
            println!("{}", serde_json::to_string(&value).unwrap());
        }
        """
        let result = try await measuredCompiler().run(
            source: source, sourcePath: "src/main.rs",
            supportingFiles: ["Cargo.toml": manifest, "Cargo.lock": lockfile],
            edition: "2021", plan: offline.plan)
        XCTAssertTrue(result.succeeded, "\(result.detail)\n\(result.stderr)")
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), #"{"answer":42}"#)
    }

    func testTokioCurrentThreadTimersAndChannelsRunOffline() async throws {
        try Self.requireCompilerGate()
        let cold = ProcessInfo.processInfo.environment["CRABRIX_COLD_DEPENDENCY_GATE"] == "1"
        try await runTokioOfflineProbe(cold: cold)
    }

    func testTokioColdDispatchComparison() async throws {
        try Self.requireCompilerGate()
        try XCTSkipIf(ProcessInfo.processInfo.environment["CRABRIX_RUN_COLD_COMPARISON"] != "1")
        for direct in [false, true] {
            try await runTokioOfflineProbe(cold: true, experimentalDirectOverride: direct)
        }
    }

    private func requireColdComparison() throws {
        try Self.requireCompilerGate()
        try XCTSkipIf(ProcessInfo.processInfo.environment["CRABRIX_RUN_COLD_COMPARISON"] != "1")
    }

    func testTokioCold01OriginalToken() async throws {
        try requireColdComparison()
        try await runTokioOfflineProbe(cold: true, experimentalDirectOverride: false, candidateProfileOverride: false)
    }

    func testTokioCold02RebuiltToken() async throws {
        try requireColdComparison()
        try await runTokioOfflineProbe(cold: true, experimentalDirectOverride: false, candidateProfileOverride: true)
    }

    func testTokioCold03RebuiltDirect() async throws {
        try requireColdComparison()
        try await runTokioOfflineProbe(cold: true, experimentalDirectOverride: true, candidateProfileOverride: true)
    }

    func testTokioCold04OriginalDirect() async throws {
        try requireColdComparison()
        try await runTokioOfflineProbe(cold: true, experimentalDirectOverride: true, candidateProfileOverride: false)
    }

    func testTokioCold05RebuiltO2Direct() async throws {
        try requireColdComparison()
        try XCTSkipIf(ProcessInfo.processInfo.environment["CRABRIX_RUN_COMPILER_TRANSFORMED"] != "1")
        try await runTokioOfflineProbe(cold: true, experimentalDirectOverride: true,
                                      candidateProfileOverride: true, candidateArtifactName: "ArtifactO2")
    }

    func testTokioCold06RebuiltFatDirect() async throws {
        try requireColdComparison()
        try XCTSkipIf(ProcessInfo.processInfo.environment["CRABRIX_RUN_COMPILER_FAT"] != "1")
        try await runTokioOfflineProbe(cold: true, experimentalDirectOverride: true,
                                      candidateProfileOverride: true, candidateArtifactName: "ArtifactFat")
    }

    private func runTokioOfflineProbe(cold: Bool, experimentalDirectOverride: Bool? = nil,
                                      candidateProfileOverride: Bool? = nil,
                                      candidateArtifactName: String? = nil) async throws {
        let artifacts = cold ? FileManager.default.temporaryDirectory
            .appending(path: "ColdTokioArtifacts-\(UUID())", directoryHint: .isDirectory) : nil
        defer { if let artifacts { try? FileManager.default.removeItem(at: artifacts) } }
        print("TOKIO ARTIFACT MODE", cold ? "isolated-empty" : "existing-app-cache")
        let manifest = """
        [package]
        name = "tokio-offline-gate"
        version = "0.1.0"
        edition = "2021"
        [dependencies]
        tokio = { version = "=1.54.1", default-features = false, features = ["rt", "sync", "time", "io-util"] }
        """
        let manager = CargoPackageManager()
        let prepared = try await manager.prepare(manifestSource: manifest)
        XCTAssertTrue(prepared.blockingPackages.isEmpty, prepared.blockingPackages.description)
        let lockfile = try XCTUnwrap(prepared.lockfile)
        try await manager.pinForOffline(prepared.packages)
        // Recreate the package manager and prohibit HTTP. This is a new
        // resolution, not an in-memory snapshot or a cached root program.
        let offline = try await CargoPackageManager().prepare(
            manifestSource: manifest, lockfileSource: lockfile, mode: .frozen
        )
        XCTAssertTrue(offline.isOfflinePinned)
        let source = """
        // fresh Tokio compile \(UUID())
        use std::time::Duration;
        fn main() {
            let runtime = tokio::runtime::Builder::new_current_thread()
                .enable_time().build().unwrap();
            runtime.block_on(async {
                let (tx, mut rx) = tokio::sync::mpsc::channel(2);
                let task = tokio::spawn(async move {
                    tokio::time::sleep(Duration::from_millis(2)).await;
                    tx.send(42_u32).await.unwrap();
                });
                assert_eq!(rx.recv().await, Some(42));
                task.await.unwrap();
                println!("tokio offline: 42");
            });
        }
        """
        print("TOKIO THERMAL BEGIN", ProcessInfo.processInfo.thermalState.rawValue)
        let result = try await measuredCompiler(dependencyArtifactRoot: artifacts,
                                            experimentalDirectOverride: experimentalDirectOverride,
                                            candidateProfileOverride: candidateProfileOverride,
                                            candidateArtifactName: candidateArtifactName).run(
            source: source, sourcePath: "src/main.rs",
            supportingFiles: ["Cargo.toml": manifest, "Cargo.lock": lockfile],
            edition: "2021", plan: offline.plan,
            onDependencyProgress: { progress in
                print("TOKIO UNIT", Date(), progress)
                if cold { XCTAssertFalse(progress.wasCached, "Cold compiler gate reused a dependency artifact") }
            },
            onStage: { stage in print("TOKIO STAGE", Date(), stage) }
        )
        print("TOKIO COMPILER DURATION", result.duration)
        print("TOKIO THERMAL END", ProcessInfo.processInfo.thermalState.rawValue)
        XCTAssertTrue(result.succeeded, "\(result.detail)\n\(result.stderr)")
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "tokio offline: 42")
    }

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
        let result = try await measuredCompiler().run(
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

        let compiler = try measuredCompiler()
        XCTAssertTrue(compiler.probe().isReady)

        let result = await compiler.check(source: RustSamples.broken)

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(
            result.diagnostics.first?.code,
            "E0502",
            "detail: \(result.detail)\nstderr: \(result.stderr)\nstdout: \(result.stdout)"
        )
    }

    func testProgramPanicKeepsItsMessageAndRunPhase() async throws {
        try Self.requireCompilerGate()
        let result = try await measuredCompiler().run(source: "fn main() { panic!(\"program panic stays visible\"); }")
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.phase, .run)
        XCTAssertTrue(result.stderr.contains("program panic stays visible"), result.detail + "\n" + result.stderr)
        XCTAssertTrue(result.problemDiagnostics.contains { $0.level == "error" })
    }

    func testBundledRustcCompilesAndRunsRepairedProgram() async throws {
        guard ProcessInfo.processInfo.environment["CRABRIX_RUN_COMPILER_GATE"] == "1" else {
            throw XCTSkip("Run the CrabrixCompilerGate scheme for the expensive bundled compiler gate.")
        }

        let compiler = try measuredCompiler()
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
        let result = try await measuredCompiler().run(source: source)
        XCTAssertTrue(result.succeeded, "\(result.detail)\n\(result.stderr)")
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), marker)
    }

    func testUserProgramOutputStopsAtWASIWriteBudget() async throws {
        guard ProcessInfo.processInfo.environment["CRABRIX_RUN_COMPILER_GATE"] == "1" else {
            throw XCTSkip("Run the CrabrixCompilerGate scheme for the output stress gate.")
        }

        let result = try await measuredCompiler().run(
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

        let compiler = try measuredCompiler()
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

        let result = try await measuredCompiler().run(
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

        let result = try await measuredCompiler().run(
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

        let result = try await measuredCompiler().run(
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

        let compiler = try measuredCompiler()
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
        let result = try await measuredCompiler().run(source: source)
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
        let result = try await measuredCompiler().run(source: source)
        XCTAssertTrue(result.succeeded, "\(result.detail)\n\(result.stderr)")
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "true")
    }

    func testSourceBuiltCompilerI128ImmediateComparison() async throws {
        try Self.requireCompilerGate()
        let source = """
        // fresh revision: \(UUID())
        fn main() {
            let signs: String = [-1_i128, 0, 1].into_iter().map(|value| {
                if std::hint::black_box(value) < 0 { 'n' } else { 'p' }
            }).collect();
            let below_minus_one: String = [-2_i128, -1, 0].into_iter().map(|value| {
                if std::hint::black_box(value) < -1 { 'n' } else { 'p' }
            }).collect();
            let cases = [
                (i128::MAX, 1_i128), (i128::MIN, -1),
                (-1, 1), (i128::MAX, 0),
            ];
            let overflows: String = cases.into_iter().map(|(a, b)| {
                let (_, overflow) =
                    std::hint::black_box(a).overflowing_add(std::hint::black_box(b));
                if overflow { '1' } else { '0' }
            }).collect();
            println!("s={signs};t={below_minus_one};o={overflows}");
        }
        """
        let result = try await measuredCompiler().run(source: source)
        XCTAssertTrue(result.succeeded, "\(result.detail)\n\(result.stderr)")
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
                       "s=npp;t=npp;o=1100")
    }

    func testSourceBuiltCompilerFloatToI128BuiltinsUseWasmABI() async throws {
        try Self.requireCompilerGate()
        let source = """
        // fresh revision: \(UUID())
        fn main() {
            let a = std::hint::black_box(4.75_f32) as u128;
            let b = std::hint::black_box(-2.5_f32) as i128;
            let c = std::hint::black_box(9.75_f64) as u128;
            let d = std::hint::black_box(-7.25_f64) as i128;
            println!("{a},{b},{c},{d}");
        }
        """
        let result = try await measuredCompiler().run(source: source)
        XCTAssertTrue(result.succeeded, "\(result.detail)\n\(result.stderr)")
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
                       "4,-2,9,-7")
    }

    func testSourceBuiltCompilerRegexDependencyBuildsAndRuns() async throws {
        try Self.requireCompilerGate()
        let manifest = """
        [package]
        name = "regex-backend-gate"
        version = "0.1.0"
        edition = "2024"

        [dependencies]
        regex = "=1.13.1"
        """
        let source = """
        // fresh revision: \(UUID())
        use regex::Regex;

        fn main() {
            let pattern = Regex::new(r"^WARN\\s+(.+)$").unwrap();
            let input = "WARN cache miss\\nINFO start\\nWARN timeout";
            let issues: Vec<String> = input.lines().filter_map(|line| {
                pattern.captures(line).map(|capture| capture[1].to_owned())
            }).collect();
            println!("{}", issues.join(","));
        }
        """
        let snapshot = try await CargoPackageManager().prepare(manifestSource: manifest)
        XCTAssertTrue(snapshot.isOfflineReady)
        XCTAssertTrue(snapshot.blockingPackages.isEmpty,
                      snapshot.blockingPackages.map(\.id).joined(separator: ", "))
        XCTAssertGreaterThanOrEqual(snapshot.plan.units.count, 5)
        XCTAssertEqual(snapshot.plan.rootExterns.map(\.alias), ["regex"])

        let result = try await measuredCompiler().run(
            source: source,
            sourcePath: "src/main.rs",
            supportingFiles: ["Cargo.toml": manifest],
            plan: snapshot.plan
        )
        XCTAssertTrue(result.succeeded,
                      "phase: \(result.phase.rawValue)\ndetail: \(result.detail)\nstderr: \(result.stderr)")
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
                       "cache miss,timeout")
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
        let compiler = try measuredCompiler()
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
        try await assertVisualShowcase("pixel-sunset")
    }

    func testVisualCellularGardenRendersAValidatedCanvas() async throws {
        try await assertVisualShowcase("cellular-garden")
    }

    func testVisualMandelbrotRendersAValidatedCanvas() async throws {
        try await assertVisualShowcase("mandelbrot-canvas")
    }

    func testVisualConstellationRendersAValidatedCanvas() async throws {
        try await assertVisualShowcase("constellation-map")
    }

    func testVisualTerrainRendersAValidatedCanvas() async throws {
        try await assertVisualShowcase("terrain-map")
    }

    func testVisualColorWavesRendersAValidatedCanvas() async throws {
        try await assertVisualShowcase("color-waves")
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
            id: "visual-template", compiler: try measuredCompiler()
        )
    }

    private func assertVisualShowcase(_ id: String) async throws {
        try Self.requireCompilerGate()
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try await CourseBootstrap(
            bundle: .main, root: root, appVersion: SemanticVersion("1.1")
        ).activateBundledBaseline()
        let showcase = try XCTUnwrap(
            repository.showcaseProjects().first { $0.id == id }
        )
        try await Self.assertCanvas(project: showcase.project, id: id, compiler: try measuredCompiler())
    }

    private static func assertCanvas(
        project: CrabrixProject,
        id: String,
        compiler: WasmRustCompiler
    ) async throws {
        var supporting = project.files
        let source = try XCTUnwrap(
            supporting.removeValue(forKey: project.entryFile),
            id
        )
        let result = await compiler.run(
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

        let compiler = try measuredCompiler()
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

        let compiler = try measuredCompiler()
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

    func testSynParserOnlyDependencyBuildsAndRuns() async throws {
        try Self.requireCompilerGate()
        let defaultManifest = """
        [package]
        name = "syn-device-regression"
        version = "0.1.0"
        edition = "2024"
        [dependencies]
        syn = "3.0.6"
        """
        let manager = CargoPackageManager()
        let defaultSnapshot = try await manager.prepare(manifestSource: defaultManifest)
        XCTAssertTrue(defaultSnapshot.blockingPackages.contains {
            $0.name == "syn" && $0.features.contains("proc-macro")
        })

        let manifest = try CargoManifestEditor.usingSynParserFeatures(defaultManifest)
        let snapshot = try await manager.prepare(manifestSource: manifest)
        XCTAssertEqual(Set(snapshot.packages.map(\.name)), Set(["syn", "quote", "proc-macro2", "unicode-ident"]))
        XCTAssertTrue(snapshot.blockingPackages.isEmpty, snapshot.blockingPackages.map {
            "\($0.name): \($0.compatibility.detail ?? "")"
        }.joined(separator: "\n"))
        XCTAssertFalse(snapshot.packages.contains { $0.features.contains("proc-macro") })

        let source = """
        // syn parser gate \(UUID().uuidString)
        fn main() {
            let ident: syn::Ident = syn::parse_str("crabrix").unwrap();
            println!("{}", ident);
        }
        """
        let result = try await measuredCompiler().run(
            source: source, sourcePath: "src/main.rs",
            supportingFiles: ["Cargo.toml": manifest], plan: snapshot.plan
        )
        XCTAssertTrue(result.succeeded, "\(result.detail)\n\(result.stderr)")
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "crabrix")
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

        let compiler = try measuredCompiler()
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

        let compiler = try measuredCompiler()
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

        let compiler = try measuredCompiler()
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

        let compiler = try measuredCompiler()
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

    func testMultiFileRoutePlannerWithGraphCratesBuildsAndRuns() async throws {
        try Self.requireCompilerGate()
        guard ProcessInfo.processInfo.environment["CRABRIX_RUN_UNSUPPORTED_CRATE_PROBE"] == "1" else {
            throw XCTSkip("Run the opt-in source-built toolchain gate for the graph application.")
        }
        let manifest = """
        [package]
        name = "route-planner-multifile-gate"
        version = "0.1.0"
        edition = "2024"

        [dependencies]
        clap = "=4.5.50"
        regex = "=1.13.1"
        petgraph = "=0.8.3"
        itertools = "=0.14.0"
        """
        let source = """
        // fresh application revision: \(UUID())
        mod routes;
        mod report;
        use clap::{Arg, Command};

        fn main() {
            let matches = Command::new("routes")
                .arg(Arg::new("origin").long("origin").required(true).num_args(1))
                .try_get_matches_from(["routes", "--origin", "api"])
                .unwrap();
            let origin = matches.get_one::<String>("origin").unwrap();
            let edges = "api -> worker : 3\\napi -> cache : 1\\ncache -> worker : 1\\nworker -> store : 2";
            let distances = routes::shortest_paths(edges, origin);
            println!("{}", report::summarize(&distances));
        }
        """
        let routes = """
        use std::collections::HashMap;
        use petgraph::algo::dijkstra;
        use petgraph::graph::{DiGraph, NodeIndex};
        use regex::Regex;

        pub fn shortest_paths(input: &str, origin: &str) -> Vec<(String, u32)> {
            let row = Regex::new(r"^(\\w+) -> (\\w+) : (\\d+)$").unwrap();
            let mut graph = DiGraph::<String, u32>::new();
            let mut nodes: HashMap<String, NodeIndex> = HashMap::new();
            for line in input.lines() {
                let captures = row.captures(line).unwrap();
                let mut index_for = |name: &str| {
                    if let Some(&index) = nodes.get(name) {
                        index
                    } else {
                        let index = graph.add_node(name.to_owned());
                        nodes.insert(name.to_owned(), index);
                        index
                    }
                };
                let from = index_for(&captures[1]);
                let to = index_for(&captures[2]);
                drop(index_for);
                graph.add_edge(from, to, captures[3].parse().unwrap());
            }
            let start = nodes[origin];
            dijkstra(&graph, start, None, |edge| *edge.weight())
                .into_iter()
                .map(|(index, cost)| (graph[index].clone(), cost))
                .collect()
        }
        """
        let report = """
        use itertools::Itertools;

        pub fn summarize(paths: &[(String, u32)]) -> String {
            paths.iter()
                .sorted_by_key(|(name, _)| name.as_str())
                .map(|(name, cost)| format!("{name}={cost}"))
                .join(",")
        }
        """

        let snapshot = try await CargoPackageManager().prepare(manifestSource: manifest)
        XCTAssertTrue(snapshot.isOfflineReady)
        XCTAssertTrue(snapshot.blockingPackages.isEmpty, snapshot.blockingPackages.map(\.id).joined(separator: ", "))
        XCTAssertGreaterThanOrEqual(snapshot.plan.units.count, 10)
        XCTAssertEqual(Set(snapshot.plan.rootExterns.map(\.alias)),
                       ["clap", "regex", "petgraph", "itertools"])
        XCTAssertNotNil(snapshot.lockfile)

        let compiler = try measuredCompiler()
        let result = await compiler.run(
            source: source,
            sourcePath: "src/main.rs",
            supportingFiles: [
                "Cargo.toml": manifest,
                "src/routes.rs": routes,
                "src/report.rs": report,
            ],
            plan: snapshot.plan
        )
        XCTAssertTrue(result.succeeded,
                      "phase: \(result.phase.rawValue)\ndetail: \(result.detail)\nstderr: \(result.stderr)")
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
                       "api=0,cache=1,store=4,worker=2")
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

        let compiler = try measuredCompiler()
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

        let result = try await measuredCompiler().run(
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

        let compiler = try measuredCompiler()
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
