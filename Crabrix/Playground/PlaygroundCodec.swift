import Foundation
import JavaScriptCore
import Security

/// Runs the fixed, bundled Yjs codec. No user code, network or filesystem APIs
/// are exposed to this JavaScriptCore context.
@MainActor
final class PlaygroundCodec {
    struct Result: Decodable {
        var document: PlaygroundDocument?
        var snapshot: [UInt8]?
        var update: [UInt8]?
        var merged: [UInt8]?
        var presence: [UInt8]?
        var selections: [PlaygroundRemoteSelection]?
        var localSelection: PlaygroundRemoteSelection?
        var participants: Int?
        var error: String?
    }
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
    private func object(_ document: PlaygroundDocument) throws -> Any { try JSONSerialization.jsonObject(with: JSONEncoder().encode(document.validated())) }
}
