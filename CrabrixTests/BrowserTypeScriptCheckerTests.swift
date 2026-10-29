import XCTest
@testable import Crabrix

@MainActor
final class BrowserTypeScriptCheckerTests: XCTestCase {
    func testRealWorkerReportsAssignmentsArgumentsPropertiesAndUnicodePositions() async throws {
        let checker = BrowserTypeScriptChecker()
        let source = "const crab = '🦀'; const text: string = 42;\nfunction count(n:number){return n}; count('wrong');\nconst value={a:1}; value.missing;\n"
        let response = try await checker.check(files: ["main.ts": source], directory: "")
        let result = try XCTUnwrap(response)
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(Set(result.diagnostics.map(\.code)), ["TS2322", "TS2345", "TS2339"])
        let assignment = try XCTUnwrap(result.diagnostics.first { $0.code == "TS2322" })
        XCTAssertEqual(assignment.line, 1)
        XCTAssertEqual(assignment.column, (source as NSString).range(of: "text:").location + 1)
        let diagnostic = assignment.rustDiagnostic(files: ["main.ts": source])
        XCTAssertEqual(diagnostic.primarySpan?.fileName, "main.ts")
        XCTAssertFalse(checker.isWorking)
    }
    func testDOMTSXConfigAndLocalModuleResolutionUseActualCheckerSettings() async throws {
        let files = ["tsconfig.json": "{\"compilerOptions\":{\"jsx\":\"preserve\",\"strict\":false,\"baseUrl\":\".\",\"paths\":{\"@local/*\":[\"src/*\"]}},\"include\":[\"src\"]}",
            "src/main.tsx": "import {n} from '@local/helper'; declare global{namespace JSX{interface IntrinsicElements{button:{title:string}}}} function identity(value){return value}; const view=<button title={String(identity(n))}/>; document.title='local';",
            "src/helper.ts": "export const n=42;", "ignored.ts": "const n:number='wrong';"]
        let response = try await BrowserTypeScriptChecker().check(files: files, directory: "")
        let checked = try XCTUnwrap(response)
        XCTAssertTrue(checked.succeeded, checked.diagnostics.description)
        XCTAssertEqual(checked.roots, 2)
        XCTAssertEqual(BrowserTypeScriptProfile.directory(files: ["web/tsconfig.json":"{}"], entry: "web/index.html"), "web")
    }
    func testPreparedConditionalDeclarationsAndMissingTypesStayDistinct() async throws {
        let checker = BrowserTypeScriptChecker()
        let files = ["main.ts": "import {count} from 'dense'; count('wrong');",
            "node_modules/dense/package.json": "{\"name\":\"dense\",\"version\":\"1.0.0\",\"exports\":{\".\":{\"types\":\"./type.d.ts\",\"import\":\"./index.js\"}}}",
            "node_modules/dense/type.d.ts": "export function count(value:number):number;",
            "node_modules/dense/index.js": "export const count=x=>x;"]
        let response = try await checker.check(files: files, directory: "")
        let checked = try XCTUnwrap(response)
        XCTAssertEqual(checked.diagnostics.map(\.code), ["TS2345"])
        let missingResponse = try await checker.check(files: ["main.ts":"import {count} from 'unprepared'; count(1)"], directory: "")
        let missing = try XCTUnwrap(missingResponse)
        XCTAssertEqual(missing.diagnostics.map(\.code), ["TS2307"])
        XCTAssertEqual(missing.diagnostics.first?.kind, "missing-types")
    }
    func testRealPreparedReactDashboardChecksOfflineWithItsOriginalDependencyTypes() async throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "BrowserReactTypes", withExtension: "json"))
        let additions = try JSONDecoder().decode([String:String].self, from: Data(contentsOf: fixture))
        var files = try BrowserProjectBuilderTests.reactFiles().merging(additions) { _, new in new }
        let cache = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cache) }
        let builder = BrowserProjectBuilder(registry: BrowserNpmRegistry(cacheDirectory: cache))
        let bundle = try await builder.build(files: files, preferredEntry: "index.html")
        XCTAssertEqual(bundle.moduleCount, 133); XCTAssertEqual(bundle.packageCount, 8)
        let checker = BrowserTypeScriptChecker()
        var finished=false, heartbeats=0
        var largestGap=Duration.zero
        var previous=ContinuousClock.now
        let checking=Task { defer{finished=true};return try await checker.check(files:files,directory:"") }
        while !finished {
            try await Task.sleep(for:.milliseconds(10))
            let now=ContinuousClock.now;largestGap=max(largestGap,previous.duration(to:now));previous=now;heartbeats += 1
        }
        let response = try await checking.value
        XCTAssertGreaterThan(heartbeats,3,"The real checker must allow main-actor work while it analyzes the dependency graph")
        XCTAssertLessThan(largestGap,.seconds(1),"Type analysis must not block the UI actor")
        let checked = try XCTUnwrap(response)
        XCTAssertTrue(checked.succeeded, checked.diagnostics.map(\.message).joined(separator:"\n"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path), "Check and Build must not acquire missing packages")
        files["src/main.tsx"]! += "\nconst broken: ItemValue={id:1,name:8,count:2};\n"
        let rejected = try await checker.check(files: files, directory: "")
        XCTAssertTrue(rejected?.diagnostics.contains { $0.code == "TS2322" && $0.file == "src/main.tsx" } == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
    }
    func testOnlyExactSingleLegacyTypesArchiveRootIsAccepted() throws {
        XCTAssertEqual(try BrowserNpmRegistry.archiveRoot(packageName:"@types/react", paths:["react/package.json","react/index.d.ts"]),"react")
        XCTAssertEqual(try BrowserNpmRegistry.archiveRoot(packageName:"react", paths:["package/package.json"]),"package")
        XCTAssertThrowsError(try BrowserNpmRegistry.archiveRoot(packageName:"react", paths:["react/package.json"]))
        XCTAssertThrowsError(try BrowserNpmRegistry.archiveRoot(packageName:"@types/react", paths:["react/package.json","other/index.d.ts"]))
    }
    func testExplicitNpmPreparationRetainsRealTypesAndTheirDependencyClosureForOfflineCheck() async throws {
        let root=FileManager.default.temporaryDirectory.appending(path:UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let registry=BrowserNpmRegistry(cacheDirectory:root)
        let builder=BrowserProjectBuilder(registry:registry)
        let initial=["index.html":"<script type='module' src='./main.ts'></script>",
            "main.ts":"import type {CSSProperties} from 'react'; const style:CSSProperties={display:'grid'}; document.title=String(style.display);",
            "package.json":"{\"name\":\"typed-preparation\",\"devDependencies\":{\"@types/react\":\"19.2.2\",\"csstype\":\"3.1.3\"}}"]
        let prepared=try await builder.build(files:initial,preferredEntry:"index.html",preparePackages:true)
        XCTAssertEqual(prepared.packageCount,2)
        XCTAssertNotNil(prepared.sourceAdditions["node_modules/@types/react/index.d.ts"])
        XCTAssertNotNil(prepared.sourceAdditions["node_modules/csstype/index.d.ts"])
        XCTAssertTrue(prepared.sourceAdditions.keys.contains{$0.hasPrefix("node_modules/@types/react/") && $0.uppercased().hasSuffix("LICENSE")})
        let files=initial.merging(prepared.sourceAdditions){_,new in new}
        try ProjectFilePolicy.validate(files,entryFile:"index.html")
        try FileManager.default.removeItem(at:root)
        let offline=BrowserProjectBuilder(registry:BrowserNpmRegistry(cacheDirectory:root))
        _ = try await offline.build(files:files,preferredEntry:"index.html")
        let response=try await BrowserTypeScriptChecker().check(files:files,directory:"")
        let checked=try XCTUnwrap(response)
        XCTAssertTrue(checked.succeeded,checked.diagnostics.map(\.message).joined(separator:"\n"))
        XCTAssertFalse(FileManager.default.fileExists(atPath:root.path),"Offline Check must not reacquire archives after explicit preparation")
    }
    func testUnsupportedConfigAndCancellationReleaseTheWorkerAndPermitRecovery() async throws {
        let checker = BrowserTypeScriptChecker()
        do {
            _ = try await checker.check(files: ["main.ts":"let n=1", "tsconfig.json":"{\"references\":[{\"path\":\"./other\"}]}"], directory: "")
            XCTFail("Project references must be explicit")
        } catch { XCTAssertTrue(error.localizedDescription.contains("project references"), error.localizedDescription) }
        let pending = Task { try await checker.check(files: ["main.ts":"let n:number=42"], directory: "") }
        for _ in 0..<100 where !checker.isWorking { await Task.yield() }
        XCTAssertTrue(checker.isWorking)
        checker.cancel(); pending.cancel()
        do { _ = try await pending.value; XCTFail("Stopped checker must not report success") } catch { }
        XCTAssertFalse(checker.isWorking)
        let recoveryResponse = try await checker.check(files: ["main.ts":"const n:number=42; document.title=String(n);"], directory: "")
        let recovered = try XCTUnwrap(recoveryResponse)
        XCTAssertTrue(recovered.succeeded, recovered.diagnostics.description)
    }
    func testActualModelCheckRejectsTypeErrorAndRunKeepsItsIndependentBrowserBehavior() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = CompilerViewModel(projectLibrary: ProjectLibrary(storageURL: root.appending(path: "recent.json")))
        model.createProject(name: "typescript-check", template: .hello)
        let source = "const score: string=42; document.body.textContent=String(score);"
        XCTAssertTrue(model.replaceProjectFilesFromTerminal(["index.html":"<script type='module' src='./main.ts'></script>", "main.ts":source], selecting:"index.html"))
        model.check(); try await wait(model)
        XCTAssertFalse(model.result?.succeeded == true, model.result?.detail ?? "No result")
        XCTAssertEqual(model.result?.diagnostics.first?.code, "TS2322")
        XCTAssertEqual(model.result?.diagnostics.first?.primarySpan?.fileName, "main.ts")
        XCTAssertFalse(model.diagnosticAdviceState.isWorking, "TypeScript Check must not automatically lock Run behind optional AI advice")
        model.run(); try await wait(model)
        XCTAssertTrue(model.result?.succeeded == true, model.result?.detail ?? "Run failed")
        XCTAssertNotNil(model.result?.webPreview)
        model.selectFile("main.ts"); model.source=source.replacingOccurrences(of:"score: string",with:"score: number")
        model.check(); try await wait(model)
        XCTAssertTrue(model.result?.succeeded == true, model.result?.detail ?? "Check failed")
        XCTAssertEqual(model.lastBuild?.browserTypeCheckVersion, "5.9.3")
        let report=ProjectPreflight.inspect(model.preflightInput())
        XCTAssertEqual(report.operations.first { $0.kind == .check }?.state, .verified)
        XCTAssertEqual(report.operations.first { $0.kind == .run }?.state, .unverified)
        model.check(); model.source += "\n// a later edit"
        try await wait(model); XCTAssertNil(model.result)
    }
    func testBackgroundStopAlsoCancelsAQueuedCheckBeforeItsWorkerStarts() async throws {
        let root=FileManager.default.temporaryDirectory.appending(path:UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        let model=CompilerViewModel(projectLibrary:ProjectLibrary(storageURL:root.appending(path:"recent.json")))
        model.createProject(name:"background-check",template:.hello)
        let files=["index.html":"<script type='module' src='main.ts'></script>","main.ts":"const n:number=42; document.title=String(n);"]
        XCTAssertTrue(model.replaceProjectFilesFromTerminal(files,selecting:"index.html"))
        model.check(); model.stopTypeScriptForBackground()
        try await wait(model)
        XCTAssertFalse(model.result?.succeeded == true)
        XCTAssertTrue(model.canStartBuild)
        XCTAssertEqual(model.exportProject().files,files)
        model.check();try await wait(model)
        XCTAssertTrue(model.result?.succeeded == true,model.result?.detail ?? "No recovered Check")
    }
    func testUnsupportedCheckerConfigurationAlsoKeepsIndependentRunAvailable() async throws {
        let root=FileManager.default.temporaryDirectory.appending(path:UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        let model=CompilerViewModel(projectLibrary:ProjectLibrary(storageURL:root.appending(path:"recent.json")))
        model.createProject(name:"unsupported-types",template:.hello)
        XCTAssertTrue(model.replaceProjectFilesFromTerminal([
            "index.html":"<script type='module' src='main.ts'></script>","main.ts":"const n:number=42;document.title=String(n);",
            "tsconfig.json":"{\"references\":[{\"path\":\"./other\"}]}"
        ],selecting:"index.html"))
        model.check();try await wait(model)
        XCTAssertTrue(model.result?.detail.contains("project references") == true,model.result?.detail ?? "Missing config refusal")
        XCTAssertFalse(model.diagnosticAdviceState.isWorking)
        XCTAssertTrue(model.canStartBuild)
        model.run();try await wait(model)
        XCTAssertTrue(model.result?.succeeded == true,model.result?.detail ?? "Run did not recover")
    }
    private func wait(_ model: CompilerViewModel) async throws {
        let start=ContinuousClock.now
        while model.isBusy || model.isCompilerDraining {
            if start.duration(to:.now) > .seconds(60) { model.cancelBuild(); XCTFail("Local browser operation timed out"); return }
            try await Task.sleep(for:.milliseconds(25))
        }
    }
}
