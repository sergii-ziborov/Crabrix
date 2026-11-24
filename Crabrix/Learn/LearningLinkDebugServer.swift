#if DEBUG
import Foundation

/// Debug builds only: `-CrabrixLearningLinkStub` answers the learning-link API
/// in process, so UI tests and screenshots never reach crabrix.com. The link
/// lives in memory and in a throwaway defaults suite; official progress is
/// still read (never written) from the standard defaults.
///
/// After the first inbox request the stub holds two tutor messages, as an
/// agent would send them through `crabrix_assign_lessons` and
/// `crabrix_set_focus`, encrypted with the link's own key.
enum LearningLinkDebugServer {
    static let argument = "-CrabrixLearningLinkStub"
    static let suiteName = "CrabrixLearningLinkStub"

    @MainActor
    static func controllerForLaunchArguments() -> LearningLinkController? {
        guard ProcessInfo.processInfo.arguments.contains(argument),
              let defaults = UserDefaults(suiteName: suiteName) else { return nil }
        defaults.removePersistentDomain(forName: suiteName)
        let secrets = InMemoryLearningLinkSecrets()
        LearningLinkDebugProtocol.reset(secrets: secrets)
        return LearningLinkController(
            defaults: defaults,
            progressDefaults: .standard,
            secrets: secrets,
            api: LearningLinkAPI(session: LearningLinkAPI.makeSession(protocolClasses: [LearningLinkDebugProtocol.self])),
            debounce: .seconds(1),
            triggerDelay: .milliseconds(300)
        )
    }
}

final class LearningLinkDebugProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var secrets: (any LearningLinkSecretStore)?
    nonisolated(unsafe) private static var snapshotAt: Date?
    nonisolated(unsafe) private static var inbox: [(id: String, plaintext: String)] = []
    nonisolated(unsafe) private static var seeded = false

    static func reset(secrets: any LearningLinkSecretStore) {
        lock.withLock {
            self.secrets = secrets
            snapshotAt = nil
            inbox = []
            seeded = false
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.path.hasPrefix("/api/learn-links/v1") == true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let (status, body) = Self.answer(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json", "Cache-Control": "no-store"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func answer(_ request: URLRequest) -> (Int, Data) {
        lock.withLock {
            let parts = (request.url?.path ?? "").split(separator: "/").dropFirst(3).map(String.init)
            let method = request.httpMethod ?? "GET"
            guard let credentials = try? secrets?.load() else {
                return method == "POST" && parts.isEmpty ? (201, Data("{}".utf8)) : (404, Data())
            }
            guard request.value(forHTTPHeaderField: "Authorization") == "Bearer \((try? credentials.keys())?.writeToken ?? "")"
                    || (method == "POST" && parts.isEmpty) else { return (404, Data()) }
            switch (method, parts.count, parts.last) {
            case ("POST", 0, _):
                return (201, Data("{}".utf8))
            case ("PUT", 2, "snapshot"?):
                snapshotAt = Date()
                return (204, Data())
            case ("GET", 2, "status"?):
                let updated = snapshotAt.map(AILearningState.rfc3339) ?? ""
                let read = AILearningState.rfc3339(Date().addingTimeInterval(-180))
                return (200, Data(#"{"updatedAt":"\#(updated)","lastAgentReadAt":"\#(read)","pendingInbox":\#(inbox.count)}"#.utf8))
            case ("GET", 2, "inbox"?):
                if !seeded {
                    seeded = true
                    inbox = sampleMessages
                }
                guard let keys = try? credentials.keys() else { return (500, Data()) }
                let items: [[String: Any]] = inbox.compactMap { message in
                    guard let envelope = try? LearningLinkCrypto.seal(Data(message.plaintext.utf8), key: keys.encryption,
                                                                      linkID: credentials.linkID, purpose: .inbox)
                    else { return nil }
                    return ["id": message.id, "createdAt": AILearningState.rfc3339(Date()),
                            "envelope": ["v": envelope.v, "nonce": envelope.nonce, "ct": envelope.ct]]
                }
                return (200, (try? JSONSerialization.data(withJSONObject: ["items": items])) ?? Data())
            case ("DELETE", 3, let id?) where parts[1] == "inbox":
                inbox.removeAll { $0.id == id }
                return (204, Data())
            case ("DELETE", 1, _):
                try? secrets?.remove()
                return (204, Data())
            default:
                return (404, Data())
            }
        }
    }

    private static var sampleMessages: [(id: String, plaintext: String)] {
        let now = AILearningState.rfc3339(Date())
        return [
            ("m1", #"""
            {"format":"crabrix.tutor-message","schemaVersion":1,"createdAt":"\#(now)","kind":"focus",
             "pathId":"rust-for-nodejs","goal":"Build a small HTTP service in Rust",
             "concepts":["functions","loops","ownership"],"agent":"Claude"}
            """#),
            ("m2", #"""
            {"format":"crabrix.tutor-message","schemaVersion":1,"createdAt":"\#(now)","kind":"assign",
             "lessons":[{"courseId":"basics","lessonId":"functions","reason":"You asked how values get into a function: start here."},
                        {"courseId":"basics","lessonId":"loops","reason":"Practise for and while before iterators."}],
             "note":"Two short lessons before we start ownership.","agent":"Claude"}
            """#),
        ]
    }
}
#endif
