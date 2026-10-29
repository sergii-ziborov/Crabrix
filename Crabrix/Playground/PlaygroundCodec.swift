import Foundation
import JavaScriptCore
import Security
import CryptoKit

/// Runs the fixed, bundled Yjs codec. No user code, network or filesystem APIs
/// are exposed to this JavaScriptCore context.
@MainActor
final class PlaygroundCodec {
    struct Result: Decodable {
        var clientID: UInt32?
        var document: PlaygroundDocument?
        var snapshot: [UInt8]?
        var update: [UInt8]?
        var merged: [UInt8]?
        var presence: [UInt8]?
        var selections: [PlaygroundRemoteSelection]?
        var localSelection: PlaygroundRemoteSelection?
        var participants: Int?
        var error: String?
        var runtimeSource: String?
        var runtimePaths: [String]?
        var runtimeFrames: [RuntimePresenceFrame]?
    }
    struct RuntimePresenceFrame: Decodable, Equatable, Sendable { let clientID: UInt32; let clock: UInt64; let envelope: String }
    private let context: JSContext
    init(resourceURL: URL? = nil) throws {
        guard let context = JSContext(), let url = resourceURL ?? Bundle.main.url(forResource: "PlaygroundCodec", withExtension: "js") else { throw PlaygroundFailure("The bundled collaboration codec is unavailable.") }
        self.context = context
        let random: @convention(block) (Int) -> [UInt32] = { requested in
            let count = max(0, min(4096, requested))
            var result = [UInt32](repeating: 0, count: count)
            let status = result.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!) }
            // Fail closed: missing secure random must not create predictable peers.
            return status == errSecSuccess ? result : []
        }
        context.setObject(random, forKeyedSubscript: "__crabrixRandom" as NSString)
        let sourceOrigin: @convention(block) (String) -> String? = { value in
            guard value.utf16.count < 1000, value.utf8.count < 4000,
                  var parts = URLComponents(string: value), parts.scheme?.lowercased() == "https",
                  let host = parts.host?.lowercased(), ["github.com", "gist.github.com", "play.rust-lang.org"].contains(host),
                  parts.user == nil, parts.password == nil else { return nil }
            parts.scheme = "https"; parts.host = host
            if parts.port == 443 { parts.port = nil }
            if parts.percentEncodedPath.isEmpty { parts.path = "/" }
            guard let normalized = parts.url?.standardized.absoluteString, normalized.utf16.count < 1000 else { return nil }
            return normalized
        }
        context.setObject(sourceOrigin, forKeyedSubscript: "__crabrixSourceOrigin" as NSString)
        let cryptography: @convention(block) (String) -> String = { PlaygroundRuntimeCryptography.call($0) }
        context.setObject(cryptography, forKeyedSubscript: "__crabrixRuntimeCrypto" as NSString)
        context.evaluateScript(try String(contentsOf: url, encoding: .utf8))
        guard context.exception == nil else { throw PlaygroundFailure("Could not initialize the bundled collaboration codec.") }
    }
    func call(_ request: [String: Any]) throws -> Result {
        let json = try JSONSerialization.data(withJSONObject: request)
        guard json.count < 2_000_000, let argument = String(data: json, encoding: .utf8) else { throw PlaygroundFailure("Oversized collaboration operation.") }
        context.exception = nil
        guard let function = context.objectForKeyedSubscript("CrabrixPlaygroundCodec")?.objectForKeyedSubscript("call"),
              let result = function.call(withArguments: [argument])?.toString(), context.exception == nil, let data = result.data(using: .utf8) else { throw PlaygroundFailure("The local collaboration codec could not read this message.") }
        let value = try JSONDecoder().decode(Result.self, from: data)
        if let error = value.error { throw PlaygroundFailure(error) }
        if let document = value.document { _ = try document.validated() }
        return value
    }
    func initialize(_ document: PlaygroundDocument) throws -> Result { try call(["type": "initialize", "document": object(document)]) }
    func replace(_ document: PlaygroundDocument) throws -> Result { try call(["type": "replace", "document": object(document)]) }
    struct RuntimeSourceIdentity: Sendable, Equatable { let revision: String; let paths: [String] }
    func runtimeSourceIdentity() throws -> RuntimeSourceIdentity {
        let result = try call(["type": "runtime-source"])
        guard let source = result.runtimeSource, source.utf8.count <= 1_048_576,
              let paths = result.runtimePaths, (1...16).contains(paths.count) else { throw PlaygroundFailure("The shared execution source identity is unavailable.") }
        let revision = SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
        return RuntimeSourceIdentity(revision: revision, paths: paths)
    }
    func runtimePolicy(action: String, local: PlaygroundRuntimePolicyContext, envelope: Data? = nil,
                       controller: String? = nil, requestID: String? = nil, operations: [String]? = nil,
                       lifetimeMilliseconds: Int = 600_000) async throws -> PlaygroundRuntimePolicyReply {
        var request: [String: Any] = ["action": action, "context": try JSONSerialization.jsonObject(with: JSONEncoder().encode(local))]
        if let envelope {
            guard envelope.count <= PlaygroundRuntimeProtocol.envelopeBytes, let text = String(data: envelope, encoding: .utf8) else { throw PlaygroundFailure("Invalid runtime envelope.") }
            request["envelope"] = text
        }
        if let controller { request["controller"] = controller }
        if let requestID { request["requestID"] = requestID }
        if let operations { request["operations"] = operations; request["lifetimeMs"] = lifetimeMilliseconds }
        return try await runtimeCallback(request, method: "callRuntime", limit: 16_384, as: PlaygroundRuntimePolicyReply.self)
    }
    func runtimeHostCall(_ request: [String: Any]) async throws -> PlaygroundRuntimeHostReply {
        try await runtimeCallback(request, method: "callHost", limit: 1_500_000, as: PlaygroundRuntimeHostReply.self)
    }
    private func runtimeCallback<Value: Decodable & Sendable>(_ request: [String: Any], method: String, limit: Int, as: Value.Type) async throws -> Value {
        let json = try JSONSerialization.data(withJSONObject: request)
        guard json.count <= limit, let argument = String(data: json, encoding: .utf8),
              let function = context.objectForKeyedSubscript("CrabrixPlaygroundCodec")?.objectForKeyedSubscript(method) else { throw PlaygroundFailure("The local runtime policy is unavailable.") }
        let state = PlaygroundRuntimeCall<Value>()
        let reply = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.attach(continuation)
                if Task.isCancelled { state.finish(.failure(CancellationError())); return }
                let completion: @convention(block) (String) -> Void = { value in
                    do {
                        guard value.utf8.count <= limit else { throw PlaygroundFailure("Oversized local runtime policy result.") }
                        state.finish(.success(try JSONDecoder().decode(Value.self, from: Data(value.utf8))))
                    } catch { state.finish(.failure(error)) }
                }
                state.timeout = Task { @MainActor in
                    do { try await Task.sleep(for: .seconds(3)) } catch { return }
                    state.finish(.failure(PlaygroundFailure("Local runtime authorization timed out.")))
                }
                context.exception = nil
                let callback = JSValue(object: completion, in: context)!
                if function.call(withArguments: [argument, callback]) == nil || context.exception != nil {
                    state.finish(.failure(PlaygroundFailure("The local runtime policy could not authenticate this request.")))
                }
            }
        } onCancel: { Task { @MainActor in state.finish(.failure(CancellationError())) } }
        try Task.checkCancellation()
        return reply
    }
    private func object(_ document: PlaygroundDocument) throws -> Any { try JSONSerialization.jsonObject(with: JSONEncoder().encode(document.validated())) }
}
