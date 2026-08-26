import Foundation
import SystemPackage
@_spi(Fuzzing) import WasmKit
import WasmKitWASI

final class WasmRustCompiler: @unchecked Sendable {
    private enum Action {
        case check
        case run
    }

    private struct Capture {
        let stdoutURL: URL
        let stderrURL: URL
        let stdoutHandle: FileHandle
        let stderrHandle: FileHandle
    }

    private static let toolchainVersion = "artifacts-test-7"

    private let bundle: Bundle
    private let queue = DispatchQueue(label: "com.sergiiziborov.Crabrix.compiler", qos: .userInitiated)
    private let clock = ContinuousClock()
    private var cachedRustcModule: Module?
    private var cachedEngine: Engine?

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func probe() -> ToolchainStatus {
        guard let rustcURL, let sysrootURL else {
            return ToolchainStatus(
                isReady: false,
                rustcSize: 0,
                label: "Toolchain missing",
                detail: "Run scripts/bootstrap.sh before building."
            )
        }

        let size = (try? rustcURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        return ToolchainStatus(
            isReady: true,
            rustcSize: size,
            label: "Bundled rustc.wasm",
            detail: "WasmKit interpreter · fully local · \(sysrootURL.lastPathComponent)"
        )
    }

    func check(
        source: String,
        sourcePath: String = "main.rs",
        supportingFiles: [String: String] = [:]
    ) async -> CompilationResult {
        await perform(
            action: .check,
            source: source,
            sourcePath: sourcePath,
            supportingFiles: supportingFiles
        )
    }

    func run(
        source: String,
        sourcePath: String = "main.rs",
        supportingFiles: [String: String] = [:]
    ) async -> CompilationResult {
        await perform(
            action: .run,
            source: source,
            sourcePath: sourcePath,
            supportingFiles: supportingFiles
        )
    }

    private func perform(
        action: Action,
        source: String,
        sourcePath: String,
        supportingFiles: [String: String]
    ) async -> CompilationResult {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(
                    returning: execute(
                        action: action,
                        source: source,
                        sourcePath: sourcePath,
                        supportingFiles: supportingFiles
                    )
                )
            }
        }
    }

    private var toolchainRootURL: URL? {
        bundle.resourceURL?
            .appendingPathComponent("Toolchain", isDirectory: true)
            .appendingPathComponent(Self.toolchainVersion, isDirectory: true)
    }

    private var rustcURL: URL? {
        let url = toolchainRootURL?.appendingPathComponent("rustc.wasm")
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    private var sysrootURL: URL? {
        let url = toolchainRootURL?.appendingPathComponent("sysroot-wasip1", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard let url,
              FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return nil
        }
        return url
    }

    private func execute(
        action: Action,
        source: String,
        sourcePath: String,
        supportingFiles: [String: String]
    ) -> CompilationResult {
        let started = clock.now
        guard let rustcURL, let sysrootURL else {
            return .failure(phase: .setup, detail: "Bundled Rust toolchain is missing.")
        }

        let fileManager = FileManager.default
        let jobRoot = fileManager.temporaryDirectory
            .appendingPathComponent("CrabrixCompiler", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workURL = jobRoot.appendingPathComponent("work", isDirectory: true)
        let tempURL = jobRoot.appendingPathComponent("tmp", isDirectory: true)

        do {
            try fileManager.createDirectory(at: workURL, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: tempURL, withIntermediateDirectories: true)
            guard let sourceURL = projectFileURL(relativePath: sourcePath, under: workURL) else {
                return .failure(
                    phase: .setup,
                    detail: "Invalid project path: \(sourcePath)",
                    duration: started.duration(to: clock.now)
                )
            }
            try fileManager.createDirectory(
                at: sourceURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(source.utf8).write(to: sourceURL, options: .atomic)
            for (relativePath, contents) in supportingFiles {
                guard relativePath != sourcePath,
                      let fileURL = projectFileURL(relativePath: relativePath, under: workURL)
                else {
                    return .failure(
                        phase: .setup,
                        detail: "Invalid project path: \(relativePath)",
                        duration: started.duration(to: clock.now)
                    )
                }
                try fileManager.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try Data(contents.utf8).write(to: fileURL, options: .atomic)
            }
        } catch {
            return .failure(
                phase: .setup,
                detail: "Could not create the compiler sandbox: \(error.localizedDescription)",
                duration: started.duration(to: clock.now)
            )
        }
        defer { try? fileManager.removeItem(at: jobRoot) }

        do {
            let module = try loadRustcModule(from: rustcURL)
            let outputName = action == .run ? "program.wasm" : "main.rmeta"
            var arguments = [
                "rustc", "/work/\(sourcePath)",
                "--sysroot", "/sysroot",
                "--target", "wasm32-wasip1",
                "--edition", "2024",
                "--error-format=json",
                "--json=diagnostic-rendered-ansi",
            ]
            var environment: [String: String] = [:]

            switch action {
            case .check:
                arguments += ["--emit", "metadata", "-o", "/work/\(outputName)"]
            case .run:
                arguments += [
                    "-Zunstable-options", "-O", "-Cpanic=abort",
                    "-o", "/work/\(outputName)",
                ]
                environment["CLIF2WASM_OBJECT"] = "1"
            }

            let capture = try makeCapture(in: jobRoot, prefix: "compiler")
            let exitCode: UInt32
            do {
                exitCode = try runWASI(
                    module: module,
                    arguments: arguments,
                    environment: environment,
                    preopens: [
                        .init(guestPath: "/tmp", hostPath: tempURL.path),
                        .init(guestPath: "/sysroot", hostPath: sysrootURL.path),
                        .init(guestPath: "/work", hostPath: workURL.path),
                    ],
                    capture: capture
                )
            } catch {
                let output = try? finishCapture(capture)
                let stderr = output?.stderr ?? ""
                let diagnostics = RustDiagnosticParser.parse(stderr: stderr)
                if let diagnostic = diagnostics.first {
                    return CompilationResult(
                        succeeded: false,
                        phase: action == .check ? .check : .compile,
                        exitCode: nil,
                        diagnostics: diagnostics,
                        stdout: output?.stdout ?? "",
                        stderr: "",
                        duration: started.duration(to: clock.now),
                        detail: diagnostic.message
                    )
                }
                return .failure(
                    phase: action == .check ? .check : .compile,
                    detail: "Bundled rustc trapped: \(error)",
                    stderr: stderr,
                    duration: started.duration(to: clock.now)
                )
            }
            let compilerOutput = try finishCapture(capture)
            let diagnostics = RustDiagnosticParser.parse(stderr: compilerOutput.stderr)
            let hasErrors = diagnostics.contains(where: { $0.level == "error" })

            guard exitCode == 0, !hasErrors else {
                return CompilationResult(
                    succeeded: false,
                    phase: action == .check ? .check : .compile,
                    exitCode: exitCode,
                    diagnostics: diagnostics,
                    stdout: compilerOutput.stdout,
                    stderr: diagnostics.isEmpty ? compilerOutput.stderr : "",
                    duration: started.duration(to: clock.now),
                    detail: diagnostics.first?.message ?? "rustc exited with code \(exitCode)."
                )
            }

            guard action == .run else {
                return CompilationResult(
                    succeeded: true,
                    phase: .check,
                    exitCode: exitCode,
                    diagnostics: diagnostics,
                    stdout: compilerOutput.stdout,
                    stderr: compilerOutput.stderr,
                    duration: started.duration(to: clock.now),
                    detail: "Real bundled rustc accepted the program."
                )
            }

            let programURL = workURL.appendingPathComponent(outputName)
            guard fileManager.fileExists(atPath: programURL.path) else {
                return .failure(
                    phase: .compile,
                    detail: "rustc exited successfully but emitted no program.wasm.",
                    stderr: compilerOutput.stderr,
                    duration: started.duration(to: clock.now)
                )
            }

            let programModule = try parseWasm(bytes: [UInt8](Data(contentsOf: programURL)))
            let sandboxURL = jobRoot.appendingPathComponent("sandbox", isDirectory: true)
            try fileManager.createDirectory(at: sandboxURL, withIntermediateDirectories: true)
            let programCapture = try makeCapture(in: jobRoot, prefix: "program")
            let resourceLimiter = WasmSandboxResourceLimiter()
            let programExit: UInt32
            do {
                programExit = try runWASI(
                    module: programModule,
                    arguments: ["program"],
                    environment: [:],
                    preopens: [
                        .init(
                            guestPath: WasmSandboxPolicy.writableGuestDirectory,
                            hostPath: sandboxURL.path
                        )
                    ],
                    capture: programCapture,
                    resourceLimiter: resourceLimiter
                )
            } catch {
                let programOutput = try? finishCapture(programCapture)
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
                        stdout: programOutput?.stdout ?? "",
                        stderr: programOutput?.stderr ?? "",
                        duration: started.duration(to: clock.now),
                        detail: detail
                    )
                }
                throw error
            }
            let programOutput = try finishCapture(programCapture)

            return CompilationResult(
                succeeded: programExit == 0,
                phase: .run,
                exitCode: programExit,
                diagnostics: diagnostics,
                stdout: programOutput.stdout,
                stderr: programOutput.stderr,
                duration: started.duration(to: clock.now),
                detail: programExit == 0
                    ? "Compiled and executed locally inside the bounded WasmKit sandbox."
                    : "The program exited with code \(programExit)."
            )
        } catch {
            return .failure(
                phase: action == .check ? .check : .run,
                detail: "Native compiler runtime failed: \(error)",
                duration: started.duration(to: clock.now)
            )
        }
    }

    private func loadRustcModule(from url: URL) throws -> Module {
        if let cachedRustcModule { return cachedRustcModule }
        let module = try parseWasm(bytes: [UInt8](Data(contentsOf: url)))
        cachedRustcModule = module
        return module
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
            partial.appendingPathComponent(String(component))
        }
    }

    private func engine() -> Engine {
        if let cachedEngine { return cachedEngine }
        let configuration = EngineConfiguration(
            // WasmKit 0.3.1's direct-threaded interpreter crashes in optimized
            // iOS Simulator builds while executing the bundled rustc module.
            // Token threading is the supported fallback and remains stable in
            // both Debug and Release configurations.
            threadingModel: .token,
            compilationMode: .lazy,
            stackSize: 16 * 1024 * 1024,
            memoryBoundsChecking: .software
        )
        let engine = Engine(configuration: configuration)
        cachedEngine = engine
        return engine
    }

    private func runWASI(
        module: Module,
        arguments: [String],
        environment: [String: String],
        preopens: [WASIBridgeToHost.Preopen],
        capture: Capture,
        resourceLimiter: (any ResourceLimiter)? = nil
    ) throws -> UInt32 {
        let wasi = try WASIBridgeToHost(
            args: arguments,
            environment: environment,
            preopens: preopens,
            stdout: FileDescriptor(rawValue: capture.stdoutHandle.fileDescriptor),
            stderr: FileDescriptor(rawValue: capture.stderrHandle.fileDescriptor)
        )
        return try wasi.runAndClose { wasi in
            let store = Store(engine: engine())
            if let resourceLimiter {
                store.resourceLimiter = resourceLimiter
            }
            var imports = Imports()
            wasi.link(to: &imports, store: store)
            let instance = try module.instantiate(store: store, imports: imports)
            return try wasi.start(instance)
        }
    }

    private func makeCapture(in directory: URL, prefix: String) throws -> Capture {
        let stdoutURL = directory.appendingPathComponent("\(prefix)-stdout.log")
        let stderrURL = directory.appendingPathComponent("\(prefix)-stderr.log")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        return Capture(
            stdoutURL: stdoutURL,
            stderrURL: stderrURL,
            stdoutHandle: try FileHandle(forWritingTo: stdoutURL),
            stderrHandle: try FileHandle(forWritingTo: stderrURL)
        )
    }

    private func finishCapture(_ capture: Capture) throws -> (stdout: String, stderr: String) {
        try capture.stdoutHandle.close()
        try capture.stderrHandle.close()
        let stdout = String(decoding: try Data(contentsOf: capture.stdoutURL), as: UTF8.self)
        let stderr = String(decoding: try Data(contentsOf: capture.stderrURL), as: UTF8.self)
        return (stdout, stderr)
    }
}
