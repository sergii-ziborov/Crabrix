import Foundation
import SystemPackage
@_spi(Fuzzing) import WasmKit
import WasmKitWASI

/// The bundled WASI toolchain on disk.
struct BundledToolchain: Sendable {
    let rustcURL: URL
    let sysrootURL: URL
    let version: String

    static func locate(
        in bundle: Bundle,
        version: String
    ) -> BundledToolchain? {
        guard let root = bundle.resourceURL?
            .appending(path: "Toolchain", directoryHint: .isDirectory)
            .appending(path: version, directoryHint: .isDirectory)
        else {
            return nil
        }
        let rustc = root.appending(path: "rustc.wasm")
        let sysroot = root.appending(path: "sysroot-wasip1", directoryHint: .isDirectory)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rustc.path),
              FileManager.default.fileExists(atPath: sysroot.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return nil
        }
        return BundledToolchain(rustcURL: rustc, sysrootURL: sysroot, version: version)
    }
}

/// The result of one guest process.
struct WasmProcessResult: Sendable {
    let exitCode: UInt32
    let stdout: String
    let stderr: String
}

enum WasmStopReason: Sendable, Equatable {
    case userRequested
    case instructionBudget
    case wallClock
    case outputLimit
    case fileCountLimit
    case writableBytesLimit
}

/// Raised when a guest is stopped by the user or by a sandbox quota rather
/// than failing on its own. Captured output is retained for an honest result.
struct WasmExecutionCancelled: Error, Sendable {
    let reason: WasmStopReason
    let stdout: String
    let stderr: String

    init(
        reason: WasmStopReason,
        stdout: String = "",
        stderr: String = ""
    ) {
        self.reason = reason
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// Owns the WasmKit engine and the parsed modules that every rustc invocation
/// shares.
///
/// Parsing `rustc.wasm` is expensive enough that re-parsing it per dependency
/// would dominate a multi-crate build, so the module is cached for the lifetime
/// of the host.
final class RustcRuntime: @unchecked Sendable {
    private var cachedEngine: Engine?
    private var cachedRustcModule: Module?
    private var cachedProgramModules: [String: Module] = [:]

    func engine() -> Engine {
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

    func rustcModule(at url: URL) throws -> Module {
        if let cachedRustcModule { return cachedRustcModule }
        let module = try parseWasm(bytes: [UInt8](Data(contentsOf: url)))
        cachedRustcModule = module
        return module
    }

    func programModule(for key: String) -> Module? { cachedProgramModules[key] }

    func cacheProgramModule(_ module: Module, for key: String) {
        cachedProgramModules[key] = module
    }

    func clearProgramModules() {
        cachedProgramModules.removeAll(keepingCapacity: false)
    }

    /// Runs a WASI module to completion, capturing stdout and stderr.
    func run(
        module: Module,
        arguments: [String],
        environment: [String: String],
        preopens: [WASIBridgeToHost.Preopen],
        captureDirectory: URL,
        capturePrefix: String,
        resourceLimiter: (any ResourceLimiter)? = nil,
        instructionLimiter: (any InstructionLimiter)? = nil,
        interrupter: WasmInterrupter? = nil,
        capturedOutputLimitBytes: Int? = nil
    ) throws -> WasmProcessResult {
        let capture = try Capture(directory: captureDirectory, prefix: capturePrefix)
        var exitCode: UInt32 = 0
        var thrown: (any Error)?
        do {
            let wasi = try WASIBridgeToHost(
                args: arguments,
                environment: environment,
                preopens: preopens,
                stdout: FileDescriptor(rawValue: capture.stdoutHandle.fileDescriptor),
                stderr: FileDescriptor(rawValue: capture.stderrHandle.fileDescriptor)
            )
            exitCode = try wasi.runAndClose { wasi in
                let store = Store(engine: engine())
                if let resourceLimiter { store.resourceLimiter = resourceLimiter }
                store.instructionLimiter = instructionLimiter
                var imports = Imports()
                wasi.link(to: &imports, store: store)
                interrupter?.wrapHostFunctions(of: wasi, into: &imports, store: store)
                let instance = try module.instantiate(store: store, imports: imports)
                return try wasi.start(instance)
            }
        } catch {
            thrown = error
        }
        let output = try capture.finish(maxBytesPerStream: capturedOutputLimitBytes)
        if let thrown {
            if let reason = interrupter?.stopReason {
                throw WasmExecutionCancelled(
                    reason: reason,
                    stdout: output.stdout,
                    stderr: output.stderr
                )
            }
            throw RustcRuntimeFailure(underlying: thrown, stdout: output.stdout, stderr: output.stderr)
        }
        return WasmProcessResult(exitCode: exitCode, stdout: output.stdout, stderr: output.stderr)
    }

    private struct Capture {
        let stdoutURL: URL
        let stderrURL: URL
        let stdoutHandle: FileHandle
        let stderrHandle: FileHandle

        init(directory: URL, prefix: String) throws {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            stdoutURL = directory.appending(path: "\(prefix)-stdout.log")
            stderrURL = directory.appending(path: "\(prefix)-stderr.log")
            FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
            FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
            stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
            stderrHandle = try FileHandle(forWritingTo: stderrURL)
        }

        func finish(maxBytesPerStream: Int?) throws -> (stdout: String, stderr: String) {
            try? stdoutHandle.close()
            try? stderrHandle.close()
            let stdout = String(
                decoding: Self.read(url: stdoutURL, limit: maxBytesPerStream),
                as: UTF8.self
            )
            let stderr = String(
                decoding: Self.read(url: stderrURL, limit: maxBytesPerStream),
                as: UTF8.self
            )
            return (stdout, stderr)
        }

        private static func read(url: URL, limit: Int?) -> Data {
            guard let limit else { return (try? Data(contentsOf: url)) ?? Data() }
            guard let handle = try? FileHandle(forReadingFrom: url) else { return Data() }
            defer { try? handle.close() }
            return (try? handle.read(upToCount: max(0, limit))) ?? Data()
        }
    }
}

/// A guest trap plus whatever the process managed to print first.
struct RustcRuntimeFailure: Error, @unchecked Sendable {
    let underlying: any Error
    let stdout: String
    let stderr: String
}

/// Stops a running guest. Host calls are guarded here; pure-compute code is
/// guarded by `WasmInstructionBudgetLimiter` through the vendored WasmKit
/// instruction-boundary hook.
final class WasmInterrupter: @unchecked Sendable {
    private let state = AtomicStopState()

    var wasCancelled: Bool { state.reason != nil }
    var stopReason: WasmStopReason? { state.reason }

    func cancel(reason: WasmStopReason = .userRequested) {
        state.cancel(reason: reason)
    }

    /// Re-defines each WASI import as a guard that checks cancellation first.
    func wrapHostFunctions(of wasi: WASIBridgeToHost, into imports: inout Imports, store: Store) {
        let state = state
        wasi.link(to: &imports, store: store) {
            if let reason = state.reason {
                throw WasmExecutionCancelled(reason: reason)
            }
        }
    }
}

/// A lock-backed first-writer-wins stop state. The compiler queue, limiter,
/// quota monitor, and UI thread may all touch it concurrently.
final class AtomicStopState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedReason: WasmStopReason?

    var reason: WasmStopReason? {
        lock.lock()
        defer { lock.unlock() }
        return storedReason
    }

    func cancel(reason: WasmStopReason) {
        lock.lock()
        if storedReason == nil { storedReason = reason }
        lock.unlock()
    }
}
