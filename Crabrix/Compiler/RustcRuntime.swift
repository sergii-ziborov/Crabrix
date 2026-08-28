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

/// Raised when a guest is stopped on purpose rather than failing on its own.
struct WasmExecutionCancelled: Error, Sendable {}

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

    /// Runs a WASI module to completion, capturing stdout and stderr.
    func run(
        module: Module,
        arguments: [String],
        environment: [String: String],
        preopens: [WASIBridgeToHost.Preopen],
        captureDirectory: URL,
        capturePrefix: String,
        resourceLimiter: (any ResourceLimiter)? = nil,
        interrupter: WasmInterrupter? = nil
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
                var imports = Imports()
                wasi.link(to: &imports, store: store)
                interrupter?.wrapHostFunctions(of: wasi, into: &imports, store: store)
                let instance = try module.instantiate(store: store, imports: imports)
                return try wasi.start(instance)
            }
        } catch {
            thrown = error
        }
        let output = try capture.finish()
        if let thrown {
            if interrupter?.wasCancelled == true { throw WasmExecutionCancelled() }
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

        func finish() throws -> (stdout: String, stderr: String) {
            try? stdoutHandle.close()
            try? stderrHandle.close()
            let stdout = String(decoding: (try? Data(contentsOf: stdoutURL)) ?? Data(), as: UTF8.self)
            let stderr = String(decoding: (try? Data(contentsOf: stderrURL)) ?? Data(), as: UTF8.self)
            return (stdout, stderr)
        }
    }
}

/// A guest trap plus whatever the process managed to print first.
struct RustcRuntimeFailure: Error, @unchecked Sendable {
    let underlying: any Error
    let stdout: String
    let stderr: String
}

/// Stops a running guest.
///
/// WasmKit 0.3.1 exposes no engine-level interruption, so Crabrix wraps every
/// WASI host function the guest imports. A cancelled build traps the moment the
/// guest makes its next syscall, which for `rustc` is continuous file I/O and
/// for a user program is any print or file access. The one case this cannot
/// reach is a guest that spins without ever calling into the host; that is
/// tracked as a known limitation rather than papered over with a fake timeout.
final class WasmInterrupter: @unchecked Sendable {
    private let flag = AtomicFlag()

    var wasCancelled: Bool { flag.isSet }

    func cancel() { flag.set() }

    /// Re-defines each WASI import as a guard that checks cancellation first.
    func wrapHostFunctions(of wasi: WASIBridgeToHost, into imports: inout Imports, store: Store) {
        let flag = flag
        // `hostModules` is WasmKit's deprecated bridge, but it is the only public
        // way to reach the WASI implementations and re-export them wrapped.
        for (moduleName, module) in Self.hostModules(of: wasi) {
            for (name, function) in module.functions {
                let implementation = function.implementation
                imports.define(
                    module: moduleName,
                    name: name,
                    Function(store: store, type: function.type) { caller, values in
                        if flag.isSet { throw WasmExecutionCancelled() }
                        return try implementation(caller, values)
                    }
                )
            }
        }
    }

    @available(*, deprecated)
    private static func hostModules(of wasi: WASIBridgeToHost) -> [String: HostModule] {
        wasi.hostModules
    }
}

/// A lock-backed flag; the compiler queue and the UI thread both touch it.
final class AtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }
}
