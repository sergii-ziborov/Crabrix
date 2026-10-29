import Foundation
import Combine

/// Temporary, encrypted collaboration only. Compilation remains in the normal
/// local compiler. Joining a room never starts source code automatically.
@MainActor
final class PlaygroundLiveSession: ObservableObject {
    @Published private(set) var status = "Connecting…"
    @Published private(set) var document: PlaygroundDocument?
    @Published private(set) var selections: [PlaygroundRemoteSelection] = []
    @Published private(set) var participants = 1
    @Published private(set) var expired = false
    let link: PlaygroundLink
    private(set) var owner: String?
    private(set) var viewAccess: String?
    var onDocument: ((PlaygroundDocument) -> Void)?
    var onSelections: (([PlaygroundRemoteSelection]) -> Void)?
    var onLocalSelection: ((PlaygroundRemoteSelection) -> Void)?
    var onStatus: ((String) -> Void)?
    var onRuntimeFrames: (([PlaygroundCodec.RuntimePresenceFrame]) -> Void)?
    var onRuntimeReset: (() -> Void)?
    private let codec: PlaygroundCodec
    private let origin: URL
    private let network: URLSession
    private let peer = PlaygroundEncryption.newSecret()
    private var sequence = 0
    private var connected = false
    private var stopped = false
    private var streamTask: Task<Void, Never>?
    private var flushTask: Task<Void, Never>?
    private var presenceTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var snapshotTask: Task<Void, Never>?
    private var pending: [(id: String, bytes: Data)] = []
    private var presence: Data?
    private var runtimeFrames: [PlaygroundCodec.RuntimePresenceFrame] = []
    private var runtimeConnection: UInt64 = 0
    private var confirmedRuntimeConnection: UInt64?
    var runtimeEditConfirmed: Bool { connected && !stopped && !expired && !link.isReadOnly && link.expiresAt > Date() && confirmedRuntimeConnection == runtimeConnection }
    private func resetRuntime() { runtimeConnection &+= 1; confirmedRuntimeConnection = nil; onRuntimeReset?() }
    func runtimeSourceIdentity() throws -> PlaygroundCodec.RuntimeSourceIdentity { try codec.runtimeSourceIdentity() }
    func publishRuntimePresence(_ envelope: Data?) throws {
        guard !stopped, !expired else { throw PlaygroundFailure("This Playground is disconnected.") }
        if let envelope, envelope.count > PlaygroundRuntimeProtocol.envelopeBytes { throw PlaygroundFailure("Oversized runtime presence.") }
        let value: Any = try envelope.map { try JSONSerialization.jsonObject(with: $0) } ?? NSNull()
        try absorb(codec.call(["type": "runtime-presence", "envelope": value])); schedulePresence()
    }
    func confirmRuntimeEditAccess() async throws {
        guard connected, !stopped, !expired, !link.isReadOnly, link.expiresAt > Date() else { throw PlaygroundFailure("Runtime access requires a connected editable room.") }
        if runtimeEditConfirmed { return }
        let generation = runtimeConnection
        let packet = try PlaygroundEncryption.seal(Data([0, 0]), secret: link.key)
        let (data, _) = try await post(["type": "update", "peer": peer, "messageID": PlaygroundEncryption.newSecret(), "packet": ["iv": packet.iv, "data": packet.data]])
        struct Confirmation: Decodable { let sequence: Int }
        let response = try JSONDecoder().decode(Confirmation.self, from: data)
        guard response.sequence > 0, generation == runtimeConnection, connected, !stopped, !expired, link.expiresAt > Date() else { throw PlaygroundFailure("Runtime connection changed during edit confirmation.") }
        confirmedRuntimeConnection = generation
    }

    init(link: PlaygroundLink, origin: URL? = nil, codecURL: URL? = nil) throws {
        self.link = link; self.origin = origin ?? PlaygroundRelayConfiguration.origin; self.codec = try PlaygroundCodec(resourceURL: codecURL)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.httpCookieStorage = nil; configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 60; configuration.timeoutIntervalForResource = 86400
        network = URLSession(configuration: configuration)
    }

    static func create(document: PlaygroundDocument, lifetimeSeconds: Int, origin: URL? = nil, codecURL: URL? = nil) async throws -> PlaygroundLiveSession {
        let origin = origin ?? PlaygroundRelayConfiguration.origin
        _ = try document.validated()
        guard (60...86400).contains(lifetimeSeconds) else { throw PlaygroundFailure("Choose a lifetime up to 24 hours.") }
        let codec = try PlaygroundCodec(resourceURL: codecURL)
        _ = try codec.initialize(document)
        let snapshot = try codec.call(["type": "snapshot"]).snapshot ?? []
        let key = PlaygroundEncryption.newSecret()
        let packet = try PlaygroundEncryption.seal(Data(snapshot), secret: key)
        var request = URLRequest(url: origin.appendingPathComponent("api/playground/rooms/"))
        request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["snapshot": ["iv": packet.iv, "data": packet.data], "lifetimeSeconds": lifetimeSeconds])
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response, data: data)
        struct Created: Decodable { let id: String; let edit: String; let owner: String; let view: String; let expiresAt: Double }
        let value = try JSONDecoder().decode(Created.self, from: data)
        let link = PlaygroundLink(id: value.id, key: key, access: value.edit, expiresAt: Date(timeIntervalSince1970: value.expiresAt / 1000), isReadOnly: false)
        let session = try PlaygroundLiveSession(link: link, origin: origin, codecURL: codecURL)
        // Preserve the exact CRDT IDs from the encrypted initial snapshot.
        try session.absorb(session.codec.call(["type": "state", "snapshot": snapshot, "events": []]))
        session.owner = value.owner; session.viewAccess = value.view
        return session
    }

    func start() {
        guard streamTask == nil, !stopped else { return }
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard let self, !stopped, !Task.isCancelled else { return }
                do { try absorb(codec.call(["type": "tick"])); schedulePresence() } catch { updateStatus(error.localizedDescription) }
                if Date() >= link.expiresAt { expire(); return }
            }
        }
        streamTask = Task { [weak self] in
            guard let self else { return }
            while !stopped, !Task.isCancelled, Date() < link.expiresAt {
                do { try await stream() }
                catch { if !stopped && !Task.isCancelled { updateStatus("Reconnecting · local changes retained. " + error.localizedDescription) } }
                resetRuntime()
                connected = false
                if !stopped && !Task.isCancelled { try? await Task.sleep(for: .seconds(2)) }
            }
            if !stopped && !Task.isCancelled { expire() }
        }
    }

    func edit(file: String, text: String) {
        guard !link.isReadOnly, !expired, !stopped else { return }
        do { try absorb(codec.call(["type": "file", "path": file, "text": text])); scheduleFlush() }
        catch { updateStatus(error.localizedDescription) }
    }
    func replace(_ source: PlaygroundDocument) throws {
        guard !link.isReadOnly, !expired, !stopped else { throw PlaygroundFailure("This Playground is read only or expired.") }
        try absorb(codec.replace(source)); scheduleFlush()
    }
    func select(file: String, range: NSRange) {
        guard !expired, !stopped else { return }
        do { try absorb(codec.call(["type": "selection", "file": file, "anchor": range.location, "head": NSMaxRange(range)])); schedulePresence() }
        catch { updateStatus(error.localizedDescription) }
    }
    func localCopy() throws -> PlaygroundDocument {
        guard let value = document else { throw PlaygroundFailure("Wait for the encrypted source to arrive.") }
        return try value.validated()
    }
    func stop() {
        guard !stopped else { return }
        stopped = true; connected = false
        resetRuntime(); runtimeFrames = []; onRuntimeFrames?([])
        streamTask?.cancel(); flushTask?.cancel(); presenceTask?.cancel(); heartbeatTask?.cancel(); snapshotTask?.cancel()
        network.invalidateAndCancel(); selections = []; onSelections?([])
        updateStatus(expired ? "Playground expired · local copies remain available" : "Disconnected · local copy retained")
    }
    func closeRoom() async throws {
        guard let owner else { throw PlaygroundFailure("Only the creator can end this room early.") }
        var request = request(); request.httpMethod = "DELETE"; request.setValue("Bearer " + owner, forHTTPHeaderField: "Authorization")
        let (data, response) = try await network.data(for: request); try Self.check(response, data: data)
        expire()
    }
    private func expire() { expired = true; stop() }
    private func updateStatus(_ text: String) { status = text; onStatus?(text) }
    private func request(_ suffix: String = "") -> URLRequest {
        var request = URLRequest(url: URL(string: "/api/playground/rooms/\(link.id)/" + suffix, relativeTo: origin)!.absoluteURL)
        request.setValue("Bearer " + link.access, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }
    private static func check(_ response: URLResponse, data: Data) throws {
        guard let response = response as? HTTPURLResponse else { throw PlaygroundFailure("No Playground response.") }
        guard (200...299).contains(response.statusCode) else {
            struct Failure: Decodable { let error: String }
            let message = (try? JSONDecoder().decode(Failure.self, from: data))?.error ?? "Playground connection failed (\(response.statusCode))."
            throw PlaygroundFailure(message)
        }
    }
    private func post(_ body: [String: Any]) async throws -> (Data, Int) {
        var request = request(); request.httpMethod = "POST"; request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await network.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 410 { expire() }
        try Self.check(response, data: data)
        return (data, code)
    }
    private func absorb(_ value: PlaygroundCodec.Result) throws {
        if let next = value.document, document != next { document = next; onDocument?(next) }
        if let next = value.selections, selections != next { selections = next; onSelections?(next) }
        if let selection = value.localSelection { onLocalSelection?(selection) }
        if let count = value.participants { participants = count }
        if let update = value.update, update.count > 2 { pending.append((PlaygroundEncryption.newSecret(), Data(update))) }
        if let bytes = value.presence { presence = Data(bytes) }
        if let frames = value.runtimeFrames, frames != runtimeFrames { runtimeFrames = frames; onRuntimeFrames?(frames) }
    }
    private func stream() async throws {
        let (bytes, response) = try await network.bytes(for: request("events/?peer=" + peer))
        if (response as? HTTPURLResponse)?.statusCode == 410 { expire(); return }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw PlaygroundFailure("The interview connection is unavailable.") }
        var event = "", payload = ""
        for try await line in bytes.lines {
            if stopped || Task.isCancelled { return }
            guard line.utf8.count <= 2_000_000 else { throw PlaygroundFailure("Oversized interview message.") }
            // URLSession.AsyncBytes.lines skips empty lines. Each relay event has
            // exactly one data line, so consume it immediately.
            if line.hasPrefix("event: ") { event = String(line.dropFirst(7)); payload = "" }
            else if line.hasPrefix("data: ") { payload = String(line.dropFirst(6)); try receive(event: event, data: Data(payload.utf8)) }
        }
    }
    private struct State: Decodable { let expiresAt: Double; let sequence: Int; let snapshot: PlaygroundEncryptedPacket; let events: [Update]; let presence: [Presence]? }
    private struct Update: Decodable { let sequence: Int; let packet: PlaygroundEncryptedPacket }
    private struct Presence: Decodable { let packet: PlaygroundEncryptedPacket }
    private func receive(event: String, data: Data) throws {
        if event == "expired" || event == "closed" { expire(); return }
        if event == "ping" { return }
        if event == "state" {
            resetRuntime()
            let state = try JSONDecoder().decode(State.self, from: data)
            guard abs(state.expiresAt - link.expiresAt.timeIntervalSince1970 * 1000) < 1 else { throw PlaygroundFailure("The Playground lifetime does not match the link.") }
            let snapshot = try PlaygroundEncryption.open(state.snapshot, secret: link.key)
            let events = try state.events.map { Array(try PlaygroundEncryption.open($0.packet, secret: link.key, maximum: 196608)) }
            try absorb(codec.call(["type": "state", "snapshot": Array(snapshot), "events": events]))
            for item in state.presence ?? [] { receivePresence(item.packet) }
            sequence = state.sequence; connected = true
            updateStatus(link.isReadOnly ? "Connected · view only · encrypted" : "Connected · shared editor · encrypted")
            scheduleFlush(); schedulePresence()
        } else if event == "update" {
            let value = try JSONDecoder().decode(Update.self, from: data)
            if value.sequence <= sequence { return }
            guard value.sequence == sequence + 1 else { throw PlaygroundFailure("Resynchronizing interview changes.") }
            let bytes = try PlaygroundEncryption.open(value.packet, secret: link.key, maximum: 196608)
            try absorb(codec.call(["type": "update", "bytes": Array(bytes)])); sequence = value.sequence; scheduleSnapshot()
        } else if event == "presence" { receivePresence(try JSONDecoder().decode(Presence.self, from: data).packet) }
    }
    private func receivePresence(_ packet: PlaygroundEncryptedPacket) {
        do {
            let bytes = try PlaygroundEncryption.open(packet, secret: link.key, maximum: 4000)
            try absorb(codec.call(["type": "presence", "bytes": Array(bytes)]))
        } catch { /* Discard malformed transient presence without disconnecting the shared source. */ }
    }
    private func scheduleFlush() {
        guard flushTask == nil, connected, !stopped, !link.isReadOnly else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard let self else { return }
            while connected, !stopped, !Task.isCancelled, !pending.isEmpty {
                do {
                    if pending.count > 1 {
                        let bytes = try codec.call(["type": "merge", "updates": pending.map { Array($0.bytes) }]).merged ?? []
                        pending = [(PlaygroundEncryption.newSecret(), Data(bytes))]
                    }
                    guard let item = pending.first else { break }
                    guard item.bytes.count <= 196592 else { throw PlaygroundFailure("Live change exceeds the room limit. Save a local copy.") }
                    let packet = try PlaygroundEncryption.seal(item.bytes, secret: link.key)
                    _ = try await post(["type": "update", "peer": peer, "messageID": item.id, "packet": ["iv": packet.iv, "data": packet.data]])
                    pending.removeFirst(); scheduleSnapshot()
                } catch {
                    if stopped || Task.isCancelled { break }
                    updateStatus("Local changes pending. " + error.localizedDescription)
                    try? await Task.sleep(for: .seconds(2))
                }
            }
            flushTask = nil
        }
    }
    private func schedulePresence() {
        guard connected, !stopped, presenceTask == nil, presence != nil else { return }
        presenceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self, !stopped, !Task.isCancelled, let bytes = presence else { self?.presenceTask = nil; return }
            presence = nil
            do {
                let packet = try PlaygroundEncryption.seal(bytes, secret: link.key)
                _ = try await post(["type": "presence", "peer": peer, "packet": ["iv": packet.iv, "data": packet.data]])
            } catch { /* Presence is ephemeral; source updates retry independently. */ }
            presenceTask = nil
            if presence != nil { schedulePresence() }
        }
    }
    private func scheduleSnapshot() {
        guard snapshotTask == nil, !stopped, !link.isReadOnly else { return }
        snapshotTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, !stopped, !Task.isCancelled else { return }
            snapshotTask = nil
            guard connected, pending.isEmpty else { return }
            do {
                let currentSequence = sequence
                let bytes = try codec.call(["type": "snapshot"]).snapshot ?? []
                let packet = try PlaygroundEncryption.seal(Data(bytes), secret: link.key)
                _ = try await post(["type": "snapshot", "sequence": currentSequence, "packet": ["iv": packet.iv, "data": packet.data]])
            } catch { if !stopped { scheduleSnapshot() } }
        }
    }
}
