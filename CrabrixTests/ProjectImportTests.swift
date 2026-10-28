import XCTest
import ZIPFoundation
@testable import Crabrix

final class ProjectImportTests: XCTestCase {
    func testCurrentSourceRescuePreservesOverBudgetUTF8AndCleansUp() throws {
        let text = String(repeating: "🦀\n", count: 500_000)
        XCTAssertGreaterThan(text.utf8.count, ProjectFilePolicy.maximumFileBytes)
        let url = try CrabrixProjectArchive.createSourceRescue(source: text, fileName: "main.rs")
        XCTAssertEqual(try Data(contentsOf: url), Data(text.utf8))
        XCTAssertEqual(url.lastPathComponent, "main.rs")
        CrabrixProjectArchive.removeTemporaryArchive(at: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
    func testLegacyMigrationRetainsItsOriginalPreviousSnapshot() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(rootURL: root)
        var project = CrabrixProject(name: "migrate", files: ["main.rs": "fn main(){}", ".hidden.txt": "older hidden data"], entryFile: "main.rs", provenance: nil)
        _ = try await store.save(project: project, lastBuild: nil)
        let folder = root.appending(path: "projects/\(project.id.uuidString.lowercased())")
        let previous = folder.appending(path: "recovery/previous")
        try FileManager.default.createDirectory(at: previous, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: folder.appending(path: "files"), to: previous.appending(path: "files"))
        try FileManager.default.copyItem(at: folder.appending(path: "project.json"), to: previous.appending(path: "project.json"))
        try FileManager.default.removeItem(at: folder.appending(path: "files/.hidden.txt"))
        let metadata = folder.appending(path: "project.json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: metadata)) as? [String: Any])
        object["version"] = 2; object.removeValue(forKey: "fileDigests")
        try JSONSerialization.data(withJSONObject: object).write(to: metadata)
        project.files.removeValue(forKey: ".hidden.txt")
        _ = try await store.save(project: project, lastBuild: nil)
        _ = try await store.allProjects() // Recovery scan must not delete migration bytes.
        let rescue = try await store.recoveryArchive(projectID: project.id)
        defer { CrabrixProjectArchive.removeTemporaryArchive(at: rescue) }
        let expanded = root.appending(path: "migration-expanded")
        try FileManager.default.unzipItem(at: rescue, to: expanded)
        let data = try Data(contentsOf: expanded.appending(path: "SavedSnapshots/Retained-1/recovery/previous/files/.hidden.txt"))
        XCTAssertEqual(String(data: data, encoding: .utf8), "older hidden data")
    }

    func testHiddenAndCustomFilesRoundTripThroughStorePackageAndLargeZIP() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var files = ["main.rs": "fn main(){}", ".gitignore": "target/", ".rustfmt.toml": "edition = \"2024\"",
                     ".cargo/config.toml": "[build]", ".hidden/nested/source.rs": "pub const X:u8=1;",
                     "config.custom": "preserved", "target/kept.txt": "project file, not a generated cache"]
        for i in 0..<(ProjectFilePolicy.maximumFileCount - files.count) { files["modules/deep/part-\(i)/item.txt"] = "value \(i) 🦀" }
        let project = CrabrixProject(name: "complete-snapshot", files: files, entryFile: "main.rs", provenance: nil)
        let store = ProjectStore(rootURL: root)
        _ = try await store.save(project: project, lastBuild: nil)
        let reopened = try await ProjectStore(rootURL: root).project(id: project.id)
        XCTAssertEqual(reopened?.project, project)
        let package = root.appending(path: "copy.crabrixproject")
        try CrabrixProjectDocument(project: project).packageWrapper().write(to: package, options: .atomic, originalContentsURL: nil)
        let packaged = try LocalProjectLoader.load(from: package)
        XCTAssertEqual(packaged.id, project.id)
        XCTAssertEqual(packaged.files.count, ProjectFilePolicy.maximumFileCount)
        XCTAssertEqual(ProjectFilePolicy.digests(packaged.files), ProjectFilePolicy.digests(project.files))
        XCTAssertEqual(packaged.provenance, project.provenance)
        let zip = try CrabrixProjectArchive.create(project: project)
        defer { CrabrixProjectArchive.removeTemporaryArchive(at: zip) }
        let unzipped = try CrabrixProjectArchive.load(from: zip)
        XCTAssertEqual(unzipped.id, project.id)
        XCTAssertEqual(unzipped.files.count, ProjectFilePolicy.maximumFileCount)
        XCTAssertEqual(ProjectFilePolicy.digests(unzipped.files), ProjectFilePolicy.digests(project.files))
        XCTAssertEqual(unzipped.provenance, project.provenance)
    }

    func testFileBudgetRejectsWriteWithoutReplacingGoodSnapshotAndLegacyReadNeverDropsAuxiliary() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(rootURL: root)
        var project = CrabrixProject(name: "budgets", files: ["main.rs": "fn main(){}", "notes.txt": String(repeating: "x", count: ProjectFilePolicy.maximumFileBytes)], entryFile: "main.rs", provenance: nil)
        _ = try await store.save(project: project, lastBuild: nil)
        project.files["notes.txt"]! += "x"
        do { _ = try await store.save(project: project, lastBuild: nil); XCTFail("Must reject before replacing the good snapshot") }
        catch { XCTAssertEqual(error as? ProjectFilePolicy.Failure, .fileTooLarge("notes.txt")) }
        let good = try await store.project(id: project.id)
        XCTAssertEqual(good?.project.files["notes.txt"]?.utf8.count, ProjectFilePolicy.maximumFileBytes)
        let folder = root.appending(path: "projects/\(project.id.uuidString.lowercased())")
        try Data(project.files["notes.txt"]!.utf8).write(to: folder.appending(path: "files/notes.txt"))
        let metadata = folder.appending(path: "project.json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: metadata)) as? [String: Any])
        object.removeValue(forKey: "fileDigests"); object["version"] = 2
        try JSONSerialization.data(withJSONObject: object).write(to: metadata)
        do { _ = try await store.project(id: project.id); XCTFail("An oversized legacy auxiliary file must not disappear") }
        catch { XCTAssertEqual(error as? ProjectFilePolicy.Failure, .fileTooLarge("notes.txt")) }
        XCTAssertEqual(try Data(contentsOf: folder.appending(path: "files/notes.txt")).count, ProjectFilePolicy.maximumFileBytes + 1)
        try FileManager.default.removeItem(at: root.appending(path: "project-index.json"))
        let listed = try await store.allProjects()
        XCTAssertTrue(listed.isEmpty)
        let failures = await store.readFailures
        XCTAssertEqual(failures.map(\.projectID), [project.id])
        XCTAssertTrue(failures[0].message.contains("notes.txt"))
        let rescue = try await store.recoveryArchive(projectID: project.id)
        defer { CrabrixProjectArchive.removeTemporaryArchive(at: rescue) }
        let expanded = root.appending(path: "rescue-expanded")
        try FileManager.default.unzipItem(at: rescue, to: expanded)
        XCTAssertEqual(try Data(contentsOf: expanded.appending(path: "SavedSnapshots/Current/files/notes.txt")).count, ProjectFilePolicy.maximumFileBytes + 1)
    }

    func testMissingAuxiliaryIsDetectedAndRecoveryIsExplicit() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(rootURL: root)
        var project = CrabrixProject(name: "integrity", files: ["main.rs": "fn main(){}", ".hidden.txt": "first"], entryFile: "main.rs", provenance: nil)
        _ = try await store.save(project: project, lastBuild: nil)
        project.files[".hidden.txt"] = "second"
        _ = try await store.save(project: project, lastBuild: nil)
        let folder = root.appending(path: "projects/\(project.id.uuidString.lowercased())")
        try FileManager.default.removeItem(at: folder.appending(path: "files/.hidden.txt"))
        let recovered = try await store.project(id: project.id)
        XCTAssertEqual(recovered?.project.files[".hidden.txt"], "first")
        XCTAssertNotNil(recovered?.recoveryMessage)
    }

    func testPathAliasesAndFileDirectoryCollisionsAreRefusedBeforeExport() throws {
        for files in [["a.rs": "a", "A.rs": "b"], ["src": "a", "src/main.rs": "b"], ["Src/a.rs": "a", "src/b.rs": "b"], [".git/config": "secret"]] {
            XCTAssertThrowsError(try ProjectFilePolicy.validate(files))
        }
    }

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
        // Registry dependencies are resolved; build scripts need an honest
        // supported profile rather than the older blanket "not executed" note.
        XCTAssertEqual(report.notes, ["Std-only WASI build scripts can run locally. Scripts needing host subprocesses, native linking or separate build dependencies require a different profile."])
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
        XCTAssertEqual(Set(items.map(\.project.name)), ["demo", "demo-2"])
        XCTAssertEqual(Set(items.compactMap { $0.project.files["main.rs"] }), [
            first.files["main.rs"]!, second.files["main.rs"]!,
        ])
        // An autosave still carrying the requested base name must keep the
        // assigned suffix instead of creating another project or name.
        _ = try await library.record(project: second, lastBuild: nil)
        let reopened = try await ProjectLibrary(storageURL: root.appending(path: "recent-projects.json")).allItems()
        XCTAssertEqual(Set(reopened.map(\.project.name)), ["demo", "demo-2"])
        XCTAssertEqual(reopened.count, 2)
    }

    func testRenamingCannotCollideWithAnotherProjectOrItsSuffix() async throws {
        let root = temporaryRoot(named: "NameCollision")
        defer { try? FileManager.default.removeItem(at: root) }
        let library = ProjectLibrary(storageURL: root.appending(path: "recent-projects.json"))
        let first = project(name: "Demo", source: "fn main() { /* first */ }")
        let numbered = project(name: "demo-2", source: "fn main() { /* numbered */ }")
        var renamed = project(name: "other", source: "fn main() { /* renamed */ }")
        for value in [first, numbered, renamed] { _ = try await library.record(project: value, lastBuild: nil) }
        renamed.name = " demo "
        let saved = try await library.update(project: renamed, lastBuild: nil)
        XCTAssertEqual(saved.project.name, "demo-3")
        XCTAssertEqual(saved.id, renamed.id)
        XCTAssertEqual(saved.project.files, renamed.files)
        let items = try await library.allItems()
        XCTAssertEqual(Set(items.map(\.project.name)), ["Demo", "demo-2", "demo-3"])
    }

    func testConcurrentImportsAssignDistinctNamesWithoutDroppingProjects() async throws {
        let root = temporaryRoot(named: "ConcurrentNames")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(rootURL: root)
        let projects = (0..<8).map { project(name: "imported", source: "fn main() { /* \($0) */ }") }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for value in projects { group.addTask { _ = try await store.save(project: value, lastBuild: nil) } }
            try await group.waitForAll()
        }
        let items = try await store.allProjects()
        XCTAssertEqual(Set(items.map(\.id)), Set(projects.map(\.id)))
        XCTAssertEqual(Set(items.map(\.project.name)).count, projects.count)
        for value in projects { XCTAssertEqual(items.first { $0.id == value.id }?.project.files, value.files) }
    }

    func testExistingDuplicateNamesAreRepairedWithoutChangingContentOrDates() async throws {
        let root = temporaryRoot(named: "ExistingDuplicateNames")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(rootURL: root)
        let projects = [project(name: "demo", source: "fn main() { /* original */ }"),
                        project(name: "temporary", source: "fn main() { /* duplicate */ }"),
                        project(name: "demo-2", source: "fn main() { /* numbered */ }")]
        let build = ProjectBuildRecord(result: CompilationResult(
            succeeded: true, phase: .run, exitCode: 0, diagnostics: [], stdout: "kept", stderr: "",
            duration: .milliseconds(250), detail: "passed"
        ), finishedAt: Date(timeIntervalSince1970: 50))
        for (index, value) in projects.enumerated() {
            _ = try await store.save(project: value, lastBuild: build, at: Date(timeIntervalSince1970: Double(100 + index)))
        }
        // Emulate a snapshot written by an older release, including a stale index.
        let metadata = root.appending(path: "projects/\(projects[1].id.uuidString.lowercased())/project.json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: metadata)) as? [String: Any])
        json["name"] = "demo"
        try JSONSerialization.data(withJSONObject: json).write(to: metadata, options: .atomic)
        let repaired = try await store.allProjects()
        XCTAssertEqual(Set(repaired.map(\.project.name)), ["demo", "demo-2", "demo-3"])
        for (index, value) in projects.enumerated() {
            let item = try XCTUnwrap(repaired.first { $0.id == value.id })
            XCTAssertEqual(item.project.files, value.files)
            XCTAssertEqual(item.lastBuild, build)
            XCTAssertEqual(item.lastOpenedAt, Date(timeIntervalSince1970: Double(100 + index)))
        }
        let reopened = try await ProjectStore(rootURL: root).allProjects()
        XCTAssertEqual(reopened, repaired)
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
    func testSavingProjectDetailsWaitsForPersistenceAndShowsTheUniqueName() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "SettingsSave-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let library = ProjectLibrary(storageURL: root.appending(path: "projects.json"))
        let existing = CrabrixProject(name: "taken", files: ["main.rs": "fn main() {}"], entryFile: "main.rs", provenance: nil)
        _ = try await library.record(project: existing, lastBuild: nil)
        let model = CompilerViewModel(projectLibrary: library)
        let id = model.projectID
        let files = model.exportProject().files
        let saved = await model.updateCurrentProjectDetails(name: "taken", description: "Saved description",
            tags: ["rust"], folder: "Learning", kind: .general, isFavorite: true)
        XCTAssertTrue(saved)
        XCTAssertEqual(model.projectName, "taken-2")
        let stored = try await library.project(id: id)
        XCTAssertEqual(stored?.project.name, model.projectName)
        XCTAssertEqual(stored?.project.files, files)
        XCTAssertEqual(stored?.project.projectDescription, "Saved description")
        XCTAssertEqual(stored?.project.tags, ["rust"])
        XCTAssertEqual(stored?.project.folder, "Learning")
        XCTAssertEqual(stored?.project.isFavorite, true)
    }

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
