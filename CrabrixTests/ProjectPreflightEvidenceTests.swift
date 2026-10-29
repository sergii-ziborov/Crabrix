import XCTest
@testable import Crabrix

final class ProjectPreflightEvidenceTests: XCTestCase {
    private let project = CrabrixProject(name: "preflight", files: ["main.rs": "fn main() {}"], entryFile: "main.rs", provenance: nil)
    private func revision(_ compiler: String = "compiler-a", resources: String? = "resources-a") -> WorkspaceRevision {
        .capture(project: project, generation: 7, toolchainID: compiler, resourceTreeHash: resources)
    }
    private func record(_ phase: CompilationResult.Phase, debug: Bool? = nil, succeeded: Bool = true) -> ProjectBuildRecord {
        let source = revision()
        return .init(result: .init(succeeded: succeeded, phase: phase, exitCode: succeeded ? 0 : 1, diagnostics: [], stdout: "", stderr: "", duration: .zero, detail: "fixture"),
            sourceTreeHash: source.sourceTreeHash, toolchainID: source.toolchainID, resourceTreeHash: source.resourceTreeHash, isDebugExecution: debug)
    }
    func testMetadataCheckNeverClaimsLinkOrExecutionAndUserToolsAreSeparate() {
        let checked = record(.check)
        XCTAssertTrue(checked.verifies(.check, revision: revision()))
        for operation in [ProjectVerifiedOperation.build, .run, .debug] { XCTAssertFalse(checked.verifies(operation, revision: revision())) }
        for phase in [CompilationResult.Phase.test, .format, .setup] {
            for operation in ProjectVerifiedOperation.allCases { XCTAssertFalse(record(phase).verifies(operation, revision: revision())) }
        }
        XCTAssertTrue(record(.compile).verifies(.build, revision: revision()))
        XCTAssertFalse(record(.compile).verifies(.run, revision: revision()))
    }
    func testOrdinaryRunAndDebugProofCannotSubstituteForEachOther() {
        XCTAssertTrue(record(.run, debug: false).verifies(.run, revision: revision()))
        XCTAssertFalse(record(.run, debug: false).verifies(.debug, revision: revision()))
        XCTAssertTrue(record(.run, debug: true).verifies(.debug, revision: revision()))
        for operation in [ProjectVerifiedOperation.check, .build, .run] { XCTAssertFalse(record(.run, debug: true).verifies(operation, revision: revision())) }
        XCTAssertFalse(record(.run, debug: false, succeeded: false).verifies(.run, revision: revision()))
    }
    func testLegacyAmbiguousExecutionAndChangedIdentityStayUnverified() throws {
        let identity = revision()
        let oldPayload: [String: Any] = ["succeeded": true, "phase": "run", "durationMilliseconds": 12,
            "finishedAt": 0, "sourceTreeHash": identity.sourceTreeHash,
            "toolchainID": identity.toolchainID, "resourceTreeHash": "resources-a"]
        let legacy = try JSONDecoder().decode(ProjectBuildRecord.self, from: JSONSerialization.data(withJSONObject: oldPayload))
        XCTAssertNil(legacy.isDebugExecution)
        XCTAssertFalse(legacy.verifies(.run, revision: revision()))
        XCTAssertFalse(legacy.verifies(.debug, revision: revision()))
        let executed = record(.run, debug: false)
        XCTAssertFalse(executed.verifies(.run, revision: revision("compiler-b")))
        XCTAssertFalse(executed.verifies(.run, revision: revision(resources: "resources-b")))
        var changed = project; changed.files["main.rs"] = "fn main(){println!(\"new\");}"
        XCTAssertFalse(executed.verifies(.run, revision: .capture(project: changed, generation: 8, toolchainID: "compiler-a", resourceTreeHash: "resources-a")))
    }
}

@MainActor
final class ProjectPreflightCompilerEvidenceTests: XCTestCase {
    func testActualModelKeepsDebugCheckAndOrdinaryRunEvidenceDistinct() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = ProjectLibrary(storageURL: root.appending(path: "recent.json"))
        let model = CompilerViewModel(projectLibrary: library)
        model.createProject(name: "preflight-proof", template: .hello)
        model.source = "fn main() {\n    let mut word = String::from(\"crab\");\n    word.push('!');\n    println!(\"{word}\");\n}\n"
        XCTAssertTrue(model.canStartBuild)
        model.toggleDebugBreakpoint(file: model.selectedFile, line: 3)
        model.debug()
        var observedPause = false
        let start = ContinuousClock.now
        while model.isBusy || model.isCompilerDraining {
            guard start.duration(to: .now) < .seconds(90) else { model.cancelBuild(); XCTFail("Local Debug did not finish"); return }
            if model.debugPause != nil { observedPause = true; model.resumeDebug(.continue) }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(observedPause)
        XCTAssertTrue(model.result?.succeeded == true, model.result?.detail ?? "No Debug result")
        XCTAssertEqual(model.result?.stdout, "crab!\n")
        XCTAssertEqual(model.lastBuild?.isDebugExecution, true)
        XCTAssertTrue(model.lastBuild?.verifies(.debug, revision: model.workspaceRevision) == true)
        XCTAssertFalse(model.lastBuild?.verifies(.run, revision: model.workspaceRevision) == true)
        await model.retryProjectSave()
        let saved = try await library.items()
        XCTAssertEqual(saved.first { $0.id == model.projectID }?.lastBuild?.isDebugExecution, true)
        model.check()
        try await wait(model)
        XCTAssertTrue(model.result?.succeeded == true, model.result?.detail ?? "No Check result")
        XCTAssertTrue(model.lastBuild?.verifies(.check, revision: model.workspaceRevision) == true)
        XCTAssertFalse(model.lastBuild?.verifies(.run, revision: model.workspaceRevision) == true)
        model.run()
        try await wait(model)
        XCTAssertTrue(model.result?.succeeded == true, model.result?.detail ?? "No Run result")
        XCTAssertEqual(model.result?.stdout, "crab!\n")
        XCTAssertEqual(model.lastBuild?.isDebugExecution, false)
        XCTAssertTrue(model.lastBuild?.verifies(.run, revision: model.workspaceRevision) == true)
        XCTAssertFalse(model.lastBuild?.verifies(.debug, revision: model.workspaceRevision) == true)
    }
    private func wait(_ model: CompilerViewModel) async throws {
        let start = ContinuousClock.now
        while model.isBusy || model.isCompilerDraining {
            guard start.duration(to: .now) < .seconds(90) else { model.cancelBuild(); XCTFail("Local operation did not finish"); return }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
