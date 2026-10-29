import Foundation
import Combine
import UIKit

@MainActor
final class PlaygroundRuntimeHost: ObservableObject {
    @Published private(set) var grant: PlaygroundRuntimePolicyReply.Grant?
    @Published private(set) var requests: [PlaygroundRuntimePolicyReply.Request] = []
    @Published private(set) var jobs: [PlaygroundRuntimeHostReply.Job] = []
    @Published private(set) var notice = "Execution permission is off."
    @Published private(set) var working = false
    @Published private(set) var sharedOutput: PlaygroundRuntimeHostReply.SharedOutput?
    let fingerprint: String
    private let signer: PlaygroundRuntimeSigner
    private let session: PlaygroundLiveSession
    private let compiler: WasmRustCompiler
    private let localState: () -> (scope: String, ready: Bool, busy: Bool)
    private let onResult: (CompilationResult) -> Void
    var onDebug: ((RustDebugSession?, [RustDebugSite]?, RustDebugPause?) -> Void)?
    var onChange: (() -> Void)?
    var onStage: ((String) -> Void)?
    private var foreground = true, stopped = false, initialized = false
    private var epoch: UInt64 = 0
    private var queue: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var frames: [PlaygroundCodec.RuntimePresenceFrame] = []
    private var seen: [UInt32: UInt64] = [:]
    private var active: (id: String, revision: String, token: CompilerInvocationCancellation, debug: RustDebugSession?)?
    private var localGeneration = 0

    init(session: PlaygroundLiveSession, compiler: WasmRustCompiler,
         localState: @escaping () -> (scope: String, ready: Bool, busy: Bool),
         onResult: @escaping (CompilationResult) -> Void) {
        self.session = session; self.compiler = compiler; self.localState = localState; self.onResult = onResult
        let signer = PlaygroundRuntimeSigner(); self.signer = signer; fingerprint = signer.fingerprint
        session.onRuntimeFrames = { [weak self] frames in self?.frames = frames; self?.schedule() }
        session.onRuntimeReset = { [weak self] in self?.reset() }
        session.onRuntimeSourceChanged = { [weak self] in self?.sourceChanged() }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                self?.schedule()
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }
    private func reset() { initialized = false; epoch = session.runtimeEpoch; seen = [:]; localGeneration += 1; stopOwned(); grant = nil; requests = [] }
    func sourceChanged() { sharedOutput = nil; stopOwned(); schedule() }
    func clearSharedOutput() { sharedOutput = nil; Task { try? await call("clear-output") } }
    func setForeground(_ value: Bool) { foreground = value; if !value { revoke() }; schedule() }
    func stopOwned() { active?.token.cancel(); active?.debug?.stop() }
    func resumeLocal(_ command: RustDebugSession.Command) {
        guard let active else { return }
        // Commit the state before waking the guest: its next checkpoint can
        // arrive immediately on another thread.
        Task {
            await update(active.id, ["state":"working", "locals":[]])
            guard self.active?.id == active.id, !active.token.isCancelled,
                  (try? session.runtimeSourceIdentity().revision) == active.revision else { return }
            active.debug?.resume(command)
        }
    }
    func stop() {
        stopped = true; localGeneration += 1; stopOwned(); timer?.cancel(); queue?.cancel(); signer.destroy()
        try? session.publishRuntimePresence(nil)
    }
    private func context() throws -> [String: Any] {
        let identity = try session.runtimeSourceIdentity(), document = try session.localCopy(), state = localState()
        let profile = !document.files.keys.contains { ["cargo.toml", "build.rs"].contains(($0 as NSString).lastPathComponent.lowercased()) }
        return ["room": session.link.id, "target": fingerprint, "scope": state.scope + ":" + String(session.runtimeEpoch), "revision": identity.revision,
                "editCapability": session.link.access, "expires": Int64(session.link.expiresAt.timeIntervalSince1970 * 1000),
                "foreground": foreground && UIApplication.shared.applicationState == .active, "connected": session.runtimeConnected,
                "editConfirmed": session.runtimeEditConfirmed, "ready": state.ready, "busy": state.busy || working,
                "name": UIDevice.current.userInterfaceIdiom == .pad ? "Crabrix · iPad" : "Crabrix · iPhone", "debug": true, "profileReady": profile,
                "paths": identity.paths, "lines": identity.paths.map { (document.files[$0] ?? "").components(separatedBy: "\n").count }]
    }
    private func call(_ action: String, extra: [String: Any] = [:]) async throws {
        guard !stopped, session.document != nil else { return }
        var request = extra; request["action"] = action; request["context"] = try context()
        let generation = localGeneration
        let reply = try await session.runtimeHostCall(request)
        guard !stopped, generation == localGeneration else { return }
        if let error = reply.error { throw PlaygroundFailure(error) }
        sharedOutput = reply.sharedOutput
        grant = reply.grant; requests = reply.requests ?? []; jobs = reply.jobs ?? []
        for effect in reply.effects ?? [] where effect.type != "start" { apply(effect) }
        do {
        for publication in reply.publications ?? [] {
            let f = publication.fields
            let envelope = try signer.sign(.init(kind: f.kind, room: f.room, target: f.target, requestID: f.requestID, operation: f.operation, revision: f.revision ?? "", job: f.job ?? ""), payload: Data(publication.payloadJSON.utf8), editCapability: publication.proof ? session.link.access : nil)
            try session.publishRuntimePresence(envelope)
        }
        } catch {
            for effect in reply.effects ?? [] where effect.type == "start" { complete(effect, result: .failure(phase: .setup, detail: "The start acknowledgement could not be sent; no code executed.")) }
            throw error
        }
        for effect in reply.effects ?? [] where effect.type == "start" { apply(effect) }
        onChange?()
    }
    private func schedule() {
        guard queue == nil, !stopped, session.document != nil else { return }
        queue = Task { [weak self] in
            guard let self else { return }; defer { queue = nil }
            do {
                if session.runtimeConnected && foreground && !session.link.isReadOnly && !session.runtimeEditConfirmed && frames.contains(where: { $0.envelope.contains("permission-request") }) { try await session.confirmRuntimeEditAccess() }
                if !initialized || epoch != session.runtimeEpoch { epoch = session.runtimeEpoch; try await call("initialize"); initialized = true }
                else { try await call("tick") }
                let incoming = frames
                let live = Set(incoming.map(\.clientID)); seen = seen.filter { live.contains($0.key) }
                for frame in incoming where seen[frame.clientID] != frame.clock {
                    seen[frame.clientID] = frame.clock
                    do { try await call("frame", extra: ["envelope": frame.envelope]) } catch { /* Invalid peer traffic has no UI or source authority. */ }
                }
            } catch { /* Reconnection and readonly status are reported by the room. */ }
        }
    }
    func allow(_ request: PlaygroundRuntimePolicyReply.Request, operations: [String]) {
        Task {
            do { try await call("allow", extra: ["controller": request.controller, "requestID": request.requestID, "operations": operations]); notice = "Allowed on this device for up to ten minutes." }
            catch { notice = error.localizedDescription }
        }
    }
    func revoke() {
        stopOwned(); localGeneration += 1; grant = nil; requests = []
        Task { try? await call("revoke") }
        notice = "Execution permission revoked on this device."; onChange?()
    }
    private func apply(_ effect: PlaygroundRuntimeHostReply.Effect) {
        guard effect.type == "start" else {
            guard let active, active.id == effect.job, active.revision == effect.revision else {
                if effect.type == "stop" { Task { await update(effect.job, ["state":"finished", "succeeded":false, "stage":"Unstarted owned job stopped"]) } }
                return
            }
            switch effect.type {
            case "stop": stopOwned()
            case "continue": active.debug?.resume(.continue); onDebug?(active.debug, nil, nil)
            case "step": active.debug?.resume(effect.mode == "over" ? .over : effect.mode == "out" ? .out : .into); onDebug?(active.debug, nil, nil)
            case "breakpoints":
                if let paths = try? session.runtimeSourceIdentity().paths { active.debug?.updateBreakpoints(Set((effect.points ?? []).compactMap { point in guard point.count == 2, paths.indices.contains(point[0]) else { return nil }; return RustDebugBreakpoint(file: paths[point[0]], line: point[1]) })) }
            default: break
            }
            return
        }
        let state = localState()
        guard active == nil, !state.busy, state.ready, foreground, UIApplication.shared.applicationState == .active, session.runtimeEditConfirmed,
              let identity = try? session.runtimeSourceIdentity(), identity.revision == effect.revision,
              let document = try? session.localCopy(), let operation = PlaygroundRuntimeInput.Operation(rawValue: effect.operation) else {
            complete(effect, result: .failure(phase: .setup, detail: "Shared execution state changed before dispatch; no work was queued.")); return
        }
        do {
            let input = try PlaygroundRuntimeInput(document: document), token = CompilerInvocationCancellation()
            let debug: RustDebugSession? = operation == .debug ? RustDebugSession(onPlan: { [weak self] sites in
                Task { @MainActor in guard let self, !self.stopped, self.active?.id == effect.job, (try? self.session.runtimeSourceIdentity().revision) == effect.revision else { return }; self.onDebug?(self.active?.debug, sites, nil) }
            }, onPause: { [weak self] pause in
                Task { @MainActor in guard let self, !self.stopped, self.active?.id == effect.job, (try? self.session.runtimeSourceIdentity().revision) == effect.revision else { return }; self.onDebug?(self.active?.debug, nil, pause); await self.update(effect.job, ["state":"paused", "locals":pause.frames.last?.locals.map { ["name":$0.name,"type":$0.type,"value":$0.value] } ?? []]) }
            }) : nil
            sharedOutput = nil
            active = (effect.job, effect.revision, token, debug); working = true; onStage?("Shared \(operation.rawValue) · source only"); onChange?()
            Task { [self] in
                let result = await input.execute(operation, compiler: compiler, cancellation: token, debugSession: debug, onStage: { [weak self] stage in
                    Task { @MainActor in guard let self, !self.stopped, self.active?.id == effect.job else { return }; self.onStage?(stage); await self.update(effect.job, ["state":"progress", "stage":stage]) }
                })
                if active?.id == effect.job { active = nil; working = false; onDebug?(nil, [], nil); onChange?() }
                complete(effect, result: result)
            }
        } catch { complete(effect, result: .failure(phase: .setup, detail: error.localizedDescription)) }
    }
    private func complete(_ effect: PlaygroundRuntimeHostReply.Effect, result: CompilationResult) {
        guard !stopped else { return }
        if (try? session.runtimeSourceIdentity().revision) == effect.revision { onResult(result) }
        let paths = (try? session.runtimeSourceIdentity().paths) ?? []
        let diagnostics: [[String: Any]] = result.diagnostics.prefix(64).map { value in
            var row: [String: Any] = ["level":value.level, "message":Self.clip(value.message, 2048)]
            if let span = value.primarySpan, let index = paths.firstIndex(of: span.fileName.replacingOccurrences(of: "/work/", with: "")) { row["file"] = index; row["line"] = span.lineStart; row["column"] = span.columnStart }
            return row
        }
        let elapsed = result.duration.components
        let durationMs = Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
        Task { await update(effect.job, ["durationMs":durationMs, "state":"finished", "stage":Self.clip(result.detail, 180), "succeeded":result.succeeded, "exitCode":result.exitCode.map { $0 as Any } ?? NSNull(), "stdout":Self.clip(result.stdout,65536), "stderr":Self.clip(result.stderr,65536), "diagnostics":diagnostics]) }
    }
    /// Only the exact shared snapshot may publish ordinary Run output. A local
    /// project with extra/private files, resources or packages stays private.
    func reportLocalResult(_ value: CompilationResult, entry: String, files: [String:String], edition: String) {
        guard value.phase == .run, let document = try? session.localCopy(), document.files == files,
              document.entryFile == entry, document.edition == edition,
              let revision = try? session.runtimeSourceIdentity().revision else { return }
        Task { try? await call("local-output", extra: ["revision":revision,"update":["stdout":Self.clip(value.stdout,65536),"stderr":Self.clip(value.stderr,65536),"succeeded":value.succeeded,"exitCode":value.exitCode.map { $0 as Any } ?? NSNull()]]) }
    }
    private func update(_ job: String, _ value: [String: Any]) async { try? await call("update", extra: ["job":job,"update":value]) }
    static func clip(_ text: String, _ limit: Int) -> String { var bytes = Array(text.utf8.prefix(limit)); while String(bytes: bytes, encoding: .utf8) == nil && !bytes.isEmpty { bytes.removeLast() }; return String(decoding: bytes, as: UTF8.self) }
}
