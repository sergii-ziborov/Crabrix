import SwiftUI

struct LessonDetailView: View {
    @EnvironmentObject private var vitals: CrabrixVitalsStore
    let lesson: RustLesson
    let isCompleted: Bool
    let onStart: () -> Void
    let onComplete: () -> Void
    /// Called once, with the first answer the reader commits to.
    var onAnswer: (Bool) -> Void = { _ in }

    @State private var page = 0
    @State private var selectedAnswer: Int?
    /// The last thing that cost or returned something, shown briefly in the header.
    @State private var lastOutcome: VitalsOutcome?

    private var brief: RustLessonBrief { lesson.brief }
    private var practice: RustLessonPractice { lesson.lessonPractice }
    /// The quick check gates the rest of the lesson, so it needs an answer
    /// before the summary page becomes reachable at all.
    private var isQuickCheckAnswered: Bool { selectedAnswer != nil }
    private var isLive: Bool {
        if case .planned = lesson.exercise { return false }
        return true
    }

    var body: some View {
        VStack(spacing: 0) {
            progressHeader

            TabView(selection: $page) {
                conceptPage.tag(0)
                practicePage.tag(1)
                // The last page only exists once the quick check is answered.
                // Disabling the footer button was not enough on its own: a
                // right-to-left swipe walked straight past the question.
                if isQuickCheckAnswered {
                    readyPage.tag(2)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.2), value: isQuickCheckAnswered)

            Divider().overlay(CrabrixTheme.border)
            navigationFooter
        }
        // Reading a page costs energy the first time only, so revisiting a
        // lesson to review it never charges twice.
        .onAppear { chargeCurrentPage() }
        .onChange(of: page) { _, _ in chargeCurrentPage() }
        .background {
            ZStack {
                CrabrixTheme.background.ignoresSafeArea()
                LinearGradient(
                    colors: [brief.tint.opacity(0.08), .clear, CrabrixTheme.blue.opacity(0.04)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
        }
        .foregroundStyle(CrabrixTheme.primary)
        .navigationTitle(lesson.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var progressHeader: some View {
        VStack(spacing: 10) {
            HStack {
                Text("LESSON · STEP \(page + 1) OF 3")
                    .font(.caption2.monospaced().bold())
                    .foregroundStyle(brief.tint)
                Spacer()
                Label("\(lesson.minutes) MIN", systemImage: "clock.fill")
                    .font(.caption2.monospaced())
                    .foregroundStyle(CrabrixTheme.muted)
            }

            HStack(spacing: 7) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index <= page ? brief.tint : CrabrixTheme.border)
                        .frame(height: 5)
                        .animation(.easeInOut(duration: 0.2), value: page)
                }
            }

            HStack {
                VitalsPill(store: vitals, showsCountdown: false, isInteractive: true)
                Spacer(minLength: 0)
                if let lastOutcome {
                    VitalsOutcomeBadge(outcome: lastOutcome)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(CrabrixTheme.panel.opacity(0.96))
    }

    private var conceptPage: some View {
        lessonScrollPage {
            LessonPageHeading(
                step: "01 · UNDERSTAND",
                title: lesson.title,
                subtitle: lesson.concept,
                systemImage: brief.systemImage,
                tint: brief.tint
            )

            LessonCard(title: "Why this matters", systemImage: "book.pages.fill", tint: brief.tint) {
                Text(brief.summary)
                    .font(.title3.weight(.semibold))
                Text(brief.explanation)
                    .foregroundStyle(CrabrixTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                if let example = brief.example {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(example.caption)
                            .font(.caption)
                            .foregroundStyle(CrabrixTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        HighlightedCodeBlock(code: example.code)
                    }
                    .padding(.top, 4)
                }
            }

            LessonCard(title: "The rule", systemImage: "lightbulb.fill", tint: CrabrixTheme.amber) {
                Text(practice.rule)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
            }

            objectives
        }
    }

    private var objectives: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("YOU WILL PRACTICE")
                .font(.caption.monospaced().bold())
                .foregroundStyle(CrabrixTheme.blue)
            ForEach(brief.objectives, id: \.self) { objective in
                Label(objective, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(CrabrixTheme.primary)
                    .labelStyle(LessonObjectiveLabelStyle())
            }
        }
        .padding(18)
        .background(CrabrixTheme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(CrabrixTheme.border) }
    }

    private var practicePage: some View {
        lessonScrollPage {
            LessonPageHeading(
                step: "02 · PRACTICE",
                title: "Make the rule concrete",
                subtitle: brief.task,
                systemImage: "hand.tap.fill",
                tint: CrabrixTheme.blue
            )

            VStack(alignment: .leading, spacing: 10) {
                Text("CODE SNAPSHOT")
                    .font(.caption2.monospaced().bold())
                    .foregroundStyle(CrabrixTheme.blue)
                HighlightedCodeBlock(code: practice.code, fontSize: 14)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("QUICK CHECK")
                    .font(.caption2.monospaced().bold())
                    .foregroundStyle(CrabrixTheme.coral)
                Text(practice.question)
                    .font(.title3.bold())

                ForEach(Array(practice.answers.enumerated()), id: \.offset) { index, answer in
                    answerButton(answer, at: index)
                }

                if !isQuickCheckAnswered {
                    Label(
                        "Answer to unlock the rest of the lesson.",
                        systemImage: "lock.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CrabrixTheme.muted)
                }

                if let selectedAnswer {
                    Label(
                        selectedAnswer == practice.correctAnswer
                            ? "Correct — \(practice.feedback)"
                            : "Not quite — \(practice.feedback)",
                        systemImage: selectedAnswer == practice.correctAnswer
                            ? "checkmark.circle.fill"
                            : "arrow.counterclockwise.circle.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(
                        selectedAnswer == practice.correctAnswer
                            ? CrabrixTheme.mint
                            : CrabrixTheme.amber
                    )
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
            .background(CrabrixTheme.panel, in: RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).stroke(CrabrixTheme.border) }
        }
    }

    private var readyPage: some View {
        lessonScrollPage {
            LessonPageHeading(
                step: "03 · APPLY",
                title: isLive ? "Ready for the compiler" : "Lock in the idea",
                subtitle: isLive
                    ? "Use real rustc output as evidence."
                    : "Finish this lesson and unlock the next node.",
                systemImage: isLive ? "hammer.fill" : "checkmark.seal.fill",
                tint: CrabrixTheme.mint
            )

            LessonCard(title: "Success looks like", systemImage: "flag.checkered", tint: CrabrixTheme.mint) {
                Text(brief.success)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Label(
                    isLive ? "The bundled compiler checks the final result." : "Your course map records this lesson locally.",
                    systemImage: isLive ? "cpu.fill" : "internaldrive.fill"
                )
                .font(.subheadline)
                .foregroundStyle(CrabrixTheme.muted)
            }

            LessonCard(title: "Hint before you go", systemImage: "sparkles", tint: CrabrixTheme.amber) {
                Text(brief.hint)
                    .foregroundStyle(CrabrixTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isCompleted {
                Label("Already completed — you can review it any time.", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(CrabrixTheme.mint)
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CrabrixTheme.mint.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func chargeCurrentPage() {
        let outcome = vitals.startLessonPage(lessonID: lesson.id, page: page)
        guard outcome != .free else { return }
        withAnimation(.easeOut(duration: 0.2)) { lastOutcome = outcome }
    }

    private func answerButton(_ answer: String, at index: Int) -> some View {
        let isSelected = selectedAnswer == index
        return Button {
            guard selectedAnswer == nil else { return }
            withAnimation(.easeInOut(duration: 0.16)) {
                selectedAnswer = index
            }
            let correct = index == practice.correctAnswer
            withAnimation(.easeOut(duration: 0.2)) {
                lastOutcome = vitals.recordAnswer(correct: correct)
            }
            onAnswer(correct)
        } label: {
            HStack(spacing: 12) {
                Text(String(UnicodeScalar(65 + index)!))
                    .font(.caption.monospaced().bold())
                    .foregroundStyle(isSelected ? CrabrixTheme.background : CrabrixTheme.muted)
                    .frame(width: 28, height: 28)
                    .background(isSelected ? brief.tint : CrabrixTheme.border, in: Circle())
                Text(answer)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.leading)
                Spacer()
                if isSelected {
                    Image(systemName: index == practice.correctAnswer ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(index == practice.correctAnswer ? CrabrixTheme.mint : CrabrixTheme.amber)
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity)
            .background(isSelected ? brief.tint.opacity(0.10) : CrabrixTheme.background.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 13))
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .stroke(isSelected ? brief.tint : CrabrixTheme.border)
            }
            .opacity(isQuickCheckAnswered && !isSelected ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isQuickCheckAnswered)
    }

    private var navigationFooter: some View {
        HStack(spacing: 12) {
            if page > 0 {
                Button {
                    withAnimation(.easeInOut) { page -= 1 }
                } label: {
                    Label("Back", systemImage: "arrow.left")
                        .frame(minWidth: 90)
                }
                .buttonStyle(.bordered)
            }

            Spacer(minLength: 0)

            if page < 2 {
                Button {
                    withAnimation(.easeInOut) { page += 1 }
                } label: {
                    Label(
                        page == 0 ? "Try a quick check" : "Review result",
                        systemImage: "arrow.right"
                    )
                    .frame(minWidth: 180)
                }
                .buttonStyle(.borderedProminent)
                .tint(brief.tint)
                .disabled(page == 1 && !isQuickCheckAnswered)
            } else {
                Button(action: isLive ? onStart : onComplete) {
                    Label(
                        isLive
                            ? "Open compiler lab"
                            : (isCompleted ? "Back to course" : "Complete lesson"),
                        systemImage: isLive ? "hammer.fill" : "checkmark.circle.fill"
                    )
                    .frame(minWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .tint(isLive ? CrabrixTheme.coral : CrabrixTheme.mint)
            }
        }
        .font(.headline)
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
    }

    private func lessonScrollPage<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                content()
            }
            .padding(22)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct LessonPageHeading: View {
    let step: String
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 64, height: 64)
                .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 18))
            VStack(alignment: .leading, spacing: 6) {
                Text(step)
                    .font(.caption2.monospaced().bold())
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(CrabrixTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct LessonCard<Content: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    let content: Content

    init(
        title: String,
        systemImage: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CrabrixTheme.panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(tint.opacity(0.25)) }
    }
}

private struct LessonObjectiveLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 9) {
            configuration.icon.foregroundStyle(CrabrixTheme.mint)
            configuration.title
        }
    }
}

private struct RustLessonBrief {
    let summary: String
    let explanation: String
    /// A short, highlighted snippet that shows the idea before the exercise.
    let example: RustLessonExample?
    let objectives: [String]
    let task: String
    let success: String
    let hint: String
    let systemImage: String
    let tint: Color
}

private struct RustLessonExample {
    let caption: String
    let code: String
}

private struct RustLessonPractice {
    let rule: String
    let code: String
    let question: String
    let answers: [String]
    let correctAnswer: Int
    let feedback: String
}

private extension RustLesson {
    /// Both of these read from `RustLessonLibrary`, which is the single place
    /// lesson copy lives. The fallbacks only matter for a lesson added to the
    /// catalogue before its writing lands, so they stay deliberately generic
    /// rather than duplicating content that would then drift.
    var lessonPractice: RustLessonPractice {
        guard let writing = RustLessonLibrary.writing(for: id) else {
            return RustLessonPractice(
                rule: brief.explanation,
                code: "// Build the smallest example for:\n// \(concept)",
                question: "What is the best next step when your model and rustc disagree?",
                answers: ["Add unsafe", "Read the diagnostic and make one intentional edit", "Ignore the warning"],
                correctAnswer: 1,
                feedback: "Small, evidence-driven changes make the compiler part of the learning loop."
            )
        }

        return RustLessonPractice(
            rule: writing.rule,
            code: writing.practiceCode,
            question: writing.question,
            answers: writing.answers,
            correctAnswer: writing.correctAnswer,
            feedback: writing.feedback
        )
    }

    var brief: RustLessonBrief {
        let writing = RustLessonLibrary.writing(for: id)

        return RustLessonBrief(
            summary: writing?.summary
                ?? "This lesson isolates one Rust idea so you can reason about it before writing a larger program.",
            explanation: writing?.explanation
                ?? "Use the compiler feedback as evidence: read the message, change one assumption, and check again.",
            example: writing.map {
                RustLessonExample(caption: $0.exampleCaption, code: $0.exampleCode)
            },
            objectives: [concept, "Read the relevant compiler evidence", "Make one intentional code change"],
            task: writing?.task
                ?? "Explain \(concept.lowercased()) in your own words, then sketch the smallest code example.",
            success: writing?.success
                ?? "The example compiles and its result matches your explanation.",
            hint: "Start from the ownership and type of each value. Prefer the smallest edit that makes the compiler agree with your intent.",
            systemImage: lessonIcon,
            tint: lessonTint
        )
    }

    private var lessonIcon: String {
        switch exercise {
        case .runnable: "terminal.fill"
        case .borrowDiagnostic: "link.badge.plus"
        case .multiFile: "folder.fill.badge.gearshape"
        case .planned: "book.closed.fill"
        }
    }

    private var lessonTint: Color {
        switch exercise {
        case .runnable: CrabrixTheme.mint
        case .borrowDiagnostic: CrabrixTheme.coral
        case .multiFile: CrabrixTheme.blue
        case .planned: CrabrixTheme.amber
        }
    }
}
