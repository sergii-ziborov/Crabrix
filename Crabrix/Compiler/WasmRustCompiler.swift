import Foundation
import CryptoKit
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

final class WasmRustCompiler: @unchecked Sendable {
    private enum Action {
        case check
        case run

        var emit: CargoEmitKind {
            switch self {
            case .check: .metadata
            case .run: .link
            }
        }
    }

    static var toolchainVersion: String { CargoToolchain.bundledVersion }
    // Bumped when the root compiler invocation changes shape: artefacts built
    // before the root crate received its own `--cfg feature="…"` flags must not
    // be reused for the same manifest.
    private static let cacheSchemaVersion = "fast-dev-3"

    private let bundle: Bundle
    private let ledger: CrateCompatibilityLedger
    private let runtime = RustcRuntime()
    // rustc runs synchronously inside the Wasm interpreter. Keep that CPU-heavy work
    // below the UI's QoS so scrolling, navigation, and animations stay responsive.
    private let queue = DispatchQueue(
        label: "com.sergiiziborov.Crabrix.compiler",
        qos: .utility,
        autoreleaseFrequency: .workItem
    )
    private let clock = ContinuousClock()
    private var successfulCheckKeys: Set<String> = []
    private let interrupterLock = NSLock()
    private var activeInterrupter: WasmInterrupter?

    init(bundle: Bundle = .main, ledger: CrateCompatibilityLedger = .shared) {
        self.bundle = bundle
        self.ledger = ledger
    }

    // MARK: - Toolchain

    private var toolchain: BundledToolchain? {
        BundledToolchain.locate(in: bundle, version: Self.toolchainVersion)
    }

    func probe() -> ToolchainStatus {
        guard let toolchain else {
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
        edition: String = "2024",
        plan: CargoBuildPlan = .empty,
        onDependencyProgress: (@Sendable (CargoBuildProgress) -> Void)? = nil
    ) async -> CompilationResult {
        await perform(
            action: .check,
            source: source,
            sourcePath: sourcePath,
            supportingFiles: supportingFiles,
            edition: edition,
            plan: plan,
            onDependencyProgress: onDependencyProgress
        )
    }

    func run(
        source: String,
        sourcePath: String = "main.rs",
        supportingFiles: [String: String] = [:],
        edition: String = "2024",
        plan: CargoBuildPlan = .empty,
        onDependencyProgress: (@Sendable (CargoBuildProgress) -> Void)? = nil
    ) async -> CompilationResult {
        await perform(
            action: .run,
            source: source,
            sourcePath: sourcePath,
            supportingFiles: supportingFiles,
            edition: edition,
            plan: plan,
            onDependencyProgress: onDependencyProgress
        )
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
                successfulCheckKeys.removeAll(keepingCapacity: false)
                runtime.clearProgramModules()
                if let directory = CrateStorageLayout.projectArtifactDirectory,
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
        edition: String,
        plan: CargoBuildPlan,
        onDependencyProgress: (@Sendable (CargoBuildProgress) -> Void)?
    ) async -> CompilationResult {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                assert(!Thread.isMainThread, "Bundled rustc must never execute on the UI thread")
                continuation.resume(
                    returning: execute(
                        action: action,
                        source: source,
                        sourcePath: sourcePath,
                        supportingFiles: supportingFiles,
                        edition: edition,
                        plan: plan,
                        onDependencyProgress: onDependencyProgress
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
        edition: String,
        plan: CargoBuildPlan,
        onDependencyProgress: (@Sendable (CargoBuildProgress) -> Void)?
    ) -> CompilationResult {
        let started = clock.now
        guard let toolchain else {
            return .failure(phase: .setup, detail: "Bundled Rust toolchain is missing.")
        }
        guard ["2015", "2018", "2021", "2024"].contains(edition) else {
            return .failure(
                phase: .setup,
                detail: "Unsupported Cargo edition \"\(edition)\". Use 2015, 2018, 2021, or 2024."
            )
        }

        let interrupter = WasmInterrupter()
        interrupterLock.lock()
        activeInterrupter = interrupter
        interrupterLock.unlock()
        defer {
            interrupterLock.lock()
            activeInterrupter = nil
            interrupterLock.unlock()
        }

        let cacheKey = artifactKey(
            action: action,
            source: source,
            sourcePath: sourcePath,
            supportingFiles: supportingFiles,
            edition: edition,
            plan: plan
        )

        let fileManager = FileManager.default
        let jobRoot = fileManager.temporaryDirectory
            .appending(path: "CrabrixCompiler", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let workURL = jobRoot.appending(path: "work", directoryHint: .isDirectory)
        let tempURL = jobRoot.appending(path: "tmp", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: jobRoot) }

        do {
            try fileManager.createDirectory(at: workURL, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: tempURL, withIntermediateDirectories: true)
            try writeProject(
                source: source,
                sourcePath: sourcePath,
                supportingFiles: supportingFiles,
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

        do {
            if action == .check, successfulCheckKeys.contains(cacheKey) {
                return CompilationResult(
                    succeeded: true,
                    phase: .check,
                    exitCode: 0,
                    diagnostics: [],
                    stdout: "",
                    stderr: "",
                    duration: started.duration(to: clock.now),
                    detail: "Unchanged snapshot accepted from the local check cache."
                )
            }

            // Dependencies must exist before the cached-program fast path, because
            // a cached program.wasm already has them linked in.
            if action == .run, let cachedProgram = loadCachedProgramModule(for: cacheKey) {
                return try executeProgram(
                    module: cachedProgram,
                    jobRoot: jobRoot,
                    diagnostics: [],
                    started: started,
                    interrupter: interrupter,
                    successDetail: "Executed a cached local build artifact inside the bounded WasmKit sandbox."
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

            let outputName = action == .run ? "program.wasm" : "main.rmeta"
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

            switch action {
            case .check:
                arguments += ["--emit", "metadata", "-o", "/work/\(outputName)"]
            case .run:
                arguments += [
                    "-Zunstable-options", "-Copt-level=0", "-Cpanic=abort",
                    "-o", "/work/\(outputName)",
                ]
            }

            let compilerOutput: WasmProcessResult
            do {
                compilerOutput = try invokeRustc(
                    toolchain: toolchain,
                    arguments: arguments,
                    jobRoot: jobRoot,
                    capturePrefix: "compiler",
                    preopens: [
                        .init(guestPath: "/tmp", hostPath: tempURL.path),
                        .init(guestPath: "/sysroot", hostPath: toolchain.sysrootURL.path),
                        .init(guestPath: "/work", hostPath: workURL.path),
                    ] + registryPreopens(for: plan),
                    environment: rootCargoEnvironment(
                        sourcePath: sourcePath,
                        supportingFiles: supportingFiles,
                        features: plan.rootFeatures
                    ),
                    interrupter: interrupter
                )
            } catch is WasmExecutionCancelled {
                return cancelledResult(phase: action == .check ? .check : .compile, started: started)
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

            guard action == .run else {
                successfulCheckKeys.insert(cacheKey)
                return CompilationResult(
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
            }

            let programURL = workURL.appending(path: outputName)
            guard fileManager.fileExists(atPath: programURL.path) else {
                return .failure(
                    phase: .compile,
                    detail: "rustc exited successfully but emitted no program.wasm.",
                    stderr: compilerOutput.stderr,
                    duration: started.duration(to: clock.now)
                )
            }

            let programData = try Data(contentsOf: programURL)
            let programModule = try parseWasm(bytes: [UInt8](programData))
            runtime.cacheProgramModule(programModule, for: cacheKey)
            persistProgramArtifact(programData, for: cacheKey)

            return try executeProgram(
                module: programModule,
                jobRoot: jobRoot,
                diagnostics: diagnostics,
                started: started,
                interrupter: interrupter,
                successDetail: plan.isEmpty
                    ? "Compiled and executed locally inside the bounded WasmKit sandbox."
                    : "Compiled \(plan.units.count) dependencies and the program locally, then ran it in the bounded sandbox."
            )
        } catch let cancellation as WasmExecutionCancelled {
            return cancelledResult(
                phase: action == .check ? .check : .run,
                started: started,
                cancellation: cancellation
            )
        } catch {
            return .failure(
                phase: action == .check ? .check : .run,
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
            if interrupter.wasCancelled {
                return cancelledResult(phase: .compile, started: started)
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

            var arguments = [
                "rustc",
                "\(unit.guestSourceDirectory)/\(unit.libraryPath)",
                "--sysroot", "/sysroot",
                "--target", "wasm32-wasip1",
                "--edition", unit.edition,
                "--crate-name", unit.crateName,
                "--crate-type", "lib",
                "--emit", emit.rustcEmitValue,
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
            arguments += externArguments(unit.externs, emit: emit)

            let output: WasmProcessResult
            do {
                output = try invokeRustc(
                    toolchain: toolchain,
                    arguments: arguments,
                    jobRoot: jobRoot,
                    capturePrefix: "dep-\(unit.fingerprint)",
                    preopens: [
                        .init(guestPath: "/tmp", hostPath: tempURL.path),
                        .init(guestPath: "/sysroot", hostPath: toolchain.sysrootURL.path),
                        .init(guestPath: "/registry", hostPath: registryRoot.path),
                        .init(guestPath: "/artifacts", hostPath: artifacts.path),
                    ] + (patchRoot.map {
                        [.init(guestPath: "/patches", hostPath: $0.path)]
                    } ?? []),
                    environment: cargoEnvironment(for: unit),
                    interrupter: interrupter
                )
            } catch is WasmExecutionCancelled {
                return cancelledResult(phase: .compile, started: started)
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
                outcome: emit == .metadata ? .checked : .built
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
    private static func firstErrorLine(in stderr: String) -> String? {
        for line in stderr.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
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
            stderr: stderr,
            duration: started.duration(to: clock.now),
            detail: "\(unit.package.name) \(unit.package.version) did not build: \(detail)"
        )
    }

    /// `env!("CARGO_PKG_…")` is common enough in real crates that omitting these
    /// turns otherwise-compatible packages into compile errors.
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
        return [.init(guestPath: "/artifacts", hostPath: artifacts.path)]
    }

    private func artifactFileName(_ unit: CargoBuildUnit, emit: CargoEmitKind) -> String {
        "lib\(unit.crateName)-\(unit.fingerprint).\(emit.fileExtension)"
    }

    private var artifactsDirectory: URL? {
        CrateStorageLayout.artifactDirectory?
            .appending(path: Self.toolchainVersion, directoryHint: .isDirectory)
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
        interrupter: WasmInterrupter
    ) throws -> WasmProcessResult {
        let module = try runtime.rustcModule(at: toolchain.rustcURL)
        // Parsing the bundled rustc module is the one phase no interrupter can
        // reach into: it is host work, not guest execution. Ask once it is done
        // rather than starting a compile the user already stopped.
        if let reason = interrupter.stopReason {
            throw WasmExecutionCancelled(reason: reason)
        }
        return try runtime.run(
            module: module,
            arguments: arguments,
            environment: environment,
            preopens: preopens,
            captureDirectory: jobRoot,
            capturePrefix: capturePrefix,
            interrupter: interrupter
        )
    }

    private func executeProgram(
        module: Module,
        jobRoot: URL,
        diagnostics: [RustDiagnostic],
        started: ContinuousClock.Instant,
        interrupter: WasmInterrupter,
        successDetail: String
    ) throws -> CompilationResult {
        let sandboxURL = jobRoot.appending(path: "sandbox", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sandboxURL, withIntermediateDirectories: true)
        let resourceLimiter = WasmSandboxResourceLimiter()
        let instructionLimiter = WasmInstructionBudgetLimiter(interrupter: interrupter)
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
                arguments: ["program"],
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
                instructionLimiter: instructionLimiter,
                interrupter: interrupter,
                capturedOutputLimitBytes: WasmSandboxPolicy.userProgramOutputLimitBytes
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
            throw failure.underlying
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
                : "The program exited with code \(output.exitCode)."
        )
    }

    private func cancelledResult(
        phase: CompilationResult.Phase,
        started: ContinuousClock.Instant,
        cancellation: WasmExecutionCancelled = .init(reason: .userRequested)
    ) -> CompilationResult {
        let outputLimitLabel = ByteCountFormatter.string(
            fromByteCount: Int64(WasmSandboxPolicy.userProgramOutputLimitBytes),
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
            "Program stopped at the local instruction budget. Its sandbox was released."
        case .wallClock:
            "Program stopped at the 30-second local runtime limit. Its sandbox was released."
        case .outputLimit:
            "Program stopped after producing " + outputLimitLabel + " of output."
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

    // MARK: - Program artifact cache

    private func artifactKey(
        action: Action,
        source: String,
        sourcePath: String,
        supportingFiles: [String: String],
        edition: String,
        plan: CargoBuildPlan
    ) -> String {
        var hasher = SHA256()
        let actionLabel = action == .check ? "check" : "run"
        for value in [
            Self.toolchainVersion, Self.cacheSchemaVersion, actionLabel, edition, sourcePath, source,
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
        CrateStorageLayout.projectArtifactDirectory?
            .appending(path: Self.toolchainVersion, directoryHint: .isDirectory)
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
            let module = try parseWasm(bytes: [UInt8](Data(contentsOf: url)))
            runtime.cacheProgramModule(module, for: key)
            return module
        } catch {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }

    private func persistProgramArtifact(_ data: Data, for key: String) {
        guard let directory = programCacheURL, let url = programArtifactURL(for: key) else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            // A cache write must never turn a successful local compilation into a failure.
        }
    }
}
