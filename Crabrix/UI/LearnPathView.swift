import SwiftUI

struct LearnPathView: View {
    let completedStages: Set<CompilerViewModel.Stage>
    let practiceCompleted: Bool
    let onOpenLesson: (RustLesson) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                ForEach(RustLearningPath.units) { unit in
                    LearningUnitCard(
                        unit: unit,
                        completedStages: completedStages,
                        practiceCompleted: practiceCompleted,
                        onOpenLesson: onOpenLesson
                    )
                }
            }
            .padding(22)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(CrabrixTheme.background.ignoresSafeArea())
        .foregroundStyle(.white)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("LEARN RUST", systemImage: "graduationcap.fill")
                .font(.caption.monospaced().bold())
                .foregroundStyle(CrabrixTheme.coral)
            Text("Learn from code that rustc actually checks")
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text("A guided path mixes short explanations, compiler failures, repairs, and fresh practice. Three labs are live now; the remaining lessons define the next curriculum slices.")
                .foregroundStyle(CrabrixTheme.muted)
            HStack(spacing: 16) {
                Label("5 levels", systemImage: "map.fill")
                Label("20 lessons", systemImage: "circle.grid.3x3.fill")
                Label("3 live labs", systemImage: "checkmark.seal.fill")
            }
            .font(.caption.monospaced())
            .foregroundStyle(CrabrixTheme.mint)
        }
        .padding(20)
        .crabrixPanel(cornerRadius: 16)
    }
}

private struct LearningUnitCard: View {
    let unit: RustLearningUnit
    let completedStages: Set<CompilerViewModel.Stage>
    let practiceCompleted: Bool
    let onOpenLesson: (RustLesson) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("LEVEL \(unit.level)")
                        .font(.caption2.monospaced().bold())
                        .foregroundStyle(CrabrixTheme.coral)
                    Text(unit.title).font(.title3.bold())
                    Text(unit.subtitle).font(.caption).foregroundStyle(CrabrixTheme.muted)
                }
                Spacer()
                Text("\(liveCount)/\(unit.lessons.count) live")
                    .font(.caption2.monospaced())
                    .foregroundStyle(CrabrixTheme.muted)
            }

            VStack(spacing: 4) {
                ForEach(Array(unit.lessons.enumerated()), id: \.element.id) { index, lesson in
                    LessonPathRow(
                        lesson: lesson,
                        index: index,
                        isCompleted: isCompleted(lesson),
                        onOpen: { onOpenLesson(lesson) }
                    )
                }
            }
        }
        .padding(18)
        .crabrixPanel(cornerRadius: 16)
    }

    private var liveCount: Int {
        unit.lessons.filter { lesson in
            if case .planned = lesson.exercise { return false }
            return true
        }.count
    }

    private func isCompleted(_ lesson: RustLesson) -> Bool {
        switch lesson.exercise {
        case .runnable:
            completedStages.contains(.repair)
        case .borrowDiagnostic:
            practiceCompleted
        case .multiFile, .planned:
            false
        }
    }
}

private struct LessonPathRow: View {
    let lesson: RustLesson
    let index: Int
    let isCompleted: Bool
    let onOpen: () -> Void

    private var isLive: Bool {
        if case .planned = lesson.exercise { return false }
        return true
    }

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                Circle()
                    .fill(isCompleted ? CrabrixTheme.mint
                          : isLive ? CrabrixTheme.coral : CrabrixTheme.raised)
                    .frame(width: 42, height: 42)
                Image(systemName: isCompleted ? "checkmark" : isLive ? "chevron.right" : "lock.fill")
                    .font(.caption.bold())
                    .foregroundStyle(isCompleted ? CrabrixTheme.background : .white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(lesson.title).font(.subheadline.bold())
                Text(lesson.concept).font(.caption).foregroundStyle(CrabrixTheme.muted)
            }
            Spacer()
            Text(isLive ? "\(lesson.minutes) min" : "planned")
                .font(.caption2.monospaced())
                .foregroundStyle(isLive ? CrabrixTheme.mint : CrabrixTheme.muted)
        }
        .padding(.leading, index.isMultiple(of: 2) ? 0 : 34)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { if isLive { onOpen() } }
        .accessibilityAddTraits(isLive ? .isButton : [])
    }
}
