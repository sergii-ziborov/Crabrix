import Foundation
import JavaScriptCore
import WasmKit

struct RustDebugSite: Codable, Equatable, Sendable, Identifiable {
    let id: Int
    let file: String
    let line: Int
    let column: Int
    let function: String
    let functionID: Int
    let kind: String
}
struct RustDebugVariable: Equatable, Sendable { let name: String; let type: String; let value: String }
struct RustDebugFrame: Equatable, Sendable { var site: RustDebugSite; var locals: [RustDebugVariable] }
struct RustDebugPause: Equatable, Sendable { let site: RustDebugSite; let frames: [RustDebugFrame]; let reason: String }
struct RustDebugBreakpoint: Hashable, Sendable { let file: String; let line: Int }
struct RustDebugPlan: Decodable, Sendable { let version: Int; let files: [String: String]; let sites: [RustDebugSite]; let notes: [String] }
struct RustDebugFailure: LocalizedError { let message: String; var errorDescription: String? { message } }

enum RustDebugInstrumenter {
    /// Runs only the signed app's fixed Rust parser/transformer, on the compiler
    /// queue. Project text is data; no source is evaluated as JavaScript.
    static func instrument(files: [String: String], entryFile: String, bundle: Bundle = .main) throws -> RustDebugPlan {
        guard let url = bundle.url(forResource: "RustDebugCompiler", withExtension: "js"), let context = JSContext() else { throw RustDebugFailure(message: "The bundled Debug compiler is unavailable.") }
        let buildScript = files["Cargo.toml"].flatMap { try? CratePackageManifest.parse($0) }?.buildScriptPath
        let rust = files.filter { $0.key.hasSuffix(".rs") && $0.key != buildScript && ($0.key as NSString).lastPathComponent != "build.rs" }
        let input = try JSONSerialization.data(withJSONObject: ["files": rust, "entryFile": entryFile])
        guard input.count <= 24 * 1024 * 1024 else { throw RustDebugFailure(message: "Debug source exceeds its preparation limit.") }
        context.evaluateScript(try String(contentsOf: url, encoding: .utf8))
        guard context.exception == nil,
              let function = context.objectForKeyedSubscript("CrabrixRustDebugCompiler")?.objectForKeyedSubscript("instrument"),
              let result = function.call(withArguments: [String(decoding: input, as: UTF8.self)])?.toString(),
              context.exception == nil, let data = result.data(using: .utf8), data.count <= 32 * 1024 * 1024
        else { throw RustDebugFailure(message: "Could not prepare a local Debug snapshot.") }
        if let failure = try JSONSerialization.jsonObject(with: data) as? [String: Any], let message = failure["error"] as? String { throw RustDebugFailure(message: message) }
        return try JSONDecoder().decode(RustDebugPlan.self, from: data)
    }
}

/// The interpreter is paused only on its serial background queue. The UI owns
/// commands; no network server, shell or engine debug trait is required.
final class RustDebugSession: @unchecked Sendable {
    enum Command: Sendable { case `continue`, into, over, out }
    static let importName = "__crabrix_debug_checkpoint_v1"
    private let condition = NSCondition()
    private var sites: [Int: RustDebugSite] = [:]
    private var frames: [RustDebugFrame] = []
    private var breakpoints: Set<RustDebugBreakpoint>
    private var boundBreakpoints: Set<RustDebugBreakpoint> = []
    private var mode: Command = .into
    private var targetDepth = 0
    private var stoppedOnce = false
    private var stopped = false
    private var requestedPause = false
    private var command: Command?
    private var events = 0
    private var interrupter: WasmInterrupter?
    private let onPlan: @Sendable ([RustDebugSite]) -> Void
    private let onPause: @Sendable (RustDebugPause) -> Void

    init(breakpoints: Set<RustDebugBreakpoint> = [], onPlan: @escaping @Sendable ([RustDebugSite]) -> Void, onPause: @escaping @Sendable (RustDebugPause) -> Void) {
        self.breakpoints = breakpoints; self.onPlan = onPlan; self.onPause = onPause
    }
    func prepare(_ plan: RustDebugPlan) {
        condition.lock(); sites = Dictionary(uniqueKeysWithValues: plan.sites.map { ($0.id, $0) }); bindBreakpoints(); condition.unlock()
        onPlan(plan.sites)
    }
    func updateBreakpoints(_ value: Set<RustDebugBreakpoint>) { condition.lock(); breakpoints = value; bindBreakpoints(); condition.unlock() }
    private func bindBreakpoints() {
        boundBreakpoints = Set(breakpoints.compactMap { breakpoint in
            sites.values.filter { $0.file == breakpoint.file && $0.kind == "statement" && $0.line >= breakpoint.line }.min(by: { $0.line < $1.line }).map { RustDebugBreakpoint(file: $0.file, line: $0.line) }
        })
    }
    func resume(_ value: Command) { condition.lock(); command = value; condition.broadcast(); condition.unlock() }
    func requestPause() { condition.lock(); requestedPause = true; condition.unlock() }
    func attach(_ value: WasmInterrupter?) { condition.lock(); interrupter = value; let cancel = stopped; condition.unlock(); if cancel { value?.cancel() } }
    var isStopped: Bool { condition.lock(); defer { condition.unlock() }; return stopped }
    func stop() { condition.lock(); stopped = true; let interrupt = interrupter; condition.broadcast(); condition.unlock(); interrupt?.cancel() }

    func link(to imports: inout Imports, store: Store, interrupter: WasmInterrupter?) {
        imports.define(module: "env", name: Self.importName, Function(store: store, parameters: [.i32,.i32,.i32,.i32]) { [self] caller, arguments in
            guard let instance = caller.instance, let memory = instance.exports[memory: "memory"] else { throw RustDebugFailure(message: "Debug guest has no memory.") }
            let pointer = Int(arguments[2].i32), count = Int(arguments[3].i32)
            guard count <= 65536, pointer <= memory.byteCount, count <= memory.byteCount - pointer else { throw RustDebugFailure(message: "Invalid debugger memory range.") }
            let bytes = memory.withUnsafeBufferPointer(offset: UInt(pointer), count: count) { Array($0) }
            try event(kind: Int(arguments[0].i32), siteID: Int(arguments[1].i32), bytes: bytes, interrupter: interrupter)
            return []
        })
    }

    private func event(kind: Int, siteID: Int, bytes: [UInt8], interrupter: WasmInterrupter?) throws {
        condition.lock()
        defer { condition.unlock() }
        guard !stopped else { throw WasmExecutionCancelled(reason: .userRequested) }
        if let reason = interrupter?.stopReason { throw WasmExecutionCancelled(reason: reason) }
        events += 1
        guard events <= 2_000_000, let site = sites[siteID] else { throw RustDebugFailure(message: "Invalid debugger event or checkpoint budget exceeded.") }
        if kind == 1 {
            guard site.kind == "entry", frames.count < 256 else { throw RustDebugFailure(message: "Debug call stack limit reached.") }
            frames.append(RustDebugFrame(site: site, locals: [])); return
        }
        guard let frame = frames.last, frame.site.functionID == site.functionID else { throw RustDebugFailure(message: "Debug call stack does not match the compiled snapshot.") }
        if kind == 3 { frames.removeLast(); return }
        guard kind == 2, site.kind == "statement" else { throw RustDebugFailure(message: "Invalid Debug checkpoint.") }
        let values = try JSONDecoder().decode([[String]].self, from: Data(bytes))
        guard values.count <= 32, values.allSatisfy({ $0.count == 3 && $0.allSatisfy { $0.count <= 1024 } }) else { throw RustDebugFailure(message: "Invalid local-variable snapshot.") }
        frames[frames.count - 1] = RustDebugFrame(site: site, locals: values.map { RustDebugVariable(name: $0[0], type: $0[1], value: $0[2]) })
        let breakpoint = boundBreakpoints.contains(RustDebugBreakpoint(file: site.file, line: site.line))
        let stepping = mode == .into || mode == .over && frames.count <= targetDepth || mode == .out && frames.count < targetDepth
        guard breakpoint || stepping || requestedPause else { return }
        requestedPause = false; command = nil
        let snapshot = RustDebugPause(site: site, frames: frames, reason: breakpoint ? "breakpoint" : stoppedOnce ? "step" : "entry")
        interrupter?.pauseDeadline()
        condition.unlock(); onPause(snapshot); condition.lock()
        let expiry = Date().addingTimeInterval(30 * 60)
        var timedOut = false
        while command == nil && !stopped {
            _ = condition.wait(until: min(expiry, Date().addingTimeInterval(0.25)))
            if Date() >= expiry { timedOut = true; break }
            if let reason = interrupter?.stopReason { interrupter?.resumeDeadline(); throw WasmExecutionCancelled(reason: reason) }
        }
        interrupter?.resumeDeadline()
        if timedOut { throw RustDebugFailure(message: "Debug pause expired after 30 minutes.") }
        guard !stopped else { throw WasmExecutionCancelled(reason: .userRequested) }
        mode = command ?? .continue; targetDepth = frames.count; stoppedOnce = true
    }
}
