import XCTest
@testable import Crabrix

final class ProjectPreflightTests: XCTestCase {
    private let manifest = "[package]\nname='preflight'\nversion='0.1.0'\nedition='2024'\n"
    private func input(_ files: [String: String], entry: String = "main.rs", graph: CargoWorkspaceSnapshot = .empty, current: Bool = false) -> ProjectPreflight.Input {
        let project = CrabrixProject(name: "preflight", files: files, entryFile: entry, provenance: nil)
        return .init(project: project, revision: .capture(project: project, generation: 4, toolchainID: "profile"), workspace: graph, graphIsCurrent: current, lastBuild: nil)
    }
    func testInspectionNeverTurnsSourceOrMetadataIntoRunProof() {
        let snapshot = input(["main.rs": "fn main(){}"])
        let report = ProjectPreflight.inspect(snapshot)
        XCTAssertEqual(report.operations.count, 4)
        XCTAssertTrue(report.operations.allSatisfy { $0.state == .unverified })
        XCTAssertEqual(report.edition, "2024")
        let result = CompilationResult(succeeded: true, phase: .check, exitCode: 0, diagnostics: [], stdout: "", stderr: "", duration: .zero, detail: "checked")
        let record = ProjectBuildRecord(result: result, sourceTreeHash: snapshot.revision.sourceTreeHash, toolchainID: "profile", isDebugExecution: false)
        let checked = ProjectPreflight.inspect(.init(project: snapshot.project, revision: snapshot.revision, workspace: .empty, graphIsCurrent: false, lastBuild: record))
        XCTAssertEqual(checked.operations.first { $0.kind == .check }?.state, .verified)
        XCTAssertEqual(checked.operations.first { $0.kind == .run }?.state, .unverified)
    }
    func testCustomLibraryTargetCanBuildButCannotRunAndIsNeverSubstituted() {
        let files = ["Cargo.toml": manifest + "[lib]\npath='src/engine.rs'\n", "src/engine.rs": "pub fn value()->u32{42}"]
        let library = ProjectPreflight.inspect(input(files, entry: "src/engine.rs"))
        XCTAssertNil(library.blockingReason(for: .check))
        XCTAssertNil(library.blockingReason(for: .build))
        XCTAssertNotNil(library.blockingReason(for: .run))
        var dynamic = files; dynamic["Cargo.toml"]! += "crate-type=['cdylib']\n"
        XCTAssertNotNil(ProjectPreflight.inspect(input(dynamic, entry: "src/engine.rs")).blockingReason(for: .build))
    }
    func testManifestFailuresStopBeforeCompilerAndBuildFalseAndTargetsAreRespected() {
        for text in ["[workspace]\nmembers=['a']\n", manifest + "rust-version='99.0'\n", "[package]\nname=\""] {
            let report = ProjectPreflight.inspect(input(["main.rs": "fn main(){}", "Cargo.toml": text]))
            XCTAssertTrue(ProjectVerifiedOperation.allCases.allSatisfy { report.blockingReason(for: $0) != nil })
        }
        let script = ["main.rs": "fn main(){}", "build.rs": "fn main(){}", "Cargo.toml": manifest + "[build-dependencies]\nsyn='2'\n"]
        XCTAssertNotNil(ProjectPreflight.inspect(input(script)).blockingReason(for: .check))
        var disabled = script; disabled["Cargo.toml"] = manifest + "build=false\n[build-dependencies]\nsyn='2'\n"
        XCTAssertNil(ProjectPreflight.inspect(input(disabled)).blockingReason(for: .check))
        var windows = script; windows["Cargo.toml"] = manifest + "[target.'cfg(windows)'.build-dependencies]\nsyn='2'\n"
        XCTAssertNil(ProjectPreflight.inspect(input(windows)).blockingReason(for: .check))
    }
    func testOnlyCurrentGraphMaySupplyPackageReasonsOrFeatures() {
        var graph = CargoWorkspaceSnapshot.empty
        graph.packages = [.init(package: .init(name: "native-demo", version: .init(major: 1, minor: 0, patch: 0)), checksum: "abc", features: ["native"], compatibility: .unsupported("links the native library example"), isDownloaded: true, isLocallyPatched: false, isDirect: true)]
        graph.plan = .init(units: [], rootExterns: [], rootFeatures: ["web"])
        let files = ["main.rs": "fn main(){}", "Cargo.toml": manifest + "[dependencies]\nexample='1'\n"]
        let stale = ProjectPreflight.inspect(input(files, graph: graph))
        XCTAssertNil(stale.blockingReason(for: .build)); XCTAssertNil(stale.features)
        let exact = ProjectPreflight.inspect(input(files, graph: graph, current: true))
        XCTAssertTrue(exact.blockingReason(for: .build)?.contains("links the native library example") == true)
        XCTAssertEqual(exact.features, ["web"])
    }
    func testCompilerDefectIsReportedWithoutBeingReclassifiedAsAPlatformRestriction() {
        let reason = "backend lowering failed: umulhi is unimplemented"
        let compatibility = CrateCompatibility.recorded(.failed(reason))
        XCTAssertEqual(compatibility, .buildFailed(reason))
        XCTAssertFalse(compatibility.isBlocking)
        XCTAssertEqual(CrateCompatibility.recorded(.checked), .checkVerified)
        XCTAssertEqual(CrateCompatibility.recorded(.built), .verified)
        var graph = CargoWorkspaceSnapshot.empty
        graph.packages = [.init(package: .init(name: "pure-rust", version: .init(major: 1, minor: 0, patch: 0)), checksum: "abc", features: [], compatibility: compatibility, isDownloaded: true, isLocallyPatched: false, isDirect: true)]
        let report = ProjectPreflight.inspect(input(["main.rs": "fn main(){}", "Cargo.toml": manifest], graph: graph, current: true))
        XCTAssertNil(report.blockingReason(for: .build))
        XCTAssertTrue(report.issues.contains { $0.origin == .evidence && $0.detail.contains(reason) })
    }
    func testCargoOverridesAreNotSilentlyIgnoredEvenWithoutManifest() {
        let base = ["main.rs": "fn main(){}"]
        for config in ["[build]\ntarget='x86_64-unknown-linux-gnu'", "[env]\nFEATURE='enabled'", "[target.wasm32-wasip1]\nrustflags=['--cfg','custom']"] {
            XCTAssertNotNil(ProjectPreflight.inspect(input(base.merging([".cargo/config.toml": config]) { _, b in b })).blockingReason(for: .run))
        }
        for config in ["# comment only", "[alias]\nb='build'", "[target.'cfg(windows)']\nlinker='windows-linker'"] {
            XCTAssertNil(ProjectPreflight.inspect(input(base.merging([".cargo/config.toml": config]) { _, b in b })).blockingReason(for: .run))
        }
    }
    func testBrowserTranspilationNeverClaimsTypeCheckOrJavaScriptExecution() {
        let snapshot = input(["index.html": "<html></html>"], entry: "index.html")
        let value = CompilationResult(succeeded: true, phase: .run, exitCode: nil, diagnostics: [], stdout: "", stderr: "", duration: .zero, detail: "preview opened")
        let result = ProjectBuildRecord(result: value, sourceTreeHash: snapshot.revision.sourceTreeHash, toolchainID: "profile", isDebugExecution: false)
        let report = ProjectPreflight.inspect(.init(project: snapshot.project, revision: snapshot.revision, workspace: .empty, graphIsCurrent: false, lastBuild: result))
        XCTAssertEqual(report.operations.first { $0.kind == .run }?.state, .unverified)
        XCTAssertTrue(report.operations.first { $0.kind == .check }?.title.contains("syntax and bundle") == true)
        XCTAssertEqual(report.operations.first { $0.kind == .debug }?.state, .blocked)
        XCTAssertNotEqual(ProjectExecutionProfile.browserIdentity, "unavailable")
    }
}
