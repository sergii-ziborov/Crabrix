import XCTest
@testable import Crabrix

// Learn with AI (docs/ai-learning/PLAN.md, Phases 5–7). The feature is
// additive: these tests pin the AI Learning State v1 export, the prompts and
// setup steps shared with the website, the pause switch and the feedback
// flags, and prove that none of it touches existing learning data.

final class AILearningStateEncoderTests: XCTestCase {
    private let producer = AILearningState.Producer(version: "1.2.0", build: "140")
    private var fixtureDate: Date {
        ISO8601DateFormatter().date(from: "2026-11-23T18:00:00Z")!
    }
    private let fixtureProgress = AILearningState.Progress(
        completed: ["variables", "borrowing", "retired-lesson"],
        credited: [
            "functions": "node-functions",
            // Finished by the learner as well: a completion, not a credit.
            "borrowing": "c-borrowing",
            // Its course is no longer installed.
            "loops": "node-loops",
        ],
        courseIDs: ["variables": "basics", "borrowing": "ownership", "functions": "basics"]
    )

    private func json(currentLesson: AILearningLessonRef?, progress: AILearningState.Progress?) throws -> String {
        let data = try AILearningState.encode(
            now: fixtureDate, producer: producer, currentLesson: currentLesson, progress: progress
        )
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    func testFixtureEncodesToExactlyThePlannedJSON() throws {
        let output = try json(
            currentLesson: AILearningLessonRef(courseId: "ownership", lessonId: "borrowing"),
            progress: fixtureProgress
        )
        XCTAssertEqual(output, """
        {
          "aiSession" : {},
          "currentLesson" : {
            "courseId" : "ownership",
            "lessonId" : "borrowing"
          },
          "evidence" : [],
          "format" : "crabrix.ai-learning-state",
          "learner" : {},
          "learningPath" : null,
          "officialProgress" : {
            "appVersion" : "1.2.0 (140)",
            "capturedAt" : "2026-11-23T18:00:00Z",
            "completed" : [
              {
                "courseId" : "ownership",
                "lessonId" : "borrowing"
              },
              {
                "courseId" : null,
                "lessonId" : "retired-lesson"
              },
              {
                "courseId" : "basics",
                "lessonId" : "variables"
              }
            ],
            "credited" : [
              {
                "courseId" : "basics",
                "lessonId" : "functions",
                "viaLessonId" : "node-functions"
              },
              {
                "courseId" : null,
                "lessonId" : "loops",
                "viaLessonId" : "node-loops"
              }
            ],
            "source" : "crabrix-ios"
          },
          "producer" : "crabrix-ios 1.2.0 (140)",
          "schemaVersion" : 1,
          "teachingMode" : "guided",
          "updatedAt" : "2026-11-23T18:00:00Z"
        }
        """)
    }

    func testToggleOffExportsNoProgressAtAll() throws {
        let output = try json(currentLesson: nil, progress: nil)
        XCTAssertEqual(output, """
        {
          "aiSession" : {},
          "currentLesson" : null,
          "evidence" : [],
          "format" : "crabrix.ai-learning-state",
          "learner" : {},
          "learningPath" : null,
          "officialProgress" : null,
          "producer" : "crabrix-ios 1.2.0 (140)",
          "schemaVersion" : 1,
          "teachingMode" : "guided",
          "updatedAt" : "2026-11-23T18:00:00Z"
        }
        """)
        for lesson in fixtureProgress.completed.union(fixtureProgress.credited.keys) {
            XCTAssertFalse(output.contains(lesson), "\(lesson) must not leave with the toggle off")
        }
        // The prompt embeds a state only when the learner included it.
        XCTAssertEqual(AcademyAIPrompts.continuePrompt(stateJSON: nil), AcademyAIPrompts.continueLearning.text)
    }

    func testCreditsExcludeCompletedLessonsAndUnknownCoursesAreNull() throws {
        let document = AILearningState.document(
            now: fixtureDate, producer: producer, currentLesson: nil, progress: fixtureProgress
        )
        let official = try XCTUnwrap(document.officialProgress)
        XCTAssertEqual(official.completed.map(\.lessonId), ["borrowing", "retired-lesson", "variables"])
        XCTAssertEqual(official.credited.map(\.lessonId), ["functions", "loops"])
        XCTAssertFalse(official.credited.contains { $0.lessonId == "borrowing" })
        XCTAssertNil(official.completed[1].courseId)
        XCTAssertNil(official.credited[1].courseId)
        XCTAssertEqual(official.credited[0].viaLessonId, "node-functions")
    }

    func testCourseIDsComeFromTheInstalledRepository() {
        func course(_ id: String, _ lessons: [String]) -> RustCourse {
            RustCourse(id: id, level: "1", title: id, subtitle: "", systemImage: "book", theme: .basics, units: [
                RustLearningUnit(id: "\(id)-u", level: 1, title: "", subtitle: "", lessons: lessons.map {
                    RustLesson(id: $0, title: $0, concept: "", minutes: 5, exercise: .planned)
                }),
            ])
        }
        let progress = AILearningState.Progress(
            completed: ["variables", "gone"], credited: [:],
            courses: [course("basics", ["variables", "loops"]), course("ownership", ["borrowing"])]
        )
        XCTAssertEqual(progress.courseIDs, ["variables": "basics", "loops": "basics", "borrowing": "ownership"])
        let official = AILearningState.document(now: fixtureDate, producer: producer, currentLesson: nil, progress: progress)
            .officialProgress
        XCTAssertEqual(official?.completed, [
            .init(courseId: nil, lessonId: "gone"), .init(courseId: "basics", lessonId: "variables"),
        ])
    }

    func testOutputIsDeterministicWhateverTheInputOrder() throws {
        let first = try json(currentLesson: nil, progress: fixtureProgress)
        let reordered = AILearningState.Progress(
            completed: Set(fixtureProgress.completed.sorted().reversed()),
            credited: Dictionary(uniqueKeysWithValues: fixtureProgress.credited.sorted { $0.key > $1.key }),
            courseIDs: fixtureProgress.courseIDs
        )
        XCTAssertEqual(first, try json(currentLesson: nil, progress: reordered))
        XCTAssertEqual(first, try json(currentLesson: nil, progress: fixtureProgress))
    }

    /// Lesson IDs only: no answers, flashcards, mastery, rating, code, room
    /// links, credentials or file paths, and nothing a schema reader rejects.
    func testExportHasOnlySchemaFieldsAndNoForbiddenContent() throws {
        let hostile = AILearningState.Progress(
            completed: ["variables", "Bad_ID", "example/ascii-histogram", "../etc/passwd",
                        "https://crabrix.com/playground/#room=abc&key=secret", "/Users/learner/project", ""],
            credited: ["functions": "node-functions", "loops": "ghp_0123456789abcdef", "/private": "x"],
            courseIDs: ["variables": "basics", "functions": "Not A Course"]
        )
        let data = try AILearningState.encode(
            now: fixtureDate, producer: producer,
            currentLesson: AILearningLessonRef(courseId: "basics", lessonId: "../../escape"),
            progress: hostile
        )
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        // No links, paths or room fragments survive: not even a slash.
        XCTAssertFalse(text.contains("/"), text)
        for forbidden in ["room", "key", "secret", "ghp_", "Bad_ID", "passwd", "Users", "Not A Course",
                          "answer", "flashcard", "mastery", "points", "rating", "code", "project"] {
            XCTAssertFalse(text.lowercased().contains(forbidden.lowercased()), "\(forbidden) leaked: \(text)")
        }
        XCTAssertLessThan(data.count, 512 * 1_024)

        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(root.keys), ["format", "schemaVersion", "updatedAt", "producer", "learningPath",
                                        "teachingMode", "currentLesson", "learner", "aiSession",
                                        "officialProgress", "evidence"])
        XCTAssertEqual(root["format"] as? String, "crabrix.ai-learning-state")
        XCTAssertEqual(root["schemaVersion"] as? Int, 1)
        XCTAssertTrue(root["currentLesson"] is NSNull, "an invalid lesson reference is left out")
        XCTAssertEqual((root["learner"] as? [String: Any])?.count, 0)
        XCTAssertEqual((root["aiSession"] as? [String: Any])?.count, 0)
        XCTAssertEqual((root["evidence"] as? [Any])?.count, 0)
        let official = try XCTUnwrap(root["officialProgress"] as? [String: Any])
        XCTAssertEqual(Set(official.keys), ["source", "capturedAt", "appVersion", "completed", "credited"])
        let completed = try XCTUnwrap(official["completed"] as? [[String: Any]])
        let credited = try XCTUnwrap(official["credited"] as? [[String: Any]])
        XCTAssertEqual(completed.map { $0["lessonId"] as? String }, ["variables"])
        XCTAssertEqual(credited.map { $0["lessonId"] as? String }, ["functions"])
        XCTAssertTrue(credited[0]["courseId"] is NSNull, "an invalid course id is exported as null")
        let time = try NSRegularExpression(pattern: #"^20[2-9][0-9]-[01][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]Z$"#)
        for value in [root["updatedAt"], official["capturedAt"]] {
            let string = try XCTUnwrap(value as? String)
            XCTAssertEqual(time.numberOfMatches(in: string, range: NSRange(string.startIndex..., in: string)), 1, string)
        }
        for entry in completed + credited {
            for key in entry.keys { XCTAssertTrue(["courseId", "lessonId", "viaLessonId"].contains(key), key) }
            for case let value as String in entry.values {
                XCTAssertTrue(AILearningState.isIdentifier(value), value)
            }
        }
    }

    func testIdentifierRuleMatchesTheSchemaPattern() {
        for valid in ["a", "basics", "c-malloc-free-to-ownership", "lesson.2", "0-start", String(repeating: "a", count: 160)] {
            XCTAssertTrue(AILearningState.isIdentifier(valid), valid)
        }
        for invalid in ["", "-lead", ".lead", "Upper", "snake_case", "with space", "a/b", "é", String(repeating: "a", count: 161)] {
            XCTAssertFalse(AILearningState.isIdentifier(invalid), invalid)
        }
    }

    func testEntryCountsAreCappedAtTheReaderLimit() throws {
        let many = Set((0...AILearningState.maximumEntries).map { "lesson-\($0)" })
        let document = AILearningState.document(
            now: fixtureDate, producer: producer, currentLesson: nil,
            progress: .init(completed: many, credited: [:], courseIDs: [:])
        )
        XCTAssertEqual(document.officialProgress?.completed.count, AILearningState.maximumEntries)
    }

    func testFileIsNamedForTheShareSheetAndMatchesTheEncoder() throws {
        XCTAssertEqual(AILearningState.fileName, "crabrix-learning-state.json")
        let file = AILearningStateFile(currentLesson: nil, progress: fixtureProgress, producer: producer)
        XCTAssertEqual(try file.data(now: fixtureDate),
                       try AILearningState.encode(now: fixtureDate, producer: producer, currentLesson: nil, progress: fixtureProgress))
        XCTAssertEqual(producer.label, "crabrix-ios 1.2.0 (140)")
    }

    func testContinuePromptEmbedsTheStateOnlyWhenIncluded() throws {
        let state = try json(currentLesson: nil, progress: fixtureProgress)
        let prompt = AcademyAIPrompts.continuePrompt(stateJSON: state)
        XCTAssertTrue(prompt.hasPrefix(AcademyAIPrompts.continueLearning.text + "\n\n"))
        XCTAssertTrue(prompt.contains("```json\n" + state + "\n```"))
        XCTAssertTrue(prompt.contains("never change it"))
    }
}

final class AcademyAIContentTests: XCTestCase {
    func testPromptsAreTheWebsitesFour() {
        XCTAssertEqual(AcademyAIPrompts.all.map(\.id), ["beginner", "nodejs", "c", "continue"])
        XCTAssertEqual(AcademyAIPrompts.all.map(\.title), ["Beginner", "Node.js developer", "C developer", "Continue learning"])
        XCTAssertEqual(AcademyAIPrompts.all[0].text, "Teach me Rust through Crabrix Academy. Start from the basics, give me practical exercises, and help me understand each concept before moving on.")
        XCTAssertEqual(AcademyAIPrompts.all[3].text, "Help me continue my Crabrix Rust learning using my available progress and previous exercises. Do not assume I have completed lessons unless the learning state confirms it.")
        XCTAssertEqual(AcademyAIPrompts.honestLimits.count, 6)
    }

    func testLessonPromptMirrorsTheWebsiteAndHoldsOnlyPublicDetails() {
        let lab = AcademyAILessonContext(courseID: "ownership", lessonID: "borrowing", title: "Borrowing",
                                         goal: "A `&T` reference lends a value without moving it.", hasLab: true)
        XCTAssertEqual(AcademyAIPrompts.lessonPrompt(lab), """
        I'm learning Rust with Crabrix Academy. Teach me this lesson with the Crabrix Academy tools.
        Lesson: Borrowing (courseId "ownership", lessonId "borrowing")
        Link: https://crabrix.com/learn/ownership/borrowing/
        Goal: A &T reference lends a value without moving it.
        Practice: give me the lesson's exercise (crabrix_academy_get_exercise); I will write and run the code in this lesson's compiler lab in the Crabrix app, where Crabrix checks it.
        Explain it step by step for my level, let me write the code myself, give hints before any solution, and do not mark anything as passed: only Crabrix checks do that.
        """)
        let planned = AcademyAILessonContext(courseID: "basics", lessonID: "what-is-rust", title: "What Rust Is",
                                             goal: "Rust is compiled.", hasLab: false)
        let prompt = AcademyAIPrompts.lessonPrompt(planned)
        XCTAssertTrue(prompt.contains("Link: https://crabrix.com/learn/basics/what-is-rust/"))
        XCTAssertTrue(prompt.contains("crabrix_academy_open_playground"))
        XCTAssertFalse(prompt.contains("compiler lab"))
    }

    func testLessonContextUsesTheRuleThenTheConcept() {
        let lesson = RustLesson(id: "loops", title: "Loops", concept: "Repeat work", minutes: 5, exercise: .runnable)
        XCTAssertEqual(AcademyAILessonContext(courseID: "basics", lesson: lesson, rule: "Use `loop`.").goal, "Use `loop`.")
        let fallback = AcademyAILessonContext(courseID: "basics", lesson: lesson, rule: "  ")
        XCTAssertEqual(fallback.goal, "Repeat work")
        XCTAssertTrue(fallback.hasLab)
        XCTAssertEqual(fallback.reference, AILearningLessonRef(courseId: "basics", lessonId: "loops"))
    }

    func testEveryClientHasCopyableStepsWithTheAcademyURL() {
        XCTAssertEqual(AcademyAIFeature.mcpURL, "https://crabrix.com/mcp/academy")
        XCTAssertEqual(AcademyAIClient.allCases.map(\.name), ["Claude", "Claude Code", "Codex", "Cursor", "Other MCP client"])
        for client in AcademyAIClient.allCases {
            let codes = client.steps.compactMap { block -> (String, String)? in
                if case let .code(code, _, label) = block { return (code, label) }
                return nil
            }
            XCTAssertFalse(codes.isEmpty, client.name)
            XCTAssertTrue(codes.contains { $0.0.contains(AcademyAIFeature.mcpURL) }
                          || codes.contains { $0.0.contains("crabrix@\(AcademyAIFeature.sdkVersion) academy") }, client.name)
            XCTAssertEqual(Set(codes.map(\.1)).count, codes.count, "\(client.name) needs distinct VoiceOver labels")
            XCTAssertTrue(codes.allSatisfy { !$0.1.isEmpty })
        }
        XCTAssertTrue(AcademyAIClient.cursorConfiguration.contains("\"url\": \"https://crabrix.com/mcp/academy\""))
        XCTAssertEqual(AcademyAIClient.claude.openLink?.url.absoluteString, "https://claude.ai/new")
        XCTAssertEqual(AcademyAIClient.codex.openLink?.title, "Open ChatGPT")
        XCTAssertEqual(AcademyAIClient.codex.openLink?.url.absoluteString, "https://chatgpt.com/codex")
        XCTAssertNil(AcademyAIClient.cursor.openLink)
        XCTAssertNotNil(AcademyAIClient.claudeCode.computerNote)
        XCTAssertNotNil(AcademyAIClient.cursor.computerNote)
        XCTAssertNil(AcademyAIClient.claude.computerNote)
    }

    func testFeatureIsOnAndLearningRoutesAreNotPersisted() {
        XCTAssertTrue(AcademyAIFeature.isEnabled)
        // Routes live in @State only. If LearningRoute ever becomes Codable or
        // is restored from saved state, old values need a decoding test.
        XCTAssertFalse((LearningRoute.learnWithAI as Any) is any Decodable)
        XCTAssertFalse((LearningRoute.courses as Any) is any Encodable)
    }
}

final class AcademyAIStatusTests: XCTestCase {
    private func response(_ code: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: AcademyAIFeature.statusURL, statusCode: code, httpVersion: nil, headerFields: nil)!
    }

    func testInterpretsTheStatusContract() {
        let paused = Data(#"{"schemaVersion":1,"learnWithAI":"paused","academyApi":"on","academyMcp":{"url":"https://crabrix.com/mcp/academy","state":"on"},"message":"Back on Monday."}"#.utf8)
        XCTAssertEqual(AcademyAIStatus.interpret(data: paused, response: response(200)), .paused(message: "Back on Monday."))
        let on = Data(#"{"schemaVersion":1,"learnWithAI":"on","message":null}"#.utf8)
        XCTAssertEqual(AcademyAIStatus.interpret(data: on, response: response(200)), .on)
        let pausedNoMessage = Data(#"{"learnWithAI":"paused","message":null}"#.utf8)
        XCTAssertEqual(AcademyAIStatus.interpret(data: pausedNoMessage, response: response(200)), .paused(message: nil))
        XCTAssertEqual(AcademyAIStatus.interpret(data: Data(#"{"learnWithAI":"later"}"#.utf8), response: response(200)), .on)
    }

    func testMissingEndpointIsOnAndEverythingElseIsUnreachable() {
        XCTAssertEqual(AcademyAIStatus.interpret(data: Data("<html>Not found</html>".utf8), response: response(404)), .on)
        XCTAssertEqual(AcademyAIStatus.interpret(data: Data("<html></html>".utf8), response: response(200)), .unreachable)
        XCTAssertEqual(AcademyAIStatus.interpret(data: Data(), response: response(503)), .unreachable)
        XCTAssertEqual(AcademyAIStatus.interpret(data: nil, response: nil), .unreachable)
        XCTAssertEqual(AcademyAIStatus.interpret(data: Data(repeating: 32, count: 70_000), response: response(200)), .unreachable)
    }

    func testSessionIsEphemeralWithoutCookiesAndShort() {
        let configuration = AcademyAIStatusClient.makeSession().configuration
        XCTAssertEqual(configuration.httpCookieAcceptPolicy, .never)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertNil(configuration.urlCache)
        XCTAssertEqual(configuration.timeoutIntervalForRequest, 5)
        XCTAssertEqual(configuration.timeoutIntervalForResource, 5)
        XCTAssertEqual(AcademyAIFeature.statusURL.absoluteString, "https://crabrix.com/api/academy/v1/status.json")
    }

    func testFetchSendsNoCookiesAndHandlesAnswersAndFailures() async {
        func client(_ stub: AcademyAIStubProtocol.Reply) -> AcademyAIStatusClient {
            AcademyAIStubProtocol.reply = stub
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [AcademyAIStubProtocol.self]
            return AcademyAIStatusClient(session: URLSession(configuration: configuration))
        }
        let notFound = await client(.status(404, Data())).fetch()
        XCTAssertEqual(notFound, .on)
        XCTAssertNil(AcademyAIStubProtocol.lastRequest?.value(forHTTPHeaderField: "Cookie"))
        XCTAssertEqual(AcademyAIStubProtocol.lastRequest?.url, AcademyAIFeature.statusURL)
        XCTAssertEqual(AcademyAIStubProtocol.lastRequest?.httpMethod, "GET")
        let paused = await client(.status(200, Data(#"{"learnWithAI":"paused"}"#.utf8))).fetch()
        XCTAssertEqual(paused, .paused(message: nil))
        let offline = await client(.failure).fetch()
        XCTAssertEqual(offline, .unreachable)
    }
}

final class AcademyAIStubProtocol: URLProtocol, @unchecked Sendable {
    enum Reply { case status(Int, Data), failure }
    nonisolated(unsafe) static var reply: Reply = .failure
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        Self.lastRequest = request
        switch Self.reply {
        case let .status(code, body):
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case .failure:
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        }
    }
}

final class AILearningFlagsTests: XCTestCase {
    func testFeedbackIsOfferedOnceAfterACopyAndNeverAgain() throws {
        let suite = "CrabrixAIFlags.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let flags = AILearningFlags(defaults: defaults)
        XCTAssertFalse(flags.shouldOfferFeedback)
        let first = Date(timeIntervalSince1970: 1_790_000_000)
        flags.recordCopy(now: first)
        flags.recordCopy(now: first.addingTimeInterval(600))
        XCTAssertEqual(flags.firstCopyAt, first)
        XCTAssertTrue(flags.shouldOfferFeedback)
        flags.finishFeedback(.dismissed)
        flags.finishFeedback(.answered)
        XCTAssertEqual(flags.feedbackOutcome, .dismissed)
        XCTAssertFalse(flags.shouldOfferFeedback)
        let keys = Set(defaults.persistentDomain(forName: suite)?.keys.map { $0 } ?? [])
        XCTAssertEqual(keys, [AILearningFlags.firstCopyKey, AILearningFlags.feedbackKey])
        XCTAssertTrue(keys.allSatisfy { $0.hasPrefix(AILearningFlags.keyPrefix) })
    }

    func testFeedbackOpensAMailDraftWithTheAnswer() throws {
        let producer = AILearningState.Producer(version: "1.2.0", build: "140")
        let url = try XCTUnwrap(AILearningFeedback.mailURL(.notWorking, note: "Cursor said 1 + 1 tools", producer: producer, to: "learner@example.com"))
        XCTAssertEqual(url.scheme, "mailto")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "learner@example.com")
        XCTAssertEqual(components.queryItems?.first { $0.name == "subject" }?.value, "Crabrix — Learning with AI: I couldn’t get it working")
        let body = try XCTUnwrap(components.queryItems?.first { $0.name == "body" }?.value)
        XCTAssertTrue(body.contains("I couldn’t get it working"))
        XCTAssertTrue(body.contains("1 + 1"), "a typed + must survive Mail")
        XCTAssertTrue(body.contains("Crabrix 1.2.0 (build 140)"))
        XCTAssertFalse(AILearningFeedback.body(.yes, note: "  ", producer: producer).contains("\n\n\n"))
        XCTAssertEqual(AILearningFeedback.Answer.allCases.map(\.rawValue), ["Yes", "Partly", "I couldn’t get it working"])
    }
}

/// Spec §15: data preservation. Seed every learning store with the app's real
/// types and keys, exercise everything Learn with AI does, and require every
/// pre-existing value and file to be byte-identical afterwards, with only
/// `crabrix.ai.*` keys added.
@MainActor
final class LearnWithAIDataPreservationTests: XCTestCase {
    func testLearnWithAIChangesNoExistingLearningDataAndAddsOnlyAIFlags() async throws {
        let suite = "CrabrixAIPreservation.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appending(path: suite, directoryHint: .isDirectory)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        try await seed(defaults: defaults, root: root)

        let keysBefore = try domainSnapshot(defaults, suite: suite)
        let filesBefore = try fileSnapshot(root)
        XCTAssertGreaterThanOrEqual(keysBefore.count, 12)
        XCTAssertGreaterThanOrEqual(filesBefore.count, 3, "flashcards database and a saved project")

        // Everything the feature does, through the same code the views call.
        let completed = Set(defaults.stringArray(forKey: LearningProgressKeys.completed) ?? [])
        let credited = LessonCredits.decode(defaults.object(forKey: LearningProgressKeys.credited))
        XCTAssertEqual(completed, ["borrowing", "c-malloc-free-to-ownership", "variables"])
        XCTAssertEqual(credited, ["ownership-basics": "c-malloc-free-to-ownership", "variables": "node-variables"])
        let progress = AILearningState.Progress(completed: completed, credited: credited,
                                                courseIDs: ["borrowing": "ownership", "variables": "basics"])
        let lesson = AcademyAILessonContext(courseID: "ownership", lessonID: "borrowing", title: "Borrowing",
                                            goal: "Borrow, do not move.", hasLab: true)
        for client in AcademyAIClient.allCases { _ = client.steps; _ = client.openLink; _ = client.computerNote }
        let prompts = AcademyAIPrompts.all.map(\.text) + [AcademyAIPrompts.lessonPrompt(lesson)]
        XCTAssertEqual(prompts.count, 5)
        let flags = AILearningFlags(defaults: defaults)
        flags.recordCopy()
        let producer = AILearningState.Producer.current
        let without = AILearningStateFile(currentLesson: lesson.reference, progress: nil, producer: producer)
        let with = AILearningStateFile(currentLesson: lesson.reference, progress: progress, producer: producer)
        let withoutText = try XCTUnwrap(String(data: try without.data(), encoding: .utf8))
        let withText = try XCTUnwrap(String(data: try with.data(), encoding: .utf8))
        XCTAssertTrue(withoutText.contains("\"officialProgress\" : null"))
        let exported = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(withText.utf8)) as? [String: Any])
        let official = try XCTUnwrap(exported["officialProgress"] as? [String: Any])
        XCTAssertEqual((official["completed"] as? [[String: Any]])?.compactMap { $0["lessonId"] as? String },
                       ["borrowing", "c-malloc-free-to-ownership", "variables"])
        // "variables" is completed, so it is not exported as a credit too.
        XCTAssertEqual((official["credited"] as? [[String: Any]])?.compactMap { $0["lessonId"] as? String },
                       ["ownership-basics"])
        for leaked in ["answer", "mastery", "points", "E0502", "abc123", "Borrowing lab", "fn main"] {
            XCTAssertFalse(withText.contains(leaked), leaked)
        }
        _ = AcademyAIPrompts.continuePrompt(stateJSON: withText)
        _ = AcademyAIPrompts.continuePrompt(stateJSON: nil)
        XCTAssertTrue(flags.shouldOfferFeedback)
        _ = AILearningFeedback.mailURL(.partly, note: "Helpful", producer: producer)
        flags.finishFeedback(.answered)
        _ = AcademyAIStatus.interpret(data: nil, response: nil)

        let keysAfter = try domainSnapshot(defaults, suite: suite)
        for (key, bytes) in keysBefore {
            XCTAssertEqual(keysAfter[key], bytes, "\(key) changed or disappeared")
        }
        let added = Set(keysAfter.keys).subtracting(keysBefore.keys)
        XCTAssertEqual(added, [AILearningFlags.firstCopyKey, AILearningFlags.feedbackKey])
        XCTAssertTrue(added.allSatisfy { $0.hasPrefix("crabrix.ai.") })
        XCTAssertEqual(try fileSnapshot(root), filesBefore, "no learning or project file may change")

        // The real stores still read exactly what was seeded.
        XCTAssertEqual(CrabrixProgressStore(defaults: defaults).state.totalPoints, seededPoints)
        XCTAssertNotNil(TopicMasteryStore(defaults: defaults).record(for: "borrowing"))
        let snapshot = try LearningProgressPreferences.captureBase(defaults: defaults, deviceFamily: "iPhone")
        XCTAssertEqual(snapshot.answers, ["borrowing": 1, "variables": 2])
        XCTAssertEqual(snapshot.creditedLessonIDs, credited)
    }

    private var seededPoints = 0

    private func seed(defaults: UserDefaults, root: URL) async throws {
        defaults.set(["borrowing", "c-malloc-free-to-ownership", "variables"], forKey: LearningProgressKeys.completed)
        defaults.set(["ownership-basics": "c-malloc-free-to-ownership", "variables": "node-variables"],
                     forKey: LearningProgressKeys.credited)
        defaults.set(["borrowing": 1, "variables": 2], forKey: LearningProgressKeys.answers)
        defaults.set(["loops": 1_790_000_000.0], forKey: LearningProgressKeys.resetDates)
        defaults.set(4, forKey: LearningProgressKeys.terms)
        defaults.set(2, forKey: LearningProgressKeys.recall)
        defaults.set(3, forKey: LearningProgressKeys.cards)
        defaults.set("dark", forKey: "crabrix.appearance")
        defaults.set("existingLearner", forKey: "crabrix.academy.initialInstall.v1")
        let evidence = [LessonAttemptEvidence(
            lessonID: "borrowing", projectRevision: "rev-1", validatorVersion: LessonAttemptEvidence.validatorVersion,
            compilerVersion: "rustc 1.91.0", result: .passed, diagnosticCodes: ["E0502"], stdoutHash: "abc123",
            completedAt: Date(timeIntervalSince1970: 1_790_000_100),
            identity: LessonAttemptIdentity(courseID: "ownership", language: "en", contentVersion: "1.0.1",
                                            lessonID: "borrowing", exerciseID: "borrowing", validatorVersion: "lesson-evidence-1",
                                            toolchainID: "crabrix-rust", projectID: UUID(), projectRevision: "rev-1")
        )]
        defaults.set(try JSONEncoder().encode(evidence), forKey: "crabrix.learn.attemptEvidence.v1")

        let progress = CrabrixProgressStore(defaults: defaults)
        XCTAssertTrue(progress.record(.lessonCompleted, eventKey: "lesson:borrowing:first-completion"))
        XCTAssertTrue(progress.record(.lessonCompleted, eventKey: "lesson:variables:first-completion"))
        seededPoints = progress.state.totalPoints
        XCTAssertGreaterThan(seededPoints, 0)
        XCTAssertNotNil(defaults.data(forKey: LearningProgressKeys.progress))

        let mastery = TopicMasteryStore(defaults: defaults)
        mastery.record(topic: "borrowing", correct: true, now: Date(timeIntervalSince1970: 1_790_000_200))
        mastery.record(topic: "variables", correct: false, now: Date(timeIntervalSince1970: 1_790_000_300))
        XCTAssertNotNil(defaults.data(forKey: LearningProgressKeys.mastery))

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        do {
            let database = try FlashcardReviewDatabase(url: root.appending(path: "Learning/flashcards.sqlite"))
            let card = Flashcard(id: "ownership/borrowing/concept", courseID: "ownership", courseTitle: "Ownership",
                                 lessonID: "borrowing", lessonTitle: "Borrowing", kind: .concept,
                                 prompt: "What is borrowed?", answer: "A reference", code: nil)
            _ = try database.review(card: card, grade: .hard, eventID: UUID().uuidString,
                                    now: Date(timeIntervalSince1970: 1_790_000_400))
        }
        let store = ProjectStore(rootURL: root.appending(path: "Crabrix", directoryHint: .isDirectory))
        let project = CrabrixProject(
            name: "Borrowing lab", files: ["Cargo.toml": "[package]\nname = \"lab\"\nversion = \"0.1.0\"\nedition = \"2021\"\n",
                                           "src/main.rs": "fn main() { println!(\"hi\"); }\n"],
            entryFile: "src/main.rs", provenance: .files()
        )
        _ = try await store.save(project: project, lastBuild: nil, at: Date(timeIntervalSince1970: 1_790_000_500))
    }

    /// Every value as XML property-list bytes (dictionary keys sorted), and
    /// `Data` values as their own bytes.
    private func domainSnapshot(_ defaults: UserDefaults, suite: String) throws -> [String: Data] {
        let domain = try XCTUnwrap(defaults.persistentDomain(forName: suite))
        return try domain.mapValues { value in
            if let data = value as? Data { return data }
            return try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
        }
    }

    private func fileSnapshot(_ root: URL) throws -> [String: Data] {
        var files: [String: Data] = [:]
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey], options: []
        ))
        for case let url as URL in enumerator
        where (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true {
            files[String(url.path.dropFirst(root.path.count))] = try Data(contentsOf: url)
        }
        return files
    }
}
