import Foundation
import CryptoKit

struct PlaygroundEncryptedPacket: Codable, Sendable {
    let iv: String
    let data: String
}
enum PlaygroundEncryption {
    static let authentication = Data("crabrix-playground-v1".utf8)
    static func newSecret() -> String { Data(SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }).base64URL }
    static func seal(_ bytes: Data, secret: String) throws -> PlaygroundEncryptedPacket {
        let box = try AES.GCM.seal(bytes, using: key(secret), authenticating: authentication)
        return PlaygroundEncryptedPacket(iv: box.nonce.withUnsafeBytes { Data($0).base64URL }, data: (box.ciphertext + box.tag).base64URL)
    }
    static func open(_ packet: PlaygroundEncryptedPacket, secret: String, maximum: Int = 262144) throws -> Data {
        guard packet.data.count <= (maximum + 16) * 4 / 3 + 4, let iv = Data(base64URL: packet.iv), iv.count == 12,
              let data = Data(base64URL: packet.data), data.count >= 16, data.count <= maximum + 16 else { throw PlaygroundFailure("Invalid encrypted Playground message.") }
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: iv), ciphertext: data.dropLast(16), tag: data.suffix(16))
        let plain = try AES.GCM.open(box, using: key(secret), authenticating: authentication)
        guard plain.count <= maximum else { throw PlaygroundFailure("Decoded Playground message is too large.") }
        return plain
    }
    private static func key(_ secret: String) throws -> SymmetricKey {
        guard secret.count == 43, let data = Data(base64URL: secret), data.count == 32 else { throw PlaygroundFailure("Invalid Playground encryption key.") }
        return SymmetricKey(data: data)
    }
}
extension Data {
    var base64URL: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    init?(base64URL: String) {
        guard base64URL.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else { return nil }
        var value = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        value += String(repeating: "=", count: (4 - value.count % 4) % 4)
        self.init(base64Encoded: value)
    }
}
