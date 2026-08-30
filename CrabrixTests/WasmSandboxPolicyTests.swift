import XCTest
@_spi(Fuzzing) import WasmKit
@testable import Crabrix

final class WasmSandboxPolicyTests: XCTestCase {
    func testMemoryAndTableGrowthAreBounded() throws {
        let limiter = WasmSandboxResourceLimiter()

        XCTAssertTrue(try limiter.limitMemoryGrowth(to: 32 * 1024 * 1024))
        XCTAssertTrue(try limiter.limitMemoryGrowth(to: WasmSandboxPolicy.userProgramMemoryLimitBytes))
        XCTAssertFalse(try limiter.limitMemoryGrowth(to: WasmSandboxPolicy.userProgramMemoryLimitBytes + 1))
        XCTAssertEqual(limiter.deniedResource, .memory)

        let tableLimiter = WasmSandboxResourceLimiter()
        XCTAssertTrue(try tableLimiter.limitTableGrowth(to: 1_024))
        XCTAssertFalse(try tableLimiter.limitTableGrowth(to: WasmSandboxPolicy.userProgramTableElementLimit + 1))
        XCTAssertEqual(tableLimiter.deniedResource, .table)
    }

    func testInstructionBudgetStopsPureComputeGuestWithoutHostCalls() throws {
        // (module (func (export "_start") (loop (br 0))))
        let module = try parseWasm(bytes: Self.infiniteLoopModule)
        let runtime = RustcRuntime()
        let interrupter = WasmInterrupter()
        let limiter = WasmInstructionBudgetLimiter(
            interrupter: interrupter,
            instructionBudget: 8_192,
            wallClockLimit: .seconds(5)
        )
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "CrabrixPureLoopTest-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertThrowsError(
            try runtime.run(
                module: module,
                arguments: ["program"],
                environment: [:],
                preopens: [],
                captureDirectory: directory,
                capturePrefix: "pure-loop",
                instructionLimiter: limiter,
                interrupter: interrupter
            )
        ) { error in
            XCTAssertEqual((error as? WasmExecutionCancelled)?.reason, .instructionBudget)
        }
        XCTAssertEqual(interrupter.stopReason, .instructionBudget)
    }

    func testUserStopInterruptsPureComputeGuestAndNextRunStarts() async throws {
        let runtime = RustcRuntime()
        let module = try parseWasm(bytes: Self.infiniteLoopModule)
        let interrupter = WasmInterrupter()
        let limiter = WasmInstructionBudgetLimiter(
            interrupter: interrupter,
            instructionBudget: .max,
            wallClockLimit: .seconds(5)
        )
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "CrabrixUserStopTest-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let running = Task.detached {
            Result {
                try runtime.run(
                    module: module,
                    arguments: ["program"],
                    environment: [:],
                    preopens: [],
                    captureDirectory: directory,
                    capturePrefix: "stopped",
                    instructionLimiter: limiter,
                    interrupter: interrupter
                )
            }
        }
        try await Task.sleep(for: .milliseconds(20))
        let stopStarted = ContinuousClock().now
        interrupter.cancel()
        let stopped = await running.value
        let stopDuration = stopStarted.duration(to: ContinuousClock().now)

        switch stopped {
        case .success:
            XCTFail("The pure-compute guest returned instead of being stopped.")
        case let .failure(error):
            XCTAssertEqual((error as? WasmExecutionCancelled)?.reason, .userRequested)
        }
        XCTAssertLessThan(stopDuration, .seconds(1))

        let finiteModule = try parseWasm(bytes: Self.emptyStartModule)
        let next = try runtime.run(
            module: finiteModule,
            arguments: ["program"],
            environment: [:],
            preopens: [],
            captureDirectory: directory,
            capturePrefix: "next-run"
        )
        XCTAssertEqual(next.exitCode, 0)
    }

    func testOutputQuotaCancelsGuest() throws {
        let root = try makeQuotaDirectories()
        defer { try? FileManager.default.removeItem(at: root.capture) }
        let output = root.capture.appending(path: "program-stdout.log")
        try Data(count: WasmSandboxPolicy.userProgramOutputLimitBytes + 1).write(to: output)
        let interrupter = WasmInterrupter()
        let monitor = WasmSandboxQuotaMonitor(
            captureDirectory: root.capture,
            capturePrefix: "program",
            writableDirectory: root.writable,
            interrupter: interrupter
        )

        XCTAssertEqual(monitor.checkNow(), .outputLimit)
        XCTAssertEqual(interrupter.stopReason, .outputLimit)
    }

    func testWritableByteAndFileCountQuotasCancelGuest() throws {
        let byteRoot = try makeQuotaDirectories()
        defer { try? FileManager.default.removeItem(at: byteRoot.capture) }
        try Data(count: WasmSandboxPolicy.userProgramWritableBytesLimit + 1)
            .write(to: byteRoot.writable.appending(path: "large.bin"))
        let byteInterrupter = WasmInterrupter()
        let byteMonitor = WasmSandboxQuotaMonitor(
            captureDirectory: byteRoot.capture,
            capturePrefix: "program",
            writableDirectory: byteRoot.writable,
            interrupter: byteInterrupter
        )
        XCTAssertEqual(byteMonitor.checkNow(), .writableBytesLimit)

        let countRoot = try makeQuotaDirectories()
        defer { try? FileManager.default.removeItem(at: countRoot.capture) }
        for index in 0...WasmSandboxPolicy.userProgramFileCountLimit {
            _ = FileManager.default.createFile(
                atPath: countRoot.writable.appending(path: "\(index).txt").path,
                contents: Data()
            )
        }
        let countInterrupter = WasmInterrupter()
        let countMonitor = WasmSandboxQuotaMonitor(
            captureDirectory: countRoot.capture,
            capturePrefix: "program",
            writableDirectory: countRoot.writable,
            interrupter: countInterrupter
        )
        XCTAssertEqual(countMonitor.checkNow(), .fileCountLimit)
    }

    private func makeQuotaDirectories() throws -> (capture: URL, writable: URL) {
        let capture = FileManager.default.temporaryDirectory
            .appending(path: "CrabrixQuotaTest-\(UUID().uuidString)", directoryHint: .isDirectory)
        let writable = capture.appending(path: "sandbox", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: writable, withIntermediateDirectories: true)
        return (capture, writable)
    }

    private static let infiniteLoopModule: [UInt8] = [
        0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00,
        0x01, 0x04, 0x01, 0x60, 0x00, 0x00,
        0x03, 0x02, 0x01, 0x00,
        0x07, 0x0A, 0x01, 0x06, 0x5F, 0x73, 0x74, 0x61, 0x72, 0x74, 0x00, 0x00,
        0x0A, 0x09, 0x01, 0x07, 0x00, 0x03, 0x40, 0x0C, 0x00, 0x0B, 0x0B,
    ]

    private static let emptyStartModule: [UInt8] = [
        0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00,
        0x01, 0x04, 0x01, 0x60, 0x00, 0x00,
        0x03, 0x02, 0x01, 0x00,
        0x07, 0x0A, 0x01, 0x06, 0x5F, 0x73, 0x74, 0x61, 0x72, 0x74, 0x00, 0x00,
        0x0A, 0x04, 0x01, 0x02, 0x00, 0x0B,
    ]
}
