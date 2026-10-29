import Foundation
import CoreFoundation
import CryptoKit

// Unreleased wire foundation. A verified frame is authentication, never a
// permission to compile/run. The client-local governor must authorize it again.
enum PlaygroundRuntimeProtocol {
    static let name = "crabrix-runtime-v1"
    static let envelopeBytes = 2_400, payloadBytes = 768, replayEntries = 512
    static let lifetimeMilliseconds: Int64 = 15_000, clockSkewMilliseconds: Int64 = 5_000
    static let maximumSafeInteger: Int64 = 9_007_199_254_740_991
    static let kinds: Set<String> = ["capabilities", "permission-request", "command", "response"]
    static let operations: Set<String> = ["discover", "grant", "check", "build", "run", "debug", "step", "continue", "stop", "status", "stdout", "stderr", "diagnostics", "locals", "breakpoints", "revoke"]

    struct Failure: LocalizedError { let errorDescription: String?; init(_ message: String) { errorDescription = message } }
    struct Fields {
        let kind: String, room: String, target: String, requestID: String, operation: String
        var revision = "", job = ""
    }
    struct Header: Sendable {
        let kind: String, room: String, sender: String, target: String, requestID: String, operation: String
        let revision: String, job: String, nonce: String, issued: Int64, expires: Int64, payloadHash: String
        var values: [Any] { [name, kind, room, sender, target, requestID, operation, revision, job, nonce, issued, expires, payloadHash] }
        var canonical: Data { get throws { try json(values) } }
        fileprivate init(_ value: Any) throws {
            guard let a = value as? [Any], a.count == 13, a[0] as? String == name,
                  let kind = a[1] as? String, kinds.contains(kind), let room = a[2] as? String, identifier(room, count: 24),
                  let sender = a[3] as? String, hexDigest(sender), let target = a[4] as? String, hexDigest(target) || (kind == "capabilities" && target.isEmpty),
                  let request = a[5] as? String, identifier(request), let operation = a[6] as? String, operations.contains(operation),
                  let revision = a[7] as? String, revision.isEmpty || hexDigest(revision), let job = a[8] as? String, job.isEmpty || identifier(job),
                  let nonce = a[9] as? String, let issued = integer(a[10]), let expires = integer(a[11]), issued >= 0,
                  expires > issued, expires - issued <= lifetimeMilliseconds, let hash = a[12] as? String, hexDigest(hash) else { throw Failure("Invalid runtime header.") }
            guard !(kind == "capabilities" && operation != "discover"), !(kind == "permission-request" && operation != "grant"),
                  !(kind == "command" && ["discover", "grant"].contains(operation)) else { throw Failure("Invalid runtime message kind.") }
            _ = try bytes(nonce, maximum: 32, exact: 32)
            self.kind = kind; self.room = room; self.sender = sender; self.target = target; requestID = request; self.operation = operation
            self.revision = revision; self.job = job; self.nonce = nonce; self.issued = issued; self.expires = expires; payloadHash = hash
        }
        fileprivate func fresh(at now: Int64) throws {
            guard now >= 0, now <= maximumSafeInteger - clockSkewMilliseconds, issued <= now + clockSkewMilliseconds, expires > now else { throw Failure("Runtime message expired or device clocks disagree.") }
        }
    }
    struct VerifiedFrame: Sendable {
        let header: Header, payload: Data, canonicalHeader: Data
        let editAccessProved: Bool
        fileprivate init(header: Header, payload: Data, canonicalHeader: Data, editAccessProved: Bool) { self.header = header; self.payload = payload; self.canonicalHeader = canonicalHeader; self.editAccessProved = editAccessProved }
    }
    struct VerificationContext {
        let room: String
        var target: String?, sender: String?, editCapability: String?
        var requireEditProof = false
    }
    static func verify(_ data: Data, context: VerificationContext, clock: () -> Int64 = milliseconds) throws -> VerifiedFrame {
        guard data.count <= envelopeBytes, let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure("Invalid runtime envelope.") }
        let expected: Set<String> = ["v", "key", "header", "payload", "signature"]
        let keys = Set(value.keys)
        guard keys == expected || keys == expected.union(["editProof"]), value["v"].flatMap(integer) == 1, let headerValue = value["header"],
              let key = value["key"] as? String, let payload = value["payload"] as? String, let signature = value["signature"] as? String,
              !keys.contains("editProof") || value["editProof"] is String else { throw Failure("Invalid runtime envelope fields.") }
        let header = try Header(headerValue)
        try header.fresh(at: clock())
        guard header.room == context.room, context.target == nil || header.target == context.target,
              context.sender == nil || header.sender == context.sender else { throw Failure("Runtime room or participant does not match.") }
        let rawKey = try bytes(key, maximum: 65, exact: 65), rawSignature = try bytes(signature, maximum: 64, exact: 64)
        let payloadData = try bytes(payload, maximum: payloadBytes)
        guard rawKey.first == 4, digest(rawKey) == header.sender, digest(payloadData) == header.payloadHash else { throw Failure("Runtime identity or payload digest does not match.") }
        let canonical = try header.canonical
        let publicKey = try P256.Signing.PublicKey(x963Representation: rawKey)
        guard publicKey.isValidSignature(try P256.Signing.ECDSASignature(rawRepresentation: rawSignature), for: canonical) else { throw Failure("Invalid runtime signature.") }
        if context.requireEditProof || value["editProof"] != nil {
            guard let capability = context.editCapability, let encodedProof = value["editProof"] as? String else { throw Failure("Runtime edit access was not proved.") }
            let proof = try bytes(encodedProof, maximum: 32, exact: 32)
            guard HMAC<SHA256>.isValidAuthenticationCode(proof, authenticating: proofInput(canonical, signature: signature), using: try editKey(capability)) else { throw Failure("Runtime edit access was not proved.") }
        }
        try validatePayload(payloadData)
        try header.fresh(at: clock())
        return VerifiedFrame(header: header, payload: payloadData, canonicalHeader: canonical, editAccessProved: value["editProof"] != nil)
    }
    static func milliseconds() -> Int64 { Int64(Date().timeIntervalSince1970 * 1_000) }
    fileprivate static func json(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.withoutEscapingSlashes, .fragmentsAllowed]) }
    fileprivate static func validatePayload(_ data: Data) throws {
        guard data.count <= payloadBytes, String(data: data, encoding: .utf8) != nil else { throw Failure("Invalid runtime payload JSON or page budget.") }
        _ = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
    }
    fileprivate static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    fileprivate static func integer(_ value: Any) -> Int64? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite,
              n.doubleValue.rounded() == n.doubleValue, abs(n.doubleValue) <= Double(maximumSafeInteger) else { return nil }
        return n.int64Value
    }
    fileprivate static func identifier(_ value: String, count: Int? = nil) -> Bool {
        let bytes = value.utf8
        return (count.map { bytes.count == $0 } ?? (16...64).contains(bytes.count)) && bytes.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }
    }
    fileprivate static func hexDigest(_ value: String) -> Bool { value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }
    fileprivate static func bytes(_ value: String, maximum: Int, exact: Int? = nil) throws -> Data {
        guard value.utf8.count <= (maximum * 4 + 2) / 3, let data = Data(base64URL: value), data.count <= maximum,
              exact == nil || data.count == exact, data.base64URL == value else { throw Failure("Invalid runtime encoding.") }
        return data
    }
    fileprivate static func editKey(_ capability: String) throws -> SymmetricKey {
        _ = try bytes(capability, maximum: 32, exact: 32)
        return SymmetricKey(data: Data(capability.utf8))
    }
    fileprivate static func proofInput(_ header: Data, signature: String) -> Data { Data("crabrix-runtime-edit-proof-v1\n".utf8) + header + Data(("\n" + signature).utf8) }
}

@MainActor
final class PlaygroundRuntimeSigner {
    private var privateKey: P256.Signing.PrivateKey?
    let key: String, fingerprint: String
    init() {
        let signing = P256.Signing.PrivateKey(); privateKey = signing
        let raw = signing.publicKey.x963Representation
        key = raw.base64URL; fingerprint = PlaygroundRuntimeProtocol.digest(raw)
    }
    func destroy() { privateKey = nil }
    func sign(_ fields: PlaygroundRuntimeProtocol.Fields, payload: Data, editCapability: String? = nil,
              now: Int64 = PlaygroundRuntimeProtocol.milliseconds(), lifetime: Int64 = PlaygroundRuntimeProtocol.lifetimeMilliseconds) throws -> Data {
        typealias Wire = PlaygroundRuntimeProtocol
        guard let privateKey else { throw Wire.Failure("Runtime signer is closed.") }
        try Wire.validatePayload(payload)
        guard lifetime > 0, lifetime <= Wire.lifetimeMilliseconds, now >= 0, now <= Wire.maximumSafeInteger - lifetime else { throw Wire.Failure("Invalid runtime lifetime.") }
        let nonce = Data(SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }).base64URL
        let header = try Wire.Header([Wire.name, fields.kind, fields.room, fingerprint, fields.target, fields.requestID, fields.operation, fields.revision, fields.job, nonce, now, now + lifetime, Wire.digest(payload)])
        let canonical = try header.canonical, signature = try privateKey.signature(for: canonical).rawRepresentation.base64URL
        var envelope: [String: Any] = ["v": 1, "key": key, "header": header.values, "payload": payload.base64URL, "signature": signature]
        if let editCapability { envelope["editProof"] = Data(HMAC<SHA256>.authenticationCode(for: Wire.proofInput(canonical, signature: signature), using: try Wire.editKey(editCapability))).base64URL }
        let data = try Wire.json(envelope)
        guard data.count <= Wire.envelopeBytes else { throw Wire.Failure("Runtime message exceeds the transient presence budget.") }
        return data
    }
}

@MainActor
final class PlaygroundRuntimeReplayWindow {
    private var seen: [String: (header: Data, expires: Int64)] = [:]
    enum Disposition { case new, duplicate }
    func consume(_ frame: PlaygroundRuntimeProtocol.VerifiedFrame, now: Int64 = PlaygroundRuntimeProtocol.milliseconds()) throws -> Disposition {
        typealias Wire = PlaygroundRuntimeProtocol
        try frame.header.fresh(at: now)
        seen = seen.filter { $0.value.expires > now }
        let key = frame.header.sender + ":" + frame.header.nonce
        if let previous = seen[key] {
            guard previous.header == frame.canonicalHeader else { throw Wire.Failure("Runtime nonce was reused for a different message.") }
            return .duplicate
        }
        guard seen.count < Wire.replayEntries else { throw Wire.Failure("Runtime replay window is full.") }
        seen[key] = (frame.canonicalHeader, frame.header.expires)
        return .new
    }
}
