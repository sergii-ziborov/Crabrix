#if CRABRIX_NATIVE_COMPILER
import XCTest
@_spi(Fuzzing) import WasmKit
@testable import Crabrix

final class NativeCompilerProxyTests: XCTestCase {
    func testEveryProxyEntrySuppliesItsBoundedMemoryContext() throws {
        for model in [EngineConfiguration.ThreadingModel.token, .direct] {
            var configuration = EngineConfiguration(threadingModel: model,
                memoryBoundsChecking: .software, fuelMetering: true)
            configuration.enableExperimentalSoftwareDirectThreading()
            let store = Store(engine: Engine(configuration: configuration))
            store.fuel = Fuel(remaining: 10_000)
            var calls: [String] = []
            var imports = Imports()
            for (name, count) in [("exchange", 6), ("read_reply", 2)] {
                imports.define(module: "crabrix_proc_macro_v1", name: name,
                    Function(store: store, parameters: Array(repeating: .i32, count: count), results: [.i32]) { caller, _ in
                        let instance = try XCTUnwrap(caller.instance)
                        XCTAssertNotNil(instance.exports[memory: "memory"])
                        calls.append(name)
                        return [.i32(4)]
                    })
            }
            imports.define(module: "crabrix_native_proxy", name: "dispatch",
                Function(store: store, parameters: [.i32, .i32], results: [.i64]) { caller, _ in
                    XCTAssertNotNil(caller.instance?.exports[memory: "memory"])
                    calls.append("dispatch")
                    return [.i64(4 << 32)]
                })
            let instance = try parseWasm(bytes: ProcMacroNativeProxy.bytes).instantiate(store: store, imports: imports)
            let allocate = try XCTUnwrap(instance.exports[function: "__crabrix_pm_alloc"])
            XCTAssertEqual(try allocate([.i32(65_537)]), [.i32(0)])
            XCTAssertEqual(try XCTUnwrap(instance.exports[memory: "memory"]).guestMemoryByteCount, 131_072)
            XCTAssertEqual(try XCTUnwrap(instance.exports[function: "exchange"])(Array(repeating: .i32(0), count: 6)), [.i32(4)])
            XCTAssertEqual(try XCTUnwrap(instance.exports[function: "read_reply"])([.i32(0), .i32(4)]), [.i32(4)])
            XCTAssertEqual(try XCTUnwrap(instance.exports[function: "__crabrix_pm_dispatch"])([.i32(0), .i32(4)]), [.i64(4 << 32)])
            XCTAssertEqual(calls, ["exchange", "read_reply", "dispatch"])
            XCTAssertThrowsError(try allocate([.i32(16 * 1024 * 1024 + 1)]))
        }
    }
}
#endif
