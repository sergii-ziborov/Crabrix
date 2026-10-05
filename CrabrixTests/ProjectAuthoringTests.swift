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

    func testCreatesNestedFilesAndFoldersWithoutClobberingExistingPaths() {
        let model = CompilerViewModel()
        model.createProject(name: "nested-tree", template: .empty)

        XCTAssertTrue(model.createModuleFolder(at: "src/ui/widgets"))
        XCTAssertTrue(model.createRustFile(at: "src/ui/widgets/button"))
        XCTAssertTrue(model.createTextFile(at: "docs/guides/README.md"))
        XCTAssertFalse(model.createTextFile(at: "src/ui/widgets"))
        XCTAssertFalse(model.createModuleFolder(at: "docs/guides/README.md/other"))

        let files = model.exportProject().files
        XCTAssertNotNil(files["src/ui/widgets/mod.rs"])
        XCTAssertNotNil(files["src/ui/widgets/button.rs"])
        XCTAssertEqual(files["docs/guides/README.md"], "")
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

    func testCatalogAddsSynWithExplicitLocalCompilerFeatures() throws {
        let model = CompilerViewModel()
        model.createProject(name: "syn-parser", template: .empty)

        XCTAssertTrue(model.addCargoDependency(name: "syn", requirement: "3.0.6"))

        let source = try XCTUnwrap(model.exportProject().files["Cargo.toml"])
        let manifest = try CratePackageManifest.parse(source)
        let dependency = try XCTUnwrap(manifest.dependencies.first { $0.alias == "syn" })
        XCTAssertFalse(dependency.usesDefaultFeatures)
        XCTAssertEqual(Set(dependency.features), Set(["derive", "parsing", "printing", "clone-impls"]))
    }

    func testExistingPlainSynDependencyCanBeRepairedInProject() throws {
        let model = CompilerViewModel()
        model.createProject(name: "weather-station", template: .empty)
        XCTAssertTrue(model.addCargoDependency(name: "syn", requirement: "3.0.6"))
        model.selectFile("Cargo.toml")
        model.source = model.source.replacingOccurrences(
            of: CargoManifestEditor.localCompilerDeclaration(name: "syn", requirement: "3.0.6"),
            with: "syn = \"3.0.6\""
        )

        XCTAssertTrue(model.useSynParserFeatures())

        let manifest = try CratePackageManifest.parse(
            XCTUnwrap(model.exportProject().files["Cargo.toml"])
        )
        let dependency = try XCTUnwrap(manifest.dependencies.first { $0.alias == "syn" })
        XCTAssertFalse(dependency.usesDefaultFeatures)
        XCTAssertEqual(Set(dependency.features), Set(["derive", "parsing", "printing", "clone-impls"]))
    }

    func testInstalledAcademyExamplesHaveRunnableEntries() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try await CourseBootstrap(
            bundle: .main, root: root, appVersion: SemanticVersion("1.1")
        ).activateBundledBaseline()
        let projects = repository.showcaseProjects()
        XCTAssertEqual(projects.count, 46)
        XCTAssertEqual(Set(projects.map(\.id)).count, 46)
        XCTAssertGreaterThanOrEqual(
            projects.filter(\.isGuided).count,
            26
        )
        XCTAssertEqual(
            projects.filter(\.isVisual).count,
            6
        )
        for showcase in projects {
            XCTAssertNotNil(showcase.project.files[showcase.project.entryFile])
            XCTAssertNotNil(showcase.project.files["Cargo.toml"])
        }
        for showcase in projects.filter(\.isVisual) {
            XCTAssertEqual(showcase.project.kind, .visual)
            XCTAssertEqual(showcase.project.folder, "Visual Gallery")
            XCTAssertNotNil(showcase.project.files["README.md"])
        }
        let example = try XCTUnwrap(projects.first)
        let model = CompilerViewModel(projectLibrary: ProjectLibrary(
            storageURL: root.appending(path: "projects.json")
        ))
        model.openAcademyExample(example, contentVersion: "1.0.1")
        let firstCopy = model.exportProject()
        XCTAssertNotEqual(firstCopy.id, example.project.id)
        XCTAssertEqual(firstCopy.provenance?.course?.courseID, "projects")
        XCTAssertEqual(firstCopy.provenance?.course?.contentVersion, "1.0.1")
        let expectedHash = CourseProjectTemplate(
            name: example.project.name, entryFile: example.project.entryFile,
            files: example.project.files
        ).templateHash
        XCTAssertEqual(firstCopy.provenance?.course?.templateHash, expectedHash)
        model.source += "\n// local change"
        XCTAssertNotEqual(model.exportProject().files, example.project.files)
        model.openAcademyExample(example, contentVersion: "1.0.1")
        XCTAssertNotEqual(model.exportProject().id, firstCopy.id)
        let guided = try XCTUnwrap(projects.first(where: \.isGuided))
        model.openAcademyExample(guided, courseID: "examples", contentVersion: "1.0.0")
        let separateCopy = model.exportProject()
        XCTAssertEqual(separateCopy.provenance?.course?.courseID, "examples")
        XCTAssertEqual(separateCopy.provenance?.course?.contentVersion, "1.0.0")
        XCTAssertEqual(separateCopy.files["README.md"], guided.project.files["README.md"])
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

    func testResetCourseProgressKeepsOtherCourseAndProject() {
        let suite = "crabrix.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = CompilerViewModel(userDefaults: defaults)
        let projectID = model.projectID
        model.completeLesson("basics-1")
        model.completeLesson("ownership-1")
        model.recordLessonAnswer(1, for: "basics-1")
        model.recordLessonAnswer(2, for: "ownership-1")
        model.beginLesson("basics-1", isReview: true)

        model.resetCourseProgress(lessonIDs: ["basics-1"])

        XCTAssertFalse(model.completedLessonIDs.contains("basics-1"))
        XCTAssertTrue(model.completedLessonIDs.contains("ownership-1"))
        XCTAssertNil(model.lessonAnswerIndices["basics-1"])
        XCTAssertEqual(model.lessonAnswerIndices["ownership-1"], 2)
        XCTAssertNil(model.activeLessonID)
        XCTAssertEqual(model.projectID, projectID)

        let reopened = CompilerViewModel(userDefaults: defaults)
        XCTAssertEqual(reopened.completedLessonIDs, ["ownership-1"])
        XCTAssertEqual(reopened.lessonAnswerIndices, ["ownership-1": 2])
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
