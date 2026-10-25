import Foundation

/// Native compiler frames need a larger stack than a dispatch worker supplies.
/// Its caller already runs off MainActor and waits until this owned thread exits.
enum NativeCompilerWorker {
    private final class Job: @unchecked Sendable {
        let body: () throws -> UInt32
        let finished = DispatchSemaphore(value: 0)
        var result: Result<UInt32, any Error>?
        init(body: @escaping () throws -> UInt32) { self.body = body }
        func run() {
            autoreleasepool { result = Result(catching: body) }
            finished.signal()
        }
    }

    static func perform(_ body: @escaping () throws -> UInt32) throws -> UInt32 {
        let job = Job(body: body)
        let thread = Thread { job.run() }
        thread.name = "Crabrix bundled compiler"
        thread.qualityOfService = .userInitiated
        thread.stackSize = 32 * 1024 * 1024
        thread.start()
        job.finished.wait()
        return try job.result!.get()
    }
}
