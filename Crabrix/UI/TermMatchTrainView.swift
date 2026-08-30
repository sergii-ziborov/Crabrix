import Combine
import SwiftUI

struct TermMatchTrainView: View {
    private enum Side: Hashable { case description, term }

    private struct Position: Hashable {
        let side: Side
        let id: String
    }

    private struct MatchAnchorKey: PreferenceKey {
        static let defaultValue: [Position: Anchor<CGPoint>] = [:]

        static func reduce(
            value: inout [Position: Anchor<CGPoint>],
            nextValue: () -> [Position: Anchor<CGPoint>]
        ) {
            value.merge(nextValue(), uniquingKeysWith: { _, new in new })
        }
    }

    /// Cards are sized to the tallest one on the board so nothing shifts as
    /// pairs are matched and replaced.
    private struct CardHeightKey: PreferenceKey {
        static let defaultValue: CGFloat = 0

        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var progress: CrabrixProgressStore
    @EnvironmentObject private var vitals: CrabrixVitalsStore
    private let mastery = TopicMasteryStore.shared

    @State private var mode: TermTrainMode?
    @State private var board: [TermTrainPair] = []
    @State private var descriptionOrder: [TermTrainPair] = []
    @State private var termOrder: [TermTrainPair] = []
    @State private var selectedDescription: String?
    @State private var selectedTerm: String?
    @State private var resolvingPair: String?
    @State private var wrongPair: Set<String> = []
    @State private var cardHeight: CGFloat = 76

    @State private var matched = 0
    @State private var mistakes = 0
    @State private var streak = 0
    @State private var bestStreak = 0
    @State private var secondsRemaining = 0
    @State private var secondsElapsed = 0
    @State private var isFinished = false
    @State private var result: TermTrainRunResult?
    /// Snapshotted when the run ends: the root overlay drains the shared queue,
    /// so the summary cannot read it back afterwards.
    @State private var unlockedThisRun: [CrabrixAchievement] = []

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    let onComplete: () -> Void

    /// Starts straight into a mode instead of showing the picker.
    init(startingIn mode: TermTrainMode? = nil, onComplete: @escaping () -> Void) {
        _mode = State(initialValue: mode)
        _board = State(
            initialValue: mode == nil
                ? []
                : TermTrainDeck.board(records: TopicMasteryStore.shared.records)
        )
        self.onComplete = onComplete
    }

    var body: some View {
        VStack(spacing: 0) {
            if let mode {
                header(mode: mode)
                Divider().overlay(CrabrixTheme.border)
                if isFinished {
                    completion
                        .transition(.scale(scale: 0.94).combined(with: .opacity))
                } else {
                    playfield(mode: mode)
                }
            } else {
                modePicker
            }
        }
        .background(CrabrixTheme.background.ignoresSafeArea())
        .foregroundStyle(CrabrixTheme.primary)
        .navigationTitle("Term Train")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // A run started directly (rather than from the picker) still needs
            // its two independently shuffled columns.
            if mode != nil, descriptionOrder.isEmpty, !board.isEmpty {
                descriptionOrder = board.shuffled()
                termOrder = board.shuffled()
                secondsRemaining = mode?.duration ?? 0
            }
        }
        .onReceive(ticker) { _ in tick() }
        .onPreferenceChange(CardHeightKey.self) { height in
            // Only ever grow, so the board never shrinks mid-run.
            if height > cardHeight { cardHeight = height }
        }
    }

    // MARK: - Mode selection

    private var modePicker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("RUST MEMORY TRAIN")
                        .font(.caption.monospaced().bold())
                        .foregroundStyle(CrabrixTheme.mint)
                    Text("Match Rust terms to their meaning")
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                    Text("Choose a description on the left and a term on the right. Correct pairs connect and clear.")
                        .font(.subheadline)
                        .foregroundStyle(CrabrixTheme.muted)
                }

                RatingSummaryCard(store: progress)

                VStack(spacing: 11) {
                    ForEach(TermTrainMode.allCases) { option in
                        Button { start(option) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: option.systemImage)
                                    .font(.title3)
                                    .foregroundStyle(CrabrixTheme.coral)
                                    .frame(width: 46, height: 46)
                                    .background(
                                        CrabrixTheme.coral.opacity(0.13),
                                        in: RoundedRectangle(cornerRadius: 13)
                                    )
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(option.title).font(.headline)
                                    Text(option.detail)
                                        .font(.caption)
                                        .foregroundStyle(CrabrixTheme.muted)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(CrabrixTheme.muted)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .crabrixPanel(cornerRadius: 15)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Playfield

    private func header(mode: TermTrainMode) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Label(mode.title.uppercased(), systemImage: mode.systemImage)
                    .font(.caption.monospaced().bold())
                    .foregroundStyle(CrabrixTheme.mint)
                Spacer()
                if mode == .timed {
                    Label("\(secondsRemaining)s", systemImage: "clock.fill")
                        .font(.caption.monospaced().bold())
                        .foregroundStyle(secondsRemaining <= 10 ? CrabrixTheme.coral : CrabrixTheme.amber)
                        .monospacedDigit()
                }
                Label("\(matched)", systemImage: "checkmark.circle.fill")
                    .font(.caption.monospaced().bold())
                    .foregroundStyle(CrabrixTheme.mint)
                if streak >= 2 {
                    Label("x\(streak)", systemImage: "flame.fill")
                        .font(.caption.monospaced().bold())
                        .foregroundStyle(CrabrixTheme.coral)
                }
            }
            ProgressView(
                value: mode == .timed
                    ? Double(secondsRemaining)
                    : Double(TermTrainDeck.boardSize - board.count),
                total: mode == .timed
                    ? Double(mode.duration ?? 60)
                    : Double(TermTrainDeck.boardSize)
            )
            .tint(mode == .timed ? CrabrixTheme.amber : CrabrixTheme.mint)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(CrabrixTheme.panel)
    }

    private func playfield(mode: TermTrainMode) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                matchingBoard
                Label(
                    wrongPair.isEmpty
                        ? "Correct matches disappear automatically"
                        : (mode == .timed
                            ? "Not a pair — \(mode.mistakePenaltySeconds)s off the clock"
                            : "Those two do not belong together — try again"),
                    systemImage: wrongPair.isEmpty
                        ? "wand.and.stars"
                        : "arrow.counterclockwise.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(wrongPair.isEmpty ? CrabrixTheme.muted : CrabrixTheme.amber)
                .animation(.easeInOut(duration: 0.18), value: wrongPair)

                Button("End run") { finish() }
                    .font(.caption.bold())
                    .buttonStyle(.bordered)
                    .tint(CrabrixTheme.muted)
            }
            .padding(20)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
    }

    private var matchingBoard: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(spacing: 11) {
                columnTitle("DESCRIPTION", alignment: .leading)
                ForEach(descriptionOrder) { pair in
                    matchButton(
                        text: pair.description,
                        pairID: pair.id,
                        side: .description,
                        selected: selectedDescription == pair.id
                    ) {
                        select(pair.id, side: .description)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 11) {
                columnTitle("TERM", alignment: .trailing)
                ForEach(termOrder) { pair in
                    matchButton(
                        text: pair.term,
                        pairID: pair.id,
                        side: .term,
                        selected: selectedTerm == pair.id
                    ) {
                        select(pair.id, side: .term)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .overlayPreferenceValue(MatchAnchorKey.self) { positions in
            GeometryReader { proxy in
                if let selectedDescription,
                   let selectedTerm,
                   let start = positions[Position(side: .description, id: selectedDescription)],
                   let end = positions[Position(side: .term, id: selectedTerm)] {
                    Path { path in
                        path.move(to: proxy[start])
                        path.addCurve(
                            to: proxy[end],
                            control1: CGPoint(x: proxy[start].x + 55, y: proxy[start].y),
                            control2: CGPoint(x: proxy[end].x - 55, y: proxy[end].y)
                        )
                    }
                    .stroke(
                        selectedDescription == selectedTerm ? CrabrixTheme.mint : CrabrixTheme.coral,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [7, 5])
                    )
                    .shadow(
                        color: (selectedDescription == selectedTerm ? CrabrixTheme.mint : CrabrixTheme.coral)
                            .opacity(0.55),
                        radius: 6
                    )
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: board)
        .padding(14)
        .background(CrabrixTheme.editor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(CrabrixTheme.border) }
    }

    private func columnTitle(_ text: String, alignment: Alignment) -> some View {
        Text(text)
            .font(.caption2.monospaced().bold())
            .foregroundStyle(CrabrixTheme.muted)
            .frame(maxWidth: .infinity, alignment: alignment)
            .padding(.horizontal, 3)
    }

    private func matchButton(
        text: String,
        pairID: String,
        side: Side,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let isResolving = resolvingPair == pairID
        let isWrong = wrongPair.contains(pairID)
        let tint = isWrong ? CrabrixTheme.coral : (isResolving ? CrabrixTheme.mint : CrabrixTheme.blue)
        return Button(action: action) {
            HStack(spacing: 8) {
                if side == .term {
                    Circle().fill(selected ? tint : CrabrixTheme.border).frame(width: 8, height: 8)
                }
                Text(text)
                    .font(side == .term ? .system(size: 13, weight: .bold, design: .monospaced) : .caption)
                    .multilineTextAlignment(side == .term ? .trailing : .leading)
                    .frame(maxWidth: .infinity, alignment: side == .term ? .trailing : .leading)
                if side == .description {
                    Circle().fill(selected ? tint : CrabrixTheme.border).frame(width: 8, height: 8)
                }
            }
            .padding(12)
            // Every card reports its natural height; the board adopts the tallest
            // so text never makes the columns jump.
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: CardHeightKey.self, value: proxy.size.height)
                }
            )
            .frame(maxWidth: .infinity, minHeight: cardHeight)
            .background((selected || isResolving || isWrong) ? tint.opacity(0.14) : CrabrixTheme.raised)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .stroke(
                        (selected || isResolving || isWrong) ? tint : CrabrixTheme.border,
                        lineWidth: selected ? 2 : 1
                    )
            }
            .scaleEffect(isResolving ? 0.96 : 1)
            .opacity(isResolving ? 0.78 : 1)
        }
        .buttonStyle(.plain)
        .disabled(resolvingPair != nil)
        .anchorPreference(
            key: MatchAnchorKey.self,
            value: .center,
            transform: { [Position(side: side, id: pairID): $0] }
        )
        .accessibilityLabel("\(side == .term ? "Term" : "Description"): \(text)")
    }

    // MARK: - Completion

    private var completion: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(CrabrixTheme.mint)
                Text(result?.mode == .timed ? "Time is up" : "Connections complete")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)

                if let result {
                    HStack(spacing: 10) {
                        runStat("\(result.matched)", label: "matched", tint: CrabrixTheme.mint)
                        runStat("x\(result.bestStreak)", label: "best streak", tint: CrabrixTheme.coral)
                        runStat(
                            "\(Int((result.accuracy * 100).rounded()))%",
                            label: "accuracy",
                            tint: CrabrixTheme.blue
                        )
                    }
                    Text("+\(result.progressEvent.points) rating")
                        .font(.headline.monospaced())
                        .foregroundStyle(CrabrixTheme.amber)
                }

                if !unlockedThisRun.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("NEW ACHIEVEMENTS")
                            .font(.caption2.monospaced().bold())
                            .foregroundStyle(CrabrixTheme.amber)
                        ForEach(unlockedThisRun) { achievement in
                            AchievementRow(achievement: achievement, state: progress.state)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .crabrixPanel(cornerRadius: 14)
                }

                RatingSummaryCard(store: progress)

                HStack(spacing: 12) {
                    Button("Change mode") { returnToModePicker() }
                        .buttonStyle(.bordered)
                    Button("Train again") { if let mode { start(mode) } }
                        .buttonStyle(.borderedProminent)
                        .tint(CrabrixTheme.coral)
                }
                Button("Back to Learn") { dismiss() }
                    .font(.caption.bold())
                    .buttonStyle(.plain)
                    .foregroundStyle(CrabrixTheme.muted)
            }
            .padding(24)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
    }

    private func runStat(_ value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.title3.monospaced().bold()).foregroundStyle(tint)
            Text(label).font(.caption2).foregroundStyle(CrabrixTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .crabrixPanel(cornerRadius: 12)
    }

    // MARK: - Run control

    private func start(_ selected: TermTrainMode) {
        withAnimation(.easeInOut(duration: 0.22)) {
            mode = selected
            board = TermTrainDeck.board(records: mastery.records)
            descriptionOrder = board.shuffled()
            termOrder = board.shuffled()
            selectedDescription = nil
            selectedTerm = nil
            resolvingPair = nil
            wrongPair = []
            matched = 0
            mistakes = 0
            streak = 0
            bestStreak = 0
            secondsElapsed = 0
            secondsRemaining = selected.duration ?? 0
            isFinished = false
            result = nil
        }
        unlockedThisRun = []
    }

    private func returnToModePicker() {
        withAnimation(.easeInOut(duration: 0.22)) {
            mode = nil
            isFinished = false
            result = nil
        }
        unlockedThisRun = []
    }

    private func recordMastery(pairID: String, correct: Bool) {
        guard let pair = TermTrainDeck.all.first(where: { $0.id == pairID }) else { return }
        mastery.record(topic: pair.topic, correct: correct)
        // Term Train is training: unlimited by design, so it only feeds the
        // flow streak and never spends health.
        vitals.recordTrainingAnswer(correct: correct)
    }

    private func tick() {
        guard let mode, mode == .timed, !isFinished, !board.isEmpty else { return }
        secondsElapsed += 1
        secondsRemaining = max(0, secondsRemaining - 1)
        if secondsRemaining == 0 { finish() }
    }

    private func finish() {
        guard let mode, !isFinished else { return }
        let elapsed = mode == .timed
            ? min(secondsElapsed, mode.duration ?? secondsElapsed)
            : secondsElapsed
        let outcome = TermTrainRunResult(
            mode: mode,
            matched: matched,
            mistakes: mistakes,
            bestStreak: bestStreak,
            elapsedSeconds: max(elapsed, 1)
        )
        result = outcome
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { isFinished = true }
        let before = progress.state.unlockedAchievementIDs
        progress.record(outcome.progressEvent)
        unlockedThisRun = CrabrixAchievementCatalog.all.filter {
            progress.state.unlockedAchievementIDs.contains($0.id) && !before.contains($0.id)
        }
        onComplete()
    }

    private func select(_ id: String, side: Side) {
        guard resolvingPair == nil, !isFinished else { return }
        wrongPair = []
        withAnimation(.easeOut(duration: 0.16)) {
            if side == .description { selectedDescription = id } else { selectedTerm = id }
        }
        guard let selectedDescription, let selectedTerm else { return }

        if selectedDescription == selectedTerm {
            resolvingPair = selectedDescription
            matched += 1
            streak += 1
            bestStreak = max(bestStreak, streak)
            recordMastery(pairID: selectedDescription, correct: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    clear(pairID: selectedDescription)
                    self.selectedDescription = nil
                    self.selectedTerm = nil
                    resolvingPair = nil
                }
            }
        } else {
            mistakes += 1
            streak = 0
            // Both halves of a wrong guess are evidence the learner is unsure.
            recordMastery(pairID: selectedDescription, correct: false)
            recordMastery(pairID: selectedTerm, correct: false)
            if let mode, mode == .timed {
                secondsRemaining = max(0, secondsRemaining - mode.mistakePenaltySeconds)
                if secondsRemaining == 0 { finish() }
            }
            withAnimation(.easeInOut(duration: 0.16)) {
                wrongPair = [selectedDescription, selectedTerm]
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeOut(duration: 0.18)) {
                    self.selectedDescription = nil
                    self.selectedTerm = nil
                    wrongPair = []
                }
            }
        }
    }

    /// Removes a solved pair, refilling the board in timed mode so the run is
    /// bounded by the clock rather than by the deck.
    private func clear(pairID: String) {
        board.removeAll { $0.id == pairID }
        descriptionOrder.removeAll { $0.id == pairID }
        termOrder.removeAll { $0.id == pairID }

        if mode == .timed,
           let replacement = TermTrainDeck.replacement(
               excluding: Set(board.map(\.id)),
               records: mastery.records
           ) {
            board.append(replacement)
            descriptionOrder.insert(replacement, at: Int.random(in: 0...descriptionOrder.count))
            termOrder.insert(replacement, at: Int.random(in: 0...termOrder.count))
        } else if board.isEmpty {
            finish()
        }
    }
}
