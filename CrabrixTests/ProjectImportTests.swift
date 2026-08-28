import XCTest
@testable import Crabrix

final class ProjectImportTests: XCTestCase {
    func testLoadsCargoFolderAndIgnoresBuildArtifacts() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "CrabrixProjectTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appending(path: "src", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appending(path: "target", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        try Data(RustSamples.cargoManifest.utf8).write(to: root.appending(path: "Cargo.toml"))
        try Data(RustSamples.multiFileMain.utf8).write(to: root.appending(path: "src/main.rs"))
        try Data("ignored".utf8).write(to: root.appending(path: "target/output.txt"))

        let project = try LocalProjectLoader.load(from: root, provenance: .files())

        XCTAssertEqual(project.name, "modules-lab")
        XCTAssertEqual(project.entryFile, "src/main.rs")
        XCTAssertEqual(Set(project.files.keys), ["Cargo.toml", "src/main.rs"])
        XCTAssertEqual(project.provenance?.source, .files)
    }

    func testCompatibilityScannerFlagsDependenciesAndBuildScript() {
        let project = CrabrixProject(
            name: "scanner",
            files: [
                "Cargo.toml": """
                [package]
                name = "scanner"
                [dependencies]
                serde = "1"
                """,
                "src/main.rs": "fn main() {}",
                "build.rs": "fn main() {}",
            ],
            entryFile: "src/main.rs",
            provenance: nil
        )

        let report = ProjectCompatibilityReport.scan(project)
        XCTAssertEqual(report.status, .inspect)
        XCTAssertEqual(report.dependencies, 1)
        XCTAssertEqual(report.rustFiles, 2)
        // Registry dependencies are resolved by the package manager now, so the
        // only remaining note is the build script the local build does not run.
        XCTAssertEqual(report.notes, ["build.rs is not executed by the local build."])
    }

    func testRecentProjectLibraryPersistsBuildStatus() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "CrabrixLibraryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let storageURL = root.appending(path: "recent.json")
        let project = CrabrixProject(
            name: "recent-crab",
            files: ["main.rs": "fn main() {}"],
            entryFile: "main.rs",
            provenance: nil
        )
        let build = ProjectBuildRecord(
            result: CompilationResult(
                succeeded: true,
                phase: .run,
                exitCode: 0,
                diagnostics: [],
                stdout: "",
                stderr: "",
                duration: .milliseconds(250),
                detail: "passed"
            )
        )

        let writer = ProjectLibrary(storageURL: storageURL)
        _ = try await writer.record(project: project, lastBuild: build)
        let reader = ProjectLibrary(storageURL: storageURL)
        let items = try await reader.items()

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.project, project)
        XCTAssertEqual(items.first?.lastBuild?.succeeded, true)
        XCTAssertEqual(items.first?.lastBuild?.durationMilliseconds, 250)
    }

    func testSavedCrabrixPackageRoundTripsEditableFilesAndProvenance() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "Saved.crabrixproject", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let provenance = CrabrixProject.Provenance(
            source: .github,
            owner: "crabrix",
            repository: "demo",
            reference: "main",
            commit: nil,
            importedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let project = CrabrixProject(
            name: "demo",
            files: [
                "Cargo.toml": "[package]\nname = \"demo\"\n",
                "src/main.rs": "fn main() {}",
            ],
            entryFile: "src/main.rs",
            provenance: provenance
        )
        let wrapper = try CrabrixProjectDocument(project: project).packageWrapper()
        try wrapper.write(to: root, options: .atomic, originalContentsURL: nil)

        let loaded = try LocalProjectLoader.load(from: root)

        XCTAssertEqual(loaded.name, "demo")
        XCTAssertEqual(loaded.files, project.files)
        XCTAssertEqual(loaded.entryFile, "src/main.rs")
        XCTAssertEqual(loaded.provenance, provenance)
    }

    func testZipArchiveRoundTripsProjectFiles() throws {
        let project = CrabrixProject(
            name: "share-crab",
            files: [
                "Cargo.toml": "[package]\nname = \"share-crab\"\n",
                "src/main.rs": "fn main() { println!(\"shared\"); }",
                "src/lib.rs": "pub fn value() -> i32 { 7 }",
            ],
            entryFile: "src/main.rs",
            provenance: nil
        )
        let archiveURL = try CrabrixProjectArchive.create(project: project)
        defer { CrabrixProjectArchive.removeTemporaryArchive(at: archiveURL) }

        let loaded = try CrabrixProjectArchive.load(from: archiveURL)

        XCTAssertEqual(loaded.name, project.name)
        XCTAssertEqual(loaded.files, project.files)
        XCTAssertEqual(loaded.entryFile, project.entryFile)
    }
}
