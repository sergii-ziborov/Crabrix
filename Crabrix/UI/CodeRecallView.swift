import SwiftUI

/// Code Recall: memorise a snippet while it is visible, then rebuild it.
///
/// Distinct from Term Train, which is a matching game with everything on screen.
/// Here the snippet disappears, so the round is a memory test — and because the
/// snippets come from lesson content, the thing being memorised is real Rust.
struct CodeRecallView: View {
    let onComplete: () -> Void

    @EnvironmentObject private var progress: CrabrixProgressStore
    @EnvironmentObject private var vitals: CrabrixVitalsStore
    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable {
        case idle
        case studying
        case rebuilding
        case roundCleared
        case finished
    }

    @State private var phase: Phase = .idle
    @State private var snippet: CodeRecallSnippet?
    @State private var level = CodeRecallDeck.minimumLines
    @State private var target: [String] = []
    @State private var tiles: [String] = []
    @State private var placed: [String] = []
    @State private var wrongTile: String?
    @State private var usedTopics: Set<String> = []
    @State private var roundsCleared = 0
    @State private var linesRecalled = 0
    @State private var bestLevel = 0
    @State private var secondsLeft = 0
    @State private var unlockedThisRun: [CrabrixAchievement] = []

    private let mastery = TopicMasteryStore.shared
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Study time grows with the snippet, but sublinearly: the game has to get
    /// harder as the window widens or the level number means nothing.
    private var studySeconds: Int { 3 + Int((Double(level) * 0.8).rounded()) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(CrabrixTheme.border)
            content
                .frame(maxWidth: 720, maxHeight: .infinity)
                .frame(maxWidth: .infinity)
        }
        .background(CrabrixTheme.background.ignoresSafeArea())
        .foregroundStyle(CrabrixTheme.primary)
        .navigationTitle("Code Recall")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(timer) { _ in tick() }
    }

    // MARK: - Chrome

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("MEMORY DRILL", systemImage: "brain.head.profile")
                    .font(.caption.monospaced().bold())
                    .foregroundStyle(CrabrixTheme.blue)
                Spacer()
                Text("LEVEL \(level)")
                    .font(.caption.monospaced().bold())
                    .foregroundStyle(CrabrixTheme.amber)
                    .monospacedDigit()
            }
            HStack(spacing: 14) {
                stat("Cleared", "\(roundsCleared)")
                stat("Best", "\(max(bestLevel, 0))")
                stat("Lines", "\(linesRecalled)")
                Spacer(minLength: 0)
                Label("Free", systemImage: "infinity")
                    .font(.caption2.monospaced().bold())
                    .foregroundStyle(CrabrixTheme.mint)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        .background(CrabrixTheme.panel.opacity(0.96))
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(CrabrixTheme.muted)
            Text(value)
                .font(.caption.monospaced().bold())
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle: intro
        case .studying: studyBoard
        case .rebuilding: rebuildBoard
        case .roundCleared: clearedBoard
        case .finished: summary
        }
    }

    // MARK: - Phases

    private var intro: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "eye.trianglebadge.exclamationmark.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(CrabrixTheme.blue)
                    .padding(.top, 34)
                Text("Rebuild the snippet from memory")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text("""
                A short piece of real Rust appears for a few seconds. When it \
                disappears, put its lines back in order. Every cleared round adds \
                another line, and the snippets come straight from the lessons.
                """)
                .font(.subheadline)
                .foregroundStyle(CrabrixTheme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

                Label("Training — never costs health or energy", systemImage: "infinity")
                    .font(.caption.bold())
                    .foregroundStyle(CrabrixTheme.mint)

                Button(action: startRun) {
                    Label("Start", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .font(.headline)
                .buttonStyle(.borderedProminent)
                .tint(CrabrixTheme.coral)
            }
            .padding(24)
        }
    }

    private var studyBoard: some View {
        VStack(spacing: 16) {
            HStack {
                Label(snippet?.title ?? "", systemImage: "text.book.closed.fill")
                    .font(.caption.bold())
                    .foregroundStyle(CrabrixTheme.muted)
                Spacer()
                Label("\(secondsLeft)s", systemImage: "timer")
                    .font(.headline.monospaced())
                    .foregroundStyle(secondsLeft <= 2 ? CrabrixTheme.coral : CrabrixTheme.amber)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            HighlightedCodeBlock(code: target.joined(separator: "\n"), fontSize: 15)

            ProgressView(value: Double(secondsLeft), total: Double(studySeconds))
                .tint(CrabrixTheme.amber)

            Text("Memorise the order.")
                .font(.caption)
                .foregroundStyle(CrabrixTheme.muted)

            Button("I have it — hide it now") { beginRebuild() }
                .buttonStyle(.bordered)
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private var rebuildBoard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Tap the lines in their original order")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(placed.enumerated()), id: \.offset) { index, line in
                        placedRow(index: index, line: line)
                    }
                    ForEach(placed.count..<target.count, id: \.self) { index in
                        emptyRow(index: index)
                    }
                }

                Divider().overlay(CrabrixTheme.border)

                VStack(spacing: 9) {
                    ForEach(tiles, id: \.self) { line in
                        tileButton(line)
                    }
                }
            }
            .padding(20)
        }
    }

    private var clearedBoard: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundStyle(CrabrixTheme.mint)
            Text("Level \(level) cleared")
                .font(.title2.bold())
            Text("\(target.count) lines, in order, from memory.")
                .font(.subheadline)
                .foregroundStyle(CrabrixTheme.muted)
            HighlightedCodeBlock(code: target.joined(separator: "\n"), fontSize: 14)
            HStack(spacing: 12) {
                Button("Stop here") { finish() }
                    .buttonStyle(.bordered)
                Button {
                    level += 1
                    nextRound()
                } label: {
                    Label("Next level", systemImage: "arrow.right")
                }
                .buttonStyle(.borderedProminent)
                .tint(CrabrixTheme.mint)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private var summary: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: bestLevel >= 6 ? "crown.fill" : "brain.head.profile")
                    .font(.system(size: 52))
                    .foregroundStyle(CrabrixTheme.amber)
                    .padding(.top, 24)
                Text(bestLevel > 0 ? "Best: \(bestLevel) lines" : "Round over")
                    .font(.title.bold())
                Text("\(roundsCleared) round\(roundsCleared == 1 ? "" : "s") cleared · \(linesRecalled) lines recalled")
                    .font(.subheadline)
                    .foregroundStyle(CrabrixTheme.muted)

                Text("+\(CodeRecallRunResult(bestLevel: bestLevel, roundsCleared: roundsCleared, linesRecalled: linesRecalled).progressEvent.points) rating")
                    .font(.headline.monospaced())
                    .foregroundStyle(CrabrixTheme.amber)

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

                HStack(spacing: 12) {
                    Button("Done") { dismiss() }
                        .buttonStyle(.bordered)
                    Button {
                        startRun()
                    } label: {
                        Label("Play again", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(CrabrixTheme.coral)
                }
            }
            .padding(24)
        }
    }

    // MARK: - Rows

    private func placedRow(index: Int, line: String) -> some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.caption2.monospaced().bold())
                .foregroundStyle(CrabrixTheme.background)
                .frame(width: 22, height: 22)
                .background(CrabrixTheme.mint, in: Circle())
            Text(SyntaxTheme.attributedString(line, filePath: "snippet.rs", fontSize: 13))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CrabrixTheme.mint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }

    private func emptyRow(index: Int) -> some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.caption2.monospaced().bold())
                .foregroundStyle(CrabrixTheme.muted)
                .frame(width: 22, height: 22)
                .background(CrabrixTheme.border, in: Circle())
            Text("—")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(CrabrixTheme.muted)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CrabrixTheme.panel.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func tileButton(_ line: String) -> some View {
        Button {
            place(line)
        } label: {
            HStack {
                Text(SyntaxTheme.attributedString(line, filePath: "snippet.rs", fontSize: 13))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                wrongTile == line ? CrabrixTheme.coral.opacity(0.18) : CrabrixTheme.raised,
                in: RoundedRectangle(cornerRadius: 11)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .stroke(wrongTile == line ? CrabrixTheme.coral : CrabrixTheme.border)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Run control

    private func startRun() {
        level = CodeRecallDeck.minimumLines
        roundsCleared = 0
        linesRecalled = 0
        bestLevel = 0
        usedTopics = []
        unlockedThisRun = []
        nextRound()
    }

    private func nextRound() {
        guard let picked = CodeRecallDeck.next(records: mastery.records, excluding: usedTopics) else {
            finish()
            return
        }
        usedTopics.insert(picked.topic)
        snippet = picked
        target = picked.window(size: level)
        // A snippet shorter than the level caps the window, so the label has to
        // follow the window rather than the other way round.
        level = target.count
        tiles = target.shuffled()
        placed = []
        wrongTile = nil
        secondsLeft = studySeconds
        withAnimation(.easeInOut(duration: 0.2)) { phase = .studying }
    }

    private func beginRebuild() {
        tiles = target.shuffled()
        placed = []
        withAnimation(.easeInOut(duration: 0.25)) { phase = .rebuilding }
    }

    private func tick() {
        guard phase == .studying else { return }
        guard secondsLeft > 1 else {
            beginRebuild()
            return
        }
        secondsLeft -= 1
    }

    private func place(_ line: String) {
        guard phase == .rebuilding else { return }
        let expected = target[placed.count]
        guard line == expected else {
            recordTopic(correct: false)
            withAnimation(.easeInOut(duration: 0.15)) { wrongTile = line }
            finish()
            return
        }
        withAnimation(.easeOut(duration: 0.18)) {
            placed.append(line)
            tiles.removeAll { $0 == line }
        }
        linesRecalled += 1
        guard placed.count == target.count else { return }
        roundsCleared += 1
        bestLevel = max(bestLevel, target.count)
        recordTopic(correct: true)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { phase = .roundCleared }
    }

    private func recordTopic(correct: Bool) {
        guard let snippet else { return }
        mastery.record(topic: snippet.topic, correct: correct)
        // Training: it feeds the flow streak and never spends anything.
        vitals.recordTrainingAnswer(correct: correct)
    }

    private func finish() {
        let outcome = CodeRecallRunResult(
            bestLevel: bestLevel,
            roundsCleared: roundsCleared,
            linesRecalled: linesRecalled
        )
        let before = progress.state.unlockedAchievementIDs
        progress.record(outcome.progressEvent)
        unlockedThisRun = CrabrixAchievementCatalog.all.filter {
            progress.state.unlockedAchievementIDs.contains($0.id) && !before.contains($0.id)
        }
        withAnimation(.easeInOut(duration: 0.25)) { phase = .finished }
        onComplete()
    }
}
