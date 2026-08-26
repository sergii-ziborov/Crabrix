import XCTest
@testable import Crabrix

@MainActor
final class ProjectAuthoringTests: XCTestCase {
    func testNewProjectCreatesCargoLayout() {
        let model = CompilerViewModel()

        model.createProject(name: "My First Crab", template: .hello)
        let project = model.exportProject()

        XCTAssertEqual(project.name, "my-first-crab")
        XCTAssertEqual(project.entryFile, "src/main.rs")
        XCTAssertNotNil(project.files["Cargo.toml"])
        XCTAssertTrue(project.files["src/main.rs"]?.contains("Hello from my-first-crab") == true)
    }

    func testCreatesRustFileAndPersistentModuleFolder() {
        let model = CompilerViewModel()
        model.createProject(name: "tree-test", template: .empty)

        XCTAssertTrue(model.createRustFile(at: "src/state"))
        XCTAssertTrue(model.createModuleFolder(at: "src/ui"))

        let files = model.exportProject().files
        XCTAssertNotNil(files["src/state.rs"])
        XCTAssertNotNil(files["src/ui/mod.rs"])
    }

    func testCargoDependencyIsInsertedAndUpdated() {
        let model = CompilerViewModel()
        model.createProject(name: "cargo-test", template: .empty)

        XCTAssertTrue(model.addCargoDependency(name: "serde", requirement: "1.0"))
        XCTAssertTrue(model.addCargoDependency(name: "serde", requirement: "1.1"))

        let manifest = model.exportProject().files["Cargo.toml"] ?? ""
        XCTAssertTrue(manifest.contains("serde = \"1.1\""))
        XCTAssertFalse(manifest.contains("serde = \"1.0\""))
        XCTAssertEqual(CargoManifest.parse(manifest)?.dependencies.count, 1)
    }

    func testBundledProjectLibraryHasRunnableEntries() {
        XCTAssertGreaterThanOrEqual(RustShowcaseLibrary.projects.count, 4)
        for showcase in RustShowcaseLibrary.projects {
            XCTAssertNotNil(showcase.project.files[showcase.project.entryFile])
            XCTAssertNotNil(showcase.project.files["Cargo.toml"])
        }
    }
}
