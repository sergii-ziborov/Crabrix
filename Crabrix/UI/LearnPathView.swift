import SwiftUI

struct LearnPathView: View {
    let units: [RustLearningUnit]
    let courseTitle: String
    let completedLessonIDs: Set<String>
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

    private var nextLessonID: String? {
        RustLessonProgression.nextLessonID(
            in: units,
            completedLessonIDs: completedLessonIDs
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 30) {
                LearningHero(
                    completedLessonCount: completedLessonCount,
                    totalLessonCount: lessons.count,
                    chapterCount: units.count,
                    liveLessonCount: lessons.filter(\.hasCompilerLab).count,
                    actionTitle: isCourseCompleted
                        ? "Review course from start"
                        : (completedLessonCount == 0 ? "Start course" : "Continue course"),
                    actionSystemImage: isCourseCompleted
                        ? "arrow.counterclockwise"
                        : "arrow.right",
                    onAction: {
                        guard let courseEntryLesson else { return }
                        onOpenLesson(courseEntryLesson)
                    }
                )

                ForEach(units) { unit in
                    LearningUnitMap(
                        unit: unit,
                        completedLessonIDs: completedLessonIDs,
                        nextLessonID: nextLessonID,
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
                    colors: [CrabrixTheme.blue.opacity(0.08), .clear, CrabrixTheme.coral.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
        }
        .foregroundStyle(CrabrixTheme.primary)
        .navigationTitle(courseTitle)
    }
}

private struct LearningHero: View {
    let completedLessonCount: Int
    let totalLessonCount: Int
    let chapterCount: Int
    let liveLessonCount: Int
    let actionTitle: String
    let actionSystemImage: String
    let onAction: () -> Void

    private var progress: Double {
        guard totalLessonCount > 0 else { return 0 }
        return Double(completedLessonCount) / Double(totalLessonCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("YOUR RUST JOURNEY", systemImage: "map.fill")
                        .font(.caption.monospaced().bold())
                        .foregroundStyle(CrabrixTheme.mint)

                    Text("Build fearless\nRust instincts")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .minimumScaleFactor(0.8)

                    Text("Follow the map from your first compile to real Cargo projects. Live labs are verified by the compiler inside Crabrix.")
                        .font(.subheadline)
                        .foregroundStyle(CrabrixTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                ZStack {
                    Circle()
                        .stroke(CrabrixTheme.border, lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: max(progress, 0.025))
                        .stroke(
                            AngularGradient(
                                colors: [CrabrixTheme.mint, CrabrixTheme.blue, CrabrixTheme.mint],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 1) {
                        Text("\(completedLessonCount)")
                            .font(.title2.monospaced().bold())
                        Text("of \(totalLessonCount)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(CrabrixTheme.muted)
                    }
                }
                .frame(width: 88, height: 88)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(completedLessonCount) of \(totalLessonCount) lessons complete")
            }

            HStack(spacing: 10) {
                JourneyMetric(icon: "flag.checkered", value: "\(chapterCount)", label: "chapters", tint: CrabrixTheme.blue)
                JourneyMetric(icon: "hammer.fill", value: "\(liveLessonCount)", label: "live labs", tint: CrabrixTheme.coral)
                JourneyMetric(icon: "wifi.slash", value: "100%", label: "local", tint: CrabrixTheme.mint)
            }

            Button(action: onAction) {
                Label(actionTitle, systemImage: actionSystemImage)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(CrabrixTheme.mint)
        }
        .padding(22)
        .background {
            ZStack(alignment: .topTrailing) {
                LinearGradient(
                    colors: [Color(red: 0.10, green: 0.20, blue: 0.30), CrabrixTheme.panel],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(CrabrixTheme.blue.opacity(0.15))
                    .frame(width: 180, height: 180)
                    .offset(x: 65, y: -90)
                Circle()
                    .fill(CrabrixTheme.coral.opacity(0.11))
                    .frame(width: 120, height: 120)
                    .offset(x: -235, y: 155)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(CrabrixTheme.border, lineWidth: 1)
        }
    }
}

private struct JourneyMetric: View {
    let icon: String
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption.bold())
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.13), in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.caption.monospaced().bold())
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(CrabrixTheme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct LearningUnitMap: View {
    let unit: RustLearningUnit
    let completedLessonIDs: Set<String>
    let nextLessonID: String?
    let onOpenLesson: (RustLesson) -> Void

    /// The lesson a reader just tried to open too early.
    @State private var blocked: RustLesson?

    private let rowHeight: CGFloat = 124

    private var palette: LearningPalette { .palette(for: unit.level) }

    private var completedCount: Int {
        unit.lessons.filter(isCompleted).count
    }

    private var readyCount: Int {
        unit.lessons.filter { $0.id == nextLessonID }.count
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
                completedCount: completedCount,
                readyCount: readyCount
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
        return lesson.id == nextLessonID ? .ready : .locked
    }

    private func isCompleted(_ lesson: RustLesson) -> Bool {
        completedLessonIDs.contains(lesson.id)
    }

    private func labelToRight(at index: Int) -> Bool {
        switch index % 4 {
        case 0, 3: true
        default: false
        }
    }
}

private struct UnitBanner: View {
    let unit: RustLearningUnit
    let palette: LearningPalette
    let completedCount: Int
    let readyCount: Int

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
                Text(
                    completedCount > 0
                        ? "\(completedCount)/\(unit.lessons.count)"
                        : (readyCount > 0 ? "\(readyCount) ready" : "locked")
                )
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
            x: width * trailFraction(at: index),
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
            let nodeX = width * trailFraction(at: lessonNumber - 1)
            let labelWidth = min(230, max(150, width * 0.47))
            let labelOffset = min(labelWidth / 2 + 48, width * 0.38)
            let labelX = nodeX + (labelToRight ? labelOffset : -labelOffset)

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
        case .ready: .white
        case .locked: CrabrixTheme.muted
        }
    }

    private var nodeGradient: LinearGradient {
        switch state {
        case .completed:
            LinearGradient(colors: [CrabrixTheme.mint, Color(red: 0.24, green: 0.69, blue: 0.50)], startPoint: .top, endPoint: .bottom)
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
            LearningPalette(primary: CrabrixTheme.blue, secondary: Color(red: 0.25, green: 0.48, blue: 0.94), symbol: "sparkles")
        case 2:
            LearningPalette(primary: CrabrixTheme.coral, secondary: Color(red: 0.82, green: 0.22, blue: 0.27), symbol: "link")
        case 3:
            LearningPalette(primary: Color(red: 0.72, green: 0.47, blue: 0.98), secondary: Color(red: 0.43, green: 0.32, blue: 0.82), symbol: "shippingbox.fill")
        case 4:
            LearningPalette(primary: CrabrixTheme.amber, secondary: Color(red: 0.84, green: 0.45, blue: 0.14), symbol: "function")
        default:
            LearningPalette(primary: CrabrixTheme.mint, secondary: Color(red: 0.20, green: 0.61, blue: 0.55), symbol: "flag.checkered")
        }
    }
}

private func trailFraction(at index: Int) -> CGFloat {
    switch index % 4 {
    case 0: 0.28
    case 1: 0.50
    case 2: 0.72
    default: 0.50
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
