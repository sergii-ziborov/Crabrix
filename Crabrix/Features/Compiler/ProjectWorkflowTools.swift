import Foundation
import SQLite3
import Network
@_spi(Fuzzing) import WasmKit

struct ProjectWorkflowFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Real SQLite connections. Every handle belongs to one database; the authorizer
/// denies access to other files, extension loading and runtime configuration.
final class ProjectSQLDatabase: Equatable, @unchecked Sendable {
    static func == (lhs: ProjectSQLDatabase, rhs: ProjectSQLDatabase) -> Bool { lhs === rhs }
    private let lock = NSLock()
    private var handle: OpaquePointer?
    private var remainingTicks = 0
    private var deadline = Date.distantPast
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    struct Result: Sendable { let columns: [String]; let rows: [[String?]]; let changes: Int }

    static func open(projectID: UUID, name: String) throws -> ProjectSQLDatabase {
        guard !name.isEmpty, name.utf8.count <= 80,
              name.range(of: "^[A-Za-z0-9_-]+(?:\\.(?:db|sqlite))?$", options: .regularExpression) != nil else {
            throw ProjectWorkflowFailure("Use a database name such as tasks.db, without directories.")
        }
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true).appending(path: "Crabrix/TerminalDatabases/" + projectID.uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return try ProjectSQLDatabase(path: root.appending(path: name).path)
    }

    static func remove(projectID: UUID) throws {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let root = support.appending(path: "Crabrix/TerminalDatabases/" + projectID.uuidString)
        if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
    }

    init(path: String = ":memory:") throws {
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Cannot open database."
            if let handle { sqlite3_close(handle) }; handle = nil
            throw ProjectWorkflowFailure(message)
        }
        sqlite3_busy_timeout(handle, 1000)
        sqlite3_limit(handle, SQLITE_LIMIT_LENGTH, 256 * 1024)
        sqlite3_limit(handle, SQLITE_LIMIT_SQL_LENGTH, 64 * 1024)
        sqlite3_limit(handle, SQLITE_LIMIT_COLUMN, 128)
        sqlite3_limit(handle, SQLITE_LIMIT_ATTACHED, 0)
        sqlite3_limit(handle, SQLITE_LIMIT_EXPR_DEPTH, 64)
        sqlite3_exec(handle, "PRAGMA foreign_keys=ON; PRAGMA max_page_count=2048; PRAGMA journal_mode=DELETE;", nil, nil, nil)
        sqlite3_set_authorizer(handle, { _, action, a, b, _, _ in
            if [SQLITE_ATTACH, SQLITE_DETACH, SQLITE_PRAGMA].contains(action) { return SQLITE_DENY }
            if action == SQLITE_FUNCTION, let raw = b ?? a {
                let function = String(cString: raw).lowercased()
                if ["load_extension", "readfile", "writefile"].contains(function) { return SQLITE_DENY }
            }
            return SQLITE_OK
        }, nil)
    }
    deinit { if let handle { sqlite3_close(handle) } }

    /// Runs all statements in one invocation. A failed script rolls back its open
    /// transaction; completed autocommit statements keep SQLite's normal semantics.
    func execute(_ sql: String, parameters: [Any] = [], readOnly: Bool = false) throws -> Result {
        lock.lock(); defer { lock.unlock() }
        guard let handle, !sql.contains("\0"), sql.utf8.count <= 65536, parameters.count <= 128 else {
            throw ProjectWorkflowFailure("SQL exceeds the database command limits.")
        }
        remainingTicks = 10000; deadline = Date().addingTimeInterval(2)
        let context = Unmanaged.passUnretained(self).toOpaque()
        sqlite3_progress_handler(handle, 1000, { raw in
            guard let raw else { return 1 }
            let owner = Unmanaged<ProjectSQLDatabase>.fromOpaque(raw).takeUnretainedValue()
            owner.remainingTicks -= 1
            return owner.remainingTicks <= 0 || Date() > owner.deadline ? 1 : 0
        }, context)
        defer { sqlite3_progress_handler(handle, 0, nil, nil) }
        var columns: [String] = [], rows: [[String?]] = []
        var bytes = 0, statements = 0
        do {
            try sql.withCString { start in
                var cursor: UnsafePointer<CChar>? = start
                while let current = cursor, current.pointee != 0 {
                    var statement: OpaquePointer?, tail: UnsafePointer<CChar>?
                    guard sqlite3_prepare_v2(handle, current, -1, &statement, &tail) == SQLITE_OK else {
                        throw ProjectWorkflowFailure(String(cString: sqlite3_errmsg(handle)))
                    }
                    guard tail != current else { break }; cursor = tail
                    guard let statement else { continue }
                    defer { sqlite3_finalize(statement) }
                    guard !readOnly || sqlite3_stmt_readonly(statement) != 0 else { throw ProjectWorkflowFailure("The verification query must be read-only.") }
                    statements += 1
                    guard statements <= 64, parameters.isEmpty || statements == 1 else {
                        throw ProjectWorkflowFailure("Use one parameterized statement or at most 64 script statements.")
                    }
                    guard sqlite3_bind_parameter_count(statement) == parameters.count else {
                        throw ProjectWorkflowFailure("The SQL parameter count does not match the supplied values.")
                    }
                    for (index, value) in parameters.enumerated() {
                        let slot = Int32(index + 1)
                        let code: Int32
                        if value is NSNull { code = sqlite3_bind_null(statement, slot) }
                        else if let number = value as? NSNumber {
                            if String(cString: number.objCType) == "d" || String(cString: number.objCType) == "f" {
                                code = sqlite3_bind_double(statement, slot, number.doubleValue)
                            } else {
                                guard number.stringValue.first != "-" || number.int64Value < 0,
                                      number.stringValue == String(number.int64Value) || number == 0 || number == 1 else {
                                    throw ProjectWorkflowFailure("SQL integer is outside the signed 64-bit range.")
                                }
                                code = sqlite3_bind_int64(statement, slot, number.int64Value)
                            }
                        } else if let text = value as? String {
                            guard text.utf8.count <= 256 * 1024 else { throw ProjectWorkflowFailure("SQL text value exceeds 256 KiB.") }
                            code = text.withCString { sqlite3_bind_text(statement, slot, $0, Int32(text.utf8.count), Self.transient) }
                        } else { throw ProjectWorkflowFailure("SQL values must be strings, numbers or null.") }
                        guard code == SQLITE_OK else { throw ProjectWorkflowFailure("Cannot bind SQL value.") }
                    }
                    let count = sqlite3_column_count(statement)
                    if count > 0 {
                        columns = (0..<count).map { String(cString: sqlite3_column_name(statement, $0)) }; rows = []
                    }
                    var status = sqlite3_step(statement)
                    while status == SQLITE_ROW {
                        var row: [String?] = []
                        for index in 0..<count {
                            if sqlite3_column_type(statement, index) == SQLITE_NULL { row.append(nil) }
                            else {
                                let length = Int(sqlite3_column_bytes(statement, index)); bytes += length
                                guard bytes <= 65536 else { throw ProjectWorkflowFailure("SQL result exceeds 64 KiB; add LIMIT or select fewer columns.") }
                                guard let value = sqlite3_column_text(statement, index) else { row.append(""); continue }
                                row.append(String(decoding: UnsafeBufferPointer(start: value, count: length), as: UTF8.self))
                            }
                        }
                        rows.append(row)
                        guard rows.count <= 1000 else { throw ProjectWorkflowFailure("SQL result exceeds 1000 rows; add LIMIT.") }
                        status = sqlite3_step(statement)
                    }
                    guard status == SQLITE_DONE else { throw ProjectWorkflowFailure(String(cString: sqlite3_errmsg(handle))) }
                }
            }
        } catch {
            if sqlite3_get_autocommit(handle) == 0 { sqlite3_exec(handle, "ROLLBACK", nil, nil, nil) }
            throw error
        }
        // Terminal commands never retain a half-open transaction between invocations.
        if sqlite3_get_autocommit(handle) == 0 {
            sqlite3_exec(handle, "ROLLBACK", nil, nil, nil)
            throw ProjectWorkflowFailure("Uncommitted transaction rolled back. Include COMMIT or ROLLBACK in the same command/script.")
        }
        return Result(columns: columns, rows: rows, changes: Int(sqlite3_changes(handle)))
    }

    func json(_ request: Data) throws -> Data {
        guard request.count <= 65536,
              let object = try JSONSerialization.jsonObject(with: request) as? [String: Any],
              let sql = object["sql"] as? String else { throw ProjectWorkflowFailure("Expected {sql, params} JSON.") }
        let result = try execute(sql, parameters: object["params"] as? [Any] ?? [], readOnly: object["readOnly"] as? Bool ?? false)
        if object["jsonResult"] as? Bool == true {
            guard result.columns.count == 1, result.rows.count == 1,
                  let value = result.rows[0][0], let bytes = value.data(using: .utf8),
                  (try? JSONSerialization.jsonObject(with: bytes, options: [.fragmentsAllowed])) != nil else {
                throw ProjectWorkflowFailure("JSON result mode requires one row containing one valid JSON value.")
            }
            return bytes
        }
        return try JSONSerialization.data(withJSONObject: ["columns": result.columns,
            "rows": result.rows.map { $0.map { $0 as Any? ?? NSNull() } }, "changes": result.changes], options: [.sortedKeys])
    }

    func link(to imports: inout Imports, store: Store, module: Module, interrupter: WasmInterrupter?) {
        let function = Function(store: store,
            parameters: [.i32, .i32, .i32, .i32], results: [.i32]) { [self] caller, arguments in
            if let reason = interrupter?.stopReason { throw WasmExecutionCancelled(reason: reason) }
            guard let memory = caller.instance?.exports[memory: "memory"], let size = memory.guestMemoryByteCount else { return [.i32(UInt32.max)] }
            let pointer = Int(arguments[0].i32), length = Int(arguments[1].i32)
            let output = Int(arguments[2].i32), capacity = Int(arguments[3].i32)
            guard length <= 65536, capacity <= 65536, pointer <= size,
                  length <= size - pointer, output <= size,
                  capacity <= size - output else { return [.i32(UInt32.max)] }
            let request = memory.withUnsafeBufferPointer(offset: UInt(pointer), count: length) { Data($0) }
            let response: Data
            do { response = try json(request) }
            catch { response = (try? JSONSerialization.data(withJSONObject: ["error": error.localizedDescription])) ?? Data() }
            if let reason = interrupter?.stopReason { throw WasmExecutionCancelled(reason: reason) }
            guard response.count <= capacity else { return [.i32(UInt32.max)] }
            memory.withUnsafeMutableBufferPointer(offset: UInt(output), count: response.count) { destination in
                response.copyBytes(to: destination)
            }
            return [.i32(UInt32(response.count))]
        }
        imports.define(module: "crabrix_sql", name: "query", function)
        imports.define(module: "crabrix_sql", name: "crabrix_sql_query", function)
        imports.define(module: "env", name: "crabrix_sql_query", function)
        // The installed direct-emission backend currently retains the Rust v0
        // foreign symbol in env. Bind only this named bridge under an explicit
        // database grant; other env imports keep normal unresolved-import errors.
        for item in module.imports where item.module == "env" && item.name.hasPrefix("_R")
            && item.name.contains("17crabrix_sql_query") {
            imports.define(module: item.module, name: item.name, function)
        }
    }
}

/// Strict HTTP/1.1 framing for the on-device, one-request-per-connection adapter.
/// Student Rust receives the real request on stdin and produces a real response.
enum ProjectHTTPWire {
    static let limit = 65536
    static func completeRequest(_ bytes: Data) throws -> Bool {
        guard bytes.count <= limit else { throw ProjectWorkflowFailure("HTTP request exceeds 64 KiB.") }
        guard let end = bytes.range(of: Data("\r\n\r\n".utf8)) else { return false }
        guard let header = String(data: bytes[..<end.lowerBound], encoding: .utf8) else { throw ProjectWorkflowFailure("Invalid HTTP headers.") }
        let lines = header.components(separatedBy: "\r\n")
        guard let first = lines.first, first.split(separator: " ").count == 3,
              first.hasSuffix(" HTTP/1.1") || first.hasSuffix(" HTTP/1.0") else { throw ProjectWorkflowFailure("Expected an HTTP/1.x request.") }
        let target = first.split(separator: " ")[1]
        guard target.hasPrefix("/") || target == "*" else { throw ProjectWorkflowFailure("Use an origin-form HTTP request target.") }
        var lengths: [Int] = []
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":"), !line.hasPrefix(" "), !line.hasPrefix("\t") else { throw ProjectWorkflowFailure("Invalid HTTP header.") }
            let name = line[..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if name == "transfer-encoding" { throw ProjectWorkflowFailure("Chunked requests are outside this local adapter; send Content-Length.") }
            if name == "content-length" {
                guard !value.isEmpty, value.allSatisfy(\.isNumber), let count = Int(value), count <= limit else { throw ProjectWorkflowFailure("Invalid Content-Length.") }
                lengths.append(count)
            }
        }
        guard lengths.count <= 1 else { throw ProjectWorkflowFailure("Duplicate Content-Length.") }
        let expected = end.upperBound + (lengths.first ?? 0)
        guard expected <= limit, bytes.count <= expected else { throw ProjectWorkflowFailure("HTTP pipelining is outside this local adapter.") }
        return bytes.count == expected
    }

    static func response(_ raw: String) throws -> Data {
        let bytes = Data(raw.utf8)
        guard bytes.count <= limit, let end = bytes.range(of: Data("\r\n\r\n".utf8)),
              let header = String(data: bytes[..<end.lowerBound], encoding: .utf8) else { throw ProjectWorkflowFailure("Rust must return an HTTP response with CRLF headers.") }
        var lines = header.components(separatedBy: "\r\n")
        let parts = (lines.first ?? "").split(separator: " ")
        guard parts.count >= 2, ["HTTP/1.0", "HTTP/1.1"].contains(String(parts[0])),
              let status = Int(parts[1]), (200...599).contains(status) else { throw ProjectWorkflowFailure("Invalid Rust HTTP status line.") }
        guard lines.dropFirst().allSatisfy({ $0.contains(":") }) else { throw ProjectWorkflowFailure("Invalid Rust response header.") }
        lines = lines.filter { !$0.lowercased().hasPrefix("content-length:") && !$0.lowercased().hasPrefix("connection:") && !$0.lowercased().hasPrefix("transfer-encoding:") }
        let body = bytes[end.upperBound...]
        return Data((lines.joined(separator: "\r\n") + "\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n").utf8) + body
    }
}

@MainActor
final class ProjectHTTPServer {
    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]
    private var jobs: [UUID: Task<Void, Never>] = [:]
    private var generation = UUID()
    private var observer: NSObjectProtocol?
    private var stopHandler: (() -> Void)?
    var isRunning: Bool { listener != nil }
    var port: UInt16? { listener?.port?.rawValue }

    func start(port: UInt16, handler: @escaping @Sendable (Data) async -> String,
               event: @escaping @MainActor (String, Bool) -> Void, onStop: @escaping @MainActor () -> Void = {}) throws {
        stop()
        stopHandler = onStop
        let identity = UUID(); generation = identity
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self, self.generation == identity else { return }
                switch state {
                case .ready: event("HTTP listening at http://127.0.0.1:\(listener.port?.rawValue ?? port) · frozen Rust snapshot · stop with http stop", false)
                case let .failed(error): event(error.localizedDescription, true); self.stop()
                default: break
                }
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                guard let self, self.generation == identity, self.connections.count < 4 else { connection.cancel(); return }
                let id = UUID(); self.connections[id] = connection
                connection.start(queue: .main)
                self.jobs[id] = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(35))
                    guard !Task.isCancelled else { return }
                    self?.close(id)
                }
                self.receive(connection, id: id, bytes: Data(), identity: identity, handler: handler, event: event)
            }
        }
        observer = NotificationCenter.default.addObserver(forName: NSNotification.Name("UIApplicationDidEnterBackgroundNotification"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
        listener.start(queue: .main)
    }

    private func receive(_ connection: NWConnection, id: UUID, bytes: Data, identity: UUID,
                         handler: @escaping @Sendable (Data) async -> String,
                         event: @escaping @MainActor (String, Bool) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: max(1, ProjectHTTPWire.limit - bytes.count)) { [weak self] data, _, ended, error in
            Task { @MainActor in
                guard let self, self.generation == identity, self.connections[id] != nil else { return }
                let accumulated = bytes + (data ?? Data())
                do {
                    if try ProjectHTTPWire.completeRequest(accumulated) {
                        let began = ContinuousClock.now
                        let output = await handler(accumulated)
                        guard self.generation == identity, self.connections[id] != nil else { return }
                        let response = try ProjectHTTPWire.response(output)
                        let requestID = String(decoding: accumulated, as: UTF8.self).components(separatedBy: "\r\n").compactMap { line -> String? in
                            guard let colon = line.firstIndex(of: ":"), line[..<colon].lowercased() == "x-request-id" else { return nil }
                            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                            return !value.isEmpty && value.utf8.count <= 64 && value.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 || $0 >= 65 && $0 <= 90 || $0 >= 97 && $0 <= 122 || $0 == 45 || $0 == 95 }) ? value : nil
                        }.first ?? "local"
                        let requestLine = String(decoding: accumulated.prefix(while: { $0 != 13 }), as: UTF8.self).split(separator: " ").map(String.init)
                        let resource = requestLine.count > 1 ? String(requestLine[1].split(separator: "?", maxSplits: 1).first ?? "") : "/"
                        event("[http \(requestID)] " + (requestLine.first ?? "HTTP") + " " + resource + " → " + output.components(separatedBy: "\r\n")[0] + " · " + began.duration(to: .now).crabrixDescription, false)
                        connection.send(content: response, completion: .contentProcessed { _ in
                            Task { @MainActor in self.close(id) }
                        })
                    } else if ended || error != nil || accumulated.count == ProjectHTTPWire.limit { self.close(id) }
                    else { self.receive(connection, id: id, bytes: accumulated, identity: identity, handler: handler, event: event) }
                } catch {
                    event(error.localizedDescription, true)
                    let response = "HTTP/1.1 400 Bad Request\r\nConnection: close\r\nContent-Length: 0\r\n\r\n"
                    connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in Task { @MainActor in self.close(id) } })
                }
            }
        }
    }
    private func close(_ id: UUID) { jobs.removeValue(forKey: id)?.cancel(); connections.removeValue(forKey: id)?.cancel() }
    func stop() {
        generation = UUID(); listener?.stateUpdateHandler = nil; listener?.newConnectionHandler = nil; listener?.cancel(); listener = nil
        for job in jobs.values { job.cancel() }; jobs.removeAll()
        for connection in connections.values { connection.cancel() }; connections.removeAll()
        if let observer { NotificationCenter.default.removeObserver(observer) }; observer = nil
        let stopped = stopHandler; stopHandler = nil; stopped?()
    }
}

/// A bounded real HTTP client; redirects stay visible instead of forwarding
/// credentials to another origin. Cookies and credential stores are disabled.
final class ProjectHTTPClient: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<(Data, HTTPURLResponse), any Error>?
    private var data = Data()
    private var response: HTTPURLResponse?
    private var session: URLSession?
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 35
            configuration.timeoutIntervalForResource = 40
            configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil
            let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
            self.session = session; session.dataTask(with: request).resume()
        }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        self.response = response as? HTTPURLResponse
        completionHandler(response.expectedContentLength > 65536 ? .cancel : .allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard self.data.count + data.count <= 65536 else { dataTask.cancel(); return }
        self.data.append(data)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let pending = continuation; continuation = nil
        if let error { pending?.resume(throwing: error) }
        else if let response { pending?.resume(returning: (data, response)) }
        else { pending?.resume(throwing: ProjectWorkflowFailure("Missing HTTP response.")) }
        session.finishTasksAndInvalidate(); self.session = nil
    }
}

struct ProjectShellWord: Equatable {
    let value: String
    let isOperator: Bool
}
enum ProjectCommandLexer {
    static func words(_ source: String) throws -> [ProjectShellWord] {
        var result: [ProjectShellWord] = [], value = ""
        var quote: Character?, escaped = false, started = false
        func flush() {
            if started { result.append(.init(value: value, isOperator: false)) }
            value = ""; started = false
        }
        var iterator = source.makeIterator(), current = iterator.next()
        while let character = current {
            if escaped { value.append(character); escaped = false; started = true }
            else if character == "\\", quote != "'" { escaped = true; started = true }
            else if let active = quote {
                if character == active { quote = nil } else { value.append(character) }
            } else if character == "'" || character == "\"" { quote = character; started = true }
            else if character.isWhitespace { flush() }
            else if character == "#", !started { break }
            else if "<>|;&".contains(character) {
                flush()
                let next = iterator.next()
                if next == character { result.append(.init(value: String(repeating: String(character), count: 2), isOperator: true)); current = iterator.next() }
                else { result.append(.init(value: String(character), isOperator: true)); current = next }
                continue
            } else { value.append(character); started = true }
            current = iterator.next()
        }
        guard quote == nil, !escaped else { throw ProjectWorkflowFailure("shell: unmatched quote or trailing escape") }
        flush(); return result
    }

    static func runInput(_ words: [ProjectShellWord], files: [String: String], directory: String, projectID: UUID? = nil) throws -> RustProgramInput {
        var words = words, input = RustProgramInput()
        if words.first?.value == "env" {
            words.removeFirst()
            while let first = words.first, !first.isOperator, let equal = first.value.firstIndex(of: "=") {
                input.environment[String(first.value[..<equal])] = String(first.value[first.value.index(after: equal)...]); words.removeFirst()
            }
        }
        guard words.count >= 2, words[0].value == "cargo", words[1].value == "run" else {
            throw ProjectWorkflowFailure("usage: env KEY=value cargo run -- [arguments] [< input.txt]")
        }
        words.removeFirst(2)
        if words.first?.value == "--database", words.first?.isOperator == false {
            guard words.count >= 2, !words[1].isOperator, let projectID else { throw ProjectWorkflowFailure("--database needs one project-local database name.") }
            input.database = try ProjectSQLDatabase.open(projectID: projectID, name: words[1].value)
            words.removeFirst(2)
        }
        var redirected = false
        if words.first?.value == "--" && words.first?.isOperator == false { words.removeFirst() }
        else if words.first?.isOperator == false {
            throw ProjectWorkflowFailure("Separate program arguments with cargo run --.")
        }
        var index = 0
        while index < words.count {
            let word = words[index]
            if word.isOperator {
                guard word.value == "<", !redirected, index + 1 < words.count, !words[index + 1].isOperator else {
                    throw ProjectWorkflowFailure("This CLI profile supports one stdin file (<); pipelines and output redirection are not enabled.")
                }
                let raw = words[index + 1].value
                var path = directory.split(separator: "/").map(String.init)
                guard !raw.hasPrefix("/"), !raw.hasPrefix("~") else { throw ProjectWorkflowFailure("Use an input file inside this project.") }
                for part in raw.split(separator: "/") {
                    if part == "." { continue }
                    if part == ".." { guard !path.isEmpty else { throw ProjectWorkflowFailure("Input path leaves the project.") }; path.removeLast() }
                    else { path.append(String(part)) }
                }
                guard let text = files[path.joined(separator: "/")] else { throw ProjectWorkflowFailure("stdin file does not exist: " + raw) }
                input.standardInput = Data(text.utf8); redirected = true; index += 2
            } else { input.arguments.append(word.value); index += 1 }
        }
        guard input.isValid else { throw ProjectWorkflowFailure("Program input exceeds the bounded CLI profile.") }
        return input
    }
}

/// One explicit request per file. Its output uses the same bounded client and
/// validation as curl, including redirect and header handling.
enum ProjectHTTPRequestFile {
    static func curlArguments(_ source: String) throws -> [String] {
        guard source.utf8.count <= 65536 else { throw ProjectWorkflowFailure("HTTP request file exceeds 64 KiB.") }
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var index = 0
        while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).isEmpty || lines[index].hasPrefix("#") { index += 1 }
        guard index < lines.count else { throw ProjectWorkflowFailure("HTTP request file is empty.") }
        let request = lines[index].split(whereSeparator: \.isWhitespace).map(String.init); index += 1
        guard (request.count == 2 || request.count == 3 && request[2] == "HTTP/1.1"),
              ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"].contains(request[0]) else {
            throw ProjectWorkflowFailure("Expected METHOD URL [HTTP/1.1] on the first request line.")
        }
        var arguments = ["-i", "-X", request[0]]
        while index < lines.count, !lines[index].isEmpty {
            guard !lines[index].hasPrefix("#"), lines[index].contains(":") else { throw ProjectWorkflowFailure("Invalid HTTP request header.") }
            arguments += ["-H", lines[index]]; index += 1
        }
        if index < lines.count { index += 1 }
        let body = lines[index...].joined(separator: "\n")
        guard !body.components(separatedBy: "\n").contains(where: { $0.hasPrefix("###") }) else {
            throw ProjectWorkflowFailure("Use one request per .http file in this profile.")
        }
        if !body.isEmpty { arguments += ["--data-binary", body] }
        return arguments + [request[1]]
    }
}
