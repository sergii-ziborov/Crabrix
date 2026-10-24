import CryptoKit
import Foundation
import WasmKit
import WasmKitWASI
import XCTest
@testable import Crabrix

/// This never changes the app's production artifact identity. A test-only
/// resource contains the compiler built by the separate manual Cloud workflow.
final class CompilerCandidateGateTests: XCTestCase {
    func testCandidateCompilesAndRunsUsingSignedSysroot() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["CRABRIX_RUN_COMPILER_CANDIDATE"] != "1")
        let directory = try XCTUnwrap(Bundle(for: Self.self).resourceURL)
            .appending(path: "CompilerCandidate/Artifact", directoryHint: .isDirectory)
        let compiler = directory.appending(path: "rustc.wasm")
        let provenanceURL = directory.appending(path: "provenance.json")
        let provenance = try JSONSerialization.jsonObject(with: Data(contentsOf: provenanceURL)) as? [String: Any]
        XCTAssertEqual(provenance?["candidate"] as? Bool, true)
        XCTAssertEqual(provenance?["productionReplacement"] as? Bool, false)
        let bytes = try Data(contentsOf: compiler, options: [.mappedIfSafe])
        XCTAssertEqual(Array(bytes.prefix(8)), [0, 97, 115, 109, 1, 0, 0, 0])
        let sha = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(sha, provenance?["compilerSHA256"] as? String)
        XCTAssertEqual(bytes.count, provenance?["compilerBytes"] as? Int)
        for url in [compiler, provenanceURL] {
            let attachment = XCTAttachment(contentsOfFile: url)
            attachment.name = "compiler-candidate-" + url.lastPathComponent
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let toolchain = try XCTUnwrap(BundledToolchain.locate(in: .main, version: CargoToolchain.bundledVersion))
        let root = FileManager.default.temporaryDirectory.appending(path: "CompilerCandidate-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let smoke = #"""
        use std::collections::BTreeMap;
        fn main() {
            let values = BTreeMap::from([("gamma", 3_i64), ("alpha", 1), ("beta", 2)]);
            let sum: i64 = values.values().copied().sum();
            assert_eq!(sum, 6);
            let a: i128 = std::hint::black_box(-7);
            let b: i128 = std::hint::black_box(17);
            assert_eq!(a * b, -119);
            let wide = std::hint::black_box(1_i128 << 100);
            assert!(wide > 1_i128 << 99);
            assert_eq!((wide | 0x1234).swap_bytes().swap_bytes(), wide | 0x1234);
            let convert = |n: i64| n * n;
            assert_eq!(values.values().map(|&n| convert(n)).sum::<i64>(), 14);
            println!("candidate smoke: sum={sum} wide={}", a * b);
        }
        """#
        for (name, url) in [("production", toolchain.rustcURL), ("candidate", compiler)] {
            let runtime = RustcRuntime()
            let module = try runtime.rustcModule(at: url)
            let work = root.appending(path: name)
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let preopens: [WASIBridgeToHost.Preopen] = [
                .init(guestPath: "/work", hostPath: work.path),
                .init(guestPath: "/tmp", hostPath: work.path),
                .init(guestPath: "/sysroot", hostPath: toolchain.sysrootURL.path, readOnly: true),
            ]
            func invoke(_ arguments: [String], prefix: String) throws -> WasmProcessResult {
                try runtime.run(
                    module: module, arguments: ["rustc"] + arguments,
                    environment: ["CLIF2WASM_OBJECT": "1"], preopens: preopens,
                    captureDirectory: work, capturePrefix: prefix,
                    resourceLimiter: WasmSandboxResourceLimiter(
                        memoryLimitBytes: CompilerHostPolicy.memoryLimitBytes,
                        tableElementLimit: CompilerHostPolicy.tableElementLimit),
                    fuelBudget: CompilerHostPolicy.fuelBudget,
                    wallClockLimit: .seconds(240), interrupter: WasmInterrupter(),
                    softwareMemoryReservationBytes: CompilerHostPolicy.memoryLimitBytes,
                    capturedOutputLimitBytes: CompilerHostPolicy.outputLimitBytes)
            }
            let version = try invoke(["--version"], prefix: "version")
            XCTAssertEqual(version.exitCode, 0, version.stderr)
            XCTAssertTrue(version.stdout.contains("rustc 1.96.0"), version.stdout)
            try smoke.write(to: work.appending(path: "main.rs"), atomically: true, encoding: .utf8)
            let flags = ["--sysroot", "/sysroot", "--target", "wasm32-wasip1", "--edition", "2021",
                         "--error-format=json", "-Copt-level=0", "-Cpanic=abort", "-Zunstable-options"]
            let started = ContinuousClock.now
            let compiled = try invoke(["/work/main.rs"] + flags + ["-o", "/work/program.wasm"], prefix: "compile")
            print("COMPILER CANDIDATE COMPILE", name, started.duration(to: .now))
            guard compiled.exitCode == 0 else {
                return XCTFail("\(name) cannot compile with signed target sysroot: \(compiled.stderr)")
            }
            let program = try parseWasm(filePath: work.appending(path: "program.wasm").path)
            let executed = try runtime.run(
                module: program, arguments: ["program"], environment: [:], preopens: [],
                captureDirectory: work, capturePrefix: "run",
                resourceLimiter: WasmSandboxResourceLimiter(),
                fuelBudget: WasmSandboxPolicy.userProgramInstructionBudget,
                wallClockLimit: .seconds(10), interrupter: WasmInterrupter(),
                capturedOutputLimitBytes: WasmSandboxPolicy.userProgramOutputLimitBytes)
            XCTAssertEqual(executed.exitCode, 0, executed.stderr)
            XCTAssertEqual(executed.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
                           "candidate smoke: sum=6 wide=-119")

            let invalid = "fn main() { let mut v = vec![1]; let first = &v[0]; v.push(2); println!(\"{first}\"); }"
            try invalid.write(to: work.appending(path: "invalid.rs"), atomically: true, encoding: .utf8)
            let diagnosticOutput: String
            do {
                let diagnostic = try invoke(["/work/invalid.rs"] + flags + ["--emit=metadata", "-o", "/work/invalid.rmeta"], prefix: "diagnostic")
                XCTAssertNotEqual(diagnostic.exitCode, 0)
                diagnosticOutput = diagnostic.stderr
            } catch let failure as RustcRuntimeFailure {
                // The existing WASI compiler aborts after emitting a fatal
                // language diagnostic. Match only that exact trap shape;
                // memory, fuel, cancellation and other failures still fail.
                guard let trap = failure.underlying as? Trap,
                      trap.description.split(separator: "\n").first == "Trap: unreachable"
                else { throw failure }
                diagnosticOutput = failure.stderr
            }
            let diagnostics = RustDiagnosticParser.parse(stderr: diagnosticOutput)
            XCTAssertTrue(diagnostics.contains {
                $0.code == "E0502" && $0.level == "error"
                    && $0.primarySpan?.fileName == "invalid.rs"
            }, diagnosticOutput)
        }
    }
}
