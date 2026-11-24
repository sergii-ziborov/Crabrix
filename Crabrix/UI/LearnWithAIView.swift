import SwiftUI
import UIKit

/// What a lesson hands to "Learn this lesson with AI": its public details, and
/// a way to read the learner's progress only if they later choose to export it.
struct LessonAIContext {
    let lesson: AcademyAILessonContext
    let progress: @MainActor () -> AILearningState.Progress
}

/// Learn with AI in the Academy library: connection steps per client, prompts,
/// honest limits and an opt-in AI Learning State export.
///
/// Static content with copy and share actions. It shows without a network, the
/// only request is the status check below, and it stores nothing except the
/// `crabrix.ai.*` flags in `AILearningFlags`.
struct LearnWithAIView: View {
    /// The lesson this screen was opened from, if any.
    let currentLesson: AILearningLessonRef?
    let progress: @MainActor () -> AILearningState.Progress
    var flags = AILearningFlags()
    var statusClient = AcademyAIStatusClient()
    /// "Connect my progress" (docs/ai-learning/learning-link.md).
    @ObservedObject var learningLink: LearningLinkController = .shared

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var client: AcademyAIClient = .claude
    @State private var status: AcademyAIStatus = .checking
    @State private var learningLinks: LearningLinkAvailability = .unknown
    /// Off on every visit: nothing about progress leaves without a choice.
    @State private var includesProgress = false
    @State private var showsFeedback = false
    @State private var wasInBackground = false

    private let promptColumns = [GridItem(.adaptive(minimum: 300), spacing: 14, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                intro
                if showsFeedback {
                    AIFeedbackCard(flags: flags) { showsFeedback = false }
                }
                LearningLinkSection(link: learningLink, availability: learningLinks,
                                    learnWithAIPaused: status.isPaused)
                if case let .paused(message) = status {
                    pausedNotice(message)
                } else if learningLink.isConnected {
                    // The personal URL above replaces the public one.
                    connectedInsteadNote
                } else {
                    connectSection
                }
                promptsSection
                continueSection
                limitsSection
            }
            .padding(.vertical, 20)
            .crabrixPageContent()
        }
        .background(CrabrixTheme.background.ignoresSafeArea())
        .foregroundStyle(CrabrixTheme.primary)
        .navigationTitle("Learn with AI")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard status == .checking else { return }
            let report = await statusClient.fetchReport()
            status = report.learnWithAI
            learningLinks = report.learningLinks
            learningLink.applyAvailability(report.learnWithAI.isPaused ? .paused : report.learningLinks)
        }
        .onAppear {
            showsFeedback = flags.shouldOfferFeedback
            learningLink.learnDidAppear()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                wasInBackground = true
            } else if phase == .active, wasInBackground {
                wasInBackground = false
                if flags.shouldOfferFeedback { showsFeedback = true }
            }
        }
    }

    // MARK: Sections

    private var intro: some View {
        // At accessibility text sizes the icon sits above the text, so the
        // words keep the full width.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
        return layout {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(CrabrixTheme.blue)
                .frame(width: 48, height: 48)
                .background(CrabrixTheme.blue.opacity(0.13), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("OPTIONAL · FREE · NO ACCOUNT")
                    .font(.caption2.monospaced().bold())
                    .foregroundStyle(CrabrixTheme.blue)
                Text("Learn Rust with your AI agent.")
                    .font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("Connect Claude, Codex, Cursor or another MCP client to Crabrix Academy. Your agent teaches from the real lessons and exercises, and you write the code and run it in Crabrix.")
                    .font(.subheadline)
                    .foregroundStyle(CrabrixTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Text("AI is optional. Every lesson, exercise and the Playground work exactly as before without it.")
                    .font(.caption)
                    .foregroundStyle(CrabrixTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func pausedNotice(_ message: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Learn with AI is paused", systemImage: "pause.circle.fill")
                .font(.headline)
                .foregroundStyle(CrabrixTheme.amber)
            Text(message ?? "Connecting an agent to Crabrix Academy is paused for a while, so the setup steps are hidden. Lessons, exercises, the Playground and your progress work as usual. Please check back later.")
                .font(.subheadline)
                .foregroundStyle(CrabrixTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .crabrixPanel(cornerRadius: 16)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ai-paused-notice")
    }

    private var connectSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Connect your agent")
            Text("The Academy server is read-only and public: it serves lessons, exercises, examples and learning paths. It never sees your progress, your projects or your Playground rooms.")
                .font(.subheadline)
                .foregroundStyle(CrabrixTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            if status == .unreachable {
                Label("Offline — you can still copy the steps", systemImage: "wifi.slash")
                    .font(.caption)
                    .foregroundStyle(CrabrixTheme.muted)
                    .accessibilityIdentifier("ai-offline-note")
            }
            AIClientPicker(selection: $client)
            AIClientSteps(client: client, onCopied: { flags.recordCopy() })
                .id(client)
        }
    }

    private var connectedInsteadNote: some View {
        Label("Your agent uses your personal URL above, which includes every Crabrix Academy tool. You do not need the public Academy connector as well.",
              systemImage: "checkmark.seal.fill")
            .font(.subheadline)
            .foregroundStyle(CrabrixTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("ai-public-setup-replaced")
    }

    private var promptsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Start with a prompt")
            Text("Paste one into a chat with Crabrix Academy connected.")
                .font(.subheadline)
                .foregroundStyle(CrabrixTheme.muted)
            LazyVGrid(columns: promptColumns, alignment: .leading, spacing: 14) {
                ForEach(AcademyAIPrompts.all.filter { $0.id != AcademyAIPrompts.continueLearning.id }) { prompt in
                    AIPromptCard(title: prompt.title, text: prompt.text) {
                        AICopyButton(
                            title: "Copy prompt",
                            accessibilityLabel: "Copy the \(prompt.title) prompt",
                            identifier: "ai-copy-prompt-\(prompt.id)",
                            text: { prompt.text },
                            onCopied: { flags.recordCopy() }
                        )
                    }
                }
            }
        }
    }

    private var continueSection: some View {
        let snapshot = includesProgress ? progress() : nil
        let file = AILearningStateFile(
            currentLesson: currentLesson, progress: snapshot, producer: .current
        )
        return VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Continue learning")
            Text("Your progress stays on this device, and your agent knows only what you give it. Export your learning state and paste it into your agent with the Continue learning prompt.")
                .font(.subheadline)
                .foregroundStyle(CrabrixTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: $includesProgress) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Include my completed lessons")
                            .font(.subheadline.weight(.semibold))
                        Text(progressSummary(snapshot))
                            .font(.caption)
                            .foregroundStyle(CrabrixTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(CrabrixTheme.mint)
                .accessibilityIdentifier("ai-include-progress")

                if let currentLesson {
                    Label("Includes the lesson you came from: \(currentLesson.courseId)/\(currentLesson.lessonId)",
                          systemImage: "book.closed")
                        .font(.caption)
                        .foregroundStyle(CrabrixTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider().overlay(CrabrixTheme.border)

                AIPromptCard(title: AcademyAIPrompts.continueLearning.title,
                             text: AcademyAIPrompts.continueLearning.text,
                             detail: includesProgress
                                ? "Copies the prompt with your learning state below it."
                                : "Copies the prompt only. Switch on the option above to add your lessons.") {
                    AICopyButton(
                        title: "Copy prompt",
                        accessibilityLabel: includesProgress
                            ? "Copy the Continue learning prompt with my learning state"
                            : "Copy the Continue learning prompt",
                        identifier: "ai-copy-prompt-continue",
                        prominent: true,
                        text: {
                            let state = includesProgress
                                ? (try? file.data()).flatMap { String(data: $0, encoding: .utf8) } : nil
                            return AcademyAIPrompts.continuePrompt(stateJSON: state)
                        },
                        onCopied: { flags.recordCopy() }
                    )
                }

                Divider().overlay(CrabrixTheme.border)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Learning state file")
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 10) {
                        ShareLink(item: file, preview: SharePreview(AILearningState.fileName)) {
                            Label("Share file", systemImage: "square.and.arrow.up")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .tint(CrabrixTheme.blue)
                        .accessibilityLabel("Share my learning state as \(AILearningState.fileName)")
                        .accessibilityIdentifier("ai-share-state")
                        AICopyButton(
                            title: "Copy as text",
                            accessibilityLabel: "Copy my learning state as text",
                            identifier: "ai-copy-state",
                            text: { (try? file.data()).flatMap { String(data: $0, encoding: .utf8) } ?? "" }
                        )
                    }
                    Text("\(AILearningState.fileName) · AI Learning State v1. Lesson IDs only: no answers, code, rating, projects or links. It never changes your progress in the app.")
                        .font(.caption)
                        .foregroundStyle(CrabrixTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .crabrixPanel(cornerRadius: 16)
        }
    }

    private func progressSummary(_ snapshot: AILearningState.Progress?) -> String {
        guard let snapshot else {
            return "Off: the file and prompt contain no progress."
        }
        let completed = snapshot.completed.filter(AILearningState.isIdentifier).count
        let known = snapshot.credited.keys.filter {
            !snapshot.completed.contains($0) && AILearningState.isIdentifier($0)
        }.count
        let lessons = completed == 1 ? "lesson" : "lessons"
        let knownText = known > 0 ? ", \(known) known from a bridge course" : ""
        return "On: \(completed) completed \(lessons)\(knownText). Only lesson IDs, copied from this device."
    }

    private var limitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("What your agent can and cannot do")
            VStack(alignment: .leading, spacing: 10) {
                ForEach(AcademyAIPrompts.honestLimits, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(CrabrixTheme.mint)
                            .accessibilityHidden(true)
                        Text(line)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Link(destination: URL(string: "https://crabrix.com/api/academy/v1/teaching-contract.md")!) {
                    Label("Agents follow the Crabrix teaching contract", systemImage: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CrabrixTheme.blue)
                }
                .padding(.top, 2)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .crabrixPanel(cornerRadius: 16)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.title2.bold())
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

/// "Learn this lesson with AI": this lesson's public context as a prompt, with
/// copy, share and the clients' open links. No learner data, no network.
struct LessonAISheet: View {
    let context: LessonAIContext
    var flags = AILearningFlags()

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var client: AcademyAIClient = .claude

    private var prompt: String { AcademyAIPrompts.lessonPrompt(context.lesson) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Learn this lesson with AI")
                            .font(.title2.bold())
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text("Paste this into Claude, Codex, Cursor or another agent connected to Crabrix Academy. It contains only this lesson’s public details.")
                            .font(.subheadline)
                            .foregroundStyle(CrabrixTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        AICodeBlock(text: prompt)
                            .accessibilityIdentifier("ai-lesson-prompt")
                        HStack(spacing: 10) {
                            AICopyButton(
                                title: "Copy prompt",
                                accessibilityLabel: "Copy the prompt for this lesson",
                                identifier: "ai-copy-lesson-prompt",
                                prominent: true,
                                text: { prompt },
                                onCopied: { flags.recordCopy() }
                            )
                            ShareLink(item: prompt) {
                                Label("Share", systemImage: "square.and.arrow.up")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .tint(CrabrixTheme.blue)
                            .accessibilityLabel("Share the prompt for this lesson")
                        }
                        Label(practiceNote, systemImage: context.lesson.hasLab ? "hammer.fill" : "play.rectangle")
                            .font(.caption)
                            .foregroundStyle(CrabrixTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .crabrixPanel(cornerRadius: 16)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Open your agent")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        AIClientPicker(selection: $client)
                        clientAction
                    }

                    NavigationLink {
                        LearnWithAIView(currentLesson: context.lesson.reference, progress: context.progress, flags: flags)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "point.3.connected.trianglepath.dotted")
                                .foregroundStyle(CrabrixTheme.blue)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Connect your agent to Crabrix Academy")
                                    .font(.subheadline.weight(.semibold))
                                Text("Setup steps, prompts and Continue learning")
                                    .font(.caption)
                                    .foregroundStyle(CrabrixTheme.muted)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(CrabrixTheme.blue)
                                .accessibilityHidden(true)
                        }
                        .padding(15)
                        .contentShape(Rectangle())
                        .crabrixPanel(cornerRadius: 16)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("ai-lesson-open-setup")
                }
                .padding(.vertical, 20)
                .crabrixPageContent(maximumWidth: CrabrixPageLayout.readingMaximumWidth)
            }
            .background(CrabrixTheme.background.ignoresSafeArea())
            .foregroundStyle(CrabrixTheme.primary)
            .navigationTitle(context.lesson.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                CrabrixModalCloseAction { dismiss() }
            }
        }
    }

    private var practiceNote: String {
        context.lesson.hasLab
            ? "Your agent gives you the exercise; you write and run the code in this lesson’s compiler lab, where Crabrix checks it."
            : "Your agent can open this lesson in the web Playground (crabrix_academy_open_playground); you write the code there."
    }

    @ViewBuilder
    private var clientAction: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let link = client.openLink {
                Button {
                    UIPasteboard.general.string = prompt
                    flags.recordCopy()
                    openURL(link.url)
                } label: {
                    Label("Copy and \(link.title.prefix(1).lowercased() + link.title.dropFirst())",
                          systemImage: "arrow.up.right.square")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(CrabrixTheme.coral)
                .accessibilityLabel("Copy the prompt and \(link.title.lowercased())")
                .accessibilityIdentifier("ai-lesson-open-\(client.id)")
                Text("The prompt is copied first: paste it into a new chat with Crabrix Academy connected.")
                    .font(.caption)
                    .foregroundStyle(CrabrixTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label(client.computerNote ?? "Paste the prompt into a chat in your client with Crabrix Academy connected.",
                      systemImage: client.computerNote == nil ? "app.connected.to.app.below.fill" : "laptopcomputer")
                    .font(.subheadline)
                    .foregroundStyle(CrabrixTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if client.computerNote != nil {
                    Text("Then paste the prompt into a chat with Crabrix Academy connected. Share sends it to your computer.")
                        .font(.caption)
                        .foregroundStyle(CrabrixTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .crabrixPanel(cornerRadius: 14)
    }
}

// MARK: - Shared pieces

/// One client's steps, as on the website, with a copy button for every
/// command, URL and configuration.
private struct AIClientSteps: View {
    let client: AcademyAIClient
    let onCopied: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(client.name)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if let note = client.computerNote {
                Label(note, systemImage: "laptopcomputer")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CrabrixTheme.blue)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("ai-computer-note")
            }
            ForEach(Array(client.steps.enumerated()), id: \.offset) { index, block in
                switch block {
                case let .text(markdown):
                    Text(Self.inline(markdown))
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                case let .code(code, copyTitle, label):
                    VStack(alignment: .leading, spacing: 8) {
                        AICodeBlock(text: code)
                        AICopyButton(
                            title: copyTitle,
                            accessibilityLabel: label,
                            identifier: "ai-copy-\(client.id)-\(index)",
                            text: { code },
                            onCopied: onCopied
                        )
                    }
                }
            }
            if let link = client.openLink {
                Button {
                    openURL(link.url)
                } label: {
                    Label(link.title, systemImage: "arrow.up.right.square")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(CrabrixTheme.onAccent)
                .tint(CrabrixTheme.coral)
                .accessibilityIdentifier("ai-open-\(client.id)")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .crabrixPanel(cornerRadius: 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ai-steps-\(client.id)")
    }

    /// Bold, emphasis and `code` at the surrounding text size.
    private static func inline(_ markdown: String) -> AttributedString {
        (try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(markdown)
    }
}

/// The five clients as chips that wrap at any text size.
struct AIClientPicker: View {
    @Binding var selection: AcademyAIClient

    var body: some View {
        AIFlowLayout(spacing: 8) {
            ForEach(AcademyAIClient.allCases) { client in
                let selected = client == selection
                Button {
                    selection = client
                } label: {
                    Text(client.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(minHeight: 44)
                        .foregroundStyle(selected ? CrabrixTheme.onAccent : CrabrixTheme.primary)
                        .background(selected ? CrabrixTheme.coral : CrabrixTheme.raised, in: Capsule())
                        .overlay { Capsule().stroke(selected ? Color.clear : CrabrixTheme.border) }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(client.name)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("ai-client-\(client.id)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Choose your AI client")
    }
}

struct AICodeBlock: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.footnote, design: .monospaced))
            .foregroundStyle(CrabrixTheme.primary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(CrabrixTheme.editor, in: RoundedRectangle(cornerRadius: 11))
            .overlay { RoundedRectangle(cornerRadius: 11).stroke(CrabrixTheme.border) }
    }
}

/// Copies on tap, says "Copied" for a moment and announces it to VoiceOver.
struct AICopyButton: View {
    let title: String
    let accessibilityLabel: String
    var identifier: String? = nil
    var prominent = false
    let text: () -> String
    var onCopied: () -> Void = {}

    @State private var copied = false
    @State private var reset: Task<Void, Never>?

    var body: some View {
        let button = Button {
            UIPasteboard.general.string = text()
            onCopied()
            copied = true
            UIAccessibility.post(notification: .announcement, argument: "Copied")
            reset?.cancel()
            reset = Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                if !Task.isCancelled { copied = false }
            }
        } label: {
            Label(copied ? "Copied" : title, systemImage: copied ? "checkmark" : "doc.on.doc")
                .font(.subheadline.weight(.semibold))
        }
        .accessibilityLabel(copied ? "Copied" : accessibilityLabel)
        .accessibilityIdentifier(identifier ?? "")

        if prominent {
            button
                .buttonStyle(.borderedProminent)
                .foregroundStyle(CrabrixTheme.onAccent)
                .tint(copied ? CrabrixTheme.mint : CrabrixTheme.coral)
        } else {
            button
                .buttonStyle(.bordered)
                .tint(copied ? CrabrixTheme.mint : CrabrixTheme.coral)
        }
    }
}

private struct AIPromptCard<Action: View>: View {
    let title: String
    let text: String
    var detail: String? = nil
    @ViewBuilder let action: () -> Action

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .top, spacing: 10) {
                Capsule()
                    .fill(CrabrixTheme.coral.opacity(0.6))
                    .frame(width: 3)
                    .accessibilityHidden(true)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(CrabrixTheme.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(CrabrixTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            action()
        }
        .padding(detail == nil ? 16 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(AIPromptCardBackground(isPanel: detail == nil))
    }
}

private struct AIPromptCardBackground: ViewModifier {
    let isPanel: Bool

    func body(content: Content) -> some View {
        if isPanel {
            content.crabrixPanel(cornerRadius: 16)
        } else {
            content
        }
    }
}

/// Shown once (see `AILearningFlags.shouldOfferFeedback`). Answered or
/// dismissed, it never returns. The answer and the optional text go only into
/// a mail draft; nothing is counted or sent by the app.
private struct AIFeedbackCard: View {
    let flags: AILearningFlags
    let onClose: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var answer: AILearningFeedback.Answer?
    @State private var note = ""
    @State private var mailUnavailable = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(AILearningFeedback.question)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button {
                    if answer == nil { flags.finishFeedback(.dismissed) }
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.bold())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(CrabrixTheme.muted)
                .accessibilityLabel(answer == nil ? "Dismiss this question" : "Close")
            }

            if let answer {
                Text("Thank you. Anything to add? Optional; it goes only into an email draft you send yourself.")
                    .font(.subheadline)
                    .foregroundStyle(CrabrixTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("Your comment", text: $note, axis: .vertical)
                    .lineLimit(2...6)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(CrabrixTheme.editor, in: RoundedRectangle(cornerRadius: 11))
                    .overlay { RoundedRectangle(cornerRadius: 11).stroke(CrabrixTheme.border) }
                    .accessibilityLabel("Your comment, optional")
                    .accessibilityIdentifier("ai-feedback-text")
                HStack(spacing: 10) {
                    Button {
                        email(answer)
                    } label: {
                        Label("Email it", systemImage: "envelope.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(CrabrixTheme.onAccent)
                    .tint(CrabrixTheme.coral)
                    .accessibilityHint("Opens a mail draft with your answer. Nothing is sent until you send it.")
                    Button("Done", action: onClose)
                        .buttonStyle(.bordered)
                }
                if mailUnavailable {
                    Text("No mail app answered. Your message is on the clipboard instead.")
                        .font(.caption)
                        .foregroundStyle(CrabrixTheme.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                AIFlowLayout(spacing: 8) {
                    ForEach(AILearningFeedback.Answer.allCases) { item in
                        Button(item.rawValue) {
                            answer = item
                            flags.finishFeedback(.answered)
                        }
                        .buttonStyle(.bordered)
                        .tint(CrabrixTheme.blue)
                        .accessibilityIdentifier("ai-feedback-\(item == .yes ? "yes" : item == .partly ? "partly" : "not-working")")
                    }
                    Button("Not now") {
                        flags.finishFeedback(.dismissed)
                        onClose()
                    }
                    .buttonStyle(.bordered)
                    .tint(CrabrixTheme.muted)
                    .accessibilityLabel("Not now, dismiss this question")
                }
                Text("Nothing is sent: an answer goes only into an email draft, if you choose to write one.")
                    .font(.caption)
                    .foregroundStyle(CrabrixTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CrabrixTheme.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(CrabrixTheme.blue.opacity(0.3)) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ai-feedback-card")
    }

    private func email(_ answer: AILearningFeedback.Answer) {
        let producer = AILearningState.Producer.current
        guard let url = AILearningFeedback.mailURL(answer, note: note, producer: producer) else { return }
        openURL(url) { accepted in
            guard !accepted else { return }
            UIPasteboard.general.string = AILearningFeedback.body(answer, note: note, producer: producer)
            mailUnavailable = true
        }
    }
}

/// Lays children out in rows and wraps, so chips stay whole at large text sizes.
struct AIFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = measured(subview, maxWidth: maxWidth)
            if x > 0, x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = measured(subview, maxWidth: bounds.width)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }

    private func measured(_ subview: LayoutSubview, maxWidth: CGFloat) -> CGSize {
        let ideal = subview.sizeThatFits(.unspecified)
        guard ideal.width > maxWidth else { return ideal }
        return subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
    }
}
