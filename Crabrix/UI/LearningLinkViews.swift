import SwiftUI
import UIKit

/// The words of "Connect my progress": what the snapshot holds and what it
/// never holds (docs/ai-learning/learning-link.md, "Snapshot plaintext"), and
/// the per-client steps for the personal URL.
enum LearningLinkGuide {
    static let shared = [
        "Completed lessons, and lessons known from a bridge course (lesson IDs)",
        "The lesson you opened last and up to 10 recent lessons",
        "Installed courses: title, version, number of lessons and how many you completed",
        "Up to 30 of your weakest practice topics: attempts, correct answers and next review date",
        "Lessons and focus your AI tutor sent you, and whether you completed them",
        "The app version and whether this is an iPhone or iPad",
    ]

    static let notShared = [
        "Your answers, code and projects",
        "XP, rating and achievements",
        "Playground rooms, room links and Git credentials",
        "Your name, account, email or any contact details",
    ]

    static let howItWorks = "Your progress is encrypted on this device with a key that only your personal URL contains. crabrix.com stores the encrypted copy and cannot read it; your agent’s Crabrix connector decrypts it while answering. Anyone with the URL can read your progress, so treat it like a password."

    static let limits = "Your agent can read your progress and suggest lessons. It can never complete a lesson or change your answers: only Crabrix checks in the app do that."

    /// "Add this URL as a custom connector instead of the public one."
    static func steps(for client: AcademyAIClient, url: String) -> [AcademyAIClient.Block] {
        switch client {
        case .claude:
            return [
                .text("In Claude on the web, desktop or mobile: **Customize → Connectors → Add custom connector**. Name it *Crabrix (my progress)* and paste your URL:"),
                .code(url, copyTitle: "Copy URL", accessibilityLabel: "Copy my personal Crabrix URL"),
                .text("Use it instead of the public Crabrix Academy connector: it has every Academy tool plus your progress. Remove the public one so your agent does not mix them up."),
            ]
        case .claudeCode:
            return [
                .text("Add your personal server instead of `crabrix-academy`:"),
                .code("claude mcp add --transport http crabrix-me \(url)",
                      copyTitle: "Copy command", accessibilityLabel: "Copy the Claude Code command with my personal URL"),
                .text("If you added the public one before, remove it with `claude mcp remove crabrix-academy`."),
            ]
        case .codex:
            return [
                .text("Add your personal server instead of `crabrix-academy`:"),
                .code("codex mcp add crabrix-me --url \(url)",
                      copyTitle: "Copy command", accessibilityLabel: "Copy the Codex command with my personal URL"),
            ]
        case .cursor:
            return [
                .text("In `~/.cursor/mcp.json`, replace `crabrix-academy` with this entry, then restart Cursor:"),
                .code(cursorConfiguration(url: url), copyTitle: "Copy JSON",
                      accessibilityLabel: "Copy the Cursor configuration with my personal URL"),
            ]
        case .other:
            return [
                .text("Add a remote MCP server with Streamable HTTP and no authentication, using your URL instead of the public Academy URL:"),
                .code(url, copyTitle: "Copy URL", accessibilityLabel: "Copy my personal Crabrix URL"),
            ]
        }
    }

    static func cursorConfiguration(url: String) -> String {
        """
        {
          "mcpServers": {
            "crabrix-me": {
              "url": "\(url)"
            }
          }
        }
        """
    }
}

/// "Connect my progress" in Learn with AI. Off until the learner connects; a
/// confirmation sheet comes before the first upload, and Disconnect is always
/// available while connected, even when the feature is paused.
struct LearningLinkSection: View {
    @ObservedObject var link: LearningLinkController
    let availability: LearningLinkAvailability
    let learnWithAIPaused: Bool

    @State private var confirmsConnect = false
    @State private var confirmsDisconnect = false
    @State private var client: AcademyAIClient = .claude

    private var paused: Bool { learnWithAIPaused || availability == .paused || link.isPaused }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Connect my progress")
                    .font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if link.isConnected {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CrabrixTheme.mint)
                        .accessibilityIdentifier("link-connected-badge")
                }
            }
            if link.isConnected {
                connectedPanel
            } else if paused {
                pausedNote
            } else {
                disconnectedPanel
            }
            if let notice = link.notice, !link.isConnected {
                Label(notice, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(CrabrixTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("link-notice")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("link-section")
        .sheet(isPresented: $confirmsConnect) {
            LearningLinkConfirmSheet(link: link)
        }
        .alert("Disconnect your agent?", isPresented: $confirmsDisconnect) {
            Button("Disconnect", role: .destructive) {
                Task { await link.disconnect() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your agent loses access at once, the encrypted copy on crabrix.com is deleted, and lessons from your AI tutor are removed from Learn. Your progress in Crabrix does not change.")
        }
        .task {
            link.prepareForDisplay()
            await link.refreshStatus()
        }
    }

    // MARK: Not connected

    private var disconnectedPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Give your agent a personal connector that can read your Crabrix progress and send you lessons to practise. Nothing is shared until you connect, and Disconnect deletes it.")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            LearningLinkSharedList()
            Button {
                link.notice = nil
                confirmsConnect = true
            } label: {
                Label("Connect", systemImage: "link.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 30)
            }
            .buttonStyle(.borderedProminent)
            .foregroundStyle(CrabrixTheme.onAccent)
            .tint(CrabrixTheme.coral)
            .accessibilityHint("Shows what is shared before anything is uploaded.")
            .accessibilityIdentifier("link-connect")
            if let line = link.statusLine {
                statusText(line)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .crabrixPanel(cornerRadius: 16)
    }

    private var pausedNote: some View {
        Label("Connecting your progress is paused on crabrix.com for a while. Nothing is shared. Please check back later.",
              systemImage: "pause.circle.fill")
            .font(.subheadline)
            .foregroundStyle(CrabrixTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .crabrixPanel(cornerRadius: 16)
            .accessibilityIdentifier("link-paused")
    }

    // MARK: Connected

    private var connectedPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let url = link.url?.absoluteString {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your personal URL")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    AICodeBlock(text: url)
                        .accessibilityLabel("Your personal Crabrix URL")
                        .accessibilityValue(url)
                        .accessibilityIdentifier("link-url")
                    AIFlowLayout(spacing: 10) {
                        AICopyButton(title: "Copy URL", accessibilityLabel: "Copy my personal Crabrix URL",
                                     identifier: "link-copy-url", prominent: true, text: { url })
                        ShareLink(item: url) {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .tint(CrabrixTheme.blue)
                        .accessibilityLabel("Share my personal Crabrix URL")
                        .accessibilityIdentifier("link-share-url")
                    }
                    Label("Anyone with this URL can read your progress. Give it only to your agent.",
                          systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(CrabrixTheme.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider().overlay(CrabrixTheme.border)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Add it to your agent")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    AIClientPicker(selection: $client)
                    LearningLinkClientSteps(client: client, url: url)
                        .id(client)
                }

                Divider().overlay(CrabrixTheme.border)
            } else {
                Label("Your personal URL is in this device’s Keychain and will show once it can be read.",
                      systemImage: "key.fill")
                    .font(.caption)
                    .foregroundStyle(CrabrixTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            statusRows

            if let line = link.statusLine {
                statusText(line)
            }
            if link.isPaused || availability == .paused || learnWithAIPaused {
                Label("Sync is paused on crabrix.com. You can still disconnect.", systemImage: "pause.circle")
                    .font(.caption)
                    .foregroundStyle(CrabrixTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("link-sync-paused")
            }

            AIFlowLayout(spacing: 10) {
                Button {
                    Task { await link.syncNow() }
                } label: {
                    Label(link.activity == .syncing ? "Syncing…" : "Sync now", systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(CrabrixTheme.blue)
                .disabled(link.activity != nil || paused)
                .accessibilityIdentifier("link-sync-now")
                Button(role: .destructive) {
                    confirmsDisconnect = true
                } label: {
                    Label(link.activity == .disconnecting ? "Disconnecting…" : "Disconnect", systemImage: "link.badge.minus")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(CrabrixTheme.danger)
                .disabled(link.activity == .disconnecting)
                .accessibilityHint("Deletes the link and your encrypted progress on crabrix.com.")
                .accessibilityIdentifier("link-disconnect")
            }

            DisclosureGroup("What your agent can read") {
                LearningLinkSharedList()
                    .padding(.top, 8)
            }
            .font(.subheadline.weight(.semibold))
            .tint(CrabrixTheme.blue)
            .accessibilityIdentifier("link-what-is-shared")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .crabrixPanel(cornerRadius: 16)
    }

    private var statusRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            statusRow("Last synced", value: link.state?.lastSyncedAt, never: "Not yet", identifier: "link-last-synced")
            statusRow("Last used by your agent", value: link.state?.lastAgentReadAt, never: "Not yet",
                      identifier: "link-last-used")
        }
    }

    private func statusRow(_ title: String, value: Date?, never: String, identifier: String) -> some View {
        let text = value.map { Self.relative($0) } ?? never
        return HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(CrabrixTheme.muted)
            Spacer(minLength: 8)
            Text(text)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    private func statusText(_ line: String) -> some View {
        Label(line, systemImage: "exclamationmark.circle")
            .font(.caption)
            .foregroundStyle(CrabrixTheme.amber)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("link-status-line")
    }

    static func relative(_ date: Date, now: Date = Date()) -> String {
        if now.timeIntervalSince(date) < 60 { return "Just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

/// Exactly what is and is not shared.
private struct LearningLinkSharedList: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            list("Shared with your agent", LearningLinkGuide.shared, icon: "checkmark.circle.fill", tint: CrabrixTheme.mint,
                 identifier: "link-shared-list")
            list("Never shared", LearningLinkGuide.notShared, icon: "xmark.circle.fill", tint: CrabrixTheme.coral,
                 identifier: "link-not-shared-list")
            Text(LearningLinkGuide.howItWorks)
                .font(.caption)
                .foregroundStyle(CrabrixTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text(LearningLinkGuide.limits)
                .font(.caption)
                .foregroundStyle(CrabrixTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func list(_ title: String, _ lines: [String], icon: String, tint: Color, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                    Text(line)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

/// One client's steps with the personal URL.
private struct LearningLinkClientSteps: View {
    let client: AcademyAIClient
    let url: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let note = client.computerNote {
                Label(note, systemImage: "laptopcomputer")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CrabrixTheme.blue)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(LearningLinkGuide.steps(for: client, url: url).enumerated()), id: \.offset) { index, block in
                switch block {
                case let .text(markdown):
                    Text(Self.inline(markdown))
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                case let .code(code, copyTitle, label):
                    VStack(alignment: .leading, spacing: 8) {
                        AICodeBlock(text: code)
                        AICopyButton(title: copyTitle, accessibilityLabel: label,
                                     identifier: "link-copy-\(client.id)-\(index)", text: { code })
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("link-steps-\(client.id)")
    }

    /// Our own fixed text only; nothing from an agent goes through Markdown.
    private static func inline(_ markdown: String) -> AttributedString {
        (try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(markdown)
    }
}

/// Before the first upload: what will be sent, in counts and in full.
struct LearningLinkConfirmSheet: View {
    @ObservedObject var link: LearningLinkController
    @Environment(\.dismiss) private var dismiss
    @State private var input: LearningLinkSnapshot.Input?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Share your progress with your agent?")
                            .font(.title2.bold())
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text("Crabrix creates a personal URL and uploads an encrypted copy of the items below. It stays in sync while you are connected.")
                            .font(.subheadline)
                            .foregroundStyle(CrabrixTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let input {
                        summary(input)
                    }
                    LearningLinkSharedList()
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .crabrixPanel(cornerRadius: 16)
                    if let input, let preview = LearningLinkSnapshot.preview(input) {
                        DisclosureGroup("See exactly what is sent") {
                            AICodeBlock(text: preview)
                                .padding(.top, 8)
                                .accessibilityIdentifier("link-preview-json")
                        }
                        .font(.subheadline.weight(.semibold))
                        .tint(CrabrixTheme.blue)
                        .accessibilityIdentifier("link-preview")
                    }
                    if let line = link.statusLine {
                        Label(line, systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(CrabrixTheme.amber)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    AIFlowLayout(spacing: 10) {
                        Button {
                            Task {
                                if await link.connect() { dismiss() }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if link.activity == .connecting { ProgressView().tint(CrabrixTheme.onAccent) }
                                Text(link.activity == .connecting ? "Connecting…" : "Connect and upload")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .frame(minHeight: 30)
                        }
                        .buttonStyle(.borderedProminent)
                        .foregroundStyle(CrabrixTheme.onAccent)
                        .tint(CrabrixTheme.coral)
                        .disabled(link.activity != nil || input == nil)
                        .accessibilityIdentifier("link-confirm-connect")
                        Button("Cancel") { dismiss() }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("link-confirm-cancel")
                    }
                }
                .padding(.vertical, 20)
                .crabrixPageContent(maximumWidth: CrabrixPageLayout.readingMaximumWidth)
            }
            .background(CrabrixTheme.background.ignoresSafeArea())
            .foregroundStyle(CrabrixTheme.primary)
            .navigationTitle("Connect my progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                CrabrixModalCloseAction { dismiss() }
            }
        }
        .onAppear { input = link.snapshotInput() }
    }

    private func summary(_ input: LearningLinkSnapshot.Input) -> some View {
        let document = LearningLinkSnapshot.document(input)
        let lines = [
            Self.count(document.completed.count, "completed lesson", "completed lessons"),
            Self.count(document.credited.count, "lesson known from a bridge course", "lessons known from a bridge course"),
            Self.count(document.courses.count, "installed course", "installed courses"),
            Self.count(document.topics.count, "practice topic", "practice topics"),
        ]
        return VStack(alignment: .leading, spacing: 6) {
            Text("From this \(input.device == "iPad" ? "iPad" : "iPhone")")
                .font(.subheadline.weight(.semibold))
            ForEach(lines, id: \.self) { line in
                Label(line, systemImage: "circle.fill")
                    .labelStyle(SmallDotLabelStyle())
                    .font(.subheadline)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .crabrixPanel(cornerRadius: 16)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("link-confirm-summary")
    }

    private static func count(_ value: Int, _ one: String, _ many: String) -> String {
        "\(value) \(value == 1 ? one : many)"
    }
}

private struct SmallDotLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon
                .font(.system(size: 5))
                .foregroundStyle(CrabrixTheme.blue)
                .accessibilityHidden(true)
            configuration.title
        }
    }
}

/// "From your AI tutor" at the top of the Learn library: open assignments with
/// the agent's reason, the focus, Open through the app's own navigation and
/// Dismiss per item. Everything the agent wrote is shown verbatim as plain text.
struct TutorPlanCard: View {
    @ObservedObject var link: LearningLinkController
    let catalog: LearningLinkCatalog?
    /// The app's own completions: an assignment is done only when its lesson is here.
    let completedLessonIDs: Set<String>
    let onOpen: (_ courseID: String, _ lessonID: String) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let plan = link.tutorPlan
        let open = plan.openAssignments(completed: completedLessonIDs)
        if !open.isEmpty || plan.focus != nil {
            VStack(alignment: .leading, spacing: 14) {
                header(plan)
                if let focus = plan.focus { focusView(focus) }
                if let note = plan.note, !open.isEmpty {
                    Text(verbatim: note.text)
                        .font(.subheadline)
                        .foregroundStyle(CrabrixTheme.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 10)
                        .overlay(alignment: .leading) {
                            Capsule().fill(CrabrixTheme.blue.opacity(0.6)).frame(width: 3)
                        }
                        .accessibilityLabel("Note from your AI tutor: \(note.text)")
                }
                ForEach(open) { assignment in
                    row(assignment)
                    if assignment.id != open.last?.id { Divider().overlay(CrabrixTheme.border) }
                }
                footer(plan)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CrabrixTheme.blue.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(CrabrixTheme.blue.opacity(0.3)) }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("tutor-card")
        }
    }

    private func header(_ plan: TutorPlan) -> some View {
        let agent = plan.assignments.first?.agent ?? plan.focus?.agent
        return HStack(alignment: .center, spacing: 10) {
            // At accessibility sizes the words keep the full width.
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: "sparkles")
                    .font(.headline)
                    .foregroundStyle(CrabrixTheme.blue)
                    .frame(width: 34, height: 34)
                    .background(CrabrixTheme.blue.opacity(0.13), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("From your AI tutor")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                if let agent {
                    Text(verbatim: agent)
                        .font(.caption)
                        .foregroundStyle(CrabrixTheme.muted)
                        .accessibilityLabel("Sent by \(agent)")
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func focusView(_ focus: TutorPlan.Focus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Focus")
                    .font(.caption.monospaced().bold())
                    .foregroundStyle(CrabrixTheme.blue)
                Spacer(minLength: 8)
                Button {
                    link.clearFocus()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.bold())
                        .frame(width: 44, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(CrabrixTheme.muted)
                .accessibilityLabel("Dismiss the focus from your AI tutor")
                .accessibilityIdentifier("tutor-dismiss-focus")
            }
            if let goal = focus.goal {
                Text(verbatim: goal)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let path = focus.pathId {
                Label {
                    Text(verbatim: path)
                } icon: {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                }
                .font(.caption)
                .foregroundStyle(CrabrixTheme.muted)
                .accessibilityLabel("Learning path \(path)")
            }
            if !focus.concepts.isEmpty {
                AIFlowLayout(spacing: 6) {
                    ForEach(focus.concepts, id: \.self) { concept in
                        Text(verbatim: concept)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(CrabrixTheme.raised, in: Capsule())
                            .overlay { Capsule().stroke(CrabrixTheme.border) }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Concepts: \(focus.concepts.joined(separator: ", "))")
            }
            if let note = focus.note {
                Text(verbatim: note)
                    .font(.subheadline)
                    .foregroundStyle(CrabrixTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tutor-focus")
    }

    private func row(_ assignment: TutorPlan.Assignment) -> some View {
        let check = catalog?.check(courseID: assignment.courseId, lessonID: assignment.lessonId) ?? .unknown
        let title = catalog?.lessonTitles[assignment.lessonId] ?? assignment.lessonId
        let course = catalog?.courses.first { $0.id == assignment.courseId }?.title
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        return layout {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: course ?? assignment.courseId)
                    .font(.caption)
                    .foregroundStyle(CrabrixTheme.muted)
                if let reason = assignment.reason {
                    Text(verbatim: reason)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Reason: \(reason)")
                }
                if check == .courseNotInstalled {
                    Text("Download this course in Learn to open the lesson.")
                        .font(.caption)
                        .foregroundStyle(CrabrixTheme.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
            HStack(spacing: 6) {
                if check == .installed {
                    Button("Open") { onOpen(assignment.courseId, assignment.lessonId) }
                        .buttonStyle(.borderedProminent)
                        .foregroundStyle(CrabrixTheme.onAccent)
                        .tint(CrabrixTheme.coral)
                        .font(.subheadline.weight(.semibold))
                        .accessibilityLabel("Open \(title)")
                        .accessibilityIdentifier("tutor-open-\(assignment.lessonId)")
                }
                Button {
                    link.dismissAssignment(assignment.lessonId)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.bold())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(CrabrixTheme.muted)
                .accessibilityLabel("Dismiss \(title)")
                .accessibilityIdentifier("tutor-dismiss-\(assignment.lessonId)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tutor-assignment-\(assignment.lessonId)")
    }

    private func footer(_ plan: TutorPlan) -> some View {
        let done = plan.doneCount(completed: completedLessonIDs)
        let doneText = done == 0 ? "" : " \(done) assigned lesson\(done == 1 ? "" : "s") done."
        return Text("Suggestions from your agent. Only Crabrix checks complete a lesson.\(doneText)")
            .font(.caption)
            .foregroundStyle(CrabrixTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
