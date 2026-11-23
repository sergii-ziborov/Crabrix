import Foundation

/// The only things Learn with AI stores: two `crabrix.ai.*` flags in the
/// standard defaults. No progress key is read or written here, and nothing is
/// sent anywhere.
struct AILearningFlags {
    /// When the learner first copied a setup step or a prompt (seconds since 1970).
    static let firstCopyKey = "crabrix.ai.firstCopyAt.v1"
    /// `answered` or `dismissed`: the feedback card never returns after either.
    static let feedbackKey = "crabrix.ai.feedback.v1"
    static let keyPrefix = "crabrix.ai."

    enum FeedbackOutcome: String {
        case answered
        case dismissed
    }

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var firstCopyAt: Date? {
        let value = defaults.double(forKey: Self.firstCopyKey)
        return value > 0 ? Date(timeIntervalSince1970: value) : nil
    }

    /// The first meaningful interaction. Later copies change nothing.
    func recordCopy(now: Date = Date()) {
        guard firstCopyAt == nil else { return }
        defaults.set(now.timeIntervalSince1970, forKey: Self.firstCopyKey)
    }

    var feedbackOutcome: FeedbackOutcome? {
        defaults.string(forKey: Self.feedbackKey).flatMap(FeedbackOutcome.init(rawValue:))
    }

    func finishFeedback(_ outcome: FeedbackOutcome) {
        guard feedbackOutcome == nil else { return }
        defaults.set(outcome.rawValue, forKey: Self.feedbackKey)
    }

    /// Shown once: after a copy recorded earlier, on a later visit to the
    /// screen or when the app returns to the foreground, until it is answered
    /// or dismissed.
    var shouldOfferFeedback: Bool {
        firstCopyAt != nil && feedbackOutcome == nil
    }
}

/// "Did learning Rust with your AI agent help?" goes into a mail draft the
/// learner reads and sends themselves, like a problem report.
enum AILearningFeedback {
    enum Answer: String, CaseIterable, Identifiable, Sendable {
        case yes = "Yes"
        case partly = "Partly"
        case notWorking = "I couldn’t get it working"

        var id: String { rawValue }
    }

    static let question = "Did learning Rust with your AI agent help?"

    /// Same subject as the website's card: `Crabrix — Learning with AI: Yes`.
    static func subject(_ answer: Answer) -> String {
        "Crabrix — Learning with AI: \(answer.rawValue)"
    }

    static func body(_ answer: Answer, note: String, producer: AILearningState.Producer) -> String {
        var sections = ["\(question)\n\(answer.rawValue)"]
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { sections.append(note) }
        sections.append("Crabrix \(producer.version) (build \(producer.build)), iOS app")
        return sections.joined(separator: "\n\n") + "\n"
    }

    static func mailURL(_ answer: Answer, note: String, producer: AILearningState.Producer,
                        to address: String = CrabrixLinks.supportEmail) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject(answer)),
            URLQueryItem(name: "body", value: body(answer, note: note, producer: producer)),
        ]
        // As in ProblemReport: Mail reads a raw + in a query as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }
}
