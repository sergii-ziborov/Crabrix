import XCTest
@testable import Crabrix

@MainActor
final class PlaygroundRuntimeInputTests: XCTestCase {
    func testActualSharedCompilerBuildDoesNotRunAndLateStopCannotCancelTheNextLocalRun() async throws {
        guard ProcessInfo.processInfo.environment["CRABRIX_RUN_SHARED_RUNTIME_GATE"] == "1" else {
            throw XCTSkip("Enable the explicit Shared runtime compiler qualification.")
        }
        let compiler = WasmRustCompiler(), completed = CompilerInvocationCancellation()
        let input = try PlaygroundRuntimeInput(document: .init(name: "sample", entryFile: "main.rs", files: ["main.rs": "fn main(){ println!(\"shared-isolated=42\"); }"]))
        let built = await input.execute(.build, compiler: compiler, cancellation: completed)
        XCTAssertTrue(built.succeeded, built.detail + built.stderr)
        XCTAssertEqual(built.phase, .compile); XCTAssertEqual(built.stdout, "")
        let ran = await input.execute(.run, compiler: compiler, cancellation: .init())
        XCTAssertTrue(ran.succeeded, ran.detail + ran.stderr)
        XCTAssertEqual(ran.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "shared-isolated=42")
        XCTAssertNil(ran.webPreview)

        let running = XCTestExpectation(description: "Next ordinary program entered the interpreter")
        let ordinary = CompilerInvocationCancellation(), flag = CompletionFlag()
        let task = Task {
            let value = await compiler.run(source: "fn main(){ loop {} }", cancellation: ordinary, onStage: { stage in
                if stage == "Running program" { running.fulfill() }
            })
            flag.finish(); return value
        }
        let started = await XCTWaiter.fulfillment(of: [running], timeout: 60)
        guard started == .completed else {
            ordinary.cancel(); _ = await task.value
            return XCTFail("The next ordinary run never reached execution.")
        }
        completed.cancel() // A late Stop from the already-finished Shared job.
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(flag.finished, "A completed Shared job stopped a later ordinary local run.")
        ordinary.cancel()
        let stopped = await task.value
        XCTAssertTrue(stopped.wasStopped, stopped.detail)

        let privateRead = try PlaygroundRuntimeInput(document: .init(name: "sample", entryFile: "main.rs", files: ["main.rs": "fn main(){ println!(\"{}\", include_str!(\".cargo/private.txt\")); }"]))
        let refused = await privateRead.execute(.check, compiler: compiler, cancellation: .init())
        XCTAssertFalse(refused.succeeded)
        XCTAssertTrue(refused.diagnostics.contains { $0.level == "error" })
    }

    func testSnapshotIncludesOnlyValidatedRoomFilesAndKeepsExactEditionAndEntry() throws {
        let files = ["src/main.rs": "mod helper; fn main() { helper::go(); }", "src/helper.rs": "pub fn go() {}", "README.md": "shared"]
        let input = try PlaygroundRuntimeInput(document: .init(name: "sample", entryFile: "src/main.rs", files: files, edition: "2021"))
        XCTAssertEqual(input.source, files["src/main.rs"])
        XCTAssertEqual(input.sourcePath, "src/main.rs")
        XCTAssertEqual(input.edition, "2021")
        XCTAssertEqual(input.supportingFiles, files.filter { $0.key != "src/main.rs" })
    }

    func testCargoRequirementsCannotBeSilentlyOmittedOrAcquirePackages() throws {
        let base = "[package]\nname='sample'\nversion='0.1.0'\nedition='2024'\n"
        let unsupported = [
            "[dependencies]\nserde='1'", "[dev-dependencies]\nserde='1'", "[build-dependencies]\ncc='1'",
            "[target.'cfg(unix)'.dependencies]\nlibc='*'", "[features]\ndefault=['extra']\nextra=[]",
            "[workspace]\nmembers=[]", "[patch.crates-io]\n", "[profile.dev]\nopt-level=3",
            "[lib]\nproc-macro=true", "[lib]\ncrate-type=['cdylib']",
            "[lib]\npath=4", "[lib]\ncrate-type=[4]", "[[bin]]\npath=4",
            "[[bin]]\npath='other.rs'", "[[bin]]\npath='src/main.rs'\nrequired-features=['x']"
        ]
        for suffix in unsupported {
            XCTAssertThrowsError(try PlaygroundRuntimeInput(document: .init(name: "sample", entryFile: "src/main.rs", files: ["src/main.rs": "fn main(){}", "Cargo.toml": base + suffix])), suffix)
        }
        for packageField in ["build='custom.rs'", "build=true", "links='native'", "edition='2021'"] {
            let manifest = packageField.hasPrefix("edition") ? base.replacingOccurrences(of: "edition='2024'", with: packageField) : base + packageField
            XCTAssertThrowsError(try PlaygroundRuntimeInput(document: .init(name: "sample", entryFile: "src/main.rs", files: ["src/main.rs": "fn main(){}", "Cargo.toml": manifest])), packageField)
        }
        _ = try PlaygroundRuntimeInput(document: .init(name: "sample", entryFile: "src/main.rs", files: ["src/main.rs": "fn main(){}", "Cargo.toml": base + "build=false\n[[bin]]\nname='sample'\npath='src/main.rs'"]))
    }

    func testPrivateInputsPathAliasesAndBuildScriptsAreRefusedBeforeCompilation() throws {
        for path in [".cargo/config.toml", "vendor/private.rs", "target/private.rs", ".git/config.txt", "node_modules/private.txt", "build.rs", "nested/Cargo.toml", ".CARGO/private.toml", "TARGET/private.rs", "Vendor/private.rs", "BUILD.RS", "CARGO.TOML", "nested/CARGO.TOML"] {
            XCTAssertThrowsError(try PlaygroundRuntimeInput(document: .init(name: "sample", entryFile: "main.rs", files: ["main.rs": "fn main(){}", path: "private"])), path)
        }
        XCTAssertThrowsError(try PlaygroundRuntimeInput(document: .init(name: "sample", entryFile: "main.rs", files: ["main.rs": "fn main(){}", "Main.rs": "fn main(){}"])))
    }
}

private final class CompletionFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func finish() { lock.lock(); value = true; lock.unlock() }
    var finished: Bool { lock.lock(); defer { lock.unlock() }; return value }
}
