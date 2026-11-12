import SwiftUI

struct FlashcardsView: View {
    let completedLessonIDs: Set<String>
    let onComplete: () -> Void

    @EnvironmentObject private var academy: AcademyContentStore
    @EnvironmentObject private var backup: LearningBackupCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var database: FlashcardReviewDatabase?
    @State private var cards: [Flashcard] = []
    @State private var records: [String: FlashcardReviewRecord] = [:]
    @State private var queue: [Flashcard] = []
    @State private var index = 0
    @State private var revealed = false
    @State private var selectedGrade: FlashcardGrade?
    @State private var attemptID = UUID().uuidString
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var hasStarted = false
    @State private var didFinish = false
    @State private var reviewed = 0
    @State private var remembered = 0
    @State private var dragOffset: CGFloat = 0
    @State private var errorMessage: String?

    private var current: Flashcard? { queue.indices.contains(index) ? queue[index] : nil }
    private var eligible: [Flashcard] { FlashcardDeck.learned(cards, completedLessonIDs: completedLessonIDs) }
    private var dueCount: Int { FlashcardReviewQueue.due(eligible, records: records, now: Date()).count }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 18) {
                    if isLoading {
                        ProgressView("Preparing your cards…").padding(.top, 60)
                    } else if !hasStarted || current == nil {
                        overview
                    } else if let card = current {
                        sessionHeader(card)
                        cardFaces(card)
                            .frame(height: max(240, min(540, geometry.size.height - 140)))
                            .offset(x: reduceMotion ? 0 : dragOffset)
                            .simultaneousGesture(swipe)
                    }
                    if let errorMessage {
                        Text(errorMessage).font(.callout).foregroundStyle(CrabrixTheme.coral)
                            .accessibilityIdentifier("flashcards-save-error")
                    }
                }
                .padding(20)
                .padding(.bottom, hasStarted && current != nil ? 0 : 60)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if hasStarted, current != nil {
                reviewActions
            }
        }
        .foregroundStyle(CrabrixTheme.primary)
        .background(CrabrixTheme.background.ignoresSafeArea())
        .navigationTitle("Flashcards")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    /// Keep grading and Next above the home indicator and native tab chrome,
    /// including the shorter open-Duo viewport. Long answers scroll independently.
    private var reviewActions: some View {
        VStack(spacing: 12) {
            gradeButtons
            if revealed || selectedGrade != nil {
                Button(action: next) {
                    Label(index + 1 == queue.count ? "Finish review" : "Next card", systemImage: "arrow.right")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent).tint(CrabrixTheme.blue)
                .foregroundStyle(CrabrixTheme.onAccent)
                .disabled(selectedGrade == nil || isSaving)
                .accessibilityIdentifier("flashcards-next")
            } else {
                Text("Swipe left: don’t know · right: easy")
                    .font(.caption).foregroundStyle(CrabrixTheme.muted)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
        .background(CrabrixTheme.background)
    }

    private var overview: some View {
        VStack(spacing: 20) {
            Image(systemName: "rectangle.stack.fill")
                .font(.system(size: 54)).foregroundStyle(CrabrixTheme.coral)
                .padding(.top, 28).accessibilityHidden(true)
            Text(didFinish ? "A little stronger, card by card." : "Keep what you’ve learned.")
                .font(.title2.bold()).multilineTextAlignment(.center)
            if didFinish {
                HStack(spacing: 28) {
                    summaryStat("Reviewed", reviewed)
                    summaryStat("Felt easy", remembered)
                }
            }
            if eligible.isEmpty {
                Text("Finish a lesson to add its questions to your deck. Your cards come from the courses you keep on this device.")
                    .foregroundStyle(CrabrixTheme.muted).multilineTextAlignment(.center)
            } else {
                Text("Think of the answer, then choose Don’t know, Hard or Easy. The card flips so you can compare. Read at your own pace before continuing.")
                    .foregroundStyle(CrabrixTheme.muted).multilineTextAlignment(.center)
                Text("\(eligible.count) cards from your completed lessons · \(dueCount) due")
                    .font(.caption.monospaced()).foregroundStyle(CrabrixTheme.muted)
                if dueCount == 0 {
                    Label("You’re caught up for now.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(CrabrixTheme.mint)
                    Text("Cards you find difficult return sooner. Come back when the next review is due.")
                        .font(.callout).foregroundStyle(CrabrixTheme.muted).multilineTextAlignment(.center)
                } else {
                    Button(action: start) {
                        Label(didFinish ? "Review more" : "Start review", systemImage: "play.fill")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent).tint(CrabrixTheme.coral)
                    .foregroundStyle(CrabrixTheme.onAccent)
                    .disabled(database == nil).accessibilityIdentifier("flashcards-start")
                }
            }
            if database == nil {
                Button("Try again") { Task { await load() } }.buttonStyle(.bordered)
            }
            Text("Your review history is saved on this device.")
                .font(.caption).foregroundStyle(CrabrixTheme.muted).multilineTextAlignment(.center)
        }
    }

    private func summaryStat(_ title: String, _ value: Int) -> some View {
        VStack(spacing: 4) {
            Text("\(value)").font(.title.bold()).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(CrabrixTheme.muted)
        }
    }

    private func sessionHeader(_ card: Flashcard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("REVIEW", systemImage: "rectangle.stack")
                    .font(.caption.monospaced().bold()).foregroundStyle(CrabrixTheme.coral)
                Spacer()
                Text("\(index + 1) / \(queue.count)").font(.caption.monospaced()).monospacedDigit()
            }
            ProgressView(value: Double(index), total: Double(max(1, queue.count))).tint(CrabrixTheme.coral)
            Text(card.lessonTitle).font(.headline)
            Text(card.courseTitle).font(.caption).foregroundStyle(CrabrixTheme.muted)
        }
    }

    private func cardFaces(_ card: Flashcard) -> some View {
        ZStack {
            face(card, back: false)
                .modifier(FlashcardFaceRotation(angle: reduceMotion ? 0 : (revealed ? 180 : 0), back: false))
                .opacity(reduceMotion && revealed ? 0 : 1)
                .accessibilityHidden(revealed)
                .allowsHitTesting(!revealed)
            face(card, back: true)
                .modifier(FlashcardFaceRotation(angle: reduceMotion ? 180 : (revealed ? 180 : 0), back: true))
                .opacity(reduceMotion && !revealed ? 0 : 1)
                .accessibilityHidden(!revealed)
                .allowsHitTesting(revealed)
        }
        .animation(reduceMotion ? .easeOut(duration: 0.18) : .easeInOut(duration: 0.48), value: revealed)
        .accessibilityIdentifier("flashcard-\(revealed ? "answer" : "question")")
    }

    private func face(_ card: Flashcard, back: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: back ? "sparkles" : "questionmark")
                    .foregroundStyle(back ? CrabrixTheme.mint : CrabrixTheme.coral)
                Text(back ? "THE IDEA" : "THINK FIRST").font(.caption.monospaced().bold())
                Spacer()
                Image(systemName: "rectangle.on.rectangle")
            }.foregroundStyle(CrabrixTheme.primary)
            Divider().overlay(CrabrixTheme.border)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if back {
                        Text(LocalizedStringKey(card.answer)).font(.title3)
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    } else {
                        Text(LocalizedStringKey(card.prompt)).font(.title2.bold())
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !back, let code = card.code {
                        Text(code).font(.caption.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14).background(CrabrixTheme.background, in: CrabrixCardShape(cornerRadius: 12))
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if !back {
                Button("Show answer") { revealed = true }
                    .font(.callout.bold()).buttonStyle(.bordered)
                    .accessibilityIdentifier("flashcards-reveal")
            } else {
                if let grade = selectedGrade {
                    Label(reviewHint(grade), systemImage: grade == .again ? "arrow.clockwise" : "calendar")
                        .font(.caption).foregroundStyle(CrabrixTheme.muted)
                }
                Button("View question again") { revealed = false }.font(.caption).buttonStyle(.bordered)
            }
        }
        .padding(22).frame(maxWidth: .infinity, maxHeight: .infinity)
        .crabrixPanel(cornerRadius: 24)
    }

    private var gradeButtons: some View {
        HStack(spacing: 8) {
            ForEach(FlashcardGrade.allCases, id: \.rawValue) { grade in
                Button { save(grade) } label: {
                    VStack(spacing: 6) {
                        Image(systemName: grade == .again ? "arrow.counterclockwise" : (grade == .hard ? "circle.lefthalf.filled" : "checkmark"))
                        Text(grade.title).font(.caption.bold()).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(selectedGrade == grade ? CrabrixTheme.onAccent : CrabrixTheme.primary)
                    .background((selectedGrade == grade ? tint(grade) : tint(grade).opacity(0.12)), in: CrabrixCardShape(cornerRadius: 13))
                }
                .buttonStyle(.plain).disabled(isSaving || selectedGrade != nil)
                .accessibilityLabel(grade == .hard ? "Hard to remember" : grade.title)
                .accessibilityIdentifier("flashcards-grade-\(grade.rawValue)")
            }
        }
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                guard !revealed, !isSaving, selectedGrade == nil, abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                dragOffset = max(-32, min(32, value.translation.width / 5))
            }
            .onEnded { value in
                withAnimation(.easeOut(duration: 0.15)) { dragOffset = 0 }
                guard !revealed, !isSaving, selectedGrade == nil, abs(value.translation.width) > 80,
                      abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                save(value.translation.width < 0 ? .again : .easy)
            }
    }

    private func tint(_ grade: FlashcardGrade) -> Color {
        switch grade {
        case .again: CrabrixTheme.coral
        case .hard: CrabrixTheme.amber
        case .easy: CrabrixTheme.mint
        }
    }

    private func reviewHint(_ grade: FlashcardGrade) -> String {
        guard let current, let next = records[current.id]?.mastery.dueAt else { return "Saved for your next review" }
        if grade == .again { return "We’ll revisit this in about 10 minutes" }
        return "Next review \(next.formatted(date: .abbreviated, time: .omitted))"
    }

    private func load() async {
        guard database == nil else { return }
        isLoading = true
        errorMessage = nil
        do {
            await academy.prepare()
            guard let repository = academy.repository else { isLoading = false; return }
            let loaded = try await Task.detached(priority: .utility) {
                let database = try FlashcardReviewDatabase(url: FlashcardReviewDatabase.defaultURL())
                return (database, try database.records(), FlashcardDeck.cards(from: repository))
            }.value
            database = loaded.0
            records = loaded.1
            cards = loaded.2
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    private func start() {
        var generator = SystemRandomNumberGenerator()
        queue = FlashcardReviewQueue.session(from: eligible, records: records, now: Date(), using: &generator)
        index = 0
        reviewed = 0
        remembered = 0
        didFinish = false
        hasStarted = !queue.isEmpty
        resetCard()
    }

    private func save(_ grade: FlashcardGrade) {
        guard let card = current, let database, !isSaving, selectedGrade == nil else { return }
        isSaving = true
        backup.beginReviewWrite()
        errorMessage = nil
        let eventID = attemptID
        Task {
            defer { backup.endReviewWrite() }
            do {
                let record = try await Task.detached(priority: .utility) {
                    try database.review(card: card, grade: grade, eventID: eventID, now: Date())
                }.value
                records[card.id] = record
                NotificationCenter.default.post(name: .flashcardReviewSaved, object: nil)
                selectedGrade = grade
                reviewed += 1
                if grade == .easy { remembered += 1 }
                revealed = true
            } catch { errorMessage = error.localizedDescription }
            isSaving = false
        }
    }

    private func next() {
        guard selectedGrade != nil, !isSaving else { return }
        if index + 1 == queue.count {
            didFinish = true
            hasStarted = false
            onComplete()
        } else {
            index += 1
            resetCard()
        }
    }

    private func resetCard() {
        // Reset without replaying the preceding card's reverse animation.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { revealed = false }
        selectedGrade = nil
        attemptID = UUID().uuidString
        dragOffset = 0
    }
}

private nonisolated struct FlashcardFaceRotation: AnimatableModifier {
    var angle: Double
    let back: Bool
    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }
    func body(content: Content) -> some View {
        content
            .opacity((angle < 90) != back ? 1 : 0)
            .rotation3DEffect(.degrees(angle + (back ? 180 : 0)), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
    }
}
