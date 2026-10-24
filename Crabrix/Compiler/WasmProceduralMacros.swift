import Foundation
@_spi(Fuzzing) import WasmKit
import WasmKitWASI

/// One rustc invocation's declared, network-free macro inputs. This session
/// exists only for a toolchain explicitly advertising the RPC v1 capability.
final class WasmProceduralMacroSession {
    private let engine: Engine
    private let allowedInputs: Set<String>
    private let environment: [String: String]
    private let preopens: [WASIBridgeToHost.Preopen]
    private let stdout: Int32
    private let stderr: Int32
    private let outputBudget: WASIOutputBudget?
    private let interrupter: WasmInterrupter?
    private var modules: [String: Module] = [:]

    lazy var transport = ProcMacroTransport(engine: engine) { [weak self] path, _, store, imports in
        guard let self else { throw ProcMacroTransport.Failure.unavailable }
        return try self.load(path, store: store, imports: &imports)
    }

    init(engine: Engine, arguments: [String], inputs: [String], environment: [String: String],
         preopens: [WASIBridgeToHost.Preopen], stdout: Int32, stderr: Int32,
         outputBudget: WASIOutputBudget?, interrupter: WasmInterrupter?) {
        self.engine = engine
        var declared = Set(inputs)
        for index in arguments.indices where arguments[index] == "--extern" && index + 1 < arguments.count {
            if let path = arguments[index + 1].split(separator: "=", maxSplits: 1).last,
               path.hasSuffix(".wasm") { declared.insert(String(path)) }
        }
        self.allowedInputs = declared
        self.environment = environment
        self.preopens = preopens
        self.stdout = stdout
        self.stderr = stderr
        self.outputBudget = outputBudget
        self.interrupter = interrupter
    }

    func close() {
        transport.close()
        modules.removeAll()
    }

    /// Resolve only an exact declared artifact through a granted preopen. A
    /// symlink escaping that grant must fail before opening or parsing a file.
    static func artifactURL(_ path: String, allowed: Set<String>,
                            preopens: [WASIBridgeToHost.Preopen]) throws -> URL {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard allowed.contains(path), path.hasSuffix(".wasm"), path.hasPrefix("/"),
              !path.utf8.contains(0), components.dropFirst().allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else { throw ProcMacroTransport.Failure.invalidRequest }
        for preopen in preopens.sorted(by: { $0.guestPath.count > $1.guestPath.count }) {
            let prefix = preopen.guestPath.hasSuffix("/") ? preopen.guestPath : preopen.guestPath + "/"
            guard path.hasPrefix(prefix) else { continue }
            let root = URL(fileURLWithPath: preopen.hostPath, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
            let file = root.appending(path: String(path.dropFirst(prefix.count))).resolvingSymlinksInPath().standardizedFileURL
            guard file.path.hasPrefix(root.path + "/") else { throw ProcMacroTransport.Failure.invalidRequest }
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, let size = values.fileSize,
                  size >= 8, size <= 32 * 1024 * 1024 else { throw ProcMacroTransport.Failure.messageTooLarge }
            return file
        }
        throw ProcMacroTransport.Failure.invalidRequest
    }

    private func load(_ path: String, store: Store, imports: inout Imports) throws -> ProcMacroTransport.LoadedModule {
        let url = try Self.artifactURL(path, allowed: allowedInputs, preopens: preopens)
        let module: Module
        if let cached = modules[path] { module = cached }
        else {
            module = try parseWasm(filePath: url.path)
            modules[path] = module
        }
        // Macros can inspect the same source inputs as rustc, but cannot modify
        // the artifact cache, source tree or build outputs behind its back.
        let readOnly = preopens.map {
            WASIBridgeToHost.Preopen(guestPath: $0.guestPath, hostPath: $0.hostPath, readOnly: true)
        }
        let wasi: WASIBridgeToHost
        if let outputBudget {
            wasi = try WASIBridgeToHost(args: [path], environment: environment, preopens: readOnly,
                                       stdout: stdout, stderr: stderr, outputBudget: outputBudget)
        } else {
            wasi = try WASIBridgeToHost(args: [path], environment: environment, preopens: readOnly,
                                       stdout: stdout, stderr: stderr)
        }
        var handedOff = false
        defer { if !handedOff { try? wasi.close() } }
        if let interrupter { interrupter.wrapHostFunctions(of: wasi, into: &imports, store: store) }
        else { wasi.link(to: &imports, store: store, capabilities: [.environment, .clocks, .random, .process, .stdio, .fileSystem, .poll]) }
        let instance = try module.instantiate(store: store, imports: imports)
        if let constructors = instance.exports[function: "__wasm_call_ctors"] { try constructors() }
        handedOff = true
        return .init(instance: instance, close: { try? wasi.close() })
    }
}
