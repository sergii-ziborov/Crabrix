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

    func testTargetFolderIsOnlyBuildOutputAtTheRootOrBesideAManifest() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Import-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        for (path, contents) in [
            ("Cargo.toml", "[package]\nname = \"targets\"\n"),
            ("src/main.rs", "mod target;\nfn main() {}\n"),
            ("src/target/mod.rs", "pub fn x() {}\n"),
            ("target/debug/output.txt", "ignored"),
            ("member/Cargo.toml", "[package]\nname = \"member\"\n"),
            ("member/target/debug/output.txt", "ignored"),
        ] {
            let file = root.appending(path: path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: file)
        }

        let project = try LocalProjectLoader.load(from: root, provenance: .files())

        XCTAssertEqual(Set(project.files.keys), ["Cargo.toml", "src/main.rs", "src/target/mod.rs", "member/Cargo.toml"])
    }

    func testFolderNamesLoseOnlyATrailingBranch() {
        XCTAssertEqual(LocalProjectLoader.folderDisplayName("repo-main"), "repo")
        XCTAssertEqual(LocalProjectLoader.folderDisplayName("repo-master"), "repo")
        XCTAssertEqual(LocalProjectLoader.folderDisplayName("my-mainframe"), "my-mainframe")
        XCTAssertEqual(LocalProjectLoader.folderDisplayName("main-master-plan"), "main-master-plan")
        XCTAssertEqual(LocalProjectLoader.folderDisplayName("-main"), "-main")
    }

    private func makeZip(_ url: URL, entries: [(String, Data)]) throws {
        let archive = try Archive(url: url, accessMode: .create)
        for (path, bytes) in entries {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(bytes.count), compressionMethod: .deflate) { position, size in
                bytes.subdata(in: Int(position)..<Int(position) + size)
            }
        }
    }

    func testRootLevelArchiveIsNamedAfterTheArchiveNotItsTemporaryFolder() throws {
        let work = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: work) }
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let zip = work.appending(path: "landing-page.zip")
        try makeZip(zip, entries: [("index.html", Data("<h1>Hello</h1>".utf8))])

        let project = try CrabrixProjectArchive.load(from: zip)

        XCTAssertEqual(project.name, "landing-page")
        XCTAssertEqual(project.entryFile, "index.html")

        let branch = work.appending(path: "site-main.zip")
        try makeZip(branch, entries: [("index.html", Data("<h1>Hello</h1>".utf8))])
        XCTAssertEqual(try CrabrixProjectArchive.load(from: branch).name, "site")
    }

    /// Rewrites one entry's declared size in the ZIP's central directory, as a
    /// crafted archive would. The compressed stream still inflates to full size.
    private func declareSize(_ size: UInt32, in url: URL) throws {
        var bytes = try Data(contentsOf: url)
        let signature = Data([0x50, 0x4B, 0x01, 0x02])
        var found = 0
        var search = bytes.startIndex
        while let range = bytes.range(of: signature, in: search..<bytes.endIndex) {
            withUnsafeBytes(of: size.littleEndian) { bytes.replaceSubrange(range.lowerBound + 24..<range.lowerBound + 28, with: $0) }
            search = range.upperBound
            found += 1
        }
        XCTAssertEqual(found, 1)
        try bytes.write(to: url)
    }

    func testExpansionCountsActualBytesInsteadOfTheDeclaredSize() throws {
        let work = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: work) }
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let zip = work.appending(path: "bomb.zip")
        try makeZip(zip, entries: [("main.rs", Data(repeating: 0x20, count: 2_000_000))])
        XCTAssertLessThan(try Data(contentsOf: zip).count, 100_000)
        try declareSize(1, in: zip)

        XCTAssertThrowsError(try CrabrixProjectArchive.load(from: zip)) { error in
            guard case CrabrixProjectArchive.ArchiveError.archiveTooLarge = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        // The overall limit applies to what was written, not what was promised.
        let expanded = work.appending(path: "expanded")
        try FileManager.default.createDirectory(at: expanded, withIntermediateDirectories: true)
        let honest = work.appending(path: "honest.zip")
        try makeZip(honest, entries: [("a.txt", Data(repeating: 0x20, count: 40_000)), ("b.txt", Data(repeating: 0x21, count: 40_000))])
        struct TooLarge: Error {}
        XCTAssertThrowsError(try CrabrixProjectArchive.expand(honest, to: expanded, maximumBytes: 50_000) { TooLarge() }) {
            XCTAssertTrue($0 is TooLarge)
        }
        let fresh = work.appending(path: "fresh")
        try FileManager.default.createDirectory(at: fresh, withIntermediateDirectories: true)
        try CrabrixProjectArchive.expand(honest, to: fresh, maximumBytes: 80_000) { TooLarge() }
        XCTAssertEqual(try Data(contentsOf: fresh.appending(path: "b.txt")).count, 40_000)
    }

    func testUnreadableRecentProjectDoesNotFailOtherSavesOrHideItsRescue() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = ProjectLibrary(storageURL: root.appending(path: "recent.json"))
        let good = CrabrixProject(name: "good", files: ["main.rs": "fn main(){}"], entryFile: "main.rs", provenance: nil)
        let broken = CrabrixProject(name: "broken", files: ["main.rs": "fn main(){}", "notes.txt": "small"], entryFile: "main.rs", provenance: nil)
        _ = try await library.record(project: good, lastBuild: nil)
        _ = try await library.record(project: broken, lastBuild: nil)
        // A legacy project with one over-budget file, which still sits in Recents.
        let folder = root.appending(path: "projects/\(broken.id.uuidString.lowercased())")
        try Data(repeating: 0x78, count: ProjectFilePolicy.maximumFileBytes + 1).write(to: folder.appending(path: "files/notes.txt"))
        let metadata = folder.appending(path: "project.json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: metadata)) as? [String: Any])
        object.removeValue(forKey: "fileDigests"); object["version"] = 2
        try JSONSerialization.data(withJSONObject: object).write(to: metadata)

        var updated = good
        updated.files["main.rs"] = "fn main(){ println!(\"saved\"); }"
        let recents = try await library.record(project: updated, lastBuild: nil)
        XCTAssertEqual(recents.map(\.id), [good.id])
        XCTAssertEqual(recents.first?.project.files["main.rs"], updated.files["main.rs"])

        let items = try await library.items()
        XCTAssertEqual(items.map(\.id), [good.id])
        let all = try await library.allItems()
        XCTAssertEqual(all.map(\.id), [good.id])
        let failures = await library.readFailures()
        XCTAssertEqual(failures.map(\.projectID), [broken.id])
        // Still counts as taken, so an import cannot overwrite the rescue copy.
        let isTaken = await library.containsProject(id: broken.id)
        XCTAssertTrue(isTaken)
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

/// Answers GitHub archive requests, so a test exercises the real error types.
private final class GitHubArchiveStub: URLProtocol {
    enum Answer: Sendable, CustomStringConvertible {
        case failure(URLError)
        case status(Int, [String: String])
        case archive(Data)

        var description: String {
            switch self {
            case let .failure(error): "URLError \(error.code.rawValue)"
            case let .status(code, headers): "HTTP \(code) \(headers)"
            case .archive: "an archive"
            }
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var stored: Answer = .status(500, [:])
    static var answer: Answer {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url ?? URL(fileURLWithPath: "/")
        switch Self.answer {
        case let .failure(error):
            client?.urlProtocol(self, didFailWithError: error)
            return
        case let .status(code, headers):
            let response = HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        case let .archive(data):
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
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

    private func makeModel(_ root: URL) -> (CompilerViewModel, ProjectLibrary) {
        let library = ProjectLibrary(storageURL: root.appending(path: "recent.json"))
        let suite = "crabrix.tests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return (CompilerViewModel(projectLibrary: library, userDefaults: UserDefaults(suiteName: suite)!), library)
    }

    private func eventually(
        _ what: String, _ condition: () async throws -> Bool, file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while ContinuousClock.now < deadline {
            if try await condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for \(what)", file: file, line: line)
    }

    func testImportingAPackageWithATakenIDMakesACopyAndKeepsTheOriginal() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ImportCopy-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let (model, library) = makeModel(root)
        let exported = CrabrixProject(name: "mine", files: ["main.rs": "// version 1\nfn main(){}"], entryFile: "main.rs", provenance: nil)
        var moved = exported
        moved.files["main.rs"] = "// version 2\nfn main(){}"
        _ = try await library.record(project: moved, lastBuild: nil)
        let package = root.appending(path: "export.crabrixproject")
        try CrabrixProjectDocument(project: exported).packageWrapper().write(to: package, options: .atomic, originalContentsURL: nil)
        let zip = try CrabrixProjectArchive.create(project: exported)
        defer { CrabrixProjectArchive.removeTemporaryArchive(at: zip) }

        for url in [package, zip] {
            await model.openProject(from: url)
            XCTAssertNotEqual(model.projectID, exported.id, url.lastPathComponent)
            XCTAssertEqual(model.exportProject().files["main.rs"], exported.files["main.rs"])
            let original = try await library.project(id: exported.id)
            XCTAssertEqual(original?.project.files["main.rs"], moved.files["main.rs"])
        }
        let copyID = model.projectID
        try await eventually("the copy to save") {
            try await library.project(id: copyID) != nil
        }

        // An ID nothing here uses is kept, so moving to a new device keeps identity.
        let fresh = CrabrixProject(name: "fresh", files: ["main.rs": "fn main(){}"], entryFile: "main.rs", provenance: nil)
        let freshPackage = root.appending(path: "fresh.crabrixproject")
        try CrabrixProjectDocument(project: fresh).packageWrapper().write(to: freshPackage, options: .atomic, originalContentsURL: nil)
        await model.openProject(from: freshPackage)
        XCTAssertEqual(model.projectID, fresh.id)
    }

    func testSwitchingProjectSavesEditsStillWaitingOnAutosave() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Flush-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let (model, library) = makeModel(root)
        model.loadRunnableSample(projectName: "first")
        let firstID = model.projectID
        try await eventually("the project to save") { try await library.project(id: firstID) != nil }

        model.source += "\n// typed just before switching"
        let edited = model.source
        model.loadRunnableSample(projectName: "second")

        try await eventually("the last edit to reach storage") {
            try await library.project(id: firstID)?.project.files["main.rs"] == edited
        }
    }

    func testBackgroundFlushSavesWithoutWaitingForTheQuietPeriod() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Background-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let (model, library) = makeModel(root)
        model.source += "\n// typed just before backgrounding"
        let edited = model.source
        let id = model.projectID

        model.flushPendingAutosave()

        // Autosave would wait out its 500 ms quiet period. A flush starts at once.
        let started = ContinuousClock.now
        try await eventually("the flush to start") {
            if case .unsaved = model.saveState { return false }
            return true
        }
        XCTAssertLessThan(started.duration(to: .now), .milliseconds(450))
        try await eventually("the flush to reach storage") {
            try await library.project(id: id)?.project.files["main.rs"] == edited
        }
        // With nothing pending, a flush does nothing at all.
        model.flushPendingAutosave()
    }

    func testSharedLinkLeavesTheQueueOnlyWhenItWillNotBeRetried() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Queue-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GitHubArchiveStub.self]
        let suite = "crabrix.tests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let model = CompilerViewModel(
            githubImporter: GitHubProjectImporter(session: URLSession(configuration: configuration)),
            projectLibrary: ProjectLibrary(storageURL: root.appending(path: "recent.json")),
            userDefaults: UserDefaults(suiteName: suite)!
        )
        let link = "https://github.com/owner/repo"
        func stays(_ answer: GitHubArchiveStub.Answer, line: UInt = #line) async {
            GitHubArchiveStub.answer = answer
            var removed: [String] = []
            await model.consumeSharedImport(link, remove: { removed.append($0) })
            XCTAssertTrue(removed.isEmpty, "\(answer) dropped the link", line: line)
        }
        func leaves(_ answer: GitHubArchiveStub.Answer, line: UInt = #line) async {
            GitHubArchiveStub.answer = answer
            var removed: [String] = []
            await model.consumeSharedImport(link, remove: { removed.append($0) })
            XCTAssertEqual(removed, [link], "\(answer) kept the link", line: line)
        }

        // A later attempt can succeed.
        await stays(.failure(URLError(.notConnectedToInternet)))
        await stays(.status(429, [:]))
        await stays(.status(403, ["X-RateLimit-Remaining": "0"]))
        await stays(.status(403, ["Retry-After": "60"]))
        await stays(.status(500, [:]))
        await stays(.status(503, [:]))

        // A later attempt never can, so it must not block the queue.
        await leaves(.status(404, [:]))
        await leaves(.status(403, ["X-RateLimit-Remaining": "12"]))
        var removed: [String] = []
        await model.consumeSharedImport("not a repository", remove: { removed.append($0) })
        XCTAssertEqual(removed, ["not a repository"])

        // Success.
        let zip = root.appending(path: "repo.zip")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let archive = try Archive(url: zip, accessMode: .create)
        let manifest = Data("[package]\nname = \"repo\"\nversion = \"0.1.0\"\n".utf8)
        try archive.addEntry(with: "repo-main/Cargo.toml", type: .file, uncompressedSize: Int64(manifest.count)) { position, size in
            manifest.subdata(in: Int(position)..<Int(position) + size)
        }
        let source = Data("fn main() {}\n".utf8)
        try archive.addEntry(with: "repo-main/src/main.rs", type: .file, uncompressedSize: Int64(source.count)) { position, size in
            source.subdata(in: Int(position)..<Int(position) + size)
        }
        await leaves(.archive(try Data(contentsOf: zip)))
        XCTAssertEqual(model.projectName, "repo")
    }

    /// A course the learner resets must stay reset, whichever way its lab comes back.
    func testResettingACourseDoesNotRebindItsOpenLab() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Reset-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let lessonID = try XCTUnwrap(AlgorithmCourseCatalog.patterns.first).lessonID(.challenge)
        let (content, repository) = try await lessonSession(root: root, lessonID: lessonID)
        let template = try XCTUnwrap(repository.starterProject(for: lessonID))
        let session = try XCTUnwrap(CourseSession(lessonID: lessonID, repository: repository))
        let suite = "crabrix.tests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let library = ProjectLibrary(storageURL: root.appending(path: "recent.json"))
        let model = CompilerViewModel(projectLibrary: library, userDefaults: defaults)

        model.loadCourseStarter(template, session: session)
        model.beginLesson(lessonID, content: content)
        let labID = model.projectID
        await model.retryProjectSave()
        model.resetCourseProgress(lessonIDs: [lessonID])

        XCTAssertNil(model.activeLessonID)
        XCTAssertNil(model.resumableLessonID, "The open lab must not rebind straight after a reset")
        model.resumeLesson(content: content, starterFiles: template.files)
        XCTAssertNil(model.activeLessonID)

        // Neither when it is reopened, even after a relaunch.
        model.loadRunnableSample(projectName: "elsewhere")
        let reopened = await model.openRecentProject(id: labID)
        XCTAssertTrue(reopened)
        XCTAssertNil(model.resumableLessonID)
        let relaunched = CompilerViewModel(projectLibrary: library, userDefaults: defaults)
        let reopenedAfterRelaunch = await relaunched.openRecentProject(id: labID)
        XCTAssertTrue(reopenedAfterRelaunch)
        XCTAssertNil(relaunched.resumableLessonID)

        // A lab started after the reset is a new attempt and resumes normally.
        model.loadCourseStarter(template, session: session)
        XCTAssertEqual(model.resumableLessonID, lessonID)
    }

    private static let borrowFailure = CompilationResult(
        succeeded: false, phase: .compile, exitCode: nil,
        diagnostics: [RustDiagnostic(
            level: "error", message: "cannot borrow `items` as mutable", code: "E0502", rendered: "E0502",
            spans: [
                .init(fileName: "main.rs", lineStart: 4, lineEnd: 4, columnStart: 5, columnEnd: 20, isPrimary: true,
                      label: "mutable borrow occurs here", sourceLine: ""),
                .init(fileName: "main.rs", lineStart: 5, lineEnd: 5, columnStart: 5, columnEnd: 20, isPrimary: false,
                      label: "immutable borrow later used here", sourceLine: ""),
            ]
        )],
        stdout: "", stderr: "", duration: .milliseconds(1), detail: "fixture"
    )

    func testAppliedRepairIsRememberedAcrossReopeningUntilTheCodeMovesAway() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Applied-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let (content, repository) = try await lessonSession(root: root, lessonID: "borrowing")
        let session = try XCTUnwrap(CourseSession(lessonID: "borrowing", repository: repository))
        let template = try XCTUnwrap(repository.starterProject(for: "borrowing"))
        let suite = "crabrix.tests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let library = ProjectLibrary(storageURL: root.appending(path: "recent.json"))
        let model = CompilerViewModel(projectLibrary: library, userDefaults: defaults)

        model.loadCourseStarter(template, session: session)
        model.beginLesson("borrowing", content: content)
        let labID = model.projectID
        let starter = model.source
        model.receiveSharedRuntimeResult(Self.borrowFailure)
        model.applyRepair()
        let applied = model.source
        XCTAssertNotEqual(applied, starter)
        XCTAssertNotNil(model.activeLessonAutomaticRepairFingerprint)

        // Only comments and spacing: still the app's fix.
        model.source = applied + "\n// mine\n"
        XCTAssertNotNil(model.activeLessonAutomaticRepairFingerprint)
        model.source = applied
        await model.retryProjectSave()

        // Reopened, and after a relaunch: the marker comes back with the code.
        let relaunched = CompilerViewModel(projectLibrary: library, userDefaults: defaults)
        let reopened = await relaunched.openRecentProject(id: labID)
        XCTAssertTrue(reopened)
        relaunched.resumeLesson(content: content, starterFiles: template.files)
        XCTAssertEqual(relaunched.source, applied)
        XCTAssertEqual(
            relaunched.activeLessonAutomaticRepairFingerprint,
            LessonSourceText.fingerprint(in: relaunched.exportProject().files)
        )

        // Undo, and the identical line move by hand is the learner's own.
        relaunched.source = starter
        XCTAssertNil(relaunched.activeLessonAutomaticRepairFingerprint)
        relaunched.source = applied
        XCTAssertNil(relaunched.activeLessonAutomaticRepairFingerprint)
        await relaunched.retryProjectSave()
        let again = CompilerViewModel(projectLibrary: library, userDefaults: defaults)
        let reopenedAgain = await again.openRecentProject(id: labID)
        XCTAssertTrue(reopenedAgain)
        again.resumeLesson(content: content, starterFiles: template.files)
        XCTAssertNil(again.activeLessonAutomaticRepairFingerprint, "The cleared marker must stay cleared")
    }

    private func lessonSession(root: URL, lessonID: String) async throws -> (CourseLessonExecution, InstalledCourseRepository) {
        let repository = try await CourseBootstrap(
            bundle: .main, root: root.appending(path: "courses"), appVersion: SemanticVersion("1.1")
        ).activateBundledBaseline()
        let session = try XCTUnwrap(CourseSession(lessonID: lessonID, repository: repository))
        let lesson = try XCTUnwrap(repository.lesson(id: lessonID))
        return (try XCTUnwrap(CourseLessonExecution(lesson: lesson, session: session)), repository)
    }

    func testReopeningALabRestoresTheLessonWithoutTouchingTheLearnersWork() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "Resume-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let lessonID = try XCTUnwrap(AlgorithmCourseCatalog.patterns.first).lessonID(.challenge)
        let (content, repository) = try await lessonSession(root: root, lessonID: lessonID)
        let template = try XCTUnwrap(repository.starterProject(for: lessonID))
        let session = try XCTUnwrap(CourseSession(lessonID: lessonID, repository: repository))
        let (model, library) = makeModel(root)

        model.loadCourseStarter(template, session: session)
        model.beginLesson(lessonID, content: content)
        XCTAssertNil(model.resumableLessonID, "A lab that is already bound has nothing to resume")
        XCTAssertFalse(model.activeLessonWasResumed, "Closing this lab must return to its lesson")
        let labID = model.projectID
        model.source = "pub fn solve(input: &str) -> String {\n    // half written\n    input.to_string()\n}\n"
        let work = model.source
        await model.retryProjectSave()

        model.loadRunnableSample(projectName: "elsewhere")
        XCTAssertNil(model.activeLessonID)
        XCTAssertNil(model.resumableLessonID, "A project unrelated to a lesson has nothing to resume")

        let reopened = await model.openRecentProject(id: labID)
        XCTAssertTrue(reopened)
        XCTAssertNil(model.activeLessonID)
        XCTAssertEqual(model.resumableLessonID, lessonID)
        XCTAssertEqual(model.source, work)

        model.resumeLesson(content: content, starterFiles: template.files)
        XCTAssertEqual(model.activeLessonID, lessonID)
        XCTAssertTrue(model.activeLessonWasResumed, "Closing this lab must return to Projects")
        XCTAssertEqual(model.source, work, "Resuming must not reload the starter")
        XCTAssertNil(model.resumableLessonID)
        XCTAssertFalse(model.activeLessonIsReview)
        let stored = try await library.project(id: labID)
        XCTAssertEqual(stored?.project.files[template.entryFile], work)
    }

    func testReplayAndExampleCopiesAreNotResumableLabs() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "NoResume-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let (model, _) = makeModel(root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        func open(_ provenance: CrabrixProject.Provenance) async throws {
            let project = CrabrixProject(name: "copy", files: ["main.rs": "fn main(){}"], entryFile: "main.rs", provenance: provenance)
            let package = root.appending(path: "\(UUID().uuidString).crabrixproject")
            try CrabrixProjectDocument(project: project).packageWrapper().write(to: package, options: .atomic, originalContentsURL: nil)
            await model.openProject(from: package)
            XCTAssertEqual(model.exportProject().provenance?.course, provenance.course)
        }

        try await open(.academyExample(id: "demo", contentVersion: "1.0.0", templateHash: "hash"))
        XCTAssertNil(model.resumableLessonID)

        var recording = CrabrixProject.Provenance.academyExample(id: "demo", contentVersion: "1.0.0", templateHash: "hash")
        recording.course = .init(courseID: "algorithms", contentVersion: "1.0.0", lessonID: "algorithm.x.challenge", templateHash: "hash",
            recording: .init(key: "k", sourceHash: "s", input: "i", packVersion: "1", packDigest: "d", courseContentVersion: "1"))
        try await open(recording)
        XCTAssertNil(model.resumableLessonID)

        // Someone else's solved lab: the files arrive, the lesson link does not, so
        // running it earns nothing here. The same applies to a learner's own export,
        // whose work is all kept and which only needs its lesson opened again.
        var lab = recording
        lab.course?.recording = nil
        let solved = "pub fn solve(input: &str) -> String { input.to_string() }\n"
        let project = CrabrixProject(name: "solved", files: ["solution.rs": solved], entryFile: "solution.rs", provenance: lab)
        let package = root.appending(path: "solved.crabrixproject")
        try CrabrixProjectDocument(project: project).packageWrapper().write(to: package, options: .atomic, originalContentsURL: nil)
        await model.openProject(from: package)
        XCTAssertEqual(model.exportProject().files["solution.rs"], solved)
        XCTAssertNil(model.provenance?.course)
        XCTAssertNil(model.resumableLessonID)
        XCTAssertEqual(model.provenance?.source, .academy)
        await model.openProject(from: package)
        XCTAssertNil(model.resumableLessonID, "A copy under a new ID must not keep the link either")
        XCTAssertEqual(model.exportProject().files["solution.rs"], solved)
    }

    func testStopDuringDependencyResolutionReportsStoppedNotFailed() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "StopResolve-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let (model, _) = makeModel(root)
        model.createProject(name: "resolve", template: .hello)
        model.selectFile("Cargo.toml")
        XCTAssertEqual(model.selectedFile, "Cargo.toml")
        model.source = "[package]\nname = \"resolve\"\nversion = \"0.1.0\"\nedition = \"2021\"\n\n[dependencies]\nserde = \"1\"\n"
        model.run()
        // Stop as soon as resolution begins, however far the network has got.
        try await eventually("resolution to start") { model.cargoStage.isWorking || !model.isBusy }
        try XCTSkipUnless(model.isBusy, "Resolution finished before Stop could be pressed")
        model.cancelBuild()
        XCTAssertTrue(model.result?.wasStopped == true)
        try await eventually("the worker to drain") { !model.isCompilerDraining }

        XCTAssertTrue(model.result?.wasStopped == true, model.result?.detail ?? "No result")
        if case .failed = model.cargoStage { XCTFail("Stop must not report a resolution failure") }
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
