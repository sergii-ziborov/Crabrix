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

        model.createProject(name: "visual-crab", template: .visual)
        project = model.exportProject()
        XCTAssertEqual(project.kind, .visual)
        XCTAssertTrue(
            project.files["src/main.rs"]?.contains(RustCanvasOutput.marker)
                == true
        )
    }

    func testNewProjectPersistsOrganizationMetadata() {
        let model = CompilerViewModel()
        model.createProject(
            NewRustProjectRequest(
                name: "Borrow Notebook",
                template: .modules,
                projectDescription: "Experiments with shared references",
                folder: "Learning",
                tags: ["Borrowing", "practice", "borrowing"],
                kind: .experiment
            )
        )

        let project = model.exportProject()
        XCTAssertEqual(project.name, "borrow-notebook")
        XCTAssertEqual(project.projectDescription, "Experiments with shared references")
        XCTAssertEqual(project.folder, "Learning")
        XCTAssertEqual(project.tags, ["borrowing", "practice"])
        XCTAssertEqual(project.kind, .experiment)
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
        XCTAssertEqual(RustShowcaseLibrary.projects.count, 46)
        XCTAssertEqual(Set(RustShowcaseLibrary.projects.map(\.id)).count, 46)
        XCTAssertGreaterThanOrEqual(
            RustShowcaseLibrary.projects.filter(\.isGuided).count,
            26
        )
        XCTAssertEqual(
            RustShowcaseLibrary.projects.filter(\.isVisual).count,
            6
        )
        for showcase in RustShowcaseLibrary.projects {
            XCTAssertNotNil(showcase.project.files[showcase.project.entryFile])
            XCTAssertNotNil(showcase.project.files["Cargo.toml"])
        }
        for showcase in RustShowcaseLibrary.projects.filter(\.isVisual) {
            XCTAssertEqual(showcase.project.kind, .visual)
            XCTAssertEqual(showcase.project.folder, "Visual Gallery")
            XCTAssertNotNil(showcase.project.files["README.md"])
        }
    }

    func testSwitchingFilesPreservesRevisionAndUnsavedEdits() {
        let model = CompilerViewModel()
        model.createProject(name: "navigation", template: .modules)
        model.source += "\n// unsaved main edit"
        let revision = model.workspaceRevision
        let files = model.exportProject().files

        model.selectFile("src/greeter.rs")
        XCTAssertEqual(model.selectedFile, "src/greeter.rs")
        XCTAssertEqual(model.workspaceRevision, revision)
        XCTAssertEqual(model.exportProject().files, files)
        model.source += "\n// helper edit"
        XCTAssertNotEqual(model.workspaceRevision, revision)
        model.selectFile("src/main.rs")
        XCTAssertEqual(model.source, files["src/main.rs"])
        XCTAssertTrue(model.exportProject().files["src/greeter.rs"]?.contains("helper edit") == true)
    }

    func testRemovingTheLastDependencyUpdatesSelectedManifestAndLockfile() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "removal-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let model = CompilerViewModel(projectLibrary: ProjectLibrary(storageURL: root.appending(path: "projects.json")))
        model.createProject(name: "remove-test", template: .empty)
        let source = """
        [package]
        name = "remove-test"
        version = "0.1.0"
        edition = "2024"
        [dependencies]
        hashbrown = "=0.17.1"
        """
        var files = model.exportProject().files
        files["Cargo.toml"] = source
        files["Cargo.lock"] = """
        version = 4
        [[package]]
        name = "remove-test"
        version = "0.1.0"
        dependencies = ["hashbrown"]
        [[package]]
        name = "hashbrown"
        version = "0.17.1"
        source = "registry+https://github.com/rust-lang/crates.io-index"
        checksum = "\(String(repeating: "0", count: 64))"
        """
        _ = try CargoLockfile.parseValidated(try XCTUnwrap(files["Cargo.lock"]))
        XCTAssertTrue(model.replaceProjectFilesFromTerminal(files, selecting: "Cargo.toml"))
        XCTAssertTrue(model.removeCargoDependency(name: "hashbrown"))
        XCTAssertTrue(model.cargoManifest?.dependencies.isEmpty == true)
        XCTAssertEqual(model.source, model.cargoManifestSource)
        XCTAssertEqual(model.exportProject().files["src/main.rs"], files["src/main.rs"])
        XCTAssertFalse(model.removeCargoDependency(name: "missing"))

        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while model.exportProject().files["Cargo.lock"]?.contains("hashbrown") == true,
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertFalse(model.exportProject().files["Cargo.lock"]?.contains("hashbrown") == true, "\(model.cargoStage)")
        XCTAssertTrue(model.cargoWorkspace.packages.isEmpty)
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

    func testLessonAnswerAndReviewStateSurviveTheExpectedTransitions() {
        let suite = "crabrix.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let first = CompilerViewModel(userDefaults: defaults)

        first.recordLessonAnswer(2, for: "hello-rust")
        first.recordLessonAnswer(0, for: "hello-rust")
        first.beginLesson("hello-rust", isReview: true)

        XCTAssertEqual(first.lessonAnswerIndices["hello-rust"], 2)
        XCTAssertTrue(first.activeLessonIsReview)
        XCTAssertFalse(first.earnsProgressForCurrentRun)

        let reopened = CompilerViewModel(userDefaults: defaults)
        XCTAssertEqual(reopened.lessonAnswerIndices["hello-rust"], 2)
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
