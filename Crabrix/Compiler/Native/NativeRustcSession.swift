#if CRABRIX_NATIVE_COMPILER
import Foundation
import WASI
@_spi(Fuzzing) import WasmKit

/// Only the app's statically linked compiler uses this path. Editable programs,
/// build scripts and downloaded macro crates always execute as WasmKit guests.
final class NativeRustcSession {
    enum Failure: Error { case unavailable, invalidABI, trap(Int32), busy }

    private struct Memory: GuestMemory {
        let handle: OpaquePointer
        var guestMemoryByteCount: Int? { Int(crabrix_native_compiler_memory_size(handle)) }
        func withUnsafeMutableBufferPointer<T>(offset: UInt, count: Int,
            _ body: (UnsafeMutableRawBufferPointer) throws -> T) rethrows -> T {
            // WASI validates every guest range before requesting an unsafe view.
            let size = crabrix_native_compiler_memory_size(handle)
            precondition(count >= 0 && offset <= size && UInt64(count) <= size - UInt64(offset))
            let base = crabrix_native_compiler_memory(handle).map { $0.advanced(by: Int(offset)) }
            return try body(UnsafeMutableRawBufferPointer(start: base, count: count))
        }
    }

    static var compilerSHA256: String { String(cString: crabrix_native_compiler_source_sha256()) }
    private var handle: OpaquePointer!
    private var functions: [String: WASIHostFunction<Memory>] = [:]
    private var failure: (any Error)?
    private var exitCode: UInt32?
    private let interrupter: WasmInterrupter
    private let proxyStore: Store
    private var proxy: Instance?
    private let macros: WasmProceduralMacroSession?
    private static let maximumMessageBytes = 16 * 1024 * 1024

    init(wasi: WASI.WASIBridgeToHost, engine: Engine, macros: WasmProceduralMacroSession?,
         interrupter: WasmInterrupter, budget: UInt64) throws {
        self.interrupter = interrupter
        self.macros = macros
        proxyStore = Store(engine: engine)
        proxyStore.fuel = Fuel(remaining: budget)
        proxyStore.cancellationProbe = interrupter
        functions = wasi.hostFunctions(capabilities: [.environment, .clocks, .random, .process, .stdio, .fileSystem,
            .interruptiblePoll {
                if let reason = interrupter.stopReason { throw WasmExecutionCancelled(reason: reason) }
            }])
        handle = crabrix_native_compiler_create(Unmanaged.passUnretained(self).toOpaque(), Self.host, Self.poll)
        guard handle != nil else { throw Failure.unavailable }
        do {
            var imports = Imports()
            if let macros { macros.transport.link(to: &imports, store: proxyStore) }
            else { ProcMacroTransport.linkUnavailable(to: &imports, store: proxyStore) }
            imports.define(module: "crabrix_native_proxy", name: "dispatch",
                Function(store: proxyStore, parameters: [.i32, .i32], results: [.i64]) { [weak self] caller, values in
                    guard let self, let instance = caller.instance else { throw Failure.unavailable }
                    return [.i64(try self.dispatch(instance: instance, pointer: values[0].i32, count: values[1].i32))]
                })
            proxy = try parseWasm(bytes: ProcMacroNativeProxy.bytes).instantiate(store: proxyStore, imports: imports)
        } catch {
            crabrix_native_compiler_free(handle); handle = nil
            throw error
        }
    }

    deinit { if let handle { crabrix_native_compiler_free(handle) } }

    func run(budget: UInt64) throws -> UInt32 {
        if let reason = interrupter.stopReason { throw WasmExecutionCancelled(reason: reason) }
        let trap = crabrix_native_compiler_run(handle, budget)
        if let failure { throw failure }
        if let reason = interrupter.stopReason { throw WasmExecutionCancelled(reason: reason) }
        if let exitCode { return exitCode }
        if crabrix_native_compiler_remaining_work(handle) == 0 {
            interrupter.cancel(reason: .instructionBudget)
            throw WasmExecutionCancelled(reason: .instructionBudget)
        }
        if trap == -1 { throw Failure.busy }
        guard trap == 0 else { throw Failure.trap(trap) }
        return 0
    }

    private static let poll: CrabrixNativePoll = { opaque in
        guard let opaque else { return 1 }
        return Unmanaged<NativeRustcSession>.fromOpaque(opaque).takeUnretainedValue().interrupter.isCancelled ? 1 : 0
    }

    private static let host: CrabrixNativeHostCall = { opaque, module, name, input, count, result in
        guard let opaque, let module, let name, let result, count == 0 || input != nil else { return 1 }
        let session = Unmanaged<NativeRustcSession>.fromOpaque(opaque).takeUnretainedValue()
        do {
            if let reason = session.interrupter.stopReason { throw WasmExecutionCancelled(reason: reason) }
            let values = count == 0 ? [] : Array(UnsafeBufferPointer(start: input!, count: Int(count)))
            result.pointee = try session.call(module: String(cString: module), name: String(cString: name), arguments: values)
            return 0
        } catch let exit as WASIExitCode { session.exitCode = exit.code; return 1 }
        catch { session.failure = error; return 1 }
    }

    private func call(module: String, name: String, arguments: [UInt64]) throws -> UInt64 {
        if module == "crabrix_proc_macro_v1" { return try rpc(name: name, arguments: arguments) }
        guard module == "wasi_snapshot_preview1", let function = functions[name],
              function.type.parameters.count == arguments.count else { throw Failure.invalidABI }
        let values: [Value] = try zip(function.type.parameters, arguments).map { type, value in
            switch type {
            case .i32: return .i32(UInt32(truncatingIfNeeded: value))
            case .i64: return .i64(value)
            default: throw Failure.invalidABI
            }
        }
        let output = try function.implementation(Memory(handle: handle), values)
        guard output.count <= 1 else { throw Failure.invalidABI }
        guard let value = output.first else { return 0 }
        switch value {
        case .i32(let value): return UInt64(value)
        case .i64(let value): return value
        default: throw Failure.invalidABI
        }
    }

    private func syncToProxy() {
        proxyStore.fuel = Fuel(remaining: min(proxyStore.fuel?.remaining ?? .max,
            crabrix_native_compiler_remaining_work(handle)))
    }

    private func syncFromProxy() throws {
        let remaining = min(proxyStore.fuel?.remaining ?? .max, crabrix_native_compiler_remaining_work(handle))
        guard crabrix_native_compiler_reduce_work(handle, remaining) == 0 else { throw Failure.invalidABI }
    }

    private func rpc(name: String, arguments: [UInt64]) throws -> UInt64 {
        guard let proxy else { throw Failure.unavailable }
        syncToProxy()
        defer { try? syncFromProxy() }
        if name == "exchange", arguments.count == 6 {
            let length = UInt32(truncatingIfNeeded: arguments[4])
            let bytes = try readNative(pointer: UInt32(truncatingIfNeeded: arguments[3]), count: length)
            let pointer = try putProxy(bytes, instance: proxy)
            var values = arguments.map { Value.i32(UInt32(truncatingIfNeeded: $0)) }
            values[3] = .i32(pointer)
            return UInt64(try invoke(proxy, name, values)[0].i32)
        }
        if name == "read_reply", arguments.count == 2 {
            let length = UInt32(truncatingIfNeeded: arguments[1])
            try checkNativeRange(pointer: UInt32(truncatingIfNeeded: arguments[0]), count: length)
            let pointer = try allocateProxy(length, instance: proxy)
            let result = try invoke(proxy, name, [.i32(pointer), .i32(length)])[0].i32
            guard result == length else { throw Failure.invalidABI }
            let bytes = try readProxy(proxy, pointer: pointer, count: length)
            try writeNative(bytes, pointer: UInt32(truncatingIfNeeded: arguments[0]))
            return UInt64(result)
        }
        throw Failure.invalidABI
    }

    private func dispatch(instance: Instance, pointer: UInt32, count: UInt32) throws -> UInt64 {
        try syncFromProxy()
        defer { syncToProxy() }
        let bytes = try readProxy(instance, pointer: pointer, count: count)
        let nativePointer = UInt32(truncatingIfNeeded: try exported(1, count, 0))
        try writeNative(bytes, pointer: nativePointer)
        let packed = try exported(3, nativePointer, count)
        let replyPointer = UInt32(truncatingIfNeeded: packed), length = UInt32(packed >> 32)
        let reply = try readNative(pointer: replyPointer, count: length)
        _ = try exported(2, replyPointer, length)
        let destination = try putProxy(reply, instance: instance)
        return UInt64(destination) | UInt64(length) << 32
    }

    private func exported(_ kind: UInt32, _ first: UInt32, _ second: UInt32) throws -> UInt64 {
        var result: UInt64 = 0
        let trap = crabrix_native_compiler_export(handle, kind, first, second, &result)
        guard trap == 0 else { throw failure ?? Failure.trap(trap) }
        return result
    }

    private func checkNativeRange(pointer: UInt32, count: UInt32) throws {
        let size = crabrix_native_compiler_memory_size(handle)
        guard count <= Self.maximumMessageBytes, UInt64(pointer) <= size,
              UInt64(count) <= size - UInt64(pointer) else { throw Failure.invalidABI }
    }

    private func readNative(pointer: UInt32, count: UInt32) throws -> [UInt8] {
        try checkNativeRange(pointer: pointer, count: count)
        guard count != 0 else { return [] }
        guard let memory = crabrix_native_compiler_memory(handle) else { throw Failure.invalidABI }
        return Array(UnsafeBufferPointer(start: memory.advanced(by: Int(pointer)), count: Int(count)))
    }

    private func writeNative(_ bytes: [UInt8], pointer: UInt32) throws {
        try checkNativeRange(pointer: pointer, count: UInt32(bytes.count))
        guard !bytes.isEmpty else { return }
        guard let memory = crabrix_native_compiler_memory(handle) else { throw Failure.invalidABI }
        bytes.withUnsafeBufferPointer { memory.advanced(by: Int(pointer)).update(from: $0.baseAddress!, count: bytes.count) }
    }

    private func invoke(_ instance: Instance, _ name: String, _ values: [Value]) throws -> [Value] {
        guard let function = instance.exports[function: name] else { throw Failure.invalidABI }
        return try function(values)
    }

    private func allocateProxy(_ count: UInt32, instance: Instance) throws -> UInt32 {
        guard count <= Self.maximumMessageBytes else { throw Failure.invalidABI }
        return try invoke(instance, "__crabrix_pm_alloc", [.i32(count)])[0].i32
    }

    private func putProxy(_ bytes: [UInt8], instance: Instance) throws -> UInt32 {
        let pointer = try allocateProxy(UInt32(bytes.count), instance: instance)
        guard let memory = instance.exports[memory: "memory"] else { throw Failure.invalidABI }
        memory.withUnsafeMutableBufferPointer(offset: UInt(pointer), count: bytes.count) { destination in
            bytes.withUnsafeBytes { destination.copyMemory(from: $0) }
        }
        return pointer
    }

    private func readProxy(_ instance: Instance, pointer: UInt32, count: UInt32) throws -> [UInt8] {
        guard count <= Self.maximumMessageBytes, let memory = instance.exports[memory: "memory"],
              let size = memory.guestMemoryByteCount, UInt64(pointer) <= size,
              UInt64(count) <= UInt64(size) - UInt64(pointer) else { throw Failure.invalidABI }
        return memory.withUnsafeMutableBufferPointer(offset: UInt(pointer), count: Int(count)) { Array($0) }
    }
}

#endif
