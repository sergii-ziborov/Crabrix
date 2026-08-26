import Foundation
import WasmKit

enum WasmSandboxPolicy {
    static let writableGuestDirectory = "/sandbox"
    static let userProgramMemoryLimitBytes = 64 * 1024 * 1024
    static let userProgramTableElementLimit = 4_096

    static var memoryLimitLabel: String {
        ByteCountFormatter.string(
            fromByteCount: Int64(userProgramMemoryLimitBytes),
            countStyle: .memory
        )
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
