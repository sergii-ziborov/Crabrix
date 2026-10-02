import XCTest
@_spi(Fuzzing) import WasmKit
@testable import Crabrix

final class RustcRuntimeCacheTests: XCTestCase {
    func testProgramModuleCacheEvictsLeastRecentAndRejectsOversizedModule() throws {
        // An empty _start module is sufficient: this checks cache identity and
        // admission, not the guest's execution behavior.
        let module = try parseWasm(bytes: Self.emptyStartModule)
        let runtime = RustcRuntime(
            programModuleCacheEntryLimit: 2,
            programModuleCacheCostLimitBytes: 128 * 1024
        )

        runtime.cacheProgramModule(module, for: "a", wasmFileBytes: 64)
        runtime.cacheProgramModule(module, for: "b", wasmFileBytes: 64)
        XCTAssertNotNil(runtime.programModule(for: "a"))
        runtime.cacheProgramModule(module, for: "c", wasmFileBytes: 64)

        XCTAssertNil(runtime.programModule(for: "b"))
        XCTAssertNotNil(runtime.programModule(for: "a"))
        XCTAssertNotNil(runtime.programModule(for: "c"))

        runtime.cacheProgramModule(module, for: "oversized", wasmFileBytes: 32 * 1024 + 1)
        XCTAssertNil(runtime.programModule(for: "oversized"))
        XCTAssertNotNil(runtime.programModule(for: "a"))

        runtime.clearProgramModules()
        XCTAssertNil(runtime.programModule(for: "a"))
        XCTAssertNil(runtime.programModule(for: "c"))
    }

    private static let emptyStartModule: [UInt8] = [
        0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00,
        0x01, 0x04, 0x01, 0x60, 0x00, 0x00,
        0x03, 0x02, 0x01, 0x00,
        0x07, 0x0A, 0x01, 0x06, 0x5F, 0x73, 0x74, 0x61, 0x72, 0x74, 0x00, 0x00,
        0x0A, 0x04, 0x01, 0x02, 0x00, 0x0B,
    ]
}
