import XCTest
import CryptoKit
@testable import Crabrix

final class BrowserProjectBuilderTests: XCTestCase {
    static func reactFiles() throws -> [String: String] {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "BrowserReactProject", withExtension: "json"))
        return try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
    }

    func testRealReactTSXBuildsFromEditableSourceWithEmptyArchiveCache() async throws {
        let files = try Self.reactFiles()
        let cache = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cache) }
        let builder = BrowserProjectBuilder(registry: BrowserNpmRegistry(cacheDirectory: cache))
        let result = try await builder.build(files: files, preferredEntry: "index.html")
        XCTAssertEqual(result.packageCount, 8)
        XCTAssertEqual(result.moduleCount, 133)
        XCTAssertTrue(result.sourceAdditions.isEmpty)
        XCTAssertTrue(result.preview.assets.keys.contains("crabrix-web/entry-0.js"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path), "Run must not even create the package archive cache")
        var edited = files
        edited["src/main.tsx"] = files["src/main.tsx"]!.replacingOccurrences(of: "Count ", with: "Offline ")
        let next = try await builder.build(files: edited, preferredEntry: "index.html")
        XCTAssertNotEqual(next.preview.id, result.preview.id)
    }

    @MainActor
    func testProjectRunAutomaticallyUsesBrowserBuilderAndSavedSourcesRoundTrip() async throws {
        let files = try Self.reactFiles()
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for (path, source) in files {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(source.utf8).write(to: url)
        }
        let loaded = try LocalProjectLoader.load(from: root)
        XCTAssertEqual(loaded.entryFile, "index.html")
        XCTAssertEqual(Set(loaded.files.keys), Set(files.keys), "Editable npm modules and their licenses must survive reopening")
        for path in files.keys { XCTAssertTrue(loaded.files[path] == files[path], "Source changed: \(path)") }
        let model = CompilerViewModel(projectLibrary: ProjectLibrary(storageURL: root.appending(path: "library/recent.json")))
        await model.openProject(from: root)
        XCTAssertTrue(model.canStartBuild, "Browser builds do not require the Rust compiler to finish setup")
        model.run()
        for _ in 0..<300 where model.isBusy { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertFalse(model.isBusy)
        XCTAssertTrue(model.result?.succeeded == true, model.result?.detail ?? "no result")
        XCTAssertNotNil(model.result?.webPreview)
        XCTAssertTrue(model.result?.detail.contains("133 browser modules") == true)
        model.performBrowserCommand(.build(run: false, directory: ""))
        for _ in 0..<300 where model.isBusy { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertTrue(model.result?.succeeded == true)
        XCTAssertNil(model.result?.webPreview, "npm run build checks/bundles without opening a browser")
        model.run()
        model.source += "\n<!-- edit while a snapshot is queued -->"
        for _ in 0..<300 where model.isBusy { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertNil(model.result, "A stale queued browser build must not publish over a newer edit")
    }

    func testUnpreparedHostNodeModulesAreIgnoredAndServerOnlyProjectCanBeInspected() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appending(path: "node_modules/demo"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: root.appending(path: "package.json"))
        try Data("ignored".utf8).write(to: root.appending(path: "node_modules/demo/index.js"))
        let project = try LocalProjectLoader.load(from: root)
        XCTAssertEqual(project.entryFile, "package.json")
        XCTAssertEqual(Set(project.files.keys), ["package.json"])
    }

    func testMissingPackageSyntaxAndServerErrorsAreActionable() async throws {
        let builder = BrowserProjectBuilder()
        let base = ["index.html": "<script type='module' src='/app.ts'></script>",
                    "package.json": "{\"dependencies\":{\"clsx\":\"2.1.1\"}}"]
        for (source, expected) in [("import clsx from 'clsx'; console.log(clsx('x'))", "npm install"),
                                   ("const x: = ;", "app.ts"),
                                   ("import fs from 'node:fs'", "server-only") ] {
            do {
                _ = try await builder.build(files: base.merging(["app.ts": source]) { _, b in b }, preferredEntry: "index.html")
                XCTFail("Expected a bounded browser build failure")
            } catch { XCTAssertTrue(error.localizedDescription.contains(expected), error.localizedDescription) }
        }
        do {
            _ = try await builder.build(files: ["package.json": "{}"], preferredEntry: "package.json", preparePackages: true, frozen: true)
            XCTFail("ci requires a lock")
        } catch { XCTAssertTrue(error.localizedDescription.contains("package-lock.json")) }
    }

    func testCiRejectsManifestDriftBeforePackageAcquisition() async throws {
        let files = ["index.html": "<script type='module' src='main.ts'></script>",
                     "main.ts": "import 'demo'", "package.json": "{\"dependencies\":{\"demo\":\"2.0.0\"}}",
                     "package-lock.json": "{\"lockfileVersion\":3,\"packages\":{\"\":{\"dependencies\":{\"demo\":\"1.0.0\"}}}}"]
        do { _ = try await BrowserProjectBuilder().build(files: files, preferredEntry: "index.html", preparePackages: true, frozen: true); XCTFail("Expected lock drift") }
        catch { XCTAssertTrue(error.localizedDescription.contains("disagree"), error.localizedDescription) }
    }

    func testRegistryIntegrityAndOriginChecksRejectChangedOrRemoteData() {
        let data = Data("verified archive".utf8)
        let sri = "sha512-" + Data(SHA512.hash(data: data)).base64EncodedString()
        XCTAssertTrue(BrowserNpmRegistry.valid(data, integrity: sri))
        XCTAssertFalse(BrowserNpmRegistry.valid(Data("changed".utf8), integrity: sri))
        for url in ["http://registry.npmjs.org/a", "https://example.com/a", "https://registry.npmjs.org.evil.test/a", "https://user@registry.npmjs.org/a", "https://registry.npmjs.org:444/a"] {
            XCTAssertFalse(BrowserNpmRegistry.permitted(URL(string: url)!), url)
        }
        XCTAssertTrue(BrowserNpmRegistry.permitted(URL(string: "https://registry.npmjs.org/react/-/react-19.2.0.tgz")!))
    }

    func testNestedBrowserEntryAndRustEntryRemainDistinct() {
        let files = ["src/main.rs": "fn main(){}", "web/package.json": "{}", "web/index.html": "", "web/src/app.tsx": ""]
        XCTAssertFalse(BrowserProjectConfiguration.isBrowserEntry("src/main.rs"))
        XCTAssertEqual(BrowserProjectConfiguration.entry(files: files, preferred: "src/main.rs", directory: "web/src"), "web/index.html")
        XCTAssertEqual(BrowserProjectConfiguration.manifestPath(files: files, entry: "web/src/app.tsx"), "web/package.json")
    }
}
