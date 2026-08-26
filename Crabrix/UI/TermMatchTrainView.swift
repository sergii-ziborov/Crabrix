import SwiftUI

struct TermMatchTrainView: View {
    private struct Pair: Identifiable, Equatable {
        let id: String
        let term: String
        let description: String

        static let lesson: [Pair] = [
            Pair(id: "ownership", term: "Ownership", description: "One value has one owner; dropping the owner releases it."),
            Pair(id: "borrow", term: "Borrow", description: "Use a value through a reference without taking ownership."),
            Pair(id: "mutable", term: "mut", description: "Explicitly allows a binding or reference to change a value."),
            Pair(id: "result", term: "Result<T, E>", description: "Represents either a successful value or a recoverable error."),
            Pair(id: "trait", term: "Trait", description: "Defines shared behavior that multiple types can implement."),
        ]
    }

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

    @Environment(\.dismiss) private var dismiss
    @State private var descriptionOrder = Pair.lesson.shuffled()
    @State private var termOrder = Pair.lesson.shuffled()
    @State private var remaining = Set(Pair.lesson.map(\.id))
    @State private var selectedDescription: String?
    @State private var selectedTerm: String?
    @State private var resolvingPair: String?
    @State private var wrongPair: Set<String> = []
    @State private var score = 0
    @State private var didReportCompletion = false

    let onComplete: () -> Void

    private var completed: Int { Pair.lesson.count - remaining.count }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(CrabrixTheme.border)

            if remaining.isEmpty {
                completion
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("CONNECT THE PAIRS")
                                .font(.caption.monospaced().bold())
                                .foregroundStyle(CrabrixTheme.coral)
                            Text("Match Rust terms to their meaning")
                                .font(.system(size: 27, weight: .bold, design: .rounded))
                            Text("Choose one description on the left and one term on the right. A correct pair connects, then clears from the board.")
                                .font(.subheadline)
                                .foregroundStyle(CrabrixTheme.muted)
                        }

                        matchingBoard

                        Label(
                            wrongPair.isEmpty ? "Correct matches disappear automatically" : "Those two do not belong together — try again",
                            systemImage: wrongPair.isEmpty ? "wand.and.stars" : "arrow.counterclockwise.circle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(wrongPair.isEmpty ? CrabrixTheme.muted : CrabrixTheme.amber)
                        .animation(.easeInOut(duration: 0.18), value: wrongPair)
                    }
                    .padding(20)
                    .frame(maxWidth: 820)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .background(CrabrixTheme.background.ignoresSafeArea())
        .foregroundStyle(CrabrixTheme.primary)
        .navigationTitle("Term Train")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("RUST MEMORY TRAIN", systemImage: "link")
                    .font(.caption.monospaced().bold())
                    .foregroundStyle(CrabrixTheme.mint)
                Spacer()
                Text("\(completed) / \(Pair.lesson.count)")
                    .font(.caption.monospaced().bold())
                    .foregroundStyle(CrabrixTheme.muted)
            }
            ProgressView(value: Double(completed), total: Double(Pair.lesson.count))
                .tint(CrabrixTheme.mint)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(CrabrixTheme.panel)
    }

    private var matchingBoard: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(spacing: 11) {
                columnTitle("DESCRIPTION", alignment: .leading)
                ForEach(descriptionOrder.filter { remaining.contains($0.id) }) { pair in
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
                ForEach(termOrder.filter { remaining.contains($0.id) }) { pair in
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
                    .shadow(color: (selectedDescription == selectedTerm ? CrabrixTheme.mint : CrabrixTheme.coral).opacity(0.55), radius: 6)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: remaining)
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
            .frame(maxWidth: .infinity, minHeight: 72)
            .background((selected || isResolving || isWrong) ? tint.opacity(0.14) : CrabrixTheme.raised)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .stroke((selected || isResolving || isWrong) ? tint : CrabrixTheme.border, lineWidth: selected ? 2 : 1)
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

    private var completion: some View {
        VStack(spacing: 18) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(CrabrixTheme.mint)
            Text("Connections complete")
                .font(.largeTitle.bold())
            Text("You matched all \(score) Rust concepts.")
                .foregroundStyle(CrabrixTheme.muted)
            HStack(spacing: 12) {
                Button("Train again") { reset() }
                    .buttonStyle(.bordered)
                Button("Back to Learn") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(CrabrixTheme.coral)
            }
        }
        .padding(24)
        .onAppear {
            guard !didReportCompletion else { return }
            didReportCompletion = true
            onComplete()
        }
    }

    private func select(_ id: String, side: Side) {
        guard resolvingPair == nil else { return }
        wrongPair = []
        withAnimation(.easeOut(duration: 0.16)) {
            if side == .description { selectedDescription = id }
            else { selectedTerm = id }
        }
        guard let selectedDescription, let selectedTerm else { return }

        if selectedDescription == selectedTerm {
            resolvingPair = selectedDescription
            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {}
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.62) {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    remaining.remove(selectedDescription)
                    score += 1
                    self.selectedDescription = nil
                    self.selectedTerm = nil
                    resolvingPair = nil
                }
            }
        } else {
            withAnimation(.easeInOut(duration: 0.16)) {
                wrongPair = [selectedDescription, selectedTerm]
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                withAnimation(.easeOut(duration: 0.18)) {
                    self.selectedDescription = nil
                    self.selectedTerm = nil
                    wrongPair = []
                }
            }
        }
    }

    private func reset() {
        withAnimation(.easeInOut(duration: 0.25)) {
            descriptionOrder.shuffle()
            termOrder.shuffle()
            remaining = Set(Pair.lesson.map(\.id))
            selectedDescription = nil
            selectedTerm = nil
            resolvingPair = nil
            wrongPair = []
            score = 0
            didReportCompletion = false
        }
    }
}
