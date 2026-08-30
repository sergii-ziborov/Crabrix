import XCTest
@testable import Crabrix

final class ProjectImportTests: XCTestCase {
    private struct LegacyProject: Codable {
        let name: String
        let files: [String: String]
        let entryFile: String
        let provenance: CrabrixProject.Provenance?
    }

    private struct LegacyItem: Codable {
        let id: UUID
        let project: LegacyProject
        let lastOpenedAt: Date
        let lastBuild: ProjectBuildRecord?
    }

    private struct LegacyState: Codable {
        let items: [LegacyItem]
    }

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
            provenance: provenance,
            projectDescription: "A tagged parser experiment",
            tags: ["parser", "practice"],
            folder: "Learning",
            kind: .experiment,
            isFavorite: true
        )
        let wrapper = try CrabrixProjectDocument(project: project).packageWrapper()
        try wrapper.write(to: root, options: .atomic, originalContentsURL: nil)

        let loaded = try LocalProjectLoader.load(from: root)

        XCTAssertEqual(loaded.name, "demo")
        XCTAssertEqual(loaded.id, project.id)
        XCTAssertEqual(loaded.files, project.files)
        XCTAssertEqual(loaded.entryFile, "src/main.rs")
        XCTAssertEqual(loaded.provenance, provenance)
        XCTAssertEqual(loaded.projectDescription, project.projectDescription)
        XCTAssertEqual(loaded.tags, project.tags)
        XCTAssertEqual(loaded.folder, project.folder)
        XCTAssertEqual(loaded.kind, project.kind)
        XCTAssertEqual(loaded.isFavorite, project.isFavorite)
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
            provenance: nil,
            projectDescription: "Round-trip archive",
            tags: ["share"],
            folder: "Personal",
            kind: .library,
            isFavorite: true
        )
        let archiveURL = try CrabrixProjectArchive.create(project: project)
        defer { CrabrixProjectArchive.removeTemporaryArchive(at: archiveURL) }

        let loaded = try CrabrixProjectArchive.load(from: archiveURL)

        XCTAssertEqual(loaded.name, project.name)
        XCTAssertEqual(loaded.id, project.id)
        XCTAssertEqual(loaded.files, project.files)
        XCTAssertEqual(loaded.entryFile, project.entryFile)
        XCTAssertEqual(loaded.projectDescription, project.projectDescription)
        XCTAssertEqual(loaded.tags, project.tags)
        XCTAssertEqual(loaded.folder, project.folder)
        XCTAssertEqual(loaded.kind, project.kind)
        XCTAssertEqual(loaded.isFavorite, project.isFavorite)
    }

    func testDurableStoreKeepsEveryProjectBeyondRecentLimit() async throws {
        let root = temporaryRoot(named: "DurableCount")
        defer { try? FileManager.default.removeItem(at: root) }
        let library = ProjectLibrary(storageURL: root.appending(path: "recent-projects.json"))
        var expectedIDs: Set<UUID> = []

        for index in 0..<25 {
            let project = project(name: "project-\(index)", source: "fn main() { /* \(index) */ }")
            expectedIDs.insert(project.id)
            _ = try await library.record(project: project, lastBuild: nil)
        }

        let durable = try await ProjectLibrary(
            storageURL: root.appending(path: "recent-projects.json")
        ).allItems()
        let recent = try await library.items()

        XCTAssertEqual(Set(durable.map(\.id)), expectedIDs)
        XCTAssertEqual(durable.count, 25)
        XCTAssertEqual(recent.count, 20)
    }

    func testProjectsWithSameNameRemainSeparate() async throws {
        let root = temporaryRoot(named: "SameName")
        defer { try? FileManager.default.removeItem(at: root) }
        let library = ProjectLibrary(storageURL: root.appending(path: "recent-projects.json"))
        let first = project(name: "demo", source: "fn main() { println!(\"first\"); }")
        let second = project(name: "demo", source: "fn main() { println!(\"second\"); }")

        _ = try await library.record(project: first, lastBuild: nil)
        _ = try await library.record(project: second, lastBuild: nil)
        let items = try await library.allItems()

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(Set(items.map(\.id)), [first.id, second.id])
        XCTAssertEqual(Set(items.compactMap { $0.project.files["main.rs"] }), [
            first.files["main.rs"]!, second.files["main.rs"]!,
        ])
    }

    func testRenamePreservesProjectIdentity() async throws {
        let root = temporaryRoot(named: "Rename")
        defer { try? FileManager.default.removeItem(at: root) }
        let library = ProjectLibrary(storageURL: root.appending(path: "recent-projects.json"))
        var value = project(name: "before", source: "fn main() {}")
        let originalID = value.id

        _ = try await library.record(project: value, lastBuild: nil)
        value.name = "after"
        _ = try await library.record(project: value, lastBuild: nil)
        let items = try await library.allItems()

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.id, originalID)
        XCTAssertEqual(items.first?.project.name, "after")
    }

    func testOrganizingProjectPersistsMetadataWithoutChangingRecentOrder() async throws {
        let root = temporaryRoot(named: "OrganizeWithoutTouch")
        defer { try? FileManager.default.removeItem(at: root) }
        let library = ProjectLibrary(storageURL: root.appending(path: "recent-projects.json"))
        var first = project(name: "first", source: "fn main() {}")
        let second = project(name: "second", source: "fn main() {}")

        _ = try await library.record(project: first, lastBuild: nil)
        _ = try await library.record(project: second, lastBuild: nil)
        let initialRecent = try await library.items()
        XCTAssertEqual(initialRecent.map(\.id), [second.id, first.id])

        first.folder = "Learning"
        first.tags = ["borrow", "practice"]
        first.projectDescription = "Compiler drills"
        first.isFavorite = true
        _ = try await library.update(project: first, lastBuild: nil)

        let recent = try await library.items()
        let allProjects = try await library.allItems()
        let stored = try XCTUnwrap(allProjects.first { $0.id == first.id })
        XCTAssertEqual(recent.map(\.id), [second.id, first.id])
        XCTAssertEqual(stored.project.folder, "Learning")
        XCTAssertEqual(stored.project.tags, ["borrow", "practice"])
        XCTAssertEqual(stored.project.projectDescription, "Compiler drills")
        XCTAssertTrue(stored.project.isFavorite)
    }

    func testInterruptedTransactionRestoresPreviousSnapshot() async throws {
        let root = temporaryRoot(named: "Interrupted")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(rootURL: root)
        let value = project(name: "survivor", source: "fn main() { println!(\"safe\"); }")
        _ = try await store.save(project: value, lastBuild: nil)

        let projectsURL = root.appending(path: "projects", directoryHint: .isDirectory)
        let committed = projectsURL.appending(
            path: value.id.uuidString.lowercased(),
            directoryHint: .isDirectory
        )
        let interruptedBackup = projectsURL.appending(
            path: ".backup-\(value.id.uuidString)-simulated",
            directoryHint: .isDirectory
        )
        try FileManager.default.moveItem(at: committed, to: interruptedBackup)

        let recovered = try await ProjectStore(rootURL: root).project(id: value.id)

        XCTAssertEqual(recovered?.project, value)
        XCTAssertTrue(FileManager.default.fileExists(atPath: committed.path))
    }

    func testCorruptCurrentSnapshotFallsBackToPreviousValidState() async throws {
        let root = temporaryRoot(named: "Recovery")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(rootURL: root)
        var value = project(name: "recoverable", source: "fn main() { println!(\"first\"); }")
        let firstSource = value.files["main.rs"]
        _ = try await store.save(project: value, lastBuild: nil)
        value.files["main.rs"] = "fn main() { println!(\"second\"); }"
        _ = try await store.save(project: value, lastBuild: nil)

        let metadataURL = root
            .appending(path: "projects", directoryHint: .isDirectory)
            .appending(path: value.id.uuidString.lowercased(), directoryHint: .isDirectory)
            .appending(path: "project.json")
        try Data("not-json".utf8).write(to: metadataURL, options: .atomic)

        let recovered = try await ProjectStore(rootURL: root).project(id: value.id)

        XCTAssertEqual(recovered?.id, value.id)
        XCTAssertEqual(recovered?.project.files["main.rs"], firstSource)
    }

    func testCorruptIndexRebuildsFromIndependentProjectDirectories() async throws {
        let root = temporaryRoot(named: "IndexRecovery")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(rootURL: root)
        let first = project(name: "one", source: "fn main() { println!(\"one\"); }")
        let second = project(name: "two", source: "fn main() { println!(\"two\"); }")
        _ = try await store.save(project: first, lastBuild: nil)
        _ = try await store.save(project: second, lastBuild: nil)
        try Data("corrupt".utf8).write(
            to: root.appending(path: "project-index.json"),
            options: .atomic
        )

        let recovered = try await ProjectStore(rootURL: root).allProjects()

        XCTAssertEqual(Set(recovered.map(\.id)), [first.id, second.id])
    }

    func testLegacyRecentProjectsMigrateWithoutChangingIdentity() async throws {
        let root = temporaryRoot(named: "LegacyMigration")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let storageURL = root.appending(path: "recent-projects.json")
        let legacyID = UUID()
        let state = LegacyState(items: [
            LegacyItem(
                id: legacyID,
                project: LegacyProject(
                    name: "legacy",
                    files: ["main.rs": "fn main() {}"],
                    entryFile: "main.rs",
                    provenance: nil
                ),
                lastOpenedAt: Date(timeIntervalSince1970: 1_700_000_000),
                lastBuild: nil
            ),
        ])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: storageURL, options: .atomic)

        let library = ProjectLibrary(storageURL: storageURL)
        let recent = try await library.items()
        let durable = try await library.allItems()

        XCTAssertEqual(recent.first?.id, legacyID)
        XCTAssertEqual(durable.first?.id, legacyID)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appending(path: "recovery/recent-projects-v1.json").path
        ))
    }

    func testWorkspaceRevisionUsesCanonicalSourceTreeAndCargoHashes() {
        let id = UUID()
        let first = CrabrixProject(
            id: id,
            name: "revision",
            files: [
                "src/main.rs": "fn main() {}",
                "Cargo.toml": "[package]\nname = \"revision\"",
                "Cargo.lock": "version = 4",
            ],
            entryFile: "src/main.rs",
            provenance: nil
        )
        let reordered = CrabrixProject(
            id: id,
            name: "revision",
            files: [
                "Cargo.lock": "version = 4",
                "Cargo.toml": "[package]\nname = \"revision\"",
                "src/main.rs": "fn main() {}",
            ],
            entryFile: "src/main.rs",
            provenance: nil
        )

        let left = WorkspaceRevision.capture(
            project: first,
            generation: 7,
            toolchainID: "test-toolchain"
        )
        let right = WorkspaceRevision.capture(
            project: reordered,
            generation: 7,
            toolchainID: "test-toolchain"
        )

        XCTAssertEqual(left, right)
        XCTAssertNotNil(left.manifestHash)
        XCTAssertNotNil(left.lockfileHash)
    }

    func testWorkspaceGenerationPreventsABARevisionReuse() {
        var value = project(name: "aba", source: "fn main() {}")
        let original = WorkspaceRevision.capture(
            project: value,
            generation: 1,
            toolchainID: "test-toolchain"
        )
        value.files["main.rs"] = "fn main() { println!(\"changed\"); }"
        _ = WorkspaceRevision.capture(
            project: value,
            generation: 2,
            toolchainID: "test-toolchain"
        )
        value.files["main.rs"] = "fn main() {}"
        let restored = WorkspaceRevision.capture(
            project: value,
            generation: 3,
            toolchainID: "test-toolchain"
        )

        XCTAssertEqual(original.sourceTreeHash, restored.sourceTreeHash)
        XCTAssertNotEqual(original, restored)
    }

    private func temporaryRoot(named name: String) -> URL {
        FileManager.default.temporaryDirectory.appending(
            path: "Crabrix\(name)Tests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
    }

    private func project(name: String, source: String) -> CrabrixProject {
        CrabrixProject(
            name: name,
            files: ["main.rs": source],
            entryFile: "main.rs",
            provenance: nil
        )
    }
}

@MainActor
final class WorkspaceRevisionViewModelTests: XCTestCase {
    func testActiveProjectKeepsIdentityWhileEditsAdvanceRevision() {
        let model = CompilerViewModel(
            userDefaults: UserDefaults(suiteName: "crabrix.tests.\(UUID().uuidString)")!
        )
        let projectID = model.projectID
        let before = model.workspaceRevision

        model.source += "\n// edit"
        let after = model.workspaceRevision

        XCTAssertEqual(model.projectID, projectID)
        XCTAssertEqual(model.exportProject().id, projectID)
        XCTAssertEqual(after.projectID, projectID)
        XCTAssertGreaterThan(after.generation, before.generation)
        XCTAssertNotEqual(after.sourceTreeHash, before.sourceTreeHash)
    }

    func testLoadingANewProjectChangesIdentityAndRevision() {
        let model = CompilerViewModel(
            userDefaults: UserDefaults(suiteName: "crabrix.tests.\(UUID().uuidString)")!
        )
        let before = model.workspaceRevision

        model.loadRunnableSample(projectName: "another-project")
        let after = model.workspaceRevision

        XCTAssertNotEqual(after.projectID, before.projectID)
        XCTAssertNotEqual(after, before)
    }
}
