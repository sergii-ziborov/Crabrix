import XCTest
import SwiftUI
import UIKit
@testable import Crabrix

final class RustSemanticTextTests: XCTestCase {
    @MainActor
    func testCursorReadUsesActualScopedEditorWhenPublishedBindingLags() throws {
        let identity = UUID(), source = "mod models;\nfn main() { let value: Widg; }\n"
        let editor = SyntaxCodeEditor(text: .constant(source), cursorOffset: .constant(0), projectID: identity,
            filePath: "main.rs", isEditable: true, navigationTarget: nil, onRequestCompletion: {})
        let coordinator = editor.makeCoordinator(), textView = UITextView()
        textView.text = source
        textView.selectedRange = NSRange(location: 39, length: 0)
        coordinator.textView = textView
        XCTAssertEqual(coordinator.cursorOffset(projectID: identity, file: "main.rs"), 39)
        XCTAssertNil(coordinator.cursorOffset(projectID: UUID(), file: "main.rs"))
        XCTAssertNil(coordinator.cursorOffset(projectID: identity, file: "models.rs"))
        textView.text = "fn main(){}"
        XCTAssertNil(coordinator.cursorOffset(projectID: identity, file: "main.rs"))
    }
    private func edit(_ start: Int, _ end: Int, _ value: String) -> RustSemanticEdit {
        .init(range: .init(start: start, end: end, unit: "utf8"), insert: value)
    }
    func testUnicodeOffsetsAndAtomicMultiFileEditsRejectCorruption() throws {
        let text = "// 🦀\nfn main(){let café=1;}"
        let position = (text as NSString).range(of: "café").location
        let offset = try RustSemanticText.utf8Offset(position, in: text)
        XCTAssertEqual(RustSemanticText.location(offset: offset, in: text)?.line, 2)
        XCTAssertThrowsError(try RustSemanticText.utf8Offset(4, in: text))
        XCTAssertThrowsError(try RustSemanticText.utf8Offset(-1, in: text))
        XCTAssertThrowsError(try RustSemanticText.applying([edit(4, 5, "x")], to: text))
        XCTAssertThrowsError(try RustSemanticText.applying([edit(0, 5, "x"), edit(4, 8, "y")], to: text))
        XCTAssertEqual(try RustSemanticText.applying([edit(0, 0, "use a;"), edit(0, 0, "\n")], to: "fn main(){}"), "use a;\nfn main(){}")
        let files = ["main.rs": text, "helper.rs": "pub fn value(){}", "web/index.html": "<p>keep</p>"]
        let proposal = try RustSemanticProposal(files: files, changes: [
            .init(file: "main.rs", edits: [edit(offset, offset + "café".utf8.count, "count")]),
            .init(file: "helper.rs", edits: [edit(7, 12, "answer")]),
        ])
        XCTAssertEqual(proposal.after["web/index.html"], files["web/index.html"])
        XCTAssertEqual(proposal.changedPaths, ["helper.rs", "main.rs"])
        XCTAssertTrue(proposal.after["main.rs"]?.contains("let count=1") == true)
        XCTAssertThrowsError(try RustSemanticProposal(files: files, changes: [.init(file: "__dep/library/lib.rs", edits: [edit(0, 0, "bad")])]))
        XCTAssertEqual(files["main.rs"], text)
    }

    @MainActor
    func testReviewedApplyRequiresExactRevisionAndPersistsWholeTree() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = CompilerViewModel(projectLibrary: ProjectLibrary(storageURL: root.appending(path: "recent.json")))
        model.createProject(name: "semantic-atomic", template: .hello)
        let entry = model.exportProject().entryFile
        var files = model.exportProject().files
        files[entry] = "mod helper;fn main(){let value=helper::value();}"
        files["src/helper.rs"] = "pub fn value()->i32{1}"
        XCTAssertTrue(model.replaceProjectFilesFromTerminal(files))
        let context = try model.semanticContext()
        let start = try XCTUnwrap(files[entry]?.range(of: "value=helper")).lowerBound.utf16Offset(in: files[entry]!)
        let proposal = try RustSemanticProposal(files: files, changes: [.init(file: entry, edits: [edit(start, start + 5, "answer")])])
        model.source += "// newer"
        XCTAssertFalse(model.applySemanticProposal(proposal, expected: context.revision))
        let current = try model.semanticContext()
        let next = try RustSemanticProposal(files: current.project.files, changes: [.init(file: entry, edits: [edit(start, start + 5, "answer")])])
        XCTAssertTrue(model.applySemanticProposal(next, expected: current.revision))
        XCTAssertEqual(model.exportProject().files, next.after)
        XCTAssertFalse(model.applySemanticProposal(next, expected: current.revision))
        await model.retryProjectSave()
        XCTAssertEqual(model.exportProject().files, next.after)
        XCTAssertTrue(model.canUndoSymbolChanges)
        XCTAssertTrue(model.undoSymbolChanges())
        XCTAssertEqual(model.exportProject().files, current.project.files)
        XCTAssertFalse(model.canUndoSymbolChanges)
        var generated = model.exportProject().files; generated["build.rs"] = "fn main(){}"
        XCTAssertTrue(model.replaceProjectFilesFromTerminal(generated))
        XCTAssertThrowsError(try model.semanticContext())
    }

    @MainActor
    func testPreparedCrateBudgetRejectsLargeSourceAndRecoversAfterReduction() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let lib = root.appending(path: "bounded-1.0.0/src")
        try FileManager.default.createDirectory(at: lib, withIntermediateDirectories: true)
        try "pub fn count() -> usize { 1 }".write(to: lib.appending(path: "lib.rs"), atomically: true, encoding: .utf8)
        let model = CompilerViewModel(projectLibrary: ProjectLibrary(storageURL: root.appending(path: "recent.json")))
        model.createProject(name: "semantic-budget", template: .hello)
        let project = model.exportProject()
        let unit = CargoBuildUnit(package: .init(name: "bounded", version: try XCTUnwrap(SemanticVersion("1.0.0"))), fingerprint: "fedcba9876543210", crateName: "bounded", edition: "2024", features: [], libraryPath: "src/lib.rs", source: .registry(directoryName: "bounded-1.0.0"), externs: [], authors: "", description: "", repository: "", license: "MIT", homepage: "")
        let context = RustSemanticContext(project: project, revision: model.workspaceRevision, edition: "2024",
            plan: .init(units: [unit], rootExterns: [.init(alias: "bounded", crateName: "bounded", fingerprint: unit.fingerprint)], rootFeatures: []))
        XCTAssertEqual(try RustSemanticWorkspaceBuilder.build(context, sourceRoot: root).crates.count, 2)
        let chunk = Data(repeating: 32, count: 1024 * 1024)
        for index in 0..<8 { try chunk.write(to: lib.appending(path: "chunk\(index).rs")) }
        XCTAssertThrowsError(try RustSemanticWorkspaceBuilder.build(context, sourceRoot: root)) { error in
            XCTAssertTrue(error.localizedDescription.contains("8 MiB"), error.localizedDescription)
        }
        for index in 0..<8 { try FileManager.default.removeItem(at: lib.appending(path: "chunk\(index).rs")) }
        let recovered = try RustSemanticWorkspaceBuilder.build(context, sourceRoot: root)
        XCTAssertEqual(recovered.files.count, project.files.filter { $0.key.hasSuffix(".rs") }.count + 1)
        XCTAssertEqual(model.exportProject(), project, "Analysis must leave the editable project unchanged.")
    }
}

@MainActor
final class RustSemanticIntegrationTests: XCTestCase {
    func testControllerDiscardsResultsAfterSourceChangesAndCanRestart() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = CompilerViewModel(projectLibrary: ProjectLibrary(storageURL: root.appending(path: "recent.json")))
        model.createProject(name: "semantic-stale", template: .hello)
        model.source = "fn main(){let n=3;let x=n;}"
        let controller = RustSemanticInspectorController(); defer { controller.stop() }
        var invocation = RustSemanticInvocation(file: model.selectedFile, offset: 14, action: .hover, revision: model.workspaceRevision)
        await controller.prepare(model: model, invocation: invocation)
        let old = model.source
        model.source += "// changed"; model.source = old
        for _ in 0..<400 where controller.working { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertFalse(controller.working)
        XCTAssertNil(controller.result, "Even identical restored source has a different workspace generation")
        XCTAssertNil(controller.context)
        await controller.prepare(model: model, invocation: invocation)
        XCTAssertNil(controller.context)
        XCTAssertTrue(controller.message?.contains("before analysis opened") == true)
        invocation = .init(file: model.selectedFile, offset: 14, action: .hover, revision: model.workspaceRevision)
        await controller.prepare(model: model, invocation: invocation)
        for _ in 0..<400 where controller.working { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertTrue(controller.result?.hover?.text.contains("i32") == true, controller.message ?? "No result")
        controller.stop()
        XCTAssertNil(controller.context)
    }
    private func analyze(_ runtime: RustSemanticRuntime, _ workspace: RustSemanticWorkspace,
                         _ operation: String, file: String = "src/main.rs", offset: Int, name: String? = nil) async throws -> RustSemanticResult {
        var query: [String: Any] = ["op": operation, "file": file, "offset": offset]
        if let name { query["name"] = name }
        let graph = try JSONSerialization.jsonObject(with: JSONEncoder().encode(workspace))
        let payload = try JSONSerialization.data(withJSONObject: ["workspace": graph, "query": query])
        let response = try await runtime.perform(payload)
        return try JSONDecoder().decode(RustSemanticEnvelope.self, from: response).validated()
    }
    private func workspace(_ files: [String: String]) -> RustSemanticWorkspace {
        .init(files: files.keys.sorted().map { .init(path: $0, text: files[$0]!) },
              crates: [.init(root: "src/main.rs", dependencies: [:], edition: "2024", kind: "", name: "example", features: [])])
    }
    func testRealCrossFileNavigationScopedReferencesAndRename() async throws {
        let runtime = RustSemanticRuntime(); defer { runtime.releaseMemory() }
        let source = "mod helper;fn main(){let value=1;{let value=2;let inner=value;}let outer=value;let x=helper::answer();}// value stays in comment"
        let files = ["src/main.rs": source, "src/helper.rs": "pub fn answer()->i32{42}"]
        let graph = workspace(files)
        let value = try XCTUnwrap(source.range(of: "outer=value")).lowerBound.utf16Offset(in: source) + 6
        let references = try await analyze(runtime, graph, "references", offset: value)
        XCTAssertEqual(references.references?.count, 2)
        let renamed = try await analyze(runtime, graph, "rename", offset: value, name: "score")
        let proposal = try RustSemanticProposal(files: files, changes: renamed.files ?? [])
        XCTAssertTrue(proposal.after["src/main.rs"]?.contains("let score=1") == true)
        XCTAssertTrue(proposal.after["src/main.rs"]?.contains("let value=2;let inner=value") == true)
        XCTAssertTrue(proposal.after["src/main.rs"]?.hasSuffix("// value stays in comment") == true)
        let answer = try XCTUnwrap(source.range(of: "answer()" )).lowerBound.utf16Offset(in: source)
        let definition = try await analyze(runtime, graph, "definition", offset: answer)
        XCTAssertEqual(definition.targets?.first?.file, "src/helper.rs")
        let signature = try await analyze(runtime, graph, "signature", offset: answer + 7)
        XCTAssertTrue(signature.signature?.text.contains("answer") == true)
    }
    func testPreparedDependencyUsesExactSourcesAndReadOnlyDefinition() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let lib = root.appending(path: "dense-1.0.0/src"); try FileManager.default.createDirectory(at: lib, withIntermediateDirectories: true)
        try "pub struct Counter; impl Counter { pub fn total(&self)->usize{42} }".write(to: lib.appending(path: "lib.rs"), atomically: true, encoding: .utf8)
        let model = CompilerViewModel(projectLibrary: ProjectLibrary(storageURL: root.appending(path: "recent.json")))
        model.createProject(name: "semantic-dep", template: .hello)
        let project = model.exportProject()
        let source = "fn main(){let item=dense::Counter;item.tot;}"
        var unit = CargoBuildUnit(package: .init(name: "dense", version: try XCTUnwrap(SemanticVersion("1.0.0"))), fingerprint: "0123456789abcdef", crateName: "dense", edition: "2024", features: [], libraryPath: "src/lib.rs", source: .registry(directoryName: "dense-1.0.0"), externs: [], authors: "", description: "", repository: "", license: "MIT", homepage: "")
        var files = project.files; files[project.entryFile] = source
        var copy = project; copy.files = files
        let plan = CargoBuildPlan(units: [unit], rootExterns: [.init(alias: "dense", crateName: "dense", fingerprint: unit.fingerprint)], rootFeatures: [])
        let context = RustSemanticContext(project: copy, revision: .capture(project: copy, generation: 1, toolchainID: CargoToolchain.bundledVersion), edition: "2024", plan: plan)
        let graph = try RustSemanticWorkspaceBuilder.build(context, sourceRoot: root)
        let runtime = RustSemanticRuntime(); defer { runtime.releaseMemory() }
        let offset = try XCTUnwrap(source.range(of: "item.tot")).upperBound.utf16Offset(in: source)
        let completion = try await analyze(runtime, graph, "complete", file: project.entryFile, offset: offset)
        XCTAssertTrue(completion.items?.contains { $0.label == "total" } == true)
        XCTAssertFalse(completion.items?.contains { $0.label == "iter" } == true)
        let counter = try XCTUnwrap(source.range(of: "Counter")).lowerBound.utf16Offset(in: source)
        let definition = try await analyze(runtime, graph, "definition", file: project.entryFile, offset: counter)
        let target = try XCTUnwrap(definition.targets?.first)
        XCTAssertTrue(target.file.hasPrefix("__dep/"))
        let library = try await analyze(runtime, graph, "source", file: target.file, offset: target.range.start)
        XCTAssertEqual(library.readOnly, true)
        XCTAssertTrue(library.text?.contains("struct Counter") == true)
        unit.isProceduralMacro = true
        let rejected = RustSemanticContext(project: copy, revision: context.revision, edition: "2024", plan: .init(units: [unit], rootExterns: plan.rootExterns, rootFeatures: []))
        XCTAssertThrowsError(try RustSemanticWorkspaceBuilder.build(rejected, sourceRoot: root))
    }
    func testStopOrInvalidSourceDoesNotPoisonNextLocalAnalysis() async throws {
        let runtime = RustSemanticRuntime(); defer { runtime.releaseMemory() }
        let source = "fn main(){let n=3;let x=n;}"
        let graph = workspace(["src/main.rs": source])
        let query = Task { try await analyze(runtime, graph, "hover", offset: 14) }
        await Task.yield(); runtime.releaseMemory(); query.cancel()
        do { _ = try await query.value; XCTFail("Canceled analysis must not report success") } catch {}
        let good = try await analyze(runtime, graph, "hover", offset: 14)
        XCTAssertTrue(good.hover?.text.contains("i32") == true)
        do { _ = try await analyze(runtime, graph, "hover", offset: Int.max); XCTFail("Invalid offset accepted") } catch {}
        let recovered = try await analyze(runtime, graph, "hover", offset: 14)
        XCTAssertTrue(recovered.hover?.text.contains("i32") == true)
    }
}
