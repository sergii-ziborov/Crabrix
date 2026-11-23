import Combine
import CryptoKit
import Foundation
import XCTest
import ZIPFoundation
@testable import Crabrix

/// Bridge lessons (`bridge-lessons-v1`): decoding, capability gating, credits
/// on the course path and their persistence.
@MainActor
final class LessonBridgeTests: XCTestCase {
    // MARK: Fixtures

    nonisolated private static let bridgeCourse = "rust-for-c-developers"

    private func bridgeJSON(credits: [String] = ["target-course/known-lesson", "absent-course/missing"],
                            from: String = "c", contrasts: Int = 2) -> [String: Any] {
        [
            "from": from, "fromLabel": "C",
            "fromCode": "#include <stdlib.h>\nint main(void) {\n    int *p = malloc(4);\n    free(p);\n}\n",
            "fromCaption": "`free` is a call you must remember on every path.",
            "contrasts": (0..<contrasts).map { ["from": "C row \($0)", "rust": "Rust row \($0)"] },
            "credits": credits,
        ]
    }

    private func decodeBridge(_ object: [String: Any]) throws -> CourseBridgeDTO {
        try JSONDecoder().decode(CourseBridgeDTO.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func lessonJSON(id: String, parent: String, order: Int, bridge: [String: Any]?) -> [String: Any] {
        var lesson: [String: Any] = [
            "id": id, "parentID": parent, "order": order, "title": "Title \(id)",
            "concept": "Concept \(id)", "minutes": 8, "exerciseKind": "planned",
            "writing": [
                "summary": "s", "explanation": "e", "exampleCaption": "Rust caption",
                "exampleCode": "fn main() {\n    let b = Box::new(4);\n}\n", "task": "t", "success": "ok",
                "rule": "r", "practiceCode": "let x = 1;", "question": "q?", "answers": ["a", "b"],
                "correctAnswer": 0, "feedback": "f",
                "recall": [["question": "Why \(id)?", "answer": "Because."]],
            ],
            "depth": [
                "traceSteps": [["title": "one", "detail": "d"]], "misconception": "m", "correction": "c",
                "transferChallenge": "x", "connections": [] as [Any],
            ],
        ]
        if let bridge { lesson["bridge"] = bridge }
        return lesson
    }

    /// A pack signed by a throwaway key, holding one unit of planned lessons.
    private struct SignedPack {
        let descriptor: Data
        let archive: URL

        init(courseID: String, theme: String, lessons: [[String: Any]], capabilities: [String],
             directory: URL, key: Curve25519.Signing.PrivateKey) throws {
            let unitID = "\(courseID)-unit"
            func json(_ object: Any) throws -> Data {
                try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            }
            var files: [(String, Data)] = []
            let course = try json([
                "id": courseID, "language": "en", "contentVersion": "1.0.0", "order": 9, "level": "BRIDGE",
                "title": courseID == LessonBridgeTests.bridgeCourse ? "Rust for C Developers" : "Target",
                "subtitle": "test", "systemImage": "book", "theme": theme, "unitIDs": [unitID],
            ] as [String: Any])
            files.append(("course.json", course))
            files.append(("terms.json", Data("[]".utf8)))
            files.append(("units/\(unitID).json", try json([
                "id": unitID, "parentID": courseID, "order": 0, "level": 1, "title": "Unit", "subtitle": "u",
                "lessonIDs": lessons.map { $0["id"] as! String },
            ] as [String: Any])))
            for lesson in lessons {
                let id = lesson["id"] as! String
                var placed = lesson
                placed["parentID"] = unitID
                files.append(("lessons/\(id).json", try json(placed)))
                files.append(("checks/\(id).json", try json(["evidence": ["kind": "reasoning", "correctAnswer": 0]])))
            }
            func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
            let manifest = try json([
                "schemaVersion": 1, "courseID": courseID, "language": "en", "contentVersion": "1.0.0",
                "files": files.map { ["path": $0.0, "bytes": $0.1.count, "sha256": digest($0.1)] as [String: Any] },
            ] as [String: Any])
            let name = "\(courseID)-1.0.0.zip"
            archive = directory.appending(path: name)
            let zip = try Archive(url: archive, accessMode: .create)
            for (path, bytes) in [("manifest.json", manifest)] + files {
                try zip.addEntry(with: path, type: .file, uncompressedSize: Int64(bytes.count)) { position, size in
                    bytes.subdata(in: Int(position)..<Int(position) + size)
                }
            }
            let zipped = try Data(contentsOf: archive)
            let payload = try json([
                "schemaVersion": 1, "courseID": courseID, "language": "en", "contentVersion": "1.0.0",
                "archiveName": name, "archiveBytes": zipped.count, "archiveSHA256": digest(zipped),
                "courseDigest": digest(course), "minimumAppVersion": "1.0", "requiredCapabilities": capabilities,
            ] as [String: Any])
            descriptor = try JSONEncoder().encode(CourseEnvelope(
                keyID: "test-key", payloadBase64: payload.base64EncodedString(),
                signatureBase64: try key.signature(for: CoursePackVerifier.descriptorDomain + payload)
                    .base64EncodedString()
            ))
        }
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "bridge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// Installs a target course and a bridge course that credits one of its lessons.
    private func installedRepository(
        bridgeCapabilities: [String] = ["coursepack-v1", "bridge-lessons-v1"],
        bridge: [String: Any]? = nil
    ) async throws -> InstalledCourseRepository {
        let work = try temporaryDirectory()
        let root = try temporaryDirectory()
        let key = Curve25519.Signing.PrivateKey()
        let keys = CourseKeyring(keys: ["test-key": key.publicKey.rawRepresentation.base64EncodedString()])
        let installer = try CourseInstaller(root: root, appVersion: SemanticVersion("1.2"))
        let target = try SignedPack(
            courseID: "target-course", theme: "basics",
            lessons: [lessonJSON(id: "first-lesson", parent: "", order: 0, bridge: nil),
                      lessonJSON(id: "known-lesson", parent: "", order: 1, bridge: nil)],
            capabilities: ["coursepack-v1"], directory: work, key: key
        )
        _ = try await installer.install(descriptorBytes: target.descriptor, downloadedArchive: target.archive, keyring: keys)
        let pack = try SignedPack(
            courseID: Self.bridgeCourse, theme: "bridges",
            lessons: [lessonJSON(id: "c-malloc-free", parent: "", order: 0, bridge: bridge ?? bridgeJSON())],
            capabilities: bridgeCapabilities, directory: work, key: key
        )
        _ = try await installer.install(descriptorBytes: pack.descriptor, downloadedArchive: pack.archive, keyring: keys)
        return try await installer.loadRepository(keyring: keys)
    }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "crabrix.tests.bridges.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    // MARK: Decoding

    func testValidBridgeDecodesIntoTheRuntimeModel() throws {
        let bridge = try decodeBridge(bridgeJSON()).runtimeBridge(courseID: Self.bridgeCourse, lessonID: "c-malloc-free")
        XCTAssertEqual(bridge.from, .c)
        XCTAssertEqual(bridge.from.snippetPath, "snippet.c")
        XCTAssertEqual(bridge.fromLabel, "C")
        XCTAssertEqual(bridge.contrasts.count, 2)
        XCTAssertEqual(bridge.credits, [
            .init(courseID: "target-course", lessonID: "known-lesson"),
            .init(courseID: "absent-course", lessonID: "missing"),
        ])
        let node = try decodeBridge(bridgeJSON(from: "typescript"))
            .runtimeBridge(courseID: "rust-for-nodejs-developers", lessonID: "node-x")
        XCTAssertEqual(node.from.snippetPath, "snippet.ts")
    }

    func testMalformedBridgeDataIsRefused() throws {
        func rejects(_ object: [String: Any], lessonID: String = "c-malloc-free",
                     file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertThrowsError(try decodeBridge(object).runtimeBridge(courseID: Self.bridgeCourse, lessonID: lessonID),
                                 file: file, line: line)
        }
        rejects(bridgeJSON(credits: ["no-slash"]))
        rejects(bridgeJSON(credits: ["a/b/c"]))
        rejects(bridgeJSON(credits: ["/lesson"]))
        rejects(bridgeJSON(credits: ["basics/../x"]))
        rejects(bridgeJSON(credits: ["basics/x", "basics/x"]))
        rejects(bridgeJSON(credits: ["\(Self.bridgeCourse)/other"]), lessonID: "c-malloc-free")
        rejects(bridgeJSON(credits: ["basics/c-malloc-free"]))
        rejects(bridgeJSON(credits: (0..<9).map { "basics/l\($0)" }))
        rejects(bridgeJSON(contrasts: 0))
        rejects(bridgeJSON(contrasts: 7))
        var blank = bridgeJSON()
        blank["fromCode"] = "  \n"
        rejects(blank)
        var label = bridgeJSON()
        label["fromLabel"] = "C\nC"
        rejects(label)
        var missing = bridgeJSON()
        missing.removeValue(forKey: "contrasts")
        XCTAssertThrowsError(try decodeBridge(missing))
        // A language this app does not know is a capability problem, not damage.
        XCTAssertThrowsError(try decodeBridge(bridgeJSON(from: "cobol"))
            .runtimeBridge(courseID: Self.bridgeCourse, lessonID: "c-malloc-free")) { error in
            guard case CoursePackError.incompatibleCapability = error else {
                return XCTFail("Expected incompatibleCapability, got \(error)")
            }
        }
    }

    // MARK: Capability gating

    func testCapabilityIsSupportedAndUnknownCapabilitiesStayRejected() throws {
        func entry(_ capabilities: [String]) throws -> CourseCatalogPayload.Entry {
            try JSONDecoder().decode(CourseCatalogPayload.Entry.self, from: JSONSerialization.data(withJSONObject: [
                "courseID": Self.bridgeCourse, "language": "en", "contentVersion": "1.0.0",
                "descriptorURL": "https://example.invalid/d.json", "descriptorSHA256": "00",
                "archiveURL": "https://example.invalid/a.zip", "archiveSHA256": "00", "archiveBytes": 10,
                "minimumAppVersion": "1.0", "requiredCapabilities": capabilities,
            ] as [String: Any]))
        }
        XCTAssertTrue(CourseCompatibility.supportedCapabilities.contains("bridge-lessons-v1"))
        XCTAssertTrue(CourseCompatibility.supports(try entry(["coursepack-v1", "bridge-lessons-v1"]),
                                                   appVersion: SemanticVersion("1.2")!))
        XCTAssertFalse(CourseCompatibility.supports(try entry(["coursepack-v1", "bridge-lessons-v2"]),
                                                    appVersion: SemanticVersion("1.2")!))
    }

    func testInstalledBridgePackExposesBridgeAndInstalledCreditTargets() async throws {
        let repository = try await installedRepository()
        XCTAssertTrue(repository.unavailable.isEmpty, "\(repository.unavailable)")
        XCTAssertEqual(repository.course(id: Self.bridgeCourse)?.theme, .bridges)
        let bridge = try XCTUnwrap(repository.bridge(for: "c-malloc-free"))
        XCTAssertEqual(bridge.fromLabel, "C")
        XCTAssertNil(repository.bridge(for: "known-lesson"))
        // The absent course is tolerated and skipped.
        XCTAssertEqual(repository.creditTargets(for: "c-malloc-free"), ["known-lesson"])
        XCTAssertEqual(repository.creditTargets(for: "known-lesson"), [])
        let session = try XCTUnwrap(CourseSession(lessonID: "c-malloc-free", repository: repository))
        let lesson = try XCTUnwrap(repository.lesson(id: "c-malloc-free"))
        XCTAssertEqual(CourseLessonExecution(lesson: lesson, session: session)?.creditTargets, ["known-lesson"])
    }

    /// The production-signed packs from the GitHub pre-release, downloaded into
    /// a folder: `TEST_RUNNER_CRABRIX_BRIDGE_PACKS=/path xcodebuild test …`.
    func testProductionSignedBridgePacksInstallAndDecode() async throws {
        guard let folder = ProcessInfo.processInfo.environment["CRABRIX_BRIDGE_PACKS"] else {
            throw XCTSkip("Set CRABRIX_BRIDGE_PACKS to the downloaded bridge release assets.")
        }
        let packs = URL(fileURLWithPath: folder)
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bootstrap = try CourseBootstrap(bundle: .main, root: root.appending(path: "bootstrap"),
                                            appVersion: XCTUnwrap(SemanticVersion("1.1.9")))
        let installer = try CourseInstaller(root: root.appending(path: "installed"),
                                            appVersion: XCTUnwrap(SemanticVersion("1.1.9")))
        for course in ["rust-for-c-developers", "rust-for-nodejs-developers"] {
            let archive = try XCTUnwrap(FileManager.default.contentsOfDirectory(atPath: packs.path)
                .first { $0.hasPrefix("\(course)-") && $0.hasSuffix(".zip") }, course)
            _ = try await installer.install(
                descriptorBytes: Data(contentsOf: packs.appending(path: "\(course).descriptor.json")),
                downloadedArchive: packs.appending(path: archive),
                keyring: bootstrap.keyring()
            )
        }
        let repository = try await installer.loadRepository(keyring: bootstrap.keyring())
        XCTAssertTrue(repository.unavailable.isEmpty, "\(repository.unavailable)")
        for (course, label, credits) in [("rust-for-c-developers", "C", 32),
                                         ("rust-for-nodejs-developers", "JavaScript (Node.js)", 33)] {
            let loaded = try XCTUnwrap(repository.course(id: course), course)
            XCTAssertEqual(loaded.theme, .bridges)
            let lessons = loaded.units.flatMap(\.lessons)
            XCTAssertEqual(lessons.count, 20, course)
            XCTAssertTrue(lessons.first?.id.hasSuffix("what-rust-is") == true, course)
            let bridges = try lessons.map { try XCTUnwrap(repository.bridge(for: $0.id), $0.id) }
            XCTAssertEqual(bridges.map(\.credits.count).reduce(0, +), credits, course)
            XCTAssertTrue(bridges.contains { $0.fromLabel == label }, course)
        }
    }

    func testBridgeDataWithoutTheCapabilityOrMalformedIsRefusedAtInstall() async throws {
        do {
            _ = try await installedRepository(bridgeCapabilities: ["coursepack-v1"])
            XCTFail("A pack with bridge data but no bridge capability was installed")
        } catch CoursePackError.manifestMismatch {}
        do {
            _ = try await installedRepository(bridge: bridgeJSON(credits: ["broken"]))
            XCTFail("A malformed bridge was installed")
        } catch CoursePackError.manifestMismatch {}
    }

    // MARK: Progression

    private func course(_ id: String, _ lessons: [String]) -> RustCourse {
        RustCourse(id: id, level: "1", title: id == Self.bridgeCourse ? "Rust for C Developers" : id,
                   subtitle: "", systemImage: "book", theme: .basics, units: [
            RustLearningUnit(id: "\(id)-u", level: 1, title: "", subtitle: "", lessons: lessons.map {
                RustLesson(id: $0, title: $0, concept: "", minutes: 5, exercise: .planned)
            }),
        ])
    }

    func testCreditedLessonsCountAsDoneForUnlockingProgressAndContinue() {
        let basics = course("basics", ["hello-rust", "variables", "loops"])
        let bridge = course(Self.bridgeCourse, ["c-one", "c-two"])
        let courses = [basics, bridge]
        let credited = LessonCredits.completing(
            "c-one", targets: ["hello-rust", "variables"], completed: ["c-one"], credited: [:]
        )
        XCTAssertEqual(credited, ["hello-rust": "c-one", "variables": "c-one"])
        let learned = LessonCredits.learned(completed: ["c-one"], credited: credited)
        XCTAssertEqual(RustLessonProgression.readyLessonIDs(in: basics.units, completedLessonIDs: learned, scope: .course),
                       ["loops"])
        XCTAssertEqual(RustLessonProgression.completedCount(in: basics.units, completedLessonIDs: learned), 2)
        XCTAssertTrue(RustLessonProgression.isOpen(.init(courseID: "basics", lessonID: "loops"),
                                                   completedLessonIDs: learned, courses: courses))
        XCTAssertEqual(RustLessonProgression.nextStep(after: nil, completedLessonIDs: learned, courses: courses),
                       .init(courseID: "basics", lessonID: "loops"))
        // Without the credit the course still starts at its first lesson.
        XCTAssertEqual(RustLessonProgression.readyLessonIDs(in: basics.units, completedLessonIDs: ["c-one"], scope: .course),
                       ["hello-rust"])
        XCTAssertEqual(LessonCredits.knownLabel(forCourseTitle: "Rust for C Developers"), "Known from C")
        XCTAssertEqual(LessonCredits.knownLabel(forCourseTitle: "Rust for Node.js Developers"), "Known from Node.js")
        XCTAssertEqual(LessonCredits.knownLabel(forCourseTitle: "Bridges"), "Known from Bridges")
        XCTAssertEqual(LessonCredits.knownLabel(forCourseTitle: nil), "Known from a bridge course")
        let targets = LessonCredits.targets(for: LessonBridge(
            from: .c, fromLabel: "C", fromCode: "x", fromCaption: "y", contrasts: [.init(from: "a", rust: "b")],
            credits: [.init(courseID: "basics", lessonID: "loops"), .init(courseID: "basics", lessonID: "nope"),
                      .init(courseID: "ownership", lessonID: "ownership")]
        ), courses: courses)
        XCTAssertEqual(targets, ["loops"])
    }

    func testFlashcardsIncludeCreditedLessons() {
        let card = Flashcard(id: "basics/variables/recall-0", courseID: "basics", courseTitle: "Rust Basics",
                             lessonID: "variables", lessonTitle: "Variables", kind: .concept,
                             prompt: "Why?", answer: "Because.", code: nil)
        XCTAssertTrue(FlashcardDeck.learned([card], completedLessonIDs: ["c-one"]).isEmpty)
        let learned = LessonCredits.learned(completed: ["c-one"], credited: ["variables": "c-one"])
        XCTAssertEqual(FlashcardDeck.learned([card], completedLessonIDs: learned), [card])
    }

    // MARK: View model, rewards and reset

    func testCompletingABridgeLessonCreditsWithoutCountingAsCompletion() {
        let defaults = isolatedDefaults()
        let model = CompilerViewModel(userDefaults: defaults)
        model.completeLesson("hello-rust")
        var emissions: [Set<String>] = []
        let observation = model.$completedLessonIDs.dropFirst().sink { emissions.append($0) }
        defer { observation.cancel() }

        model.completeLesson("c-one", credits: ["hello-rust", "variables", "loops", "c-one"])

        // Rating comes from new entries in completedLessonIDs; credits never get there.
        XCTAssertEqual(emissions, [["hello-rust", "c-one"]])
        XCTAssertEqual(model.completedLessonIDs, ["hello-rust", "c-one"])
        XCTAssertEqual(model.creditedLessonIDs, ["variables": "c-one", "loops": "c-one"])
        XCTAssertEqual(model.learnedLessonIDs, ["hello-rust", "c-one", "variables", "loops"])
        XCTAssertEqual(defaults.dictionary(forKey: LearningProgressKeys.credited) as? [String: String],
                       ["variables": "c-one", "loops": "c-one"])

        // Finishing a credited lesson turns it into a regular completion.
        model.completeLesson("variables")
        XCTAssertTrue(model.completedLessonIDs.contains("variables"))
        XCTAssertEqual(model.creditedLessonIDs, ["loops": "c-one"])

        let reopened = CompilerViewModel(userDefaults: defaults)
        XCTAssertEqual(reopened.creditedLessonIDs, ["loops": "c-one"])
        XCTAssertEqual(reopened.completedLessonIDs, ["hello-rust", "c-one", "variables"])
    }

    func testResetClearsCreditsAndRevokesWhatABridgeCourseGranted() {
        let defaults = isolatedDefaults()
        let model = CompilerViewModel(userDefaults: defaults)
        let targets: [String: [String]] = [
            "c-one": ["hello-rust", "variables", "loops"], "node-one": ["loops"],
        ]
        model.completeLesson("hello-rust")
        model.completeLesson("c-one", credits: targets["c-one"]!)
        model.completeLesson("node-one", credits: targets["node-one"]!)
        // Already completed lessons are not credited; the first bridge keeps its credit.
        XCTAssertEqual(model.creditedLessonIDs, ["variables": "c-one", "loops": "c-one"])

        // Resetting the C bridge course revokes its credits; another completed
        // bridge lesson still vouching for `loops` keeps it known, and the real
        // completion of `hello-rust` stays.
        model.resetCourseProgress(lessonIDs: ["c-one"]) { targets[$0] ?? [] }
        XCTAssertFalse(model.completedLessonIDs.contains("c-one"))
        XCTAssertEqual(model.creditedLessonIDs, ["loops": "node-one"])
        XCTAssertTrue(model.completedLessonIDs.contains("hello-rust"))

        // Resetting the target course clears its credits and does not re-grant them.
        model.resetCourseProgress(lessonIDs: ["hello-rust", "variables", "loops"]) { targets[$0] ?? [] }
        XCTAssertEqual(model.creditedLessonIDs, [:])
        XCTAssertNil(defaults.object(forKey: LearningProgressKeys.credited))
        XCTAssertEqual(model.completedLessonIDs, ["node-one"])
        XCTAssertEqual(CompilerViewModel(userDefaults: defaults).creditedLessonIDs, [:])
    }

    func testRevokedCreditIsRegrantedOnlyBySourcesThatVouchForIt() {
        let credited = LessonCredits.afterReset(
            ["c-one"], completed: ["c-one", "loops", "node-two"], credited: ["variables": "c-one", "ranges": "c-one"],
            creditTargets: { source in
                switch source {
                case "node-two": ["ranges", "loops"]
                case "c-one": ["variables", "ranges"]
                default: []
                }
            }
        )
        // `loops` is a real completion, so it is never written as a credit.
        XCTAssertEqual(credited, ["ranges": "node-two"])
    }

    // MARK: Archive and backup

    private func snapshot(credited: [String: String]) throws -> LearningProgressSnapshot {
        LearningProgressSnapshot(
            schemaVersion: 1, id: UUID().uuidString, createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            deviceFamily: "iPhone", progressData: try JSONEncoder().encode(CrabrixProgressState()),
            completedLessonIDs: ["c-one"], answers: [:], mastery: [:], flashcards: [], lessonResetDates: [:],
            termTrainSessions: 0, codeRecallSessions: 0, flashcardSessions: 0, creditedLessonIDs: credited
        )
    }

    func testBackupRoundTripsCreditsAndOmitsAnEmptyMap() throws {
        let original = try snapshot(credited: ["variables": "c-one", "c-one": "c-two"]).validated()
        // A lesson completed for real is no longer only credited.
        XCTAssertEqual(original.creditedLessonIDs, ["variables": "c-one"])
        XCTAssertTrue(original.hasProgress)
        let decoded = try LearningBackupCodec.decode(LearningBackupCodec.encode(original))
        XCTAssertEqual(decoded, original)

        let plain = try snapshot(credited: [:]).validated()
        let json = try XCTUnwrap(String(data: LearningBackupCodec.json(plain), encoding: .utf8))
        XCTAssertFalse(json.contains("creditedLessonIDs"), "No credits must keep the old byte layout")

        var invalid = try snapshot(credited: ["variables": ""])
        XCTAssertThrowsError(try invalid.validated())
        invalid.creditedLessonIDs = ["loop": "loop"]
        XCTAssertThrowsError(try invalid.validated())
    }

    func testLegacyBackupWithoutCreditsStillRestores() throws {
        let plain = try snapshot(credited: [:]).validated()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: LearningBackupCodec.json(plain)) as? [String: Any])
        XCTAssertNil(object["creditedLessonIDs"])
        object["completedLessonIDs"] = ["borrowing"]
        let legacy = try JSONDecoder().decode(
            LearningProgressSnapshot.self, from: JSONSerialization.data(withJSONObject: object)
        )
        XCTAssertEqual(legacy.creditedLessonIDs, [:])
        XCTAssertEqual(legacy.completedLessonIDs, ["borrowing"])
        XCTAssertNoThrow(try legacy.validated())
    }

    func testPreferencesCaptureAndApplyCredits() throws {
        let domain = "CrabrixBridgeBackupTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(["c-one"], forKey: LearningProgressKeys.completed)
        defaults.set(["variables": "c-one"], forKey: LearningProgressKeys.credited)
        let captured = try LearningProgressPreferences.captureBase(defaults: defaults, deviceFamily: "iPad")
        XCTAssertEqual(captured.creditedLessonIDs, ["variables": "c-one"])

        // Restoring a backup from before credits existed leaves no stale credits.
        try LearningProgressPreferences.apply(try snapshot(credited: [:]), generation: UUID().uuidString,
                                              defaults: defaults, domain: domain)
        XCTAssertNil(defaults.object(forKey: LearningProgressKeys.credited))
        try LearningProgressPreferences.apply(try snapshot(credited: ["loops": "c-one"]), generation: UUID().uuidString,
                                              defaults: defaults, domain: domain)
        XCTAssertEqual(defaults.dictionary(forKey: LearningProgressKeys.credited) as? [String: String], ["loops": "c-one"])

        defaults.set("not a dictionary", forKey: LearningProgressKeys.credited)
        XCTAssertThrowsError(try LearningProgressPreferences.captureBase(defaults: defaults, deviceFamily: "iPad"))
    }

    // MARK: Highlighting

    func testCSnippetsAreHighlighted() {
        let tokens = SyntaxHighlighter.tokens(in: "#include <stdio.h>\nint main(void) { return 0; } // done\n",
                                              filePath: "snippet.c")
        let kinds = Set(tokens.map(\.kind))
        XCTAssertTrue(kinds.isSuperset(of: [.attribute, .type, .keyword, .number, .comment]))
    }
}
