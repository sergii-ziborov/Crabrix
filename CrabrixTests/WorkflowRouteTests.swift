import Foundation
import XCTest
@testable import Crabrix

final class WorkflowRouteTests: XCTestCase {
    struct Fixtures: Decodable {
        let standardSource: String
        let standardExpected: String
        let sql: [Lab]
        let companion: [String: String]
        struct Lab: Decodable { let id: String; let harness: String; let reference: String; let mutant: String; let expectedOutput: String }
    }
    private func fixtures() throws -> Fixtures {
        let root = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "CompilerCandidate", withExtension: nil))
        return try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: root.appending(path: "WorkflowRoute.json")))
    }
    func testBundledReleaseCatalogDownloadsAndInstallsProductionSignedRoute() async throws {
        guard ProcessInfo.processInfo.environment["CRABRIX_RUN_WORKFLOW_FETCH"] == "1" else {
            throw XCTSkip("Run CrabrixWorkflowGate for the explicit public production-package gate.")
        }
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let currentVersion = try XCTUnwrap(SemanticVersion("1.1.8"))
        let previousVersion = try XCTUnwrap(SemanticVersion("1.1.7"))
        let bootstrap = try CourseBootstrap(root: root, appVersion: currentVersion)
        let catalog = try bootstrap.bundledCatalog()
        XCTAssertEqual(catalog.sequence, 24)
        let entry = try XCTUnwrap(CourseUpdatePlanner.latestCompatible(in: catalog,
            appVersion: currentVersion)["projects|en"])
        XCTAssertEqual(entry.contentVersion, "1.1.0")
        XCTAssertEqual(entry.minimumAppVersion, "1.1.8")
        XCTAssertTrue(entry.requiredCapabilities.contains("workflow-terminal-v1"))
        XCTAssertNil(CourseUpdatePlanner.latestCompatible(in: catalog,
            appVersion: previousVersion)["projects|en"])
        let manager = try CourseDownloadManager(cacheRoot: root.appending(path: "downloads"))
        let downloaded = try await manager.download(entry)
        let installer = try CourseInstaller(root: root.appending(path: "installed"),
                                            appVersion: SemanticVersion("1.1.8"))
        _ = try await installer.install(descriptorBytes: downloaded.descriptor,
            downloadedArchive: downloaded.archive, keyring: bootstrap.keyring())
        let repository = try await installer.loadRepository(keyring: bootstrap.keyring())
        XCTAssertTrue(repository.unavailable.isEmpty)
        let lessons = try XCTUnwrap(repository.loaded["projects"]).course.units.flatMap(\.lessons)
            .filter { $0.id.hasPrefix("route-") }
        XCTAssertEqual(lessons.count, 24)
        for lesson in lessons {
            XCTAssertNotNil(repository.challenge(for: lesson.id), lesson.id)
            XCTAssertNotNil(repository.workflowCompanion(for: lesson.id), lesson.id)
        }
        let client = CourseCatalogClient(stateURL: root.appending(path: "catalog-state.json"),
            keyring: try bootstrap.keyring(), bundled: catalog)
        let retained = try await client.refresh()
        XCTAssertGreaterThanOrEqual(retained.sequence, catalog.sequence)
        XCTAssertEqual(CourseUpdatePlanner.latestCompatible(in: retained,
            appVersion: currentVersion)["projects|en"]?.contentVersion, "1.1.0")
    }
    func testSignedPackInstallsAllRouteLessonsAndKeepsAnOpenedOldSnapshot() async throws {
        let fixtures = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "CompilerCandidate", withExtension: nil))
        let pack = fixtures.appending(path: "WorkflowPack")
        guard FileManager.default.fileExists(atPath: pack.appending(path: "projects-1.1.0.zip").path) else {
            throw XCTSkip("Generate WorkflowPack with the documented public test key before the package gate.")
        }
        let legacy = try XCTUnwrap(Bundle.main.url(forResource: "MigrationCoursePacks", withExtension: nil))
        let production = try JSONDecoder().decode(CourseKeyring.self, from: Data(contentsOf: legacy.appending(path: "production-keyring.json")))
        let test = try JSONDecoder().decode(CourseKeyring.self, from: Data(contentsOf: pack.appending(path: "test-keyring.json")))
        let keys = CourseKeyring(keys: production.keys.merging(test.keys) { _, rhs in rhs })
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = try CourseInstaller(root: root, appVersion: SemanticVersion("1.1.8"))
        _ = try await installer.install(descriptorBytes: Data(contentsOf: legacy.appending(path: "projects.descriptor.json")), downloadedArchive: legacy.appending(path: "projects-1.0.1.zip"), keyring: keys)
        let before = try InstalledCourseRepository(root: root, records: await installer.installed(), keyring: keys)
        _ = try await installer.install(descriptorBytes: Data(contentsOf: pack.appending(path: "projects.descriptor.json")), downloadedArchive: pack.appending(path: "projects-1.1.0.zip"), keyring: keys)
        let after = try InstalledCourseRepository(root: root, records: await installer.installed(), keyring: keys)
        XCTAssertTrue(after.unavailable.isEmpty, after.unavailable.map(\.reason).joined())
        XCTAssertNil(before.lesson(id: "route-git-review"))
        for id in after.courses.flatMap(\.units).flatMap(\.lessons).map(\.id).filter({ $0.hasPrefix("route-") }) {
            XCTAssertNotNil(after.challenge(for: id), id)
            let companion = try XCTUnwrap(after.workflowCompanion(for: id), id)
            XCTAssertEqual(companion.entryFile, "src/main.rs")
            XCTAssertNotNil(companion.files["requests/health.http"], id)
            XCTAssertEqual(after.challenge(for: id)?.usesSQL, id.hasPrefix("route-sql-"))
        }
        XCTAssertEqual(after.courses.flatMap(\.units).flatMap(\.lessons).filter { $0.id.hasPrefix("route-") }.count, 24)
        let descriptor = try CoursePackVerifier.verify(descriptorBytes: Data(contentsOf: pack.appending(path: "projects.descriptor.json")), archiveURL: pack.appending(path: "projects-1.1.0.zip"), keyring: keys).descriptor
        XCTAssertThrowsError(try CourseCompatibility.requireSupported(descriptor, appVersion: SemanticVersion("1.1.7")!))
    }
    func testTwentyStandardLibraryRouteLabsWithRealBundledCompiler() async throws {
        let fixture = try fixtures()
        let result = await WasmRustCompiler().run(source: fixture.standardSource)
        XCTAssertTrue(result.succeeded, result.detail + result.stderr)
        XCTAssertEqual(result.stdout, fixture.standardExpected)
    }
    func testFourSQLLabsExecuteReferenceAndRejectWrongSolutions() async throws {
        let compiler = WasmRustCompiler()
        var modules: [String] = [], invocations: [(String, Bool, LessonHarnessNonce.Run)] = []
        for lab in try fixtures().sql {
            for (solution, expected) in [(lab.reference, true), (lab.mutant, false)] {
                let nonce = try XCTUnwrap(LessonHarnessNonce.instrument(verificationSource: lab.harness,
                    expectedOutput: lab.expectedOutput, nonce: "sql-" + lab.id))
                let index = modules.count
                let harness = nonce.source.replacingOccurrences(of: "mod solution;", with: "mod solution {\n" + solution + "\n}")
                    .replacingOccurrences(of: "fn main()", with: "pub fn verify()")
                modules.append("mod lab_\(index) {\n" + harness + "\n}")
                invocations.append((lab.id, expected, nonce.run))
            }
        }
        let arms = modules.indices.map { "\($0) => lab_\($0)::verify()," }.joined()
        let source = modules.joined(separator: "\n") + "\nfn main(){ match std::env::args().nth(1).unwrap().parse::<usize>().unwrap(){" + arms + "_ => panic!(\"case\")}}"
        for (index, invocation) in invocations.enumerated() {
            let result = await compiler.run(source: source, input: .init(arguments: [String(index)], database: try ProjectSQLDatabase()))
            XCTAssertEqual(result.phase, .run, invocation.0 + result.stderr + result.detail)
            XCTAssertEqual(result.succeeded, invocation.1, invocation.0 + result.stderr + result.detail)
            XCTAssertEqual(LessonHarnessNonce.reveal(stdout: result.stdout, run: invocation.2).completed, invocation.1, invocation.0)
        }
    }
    func testArgumentsEnvironmentAndStdinStayFreshAcrossCachedExecutables() async throws {
        let compiler = WasmRustCompiler()
        let source = #"""
        use std::io::Read;
        fn main(){ let mut input=String::new();std::io::stdin().read_to_string(&mut input).unwrap();
        println!("{:?}|{}|{}",std::env::args().skip(1).collect::<Vec<_>>(),std::env::var("TASK_LIMIT").unwrap_or_default(),input); }
        """#
        let first = await compiler.run(source: source, input: .init(arguments: ["two words", ""], environment: ["TASK_LIMIT":"7"], standardInput: Data("🦀".utf8)))
        XCTAssertTrue(first.succeeded, first.stderr)
        XCTAssertEqual(first.stdout, "[\"two words\", \"\"]|7|🦀\n")
        let second = await compiler.run(source: source)
        XCTAssertTrue(second.succeeded, second.stderr)
        XCTAssertEqual(second.stdout, "[]||\n")
        let invalid = await compiler.run(source: source, input: .init(arguments: ["bad\0arg"]))
        XCTAssertFalse(invalid.succeeded)
        XCTAssertEqual(invalid.phase, .setup)
    }
    func testSQLiteParametersTransactionsLimitsAndPersistence() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            let db = try ProjectSQLDatabase(path: root.path)
            _ = try db.execute("CREATE TABLE tasks(id INTEGER PRIMARY KEY,title TEXT NOT NULL); INSERT INTO tasks VALUES(1,'keep');")
            _ = try db.execute("INSERT INTO tasks(title) VALUES(?1)", parameters: ["x'; DROP TABLE tasks; --"])
            XCTAssertEqual(try db.execute("SELECT count(*) FROM tasks").rows, [["2"]])
            XCTAssertThrowsError(try db.execute("BEGIN; INSERT INTO tasks VALUES(3,'rollback'); INSERT INTO tasks VALUES(1,'duplicate'); COMMIT;"))
            XCTAssertEqual(try db.execute("SELECT count(*) FROM tasks").rows, [["2"]])
            XCTAssertThrowsError(try db.execute("BEGIN; INSERT INTO tasks VALUES(3,'unfinished')"))
            XCTAssertThrowsError(try db.execute("ATTACH DATABASE ':memory:' AS other"))
            XCTAssertThrowsError(try db.execute("PRAGMA writable_schema=ON"))
            XCTAssertThrowsError(try db.execute("DELETE FROM tasks", readOnly: true))
            XCTAssertThrowsError(try db.execute("SELECT zeroblob(300000)"))
            XCTAssertThrowsError(try db.execute("WITH RECURSIVE x(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM x) SELECT sum(n) FROM x"))
            XCTAssertEqual(try db.execute("SELECT ?1", parameters: [NSNumber(value: Int64.max)]).rows, [[String(Int64.max)]])
            XCTAssertEqual(try db.execute("SELECT ?1", parameters: ["before\0after🦀"]).rows, [["before\0after🦀"]])
        }
        let reopened = try ProjectSQLDatabase(path: root.path)
        XCTAssertEqual(try reopened.execute("SELECT title FROM tasks WHERE id=1").rows, [["keep"]])
        XCTAssertEqual(try reopened.execute("SELECT count(*) FROM tasks").rows, [["2"]])
    }
    func testHTTPFramingRejectsAmbiguityAndCountsUTF8Bytes() throws {
        XCTAssertFalse(try ProjectHTTPWire.completeRequest(Data("POST /tasks HTTP/1.1\r\nContent-Length: 4\r\n\r\n".utf8)))
        XCTAssertTrue(try ProjectHTTPWire.completeRequest(Data("POST /tasks HTTP/1.1\r\nContent-Length: 4\r\n\r\n🦀".utf8)))
        for bad in ["GET / HTTP/1.1\r\nContent-Length: 0\r\nContent-Length: 0\r\n\r\n",
                    "GET / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n",
                    "GET / HTTP/1.1\r\n\r\nGET / HTTP/1.1\r\n\r\n"] {
            XCTAssertThrowsError(try ProjectHTTPWire.completeRequest(Data(bad.utf8)))
        }
        let response = try ProjectHTTPWire.response("HTTP/1.1 200 OK\r\nContent-Length: 1\r\n\r\n🦀")
        XCTAssertTrue(String(decoding: response, as: UTF8.self).contains("Content-Length: 4\r\n"))
    }
    @MainActor
    func testTerminalCLIParsingPreservesQuotedEmptyArgumentsAndWorkingDirectory() throws {
        let terminal = ProjectTerminalSession()
        let project = CrabrixProject(name: "cli", files: ["main.rs":"fn main(){}", "input.txt":"hello"], entryFile: "main.rs", provenance: nil)
        defer { try? ProjectSQLDatabase.remove(projectID: project.id) }
        var received: [RustProgramInput] = []
        terminal.command = "env TASK_LIMIT=7 cargo run -- add 'two words' '' '<' < input.txt"
        terminal.submit(project: project, isBusy: false, onCheck: {}, onRun: { XCTFail("Plain run") }, onRunWithInput: { received.append($0) })
        XCTAssertEqual(received, [.init(arguments: ["add","two words","","<"], environment: ["TASK_LIMIT":"7"], standardInput: Data("hello".utf8))])
        terminal.command = "env API_TOKEN=private-test-value cargo run -- list"
        terminal.submit(project: project, isBusy: false, onCheck: {}, onRun: {}, onRunWithInput: { _ in })
        XCTAssertFalse(terminal.lines.map(\.text).joined().contains("private-test-value"))
        terminal.command = "cargo run --database tasks.db -- list"
        terminal.submit(project: project, isBusy: false, onCheck: {}, onRun: {}, onRunWithInput: { XCTAssertNotNil($0.database) })
        for bad in ["cargo run -- a | cat", "cargo run -- a < ../outside", "cargo run -- a < missing", "cargo run -- a && echo ok"] {
            terminal.command = bad
            terminal.submit(project: project, isBusy: false, onCheck: {}, onRun: {}, onRunWithInput: { _ in XCTFail(bad) })
            XCTAssertEqual(terminal.lines.last?.kind, .error, bad)
        }
    }
    func testHTTPRequestFilePreservesBodyAndRejectsMultipleRequests() throws {
        let text = "# one request\nPOST http://127.0.0.1:8080/tasks HTTP/1.1\nContent-Type: application/json\n\n{\"title\":\"🦀\"}"
        XCTAssertEqual(try ProjectHTTPRequestFile.curlArguments(text), ["-i", "-X", "POST", "-H", "Content-Type: application/json", "--data-binary", "{\"title\":\"🦀\"}", "http://127.0.0.1:8080/tasks"])
        XCTAssertThrowsError(try ProjectHTTPRequestFile.curlArguments(text + "\n###\nGET http://127.0.0.1:8080/tasks"))
        XCTAssertThrowsError(try ProjectHTTPRequestFile.curlArguments("POST"))
    }
    func testWorkflowSyntaxUsesTheCorrectLanguageAndOpaqueStrings() {
        XCTAssertEqual(SourceLanguage(filePath:"Dockerfile.release"), .dockerfile)
        XCTAssertEqual(SourceLanguage(filePath:".env.production"), .dotenv)
        XCTAssertEqual(SourceLanguage(filePath:"migrations/001.sql"), .sql)
        let sql = "select 'DROP TABLE tasks' as title; -- delete\n"
        let tokens = SyntaxHighlighter.tokens(in: sql, filePath: "query.sql")
        XCTAssertEqual(tokens.filter { $0.kind == .keyword }.map { (sql as NSString).substring(with:$0.range).lowercased() }, ["select","as"])
        for (path, source) in [("run.sh", "curl -H 'X-Request-ID: req_1' http://localhost:8080"), ("Dockerfile", "FROM rust:1\nRUN cargo build"), ("request.http", "GET http://localhost:8080/tasks HTTP/1.1\r\nAccept: application/json"), ("change.diff", "@@ old new @@\n+new\n-old")] {
            XCTAssertFalse(SyntaxHighlighter.tokens(in: source, filePath: path).isEmpty, path)
        }
    }
    @MainActor
    func testRealLoopbackHTTPRustAndSQLiteCreateReplayConflictAndRead() async throws {
        let files = try fixtures().companion
        let source = try XCTUnwrap(files["src/main.rs"])
        let db = try ProjectSQLDatabase()
        _ = try db.execute(try XCTUnwrap(files["migrations/001.sql"]))
        let compiler = WasmRustCompiler()
        let built = await compiler.build(source: source)
        XCTAssertTrue(built.succeeded, built.stderr)
        guard built.succeeded else { return }
        let server = ProjectHTTPServer(); defer { server.stop(); compiler.cancel() }
        let ready = expectation(description: "loopback listener ready")
        try server.start(port: 0, handler: { request in
            let result = await compiler.run(source: source, input: .init(standardInput: request, database: db))
            return result.stdout
        }, event: { message, error in
            if message.hasPrefix("HTTP listening") { ready.fulfill() }
            XCTAssertFalse(error, message)
        })
        await fulfillment(of: [ready], timeout: 10)
        let port = try XCTUnwrap(server.port)
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/tasks"))
        func send(_ title: String, key: String) async throws -> (Data, HTTPURLResponse) {
            var request = URLRequest(url: url); request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(key, forHTTPHeaderField: "Idempotency-Key")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["title": title])
            return try await ProjectHTTPClient().send(request)
        }
        let first = try await send("learn 🦀", key: "key-1")
        XCTAssertEqual(first.1.statusCode, 201, String(decoding: first.0, as: UTF8.self))
        let replay = try await send("learn 🦀", key: "key-1")
        XCTAssertEqual(replay.1.statusCode, 200)
        XCTAssertEqual(first.0, replay.0)
        let conflict = try await send("different", key: "key-1")
        XCTAssertEqual(conflict.1.statusCode, 409)
        let (data, response) = try await ProjectHTTPClient().send(URLRequest(url: url))
        XCTAssertEqual(response.statusCode, 200)
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(rows.count, 1); XCTAssertEqual(rows.first?["title"] as? String, "learn 🦀")
        let cli = await compiler.run(source: source, input: .init(arguments: ["list"], database: db))
        XCTAssertTrue(cli.succeeded, cli.stderr)
        let cliRows = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(cli.stdout.utf8)) as? [[String: Any]])
        XCTAssertEqual(cliRows.count, 1)
        let addCLI = await compiler.run(source: source, input: .init(arguments: ["add", "from CLI"], database: db))
        XCTAssertTrue(addCLI.succeeded, addCLI.stderr)
        XCTAssertEqual(try db.execute("SELECT count(*) FROM tasks").rows, [["2"]])
        server.stop(); XCTAssertFalse(server.isRunning)
    }
}
