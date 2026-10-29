import Foundation
import CryptoKit

// Fixed bounded verification primitives for the bundled JavaScriptCore policy.
// No private signing key, source evaluation, filesystem or network is exposed.
enum PlaygroundRuntimeCryptography {
    private struct Request: Decodable { let op: String; let data: [UInt8]; let key: [UInt8]?; let signature: [UInt8]? }
    static func call(_ input: String) -> String {
        do {
            guard input.utf8.count <= 16_384 else { throw Failure.invalid }
            let request = try JSONDecoder().decode(Request.self, from: Data(input.utf8))
            guard request.data.count <= 2_048 else { throw Failure.invalid }
            let data = Data(request.data)
            let result: [String: Any]
            switch request.op {
            case "digest":
                guard request.key == nil, request.signature == nil else { throw Failure.invalid }
                result = ["bytes": Array(SHA256.hash(data: data))]
            case "ecdsa":
                guard let rawKey = request.key, rawKey.count == 65, rawKey.first == 4,
                      let rawSignature = request.signature, rawSignature.count == 64 else { throw Failure.invalid }
                let key = try P256.Signing.PublicKey(x963Representation: Data(rawKey))
                let signature = try P256.Signing.ECDSASignature(rawRepresentation: Data(rawSignature))
                result = ["valid": key.isValidSignature(signature, for: data)]
            case "hmac":
                guard let rawKey = request.key, rawKey.count == 43, let secret = String(bytes: rawKey, encoding: .utf8),
                      let decoded = Data(base64URL: secret), decoded.count == 32, decoded.base64URL == secret,
                      let signature = request.signature, signature.count == 32 else { throw Failure.invalid }
                result = ["valid": HMAC<SHA256>.isValidAuthenticationCode(Data(signature), authenticating: data, using: SymmetricKey(data: Data(rawKey)))]
            default: throw Failure.invalid
            }
            return String(decoding: try JSONSerialization.data(withJSONObject: result), as: UTF8.self)
        } catch { return "{\"error\":\"Invalid native runtime verification operation.\"}" }
    }
    private enum Failure: Error { case invalid }
}
