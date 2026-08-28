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

    func testProjectTemplatesProvideDistinctRunnableLayouts() {
        let model = CompilerViewModel()

        model.createProject(name: "module-crab", template: .modules)
        var project = model.exportProject()
        XCTAssertNotNil(project.files["src/greeter.rs"])
        XCTAssertTrue(project.files["src/main.rs"]?.contains("mod greeter") == true)

        model.createProject(name: "cli-crab", template: .cli)
        project = model.exportProject()
        XCTAssertTrue(project.files["src/main.rs"]?.contains("env::args") == true)
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

    func testReviewLabCanUseAFreshProjectWithoutReusingTheOriginalName() {
        let model = CompilerViewModel(
            userDefaults: UserDefaults(suiteName: "crabrix.tests.\(UUID().uuidString)")!
        )
        model.source = "fn main() { /* completed solution */ }"

        model.loadRunnableSample(projectName: "review-hello-rust")

        XCTAssertEqual(model.projectName, "review-hello-rust")
        XCTAssertEqual(model.source, RustSamples.runnable)
    }
}

@MainActor
final class CargoTemplateTests: XCTestCase {
    func testPackagesTemplateWritesResolvableRegistryDependencies() throws {
        let model = CompilerViewModel(
            userDefaults: UserDefaults(suiteName: "crabrix.tests.\(UUID().uuidString)")!
        )
        model.createProject(name: "Package Demo", template: .packages)

        XCTAssertEqual(model.projectName, "package-demo")
        XCTAssertEqual(model.selectedFile, "src/main.rs")
        XCTAssertTrue(model.source.contains("smallvec::SmallVec"))

        let manifestSource = try XCTUnwrap(model.cargoManifestSource)
        let manifest = try CratePackageManifest.parse(manifestSource)
        XCTAssertEqual(manifest.packageName, "package-demo")
        XCTAssertEqual(manifest.edition, "2024")

        let dependencies = manifest.registryDependencies(for: .wasm32WasiP1)
        XCTAssertEqual(dependencies.map(\.alias).sorted(), ["log", "smallvec"])
        // Every template dependency must be a plain registry requirement, or the
        // resolver has nothing to look up.
        XCTAssertTrue(dependencies.allSatisfy(\.isRegistry))
        XCTAssertTrue(dependencies.allSatisfy { $0.requirement != nil })
    }

    func testEveryTemplateProducesAParsableManifest() throws {
        for template in RustProjectTemplate.allCases {
            let model = CompilerViewModel(
                userDefaults: UserDefaults(suiteName: "crabrix.tests.\(UUID().uuidString)")!
            )
            model.createProject(name: "t-\(template.rawValue)", template: template)
            let manifestSource = try XCTUnwrap(
                model.cargoManifestSource,
                "\(template.rawValue) has no Cargo.toml"
            )
            let manifest = try CratePackageManifest.parse(manifestSource)
            XCTAssertFalse(manifest.packageName.isEmpty, "\(template.rawValue)")
            XCTAssertFalse(manifest.isVirtualWorkspace, "\(template.rawValue)")
        }
    }
}
