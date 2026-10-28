import Foundation
import CryptoKit
@_spi(Fuzzing) import WasmKit

struct RustFormatRequest: Equatable, Sendable {
    enum Scope: Equatable, Sendable { case file(String), project }
    var scope: Scope
    var checkOnly = false

    func paths(in project: CrabrixProject) throws -> [String] {
        switch scope {
        case let .file(path):
            try ProjectFilePolicy.validatePath(path)
            guard path.hasSuffix(".rs"), project.files[path] != nil else { throw RustFormatter.Failure.rejected("select a Rust source file") }
            return [path]
        case .project:
            let excluded: Set<String> = ["vendor", "node_modules", "target", ".build", ".git", ".crabrix"]
            return project.files.keys.filter { path in
                path.hasSuffix(".rs") && !path.split(separator: "/").contains(where: { excluded.contains(String($0)) })
            }.sorted()
        }
    }
}

/// The pinned real rustfmt reactor. It parses text locally; it never executes
/// the user's Rust, follows project tools, or acquires code from the network.
final class RustFormatter: @unchecked Sendable {
    static let artifactSHA256 = "a3d4f84da1d32de38d2c2805db86ceb293ed2547b18bdcb87214e41bc2db6eee"
    static let version = "rustfmt 1.10.0-nightly / Rust 1.100.0"
    private let queue = DispatchQueue(label: "com.sergiiziborov.Crabrix.rustfmt", qos: .userInitiated)
    private let lock = NSLock()
    private var active: WasmInterrupter?
    private let runtime = RustcRuntime()
    private var module: Module?
    private let bundle: Bundle

    enum Failure: LocalizedError {
        case missing, integrity, configuration(String), rejected(String), noOutput
        var errorDescription: String? {
            switch self {
            case .missing: "The bundled Rust formatter is unavailable. Source was kept unchanged."
            case .integrity: "The bundled Rust formatter failed its integrity check. Source was kept unchanged."
            case let .configuration(detail): "Unsupported rustfmt configuration: \(detail). Source was kept unchanged."
            case let .rejected(detail): "Rustfmt could not format this file: \(detail). Source was kept unchanged."
            case .noOutput: "Rustfmt emitted no valid UTF-8 output. Source was kept unchanged."
            }
        }
    }

    init(bundle: Bundle = .main) { self.bundle = bundle }

    func cancel() { lock.withLock { active }?.cancel(reason: .userRequested) }

    func format(source: String, edition: String, configuration: String? = nil) async throws -> String {
        let interrupter = WasmInterrupter()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { [self] in
                    lock.withLock { active = interrupter }
                    defer { lock.withLock { active = nil } }
                    do { continuation.resume(returning: try perform(source: source, edition: edition, configuration: configuration, interrupter: interrupter)) }
                    catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { interrupter.cancel(reason: .userRequested) }
    }

    static func configuration(_ source: String?, edition: String) throws -> String {
        guard ["2015", "2018", "2021", "2024"].contains(edition) else { throw Failure.configuration("edition \(edition)") }
        let supported: Set<String> = ["edition", "style_edition", "max_width", "hard_tabs", "tab_spaces", "newline_style", "use_small_heuristics", "fn_call_width", "struct_lit_width", "struct_variant_width", "array_width", "chain_width", "single_line_if_else_max_width", "single_line_let_else_max_width", "use_field_init_shorthand", "use_try_shorthand", "reorder_imports", "reorder_modules"]
        var values: [String: String] = ["edition": edition, "style_edition": edition, "skip_children": "true"]
        if let source {
            guard source.utf8.count <= 64 * 1024 else { throw Failure.configuration("config exceeds 64 KiB") }
            for (key, value) in try TOMLParser.parse(source) {
                guard supported.contains(key) else { throw Failure.configuration(key) }
                let text: String
                switch value {
                case let .string(v): text = v
                case let .integer(v): text = String(v)
                case let .boolean(v): text = String(v)
                default: throw Failure.configuration(key + " requires a supported scalar value")
                }
                guard !text.contains("\n"), !text.contains("\r"), !text.contains("\0") else { throw Failure.configuration(key) }
                if key == "edition", text != edition { throw Failure.configuration("edition must match Cargo.toml (\(edition))") }
                values[key] = text
            }
        }
        return values.keys.sorted().map { "\($0)=\(values[$0]!)" }.joined(separator: "\n")
    }

    private func perform(source: String, edition: String, configuration: String?, interrupter: WasmInterrupter) throws -> String {
        guard interrupter.stopReason == nil else { throw CancellationError() }
        guard source.utf8.count <= ProjectFilePolicy.maximumFileBytes else { throw ProjectFilePolicy.Failure.fileTooLarge("selected Rust file") }
        let config = try Self.configuration(configuration, edition: edition)
        if module == nil {
            guard let url = bundle.url(forResource: "rust_fmt", withExtension: "wasm", subdirectory: "RustTools") else { throw Failure.missing }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == Self.artifactSHA256 else { throw Failure.integrity }
            module = try parseWasm(filePath: url.path)
        }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "CrabrixRustfmt-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: root) }
        let work = root.appending(path: "work", directoryHint: .isDirectory)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        try Data(source.utf8).write(to: work.appending(path: "input.rs"), options: .atomic)
        try Data(config.utf8).write(to: work.appending(path: "config"), options: .atomic)
        let output = try runtime.run(module: module!, arguments: ["rust_fmt"], environment: [:],
            preopens: [.init(guestPath: "/work", hostPath: work.path)], captureDirectory: root, capturePrefix: "format",
            resourceLimiter: WasmSandboxResourceLimiter(memoryLimitBytes: 128 * 1024 * 1024, tableElementLimit: 65_536),
            fuelBudget: 1_000_000_000, wallClockLimit: .seconds(15), interrupter: interrupter,
            softwareMemoryReservationBytes: 128 * 1024 * 1024, capturedOutputLimitBytes: 64 * 1024,
            reactorEntrypoint: "run")
        guard output.exitCode == 0 else { throw Failure.rejected(output.stderr.isEmpty ? "status \(output.exitCode)" : output.stderr) }
        let resultURL = work.appending(path: "output.rs")
        guard let size = try? resultURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= ProjectFilePolicy.maximumFileBytes,
              let data = try? Data(contentsOf: resultURL), let text = String(data: data, encoding: .utf8) else { throw Failure.noOutput }
        return text
    }
}
