import SwiftUI

struct QuickPracticeView: View {
    @EnvironmentObject private var academy: AcademyContentStore
    @EnvironmentObject private var progress: CrabrixProgressStore
    @State private var didAward = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var step = 0
    @State private var score = 0
    @State private var solvedQuestionIDs: Set<String> = []
    /// Drawn once per session from the whole curriculum, weighted by mastery.
    @State private var questions: [RustQuestion] = []
    private let mastery = TopicMasteryStore.shared

    /// Two hand-built drills plus the generated questions.
    private var total: Int { questions.count + 2 }

    var body: some View {
        VStack(spacing: 0) {
            practiceHeader
            Divider().overlay(CrabrixTheme.border)

            Group {
                switch step {
                case 0:
                    MatchPractice { passed in advance(passed, from: 0) }
                case 1:
                    ArrangeCodePractice { passed in advance(passed, from: 1) }
                case let index where index - 2 < questions.count:
                    let question = questions[index - 2]
                    LessonQuestionPractice(question: question) { passed in
                        mastery.record(topic: question.topic, correct: passed)
                        advance(passed, from: index)
                    }
                    .id(question.topic)
                default:
                    completion
                }
            }
            .frame(maxWidth: 760, maxHeight: .infinity)
            .frame(maxWidth: .infinity)
        }
        .background(CrabrixTheme.background.ignoresSafeArea())
        .foregroundStyle(CrabrixTheme.primary)
        .overlay {
            if academy.repository == nil {
                if let error = academy.errorMessage {
                    ContentUnavailableView("Courses unavailable", systemImage: "books.vertical",
                                           description: Text(error))
                        .background(CrabrixTheme.background)
                } else {
                    ProgressView("Preparing installed courses…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(CrabrixTheme.background)
                }
            }
        }
        .navigationTitle("Quick Practice")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard questions.isEmpty else { return }
            await academy.prepare()
            guard let repository = academy.repository else { return }
            questions = RustQuestionBank.round(
                count: 4, from: repository.practiceQuestions(), records: mastery.records
            )
        }
    }

    private var practiceHeader: some View {
        VStack(alignment: .leading, spacing: verticalSizeClass == .compact ? 4 : 10) {
            HStack {
                Label("5-MINUTE RUST", systemImage: "bolt.fill")
                    .font(.caption.monospaced().bold())
                    .foregroundStyle(CrabrixTheme.amber)
                Spacer()
                Text(step < total ? "\(step + 1) / \(total)" : "DONE")
                    .font(.caption.monospaced().bold())
                    .foregroundStyle(CrabrixTheme.muted)
            }
            ProgressView(value: Double(min(step, total)), total: Double(total))
                .tint(CrabrixTheme.mint)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, verticalSizeClass == .compact ? 5 : 14)
        .background(CrabrixTheme.panel)
    }

    private var completion: some View {
        VStack(spacing: 18) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 54))
                .foregroundStyle(CrabrixTheme.amber)
            Text("Practice complete")
                .font(.largeTitle.bold())
            Text("\(score) of \(total) solved on the first check")
                .foregroundStyle(CrabrixTheme.muted)
            RatingSummaryCard(store: progress)
            Button {
                dismiss()
            } label: {
                Label("Back to Courses", systemImage: "map.fill")
                    .frame(minWidth: 220)
            }
            .buttonStyle(.borderedProminent)
            .tint(CrabrixTheme.coral)
        }
        .padding(24)
        .frame(maxWidth: 620)
        .onAppear {
            // A question is paid once, even across new sessions and relaunches.
            guard !didAward else { return }
            didAward = true
            for questionID in solvedQuestionIDs {
                progress.record(.practicePassed, eventKey: "practice:\(questionID):first-completion")
            }
        }
    }

    private func advance(_ passed: Bool, from expectedStep: Int) {
        guard step == expectedStep, step < total else { return }
        if passed {
            score += 1
            let questionID = step < 2
                ? (step == 0 ? "match-lifetime" : "arrange-hello")
                : questions[step - 2].id
            solvedQuestionIDs.insert(questionID)
        }
        withAnimation(.easeInOut(duration: 0.22)) { step += 1 }
    }
}

private struct MatchPractice: View {
    @State private var selection: String?
    private let answers = [
        "Copies every value automatically",
        "Allows many writers at once",
        "Describes when a reference is valid",
        "Allocates the value on the heap",
    ]
    let onNext: (Bool) -> Void

    var body: some View {
        PracticeCard(
            eyebrow: "MATCH THE MEANING",
            title: "What does a lifetime describe?",
            detail: "Choose the definition that belongs to the Rust concept."
        ) {
            VStack(spacing: 9) {
                ForEach(answers, id: \.self) { answer in
                    Button { selection = answer } label: {
                        HStack {
                            Image(systemName: selection == answer ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selection == answer ? CrabrixTheme.blue : CrabrixTheme.muted)
                            Text(answer)
                            Spacer()
                        }
                        .padding(13)
                        .background(selection == answer ? CrabrixTheme.blue.opacity(0.12) : CrabrixTheme.raised)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            PracticeFeedback(
                isVisible: selection != nil,
                isCorrect: selection == answers[2],
                correctText: "Exactly — lifetimes connect reference validity.",
                wrongText: "Think about references and how long they remain valid."
            )
            Button("Continue") { onNext(selection == answers[2]) }
                .buttonStyle(.borderedProminent)
                .tint(CrabrixTheme.coral)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .disabled(selection == nil)
        }
    }
}

private struct ArrangeCodePractice: View {
    private struct CodeLine: Identifiable, Equatable {
        let id: Int
        let text: String
    }

    @State private var lines = [
        CodeLine(id: 2, text: "println!(\"{message}\");"),
        CodeLine(id: 0, text: "fn main() {"),
        CodeLine(id: 3, text: "}"),
        CodeLine(id: 1, text: "    let message = \"Hello, Rust!\";"),
    ]
    @State private var checked = false
    @State private var correct = false
    let onNext: (Bool) -> Void

    @ScaledMetric(relativeTo: .body) private var codeFontSize = 13

    var body: some View {
        GeometryReader { available in
            let compact = available.size.height < 560
            ViewThatFits(in: .vertical) {
                exercise(compact: compact, wide: available.size.width > 600 && available.size.height < 420)
                    .fixedSize(horizontal: false, vertical: true)
                // Large accessibility text may need one page scroll. The code
                // list itself never scrolls, so dragging cannot move two layers.
                ScrollView {
                    exercise(compact: compact, wide: false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .accessibilityIdentifier("arrange-code-exercise")
    }

    private func exercise(compact: Bool, wide: Bool) -> some View {
        let gap: CGFloat = compact ? 10 : 16
        return VStack(alignment: .leading, spacing: gap) {
            if wide {
                HStack(alignment: .top, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        instructions(compact: true)
                        feedback
                        checkButton
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    codeLines(compact: true)
                        .frame(maxWidth: .infinity)
                }
            } else {
                instructions(compact: compact)
                codeLines(compact: false)
                feedback
                checkButton
            }
        }
        .padding(wide ? 10 : (compact ? 16 : 22))
    }

    private var feedback: some View {
        PracticeFeedback(
            isVisible: checked,
            isCorrect: correct,
            correctText: "Perfect — function, binding, output, closing brace.",
            wrongText: "Start with fn main(), then the binding, then println!."
        )
    }

    private var checkButton: some View {
        Button(checked && correct ? "Finish" : "Check order") {
            if checked && correct {
                onNext(true)
            } else {
                correct = lines.map(\.id) == [0, 1, 2, 3]
                checked = true
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(checked && correct ? CrabrixTheme.mint : CrabrixTheme.coral)
        .frame(minHeight: 44)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityIdentifier("arrange-check-order")
    }

    private func instructions(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            Text("ARRANGE THE CODE")
                .font(.caption.monospaced().bold())
                .foregroundStyle(CrabrixTheme.coral)
            Text("Build a runnable program")
                .font(compact ? .title3.bold() : .title2.bold())
            Text("Drag the handles to reorder the lines, then check your answer.")
                .font(.subheadline)
                .foregroundStyle(CrabrixTheme.muted)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func codeLines(compact: Bool) -> some View {
        let rowHeight = max(compact ? 44 : 52, ceil(codeFontSize * (compact ? 3.3 : 3.8)))
        return List {
            ForEach(lines) { line in
                Text(line.text)
                    .font(.system(size: codeFontSize, design: .monospaced))
                    .foregroundStyle(CrabrixTheme.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: rowHeight)
                    .padding(.leading, 14)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 12))
                    .listRowBackground(CrabrixTheme.raised)
                    .accessibilityIdentifier("arrange-code-line-\(line.id)")
            }
            .onMove { source, destination in
                lines.move(fromOffsets: source, toOffset: destination)
                checked = false
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, .constant(.active))
        .environment(\.defaultMinListRowHeight, 0)
        .scrollContentBackground(.hidden)
        .contentMargins(.all, 0, for: .scrollContent)
        .scrollDisabled(true)
        .frame(height: rowHeight * CGFloat(lines.count))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier("arrange-code-lines")
    }

}

private struct PracticeCard<Content: View>: View {
    let eyebrow: String
    let title: String
    let detail: String
    @ViewBuilder let content: () -> Content

    init(
        eyebrow: String,
        title: String,
        detail: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.detail = detail
        self.content = content
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(eyebrow)
                    .font(.caption.monospaced().bold())
                    .foregroundStyle(CrabrixTheme.coral)
                Text(title)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                Text(detail)
                    .foregroundStyle(CrabrixTheme.muted)
                content()
            }
            .padding(22)
        }
    }
}

private struct PracticeFeedback: View {
    let isVisible: Bool
    let isCorrect: Bool
    let correctText: String
    let wrongText: String

    var body: some View {
        if isVisible {
            Label(
                isCorrect ? correctText : wrongText,
                systemImage: isCorrect ? "checkmark.circle.fill" : "lightbulb.fill"
            )
            .font(.caption)
            .foregroundStyle(isCorrect ? CrabrixTheme.mint : CrabrixTheme.amber)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((isCorrect ? CrabrixTheme.mint : CrabrixTheme.amber).opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 11))
        }
    }
}

/// A generated question from the curriculum, so practice grows with the lessons.
private struct LessonQuestionPractice: View {
    let question: RustQuestion
    let onFinish: (Bool) -> Void

    @State private var selection: Int?
    @State private var checked = false

    var body: some View {
        PracticeCard(
            eyebrow: question.lessonTitle.uppercased(),
            title: question.prompt,
            detail: "Pick the answer that matches how Rust actually behaves."
        ) {
            HighlightedCodeBlock(code: question.code, fontSize: 13)

            VStack(spacing: 9) {
                ForEach(question.answers.indices, id: \.self) { index in
                    Button {
                        guard !checked else { return }
                        selection = index
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: selection == index
                                  ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(selection == index
                                                 ? CrabrixTheme.blue : CrabrixTheme.muted)
                            Text(question.answers[index])
                                .font(.subheadline)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(13)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            selection == index
                                ? CrabrixTheme.blue.opacity(0.1) : CrabrixTheme.raised,
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(selection == index ? CrabrixTheme.blue : CrabrixTheme.border)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(checked)
                }
            }

            PracticeFeedback(
                isVisible: checked,
                isCorrect: selection == question.correctAnswer,
                correctText: question.feedback,
                wrongText: "Not quite — \(question.answers[question.correctAnswer])."
            )

            Button(checked ? "Continue" : "Check answer") {
                if checked {
                    onFinish(selection == question.correctAnswer)
                } else {
                    checked = true
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(CrabrixTheme.coral)
            .disabled(selection == nil)
            .frame(maxWidth: .infinity)
        }
    }
}
