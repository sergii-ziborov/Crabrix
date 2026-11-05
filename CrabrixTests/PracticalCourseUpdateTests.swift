import Foundation
import XCTest
@testable import Crabrix

final class PracticalCourseUpdateTests: XCTestCase {
    func testFilesystemLabRejectsReturningTextWithoutWritingAFile() async throws {
        struct Fixture: Decodable { let negativeFileSource: String; let negativeFileHarness: String }
        let root = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "CompilerCandidate", withExtension: nil))
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: root.appending(path: "PracticeLabs.json")))
        let harness = try XCTUnwrap(LessonHarnessNonce.instrument(
            verificationSource: fixture.negativeFileHarness,
            expectedOutput: "PASS sandbox-file-roundtrip\n", nonce: "negative-file-check"
        ))
        let result = await WasmRustCompiler().run(source: harness.source, supportingFiles: ["solution.rs": fixture.negativeFileSource])
        XCTAssertEqual(result.phase, .run, result.detail)
        XCTAssertFalse(result.succeeded, "Returning the input without the filesystem effect must fail")
        XCTAssertFalse(LessonHarnessNonce.reveal(stdout: result.stdout, run: harness.run).completed)
    }

    func testThirtyOneTypedLabsRunWithTheBundledLocalWasmCompiler() async throws {
        struct Fixture: Decodable { let count: Int; let source: String; let expected: String }
        let root = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "CompilerCandidate", withExtension: nil))
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: root.appending(path: "PracticeLabs.json")))
        XCTAssertEqual(fixture.count, 31)
        let result = await WasmRustCompiler().run(source: fixture.source)
        XCTAssertTrue(result.succeeded, result.detail + "\n" + result.stderr)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.split(whereSeparator: \.isWhitespace).joined(separator: " "), fixture.expected)
    }

    /// Local publication qualification; the path contains only signed public packs.
    /// Keeping 90 MB of duplicate release archives out of the test bundle is deliberate.
    func testSignedPracticalUpdateLoadsWithoutChangingAnOldRepository() async throws {
        guard let path = ProcessInfo.processInfo.environment["CRABRIX_PRACTICE_PACKS"] else {
            throw XCTSkip("Set CRABRIX_PRACTICE_PACKS to the verified practice release directory.")
        }
        let packs = URL(fileURLWithPath: path)
        let legacy = try XCTUnwrap(Bundle.main.url(forResource: "MigrationCoursePacks", withExtension: nil))
        let keys = try JSONDecoder().decode(CourseKeyring.self, from: Data(contentsOf: legacy.appending(path: "production-keyring.json")))
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = try CourseInstaller(root: root, appVersion: SemanticVersion("1.1.5"))
        _ = try await installer.install(descriptorBytes: Data(contentsOf: legacy.appending(path: "basics.descriptor.json")), downloadedArchive: legacy.appending(path: "basics-1.0.1.zip"), keyring: keys)
        let before = try InstalledCourseRepository(root: root, records: await installer.installed(), keyring: keys)
        let oldIDs = before.courses.flatMap(\.units).flatMap(\.lessons).map(\.id)
        let oldQuestion = before.writing(for: "functions")?.question
        for (id, version) in [("basics", "1.0.8"), ("ownership", "1.0.8"), ("projects", "1.0.9"), ("concurrency", "1.0.7"), ("systems", "1.0.8")] {
            _ = try await installer.install(descriptorBytes: Data(contentsOf: packs.appending(path: "\(id).descriptor.json")), downloadedArchive: packs.appending(path: "\(id)-\(version).zip"), keyring: keys)
        }
        let after = try InstalledCourseRepository(root: root, records: await installer.installed(), keyring: keys)
        let lessons = after.courses.flatMap(\.units).flatMap(\.lessons)
        XCTAssertEqual(lessons.count, 119)
        XCTAssertEqual(Set(lessons.map(\.id)).count, 119)
        XCTAssertTrue(Set(oldIDs).isSubset(of: Set(lessons.map(\.id))))
        XCTAssertEqual(before.courses.flatMap(\.units).flatMap(\.lessons).map(\.id), oldIDs)
        XCTAssertEqual(before.writing(for: "functions")?.question, oldQuestion)
        XCTAssertEqual(after.writing(for: "functions")?.question, oldQuestion)
        XCTAssertEqual(after.loaded.values.reduce(0) { $0 + $1.challenges.count }, 31)
        for lesson in lessons where after.challenge(for: lesson.id) != nil {
            XCTAssertTrue(lesson.hasCompilerLab, lesson.id)
            let template = try XCTUnwrap(after.starterProject(for: lesson.id))
            XCTAssertEqual(template.entryFile, "solution.rs", lesson.id)
            let challenge = try XCTUnwrap(after.challenge(for: lesson.id))
            XCTAssertEqual(template.files["solution.rs"], challenge.source)
            XCTAssertNotNil(LessonHarnessNonce.instrument(verificationSource: challenge.verificationSource, expectedOutput: challenge.expectedOutput, nonce: "qualification"), lesson.id)
        }
    }
}
