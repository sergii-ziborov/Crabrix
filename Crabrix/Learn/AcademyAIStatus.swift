import Foundation

/// The run-time pause switch, `GET /api/academy/v1/status.json` (PLAN.md,
/// Phase 7). Checked only when the Learn with AI screen appears: never at
/// launch and never when a lesson opens. Nothing about the learner is sent.
enum AcademyAIStatus: Equatable, Sendable {
    /// Not answered yet: show everything.
    case checking
    case on
    case paused(message: String?)
    /// Offline, timed out or an unexpected answer: show everything with a note.
    case unreachable

    var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }

    /// A missing endpoint (404) means the switch does not exist yet: on.
    static func interpret(data: Data?, response: URLResponse?) -> AcademyAIStatus {
        guard let http = response as? HTTPURLResponse else { return .unreachable }
        if http.statusCode == 404 { return .on }
        guard http.statusCode == 200, let data, data.count <= 64 * 1_024,
              let body = try? JSONDecoder().decode(Body.self, from: data) else { return .unreachable }
        guard body.learnWithAI == "paused" else { return .on }
        let message = body.message?.trimmingCharacters(in: .whitespacesAndNewlines)
        return .paused(message: message.flatMap { $0.isEmpty || $0.count > 280 ? nil : $0 })
    }

    private struct Body: Decodable {
        let learnWithAI: String?
        let message: String?
    }
}

struct AcademyAIStatusClient: Sendable {
    let url: URL
    let session: URLSession

    init(url: URL = AcademyAIFeature.statusURL, session: URLSession = Self.makeSession()) {
        self.url = url
        self.session = session
    }

    /// Ephemeral: no cookies, no cache, no credentials, a 5 second limit.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = 1
        return URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }

    func fetch() async -> AcademyAIStatus {
        #if DEBUG
        if let forced = Self.launchOverride { return forced }
        #endif
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            return AcademyAIStatus.interpret(data: data, response: response)
        } catch {
            return .unreachable
        }
    }

    #if DEBUG
    /// `-CrabrixAIStatus on|paused|offline`, for screenshots and UI tests.
    static var launchOverride: AcademyAIStatus? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-CrabrixAIStatus"), index + 1 < arguments.count else { return nil }
        switch arguments[index + 1] {
        case "on": return .on
        case "paused": return .paused(message: nil)
        case "offline": return .unreachable
        default: return nil
        }
    }
    #endif

    /// The status lives on crabrix.com; a redirect elsewhere is not an answer.
    private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? { nil }
    }
}
