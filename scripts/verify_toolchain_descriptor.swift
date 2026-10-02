import CryptoKit
import Foundation

private struct Envelope: Decodable {
    let keyID: String
    let payloadBase64: String
    let signatureBase64: String
}

guard CommandLine.arguments.count == 4 else {
    fputs("usage: swift verify_toolchain_descriptor.swift descriptor.json keyID publicKeyBase64\n", stderr)
    exit(2)
}

do {
    let descriptor = URL(fileURLWithPath: CommandLine.arguments[1])
    let envelope = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: descriptor))
    guard envelope.keyID == CommandLine.arguments[2],
          let publicBytes = Data(base64Encoded: CommandLine.arguments[3]),
          let payload = Data(base64Encoded: envelope.payloadBase64),
          let signature = Data(base64Encoded: envelope.signatureBase64)
    else { throw CocoaError(.fileReadCorruptFile) }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicBytes)
    var signed = Data("Crabrix.ToolchainDescriptor.v1\n".utf8)
    signed.append(payload)
    guard key.isValidSignature(signature, for: signed)
    else { throw CocoaError(.fileReadCorruptFile) }
    FileHandle.standardOutput.write(payload)
} catch {
    fputs("Toolchain descriptor signature verification failed: \(error)\n", stderr)
    exit(1)
}
