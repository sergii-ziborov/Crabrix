import Foundation

/// Owned by one caller's invocation, including both phases of Debug. A late
/// cancellation never follows the compiler's mutable "current guest" pointer.
final class CompilerInvocationCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var guest: WasmInterrupter?

    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }

    func cancel() {
        lock.lock(); cancelled = true; let current = guest; lock.unlock()
        current?.cancel()
    }

    func attach(_ value: WasmInterrupter) {
        lock.lock(); guest = value; let shouldCancel = cancelled; lock.unlock()
        if shouldCancel { value.cancel() }
    }

    func detach(_ value: WasmInterrupter) {
        lock.lock(); defer { lock.unlock() }
        if guest === value { guest = nil }
    }
}
