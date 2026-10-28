import Foundation
import XCTest
@testable import Crabrix

final class RustDebuggerTests: XCTestCase {
    func testOpaqueResourceBytesMatchNormalRunDuringRealDebug() async throws {
        let source = "fn main(){\n let bytes=include_bytes!(\"asset.bin\");\n println!(\"{:?}\",bytes);\n}\n"
        let resources = ["asset.bin": Data([0,255,42])]
        let compiler = WasmRustCompiler()
        let normal = await compiler.run(source: source, resourceFiles: resources)
        XCTAssertTrue(normal.succeeded, normal.detail + normal.stderr)
        let recorder = StepRecorder()
        let session = RustDebugSession(onPlan: { _ in }, onPause: recorder.receive)
        recorder.session = session
        let debug = await compiler.debug(source: source, resourceFiles: resources, session: session)
        XCTAssertTrue(debug.succeeded, debug.detail + debug.stderr)
        XCTAssertEqual(debug.stdout, normal.stdout)
        XCTAssertEqual(debug.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "[0, 255, 42]")
        XCTAssertGreaterThan(recorder.snapshots.count, 1)
    }
    func testGeneratedBindingsAndMacroOwnershipMatchActualRun() async throws {
        let cases = [
            "fn main(){let s=String::from(\"x\");println!(\"{}\",s);}",
            "fn main(){let r#s=String::from(\"raw\");let d=vec![1,2];println!(\"{} {}\",r#s,d.len());}",
            "macro_rules! println {($x:ident)=>{drop($x)};} fn main(){let value=String::from(\"x\");println!(value);std::println!(\"ok\");}",
            "fn main(){let value=String::from(\"x\");dbg!(value);}",
            "fn consume(_:String)->u8{7} fn main(){let value=String::from(\"x\");println!(\"{}\",consume(value));}",
            "struct String; impl String{fn new()->Self{Self}fn len(self)->u8{4}} fn main(){let value=String::new();let n=value.len();println!(\"{n}\");}"
        ]
        for source in cases {
            let recorder = StepRecorder()
            let session = RustDebugSession(onPlan: { _ in }, onPause: recorder.receive)
            recorder.session = session
            let compiler = WasmRustCompiler()
            let normal = await compiler.run(source: source)
            XCTAssertTrue(normal.succeeded, normal.detail + normal.stderr)
            let debug = await compiler.debug(source: source, session: session)
            XCTAssertTrue(debug.succeeded, source + "\n" + debug.detail + debug.stderr)
            XCTAssertEqual(debug.stdout, normal.stdout)
            if source.contains("let s=") {
                XCTAssertTrue(recorder.snapshots.flatMap { $0.frames.flatMap(\.locals) }.contains { $0.name == "s" && $0.value.contains("x") })
            }
            if source.contains("dbg!(value)") { XCTAssertTrue(debug.stderr.contains("value = \"x\""), debug.stderr) }
        }
    }

    func testShadowedResourceMacroKeepsNormalRunAndFailsBeforeRewrite() async throws {
        let source = "macro_rules! include_str {($x:literal)=>{$x};} fn main(){println!(\"{}\",include_str!(\"main.rs\"));}"
        let compiler = WasmRustCompiler()
        let normal = await compiler.run(source: source)
        XCTAssertTrue(normal.succeeded, normal.detail)
        XCTAssertEqual(normal.stdout, "main.rs\n")
        let session = RustDebugSession(onPlan: { _ in }, onPause: { _ in })
        let debug = await compiler.debug(source: source, session: session)
        XCTAssertFalse(debug.succeeded)
        XCTAssertTrue(debug.detail.contains("resolve the resource macro"), debug.detail)
        let after = await compiler.run(source: "fn main(){println!(\"recovered\");}")
        XCTAssertEqual(after.stdout, "recovered\n")
    }

    func testCompileOnlyLibraryBuildDoesNotRequireMain() async throws {
        let compiler = WasmRustCompiler()
        let library = await compiler.build(source: "pub fn answer()->u32{42}", sourcePath: "src/lib.rs")
        XCTAssertTrue(library.succeeded, library.detail + library.stderr)
        XCTAssertEqual(library.phase, .compile)
        XCTAssertEqual(library.stdout, "")
        XCTAssertNil(library.webPreview)
    }

    func testCompileOnlyBuildNeverExecutesMainAndCachesExecutableForRun() async throws {
        let source = "fn main(){std::fs::write(\"/sandbox/index.html\",\"<h1>Executed</h1>\").unwrap();println!(\"MAIN-EXECUTED\");}"
        let cache = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cache) }
        let compiler = WasmRustCompiler(projectArtifactRoot: cache)
        for _ in 0..<2 {
            let built = await compiler.build(source: source)
            XCTAssertTrue(built.succeeded, built.detail + built.stderr)
            XCTAssertEqual(built.phase, .compile)
            XCTAssertEqual(built.stdout, "")
            XCTAssertNil(built.webPreview)
        }
        let run = await compiler.run(source: source)
        XCTAssertTrue(run.succeeded, run.detail + run.stderr)
        XCTAssertEqual(run.stdout, "MAIN-EXECUTED\n")
        XCTAssertEqual(run.webPreview?.assets["index.html"], Data("<h1>Executed</h1>".utf8))
        XCTAssertTrue(run.detail.contains("cached"), run.detail)
    }

    private static let source = "fn add(a: i32, b: i32) -> i32 {\n let c = a + b;\n c\n}\nfn main() {\n let mut total = 0;\n for i in 0..3 {\n total += add(i,1);\n }\n println!(\"total={total}\");\n}\n"
    private final class Recorder: @unchecked Sendable {
        let lock = NSLock()
        weak var session: RustDebugSession?
        private var values: [RustDebugPause] = []
        var snapshots: [RustDebugPause] { lock.withLock { values } }
        func receive(_ value: RustDebugPause) {
            let index = lock.withLock { values.append(value); return values.count - 1 }
            let commands: [RustDebugSession.Command] = [.over,.continue,.into,.over,.out,.continue]
            if index == 5 { session?.updateBreakpoints([]) }
            if index >= commands.count { session?.stop(); return }
            // Release the compiler thread only after another queue has run.
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.03) { [weak self] in self?.session?.resume(commands[index]) }
        }
    }
    private final class StepRecorder: @unchecked Sendable {
        let lock = NSLock()
        weak var session: RustDebugSession?
        private var values: [RustDebugPause] = []
        var snapshots: [RustDebugPause] { lock.withLock { values } }
        func receive(_ value: RustDebugPause) {
            let count = lock.withLock { values.append(value); return values.count }
            if count > 500 { session?.stop() } else { session?.resume(.into) }
        }
    }
    func testWebGeneratorDebugsIncludedHTMLCSSAndJavaScript() async throws {
        let recorder = StepRecorder()
        let session = RustDebugSession(breakpoints: [RustDebugBreakpoint(file: "src/main.rs", line: 7)], onPlan: { _ in }, onPause: recorder.receive)
        recorder.session = session
        let files = WebProjectSamples.files.reduce(into: [String: String]()) { $0["web/" + $1.key] = $1.value }
        let compiler = WasmRustCompiler()
        let debug = await compiler.debug(source: WebProjectSamples.rustGenerator, sourcePath: "src/main.rs", supportingFiles: files, session: session)
        XCTAssertTrue(debug.succeeded, debug.detail + "\n" + debug.stderr)
        let preview = try XCTUnwrap(debug.webPreview)
        for (path, contents) in WebProjectSamples.files {
            XCTAssertEqual(preview.assets[path], Data(contents.utf8), "Debug must preserve included resource bytes")
        }
        XCTAssertTrue(recorder.snapshots.contains { $0.site.file == "src/main.rs" && $0.site.line == 7 && $0.reason == "breakpoint" })
        let normal = await compiler.run(source: WebProjectSamples.rustGenerator, sourcePath: "src/main.rs", supportingFiles: files)
        XCTAssertTrue(normal.succeeded, normal.detail + normal.stderr)
        XCTAssertEqual(debug.stdout, normal.stdout)
        XCTAssertEqual(debug.webPreview?.assets, normal.webPreview?.assets)
    }
    func testDebugIncludesOriginalRustSourceAsData() async throws {
        let source = #"""
        fn main() {
            let text = std::include_str!(r#"main.rs"#);
            let bytes = include_bytes!("/work/main.rs");
            assert_eq!(text.as_bytes(), bytes);
            println!("{}", text.len());
        }
        """#
        let recorder = StepRecorder()
        let session = RustDebugSession(onPlan: { _ in }, onPause: recorder.receive)
        recorder.session = session
        let compiler = WasmRustCompiler()
        let debug = await compiler.debug(source: source, session: session)
        XCTAssertTrue(debug.succeeded, debug.detail + debug.stderr)
        let normal = await compiler.run(source: source)
        XCTAssertTrue(normal.succeeded, normal.detail + normal.stderr)
        XCTAssertEqual(debug.stdout, normal.stdout)
        XCTAssertGreaterThan(recorder.snapshots.count, 2)
    }
    func testAggregatePreviewsWithoutUserDebugAndWithBoundedUnicode() async throws {
        let recorder = StepRecorder()
        let session = RustDebugSession(onPlan: { _ in }, onPause: recorder.receive)
        recorder.session = session
        let source = """
        struct Address { city: String }
        struct Person { name: String, scores: Vec<u32>, address: Address }
        impl std::fmt::Debug for Person {
            fn fmt(&self, _: &mut std::fmt::Formatter<'_>)->std::fmt::Result {panic!("must never call user Debug")}
        }
        fn main() {
            let mut text=String::from("Ferris 🦀");
            text.push_str(" Rust");
            let mut numbers=vec![1u32,2,3];
            numbers.push(42);
            let person=Person{name:String::from("Crab"),scores:vec![7,8],address:Address{city:String::from("Kyiv")}};
            let huge=vec![9u32;100000];
            println!("{} {} {} {}",text,numbers.len(),person.name,huge.len());
        }
        """
        let compiler = WasmRustCompiler()
        let result = await compiler.debug(source: source, session: session)
        XCTAssertTrue(result.succeeded, result.detail + "\n" + result.stderr)
        let locals = recorder.snapshots.flatMap { $0.frames.flatMap(\.locals) }
        XCTAssertTrue(locals.contains { $0.name == "text" && $0.value.contains("Ferris 🦀 Rust") })
        XCTAssertTrue(locals.contains { $0.name == "numbers" && $0.value == "[len=4] [1, 2, 3, 42]" })
        XCTAssertTrue(locals.contains { $0.name == "person" && $0.value.contains("name: \"Crab\"") && $0.value.contains("city: \"Kyiv\"") })
        XCTAssertTrue(locals.contains { $0.name == "huge" && $0.value.contains("len=100000") && $0.value.contains("…") })
        XCTAssertTrue(locals.allSatisfy { $0.value.utf8.count < 1024 })
        let normal = await compiler.run(source: source)
        XCTAssertEqual(result.stdout, normal.stdout)
    }
    func testActualTokioAsyncPollStacksAndLocalsOffline() async throws {
        let manifest = """
        [package]
        name = "debug-tokio-gate"
        version = "0.1.0"
        edition = "2021"
        [dependencies]
        tokio = { version = "=1.54.1", default-features = false, features = ["rt", "sync", "time"] }
        """
        let manager = CargoPackageManager()
        let prepared = try await manager.prepare(manifestSource: manifest)
        XCTAssertTrue(prepared.blockingPackages.isEmpty, prepared.blockingPackages.description)
        try await manager.pinForOffline(prepared.packages)
        let lock = try XCTUnwrap(prepared.lockfile)
        let offline = try await CargoPackageManager().prepare(manifestSource: manifest, lockfileSource: lock, mode: .frozen)
        XCTAssertTrue(offline.isOfflinePinned)
        let source = """
        async fn work(id:u32)->u32 {
            let text=String::from("Tokio crab 🦀");
            let values=vec![id,42];
            tokio::task::yield_now().await;
            tokio::time::sleep(std::time::Duration::from_millis(1)).await;
            println!("{text} {}",values.len());
            id+1
        }
        fn main(){
            let rt=tokio::runtime::Builder::new_current_thread().enable_time().build().unwrap();
            rt.block_on(async {
                let a=tokio::spawn(work(1));
                let b=tokio::spawn(work(2));
                let cancelled=tokio::spawn(async {std::future::pending::<()>().await;});
                tokio::task::yield_now().await;
                cancelled.abort();
                assert!(cancelled.await.unwrap_err().is_cancelled());
                let (tx,mut rx)=tokio::sync::mpsc::channel(2);
                tx.send(a.await.unwrap()+b.await.unwrap()).await.unwrap();
                assert_eq!(rx.recv().await,Some(5));
                println!("tokio debug: 5");
            });
        }
        """
        let recorder = StepRecorder()
        let session = RustDebugSession(onPlan: { _ in }, onPause: recorder.receive)
        recorder.session = session
        let compiler = WasmRustCompiler()
        let result = await compiler.debug(source: source, sourcePath: "src/main.rs", supportingFiles: ["Cargo.toml": manifest, "Cargo.lock": lock], edition: "2021", plan: offline.plan, session: session)
        XCTAssertTrue(result.succeeded, result.detail + "\n" + result.stderr)
        XCTAssertTrue(result.stdout.contains("tokio debug: 5"), result.stdout)
        let pauses = recorder.snapshots
        let asyncPauses = pauses.filter { $0.site.function == "work" }
        XCTAssertGreaterThan(asyncPauses.count, 6)
        XCTAssertTrue(asyncPauses.allSatisfy { $0.frames.filter { $0.site.function == "work" }.count == 1 }, "Suspended tasks must leave the active poll stack")
        XCTAssertTrue(asyncPauses.flatMap { $0.frames.flatMap(\.locals) }.contains { $0.name == "text" && $0.value.contains("Tokio crab 🦀") })
        let normal = await compiler.run(source: source, sourcePath: "src/main.rs", supportingFiles: ["Cargo.toml": manifest, "Cargo.lock": lock], edition: "2021", plan: offline.plan)
        XCTAssertTrue(normal.succeeded, normal.detail + normal.stderr)
        XCTAssertEqual(result.stdout, normal.stdout)
        print("TOKIO DEBUG OFFLINE VERIFIED", result.duration, "seconds,", pauses.count, "real pauses")
    }
    func testActualRustBreakpointsStepsFramesLocalsAndNormalRun() async throws {
        let recorder = Recorder()
        let session = RustDebugSession(breakpoints: [RustDebugBreakpoint(file: "main.rs", line: 8)], onPlan: { _ in }, onPause: recorder.receive)
        recorder.session = session
        let compiler = WasmRustCompiler()
        let value = await compiler.debug(source: Self.source, session: session)
        XCTAssertTrue(value.succeeded, value.detail + "\n" + value.stderr)
        XCTAssertEqual(value.stdout, "total=6\n")
        let stops = recorder.snapshots
        XCTAssertEqual(stops.map(\.site.line), [6,7,8,2,3,9])
        XCTAssertEqual(stops.map(\.site.function), ["main","main","main","add","add","main"])
        guard stops.count == 6 else { return }
        XCTAssertEqual(stops[2].reason, "breakpoint")
        XCTAssertEqual(stops[3].frames.count, 2)
        XCTAssertEqual(stops[4].frames.last?.locals.first(where: { $0.name == "c" })?.value, "1")
        XCTAssertEqual(stops[5].frames.last?.locals.first(where: { $0.name == "total" })?.value, "1")
        let normal = await compiler.run(source: Self.source)
        XCTAssertTrue(normal.succeeded, normal.detail)
        XCTAssertEqual(normal.stdout, "total=6\n", "Debug imports must not contaminate normal Run or its cache")
    }
    func testStopReleasesAPausedActualGuest() async throws {
        let paused = expectation(description: "actual guest paused")
        let session = RustDebugSession(onPlan: { _ in }, onPause: { _ in paused.fulfill() })
        let compiler = WasmRustCompiler()
        let task = Task { await compiler.debug(source: "fn main() { let mut n=0u32; loop { n=n.wrapping_add(1); std::hint::black_box(n); } }", session: session) }
        await fulfillment(of: [paused], timeout: 120)
        session.stop(); compiler.cancel()
        let value = await task.value
        XCTAssertFalse(value.succeeded)
        let next = await compiler.run(source: "fn main(){println!(\"after-stop\");}")
        XCTAssertTrue(next.succeeded, next.detail)
        XCTAssertEqual(next.stdout, "after-stop\n")
    }
    func testPausedTimeDoesNotConsumeRunningDeadline() async throws {
        let state = AtomicStopState()
        state.setDeadline(after: .milliseconds(50)); state.pauseDeadline()
        try await Task.sleep(for: .milliseconds(90))
        XCTAssertNil(state.reason)
        state.resumeDeadline(); XCTAssertNil(state.reason)
        try await Task.sleep(for: .milliseconds(90))
        XCTAssertEqual(state.reason, .wallClock)
        let cancelled = AtomicStopState(); cancelled.setDeadline(after: .seconds(1)); cancelled.pauseDeadline(); cancelled.cancel(reason: .userRequested)
        XCTAssertEqual(cancelled.reason, .userRequested)
    }
    func testOriginalBorrowSemanticsAndUninitializedLocalsStillCompile() async throws {
        let session = RustDebugSession(onPlan: { _ in }, onPause: { _ in })
        // The first run is an instrumenter gate; actual execution is covered by
        // the preceding tests. It must not add a borrow of x or read late early.
        let source = "fn main(){let mut x=1; let p=&mut x; *p+=2; let late:i32; late=4; println!(\"{} {}\",x,late); }"
        let plan = try RustDebugInstrumenter.instrument(files: ["main.rs": source], entryFile: "main.rs")
        session.prepare(plan)
        let compiler = WasmRustCompiler()
        let checked = await compiler.check(source: plan.files["main.rs"]!)
        XCTAssertTrue(checked.succeeded, checked.stderr)
    }
}
