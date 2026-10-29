import Foundation

struct PlaygroundRuntimePolicyContext: Codable, Sendable {
    struct Job: Codable, Sendable { let id: String; let grant: String; let revision: String; let operation: String; let state: String }
    let room: String, target: String, scope: String, revision: String, editCapability: String
    let expires: Int64
    var foreground: Bool, connected: Bool, editConfirmed: Bool, ready: Bool, busy: Bool
    var jobs: [Job] = []
}
struct PlaygroundRuntimePolicyReply: Decodable, Sendable {
    struct Grant: Decodable, Sendable { let id: String; let controller: String; let name: String; let operations: [String]; let expires: Int64 }
    struct Request: Decodable, Sendable { let controller: String; let requestID: String; let name: String; let operations: [String]; let expires: Int64 }
    struct Revoked: Decodable, Sendable { let grant: String; let reason: String }
    struct Admission: Decodable, Sendable { let kind: String; let requestID: String; let reason: String? }
    struct Verified: Decodable, Sendable { let sender: String; let requestID: String; let operation: String; let revision: String; let job: String; let payloadJSON: String }
    let grant: Grant?
    let requests: [Request]
    let revoked: [Revoked]
    let admission: Admission?
    let verified: Verified?
    let error: String?
}

@MainActor
final class PlaygroundRuntimePolicyCall {
    private var continuation: CheckedContinuation<PlaygroundRuntimePolicyReply, any Error>?
    private var result: Swift.Result<PlaygroundRuntimePolicyReply, any Error>?
    var timeout: Task<Void, Never>?
    func attach(_ continuation: CheckedContinuation<PlaygroundRuntimePolicyReply, any Error>) {
        if let result { continuation.resume(with: result) }
        else { self.continuation = continuation }
    }
    func finish(_ result: Swift.Result<PlaygroundRuntimePolicyReply, any Error>) {
        guard self.result == nil else { return }
        self.result = result; timeout?.cancel(); timeout = nil
        continuation?.resume(with: result); continuation = nil
    }
    deinit { timeout?.cancel() }
}
