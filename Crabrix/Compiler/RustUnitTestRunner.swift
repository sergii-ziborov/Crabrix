import Foundation

struct RustUnitTestRequest: Equatable, Sendable {
    enum Target: Equatable, Sendable { case selectedEntry, library, binary(String) }
    var target: Target = .selectedEntry
    var filter: String? = nil
    var listOnly = false

    func entry(in project: CrabrixProject) throws -> String {
        let path: String
        switch target {
        case .selectedEntry: path = project.entryFile
        case .library:
            let manifest = try project.files["Cargo.toml"].map(CratePackageManifest.parse)
            path = manifest?.library.path ?? (project.files["src/lib.rs"] != nil ? "src/lib.rs" : "lib.rs")
        case let .binary(name):
            guard let text = project.files["Cargo.toml"] else { throw Failure("--bin needs a Cargo package manifest") }
            let manifest = try CratePackageManifest.parse(text)
            let document = try TOMLParser.parse(text)
            let bins = document["bin"]?.arrayValue?.compactMap(\.tableValue) ?? []
            if let target = bins.first(where: { $0["name"]?.stringValue == name }) {
                guard target["harness"]?.boolValue != false else { throw Failure("Custom binary test harnesses are unsupported") }
                path = target["path"]?.stringValue ?? "src/bin/\(name).rs"
            } else if name == manifest.packageName, project.files["src/main.rs"] != nil { path = "src/main.rs" }
            else if project.files["src/bin/\(name).rs"] != nil { path = "src/bin/\(name).rs" }
            else { throw Failure("No supported binary target named \(name)") }
        }
        try ProjectFilePolicy.validatePath(path)
        guard path.hasSuffix(".rs"), project.files[path] != nil else { throw Failure("The selected unit-test entry is not an available Rust file: \(path)") }
        if let text = project.files["Cargo.toml"] {
            let manifest = try CratePackageManifest.parse(text)
            guard !manifest.isVirtualWorkspace, !manifest.isProcMacro else { throw Failure("Select a non-procedural-macro package entry") }
            guard !manifest.dependencies.contains(where: { $0.kind == .dev }) else { throw Failure("Dev-dependencies are not resolved by the initial unit-test profile") }
            let document = try TOMLParser.parse(text)
            let isLibrary = path == manifest.library.path || path == "src/lib.rs" || path == "lib.rs"
            if isLibrary, document["lib"]?["harness"]?.boolValue == false { throw Failure("Custom library test harnesses are unsupported") }
            let bins = document["bin"]?.arrayValue?.compactMap(\.tableValue) ?? []
            if bins.contains(where: { bin in
                let name = bin["name"]?.stringValue ?? manifest.packageName
                let entry = bin["path"]?.stringValue ?? (name == manifest.packageName ? "src/main.rs" : "src/bin/\(name).rs")
                return entry == path && bin["harness"]?.boolValue == false
            }) { throw Failure("Custom binary test harnesses are unsupported") }
        }
        return path
    }

    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { "Selected-entry Unit Test: \(message). No integration targets, doctests or missing dev-dependencies were silently treated as tested." }
    }
}

struct RustUnitTestCase: Identifiable, Equatable, Sendable {
    enum State: String, Sendable { case discovered, passed, failed, skipped, unsupported, canceled, notRun }
    let name: String
    let file: String?
    let line: Int?
    let ignored: Bool
    var state: State = .discovered
    var detail = ""
    var stdout = ""
    var stderr = ""
    var rawHarnessOutput = ""
    var id: String { name }
}

struct RustUnitTestReport: Sendable {
    var cases: [RustUnitTestCase]
    var compilerFailure: CompilationResult?
    var discoveryOnly: Bool
    var canceled = false
    var detail: String
    var duration: Duration

    var rendered: CompilationResult {
        if let compilerFailure { return compilerFailure }
        let passed = cases.filter { $0.state == .passed }.count
        let failed = cases.filter { $0.state == .failed }.count
        let skipped = cases.filter { $0.state == .skipped }.count
        let unsupported = cases.filter { $0.state == .unsupported }.count
        let notRun = cases.filter { $0.state == .notRun }.count
        let success = !canceled && failed == 0 && unsupported == 0 && notRun == 0
        let summary = discoveryOnly
            ? "Selected-entry unit tests: \(cases.count) discovered.\n"
            : "Selected-entry unit tests: \(passed) passed · \(failed) failed · \(skipped) skipped · \(unsupported) unsupported · \(notRun) not run.\n"
        let body = cases.map { test in
            let location = test.file.map { " · \($0):\(test.line ?? 1) (test declaration)" } ?? ""
            let message = test.detail.isEmpty ? "" : "\n  " + test.detail
            let stdout = test.stdout.isEmpty ? "" : "\n  stdout:\n" + test.stdout
            let stderr = test.stderr.isEmpty ? "" : "\n  stderr:\n" + test.stderr
            return "[\(test.state.rawValue)] \(test.name)\(location)\(message)\(stdout)\(stderr)"
        }.joined(separator: "\n\n")
        let diagnostics = cases.filter { $0.state == .failed || $0.state == .unsupported }.map { test in
            let spans: [RustDiagnostic.Span] = test.file.map { file in
                [.init(fileName: file, lineStart: test.line ?? 1, lineEnd: test.line ?? 1,
                    columnStart: 1, columnEnd: 1, isPrimary: true, label: "test declaration", sourceLine: "")]
            } ?? []
            return RustDiagnostic(level: "error", message: "\(test.name): \(test.detail)", code: nil,
                                  rendered: test.stderr, spans: spans)
        }
        let output = summary + detail + "\n\n" + body
        let preview = String(decoding: output.utf8.prefix(256 * 1024), as: UTF8.self)
            + (output.utf8.count > 256 * 1024 ? "\n[Terminal summary shortened; open individual test details in Output.]" : "")
        return CompilationResult(succeeded: success, phase: .test, exitCode: canceled ? nil : success ? 0 : 1,
            diagnostics: diagnostics, stdout: preview, stderr: "", duration: duration,
            detail: canceled ? "Build stopped. Unit-test execution was canceled; completed cases remain listed." : detail)
    }
}

/// Real libtest discovery and isolated, single-threaded invocations. A panic
/// aborts that one guest, allowing later tests to run. should_panic is reported
/// unsupported when libtest skips it in the panic-abort profile, never as passed.
struct RustUnitTestRunner: Sendable {
    private struct Event: Decodable {
        let type: String
        let event: String?
        let name: String?
        let ignore: Bool?
        let source_path: String?
        let start_line: Int?
    }

    private static func events(_ output: String) -> [Event] {
        output.split(separator: "\n").compactMap { line in
            try? JSONDecoder().decode(Event.self, from: Data(line.utf8))
        }
    }

    func run(compiler: WasmRustCompiler, source: String, sourcePath: String,
             supportingFiles: [String: String], edition: String, plan: CargoBuildPlan,
             filter: String? = nil, listOnly: Bool = false,
             onStage: (@Sendable (String) -> Void)? = nil) async -> RustUnitTestReport {
        let started = ContinuousClock.now
        let scope = "Selected entry only · std/normal prepared dependencies · no integration targets, dev-dependencies or doctests. #[should_panic] is unsupported in this panic-abort profile."
        let discovery = await compiler.unitTest(source: source, sourcePath: sourcePath, supportingFiles: supportingFiles,
            edition: edition, plan: plan, invocation: .discover, onStage: onStage)
        guard discovery.succeeded else {
            return .init(cases: [], compilerFailure: discovery, discoveryOnly: listOnly,
                         canceled: discovery.wasStopped || Task.isCancelled, detail: "Unit-test compilation or discovery failed. " + scope, duration: started.duration(to: .now))
        }
        let discovered = Self.events(discovery.stdout)
        guard discovered.contains(where: { $0.type == "suite" && $0.event == "completed" }) else {
            return .init(cases: [], compilerFailure: .failure(phase: .setup, detail: "Libtest did not finish discovery; no partial list was treated as complete."), discoveryOnly: listOnly, detail: scope, duration: started.duration(to: .now))
        }
        let all = discovered.filter { $0.type == "test" && $0.event == "discovered" }
        guard all.count <= 256, all.allSatisfy({ $0.name != nil }), Set(all.compactMap(\.name)).count == all.count else {
            return .init(cases: [], compilerFailure: .failure(phase: .setup, detail: "The selected-entry profile supports at most 256 distinct discovered unit tests."), discoveryOnly: listOnly, detail: scope, duration: started.duration(to: .now))
        }
        let files = supportingFiles.merging([sourcePath: source]) { _, new in new }
        var tests = all.compactMap { event -> RustUnitTestCase? in
            guard let name = event.name, filter == nil || name.contains(filter!) else { return nil }
            let path = event.source_path.flatMap { $0.hasPrefix("/work/") ? String($0.dropFirst(6)) : nil }
            let file = path.flatMap { files[$0] == nil ? nil : $0 }
            return .init(name: name, file: file, line: event.start_line, ignored: event.ignore == true,
                         state: event.ignore == true ? .skipped : .discovered,
                         detail: event.ignore == true ? "Ignored by the test declaration; this profile leaves ignored tests skipped." : "")
        }
        if listOnly { return .init(cases: tests, discoveryOnly: true, detail: scope, duration: started.duration(to: .now)) }
        var canceled = false
        var capturedBytes = 0
        let executionStarted = ContinuousClock.now
        func bounded(_ text: String) -> String {
            let limit = max(0, min(64 * 1024, 4 * 1024 * 1024 - capturedBytes))
            let bytes = Array(text.utf8.prefix(limit))
            capturedBytes += bytes.count
            return String(decoding: bytes, as: UTF8.self) + (text.utf8.count > limit ? "\n[Output shortened at the bounded report limit]" : "")
        }
        for index in tests.indices {
            if Task.isCancelled {
                canceled = true
                for rest in index..<tests.count where tests[rest].state == .discovered { tests[rest].state = .canceled }
                break
            }
            if executionStarted.duration(to: .now) > .seconds(120) {
                for rest in index..<tests.count where tests[rest].state == .discovered {
                    tests[rest].state = .notRun; tests[rest].detail = "The suite reached its 120-second execution budget. Run a smaller filter."
                }
                break
            }
            if tests[index].ignored { continue }
            onStage?("Testing \(tests[index].name) · isolated local guest")
            let result = await compiler.unitTest(source: source, sourcePath: sourcePath, supportingFiles: supportingFiles,
                edition: edition, plan: plan, invocation: .single(tests[index].name), onStage: onStage)
            if result.wasStopped || Task.isCancelled {
                canceled = true; tests[index].state = .canceled; tests[index].detail = result.detail
                for rest in (index + 1)..<tests.count where tests[rest].state == .discovered { tests[rest].state = .canceled }
                break
            }
            if result.phase != .run {
                return .init(cases: tests, compilerFailure: result, discoveryOnly: false,
                             detail: "The test harness could not be compiled. " + scope, duration: started.duration(to: .now))
            }
            let events = Self.events(result.stdout)
            let named = events.filter { $0.type == "test" && $0.name == tests[index].name }
            if named.contains(where: { $0.event == "ignored" }) {
                tests[index].state = .unsupported
                tests[index].detail = "Libtest skipped this non-ignored test in its panic-abort profile; #[should_panic] cannot be validated here."
            } else if result.succeeded && named.contains(where: { $0.event == "ok" })
                        && events.contains(where: { $0.type == "suite" && $0.event == "ok" }) {
                tests[index].state = .passed
            } else {
                tests[index].state = .failed
                tests[index].detail = result.succeeded
                    ? "The test guest returned without a complete libtest success result."
                    : result.detail + " A panic/assertion can abort this isolated guest; exact assertion text is shown only when emitted by the toolchain."
            }
            tests[index].stderr = bounded(result.stderr)
            tests[index].rawHarnessOutput = bounded(result.stdout)
            tests[index].stdout = bounded(result.stdout.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { (try? JSONDecoder().decode(Event.self, from: Data($0.utf8))) == nil }
                .joined(separator: "\n").trimmingCharacters(in: .newlines))
        }
        return .init(cases: tests, discoveryOnly: false, canceled: canceled,
                     detail: tests.isEmpty ? "No unit tests matched. " + scope : scope,
                     duration: started.duration(to: .now))
    }
}
