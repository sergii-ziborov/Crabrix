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

/// The compiler is a separate, larger guest workload. These limits remain
/// subject to device and Cargo gate measurements before a release.
enum CompilerHostPolicy {
    static let memoryLimitBytes = 2 * 1024 * 1024 * 1024
    static let tableElementLimit = 65_536
    // clap_builder 4.5.50 reaches codegen after its smaller dependencies have
    // built, but 100 billion fuel stops that single compiler invocation. Keep
    // the host budget separate from the one-billion-fuel user Run policy.
    static let fuelBudget: UInt64 = 300_000_000_000
    static let wallClockLimit: Duration = .seconds(20 * 60)
    static let outputLimitBytes = 16 * 1024 * 1024
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
    private let memoryLimitBytes: Int
    private let tableElementLimit: Int

    init(memoryLimitBytes: Int = WasmSandboxPolicy.userProgramMemoryLimitBytes,
         tableElementLimit: Int = WasmSandboxPolicy.userProgramTableElementLimit) {
        self.memoryLimitBytes = memoryLimitBytes
        self.tableElementLimit = tableElementLimit
    }

    var deniedResource: DeniedResource? {
        lock.withLock { storedDeniedResource }
    }

    func limitMemoryGrowth(to desired: Int) throws -> Bool {
        let allowed = desired <= memoryLimitBytes
        if !allowed {
            lock.withLock { storedDeniedResource = .memory }
        }
        return allowed
    }

    func limitTableGrowth(to desired: Int) throws -> Bool {
        let allowed = desired <= tableElementLimit
        if !allowed {
            lock.withLock { storedDeniedResource = .table }
        }
        return allowed
    }
}
