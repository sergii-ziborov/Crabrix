import Foundation
import XCTest
@testable import Crabrix

/// Uses the released compiler, not ArtifactMacro or a host Cargo executable.
final class LocalCargoLessonTests: XCTestCase {
    private struct Fixture: Decodable {
        let name: String
        let expected: String
        let document: Document
        struct Document: Decodable { let entryFile: String; let files: [String: String] }
    }
    private struct FrozenIndex: CrateIndexProviding {
        let root: URL
        func indexFile(for crate: String) async throws -> RegistryIndexFile {
            throw CrateRegistryError.transport("Network forbidden during local lesson qualification")
        }
        func cachedIndexFile(for crate: String) async throws -> RegistryIndexFile {
            try SparseRegistryIndex.parse(Data(contentsOf: root.appending(path: crate + ".index")), name: crate)
        }
    }
    private final class DenyNetwork: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
        override func stopLoading() {}
    }
    private final class Recorder: @unchecked Sendable {
        let lock = NSLock()
        weak var session: RustDebugSession?
        private var count = 0
        var pauses: Int { lock.withLock { count } }
        func receive(_ pause: RustDebugPause) {
            let value = lock.withLock { count += 1; return count }
            if value > 1000 { session?.stop() } else { session?.resume(.into) }
        }
    }
    func testSignedCargoLessonUpdatePreservesTheOpenedCourseSnapshot() async throws {
        guard let path = ProcessInfo.processInfo.environment["CRABRIX_LOCAL_CARGO_PACKS"],
              let previous = ProcessInfo.processInfo.environment["CRABRIX_PREVIOUS_PRACTICE_PACKS"] else {
            throw XCTSkip("Set both signed old/new pack directories for publication qualification.")
        }
        let baseline = try XCTUnwrap(Bundle.main.url(forResource: "MigrationCoursePacks", withExtension: nil))
        let keys = try JSONDecoder().decode(CourseKeyring.self, from: Data(contentsOf: baseline.appending(path: "production-keyring.json")))
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = try CourseInstaller(root: root, appVersion: SemanticVersion("1.1.5"))
        for (folder, versions) in [(previous, [("projects", "1.0.9"), ("concurrency", "1.0.7")]), (path, [("projects", "1.0.10"), ("concurrency", "1.0.8")])] {
            for (course, version) in versions {
                let directory = URL(fileURLWithPath: folder)
                _ = try await installer.install(descriptorBytes: Data(contentsOf: directory.appending(path: course + ".descriptor.json")), downloadedArchive: directory.appending(path: course + "-" + version + ".zip"), keyring: keys)
            }
            if folder == previous {
                let opened = try InstalledCourseRepository(root: root, records: await installer.installed(), keyring: keys)
                XCTAssertNotNil(opened.lesson(id: "serde-roundtrip-validation"))
                // Retain it across installation; an in-progress session must not
                // turn into a new lesson revision underneath an open question.
                oldSnapshot = opened
            }
        }
        let after = try InstalledCourseRepository(root: root, records: await installer.installed(), keyring: keys)
        let before = try XCTUnwrap(oldSnapshot)
        XCTAssertEqual(before.writing(for: "serde-roundtrip-validation")?.question, after.writing(for: "serde-roundtrip-validation")?.question)
        XCTAssertNil(before.starterProject(for: "serde-roundtrip-validation"))
        for id in ["serde-roundtrip-validation", "joinset-task-ownership", "semaphore-backpressure", "graceful-shutdown-protocol", "async-runtime"] {
            let project = try XCTUnwrap(after.starterProject(for: id))
            XCTAssertEqual(project.entryFile, "src/main.rs")
            XCTAssertNotNil(project.files["Cargo.lock"])
            XCTAssertNotNil(project.files["Cargo.toml"])
            XCTAssertTrue(after.lesson(id: id)?.hasCompilerLab == true)
        }
    }
    private var oldSnapshot: InstalledCourseRepository?

    func testFiveCargoLessonsRunAndDebugOfflineWithReleasedToolchain() async throws {
        guard let path = ProcessInfo.processInfo.environment["CRABRIX_LOCAL_CARGO_FIXTURES"] else {
            throw XCTSkip("Set CRABRIX_LOCAL_CARGO_FIXTURES to the checksum-verified local registry fixture directory.")
        }
        let root = URL(fileURLWithPath: path)
        let bundled = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "CompilerCandidate", withExtension: nil))
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: bundled.appending(path: "LocalCargoLessons.json")))
        XCTAssertEqual(fixtures.count, 5)
        // All archive bytes are checked again by CrateStore against Cargo.lock
        // and the actual registry index; no trust in an extracted fixture tree.
        let pins = try XCTUnwrap(CrateStorageLayout.pinnedArchiveDirectory)
        try FileManager.default.createDirectory(at: pins, withIntermediateDirectories: true)
        for file in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) where file.pathExtension == "crate" {
            try Data(contentsOf: file).write(to: pins.appending(path: file.lastPathComponent), options: .atomic)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DenyNetwork.self]
        let store = CrateStore(session: URLSession(configuration: configuration))
        let artifacts = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: artifacts) }
        let compiler = WasmRustCompiler(dependencyArtifactRoot: artifacts)
        for fixture in fixtures {
            let files = fixture.document.files
            let plan = try await CargoPackageManager(index: FrozenIndex(root: root), store: store)
                .prepare(manifestSource: try XCTUnwrap(files["Cargo.toml"]), lockfileSource: try XCTUnwrap(files["Cargo.lock"]), mode: .frozen)
            XCTAssertTrue(plan.blockingPackages.isEmpty, fixture.name + ": " + plan.blockingPackages.description)
            var supporting = files
            let source = try XCTUnwrap(supporting.removeValue(forKey: fixture.document.entryFile))
            let run = await compiler.run(source: source, sourcePath: fixture.document.entryFile, supportingFiles: supporting, plan: plan.plan)
            XCTAssertTrue(run.succeeded, fixture.name + "\n" + run.detail + run.stderr)
            XCTAssertTrue(run.stdout.contains(fixture.expected), run.stdout)
            let recorder = Recorder()
            let debug = RustDebugSession(onPlan: { _ in }, onPause: recorder.receive)
            recorder.session = debug
            let result = await compiler.debug(source: source, sourcePath: fixture.document.entryFile, supportingFiles: supporting, plan: plan.plan, session: debug)
            XCTAssertTrue(result.succeeded, fixture.name + "\n" + result.detail + result.stderr)
            XCTAssertEqual(result.stdout, run.stdout)
            XCTAssertGreaterThan(recorder.pauses, 0)
            print("LOCAL CARGO LESSON", fixture.name, "RUN/DEBUG", recorder.pauses)
        }
    }
}
