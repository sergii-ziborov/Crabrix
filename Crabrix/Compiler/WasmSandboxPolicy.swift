import Foundation
import WasmKit

enum WasmSandboxPolicy {
    static let writableGuestDirectory = "/sandbox"
    static let userProgramMemoryLimitBytes = 64 * 1024 * 1024
    static let userProgramTableElementLimit = 4_096
    static let userProgramInstructionBudget: UInt64 = 1_000_000_000
    static let userProgramWallClockLimit: Duration = .seconds(30)
    static let userProgramOutputLimitBytes = 1 * 1024 * 1024
    static let userProgramWritableBytesLimit = 8 * 1024 * 1024
    static let userProgramFileCountLimit = 256

    static var memoryLimitLabel: String {
        ByteCountFormatter.string(
            fromByteCount: Int64(userProgramMemoryLimitBytes),
            countStyle: .memory
        )
    }
}

/// Fuel/deadline enforcement called directly by WasmKit's token dispatch loop.
/// It does not depend on the guest performing a host call.
final class WasmInstructionBudgetLimiter: InstructionLimiter, @unchecked Sendable {
    private let lock = NSLock()
    private var remainingInstructions: UInt64
    private let deadline: ContinuousClock.Instant
    private let interrupter: WasmInterrupter
    private let clock = ContinuousClock()

    init(
        interrupter: WasmInterrupter,
        instructionBudget: UInt64 = WasmSandboxPolicy.userProgramInstructionBudget,
        wallClockLimit: Duration = WasmSandboxPolicy.userProgramWallClockLimit
    ) {
        self.interrupter = interrupter
        self.remainingInstructions = instructionBudget
        self.deadline = ContinuousClock().now.advanced(by: wallClockLimit)
    }

    func consume(instructionCount: UInt64) throws {
        if let reason = interrupter.stopReason {
            throw WasmExecutionCancelled(reason: reason)
        }
        if clock.now >= deadline {
            interrupter.cancel(reason: .wallClock)
            throw WasmExecutionCancelled(reason: .wallClock)
        }

        let exhausted = lock.withLock {
            guard instructionCount <= remainingInstructions else { return true }
            remainingInstructions -= instructionCount
            return false
        }
        if exhausted {
            interrupter.cancel(reason: .instructionBudget)
            throw WasmExecutionCancelled(reason: .instructionBudget)
        }
    }
}

/// Watches filesystem-backed output and the writable preopen while a user
/// program runs. Violations use the same engine interruption path as Stop.
final class WasmSandboxQuotaMonitor: @unchecked Sendable {
    private let captureDirectory: URL
    private let capturePrefix: String
    private let writableDirectory: URL
    private let interrupter: WasmInterrupter
    private let queue = DispatchQueue(label: "com.sergiiziborov.Crabrix.wasm-quotas", qos: .utility)
    private var timer: DispatchSourceTimer?

    init(
        captureDirectory: URL,
        capturePrefix: String,
        writableDirectory: URL,
        interrupter: WasmInterrupter
    ) {
        self.captureDirectory = captureDirectory
        self.capturePrefix = capturePrefix
        self.writableDirectory = writableDirectory
        self.interrupter = interrupter
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(25), repeating: .milliseconds(25))
        timer.setEventHandler { [weak self] in _ = self?.checkNow() }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    @discardableResult
    func checkNow() -> WasmStopReason? {
        let stdoutURL = captureDirectory.appending(path: "\(capturePrefix)-stdout.log")
        let stderrURL = captureDirectory.appending(path: "\(capturePrefix)-stderr.log")
        let outputBytes = fileSize(stdoutURL) + fileSize(stderrURL)
        if outputBytes > UInt64(WasmSandboxPolicy.userProgramOutputLimitBytes) {
            interrupter.cancel(reason: .outputLimit)
            return .outputLimit
        }

        var fileCount = 0
        var writableBytes: UInt64 = 0
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        if let enumerator = FileManager.default.enumerator(
            at: writableDirectory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsPackageDescendants]
        ) {
            for case let url as URL in enumerator {
                guard let values = try? url.resourceValues(forKeys: keys),
                      values.isRegularFile == true
                else { continue }
                fileCount += 1
                writableBytes += UInt64(max(0, values.fileSize ?? 0))
                if fileCount > WasmSandboxPolicy.userProgramFileCountLimit {
                    interrupter.cancel(reason: .fileCountLimit)
                    return .fileCountLimit
                }
                if writableBytes > UInt64(WasmSandboxPolicy.userProgramWritableBytesLimit) {
                    interrupter.cancel(reason: .writableBytesLimit)
                    return .writableBytesLimit
                }
            }
        }
        return nil
    }

    private func fileSize(_ url: URL) -> UInt64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
    }
}

final class WasmSandboxResourceLimiter: ResourceLimiter, @unchecked Sendable {
    enum DeniedResource: Equatable {
        case memory
        case table
    }

    private let lock = NSLock()
    private var storedDeniedResource: DeniedResource?

    var deniedResource: DeniedResource? {
        lock.withLock { storedDeniedResource }
    }

    func limitMemoryGrowth(to desired: Int) throws -> Bool {
        let allowed = desired <= WasmSandboxPolicy.userProgramMemoryLimitBytes
        if !allowed {
            lock.withLock { storedDeniedResource = .memory }
        }
        return allowed
    }

    func limitTableGrowth(to desired: Int) throws -> Bool {
        let allowed = desired <= WasmSandboxPolicy.userProgramTableElementLimit
        if !allowed {
            lock.withLock { storedDeniedResource = .table }
        }
        return allowed
    }
}
