import SwiftUI

struct LearnPathView: View {
    @State private var isResetConfirmationPresented = false

    let units: [RustLearningUnit]
    let courseTitle: String
    let courseTheme: RustCourseTheme
    let completedLessonIDs: Set<String>
    var unlockScope: RustLessonProgression.UnlockScope = .course
    let onResetProgress: () -> Void
    let onOpenLesson: (RustLesson) -> Void

    private var completedLessonCount: Int {
        RustLessonProgression.completedCount(
            in: units,
            completedLessonIDs: completedLessonIDs
        )
    }

    private var lessons: [RustLesson] { RustLessonProgression.lessons(in: units) }

    private var isCourseCompleted: Bool {
        !lessons.isEmpty && completedLessonCount == lessons.count
    }

    private var courseEntryLesson: RustLesson? {
        if isCourseCompleted { return lessons.first }
        return lessons.first(where: { !completedLessonIDs.contains($0.id) })
            ?? lessons.first
    }

    private var readyLessonIDs: Set<String> {
        RustLessonProgression.readyLessonIDs(
            in: units,
            completedLessonIDs: completedLessonIDs,
            scope: unlockScope
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 30) {
                VStack(spacing: 12) {
                    LearningHero(
                        completedLessonCount: completedLessonCount,
                        totalLessonCount: lessons.count,
                        actionTitle: isCourseCompleted
                            ? "Review course from start"
                            : (completedLessonCount == 0 ? "Start course" : "Continue course"),
                        actionSystemImage: isCourseCompleted
                            ? "arrow.counterclockwise"
                            : "arrow.right",
                        theme: courseTheme,
                        onAction: {
                            guard let courseEntryLesson else { return }
                            onOpenLesson(courseEntryLesson)
                        }
                    )

                    Button {
                        isResetConfirmationPresented = true
                    } label: {
                        Label("Reset course progress", systemImage: "arrow.counterclockwise")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(CrabrixTheme.coral)
                }

                ForEach(units) { unit in
                    LearningUnitMap(
                        unit: unit,
                        completedLessonIDs: completedLessonIDs,
                        readyLessonIDs: readyLessonIDs,
                        courseTheme: courseTheme,
                        onOpenLesson: onOpenLesson
                    )
                }

                LearningLegend()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 22)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background {
            ZStack {
                CrabrixTheme.background.ignoresSafeArea()
                LinearGradient(
                    colors: [courseTheme.primaryColor.opacity(0.10), .clear, courseTheme.secondaryColor.opacity(0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
        }
        .foregroundStyle(CrabrixTheme.primary)
        .navigationTitle(courseTitle)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Reset progress in \(courseTitle)?",
            isPresented: $isResetConfirmationPresented
        ) {
            Button("Reset course progress", role: .destructive, action: onResetProgress)
        } message: {
            Text("Lessons and answers restart. Projects and earned rewards stay.")
        }
    }
}

private struct LearningHero: View {
    let completedLessonCount: Int
    let totalLessonCount: Int
    let actionTitle: String
    let actionSystemImage: String
    let theme: RustCourseTheme
    let onAction: () -> Void

    private var progress: Double {
        guard totalLessonCount > 0 else { return 0 }
        return Double(completedLessonCount) / Double(totalLessonCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(completedLessonCount) of \(totalLessonCount) lessons")
                    .font(.headline)
                Spacer(minLength: 8)
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.subheadline.monospaced().bold())
                    .foregroundStyle(CrabrixTheme.muted)
            }

            ProgressView(value: progress)
                .tint(theme.primaryColor)
                .accessibilityLabel("\(completedLessonCount) of \(totalLessonCount) lessons complete")

            Button(action: onAction) {
                Label(actionTitle, systemImage: actionSystemImage)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.primaryColor)
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [theme.primaryColor.opacity(0.13), CrabrixTheme.panel],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(CrabrixTheme.border, lineWidth: 1)
        }
    }
}

private struct LearningUnitMap: View {
    let unit: RustLearningUnit
    let completedLessonIDs: Set<String>
    let readyLessonIDs: Set<String>
    let courseTheme: RustCourseTheme
    let onOpenLesson: (RustLesson) -> Void

    /// The lesson a reader just tried to open too early.
    @State private var blocked: RustLesson?

    private let rowHeight: CGFloat = 124

    private var palette: LearningPalette {
        LearningPalette(
            primary: courseTheme.primaryColor,
            secondary: courseTheme.secondaryColor,
            symbol: unit.level == 1 ? "sparkles" : "flag.checkered"
        )
    }

    private var completedCount: Int {
        unit.lessons.filter(isCompleted).count
    }

    /// Names the lesson standing in the way, rather than only refusing.
    private func blockedMessage(for lesson: RustLesson) -> String {
        guard let index = unit.lessons.firstIndex(where: { $0.id == lesson.id }),
              index > 0
        else {
            return "Lessons unlock in order. Finish the ones before this first."
        }
        let previous = unit.lessons[index - 1]
        return "\(lesson.title) unlocks once you finish \(previous.title). "
            + "The path builds on itself, so the order is the point."
    }

    var body: some View {
        VStack(spacing: 0) {
            UnitBanner(
                unit: unit,
                palette: palette,
                completedCount: completedCount
            )
            .zIndex(2)

            GeometryReader { geometry in
                let width = geometry.size.width

                ZStack(alignment: .topLeading) {
                    TrailLine(
                        lessonCount: unit.lessons.count,
                        width: width,
                        rowHeight: rowHeight,
                        tint: palette.primary
                    )

                    ForEach(Array(unit.lessons.enumerated()), id: \.element.id) { index, lesson in
                        LessonMapNode(
                            lesson: lesson,
                            lessonNumber: index + 1,
                            state: state(for: lesson),
                            palette: palette,
                            labelToRight: labelToRight(at: index),
                            onOpen: { onOpenLesson(lesson) },
                            onBlocked: { blocked = lesson }
                        )
                        .frame(width: width, height: rowHeight)
                        .offset(y: CGFloat(index) * rowHeight)
                    }
                }
            }
            .frame(height: CGFloat(unit.lessons.count) * rowHeight + 8)
            .padding(.horizontal, 4)
        }
        .alert(
            "Not yet",
            isPresented: Binding(get: { blocked != nil }, set: { if !$0 { blocked = nil } }),
            presenting: blocked
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { lesson in
            Text(blockedMessage(for: lesson))
        }
        .background(CrabrixTheme.panel.opacity(0.52))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(CrabrixTheme.border, lineWidth: 1)
        }
    }

    private func state(for lesson: RustLesson) -> LessonMapState {
        if isCompleted(lesson) { return .completed }
        return readyLessonIDs.contains(lesson.id) ? .ready : .locked
    }

    private func isCompleted(_ lesson: RustLesson) -> Bool {
        completedLessonIDs.contains(lesson.id)
    }

    private func labelToRight(at index: Int) -> Bool {
        LessonMapLayout.labelToRight(at: index)
    }
}

private struct UnitBanner: View {
    let unit: RustLearningUnit
    let palette: LearningPalette
    let completedCount: Int

    private var progress: Double {
        guard !unit.lessons.isEmpty else { return 0 }
        return Double(completedCount) / Double(unit.lessons.count)
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(.white.opacity(0.16))
                Image(systemName: palette.symbol)
                    .font(.title2.bold())
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 4) {
                Text("CHAPTER \(unit.level)")
                    .font(.caption2.monospaced().bold())
                    .foregroundStyle(CrabrixTheme.primary.opacity(0.72))
                Text(unit.title)
                    .font(.title3.bold())
                Text(unit.subtitle)
                    .font(.caption)
                    .foregroundStyle(CrabrixTheme.primary.opacity(0.70))
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                Text("\(completedCount)/\(unit.lessons.count)")
                    .font(.caption.monospaced().bold())
                ProgressView(value: progress)
                    .tint(.white)
                    .frame(width: 66)
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [palette.primary, palette.secondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: palette.primary.opacity(0.24), radius: 18, y: 8)
    }
}

private struct TrailLine: View {
    let lessonCount: Int
    let width: CGFloat
    let rowHeight: CGFloat
    let tint: Color

    var body: some View {
        ZStack {
            trailPath
                .stroke(
                    .white.opacity(0.09),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round)
                )
            trailPath
                .stroke(
                    tint.opacity(0.34),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: [4, 9])
                )
        }
    }

    private var trailPath: Path {
        Path { path in
            guard lessonCount > 0 else { return }
            var current = point(at: 0)
            path.move(to: current)

            for index in 1..<lessonCount {
                let next = point(at: index)
                let midpointY = (current.y + next.y) / 2
                path.addCurve(
                    to: next,
                    control1: CGPoint(x: current.x, y: midpointY),
                    control2: CGPoint(x: next.x, y: midpointY)
                )
                current = next
            }
        }
    }

    private func point(at index: Int) -> CGPoint {
        CGPoint(
            x: LessonMapLayout.nodeCenterX(width: width, index: index),
            y: CGFloat(index) * rowHeight + rowHeight / 2
        )
    }
}

private struct LessonMapNode: View {
    let lesson: RustLesson
    let lessonNumber: Int
    let state: LessonMapState
    let palette: LearningPalette
    let labelToRight: Bool
    let onOpen: () -> Void
    /// Called instead of `onOpen` when the lesson is still locked.
    let onBlocked: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let index = lessonNumber - 1
            let nodeX = LessonMapLayout.nodeCenterX(width: width, index: index)
            let labelWidth = LessonMapLayout.labelWidth(for: width)
            let labelX = LessonMapLayout.labelCenterX(
                width: width,
                nodeX: nodeX,
                labelWidth: labelWidth,
                labelToRight: labelToRight
            )

            Button {
                // The button style only dimmed a locked node; the action still
                // fired, so a locked lesson opened anyway. Order is the point
                // of the path, so it is enforced here.
                if state == .locked { onBlocked() } else { onOpen() }
            } label: {
                ZStack {
                    lessonLabel
                        .frame(width: labelWidth)
                        .position(x: labelX, y: geometry.size.height / 2)

                    lessonNode
                        .position(x: nodeX, y: geometry.size.height / 2)
                }
                .frame(width: width, height: geometry.size.height)
                .clipped()
                .contentShape(Rectangle())
            }
            .buttonStyle(LessonMapButtonStyle(isEnabled: state != .locked))
            .accessibilityLabel("Lesson \(lessonNumber), \(lesson.title), \(state.accessibilityLabel)")
        }
    }

    private var lessonNode: some View {
        ZStack {
            if state == .ready {
                Circle()
                    .stroke(palette.primary.opacity(0.34), lineWidth: 3)
                    .frame(width: 82, height: 82)
                Circle()
                    .stroke(palette.primary.opacity(0.16), lineWidth: 2)
                    .frame(width: 94, height: 94)
            }

            Circle()
                .fill(nodeGradient)
                .frame(width: 68, height: 68)
                .overlay {
                    Circle()
                        .stroke(CrabrixTheme.primary.opacity(state == .locked ? 0.18 : 0.25), lineWidth: 1)
                }
                .shadow(color: nodeShadow, radius: state == .ready ? 14 : 4, y: 6)

            Image(systemName: state.symbol(for: lesson))
                .font(.system(size: 23, weight: .bold))
                .foregroundStyle(nodeIconColor)
        }
        .frame(width: 96, height: 96)
    }

    private var lessonLabel: some View {
        VStack(alignment: labelToRight ? .leading : .trailing, spacing: 5) {
            HStack(spacing: 6) {
                if !labelToRight { Spacer(minLength: 0) }
                Text("\(lessonNumber)")
                    .font(.caption2.monospaced().bold())
                    .foregroundStyle(state.tint(palette: palette))
                Text(lesson.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(CrabrixTheme.primary.opacity(state == .locked ? 0.52 : 1))
                    .lineLimit(1)
                if labelToRight { Spacer(minLength: 0) }
            }

            Text(lesson.concept)
                .font(.caption)
                .foregroundStyle(CrabrixTheme.primary.opacity(state == .locked ? 0.34 : 0.58))
                .multilineTextAlignment(labelToRight ? .leading : .trailing)
                .lineLimit(2)

            Text(state.badge(minutes: lesson.minutes))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(state.tint(palette: palette))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(state.tint(palette: palette).opacity(0.11), in: Capsule())
        }
    }

    /// The locked circle is nearly white in the light theme, so a white icon on
    /// it was invisible. Every state now picks a colour that contrasts with its
    /// own fill rather than assuming a dark background.
    private var nodeIconColor: Color {
        switch state {
        case .completed: CrabrixTheme.background
        case .ready: CrabrixTheme.isCyberpunk ? CrabrixTheme.background : .white
        case .locked: CrabrixTheme.muted
        }
    }

    private var nodeGradient: LinearGradient {
        switch state {
        case .completed:
            LinearGradient(colors: [RustCourseTheme.basics.primaryColor,
                                    RustCourseTheme.basics.secondaryColor],
                           startPoint: .top, endPoint: .bottom)
        case .ready:
            LinearGradient(colors: [palette.primary, palette.secondary], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .locked:
            LinearGradient(colors: [CrabrixTheme.raised, CrabrixTheme.editor], startPoint: .top, endPoint: .bottom)
        }
    }

    private var nodeShadow: Color {
        switch state {
        case .completed: CrabrixTheme.mint.opacity(0.28)
        case .ready: palette.primary.opacity(0.38)
        case .locked: .black.opacity(0.15)
        }
    }
}

private struct LessonMapButtonStyle: ButtonStyle {
    let isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && isEnabled ? 0.975 : 1)
            .opacity(configuration.isPressed && isEnabled ? 0.82 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct LearningLegend: View {
    var body: some View {
        HStack(spacing: 18) {
            LegendItem(color: CrabrixTheme.mint, icon: "checkmark", text: "Complete")
            LegendItem(color: CrabrixTheme.coral, icon: "play.fill", text: "Live lab")
            LegendItem(color: CrabrixTheme.raised, icon: "lock.fill", text: "Coming next")
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .crabrixPanel(cornerRadius: 16)
    }
}

private struct LegendItem: View {
    let color: Color
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(color, in: Circle())
            Text(text)
                .font(.caption2)
                .foregroundStyle(CrabrixTheme.muted)
        }
    }
}

private enum LessonMapState: Equatable {
    case completed
    case ready
    case locked

    var accessibilityLabel: String {
        switch self {
        case .completed: "complete"
        case .ready: "available"
        case .locked: "coming later"
        }
    }

    func badge(minutes: Int) -> String {
        switch self {
        case .completed: "COMPLETE"
        case .ready: "START · \(minutes) MIN"
        case .locked: "COMING NEXT"
        }
    }

    func tint(palette: LearningPalette) -> Color {
        switch self {
        case .completed: CrabrixTheme.mint
        case .ready: palette.primary
        case .locked: CrabrixTheme.muted
        }
    }

    func symbol(for lesson: RustLesson) -> String {
        if self == .completed { return "checkmark" }
        if self == .locked { return "lock.fill" }
        return lesson.symbol
    }
}

private struct LearningPalette {
    let primary: Color
    let secondary: Color
    let symbol: String

    static func palette(for level: Int) -> LearningPalette {
        switch level {
        case 1:
            LearningPalette(primary: RustCourseTheme.projects.primaryColor,
                            secondary: RustCourseTheme.projects.secondaryColor, symbol: "sparkles")
        case 2:
            LearningPalette(primary: RustCourseTheme.ownership.primaryColor,
                            secondary: RustCourseTheme.ownership.secondaryColor, symbol: "link")
        case 3:
            LearningPalette(primary: RustCourseTheme.systems.primaryColor,
                            secondary: RustCourseTheme.systems.secondaryColor, symbol: "shippingbox.fill")
        case 4:
            LearningPalette(primary: RustCourseTheme.concurrency.primaryColor,
                            secondary: RustCourseTheme.concurrency.secondaryColor, symbol: "function")
        default:
            LearningPalette(primary: RustCourseTheme.basics.primaryColor,
                            secondary: RustCourseTheme.basics.secondaryColor, symbol: "flag.checkered")
        }
    }
}

/// Geometry for the winding lesson path. It deliberately exposes pure helpers
/// so narrow iPhones and Split View widths can be regression-tested without
/// taking screenshots. Labels always remain inside `edgeInset`, while nodes
/// occupy two lanes rather than placing a label-bearing node in the centre.
enum LessonMapLayout {
    static let edgeInset: CGFloat = 8
    static let nodeDiameter: CGFloat = 96
    static let labelGap: CGFloat = 6

    static func trailFraction(at index: Int) -> CGFloat {
        switch index % 4 {
        case 0, 3: 0.23
        default: 0.77
        }
    }

    static func labelToRight(at index: Int) -> Bool {
        trailFraction(at: index) < 0.5
    }

    static func nodeCenterX(width: CGFloat, index: Int) -> CGFloat {
        let radius = nodeDiameter / 2
        let minimum = edgeInset + radius
        let maximum = max(minimum, width - edgeInset - radius)
        return clamp(width * trailFraction(at: index), minimum, maximum)
    }

    static func labelWidth(for width: CGFloat) -> CGFloat {
        let available = max(0, width - edgeInset * 2)
        return min(210, available, max(112, width * 0.43))
    }

    static func labelCenterX(
        width: CGFloat,
        nodeX: CGFloat,
        labelWidth: CGFloat,
        labelToRight: Bool
    ) -> CGFloat {
        let halfLabel = labelWidth / 2
        let direction: CGFloat = labelToRight ? 1 : -1
        let ideal = nodeX + direction * (nodeDiameter / 2 + labelGap + halfLabel)
        let minimum = edgeInset + halfLabel
        let maximum = max(minimum, width - edgeInset - halfLabel)
        return clamp(ideal, minimum, maximum)
    }

    private static func clamp(
        _ value: CGFloat,
        _ minimum: CGFloat,
        _ maximum: CGFloat
    ) -> CGFloat {
        min(max(value, minimum), maximum)
    }
}

private extension RustLesson {
    var symbol: String {
        switch id {
        case "hello-rust": "terminal.fill"
        case "variables": "equal.circle.fill"
        case "types": "square.stack.3d.up.fill"
        case "control-flow": "arrow.triangle.branch"
        case "ownership": "key.fill"
        case "borrowing": "link"
        case "slices": "square.split.2x1.fill"
        case "lifetimes-intro", "lifetimes": "hourglass"
        case "structs": "shippingbox.fill"
        case "enums": "switch.2"
        case "option-result": "questionmark.diamond.fill"
        case "collections": "tray.2.fill"
        case "generics": "chevron.left.forwardslash.chevron.right"
        case "traits": "puzzlepiece.extension.fill"
        case "iterators": "arrow.triangle.2.circlepath"
        case "modules": "folder.fill"
        case "testing": "checkmark.seal.fill"
        case "errors": "exclamationmark.triangle.fill"
        case "concurrency": "circle.hexagongrid.fill"
        default: "circle.fill"
        }
    }
}
