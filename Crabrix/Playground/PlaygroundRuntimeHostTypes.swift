import Foundation

struct PlaygroundRuntimeHostReply: Decodable, Sendable {
    struct Fields: Decodable, Sendable { let kind: String; let room: String; let target: String; let requestID: String; let operation: String; let revision: String?; let job: String? }
    struct Publication: Decodable, Sendable { let fields: Fields; let payloadJSON: String; let proof: Bool }
    struct Effect: Decodable, Sendable { let type: String; let job: String; let revision: String; let operation: String; let mode: String?; let points: [[Int]]? }
    struct Job: Decodable, Sendable { let id: String; let revision: String; let operation: String; let state: String; let stage: String }
    struct SharedOutput: Decodable, Sendable { let id: String; let sender: String; let name: String; let revision: String; let stdout: String; let stderr: String; let truncated: Bool; let succeeded: Bool; let exitCode: Int? }
    let sharedOutput: SharedOutput?
    let grant: PlaygroundRuntimePolicyReply.Grant?
    let requests: [PlaygroundRuntimePolicyReply.Request]?
    let jobs: [Job]?
    let publications: [Publication]?
    let effects: [Effect]?
    let error: String?
}

