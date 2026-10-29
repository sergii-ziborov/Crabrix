import Foundation
import CryptoKit
import CrabrixGit
import UIKit
@_spi(Fuzzing) import WasmKit
import WasmKitWASI

/// Progress emitted while dependencies compile, so the UI can name the crate
/// a multi-minute build is currently working on.
struct CargoBuildProgress: Sendable, Equatable {
    let package: PackageID
    let index: Int
    let total: Int
    let wasCached: Bool
}

enum RustUnitTestInvocation: Equatable, Sendable {
    case discover
    case single(String)

    var arguments: [String] {
        switch self {
        case .discover: ["--list", "--format=json", "-Z", "unstable-options"]
        case let .single(name): [name, "--exact", "--test-threads=1", "--format=json", "-Z", "unstable-options", "--force-run-in-process", "--nocapture"]
        }
    }
}

final class WasmRustCompiler: @unchecked Sendable {
    private enum Action: Equatable {
        case check
        case build
        case run
        case test(RustUnitTestInvocation)

        var testInvocation: RustUnitTestInvocation? {
            if case let .test(invocation) = self { return invocation }
            return nil
        }

        var executionStage: String {
            switch testInvocation {
            case .discover: "Listing selected-entry unit tests locally"
            case .single: "Running isolated unit test locally"
            case nil: "Running program"
            }
        }

        var emit: CargoEmitKind {
            switch self {
            case .check: .metadata
            case .build, .run, .test: .link
            }
        }
    }

    static var toolchainVersion: String { CargoToolchain.bundledVersion }
    static var executionIdentity: String {
        CargoToolchain.artifactIdentity + ":app-" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "development")
    }
    // Bumped when the root compiler invocation changes shape: artefacts built
    // before the root crate received its own `--cfg feature="…"` flags must not
    // be reused for the same manifest.
    private static let cacheSchemaVersion = "fast-dev-6-wasi-build-scripts"
    private static let checkCacheLimit = 24

    private let bundle: Bundle
    private let ledger: CrateCompatibilityLedger
    private let runtime: RustcRuntime
    private let dependencyArtifactRoot: URL?
    private let projectArtifactRoot: URL?
    private let toolchainOverride: BundledToolchain?
    // The interpreter runs on its own serial queue. Explicit Run work receives
    // userInitiated QoS; background checks retain utility QoS.
    private let queue = DispatchQueue(
        label: "com.sergiiziborov.Crabrix.compiler",
        qos: .utility,
        autoreleaseFrequency: .workItem
    )
    private let clock = ContinuousClock()
    // Keep the complete check result: a cache hit must retain warnings and spans.
    // Both the entry count and diagnostic bytes are bounded to avoid retaining
    // arbitrarily large compiler output in memory.
    private var successfulChecks: [String: CompilationResult] = [:]
    private var checkCacheOrder: [String] = []
    private let interrupterLock = NSLock()
    private var activeInterrupter: WasmInterrupter?
    private var memoryWarningObserver: NSObjectProtocol?

    init(bundle: Bundle = .main, ledger: CrateCompatibilityLedger = .shared,
         runtime: RustcRuntime = RustcRuntime(), dependencyArtifactRoot: URL? = nil,
         projectArtifactRoot: URL? = nil,
         toolchainOverride: BundledToolchain? = nil) {
        self.bundle = bundle
        self.ledger = ledger
        self.runtime = runtime
        self.dependencyArtifactRoot = dependencyArtifactRoot
        self.projectArtifactRoot = projectArtifactRoot
        self.toolchainOverride = toolchainOverride
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.queue.async { self.runtime.clearProgramModules() }
        }
    }

    deinit {
        if let memoryWarningObserver {
            NotificationCenter.default.removeObserver(memoryWarningObserver)
        }
    }

    // MARK: - Toolchain

    private var toolchain: BundledToolchain? {
        toolchainOverride ?? BundledToolchain.locate(in: bundle, version: Self.toolchainVersion)
    }

    // A test-created compiler can use a separately verified candidate without
    // changing signed app resources. Its outputs occupy a separate namespace.
    private var toolchainNamespace: String { toolchainOverride?.version ?? Self.toolchainVersion }

    func probe() -> ToolchainStatus {
        guard let toolchain = toolchainOverride ?? BundledToolchain.locate(
            in: bundle, version: Self.toolchainVersion, prepareSysroot: false
        ) else {
            return ToolchainStatus(
                isReady: false,
                rustcSize: 0,
                label: "Toolchain missing",
                detail: "Run scripts/bootstrap.sh before building."
            )
        }
        let size = (try? toolchain.rustcURL.resourceValues(forKeys: [.fileSizeKey]).fileSize)
            .map(Int64.init) ?? 0
        return ToolchainStatus(
            isReady: true,
            rustcSize: size,
            label: "Bundled rustc.wasm",
            detail: "WasmKit interpreter · fully local · \(toolchain.sysrootURL.lastPathComponent)"
        )
    }

    // MARK: - Public entry points

    func check(
        source: String,
        sourcePath: String = "main.rs",
        supportingFiles: [String: String] = [:],
        resourceFiles: [String: Data] = [:],
        edition: String = "2024",
        plan: CargoBuildPlan = .empty,
        cancellation: CompilerInvocationCancellation? = nil,
        onDependencyProgress: (@Sendable (CargoBuildProgress) -> Void)? = nil,
        onStage: (@Sendable (String) -> Void)? = nil
    ) async -> CompilationResult {
        await perform(
            action: .check,
            source: source,
            sourcePath: sourcePath,
            supportingFiles: supportingFiles, resourceFiles: resourceFiles,
            edition: edition,
            plan: plan,
            cancellation: cancellation, onDependencyProgress: onDependencyProgress,
            onStage: onStage
        )
    }

    func run(
        source: String,
        sourcePath: String = "main.rs",
        supportingFiles: [String: String] = [:],
        resourceFiles: [String: Data] = [:],
        edition: String = "2024",
        plan: CargoBuildPlan = .empty,
        cancellation: CompilerInvocationCancellation? = nil,
        onDependencyProgress: (@Sendable (CargoBuildProgress) -> Void)? = nil,
        onStage: (@Sendable (String) -> Void)? = nil
    ) async -> CompilationResult {
        await perform(
            action: .run,
            source: source,
            sourcePath: sourcePath,
            supportingFiles: supportingFiles, resourceFiles: resourceFiles,
            edition: edition,
            plan: plan,
            cancellation: cancellation, onDependencyProgress: onDependencyProgress,
            onStage: onStage
        )
    }

    /// Link and cache the executable without instantiating or invoking main.
    func build(
        source: String, sourcePath: String = "main.rs", supportingFiles: [String: String] = [:],
        resourceFiles: [String: Data] = [:],
        edition: String = "2024", plan: CargoBuildPlan = .empty,
        cancellation: CompilerInvocationCancellation? = nil,
        onDependencyProgress: (@Sendable (CargoBuildProgress) -> Void)? = nil,
        onStage: (@Sendable (String) -> Void)? = nil
    ) async -> CompilationResult {
        await perform(action: .build, source: source, sourcePath: sourcePath, supportingFiles: supportingFiles, resourceFiles: resourceFiles,
                      edition: edition, plan: plan, cancellation: cancellation, onDependencyProgress: onDependencyProgress, onStage: onStage)
    }

    /// The standard libtest harness for one selected entry. Dev-dependencies,
    /// custom harnesses and virtual workspaces are explicitly outside this profile.
    func unitTest(source: String, sourcePath: String = "main.rs", supportingFiles: [String: String] = [:],
        resourceFiles: [String: Data] = [:],
                  edition: String = "2024", plan: CargoBuildPlan = .empty,
                  invocation: RustUnitTestInvocation,
                  cancellation: CompilerInvocationCancellation? = nil,
                  onDependencyProgress: (@Sendable (CargoBuildProgress) -> Void)? = nil,
                  onStage: (@Sendable (String) -> Void)? = nil) async -> CompilationResult {
        if case let .single(name) = invocation,
           name.isEmpty || name.hasPrefix("-") || name.utf8.count > 1_024 || name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            return .failure(phase: .setup, detail: "Unsupported unit-test name.")
        }
        if let manifestSource = supportingFiles["Cargo.toml"] {
            do {
                let manifest = try CratePackageManifest.parse(manifestSource)
                guard !manifest.isProcMacro, !manifest.isVirtualWorkspace else {
                    return .failure(phase: .setup, detail: "Unit Test needs a selected non-procedural-macro Rust entry.")
                }
                guard !manifest.dependencies.contains(where: { $0.kind == .dev }) else {
                    return .failure(phase: .setup, detail: "The initial Unit Test profile does not resolve dev-dependencies. They were not silently omitted.")
                }
                let document = try TOMLParser.parse(manifestSource)
                if document["lib"]?["harness"]?.boolValue == false,
                   isLibraryEntry(sourcePath, supportingFiles: supportingFiles) {
                    return .failure(phase: .setup, detail: "This library disables the standard libtest harness; custom harnesses are not supported.")
                }
            } catch { return .failure(phase: .setup, detail: error.localizedDescription) }
        }
        return await perform(action: .test(invocation), source: source, sourcePath: sourcePath,
            supportingFiles: supportingFiles, resourceFiles: resourceFiles, edition: edition, plan: plan,
            cancellation: cancellation, onDependencyProgress: onDependencyProgress, onStage: onStage)
    }

    func debug(
        source: String, sourcePath: String = "main.rs", supportingFiles: [String: String] = [:],
        resourceFiles: [String: Data] = [:],
        edition: String = "2024", plan: CargoBuildPlan = .empty, session: RustDebugSession,
        cancellation: CompilerInvocationCancellation? = nil,
        onDependencyProgress: (@Sendable (CargoBuildProgress) -> Void)? = nil,
        onStage: (@Sendable (String) -> Void)? = nil
    ) async -> CompilationResult {
        await withCheckedContinuation { continuation in
            queue.async(qos: .userInitiated, flags: .enforceQoS) { [self] in
                let checked = execute(action: .check, source: source, sourcePath: sourcePath, supportingFiles: supportingFiles, resourceFiles: resourceFiles, edition: edition, plan: plan, cancellation: cancellation, onDependencyProgress: onDependencyProgress, onStage: onStage)
                guard checked.succeeded else { continuation.resume(returning: checked); return }
                guard !session.isStopped, cancellation?.isCancelled != true else { continuation.resume(returning: .failure(phase: .setup, detail: "Debug stopped before execution.")); return }
                do {
                    onStage?("Preparing separate local Debug snapshot")
                    var files = supportingFiles; files[sourcePath] = source
                    let instrumented = try RustDebugInstrumenter.instrument(files: files, entryFile: sourcePath, bundle: bundle)
                    session.prepare(instrumented)
                    files.merge(instrumented.files) { _, debug in debug }
                    let main = files.removeValue(forKey: sourcePath)!
                    continuation.resume(returning: execute(action: .run, source: main, sourcePath: sourcePath, supportingFiles: files, resourceFiles: resourceFiles, edition: edition, plan: plan, cancellation: cancellation, onDependencyProgress: onDependencyProgress, onStage: onStage, debugSession: session))
                } catch { continuation.resume(returning: .failure(phase: .setup, detail: error.localizedDescription)) }
            }
        }
    }

    /// Stops the guest currently executing on the compiler queue.
    ///
    /// Cancellation is checked in WasmKit's dispatch loop and at every WASI
    /// call, so it also reaches a user guest that performs pure computation.
    func cancel() {
        interrupterLock.lock()
        let interrupter = activeInterrupter
        interrupterLock.unlock()
        interrupter?.cancel()
    }

    /// Clears both persisted root-program Wasm files and their in-memory fast
    /// paths. Work is serialized behind an active compilation on `queue`.
    func clearProjectArtifacts() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                successfulChecks.removeAll(keepingCapacity: false)
                checkCacheOrder.removeAll(keepingCapacity: false)
                runtime.clearProgramModules()
                if let directory = projectArtifactRoot ?? CrateStorageLayout.projectArtifactDirectory,
                   FileManager.default.fileExists(atPath: directory.path) {
                    try? FileManager.default.removeItem(at: directory)
                }
                continuation.resume()
            }
        }
    }

    /// True when every artefact this plan needs is already on disk.
    func isPlanCached(_ plan: CargoBuildPlan, emit: CargoEmitKind) -> Bool {
        guard let artifacts = artifactsDirectory else { return plan.isEmpty }
        return plan.units.allSatisfy { unit in
            FileManager.default.fileExists(
                atPath: artifacts.appending(path: artifactFileName(unit, emit: emit)).path
            )
        }
    }

    private func perform(
        action: Action,
        source: String,
        sourcePath: String,
        supportingFiles: [String: String],
        resourceFiles: [String: Data],
        edition: String,
        plan: CargoBuildPlan,
        cancellation: CompilerInvocationCancellation? = nil,
        onDependencyProgress: (@Sendable (CargoBuildProgress) -> Void)?,
        onStage: (@Sendable (String) -> Void)?
    ) async -> CompilationResult {
        await withCheckedContinuation { continuation in
            queue.async(qos: action == .check ? .utility : .userInitiated,
                        flags: .enforceQoS) { [self] in
                assert(!Thread.isMainThread, "Bundled rustc must never execute on the UI thread")
                continuation.resume(
                    returning: execute(
                        action: action,
                        source: source,
                        sourcePath: sourcePath,
                        supportingFiles: supportingFiles, resourceFiles: resourceFiles,
                        edition: edition,
                        plan: plan,
                        cancellation: cancellation,
                        onDependencyProgress: onDependencyProgress,
                        onStage: onStage
                    )
                )
            }
        }
    }

    // MARK: - Compilation

    private func execute(
        action: Action,
        source: String,
        sourcePath: String,
        supportingFiles: [String: String],
        resourceFiles: [String: Data],
        edition: String,
        plan: CargoBuildPlan,
        cancellation: CompilerInvocationCancellation? = nil,
        onDependencyProgress: (@Sendable (CargoBuildProgress) -> Void)?,
        onStage: (@Sendable (String) -> Void)?,
        debugSession: RustDebugSession? = nil
    ) -> CompilationResult {
        let started = clock.now
        let interrupter = WasmInterrupter()
        cancellation?.attach(interrupter)
        interrupterLock.lock()
        activeInterrupter = interrupter
        interrupterLock.unlock()
        debugSession?.attach(interrupter)
        defer {
            debugSession?.attach(nil)
            cancellation?.detach(interrupter)
            interrupterLock.lock()
            activeInterrupter = nil
            interrupterLock.unlock()
        }

        // A caller may stop while this invocation is still queued. Do not
        // even prepare the bundled sysroot for an already cancelled job.
        if let reason = interrupter.stopReason {
            return cancelledResult(phase: .setup, started: started, cancellation: .init(reason: reason))
        }
        onStage?("Preparing bundled compiler")
        guard let toolchain else {
            return .failure(phase: .setup, detail: "Bundled Rust toolchain is missing.")
        }
        guard ["2015", "2018", "2021", "2024"].contains(edition) else {
            return .failure(
                phase: .setup,
                detail: "Unsupported Cargo edition \"\(edition)\". Use 2015, 2018, 2021, or 2024."
            )
        }

        // The first build may install bundled compiler data. Remember a Stop
        // pressed during that preparation and do not start a guest afterwards.
        if let reason = interrupter.stopReason {
            return cancelledResult(phase: .setup, started: started, cancellation: .init(reason: reason))
        }

        do { try validateResources(resourceFiles, source: source, sourcePath: sourcePath, supportingFiles: supportingFiles) }
        catch { return .failure(phase: .setup, detail: error.localizedDescription) }

        let cacheKey = artifactKey(
            action: action,
            source: source,
            sourcePath: sourcePath,
            supportingFiles: supportingFiles, resourceFiles: resourceFiles,
            edition: edition,
            plan: plan
        )
        let libraryBuild = action == .build && isLibraryEntry(sourcePath, supportingFiles: supportingFiles)
        if libraryBuild, let manifest = supportingFiles["Cargo.toml"].flatMap({ try? CratePackageManifest.parse($0) }),
           manifest.library.isProcMacro || manifest.library.crateTypes.contains(where: { !["lib", "rlib"].contains($0) }) {
            return .failure(phase: .setup, detail: "Compile-only Build supports an rlib library entry. This manifest requests a different library target; it was not substituted.")
        }

        if action == .check, let cached = cachedCheck(for: cacheKey) {
            return CompilationResult(
                succeeded: cached.succeeded,
                phase: cached.phase,
                exitCode: cached.exitCode,
                diagnostics: cached.diagnostics,
                stdout: cached.stdout,
                stderr: cached.stderr,
                duration: started.duration(to: clock.now),
                detail: "Unchanged snapshot accepted from the local check cache."
            )
        }

        let fileManager = FileManager.default
        let jobRoot = fileManager.temporaryDirectory
            .appending(path: "CrabrixCompiler", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let workURL = jobRoot.appending(path: "work", directoryHint: .isDirectory)
        let tempURL = jobRoot.appending(path: "tmp", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: jobRoot) }

        do {
            // Dependencies must exist before the cached-program fast path, because
            // a cached program.wasm already has them linked in.
            if action != .check, !libraryBuild, let cachedProgram = loadCachedProgramModule(for: cacheKey) {
                if action == .build {
                    onStage?("Build artifact ready · main was not executed")
                    return CompilationResult(succeeded: true, phase: .compile, exitCode: 0, diagnostics: [], stdout: "", stderr: "", duration: started.duration(to: clock.now), detail: "Unchanged executable accepted from the local build cache. main was not executed.")
                }
                onStage?(action.executionStage)
                return try executeProgram(
                    module: cachedProgram,
                    jobRoot: jobRoot,
                    diagnostics: [],
                    started: started,
                    interrupter: interrupter,
                    previewSourceFiles: action.testInvocation == nil ? supportingFiles : [:],
                    previewResourceFiles: action.testInvocation == nil ? resourceFiles : [:],
                    successDetail: "Executed a cached local build artifact inside the bounded WasmKit sandbox.",
                    debugSession: debugSession,
                    programArguments: action.testInvocation?.arguments ?? []
                )
            }

            do {
                try fileManager.createDirectory(at: workURL, withIntermediateDirectories: true)
                try fileManager.createDirectory(at: tempURL, withIntermediateDirectories: true)
                try writeProject(
                    source: source,
                    sourcePath: sourcePath,
                    supportingFiles: supportingFiles, resourceFiles: resourceFiles,
                    into: workURL
                )
            } catch let error as ProjectLayoutError {
                return .failure(
                    phase: .setup,
                    detail: error.localizedDescription,
                    duration: started.duration(to: clock.now)
                )
            } catch {
                return .failure(
                    phase: .setup,
                    detail: "Could not create the compiler sandbox: \(error.localizedDescription)",
                    duration: started.duration(to: clock.now)
                )
            }

            if !plan.isEmpty {
                if let failure = buildDependencies(
                    plan: plan,
                    emit: action.emit,
                    toolchain: toolchain,
                    jobRoot: jobRoot,
                    workURL: workURL,
                    tempURL: tempURL,
                    interrupter: interrupter,
                    started: started,
                    onProgress: onDependencyProgress
                ) {
                    return failure
                }
            }

            var rootEnvironment = rootCargoEnvironment(
                sourcePath: sourcePath, supportingFiles: supportingFiles, features: plan.rootFeatures)
            if debugSession != nil { rootEnvironment["CLIF2WASM_IMPORTS"] = RustDebugSession.importName }
            var rootScriptOutput = CargoBuildScriptOutput()
            var rootGeneratedURL: URL?
            if let manifestText = supportingFiles["Cargo.toml"],
               let parsed = try? CratePackageManifest.parse(manifestText) {
                let manifest = parsed.detectingImplicitBuildScript(
                    fileExists: fileManager.fileExists(atPath: workURL.appending(path: "build.rs").path))
                if let script = manifest.buildScriptPath {
                    onStage?("Building project build script")
                    let generated = jobRoot.appending(path: "root-generated", directoryHint: .isDirectory)
                    let unit = CargoBuildUnit(
                        package: PackageID(name: manifest.packageName, version: manifest.version ?? .init(major: 0, minor: 0, patch: 0)),
                        fingerprint: String(cacheKey.prefix(16)),
                        crateName: CratePackageManifest.crateIdentifier(for: manifest.packageName),
                        edition: manifest.edition, features: plan.rootFeatures, libraryPath: sourcePath,
                        source: .registry(directoryName: "root"), externs: [],
                        authors: "", description: "", repository: "", license: "", homepage: "",
                        buildScriptPath: script,
                        buildScriptDependencies: manifest.dependencies
                            .filter { $0.kind == .build && $0.applies(to: .wasm32WasiP1) }.map(\.alias))
                    do {
                        rootScriptOutput = try runBuildScript(
                            for: unit, toolchain: toolchain, registryRoot: workURL,
                            patchRoot: nil, generatedURL: generated, jobRoot: jobRoot,
                            tempURL: tempURL, interrupter: interrupter,
                            sourceOverride: workURL, guestSourceOverride: "/work",
                            packageEnvironment: rootEnvironment)
                    } catch let cancellation as WasmExecutionCancelled { throw cancellation }
                    catch {
                        return .failure(phase: .compile,
                                        detail: "Project build script failed: \(error.localizedDescription)",
                                        duration: started.duration(to: clock.now))
                    }
                    rootGeneratedURL = generated
                    rootEnvironment["OUT_DIR"] = "/build-out"
                    rootEnvironment.merge(rootScriptOutput.environment) { _, new in new }
                }
            }
            onStage?(action == .check ? "Checking project" : "Compiling and linking project")
            let outputName = action == .check ? "main.rmeta" : libraryBuild ? "library.rlib" : "program.wasm"
            var arguments = [
                "rustc", "/work/\(sourcePath)",
                "--sysroot", "/sysroot",
                "--target", "wasm32-wasip1",
                "--edition", edition,
                "--error-format=json",
                "--json=diagnostic-rendered-ansi",
            ]
            for feature in plan.rootFeatures {
                arguments += ["--cfg", "feature=\"\(feature)\""]
            }
            arguments += externArguments(plan.rootExterns, emit: action.emit)
            arguments += rootScriptOutput.compilerArguments
            if libraryBuild { arguments += ["--crate-type=rlib"] }

            switch action {
            case .check:
                arguments += ["--emit", "metadata", "-o", "/work/\(outputName)"]
            case .build, .run, .test:
                arguments += [
                    "-Zunstable-options", "-Copt-level=0", "-Cpanic=abort",
                    "-o", "/work/\(outputName)",
                ]
            }
            if action.testInvocation != nil { arguments += ["--test", "-Zpanic_abort_tests"] }

            let compilerOutput: WasmProcessResult
            do {
                compilerOutput = try invokeRustc(
                    toolchain: toolchain,
                    arguments: arguments,
                    jobRoot: jobRoot,
                    capturePrefix: "compiler",
                    preopens: [
                        .init(guestPath: "/tmp", hostPath: tempURL.path),
                        .init(guestPath: "/sysroot", hostPath: toolchain.sysrootURL.path, readOnly: true),
                        .init(guestPath: "/work", hostPath: workURL.path),
                    ] + registryPreopens(for: plan) + (rootGeneratedURL.map {
                        [.init(guestPath: "/build-out", hostPath: $0.path, readOnly: true)]
                    } ?? []),
                    environment: rootEnvironment,
                    interrupter: interrupter,
                    proceduralMacroInputs: macroInputs(for: plan)
                )
            } catch let cancellation as WasmExecutionCancelled {
                return cancelledResult(
                    phase: action == .check ? .check : .compile,
                    started: started,
                    cancellation: cancellation
                )
            } catch let failure as RustcRuntimeFailure {
                let diagnostics = RustDiagnosticParser.parse(stderr: failure.stderr)
                if let diagnostic = diagnostics.first {
                    return CompilationResult(
                        succeeded: false,
                        phase: action == .check ? .check : .compile,
                        exitCode: nil,
                        diagnostics: diagnostics,
                        stdout: failure.stdout,
                        stderr: "",
                        duration: started.duration(to: clock.now),
                        detail: diagnostic.message
                    )
                }
                return .failure(
                    phase: action == .check ? .check : .compile,
                    detail: "Bundled rustc trapped: \(failure.underlying)",
                    stderr: failure.stderr,
                    duration: started.duration(to: clock.now)
                )
            }

            let diagnostics = RustDiagnosticParser.parse(stderr: compilerOutput.stderr)
            let hasErrors = diagnostics.contains(where: { $0.level == "error" })

            guard compilerOutput.exitCode == 0, !hasErrors else {
                return CompilationResult(
                    succeeded: false,
                    phase: action == .check ? .check : .compile,
                    exitCode: compilerOutput.exitCode,
                    diagnostics: diagnostics,
                    stdout: compilerOutput.stdout,
                    stderr: diagnostics.isEmpty ? compilerOutput.stderr : "",
                    duration: started.duration(to: clock.now),
                    detail: diagnostics.first?.message
                        ?? "rustc exited with code \(compilerOutput.exitCode)."
                )
            }

            if action == .check {
                let result = CompilationResult(
                    succeeded: true,
                    phase: .check,
                    exitCode: compilerOutput.exitCode,
                    diagnostics: diagnostics,
                    stdout: compilerOutput.stdout,
                    stderr: compilerOutput.stderr,
                    duration: started.duration(to: clock.now),
                    detail: plan.isEmpty
                        ? "Real bundled rustc accepted the program."
                        : "Real bundled rustc accepted the program and \(plan.units.count) dependencies."
                )
                cacheCheck(result, for: cacheKey)
                return result
            }

            let programURL = workURL.appending(path: outputName)
            guard fileManager.fileExists(atPath: programURL.path) else {
                return .failure(
                    phase: .compile,
                    detail: "rustc exited successfully but emitted no \(outputName).",
                    stderr: compilerOutput.stderr,
                    duration: started.duration(to: clock.now)
                )
            }

            if libraryBuild {
                onStage?("Library compiled · no program was executed")
                return CompilationResult(succeeded: true, phase: .compile, exitCode: 0, diagnostics: diagnostics,
                    stdout: compilerOutput.stdout, stderr: diagnostics.isEmpty ? compilerOutput.stderr : "",
                    duration: started.duration(to: clock.now), detail: "Compiled a local rlib library. No program was executed.")
            }

            let programModule = try parseWasm(filePath: programURL.path)
            if let byteCount = try? programURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                runtime.cacheProgramModule(programModule, for: cacheKey, wasmFileBytes: byteCount)
            }
            persistProgramArtifact(at: programURL, for: cacheKey)

            if action == .build {
                onStage?("Build artifact ready · main was not executed")
                return CompilationResult(succeeded: true, phase: .compile, exitCode: 0, diagnostics: diagnostics,
                    stdout: compilerOutput.stdout, stderr: diagnostics.isEmpty ? compilerOutput.stderr : "",
                    duration: started.duration(to: clock.now), detail: "Compiled and linked locally. main was not executed.")
            }

            onStage?(action.executionStage)
            return try executeProgram(
                module: programModule,
                jobRoot: jobRoot,
                diagnostics: diagnostics,
                started: started,
                interrupter: interrupter,
                previewSourceFiles: action.testInvocation == nil ? supportingFiles : [:],
                    previewResourceFiles: action.testInvocation == nil ? resourceFiles : [:],
                successDetail: plan.isEmpty
                    ? "Compiled and executed locally inside the bounded WasmKit sandbox."
                    : "Compiled \(plan.units.count) dependencies and the program locally, then ran it in the bounded sandbox.",
                debugSession: debugSession,
                programArguments: action.testInvocation?.arguments ?? []
            )
        } catch let cancellation as WasmExecutionCancelled {
            return cancelledResult(
                phase: action == .check ? .check : (action == .build ? .compile : .run),
                started: started,
                cancellation: cancellation
            )
        } catch {
            return .failure(
                phase: action == .check ? .check : (action == .build ? .compile : .run),
                detail: "Native compiler runtime failed: \(error)",
                duration: started.duration(to: clock.now)
            )
        }
    }

    // MARK: - Dependencies

    /// Compiles every unit that is not already cached. Returns a failure result,
    /// or nil when the whole plan is available on disk afterwards.
    private func buildDependencies(
        plan: CargoBuildPlan,
        emit: CargoEmitKind,
        toolchain: BundledToolchain,
        jobRoot: URL,
        workURL: URL,
        tempURL: URL,
        interrupter: WasmInterrupter,
        started: ContinuousClock.Instant,
        onProgress: (@Sendable (CargoBuildProgress) -> Void)?
    ) -> CompilationResult? {
        guard let artifacts = artifactsDirectory,
              let registryRoot = CrateStorageLayout.sourceDirectory
        else {
            return .failure(
                phase: .setup,
                detail: "Crabrix could not open its package artifact cache.",
                duration: started.duration(to: clock.now)
            )
        }
        do {
            try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
        } catch {
            return .failure(
                phase: .setup,
                detail: "Could not create the package artifact cache: \(error.localizedDescription)",
                duration: started.duration(to: clock.now)
            )
        }

        for (index, unit) in plan.units.enumerated() {
            if unit.isProceduralMacro && !toolchain.supportsProceduralMacros {
                return dependencyFailure(unit: unit, detail: "This toolchain has no procedural-macro transport.", stderr: "", started: started)
            }
            let unitEmit: CargoEmitKind = unit.requiresLink || unit.isProceduralMacro ? .link : emit
            if interrupter.wasCancelled {
                return cancelledResult(
                    phase: .compile, started: started,
                    cancellation: .init(reason: interrupter.stopReason ?? .userRequested)
                )
            }
            let outputURL = artifacts.appending(path: artifactFileName(unit, emit: emit))
            if FileManager.default.fileExists(atPath: outputURL.path) {
                onProgress?(
                    CargoBuildProgress(
                        package: unit.package,
                        index: index + 1,
                        total: plan.units.count,
                        wasCached: true
                    )
                )
                continue
            }
            onProgress?(
                CargoBuildProgress(
                    package: unit.package,
                    index: index + 1,
                    total: plan.units.count,
                    wasCached: false
                )
            )

            let patchRoot: URL?
            do {
                patchRoot = try materializeProjectPatch(
                    for: unit,
                    workURL: workURL,
                    registryRoot: registryRoot,
                    jobRoot: jobRoot
                )
            } catch {
                return dependencyFailure(
                    unit: unit,
                    detail: "could not prepare the local patch: \(error.localizedDescription)",
                    stderr: "",
                    started: started
                )
            }

            let buildOutput: CargoBuildScriptOutput
            let generatedURL = jobRoot.appending(path: "generated-\(unit.fingerprint)", directoryHint: .isDirectory)
            do {
                buildOutput = try runBuildScript(
                    for: unit, toolchain: toolchain, registryRoot: registryRoot,
                    patchRoot: patchRoot, generatedURL: generatedURL,
                    jobRoot: jobRoot, tempURL: tempURL, interrupter: interrupter
                )
            } catch let cancellation as WasmExecutionCancelled {
                return cancelledResult(phase: .compile, started: started, cancellation: cancellation)
            } catch let failure as RustcRuntimeFailure {
                return dependencyFailure(unit: unit, detail: "build script failed: \(failure.underlying.localizedDescription)", stderr: failure.stderr, started: started)
            } catch {
                return dependencyFailure(unit: unit, detail: error.localizedDescription, stderr: "", started: started)
            }

            var arguments = [
                "rustc",
                "\(unit.guestSourceDirectory)/\(unit.libraryPath)",
                "--sysroot", "/sysroot",
                "--target", "wasm32-wasip1",
                "--edition", unit.edition,
                "--crate-name", unit.crateName,
                "--crate-type", unit.isProceduralMacro ? "proc-macro" : "lib",
                "--emit", unitEmit.rustcEmitValue,
                "-Cmetadata=\(unit.fingerprint)",
                "-Cextra-filename=-\(unit.fingerprint)",
                "-Copt-level=0",
                // A dependency's lints are not the user's problem.
                "--cap-lints", "allow",
                "--error-format=json",
                "--out-dir", "/artifacts",
                "-Zunstable-options",
            ]
            for feature in unit.features.sorted() {
                arguments += ["--cfg", "feature=\"\(feature)\""]
            }
            arguments += externArguments(unit.externs, emit: unitEmit)
            if unit.isProceduralMacro {
                // Cargo exposes the sysroot API through the extern prelude.
                // Edition 2018+ macro crates may use it without extern crate.
                arguments += ["--extern", "proc_macro", "-Cprefer-dynamic=no", "-Crelocation-model=static"]
            }
            arguments += buildOutput.compilerArguments

            var environment = cargoEnvironment(for: unit)
            environment.merge(buildOutput.environment) { _, new in new }
            if unit.buildScriptPath != nil { environment["OUT_DIR"] = "/build-out" }

            let output: WasmProcessResult
            do {
                output = try invokeRustc(
                    toolchain: toolchain,
                    arguments: arguments,
                    jobRoot: jobRoot,
                    capturePrefix: "dep-\(unit.fingerprint)",
                    preopens: [
                        .init(guestPath: "/tmp", hostPath: tempURL.path),
                        .init(guestPath: "/sysroot", hostPath: toolchain.sysrootURL.path, readOnly: true),
                        .init(guestPath: "/registry", hostPath: registryRoot.path, readOnly: true),
                        .init(guestPath: "/artifacts", hostPath: artifacts.path),
                    ] + (unit.buildScriptPath == nil ? [] : [
                        .init(guestPath: "/build-out", hostPath: generatedURL.path, readOnly: true)
                    ]) + (patchRoot.map {
                        [.init(guestPath: "/patches", hostPath: $0.path, readOnly: true)]
                    } ?? []),
                    environment: environment,
                    interrupter: interrupter,
                    proceduralMacroInputs: macroInputs(for: plan)
                )
            } catch let cancellation as WasmExecutionCancelled {
                return cancelledResult(
                    phase: .compile, started: started, cancellation: cancellation
                )
            } catch let failure as RustcRuntimeFailure {
                // A codegen gap in the bundled backend prints a normal JSON
                // diagnostic and *then* aborts, so the useful message is in the
                // captured output rather than in the trap itself.
                let reason = RustDiagnosticParser.parse(stderr: failure.stderr).first?.message
                    ?? Self.firstErrorLine(in: failure.stderr)
                    ?? "the bundled rustc trapped while compiling it"
                return dependencyFailure(unit: unit, detail: reason, stderr: failure.stderr, started: started)
            } catch {
                return dependencyFailure(
                    unit: unit,
                    detail: error.localizedDescription,
                    stderr: "",
                    started: started
                )
            }

            let diagnostics = RustDiagnosticParser.parse(stderr: output.stderr)
            let hasErrors = diagnostics.contains { $0.level == "error" }
            guard output.exitCode == 0, !hasErrors,
                  FileManager.default.fileExists(atPath: outputURL.path)
            else {
                let reason = diagnostics.first?.message
                    ?? Self.firstErrorLine(in: output.stderr)
                    ?? "rustc exited with code \(output.exitCode)"
                return dependencyFailure(
                    unit: unit,
                    detail: reason,
                    stderr: diagnostics.isEmpty ? output.stderr : "",
                    started: started
                )
            }
            ledger.record(
                package: unit.package,
                fingerprint: unit.fingerprint,
                outcome: unitEmit == .metadata ? .checked : .built
            )
        }
        return nil
    }

    /// Builds a private merged tree for an editable dependency overlay.
    /// Registry bytes are copied, never modified; editable project files then
    /// replace their matching paths in the temporary tree.
    private func materializeProjectPatch(
        for unit: CargoBuildUnit,
        workURL: URL,
        registryRoot: URL,
        jobRoot: URL
    ) throws -> URL? {
        guard case let .projectPatch(relativeDirectory, registryDirectoryName) = unit.source else {
            return nil
        }
        let patchesRoot = jobRoot.appending(path: "patches", directoryHint: .isDirectory)
        let destination = patchesRoot.appending(path: unit.fingerprint, directoryHint: .isDirectory)
        let original = registryRoot.appending(path: registryDirectoryName, directoryHint: .isDirectory)
        let overlay = workURL.appending(path: relativeDirectory, directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: original.path),
              FileManager.default.fileExists(atPath: overlay.path)
        else {
            throw CocoaError(.fileNoSuchFile)
        }

        try FileManager.default.createDirectory(at: patchesRoot, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: original, to: destination)

        let overlayRoot = overlay.standardizedFileURL.path
        guard let walker = FileManager.default.enumerator(
            at: overlay,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsPackageDescendants]
        ) else {
            throw CocoaError(.fileReadUnknown)
        }
        for case let fileURL as URL in walker {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                if values.isRegularFile != true { walker.skipDescendants() }
                continue
            }
            guard values.isRegularFile == true else { continue }
            let standardized = fileURL.standardizedFileURL.path
            guard standardized.hasPrefix(overlayRoot + "/") else {
                throw CocoaError(.fileReadInvalidFileName)
            }
            let relative = String(standardized.dropFirst(overlayRoot.count + 1))
            guard let target = projectFileURL(relativePath: relative, under: destination) else {
                throw ProjectLayoutError.invalidPath(relative)
            }
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.copyItem(at: fileURL, to: target)
        }
        return patchesRoot
    }

    /// Picks the first `error: …` line out of raw rustc output.
    static func firstErrorLine(in stderr: String) -> String? {
        for line in stderr.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8),
               let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
               object["level"] as? String == "error",
               let message = object["message"] as? String {
                let code = (object["code"] as? [String: Any])?["code"] as? String
                let prefix = code.map { "error[\($0)]" } ?? "error"
                return String("\(prefix): \(message)".prefix(500))
            }
            guard trimmed.hasPrefix("error") else { continue }
            return String(trimmed.prefix(240))
        }
        return nil
    }

    private func dependencyFailure(
        unit: CargoBuildUnit,
        detail: String,
        stderr: String,
        started: ContinuousClock.Instant
    ) -> CompilationResult {
        // Remember the verdict so the package list can show it without paying
        // for another multi-minute compile.
        ledger.record(package: unit.package, fingerprint: unit.fingerprint, outcome: .failed(detail))
        return CompilationResult(
            succeeded: false,
            phase: .compile,
            exitCode: nil,
            diagnostics: [],
            stdout: "",
            // rustc emits JSON Lines for dependency diagnostics. The Output
            // tab should show a readable error instead of a raw JSON object.
            stderr: Self.firstErrorLine(in: stderr) ?? detail,
            duration: started.duration(to: clock.now),
            detail: "\(unit.package.name) \(unit.package.version) did not build: \(detail)"
        )
    }

    /// `env!("CARGO_PKG_…")` is common enough in real crates that omitting these
    /// turns otherwise-compatible packages into compile errors.
    /// Build scripts are guest programs too: immutable package input, one
    /// writable OUT_DIR, no host subprocesses, network, or app storage access.
    private func runBuildScript(
        for unit: CargoBuildUnit, toolchain: BundledToolchain,
        registryRoot: URL, patchRoot: URL?, generatedURL: URL,
        jobRoot: URL, tempURL: URL, interrupter: WasmInterrupter,
        sourceOverride: URL? = nil, guestSourceOverride: String? = nil,
        packageEnvironment: [String: String]? = nil
    ) throws -> CargoBuildScriptOutput {
        guard let script = unit.buildScriptPath else { return .init() }
        guard unit.buildScriptDependencies.isEmpty else {
            throw CargoBuildScriptOutput.Failure("Build dependencies require a separate host graph: \(unit.buildScriptDependencies.joined(separator: ", "))")
        }
        let guestSource = guestSourceOverride ?? unit.guestSourceDirectory
        let sourceRoot: URL
        if let sourceOverride { sourceRoot = sourceOverride }
        else {
            switch unit.source {
            case let .registry(directoryName): sourceRoot = registryRoot.appending(path: directoryName)
            case .projectPatch:
                guard let patchRoot else { throw CargoBuildScriptOutput.Failure("Missing build-script patch input.") }
                sourceRoot = patchRoot.appending(path: unit.fingerprint)
            }
        }
        guard projectFileURL(relativePath: script, under: sourceRoot) != nil else {
            throw CargoBuildScriptOutput.Failure("Invalid build-script path: \(script)")
        }
        try FileManager.default.createDirectory(at: generatedURL, withIntermediateDirectories: true)
        let binaryName = "build-\(unit.fingerprint).wasm"
        var environment = packageEnvironment ?? cargoEnvironment(for: unit)
        environment["CARGO_MANIFEST_DIR"] = guestSource
        environment["OUT_DIR"] = "/build-out"
        environment["HOST"] = "wasm32-wasip1"
        environment["TARGET"] = "wasm32-wasip1"
        // Cargo names its compiler even when subprocesses are unavailable.
        // WASI probes can then handle Unsupported and select their conservative
        // fallback instead of aborting on a missing environment variable.
        environment["RUSTC"] = "rustc"
        environment["PROFILE"] = "debug"
        environment["OPT_LEVEL"] = "0"
        environment["DEBUG"] = "true"
        environment["NUM_JOBS"] = "1"
        environment["CARGO_ENCODED_RUSTFLAGS"] = ""
        let target = RustTargetSpec.wasm32WasiP1
        for flag in target.cfgFlags { environment["CARGO_CFG_\(flag.uppercased())"] = "" }
        for (key, values) in target.cfgValues {
            environment["CARGO_CFG_\(key.uppercased())"] = values.sorted().joined(separator: ",")
        }
        var arguments = [
            "rustc", "\(guestSource)/\(script)",
            "--sysroot", "/sysroot", "--target", "wasm32-wasip1",
            "--edition", unit.edition, "--crate-name", "build_script_build",
            "--error-format=json", "-Copt-level=0", "-Cpanic=abort",
            "-Zunstable-options", "-o", "/tmp/\(binaryName)"
        ]
        for feature in unit.features { arguments += ["--cfg", "feature=\"\(feature)\""] }
        let sourcePreopen = WASIBridgeToHost.Preopen(
            guestPath: guestSource, hostPath: sourceRoot.path, readOnly: true)
        let compilation = try invokeRustc(
            toolchain: toolchain, arguments: arguments, jobRoot: jobRoot,
            capturePrefix: "script-compile-\(unit.fingerprint)",
            preopens: [sourcePreopen,
                       .init(guestPath: "/tmp", hostPath: tempURL.path),
                       .init(guestPath: "/sysroot", hostPath: toolchain.sysrootURL.path, readOnly: true)],
            environment: environment, interrupter: interrupter)
        guard compilation.exitCode == 0 else {
            throw CargoBuildScriptOutput.Failure(
                "Could not compile \(script): \(compilation.stderr)")
        }
        let prefix = "script-run-\(unit.fingerprint)"
        let quota = WasmSandboxQuotaMonitor(
            captureDirectory: jobRoot, capturePrefix: prefix,
            writableDirectory: generatedURL, interrupter: interrupter)
        quota.start()
        defer { quota.stop() }
        let output = try runtime.run(
            module: parseWasm(filePath: tempURL.appending(path: binaryName).path),
            arguments: ["build-script"], environment: environment,
            preopens: [sourcePreopen,
                       .init(guestPath: ".", hostPath: sourceRoot.path, readOnly: true),
                       .init(guestPath: "/build-out", hostPath: generatedURL.path)],
            captureDirectory: jobRoot, capturePrefix: prefix,
            resourceLimiter: WasmSandboxResourceLimiter(),
            fuelBudget: WasmSandboxPolicy.userProgramInstructionBudget,
            wallClockLimit: WasmSandboxPolicy.userProgramWallClockLimit,
            interrupter: interrupter,
            softwareMemoryReservationBytes: WasmSandboxPolicy.userProgramMemoryLimitBytes,
            capturedOutputLimitBytes: WasmSandboxPolicy.userProgramOutputLimitBytes)
        if let reason = quota.checkNow() { throw WasmExecutionCancelled(reason: reason) }
        guard output.exitCode == 0 else {
            throw CargoBuildScriptOutput.Failure("\(script) exited with \(output.exitCode): \(output.stderr)")
        }
        return try CargoBuildScriptOutput.parse(output.stdout)
    }

    private func cargoEnvironment(for unit: CargoBuildUnit) -> [String: String] {
        let version = unit.package.version
        var environment: [String: String] = [
            "CLIF2WASM_OBJECT": "1",
            "CARGO_CRATE_NAME": unit.crateName,
            "CARGO_PKG_NAME": unit.package.name,
            "CARGO_PKG_VERSION": version.description,
            "CARGO_PKG_VERSION_MAJOR": String(version.major),
            "CARGO_PKG_VERSION_MINOR": String(version.minor),
            "CARGO_PKG_VERSION_PATCH": String(version.patch),
            "CARGO_PKG_VERSION_PRE": version.prerelease.joined(separator: "."),
            "CARGO_PKG_AUTHORS": unit.authors,
            "CARGO_PKG_DESCRIPTION": unit.description,
            "CARGO_PKG_REPOSITORY": unit.repository,
            "CARGO_PKG_HOMEPAGE": unit.homepage,
            "CARGO_PKG_LICENSE": unit.license,
            "CARGO_PKG_LICENSE_FILE": "",
            "CARGO_PKG_RUST_VERSION": "",
            "CARGO_MANIFEST_DIR": unit.guestSourceDirectory,
        ]
        for feature in unit.features {
            environment["CARGO_FEATURE_\(Self.featureEnvironmentKey(feature))"] = "1"
        }
        return environment
    }

    /// Cargo's own spelling: uppercased, with `-` and `.` folded to `_`.
    private static func featureEnvironmentKey(_ feature: String) -> String {
        feature.uppercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: ".", with: "_")
    }

    /// Cargo projects commonly use `env!("CARGO_PKG_…")` in their own root
    /// target too. These values come from the exact project manifest rather
    /// than being present only while dependencies compile.
    private func rootCargoEnvironment(
        sourcePath: String,
        supportingFiles: [String: String],
        features: [String]
    ) -> [String: String] {
        var environment = ["CLIF2WASM_OBJECT": "1"]
        for feature in features {
            environment["CARGO_FEATURE_\(Self.featureEnvironmentKey(feature))"] = "1"
        }
        guard let manifestSource = supportingFiles["Cargo.toml"],
              let manifest = try? CratePackageManifest.parse(manifestSource),
              !manifest.packageName.isEmpty
        else { return environment }

        let version = manifest.version ?? SemanticVersion(major: 0, minor: 0, patch: 0)
        let crateName = CratePackageManifest.crateIdentifier(for: manifest.packageName)
        environment.merge([
            "CARGO_CRATE_NAME": crateName,
            "CARGO_BIN_NAME": crateName,
            "CARGO_PKG_NAME": manifest.packageName,
            "CARGO_PKG_VERSION": version.description,
            "CARGO_PKG_VERSION_MAJOR": String(version.major),
            "CARGO_PKG_VERSION_MINOR": String(version.minor),
            "CARGO_PKG_VERSION_PATCH": String(version.patch),
            "CARGO_PKG_VERSION_PRE": version.prerelease.joined(separator: "."),
            "CARGO_PKG_AUTHORS": "",
            "CARGO_PKG_DESCRIPTION": "",
            "CARGO_PKG_REPOSITORY": "",
            "CARGO_PKG_HOMEPAGE": "",
            "CARGO_PKG_LICENSE": "",
            "CARGO_PKG_LICENSE_FILE": "",
            "CARGO_PKG_RUST_VERSION": manifest.rustVersion ?? "",
            "CARGO_MANIFEST_DIR": "/work",
            "CARGO_PRIMARY_PACKAGE": "1",
        ]) { _, exact in exact }
        if sourcePath.hasSuffix("lib.rs") {
            environment.removeValue(forKey: "CARGO_BIN_NAME")
        }
        return environment
    }

    private func externArguments(_ externs: [CargoExtern], emit: CargoEmitKind) -> [String] {
        guard !externs.isEmpty else { return [] }
        var arguments: [String] = []
        for value in externs.sorted(by: { $0.alias < $1.alias }) {
            arguments += ["--extern", "\(value.alias)=/artifacts/\(value.fileName(emit: emit))"]
        }
        // rustc resolves transitive dependencies out of this directory using the
        // identity recorded in each artefact, so several versions can coexist.
        arguments += ["-L", "dependency=/artifacts"]
        return arguments
    }

    private func registryPreopens(for plan: CargoBuildPlan) -> [WASIBridgeToHost.Preopen] {
        guard !plan.rootExterns.isEmpty, let artifacts = artifactsDirectory else { return [] }
        return [.init(guestPath: "/artifacts", hostPath: artifacts.path, readOnly: true)]
    }

    private func artifactFileName(_ unit: CargoBuildUnit, emit: CargoEmitKind) -> String {
        CargoExtern(alias: unit.crateName, crateName: unit.crateName, fingerprint: unit.fingerprint,
                    isProceduralMacro: unit.isProceduralMacro, requiresLink: unit.requiresLink).fileName(emit: emit)
    }

    private func macroInputs(for plan: CargoBuildPlan) -> [String] {
        plan.units.filter(\.isProceduralMacro).map { "/artifacts/" + artifactFileName($0, emit: .link) }
    }

    private var artifactsDirectory: URL? {
        (dependencyArtifactRoot ?? CrateStorageLayout.artifactDirectory)?
            .appending(path: toolchainNamespace, directoryHint: .isDirectory)
            .appending(path: CargoFingerprint.schemaVersion, directoryHint: .isDirectory)
    }

    // MARK: - Guest execution

    private func invokeRustc(
        toolchain: BundledToolchain,
        arguments: [String],
        jobRoot: URL,
        capturePrefix: String,
        preopens: [WASIBridgeToHost.Preopen],
        environment: [String: String] = ["CLIF2WASM_OBJECT": "1"],
        interrupter: WasmInterrupter,
        proceduralMacroInputs: [String] = []
    ) throws -> WasmProcessResult {
        var environment = environment
        if toolchain.supportsProceduralMacros { environment["CRABRIX_WASM_PROC_MACROS"] = "1" }
        #if CRABRIX_NATIVE_COMPILER
        if let sha = toolchain.compilerSHA256, sha == NativeRustcSession.compilerSHA256 {
            let started = ContinuousClock.now
            let result = try runtime.runNativeCompiler(arguments: arguments, environment: environment,
                preopens: preopens, captureDirectory: jobRoot, capturePrefix: capturePrefix,
                interrupter: interrupter, enableProceduralMacros: toolchain.supportsProceduralMacros,
                proceduralMacroInputs: proceduralMacroInputs)
            CompilerPhaseTrace.emit("native-rustc", since: started)
            return result
        }
        #endif
        let module = try runtime.rustcModule(at: toolchain.rustcURL)
        // Parsing the bundled rustc module is the one phase no interrupter can
        // reach into: it is host work, not guest execution. Ask once it is done
        // rather than starting a compile the user already stopped.
        if let reason = interrupter.stopReason {
            throw WasmExecutionCancelled(reason: reason)
        }
        let invocationStarted = ContinuousClock.now
        let result = try autoreleasepool { try runtime.run(
            module: module,
            arguments: arguments,
            environment: environment,
            preopens: preopens,
            captureDirectory: jobRoot,
            capturePrefix: capturePrefix,
            resourceLimiter: WasmSandboxResourceLimiter(
                memoryLimitBytes: CompilerHostPolicy.memoryLimitBytes,
                tableElementLimit: CompilerHostPolicy.tableElementLimit
            ),
            fuelBudget: CompilerHostPolicy.fuelBudget,
            wallClockLimit: CompilerHostPolicy.wallClockLimit,
            interrupter: interrupter,
            softwareMemoryReservationBytes: CompilerHostPolicy.memoryLimitBytes,
            capturedOutputLimitBytes: CompilerHostPolicy.outputLimitBytes,
            enableProceduralMacros: toolchain.supportsProceduralMacros,
            proceduralMacroInputs: proceduralMacroInputs
        ) }
        CompilerPhaseTrace.emit("rustc-after-pool", since: invocationStarted)
        return result
    }

    private func executeProgram(
        module: Module,
        jobRoot: URL,
        diagnostics: [RustDiagnostic],
        started: ContinuousClock.Instant,
        interrupter: WasmInterrupter,
        previewSourceFiles: [String: String],
        previewResourceFiles: [String: Data],
        successDetail: String,
        debugSession: RustDebugSession? = nil,
        programArguments: [String] = []
    ) throws -> CompilationResult {
        let sandboxURL = jobRoot.appending(path: "sandbox", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sandboxURL, withIntermediateDirectories: true)
        let resourceLimiter = WasmSandboxResourceLimiter()
        let quotaMonitor = WasmSandboxQuotaMonitor(
            captureDirectory: jobRoot,
            capturePrefix: "program",
            writableDirectory: sandboxURL,
            interrupter: interrupter
        )
        quotaMonitor.start()
        defer { quotaMonitor.stop() }

        let output: WasmProcessResult
        do {
            output = try runtime.run(
                module: module,
                arguments: ["program"] + programArguments,
                environment: [:],
                preopens: [
                    .init(
                        guestPath: WasmSandboxPolicy.writableGuestDirectory,
                        hostPath: sandboxURL.path
                    )
                ],
                captureDirectory: jobRoot,
                capturePrefix: "program",
                resourceLimiter: resourceLimiter,
                fuelBudget: WasmSandboxPolicy.userProgramInstructionBudget,
                wallClockLimit: WasmSandboxPolicy.userProgramWallClockLimit,
                interrupter: interrupter,
                softwareMemoryReservationBytes: WasmSandboxPolicy.userProgramMemoryLimitBytes,
                capturedOutputLimitBytes: WasmSandboxPolicy.userProgramOutputLimitBytes,
                debugSession: debugSession
            )
        } catch let cancellation as WasmExecutionCancelled {
            return cancelledResult(phase: .run, started: started, cancellation: cancellation)
        } catch let failure as RustcRuntimeFailure {
            if let deniedResource = resourceLimiter.deniedResource {
                let detail = switch deniedResource {
                case .memory:
                    "Program stopped at the \(WasmSandboxPolicy.memoryLimitLabel) sandbox memory limit."
                case .table:
                    "Program stopped at the sandbox table limit."
                }
                return CompilationResult(
                    succeeded: false,
                    phase: .run,
                    exitCode: nil,
                    diagnostics: diagnostics,
                    stdout: failure.stdout,
                    stderr: failure.stderr,
                    duration: started.duration(to: clock.now),
                    detail: detail
                )
            }
            // A panic belongs to the running program. Preserve its captured
            // message instead of reclassifying it as a compiler failure.
            let trap = String(describing: failure.underlying).split(separator: "\n").first.map(String.init)
                ?? "unexpected WebAssembly trap"
            return CompilationResult(succeeded: false, phase: .run, exitCode: nil,
                diagnostics: diagnostics, stdout: failure.stdout, stderr: failure.stderr,
                duration: started.duration(to: clock.now), detail: "Program trapped: \(trap)")
        }

        var webAssets = previewSourceFiles.filter { WebPreviewSnapshot.mimeType(for: $0.key) != nil }.mapValues { Data($0.utf8) }
        webAssets.merge(previewResourceFiles.filter { WebPreviewSnapshot.mimeType(for: $0.key) != nil }) { _, resource in resource }
        let generated = WebPreviewSnapshot.generated(in: sandboxURL)
        webAssets.merge(generated) { _, new in new }
        let printed = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !generated.keys.contains(where: { SourceLanguage(filePath: $0) == .html }),
           printed.lowercased().hasPrefix("<!doctype html") || printed.lowercased().hasPrefix("<html") {
            webAssets["index.html"] = Data(output.stdout.utf8)
        }
        return CompilationResult(
            succeeded: output.exitCode == 0,
            phase: .run,
            exitCode: output.exitCode,
            diagnostics: diagnostics,
            stdout: output.stdout,
            stderr: output.stderr,
            duration: started.duration(to: clock.now),
            detail: output.exitCode == 0
                ? successDetail
                : "The program exited with code \(output.exitCode).",
            webPreview: output.exitCode == 0 ? WebPreviewSnapshot(files: webAssets) : nil
        )
    }

    private func cancelledResult(
        phase: CompilationResult.Phase,
        started: ContinuousClock.Instant,
        cancellation: WasmExecutionCancelled = .init(reason: .userRequested)
    ) -> CompilationResult {
        let runningProgram = phase == .run
        let outputLimitLabel = ByteCountFormatter.string(
            fromByteCount: Int64(runningProgram
                ? WasmSandboxPolicy.userProgramOutputLimitBytes
                : CompilerHostPolicy.outputLimitBytes),
            countStyle: .file
        )
        let writableLimitLabel = ByteCountFormatter.string(
            fromByteCount: Int64(WasmSandboxPolicy.userProgramWritableBytesLimit),
            countStyle: .file
        )
        let detail = switch cancellation.reason {
        case .userRequested:
            "Build stopped. The Wasm guest was interrupted and its sandbox released."
        case .instructionBudget:
            (runningProgram ? "Program" : "Compiler")
                + " stopped at the local instruction budget. Its sandbox was released."
        case .wallClock:
            (runningProgram
                ? "Program stopped at the 30-second local runtime limit."
                : "Compiler stopped at the 20-minute local build limit.")
                + " Its sandbox was released."
        case .outputLimit:
            (runningProgram ? "Program" : "Compiler")
                + " stopped at the " + outputLimitLabel + " output limit."
        case .fileCountLimit:
            "Program stopped at the sandbox limit of "
                + String(WasmSandboxPolicy.userProgramFileCountLimit)
                + " writable files."
        case .writableBytesLimit:
            "Program stopped at the " + writableLimitLabel + " writable sandbox limit."
        }
        return CompilationResult(
            succeeded: false,
            phase: phase,
            exitCode: nil,
            diagnostics: [],
            stdout: cancellation.stdout,
            stderr: cancellation.stderr,
            duration: started.duration(to: clock.now),
            detail: detail
        )
    }

    // MARK: - Project layout

    private func cachedCheck(for key: String) -> CompilationResult? {
        guard let result = successfulChecks[key] else { return nil }
        checkCacheOrder.removeAll { $0 == key }
        checkCacheOrder.append(key)
        return result
    }

    private func cacheCheck(_ result: CompilationResult, for key: String) {
        let diagnosticBytes = result.diagnostics.reduce(0) { total, diagnostic in
            total + diagnostic.message.utf8.count + diagnostic.rendered.utf8.count
                + diagnostic.spans.reduce(0) { $0 + $1.sourceLine.utf8.count }
        }
        guard result.diagnostics.count <= 128,
              result.stdout.utf8.count + result.stderr.utf8.count + diagnosticBytes <= 256 * 1024
        else { return }
        successfulChecks[key] = result
        checkCacheOrder.removeAll { $0 == key }
        checkCacheOrder.append(key)
        if checkCacheOrder.count > Self.checkCacheLimit {
            successfulChecks.removeValue(forKey: checkCacheOrder.removeFirst())
        }
    }

    private enum ProjectLayoutError: LocalizedError {
        case invalidPath(String)

        var errorDescription: String? {
            switch self {
            case let .invalidPath(path): "Invalid project path: \(path)"
            }
        }
    }

    private func writeProject(
        source: String,
        sourcePath: String,
        supportingFiles: [String: String],
        resourceFiles: [String: Data],
        into workURL: URL
    ) throws {
        let fileManager = FileManager.default
        guard let sourceURL = projectFileURL(relativePath: sourcePath, under: workURL) else {
            throw ProjectLayoutError.invalidPath(sourcePath)
        }
        try fileManager.createDirectory(
            at: sourceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(source.utf8).write(to: sourceURL, options: .atomic)

        for (relativePath, contents) in supportingFiles where relativePath != sourcePath {
            guard let fileURL = projectFileURL(relativePath: relativePath, under: workURL) else {
                throw ProjectLayoutError.invalidPath(relativePath)
            }
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(contents.utf8).write(to: fileURL, options: .atomic)
        }
        for (path, data) in resourceFiles {
            guard let url = projectFileURL(relativePath: path, under: workURL) else { throw ProjectLayoutError.invalidPath(path) }
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
    }

    private func projectFileURL(relativePath: String, under root: URL) -> URL? {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !relativePath.hasPrefix("/"),
              !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else {
            return nil
        }
        return components.reduce(root) { partial, component in
            partial.appending(path: String(component))
        }
    }

    private func validateResources(_ resources: [String: Data], source: String, sourcePath: String,
                                   supportingFiles: [String: String]) throws {
        guard !resources.isEmpty else { return }
        var text = supportingFiles; text[sourcePath] = source
        guard Set(text.keys).isDisjoint(with: resources.keys), text.count + resources.count <= 8192,
              resources.values.allSatisfy({ $0.count <= 8 * 1024 * 1024 }),
              text.values.reduce(0, { $0 + $1.utf8.count }) + resources.values.reduce(0, { $0 + $1.count }) <= 64 * 1024 * 1024 else {
            throw GitRepositoryFailure("Compiler resources conflict with text or exceed the 8 MiB/file, 8,192-file, 64 MiB input profile.")
        }
        var names: Set<String> = [], folders: [String: String] = [:]
        for path in Set(text.keys).union(resources.keys).sorted() {
            try ProjectFilePolicy.validatePath(path)
            let normalized = path.precomposedStringWithCanonicalMapping.lowercased()
            guard names.insert(normalized).inserted, folders[normalized] == nil else { throw ProjectLayoutError.invalidPath(path) }
            let parts = path.split(separator: "/")
            for length in 1..<parts.count {
                let folder = parts.prefix(length).joined(separator: "/"), key = folder.precomposedStringWithCanonicalMapping.lowercased()
                guard !names.contains(key), folders[key] == nil || folders[key] == folder else { throw ProjectLayoutError.invalidPath(path) }
                folders[key] = folder
            }
        }
    }

    // MARK: - Program artifact cache

    private func isLibraryEntry(_ sourcePath: String, supportingFiles: [String: String]) -> Bool {
        let manifest = supportingFiles["Cargo.toml"].flatMap { try? CratePackageManifest.parse($0) }
        return sourcePath == manifest?.library.path || sourcePath == "lib.rs" || sourcePath.hasSuffix("/lib.rs")
    }

    private func artifactKey(
        action: Action,
        source: String,
        sourcePath: String,
        supportingFiles: [String: String],
        resourceFiles: [String: Data],
        edition: String,
        plan: CargoBuildPlan
    ) -> String {
        var hasher = SHA256()
        let actionLabel = action.testInvocation != nil ? "libtest-abort-v1" : action == .check ? "check" : action == .build && isLibraryEntry(sourcePath, supportingFiles: supportingFiles) ? "library" : "run"
        let compilerIdentity = toolchainOverride.map {
            CargoToolchain.artifactIdentity + ":candidate:" + $0.version
        } ?? CargoToolchain.artifactIdentity
        for value in [
            compilerIdentity, Self.cacheSchemaVersion,
            actionLabel, edition, sourcePath, source,
        ] {
            hasher.update(data: Data(value.utf8))
            hasher.update(data: Data([0]))
        }
        for (path, contents) in supportingFiles.sorted(by: { $0.key < $1.key }) {
            hasher.update(data: Data(path.utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: Data(contents.utf8))
            hasher.update(data: Data([0]))
        }
        if let fingerprint = GitRepositoryStore.resourceFingerprint(resourceFiles) {
            hasher.update(data: Data(("opaque-resources-v1:" + fingerprint).utf8))
        }
        // The root's own active features change what compiles, so they are part
        // of the identity even though they are derived from the manifest above.
        for feature in plan.rootFeatures {
            hasher.update(data: Data("feature=\(feature)".utf8))
            hasher.update(data: Data([0]))
        }
        // Dependency identity is part of the key, so adding or changing a crate
        // never reuses a stale program artifact.
        for value in plan.rootExterns.sorted(by: { $0.alias < $1.alias }) {
            hasher.update(data: Data("\(value.alias)=\(value.crateName)-\(value.fingerprint)".utf8))
            hasher.update(data: Data([0]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private var programCacheURL: URL? {
        (projectArtifactRoot ?? CrateStorageLayout.projectArtifactDirectory)?
            .appending(path: toolchainNamespace, directoryHint: .isDirectory)
            .appending(path: Self.cacheSchemaVersion, directoryHint: .isDirectory)
    }

    private func programArtifactURL(for key: String) -> URL? {
        programCacheURL?.appending(path: "\(key).wasm")
    }

    private func loadCachedProgramModule(for key: String) -> Module? {
        if let module = runtime.programModule(for: key) { return module }
        guard let url = programArtifactURL(for: key),
              FileManager.default.fileExists(atPath: url.path)
        else {
            return nil
        }
        do {
            let module = try parseWasm(filePath: url.path)
            if let byteCount = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                runtime.cacheProgramModule(module, for: key, wasmFileBytes: byteCount)
            }
            return module
        } catch {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }

    private func persistProgramArtifact(at source: URL, for key: String) {
        guard let directory = programCacheURL, let url = programArtifactURL(for: key) else { return }
        let staging = directory.appending(path: ".\(key)-\(UUID().uuidString).stage")
        defer { try? FileManager.default.removeItem(at: staging) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: url.path) { return }
            try FileManager.default.copyItem(at: source, to: staging)
            try FileManager.default.moveItem(at: staging, to: url)
        } catch {
            // A cache write must never turn a successful local compilation into a failure.
        }
    }
}
