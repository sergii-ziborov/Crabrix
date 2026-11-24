import Foundation
import SwiftUI
import UIKit

/// The app side of a learning link (docs/ai-learning/learning-link.md, "App").
///
/// Nothing happens until the learner connects. While connected it uploads an
/// encrypted snapshot after progress changes (debounced 5 s), when the app
/// returns to the foreground and when Learn appears, and reads the tutor inbox
/// at most once per 30 s. It never runs at launch or when a lesson opens, it
/// never writes a progress store, and failures only change a status line.
///
/// Stores: the Keychain item (id and secret), `crabrix.ai.learningLink.v1`
/// (timestamps), `crabrix.ai.recentLessons.v1` and `crabrix.ai.tutorPlan.v1`.
@MainActor
final class LearningLinkController: ObservableObject {
    static let shared = LearningLinkController.makeShared()

    enum Activity: Equatable {
        case connecting
        case syncing
        case disconnecting
    }

    /// `nil` while not connected.
    @Published private(set) var state: LearningLinkLocalState?
    /// The personal MCP URL, read from the Keychain when the screen shows it.
    @Published private(set) var url: URL?
    @Published private(set) var activity: Activity?
    /// The last failure, in words. Empty after a success.
    @Published private(set) var statusLine: String?
    @Published private(set) var availability: LearningLinkAvailability = .unknown
    @Published private(set) var tutorPlan: TutorPlan
    /// A one-off message after Disconnect.
    @Published var notice: String?

    var isConnected: Bool { state != nil }
    var isPaused: Bool { availability == .paused }

    /// Where `crabrix.ai.*` keys are written.
    let defaults: UserDefaults
    /// Where the official progress stores are read (never written).
    let progressDefaults: UserDefaults
    private let secrets: any LearningLinkSecretStore
    private let pendingDeletions: any LearningLinkPendingDeletionStore
    private let api: LearningLinkAPI
    private let now: @Sendable () -> Date
    private let app: String
    private let device: String
    private let debounce: Duration
    private let inboxInterval: TimeInterval
    private let triggerDelay: Duration
    /// Where the personal URL points: crabrix.com except in a Debug loopback check.
    private let mcpBase: String
    /// An unchanged snapshot is uploaded again after this long, so the website's
    /// 90-day expiry only removes links that are really unused.
    private let refreshInterval: TimeInterval = 12 * 3_600

    private var repository: InstalledCourseRepository?
    private var cachedCatalog: LearningLinkCatalog?
    private var fixedCatalog: LearningLinkCatalog?
    private var credentials: LearningLinkCredentials?
    private var debounceTask: Task<Void, Never>?
    private var triggerTask: Task<Void, Never>?
    private var syncing = false
    private var pendingSync = false
    private var pendingForce = false
    private var fetchingInbox = false
    private var lastInboxFetch: Date?
    private var wasInBackground = false
    /// After a 429: no request before this moment.
    private var retryNotBefore: Date?
    /// Paused by a 503 rather than by `status.json`: retried after a foreground.
    private var pausedByServer = false

    init(
        defaults: UserDefaults = .standard,
        progressDefaults: UserDefaults? = nil,
        secrets: any LearningLinkSecretStore = LearningLinkKeychain(),
        pendingDeletions: any LearningLinkPendingDeletionStore = LearningLinkPendingDeletionKeychain(),
        api: LearningLinkAPI = LearningLinkAPI(),
        now: @escaping @Sendable () -> Date = { Date() },
        app: String = AILearningState.Producer.current.appVersion,
        device: String? = nil,
        debounce: Duration = .seconds(5),
        inboxInterval: TimeInterval = 30,
        triggerDelay: Duration = .milliseconds(1_500),
        mcpBase: String = LearningLinkCredentials.mcpBase
    ) {
        self.mcpBase = mcpBase
        self.defaults = defaults
        self.progressDefaults = progressDefaults ?? defaults
        self.secrets = secrets
        self.pendingDeletions = pendingDeletions
        self.api = api
        self.now = now
        self.app = app
        self.device = device ?? (UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")
        self.debounce = debounce
        self.inboxInterval = inboxInterval
        self.triggerDelay = triggerDelay
        state = LearningLinkLocalState.load(defaults)
        tutorPlan = TutorPlanStore(defaults: defaults).load()
    }

    private static func makeShared() -> LearningLinkController {
        #if DEBUG
        if let stub = LearningLinkDebugServer.controllerForLaunchArguments() { return stub }
        if let origin = LearningLinkAPI.loopbackOrigin("-CrabrixLearningLinkOrigin") {
            let mcp = LearningLinkAPI.loopbackOrigin("-CrabrixLearningLinkMCPOrigin") ?? origin
            return LearningLinkController(api: LearningLinkAPI(baseURL: URL(string: origin + "/api/learn-links/v1/")!),
                                          triggerDelay: .milliseconds(300), mcpBase: mcp + "/mcp/learn/")
        }
        #endif
        return LearningLinkController()
    }

    // MARK: Inputs

    /// The installed courses, handed over whenever the repository changes.
    /// The catalog is built only when a link needs it.
    func updateRepository(_ repository: InstalledCourseRepository?) {
        self.repository = repository
        cachedCatalog = nil
    }

    /// Tests use a fixed catalog instead of a repository.
    func useCatalog(_ catalog: LearningLinkCatalog) {
        fixedCatalog = catalog
    }

    var catalog: LearningLinkCatalog? {
        if let fixedCatalog { return fixedCatalog }
        guard let repository else { return nil }
        if let cachedCatalog { return cachedCatalog }
        let built = LearningLinkCatalog(repository: repository)
        cachedCatalog = built
        return built
    }

    /// What the next upload would contain, from the existing stores only.
    func snapshotInput() -> LearningLinkSnapshot.Input? {
        guard let catalog else { return nil }
        let mastery = progressDefaults === UserDefaults.standard
            ? TopicMasteryStore.shared.records
            : TopicMasteryStore(defaults: progressDefaults).records
        return LearningLinkSnapshot.Input(
            completed: Set(progressDefaults.stringArray(forKey: LearningProgressKeys.completed) ?? []),
            credited: LessonCredits.decode(progressDefaults.object(forKey: LearningProgressKeys.credited)),
            catalog: catalog,
            mastery: mastery,
            recentLessons: RecentLessonsStore(defaults: defaults).load(),
            tutorPlan: tutorPlan,
            now: now(),
            app: app,
            device: device
        )
    }

    // MARK: Triggers (cheap no-ops while not connected)

    func progressDidChange() {
        guard state != nil else { return }
        scheduleSync()
    }

    /// Recorded only while connected; the app keeps no other lesson history.
    func lessonDidOpen(lessonID: String, repository: InstalledCourseRepository?) {
        guard state != nil, let course = repository?.course(containing: lessonID) else { return }
        if RecentLessonsStore(defaults: defaults).record(AILearningLessonRef(courseId: course.id, lessonId: lessonID)) {
            scheduleSync()
        }
    }

    /// Only a return from the background counts: the first activation at
    /// launch does nothing.
    func scenePhaseChanged(_ phase: ScenePhase) {
        if phase == .background {
            wasInBackground = true
            return
        }
        guard phase == .active, wasInBackground else { return }
        wasInBackground = false
        Task { await retryPendingDeletion() }
        if pausedByServer {
            pausedByServer = false
            availability = .unknown
        }
        guard state != nil else { return }
        triggerSyncAndInbox()
    }

    func learnDidAppear() {
        Task { await retryPendingDeletion() }
        guard state != nil else { return }
        triggerSyncAndInbox()
    }

    /// `status.json` `learningLinks`.
    func applyAvailability(_ availability: LearningLinkAvailability) {
        switch availability {
        case .paused:
            self.availability = .paused
            pausedByServer = false
            debounceTask?.cancel()
        case .on:
            self.availability = .on
            pausedByServer = false
        case .unknown:
            break
        }
    }

    func scheduleSync() {
        debounceTask?.cancel()
        let delay = debounce
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.runSync(force: false)
        }
    }

    private func triggerSyncAndInbox() {
        triggerTask?.cancel()
        let delay = triggerDelay
        triggerTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            await self.runSync(force: false)
            await self.fetchInbox()
        }
    }

    // MARK: Connect

    /// Creates the link, then uploads the first snapshot. On any failure
    /// nothing is left behind: not on the website, not in the Keychain.
    @discardableResult
    func connect() async -> Bool {
        guard state == nil, activity == nil, availability != .paused else { return false }
        guard let input = snapshotInput() else {
            statusLine = "Crabrix is still preparing your courses. Try again in a moment."
            return false
        }
        activity = .connecting
        defer { activity = nil }
        statusLine = nil
        notice = nil

        // A link left in the Keychain by an earlier installation goes first.
        if let orphan = try? secrets.load() {
            try? await api.deleteLink(orphan)
            try? secrets.remove()
        }
        var created: LearningLinkCredentials?
        do {
            var fresh = try LearningLinkCredentials.generate()
            try secrets.save(fresh)
            do {
                try await api.create(fresh)
            } catch LearningLinkAPI.Failure.conflict {
                // The id is taken (practically never with 18 random bytes): once more.
                fresh = try LearningLinkCredentials.generate()
                try secrets.save(fresh)
                try await api.create(fresh)
            }
            created = fresh
            let plaintext = try LearningLinkSnapshot.fittingPlaintext(input)
            let envelope = try LearningLinkSnapshot.envelope(plaintext, keys: fresh.keys(), linkID: fresh.linkID)
            try await api.putSnapshot(envelope, credentials: fresh)
            var connected = LearningLinkLocalState(connectedAt: now())
            connected.lastSyncedAt = now()
            connected.lastSnapshotDigest = try? LearningLinkSnapshot.contentDigest(input)
            connected.save(defaults)
            state = connected
            credentials = fresh
            url = fresh.url(mcpBase: mcpBase)
            lastInboxFetch = nil
            if availability == .unknown { availability = .on }
            return true
        } catch {
            if let created { try? await api.deleteLink(created) }
            try? secrets.remove()
            statusLine = Self.describe(error, connecting: true)
            if case LearningLinkAPI.Failure.paused? = error as? LearningLinkAPI.Failure { markPausedByServer() }
            return false
        }
    }

    /// Reads the URL for display. A missing Keychain item (a restored backup on
    /// another device) means the link is gone from here.
    func prepareForDisplay() {
        _ = loadCredentials()
    }

    private func loadCredentials() -> LearningLinkCredentials? {
        if let credentials { return credentials }
        guard state != nil else { return nil }
        do {
            guard let loaded = try secrets.load() else {
                forgetLocally()
                return nil
            }
            credentials = loaded
            url = loaded.url(mcpBase: mcpBase)
            return loaded
        } catch {
            // Locked before first unlock, for example: try again later.
            return nil
        }
    }

    // MARK: Sync

    func syncNow() async {
        await runSync(force: true)
        await refreshStatus()
    }

    func runSync(force: Bool) async {
        if syncing {
            pendingSync = true
            pendingForce = pendingForce || force
            return
        }
        syncing = true
        var forced = force
        repeat {
            pendingSync = false
            await uploadOnce(force: forced)
            forced = pendingForce
            pendingForce = false
        } while pendingSync && state != nil
        syncing = false
    }

    private func uploadOnce(force: Bool) async {
        guard state != nil, availability != .paused, mayCallServer(),
              let input = snapshotInput(), let credentials = loadCredentials() else { return }
        let digest = try? LearningLinkSnapshot.contentDigest(input)
        if !force, let digest, digest == state?.lastSnapshotDigest,
           let last = state?.lastSyncedAt, now().timeIntervalSince(last) < refreshInterval {
            return
        }
        activity = activity ?? .syncing
        defer { if activity == .syncing { activity = nil } }
        do {
            let plaintext = try LearningLinkSnapshot.fittingPlaintext(input)
            let envelope = try LearningLinkSnapshot.envelope(plaintext, keys: credentials.keys(), linkID: credentials.linkID)
            try await api.putSnapshot(envelope, credentials: credentials)
            guard self.credentials == credentials, var current = state else { return }
            current.lastSyncedAt = now()
            current.lastSnapshotDigest = digest
            update(current)
            statusLine = nil
        } catch {
            handle(error)
        }
    }

    /// "Last used by your agent" and the pending inbox count.
    func refreshStatus() async {
        guard state != nil, availability != .paused, mayCallServer(),
              let credentials = loadCredentials() else { return }
        do {
            let status = try await api.status(credentials)
            guard self.credentials == credentials, var current = state else { return }
            current.lastAgentReadAt = status.lastAgentReadAt
            current.serverUpdatedAt = status.updatedAt
            current.pendingInbox = status.pendingInbox
            update(current)
            if availability == .unknown { availability = .on }
        } catch {
            handle(error)
        }
    }

    // MARK: Inbox

    /// Decrypts and validates every pending message, merges the valid ones
    /// into `crabrix.ai.tutorPlan.v1`, then acknowledges all of them (an invalid
    /// message never becomes valid). Nothing here touches progress.
    func fetchInbox(force: Bool = false) async {
        guard state != nil, availability != .paused, !fetchingInbox, mayCallServer() else { return }
        if !force, let last = lastInboxFetch, now().timeIntervalSince(last) < inboxInterval { return }
        guard let catalog, let credentials = loadCredentials(), let keys = try? credentials.keys() else { return }
        fetchingInbox = true
        defer { fetchingInbox = false }
        lastInboxFetch = now()

        let items: [LearningLinkAPI.InboxItem]
        do {
            items = try await api.inbox(credentials)
        } catch {
            handle(error)
            return
        }
        guard self.credentials == credentials, state != nil else { return }
        var plan = tutorPlan
        var changed = false
        for item in items {
            guard let plaintext = try? LearningLinkCrypto.open(item.envelope, key: keys.encryption,
                                                               linkID: credentials.linkID, purpose: .inbox),
                  case let .success(message) = TutorMessageValidator.validate(plaintext, catalog: catalog, now: now())
            else { continue }
            if plan.apply(message, messageID: item.id) { changed = true }
        }
        if changed {
            tutorPlan = plan
            TutorPlanStore(defaults: defaults).save(plan)
        }
        for item in items {
            guard self.credentials == credentials else { return }
            try? await api.acknowledge(item.id, credentials: credentials)
        }
        // The snapshot echoes the plan, so the agent sees it was accepted.
        if changed { scheduleSync() }
    }

    func dismissAssignment(_ lessonID: String) {
        tutorPlan.dismiss(lessonID: lessonID)
        TutorPlanStore(defaults: defaults).save(tutorPlan)
        if state != nil { scheduleSync() }
    }

    func clearFocus() {
        tutorPlan.clearFocus()
        TutorPlanStore(defaults: defaults).save(tutorPlan)
        if state != nil { scheduleSync() }
    }

    // MARK: Disconnect

    /// `DELETE` on the website, then everything local. When the website cannot
    /// be reached the local copy goes anyway and the learner is told the
    /// encrypted copy there expires after 90 days without use.
    func disconnect() async {
        guard activity != .disconnecting else { return }
        debounceTask?.cancel()
        triggerTask?.cancel()
        activity = .disconnecting
        defer { activity = nil }
        let link = credentials ?? (try? secrets.load())
        var deletedOnServer = true
        if let link {
            do {
                try await api.deleteLink(link)
            } catch LearningLinkAPI.Failure.notFound {
                deletedOnServer = true
            } catch {
                deletedOnServer = false
                // Keep only what deleting needs, so the copy on crabrix.com goes as soon as it is reachable.
                try? pendingDeletions.save(.init(linkID: link.linkID, writeToken: link.keys().writeToken))
            }
        }
        forgetLocally()
        notice = deletedOnServer
            ? "Disconnected. Your agent can no longer read your progress, and the encrypted copy on crabrix.com is deleted. Remove the connector from your agent too."
            : "Disconnected on this device. crabrix.com could not be reached, so Crabrix deletes the encrypted copy there the next time you are online. Remove the connector from your agent too."
    }

    /// Finishes a Disconnect that could not reach crabrix.com. Gone already
    /// (404) counts as done; any other failure keeps it for the next try.
    func retryPendingDeletion() async {
        guard let pending = pendingDeletions.load() else { return }
        do {
            try await api.deleteLink(linkID: pending.linkID, writeToken: pending.writeToken)
            pendingDeletions.remove()
        } catch LearningLinkAPI.Failure.notFound {
            pendingDeletions.remove()
        } catch {}
    }

    private func forgetLocally() {
        try? secrets.remove()
        LearningLinkLocalState.clear(defaults)
        RecentLessonsStore(defaults: defaults).clear()
        TutorPlanStore(defaults: defaults).clear()
        state = nil
        credentials = nil
        url = nil
        tutorPlan = .empty
        statusLine = nil
        retryNotBefore = nil
        lastInboxFetch = nil
    }

    // MARK: Helpers

    private func update(_ value: LearningLinkLocalState) {
        value.save(defaults)
        state = value
    }

    private func markPausedByServer() {
        availability = .paused
        pausedByServer = true
    }

    private func handle(_ error: Error) {
        switch error as? LearningLinkAPI.Failure {
        case .paused?:
            markPausedByServer()
        case .notFound?:
            // Revoked or expired on crabrix.com: this device is disconnected too.
            forgetLocally()
            notice = "Your learning link was removed from crabrix.com or expired after 90 days without use, so this device is disconnected too. Connect again for a new URL, and replace it in your agent."
            return
        case let .rateLimited(retryAfter)?:
            retryNotBefore = now().addingTimeInterval(min(retryAfter ?? 60, 3_600))
        default:
            break
        }
        statusLine = Self.describe(error, connecting: false)
    }

    private func mayCallServer() -> Bool {
        guard let retryNotBefore else { return true }
        if now() >= retryNotBefore {
            self.retryNotBefore = nil
            return true
        }
        return false
    }

    static func describe(_ error: Error, connecting: Bool) -> String {
        let action = connecting ? "Could not connect" : "Not synced"
        let later = connecting ? "Please try again later." : "Crabrix tries again later."
        switch error as? LearningLinkAPI.Failure {
        case .offline?: return "\(action): you are offline. \(later)"
        case .paused?: return "Learning links are paused on crabrix.com for a while. Nothing new is shared."
        case .notFound?:
            return connecting
                ? "\(action): crabrix.com did not accept the link. \(later)"
                : "crabrix.com no longer has this link."
        case .rateLimited?: return "\(action): too many requests for now. \(later)"
        default:
            if case LearningLinkSnapshot.Failure.tooLarge? = error as? LearningLinkSnapshot.Failure {
                return "\(action): your progress is larger than a learning link can hold."
            }
            return "\(action): crabrix.com did not answer as expected. \(later)"
        }
    }
}
