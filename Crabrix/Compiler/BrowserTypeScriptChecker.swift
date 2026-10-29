import Foundation

enum BrowserTypeScriptProfile {
    static let version = "5.9.3"
    static func directory(files: [String: String], entry: String) -> String {
        let initial = (entry as NSString).deletingLastPathComponent
        var directory = initial
        while true {
            let prefix = directory.isEmpty ? "" : directory + "/"
            if files[prefix + "tsconfig.json"] != nil || files[prefix + "jsconfig.json"] != nil { return directory }
            if directory.isEmpty { break }
            directory = (directory as NSString).deletingLastPathComponent
        }
        let manifest = BrowserProjectConfiguration.manifestPath(files: files, entry: entry)
        return files[manifest] != nil ? (manifest as NSString).deletingLastPathComponent : initial
    }
    static func applies(files: [String: String], directory: String) -> Bool {
        let prefix = directory.isEmpty ? "" : directory + "/"
        return files.keys.contains { path in
            path.hasPrefix(prefix) && !path.split(separator: "/").contains("node_modules")
                && ["ts", "tsx", "mts", "cts"].contains((path as NSString).pathExtension.lowercased())
        } || files[prefix + "tsconfig.json"] != nil
    }
}

struct BrowserTypeScriptResult: Decodable, Sendable {
    struct Diagnostic: Decodable, Sendable {
        let code: String
        let kind: String
        let level: String
        let message: String
        let file: String
        let line: Int
        let column: Int
        func rustDiagnostic(files: [String: String]) -> RustDiagnostic {
            let lines = (files[file] ?? "").components(separatedBy: "\n")
            let span: [RustDiagnostic.Span] = file.isEmpty ? [] : [.init(fileName: file, lineStart: line, lineEnd: line,
                columnStart: column, columnEnd: column + 1, isPrimary: true, label: nil,
                sourceLine: line > 0 && line <= lines.count ? lines[line - 1] : "")]
            return .init(level: level, message: message, code: code, rendered: "\(file):\(line):\(column): \(code): \(message)", spans: span)
        }
    }
    let version: String
    let checked: Bool
    let roots: Int
    let sourceFiles: Int
    let succeeded: Bool
    let diagnostics: [Diagnostic]
    let omittedDiagnostics: Int
}

/// A fixed compiler runs in an isolated WebKit Worker. User text is compiler
/// input; no user JS, plugins, lifecycle scripts or host filesystem is executed.
/// Input/output/deadline are bounded; JavaScript heap has no hard Wasm-like cap.
@MainActor
final class BrowserTypeScriptChecker {
    private var runtime: BrowserTypeScriptRuntime?
    private var preparing: Task<Data, Error>?
    private var working = false
    private var canceled = false
    var isWorking: Bool { working }

    func check(files: [String: String], directory: String) async throws -> BrowserTypeScriptResult? {
        guard BrowserTypeScriptProfile.applies(files: files, directory: directory) else { return nil }
        guard !working else { throw BrowserBuildError(message: "TypeScript checking is already working.") }
        working = true; canceled = false
        defer { working = false; preparing = nil }
        struct Payload: Encodable, Sendable { let files: [String: String]; let directory: String }
        struct Reply: Decodable { let result: BrowserTypeScriptResult?; let error: String? }
        let preparation = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            try ProjectFilePolicy.validate(files)
            if !directory.isEmpty { try ProjectFilePolicy.validatePath(directory) }
            let data = try JSONEncoder().encode(Payload(files: files, directory: directory))
            try Task.checkCancellation()
            return data
        }
        preparing = preparation
        let payload = try await withTaskCancellationHandler { try await preparation.value } onCancel: { preparation.cancel() }
        try Task.checkCancellation()
        guard !canceled else { throw CancellationError() }
        let worker = BrowserTypeScriptRuntime(); runtime = worker
        defer { worker.releaseMemory(); runtime = nil }
        let reply = try JSONDecoder().decode(Reply.self, from: await worker.perform(payload))
        if let message = reply.error { throw BrowserBuildError(message: message) }
        guard let result = reply.result, result.version == BrowserTypeScriptProfile.version else {
            throw BrowserBuildError(message: "The TypeScript checker returned an invalid compiler identity.")
        }
        return result
    }

    func cancel() { canceled = true; preparing?.cancel(); runtime?.releaseMemory(message: "TypeScript checking stopped.") }
}
