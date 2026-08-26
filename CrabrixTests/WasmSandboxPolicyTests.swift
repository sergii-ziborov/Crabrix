import XCTest
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
}
