import Foundation
import ImageIO
import XCTest
@testable import Crabrix

final class InterviewCourseUpdateTests: XCTestCase {
    private func fixtures() throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(forResource: "InterviewRevision", withExtension: nil))
    }
    private func keys() throws -> CourseKeyring {
        let root = try XCTUnwrap(Bundle.main.url(forResource: "MigrationCoursePacks", withExtension: nil))
        return try JSONDecoder().decode(CourseKeyring.self, from: Data(contentsOf: root.appending(path: "production-keyring.json")))
    }
    func testProductionSignedUpdateLoads52UniqueQuestionsAndKeepsOldSession() async throws {
        let fixture = try fixtures(), keyring = try keys()
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = try CourseInstaller(root: root, appVersion: SemanticVersion("1.1.2"))
        let legacy = try XCTUnwrap(Bundle.main.url(forResource: "MigrationCoursePacks", withExtension: nil))
        _ = try await installer.install(descriptorBytes: Data(contentsOf: legacy.appending(path: "interview.descriptor.json")), downloadedArchive: legacy.appending(path: "interview-1.0.1.zip"), keyring: keyring)
        let before = try InstalledCourseRepository(root: root, records: await installer.installed(), keyring: keyring)
        let oldIDs = before.courses.flatMap(\.units).flatMap(\.lessons).map(\.id)
        let oldQuestion = before.writing(for: "q-ownership")?.question
        let oldCourseBytes = try Data(contentsOf: root.appending(path: "interview/en/1.0.1/course.json"))
        let catalogData = try Data(contentsOf: fixture.appending(path: "catalog.v1.json"))
        let catalog = try CoursePackVerifier.catalog(bytes: catalogData, keyring: keyring, lastAcceptedSequence: 15)
        XCTAssertEqual(catalog.sequence, 16)
        let latest = CourseUpdatePlanner.latestCompatible(in: catalog, appVersion: SemanticVersion("1.1.2")!)
        XCTAssertEqual(latest["interview|en"]?.contentVersion, "1.1.0")
        _ = try await installer.install(descriptorBytes: Data(contentsOf: fixture.appending(path: "interview.descriptor.json")), downloadedArchive: fixture.appending(path: "interview-1.1.0.zip"), keyring: keyring)
        let after = try InstalledCourseRepository(root: root, records: await installer.installed(), keyring: keyring)
        let lessons = after.courses.flatMap(\.units).flatMap(\.lessons)
        XCTAssertEqual(lessons.count, 52)
        XCTAssertEqual(Set(lessons.map(\.id)).count, 52)
        XCTAssertTrue(Set(oldIDs).isSubset(of: Set(lessons.map(\.id))))
        XCTAssertEqual(before.writing(for: "q-ownership")?.question, oldQuestion)
        XCTAssertEqual(before.courses.flatMap(\.units).flatMap(\.lessons).count, 40)
        XCTAssertEqual(try Data(contentsOf: root.appending(path: "interview/en/1.0.1/course.json")), oldCourseBytes)
        let questions = after.practiceQuestions()
        XCTAssertEqual(questions.count, 52)
        XCTAssertTrue(questions.allSatisfy(\.isWellFormed))
        let baseline = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture.appending(path: "baseline.json"))) as! [String: Any]
        for (id, value) in baseline["lessons"] as! [String: [String: Any]] {
            XCTAssertEqual(after.writing(for: id)?.correctAnswer, value["correctAnswer"] as? Int, id)
        }
        for lesson in lessons {
            let illustration = try XCTUnwrap(after.illustration(for: lesson.id))
            let image = try XCTUnwrap(CGImageSourceCreateWithURL(illustration.url as CFURL, nil))
            XCTAssertNotNil(CGImageSourceCreateImageAtIndex(image, 0, nil), lesson.id)
        }
        XCTAssertThrowsError(try CoursePackVerifier.catalog(bytes: catalogData, keyring: keyring, lastAcceptedSequence: 16))
        var damaged = try Data(contentsOf: fixture.appending(path: "interview-1.1.0.zip")); damaged[0] ^= 1
        let bad = root.appending(path: "bad.zip"); try damaged.write(to: bad)
        XCTAssertThrowsError(try CoursePackVerifier.verify(descriptorBytes: Data(contentsOf: fixture.appending(path: "interview.descriptor.json")), archiveURL: bad, keyring: keyring))
        let reopened = try InstalledCourseRepository(root: root, records: await installer.installed(), keyring: keyring)
        XCTAssertEqual(reopened.practiceQuestions().count, 52)
    }
    func testTwelveWorkedExamplesUseTheActualBundledOfflineCompiler() async throws {
        struct Example: Decodable { let id: String; let source: String }
        let examples = try JSONDecoder().decode([Example].self, from: Data(contentsOf: fixtures().appending(path: "worked-examples.json")))
        XCTAssertEqual(examples.count, 12)
        let compiler = WasmRustCompiler()
        for example in examples {
            let result = await compiler.run(source: example.source)
            XCTAssertTrue(result.succeeded, example.id + ": " + result.detail + "\n" + result.stderr)
            XCTAssertEqual(result.exitCode, 0, example.id)
        }
    }
}
