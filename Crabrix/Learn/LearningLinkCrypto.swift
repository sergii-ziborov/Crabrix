import CryptoKit
import Foundation
import Security

/// Keys and envelopes for a learning link (docs/ai-learning/learning-link.md,
/// "Keys"). Everything is derived from the link's 32-byte secret, so the app,
/// the website and the MCP server agree without exchanging anything else; the
/// vectors in `learning-link-vectors.json` pin all three sides.
///
/// - `encryption`: AES-256-GCM key for the snapshot and inbox messages.
/// - `app-write`: the app's bearer token.
/// - `agent-read`: the MCP server's bearer token.
///
/// The website stores only `sha256(hex)` of each token's base64url text and the
/// ciphertext, never the secret or the key.
enum LearningLinkCrypto {
    static let label = "crabrix-learning-link-v1"
    static var salt: Data { Data(label.utf8) }
    static let linkIDByteCount = 18
    static let secretByteCount = 32
    static let nonceByteCount = 12
    static let tagByteCount = 16

    /// What an envelope carries. Part of the AAD, so a snapshot can never be
    /// replayed as an inbox message or the other way round.
    enum Purpose: String, Sendable {
        case snapshot
        case inbox
    }

    enum Failure: Error, Equatable {
        case randomUnavailable
        case invalidSecret
        case invalidEnvelope
        case authenticationFailed
    }

    struct Keys: Sendable {
        let encryption: SymmetricKey
        let writeToken: String
        let readToken: String

        var writeTokenSHA256: String { LearningLinkCrypto.sha256Hex(writeToken) }
        var readTokenSHA256: String { LearningLinkCrypto.sha256Hex(readToken) }
    }

    static func keys(secret: Data) throws -> Keys {
        guard secret.count == secretByteCount else { throw Failure.invalidSecret }
        return Keys(
            encryption: SymmetricKey(data: derive(secret: secret, info: "encryption")),
            writeToken: Base64URL.encode(derive(secret: secret, info: "app-write")),
            readToken: Base64URL.encode(derive(secret: secret, info: "agent-read"))
        )
    }

    /// HKDF-SHA256, salt `crabrix-learning-link-v1`, 32 bytes.
    static func derive(secret: Data, info: String) -> Data {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: secret), salt: salt,
            info: Data(info.utf8), outputByteCount: 32
        ).withUnsafeBytes { Data($0) }
    }

    static func sha256Hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// `crabrix-learning-link-v1|<linkId>|snapshot` or `…|inbox`.
    static func aad(linkID: String, purpose: Purpose) -> Data {
        Data("\(label)|\(linkID)|\(purpose.rawValue)".utf8)
    }

    static func randomBytes(_ count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
            throw Failure.randomUnavailable
        }
        return Data(bytes)
    }

    /// A fresh random nonce per message unless a test pins one.
    static func seal(_ plaintext: Data, key: SymmetricKey, linkID: String, purpose: Purpose,
                     nonce: Data? = nil) throws -> LearningLinkEnvelope {
        let nonceBytes = try nonce ?? randomBytes(nonceByteCount)
        guard nonceBytes.count == nonceByteCount else { throw Failure.invalidEnvelope }
        let box = try AES.GCM.seal(plaintext, using: key, nonce: AES.GCM.Nonce(data: nonceBytes),
                                   authenticating: aad(linkID: linkID, purpose: purpose))
        return LearningLinkEnvelope(v: 1, nonce: Base64URL.encode(nonceBytes),
                                    ct: Base64URL.encode(box.ciphertext + box.tag))
    }

    static func open(_ envelope: LearningLinkEnvelope, key: SymmetricKey, linkID: String,
                     purpose: Purpose) throws -> Data {
        guard envelope.v == 1,
              let nonce = Base64URL.decode(envelope.nonce), nonce.count == nonceByteCount,
              let sealed = Base64URL.decode(envelope.ct), sealed.count >= tagByteCount
        else { throw Failure.invalidEnvelope }
        do {
            let box = try AES.GCM.SealedBox(
                nonce: AES.GCM.Nonce(data: nonce),
                ciphertext: sealed.prefix(sealed.count - tagByteCount),
                tag: sealed.suffix(tagByteCount)
            )
            return try AES.GCM.open(box, using: key, authenticating: aad(linkID: linkID, purpose: purpose))
        } catch {
            throw Failure.authenticationFailed
        }
    }
}

/// `{"v":1,"nonce":"…","ct":"…"}`, nonce and ciphertext‖tag in base64url.
struct LearningLinkEnvelope: Codable, Equatable, Sendable {
    let v: Int
    let nonce: String
    let ct: String

    /// Compact JSON with sorted keys, as uploaded.
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

/// RFC 4648 §5 without padding. Decoding is strict: only the URL-safe
/// alphabet, no padding and no stray bits, so every value has one spelling.
enum Base64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ text: String) -> Data? {
        guard text.count % 4 != 1,
              text.unicodeScalars.allSatisfy(isAlphabet) else { return nil }
        var standard = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        standard += String(repeating: "=", count: (4 - standard.count % 4) % 4)
        guard let data = Data(base64Encoded: standard), encode(data) == text else { return nil }
        return data
    }

    static func isAlphabet(_ scalar: Unicode.Scalar) -> Bool {
        ("A"..."Z").contains(scalar) || ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar)
            || scalar == "-" || scalar == "_"
    }
}
