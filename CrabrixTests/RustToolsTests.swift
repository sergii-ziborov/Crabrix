import XCTest
import SwiftUI
import UIKit
@testable import Crabrix

final class RustToolsTests: XCTestCase {
    @MainActor
    func testProjectFormatCheckUndoAndStaleRevisionAreTransactional() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = CompilerViewModel(projectLibrary: ProjectLibrary(storageURL: root.appending(path: "recent.json")))
        model.createProject(name: "format", template: .hello)
        var files = model.exportProject().files
        files["src/main.rs"] = "// 🦀 keep\nfn main(){println!(\"hi\");}"
        files["src/helper.rs"] = "pub fn value()->u32{2}"
        files["vendor/keep.rs"] = "fn broken( {"
        files["node_modules/keep.rs"] = "fn broken( {"
        XCTAssertTrue(model.replaceProjectFilesFromTerminal(files))
        let before = model.exportProject().files
        model.formatRust(.init(scope: .project, checkOnly: true))
        try await waitForTool(model)
        XCTAssertFalse(try XCTUnwrap(model.result).succeeded)
        XCTAssertEqual(model.exportProject().files, before)
        model.formatRust(.init(scope: .project))
        try await waitForTool(model)
        XCTAssertTrue(try XCTUnwrap(model.result).succeeded)
        XCTAssertTrue(model.canUndoFormatting)
        XCTAssertEqual(model.exportProject().files["vendor/keep.rs"], before["vendor/keep.rs"])
        XCTAssertTrue(model.exportProject().files["src/helper.rs"]?.contains("-> u32") == true)
        await model.retryProjectSave()
        model.undoFormatting()
        XCTAssertEqual(model.exportProject().files, before)
        XCTAssertFalse(model.canUndoFormatting)
        model.formatRust(.init(scope: .project))
        model.source += "\n// user edited during format"
        let latest = model.source
        try await waitForTool(model)
        XCTAssertEqual(model.source, latest)
        XCTAssertNil(model.result)
        XCTAssertFalse(model.canUndoFormatting)
    }

    @MainActor
    func testFormatFailureStopAndUserTestsDoNotAwardLearning() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = CompilerViewModel(projectLibrary: ProjectLibrary(storageURL: root.appending(path: "recent.json")))
        model.createProject(name: "tests", template: .hello)
        let completed = model.completedLessonIDs
        model.source = "#[test] fn pass(){assert_eq!(2+2,4);} fn main(){panic!(\"main must not run\");}"
        model.runUnitTests()
        try await waitForTool(model)
        XCTAssertTrue(try XCTUnwrap(model.result).succeeded)
        XCTAssertEqual(model.result?.phase, .test)
        XCTAssertNil(model.lastBuild)
        XCTAssertEqual(model.completedLessonIDs, completed)
        XCTAssertNotNil(model.unitTestReport)
        model.runUnitTests(.init(target: .binary("missing-target")))
        XCTAssertNil(model.unitTestReport, "A rejected request must not display the previous test report")
        XCTAssertFalse(try XCTUnwrap(model.result).succeeded)
        XCTAssertNil(model.lastBuild)
        model.source += "\n// changed"
        XCTAssertNil(model.unitTestReport)
        XCTAssertNil(model.result)
        model.source = "fn main( {"
        let invalid = model.source
        model.formatRust(.init(scope: .file(model.selectedFile)))
        try await waitForTool(model)
        XCTAssertEqual(model.source, invalid)
        XCTAssertFalse(try XCTUnwrap(model.result).succeeded)
        model.source = "fn main(){}"
        model.formatRust(.init(scope: .project)); model.cancelBuild()
        try await waitForTool(model)
        XCTAssertEqual(model.source, "fn main(){}")
        model.formatRust(.init(scope: .project))
        try await waitForTool(model)
        XCTAssertTrue(try XCTUnwrap(model.result).succeeded)
    }

    @MainActor
    func testNativeFormattingUndoRestoresExactTextAndSelectionAndRefusesWrongDocument() throws {
        let projectID = UUID()
        var source = "fn main(){println!(\"🦀\");}"
        var cursor = 0
        let parent = SyntaxCodeEditor(text: Binding(get: { source }, set: { source = $0 }),
            cursorOffset: Binding(get: { cursor }, set: { cursor = $0 }), projectID: projectID,
            filePath: "main.rs", isEditable: true, navigationTarget: nil, onRequestCompletion: {})
        let coordinator = parent.makeCoordinator()
        let canvas = CodeEditorCanvas(frame: CGRect(x: 0, y: 0, width: 390, height: 500))
        let window = UIWindow(frame: canvas.bounds)
        let host = UIViewController(); window.rootViewController = host
        host.view.addSubview(canvas); window.makeKeyAndVisible()
        defer { window.isHidden = true }
        coordinator.textView = canvas.textView; coordinator.canvas = canvas
        canvas.textView.text = source
        canvas.textView.becomeFirstResponder()
        let undo = try XCTUnwrap(canvas.textView.undoManager)
        undo.groupsByEvent = false
        let original = source
        let selection = NSRange(location: 3, length: 4)
        canvas.textView.selectedRange = selection
        let formatted = "fn main() {\n    println!(\"🦀\");\n}\n"
        XCTAssertFalse(coordinator.replaceDocument(projectID: UUID(), file: "main.rs", expected: original, replacement: formatted))
        XCTAssertTrue(coordinator.replaceDocument(projectID: projectID, file: "main.rs", expected: original, replacement: formatted))
        XCTAssertTrue(undo.canUndo)
        undo.undo()
        XCTAssertEqual(source, original)
        XCTAssertEqual(canvas.textView.selectedRange, selection)
        undo.redo()
        XCTAssertEqual(source, formatted)
        XCTAssertFalse(coordinator.replaceDocument(projectID: projectID, file: "main.rs", expected: original, replacement: "bad"))
    }

    @MainActor
    private func waitForTool(_ model: CompilerViewModel) async throws {
        let start = ContinuousClock.now
        while model.isBusy || model.isCompilerDraining {
            if start.duration(to: .now) > .seconds(120) { XCTFail("Tool did not release its worker"); return }
            try await Task.sleep(for: .milliseconds(30))
        }
    }
    func testPinnedNativeRustfmtPreservesCommentsUnicodeMacrosAndIdempotence() async throws {
        let formatter = RustFormatter()
        let sources = [
            "fn main(){let x=1;println!(\"🦀 {x}\");}",
            "// keep this comment\nfn main(){let raw=r#\" { x } \"#; /* keep too */println!(\"{}\",raw);}",
            "macro_rules! demo{($a:expr)=>{$a+1};}fn main(){println!(\"{}\",demo!(2));}",
            "async fn example(){let x=3;println!(\"{x}\");}",
            "mod helper;fn main(){}"
        ]
        for source in sources {
            let formatted = try await formatter.format(source: source, edition: "2024")
            let again = try await formatter.format(source: formatted, edition: "2024")
            XCTAssertEqual(again, formatted)
            XCTAssertTrue(formatted.contains("\n"))
            if source.contains("keep this") {
                XCTAssertTrue(formatted.contains("// keep this comment"))
                XCTAssertTrue(formatted.contains("/* keep too */"))
                XCTAssertTrue(formatted.contains("r#\" { x } \"#"))
            }
            if source.contains("🦀") { XCTAssertTrue(formatted.contains("🦀")) }
        }
    }

    func testRustfmtRejectsInvalidSourceAndRespectsEditionAndConfiguration() async throws {
        let formatter = RustFormatter()
        do { _ = try await formatter.format(source: "fn main( {", edition: "2024"); XCTFail("Malformed source must not produce a replacement") }
        catch { XCTAssertFalse(error.localizedDescription.isEmpty) }
        do { _ = try await formatter.format(source: "async fn test(){}", edition: "2015"); XCTFail("The selected edition must be respected") }
        catch { XCTAssertFalse(error.localizedDescription.isEmpty) }
        let tabs = try await formatter.format(source: "fn main(){let a=1;println!(\"{a}\");}", edition: "2021", configuration: "hard_tabs = true\nmax_width = 100")
        XCTAssertTrue(tabs.contains("\tlet a = 1;"), tabs)
        do { _ = try await formatter.format(source: "fn main(){}", edition: "2024", configuration: "unknown_option = true"); XCTFail("Unknown configuration must not be silently ignored") }
        catch { XCTAssertTrue(error.localizedDescription.contains("unknown_option")) }
    }

    func testRustfmtCancellationDoesNotPoisonNextFormat() async throws {
        let formatter = RustFormatter()
        let task = Task { try await formatter.format(source: "fn main(){let items=vec![" + (0..<20_000).map(String.init).joined(separator: ",") + "];println!(\"{}\",items.len());}", edition: "2024") }
        task.cancel()
        do { _ = try await task.value; XCTFail("Canceled format must not return a replacement") }
        catch { }
        let next = try await formatter.format(source: "fn main(){}", edition: "2024")
        XCTAssertEqual(next, "fn main() {}\n")
    }
    func testRealLibtestDiscoveryAndIsolatedFailures() async throws {
        let compiler = WasmRustCompiler()
        let source = """
        #[test] fn a_passes(){println!("visible test output");assert_eq!(2+2,4);}
        #[test] fn b_fails(){assert_eq!(1,2);}
        #[test] fn c_after_failure(){assert!(true);}
        #[test] #[ignore] fn d_ignored(){panic!("must not run");}
        #[test] #[should_panic] fn e_expected_panic(){panic!("not qualified");}
        fn main(){panic!("main must not run during unit tests");}
        """
        let runner = RustUnitTestRunner()
        let report = await runner.run(compiler: compiler, source: source, sourcePath: "main.rs", supportingFiles: [:], edition: "2024", plan: .empty)
        XCTAssertNil(report.compilerFailure)
        XCTAssertEqual(report.cases.count, 5)
        XCTAssertEqual(report.cases.first(where: { $0.name == "a_passes" })?.state, .passed)
        XCTAssertTrue(report.cases.first(where: { $0.name == "a_passes" })?.stdout.contains("visible test output") == true)
        XCTAssertEqual(report.cases.first(where: { $0.name == "b_fails" })?.state, .failed)
        XCTAssertEqual(report.cases.first(where: { $0.name == "c_after_failure" })?.state, .passed)
        XCTAssertEqual(report.cases.first(where: { $0.name == "d_ignored" })?.state, .skipped)
        XCTAssertEqual(report.cases.first(where: { $0.name == "e_expected_panic" })?.state, .unsupported)
        XCTAssertFalse(report.rendered.succeeded)
        XCTAssertEqual(report.rendered.phase, .test)
        XCTAssertFalse(report.rendered.stdout.contains("[passed] e_expected_panic"))
    }

    func testLibtestLibraryFilterCompileFailureAndDevDependencyBoundary() async throws {
        let compiler = WasmRustCompiler()
        let runner = RustUnitTestRunner()
        let source = "#[cfg(test)]mod tests{#[test]fn adds(){assert_eq!(2+2,4);}}"
        let report = await runner.run(compiler: compiler, source: source, sourcePath: "src/lib.rs", supportingFiles: [:], edition: "2024", plan: .empty, filter: "adds")
        XCTAssertEqual(report.cases.map(\.name), ["tests::adds"])
        XCTAssertTrue(report.rendered.succeeded)
        XCTAssertEqual(report.cases.first?.file, "src/lib.rs")
        let invalid = await runner.run(compiler: compiler, source: "#[test]fn bad(){let n:u32=\"text\";}", sourcePath: "main.rs", supportingFiles: [:], edition: "2024", plan: .empty)
        XCTAssertNotNil(invalid.compilerFailure)
        XCTAssertFalse(invalid.rendered.succeeded)
        let manifest = "[package]\nname=\"with-dev\"\nversion=\"0.1.0\"\n[dev-dependencies]\nregex=\"1\""
        let unsupported = await compiler.unitTest(source: source, supportingFiles: ["Cargo.toml":manifest], invocation: .discover)
        XCTAssertFalse(unsupported.succeeded)
        XCTAssertTrue(unsupported.detail.contains("dev-dependencies"))
    }

    func testStopInterruptsRealUnitGuestAndNextRunWorks() async throws {
        let compiler = WasmRustCompiler()
        let entered = expectation(description: "actual unit guest begins")
        let task = Task {
            await compiler.unitTest(source: "#[test]fn endless(){loop{std::hint::black_box(1);}}", invocation: .single("endless"), onStage: { stage in
                if stage == "Running isolated unit test locally" { entered.fulfill() }
            })
        }
        await fulfillment(of: [entered], timeout: 120)
        compiler.cancel()
        let canceled = await task.value
        XCTAssertTrue(canceled.wasStopped, canceled.detail)
        let next = await compiler.run(source: "fn main(){println!(\"after test stop\");}")
        XCTAssertTrue(next.succeeded, next.detail + next.stderr)
        XCTAssertEqual(next.stdout, "after test stop\n")
    }

}
