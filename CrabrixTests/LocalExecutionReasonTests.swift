import XCTest
@testable import Crabrix

final class LocalExecutionReasonTests: XCTestCase {
    private let manifest = "[package]\nname='reason-test'\nversion='0.1.0'\nedition='2024'\n"
    private func report(_ files: [String: String], graph: CargoWorkspaceSnapshot = .empty, current: Bool = false) -> ProjectPreflight {
        let project = CrabrixProject(name: "reasons", files: files, entryFile: "main.rs", provenance: nil)
        return .inspect(.init(project: project, revision: .capture(project: project, generation: 1, toolchainID: "reasons"), workspace: graph, graphIsCurrent: current, lastBuild: nil))
    }
    func testCurrentGraphRetainsSourceAssignedReasonAndExactPackage() {
        var graph = CargoWorkspaceSnapshot.empty
        graph.packages = [.init(package: .init(name: "foreign", version: .init(major: 1, minor: 2, patch: 3)), checksum: "abc", features: ["ffi"], compatibility: .unsupported("translated diagnostic", code: .nativeLinkMetadata), isDownloaded: true, isLocallyPatched: false, isDirect: true)]
        let files = ["main.rs":"fn main(){}", "Cargo.toml":manifest+"[dependencies]\nforeign='1'\n"]
        let exact = report(files, graph: graph, current: true)
        let reason = exact.issues.first { $0.code == .nativeLinkMetadata }
        XCTAssertEqual(reason?.subject, "foreign 1.2.3")
        XCTAssertEqual(reason?.code.category, .requirement)
        XCTAssertTrue(reason?.blocked.contains(.build) == true)
        XCTAssertNotNil(reason?.nextStep)
        XCTAssertFalse(report(files, graph: graph).issues.contains { $0.code == .nativeLinkMetadata })
    }
    func testCompilerTextCannotTurnFailureIntoPlatformRequirement() {
        let attempt = CrateCompatibility.recorded(.failed("native library cuda proc_macro unavailable: compiler error"))
        XCTAssertEqual(attempt.reasonCode, .previousCompilerFailure)
        XCTAssertFalse(attempt.isBlocking)
        XCTAssertEqual(attempt.reasonCode?.category, .previousAttempt)
        let unknown = CrateCompatibility.unsupported("unclassified translated requirement")
        XCTAssertEqual(unknown.reasonCode, .unspecifiedRequirement)
    }
    func testManifestScriptAndConfigReasonsKeepTheirActualSubjects() {
        let files = ["main.rs":"fn main(){}", "build.rs":"fn main(){}", "Cargo.toml":manifest+"[build-dependencies]\nhelper='1'\n"]
        let script = report(files).issues.first { $0.code == .buildDependencyGraph }
        XCTAssertEqual(script?.subject, "build.rs")
        XCTAssertTrue(script?.blocked.contains(.run) == true)
        let config = report(["main.rs":"fn main(){}", ".cargo/config.toml":"[build]\ntarget='other-target'"])
        XCTAssertEqual(config.issues.first { $0.code == .cargoConfiguration }?.subject, ".cargo/config.toml")
        let version = report(["main.rs":"fn main(){}", "Cargo.toml":manifest+"rust-version='99.0'\n"])
        XCTAssertEqual(version.issues.first { $0.code == .minimumRustVersion }?.subject, "Cargo.toml")
    }
    func testBadFileAndBadManifestDoNotBecomeCompilerFailures() {
        let files = report(["main.rs":"fn main(){}", "../escape":"text"])
        XCTAssertEqual(files.issues.first { $0.code == .invalidFiles }?.subject, "../escape")
        XCTAssertFalse(files.filesAccepted)
        let bad = report(["main.rs":"fn main(){}", "Cargo.toml":"[package]\nname=\""])
        XCTAssertEqual(bad.issues.first { $0.code == .invalidManifest }?.subject, "Cargo.toml")
        XCTAssertFalse(bad.issues.contains { $0.code == .previousCompilerFailure })
    }
    func testTerminalTreeCarriesStableCodeWithoutGuessingFromNames() {
        let project = CrabrixProject(name: "tree", files: ["main.rs":"fn main(){}"], entryFile: "main.rs", provenance: nil)
        var graph = CargoWorkspaceSnapshot.empty
        graph.packages = [.init(package: .init(name: "ordinary", version: .init(major: 1, minor: 0, patch: 0)), checksum: "abc", features: [], compatibility: .unsupported("reason", code: .proceduralMacroHost), isDownloaded: true, isLocallyPatched: false, isDirect: true)]
        XCTAssertTrue(ProjectTerminalSession.renderTree(project: project, workspace: graph).contains("unsupported:procedural-macro-host"))
        graph.packages = [.init(package: .init(name: "cuda", version: .init(major: 1, minor: 0, patch: 0)), checksum: "abc", features: [], compatibility: .expected, isDownloaded: true, isLocallyPatched: false, isDirect: true)]
        XCTAssertFalse(ProjectTerminalSession.renderTree(project: project, workspace: graph).contains("unsupported:"))
    }
}
