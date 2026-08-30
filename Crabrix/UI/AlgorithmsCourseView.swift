import SwiftUI

struct AlgorithmsCourseView: View {
    @EnvironmentObject private var progress: CrabrixProgressStore

    let completedLessonIDs: Set<String>
    let onOpenLesson: (RustLesson) -> Void

    @State private var expandedMethodIDs: Set<String> = []
    @State private var blockedPattern: AlgorithmPattern?
    @State private var showsMethodIndex = false

    private let tint = RustCourseTheme.algorithms.primaryColor

    private var completedSteps: Int {
        let ids = Set(AlgorithmCourseCatalog.units.flatMap(\.lessons).map(\.id))
        return completedLessonIDs.intersection(ids).count
    }

    private var solvedCount: Int {
        progress.state.solvedAlgorithmPatternIDs.count
    }

    private var nextPattern: AlgorithmPattern? {
        AlgorithmCourseCatalog.patterns.first { pattern in
            !completedLessonIDs.contains(pattern.lessonID(.challenge))
        } ?? AlgorithmCourseCatalog.patterns.first
    }

    private var currentMethod: AlgorithmCategory? {
        guard let nextPattern else { return AlgorithmCourseCatalog.methods.first }
        return AlgorithmCourseCatalog.method(id: nextPattern.categoryID)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    hero
                    methodDirectoryButton

                    ForEach(Array(AlgorithmCourseCatalog.methods.enumerated()), id: \.element.id) { index, method in
                        AlgorithmMethodChapter(
                            method: method,
                            methodNumber: index + 1,
                            completedLessonIDs: completedLessonIDs,
                            isExpanded: expandedMethodIDs.contains(method.id),
                            isPatternUnlocked: isUnlocked,
                            onToggle: { toggle(method.id) },
                            onOpen: open,
                            onBlocked: { blockedPattern = $0 }
                        )
                        .id(methodAnchor(method.id))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 20)
                .padding(.bottom, 86)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .sheet(isPresented: $showsMethodIndex) {
                AlgorithmMethodIndexView(
                    completedLessonIDs: completedLessonIDs,
                    isPatternUnlocked: isUnlocked,
                    onSelect: { methodID in
                        showsMethodIndex = false
                        expandedMethodIDs.insert(methodID)
                        withAnimation(.easeInOut(duration: 0.35)) {
                            proxy.scrollTo(methodAnchor(methodID), anchor: .top)
                        }
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .background {
            LinearGradient(
                colors: [tint.opacity(0.11), CrabrixTheme.background, CrabrixTheme.background],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
        .foregroundStyle(CrabrixTheme.primary)
        .navigationTitle("Algorithms")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsMethodIndex = true
                } label: {
                    Label("Methods", systemImage: "list.bullet.rectangle.portrait")
                }
            }
        }
        .onAppear {
            if expandedMethodIDs.isEmpty, let currentMethod {
                expandedMethodIDs.insert(currentMethod.id)
            }
        }
        .alert(
            "Follow the method path",
            isPresented: Binding(
                get: { blockedPattern != nil },
                set: { if !$0 { blockedPattern = nil } }
            ),
            presenting: blockedPattern
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { pattern in
            if let previous = AlgorithmCourseCatalog.previousPattern(before: pattern.id) {
                Text("Finish the challenge for \(previous.title) first. Each method builds from easier patterns to harder combinations.")
            } else {
                Text("Start with the first HOW step, then learn WHEN to use it before solving the Rust challenge.")
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    heroIcon
                    heroCopy
                }
                VStack(alignment: .leading, spacing: 12) {
                    heroIcon
                    heroCopy
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 9) { metrics }
                VStack(spacing: 9) { metrics }
            }

            ProgressView(value: Double(solvedCount), total: 200)
                .tint(tint)

            if let nextPattern {
                Button {
                    open(nextPattern)
                } label: {
                    Label(
                        solvedCount == 0 ? "Start the first method" : "Continue \(nextPattern.title)",
                        systemImage: "arrow.right"
                    )
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [tint.opacity(0.22), CrabrixTheme.panel],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay { RoundedRectangle(cornerRadius: 22).stroke(tint.opacity(0.30)) }
    }

    private var heroIcon: some View {
        Image(systemName: "point.3.connected.trianglepath.dotted")
            .font(.system(size: 30, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: 64, height: 64)
            .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 18))
    }

    private var heroCopy: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("ALGORITHM ATLAS")
                .font(.caption.monospaced().bold())
                .foregroundStyle(tint)
            Text("Learn solution methods, then recognise the problem")
                .font(.system(size: 27, weight: .heavy, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
            Text("20 method chapters · 200 patterns · every pattern moves from HOW to WHEN to a local Rust challenge")
                .font(.subheadline)
                .foregroundStyle(CrabrixTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var metrics: some View {
        AlgorithmMetric(value: "\(solvedCount)", label: "mastered", systemImage: "checkmark.seal.fill", tint: tint)
        AlgorithmMetric(value: "20", label: "methods", systemImage: "point.3.filled.connected.trianglepath.dotted", tint: CrabrixTheme.cyan)
        AlgorithmMetric(value: "\(completedSteps)/600", label: "steps", systemImage: "list.number", tint: CrabrixTheme.amber)
    }

    private var methodDirectoryButton: some View {
        Button {
            showsMethodIndex = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "map.fill")
                    .font(.headline)
                    .foregroundStyle(tint)
                    .frame(width: 42, height: 42)
                    .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    Text("20 SOLUTION METHODS")
                        .font(.caption2.monospaced().bold())
                        .foregroundStyle(tint)
                    Text(currentMethod.map { "Current · \($0.title)" } ?? "Browse the complete path")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CrabrixTheme.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(CrabrixTheme.muted)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CrabrixTheme.panel, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 17).stroke(CrabrixTheme.border) }
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ methodID: String) {
        withAnimation(.easeInOut(duration: 0.28)) {
            if expandedMethodIDs.contains(methodID) {
                expandedMethodIDs.remove(methodID)
            } else {
                expandedMethodIDs.insert(methodID)
            }
        }
    }

    private func isUnlocked(_ pattern: AlgorithmPattern) -> Bool {
        if completedLessonIDs.contains(pattern.lessonID(.challenge)) { return true }
        guard let previous = AlgorithmCourseCatalog.previousPattern(before: pattern.id) else { return true }
        return completedLessonIDs.contains(previous.lessonID(.challenge))
    }

    private func open(_ pattern: AlgorithmPattern) {
        guard isUnlocked(pattern) else {
            blockedPattern = pattern
            return
        }
        let next = pattern.lessons.first { !completedLessonIDs.contains($0.id) }
            ?? pattern.lessons.first
        if let next { onOpenLesson(next) }
    }

    private func methodAnchor(_ methodID: String) -> String {
        "algorithm-method-\(methodID)"
    }
}

private struct AlgorithmMethodChapter: View {
    let method: AlgorithmCategory
    let methodNumber: Int
    let completedLessonIDs: Set<String>
    let isExpanded: Bool
    let isPatternUnlocked: (AlgorithmPattern) -> Bool
    let onToggle: () -> Void
    let onOpen: (AlgorithmPattern) -> Void
    let onBlocked: (AlgorithmPattern) -> Void

    private var tint: Color {
        AlgorithmMethodPalette.tint(at: methodNumber - 1)
    }

    private var completedPatterns: Int {
        method.patterns.filter { completedLessonIDs.contains($0.lessonID(.challenge)) }.count
    }

    private var completedSteps: Int {
        method.patterns.flatMap(\.lessons).filter { completedLessonIDs.contains($0.id) }.count
    }

    private var isUnlocked: Bool {
        method.patterns.first.map(isPatternUnlocked) ?? false
    }

    private var statusText: String {
        if completedPatterns == method.patterns.count { return "MASTERED" }
        if !isUnlocked { return "LOCKED" }
        if completedSteps == 0 { return "READY" }
        return "\(completedPatterns)/\(method.patterns.count) SOLVED"
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                AlgorithmMethodBanner(
                    method: method,
                    methodNumber: methodNumber,
                    completedPatterns: completedPatterns,
                    statusText: statusText,
                    isExpanded: isExpanded,
                    isUnlocked: isUnlocked,
                    tint: tint
                )
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 0) {
                    AlgorithmMethodGuide(method: method, tint: tint)
                        .padding(.horizontal, 14)
                        .padding(.top, 14)

                    AlgorithmPatternPath(
                        patterns: method.patterns,
                        completedLessonIDs: completedLessonIDs,
                        isPatternUnlocked: isPatternUnlocked,
                        tint: tint,
                        onOpen: onOpen,
                        onBlocked: onBlocked
                    )
                    .padding(.horizontal, 4)
                    .padding(.top, 8)
                    .padding(.bottom, 14)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(CrabrixTheme.panel.opacity(0.72), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(tint.opacity(isExpanded ? 0.32 : 0.17))
        }
    }
}

private struct AlgorithmMethodBanner: View {
    let method: AlgorithmCategory
    let methodNumber: Int
    let completedPatterns: Int
    let statusText: String
    let isExpanded: Bool
    let isUnlocked: Bool
    let tint: Color

    private var progress: Double {
        Double(completedPatterns) / Double(max(method.patterns.count, 1))
    }

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(.white.opacity(isUnlocked ? 0.17 : 0.10))
                Image(systemName: isUnlocked ? method.systemImage : "lock.fill")
                    .font(.title3.bold())
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 4) {
                Text("METHOD \(methodNumber.formatted(.number.precision(.integerLength(2))))")
                    .font(.caption2.monospaced().bold())
                    .foregroundStyle(.white.opacity(0.74))
                Text(method.title)
                    .font(.title3.bold())
                    .lineLimit(2)
                    .minimumScaleFactor(0.84)
                    .multilineTextAlignment(.leading)
                Text(method.subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 7) {
                Text(statusText)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                ProgressView(value: progress)
                    .tint(.white)
                    .frame(width: 58)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.bold())
            }
            .foregroundStyle(.white.opacity(isUnlocked ? 0.92 : 0.56))
        }
        .padding(16)
        .foregroundStyle(.white.opacity(isUnlocked ? 1 : 0.62))
        .background(
            LinearGradient(
                colors: isUnlocked
                    ? [tint, tint.opacity(0.72)]
                    : [CrabrixTheme.muted.opacity(0.55), CrabrixTheme.muted.opacity(0.35)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Method \(methodNumber), \(method.title), \(statusText)")
        .accessibilityHint(isExpanded ? "Collapse this method" : "Show its learning path")
    }
}

private struct AlgorithmMethodGuide: View {
    let method: AlgorithmCategory
    let tint: Color

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 7), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "book.pages.fill")
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("METHOD GUIDE")
                        .font(.caption2.monospaced().bold())
                        .foregroundStyle(tint)
                    Text("Each pattern repeats one focused learning loop")
                        .font(.caption.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            LazyVGrid(columns: columns, spacing: 7) {
                AlgorithmGuideStage(number: 1, title: "HOW", detail: "model + invariant", tint: tint)
                AlgorithmGuideStage(number: 2, title: "WHEN", detail: "signals + use cases", tint: tint)
                AlgorithmGuideStage(number: 3, title: "SOLVE", detail: "local Rust task", tint: tint)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 15).stroke(tint.opacity(0.18)) }
    }
}

private struct AlgorithmGuideStage: View {
    let number: Int
    let title: String
    let detail: String
    let tint: Color

    var body: some View {
        VStack(spacing: 5) {
            Text("\(number)")
                .font(.caption2.monospaced().bold())
                .foregroundStyle(CrabrixTheme.background)
                .frame(width: 22, height: 22)
                .background(tint, in: Circle())
            Text(title)
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundStyle(tint)
            Text(detail)
                .font(.system(size: 9))
                .foregroundStyle(CrabrixTheme.muted)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(minHeight: 22, alignment: .top)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AlgorithmPatternPath: View {
    let patterns: [AlgorithmPattern]
    let completedLessonIDs: Set<String>
    let isPatternUnlocked: (AlgorithmPattern) -> Bool
    let tint: Color
    let onOpen: (AlgorithmPattern) -> Void
    let onBlocked: (AlgorithmPattern) -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                AlgorithmTrailShape(itemCount: patterns.count)
                    .stroke(CrabrixTheme.border, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                AlgorithmTrailShape(itemCount: patterns.count)
                    .stroke(
                        tint.opacity(0.43),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [7, 9])
                    )

                ForEach(Array(patterns.enumerated()), id: \.element.id) { index, pattern in
                    AlgorithmPatternPathNode(
                        pattern: pattern,
                        patternNumber: index + 1,
                        completedLessonIDs: completedLessonIDs,
                        isUnlocked: isPatternUnlocked(pattern),
                        tint: tint,
                        onOpen: { onOpen(pattern) },
                        onBlocked: { onBlocked(pattern) }
                    )
                    .frame(width: geometry.size.width, height: AlgorithmMethodPathLayout.rowHeight)
                    .offset(y: CGFloat(index) * AlgorithmMethodPathLayout.rowHeight)
                }
            }
        }
        .frame(height: CGFloat(patterns.count) * AlgorithmMethodPathLayout.rowHeight)
    }
}

private struct AlgorithmTrailShape: Shape {
    let itemCount: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard itemCount > 0 else { return path }

        let first = point(at: 0, width: rect.width)
        path.move(to: first)
        for index in 1..<itemCount {
            let previous = point(at: index - 1, width: rect.width)
            let current = point(at: index, width: rect.width)
            let middleY = (previous.y + current.y) / 2
            path.addCurve(
                to: current,
                control1: CGPoint(x: previous.x, y: middleY),
                control2: CGPoint(x: current.x, y: middleY)
            )
        }
        return path
    }

    private func point(at index: Int, width: CGFloat) -> CGPoint {
        CGPoint(
            x: AlgorithmMethodPathLayout.nodeCenterX(width: width, index: index),
            y: CGFloat(index) * AlgorithmMethodPathLayout.rowHeight
                + AlgorithmMethodPathLayout.rowHeight / 2
        )
    }
}

private struct AlgorithmPatternPathNode: View {
    let pattern: AlgorithmPattern
    let patternNumber: Int
    let completedLessonIDs: Set<String>
    let isUnlocked: Bool
    let tint: Color
    let onOpen: () -> Void
    let onBlocked: () -> Void

    private var completedStageCount: Int {
        pattern.lessons.filter { completedLessonIDs.contains($0.id) }.count
    }

    private var isMastered: Bool {
        completedLessonIDs.contains(pattern.lessonID(.challenge))
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let nodeX = AlgorithmMethodPathLayout.nodeCenterX(width: width, index: patternNumber - 1)
            let labelToRight = AlgorithmMethodPathLayout.labelToRight(at: patternNumber - 1)
            let labelWidth = AlgorithmMethodPathLayout.labelWidth(for: width)
            let labelX = AlgorithmMethodPathLayout.labelCenterX(
                width: width,
                nodeX: nodeX,
                labelWidth: labelWidth,
                labelToRight: labelToRight
            )

            ZStack {
                nodeButton
                    .position(x: nodeX, y: AlgorithmMethodPathLayout.rowHeight / 2)

                nodeLabel(labelToRight: labelToRight)
                    .frame(width: labelWidth, alignment: labelToRight ? .leading : .trailing)
                    .position(x: labelX, y: AlgorithmMethodPathLayout.rowHeight / 2)
            }
        }
    }

    private var nodeButton: some View {
        Button(action: isUnlocked ? onOpen : onBlocked) {
            ZStack {
                Circle()
                    .fill(nodeShadowColor)
                    .offset(y: 6)
                Circle()
                    .fill(nodeColor)
                Circle()
                    .stroke(.white.opacity(isUnlocked ? 0.28 : 0.08), lineWidth: 3)
                    .padding(5)

                VStack(spacing: 2) {
                    Image(systemName: isMastered ? "checkmark" : (isUnlocked ? "function" : "lock.fill"))
                        .font(.system(size: 21, weight: .black))
                    if isUnlocked && !isMastered {
                        Text(completedStageCount == 0 ? "START" : "\(completedStageCount)/3")
                            .font(.system(size: 7, weight: .black, design: .monospaced))
                    }
                }
                .foregroundStyle(isUnlocked ? .white : CrabrixTheme.muted)
            }
            .frame(width: AlgorithmMethodPathLayout.nodeDiameter, height: AlgorithmMethodPathLayout.nodeDiameter)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pattern \(patternNumber), \(pattern.title)")
        .accessibilityValue(isMastered ? "Mastered" : (isUnlocked ? "\(completedStageCount) of 3 steps complete" : "Locked"))
    }

    private func nodeLabel(labelToRight: Bool) -> some View {
        let alignment: HorizontalAlignment = labelToRight ? .leading : .trailing
        let textAlignment: TextAlignment = labelToRight ? .leading : .trailing

        return VStack(alignment: alignment, spacing: 4) {
            HStack(spacing: 5) {
                if !labelToRight { Spacer(minLength: 0) }
                Text("PATTERN \(patternNumber.formatted(.number.precision(.integerLength(2))))")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(isUnlocked ? tint : CrabrixTheme.muted)
                Text(pattern.difficulty.title)
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(pattern.difficulty.tint)
                if labelToRight { Spacer(minLength: 0) }
            }

            Text(pattern.title)
                .font(.subheadline.bold())
                .foregroundStyle(CrabrixTheme.primary.opacity(isUnlocked ? 1 : 0.48))
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .multilineTextAlignment(textAlignment)

            Text(pattern.complexity)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(CrabrixTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            AlgorithmStageProgress(
                pattern: pattern,
                completedLessonIDs: completedLessonIDs,
                tint: tint,
                alignment: labelToRight ? .leading : .trailing
            )
        }
        .multilineTextAlignment(textAlignment)
    }

    private var nodeColor: Color {
        if isMastered { return CrabrixTheme.mint }
        if isUnlocked { return tint }
        return CrabrixTheme.raised
    }

    private var nodeShadowColor: Color {
        if isMastered { return CrabrixTheme.mint.opacity(0.52) }
        if isUnlocked { return tint.opacity(0.50) }
        return CrabrixTheme.border
    }
}

private struct AlgorithmStageProgress: View {
    let pattern: AlgorithmPattern
    let completedLessonIDs: Set<String>
    let tint: Color
    let alignment: Alignment

    private let stages: [(AlgorithmLessonStage, String)] = [
        (.model, "HOW"),
        (.recognize, "WHEN"),
        (.challenge, "SOLVE"),
    ]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(stages, id: \.0.rawValue) { stage, label in
                HStack(spacing: 2) {
                    Image(systemName: completedLessonIDs.contains(pattern.lessonID(stage)) ? "checkmark.circle.fill" : "circle")
                    Text(label)
                }
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(
                    completedLessonIDs.contains(pattern.lessonID(stage)) ? CrabrixTheme.mint : tint.opacity(0.78)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment)
    }
}

private struct AlgorithmMetric: View {
    let value: String
    let label: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.bold())
                .foregroundStyle(tint)
                .frame(width: 27, height: 27)
                .background(tint.opacity(0.13), in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.caption.monospaced().bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(CrabrixTheme.muted)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CrabrixTheme.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct AlgorithmMethodIndexView: View {
    @Environment(\.dismiss) private var dismiss

    let completedLessonIDs: Set<String>
    let isPatternUnlocked: (AlgorithmPattern) -> Bool
    let onSelect: (String) -> Void

    @State private var query = ""

    private var methods: [(offset: Int, element: AlgorithmCategory)] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return AlgorithmCourseCatalog.methods.enumerated().filter { _, method in
            trimmed.isEmpty
                || method.title.localizedCaseInsensitiveContains(trimmed)
                || method.subtitle.localizedCaseInsensitiveContains(trimmed)
                || method.patterns.contains {
                    $0.title.localizedCaseInsensitiveContains(trimmed)
                        || $0.useCases.localizedCaseInsensitiveContains(trimmed)
                }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(methods, id: \.element.id) { index, method in
                        Button {
                            onSelect(method.id)
                        } label: {
                            row(method: method, index: index)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(CrabrixTheme.background)
            .foregroundStyle(CrabrixTheme.primary)
            .navigationTitle("Solution Methods")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Method, pattern, or use case")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(method: AlgorithmCategory, index: Int) -> some View {
        let tint = AlgorithmMethodPalette.tint(at: index)
        let completed = method.patterns.filter {
            completedLessonIDs.contains($0.lessonID(.challenge))
        }.count
        let unlocked = method.patterns.first.map(isPatternUnlocked) ?? false

        return HStack(spacing: 12) {
            Image(systemName: unlocked ? method.systemImage : "lock.fill")
                .font(.headline)
                .foregroundStyle(unlocked ? tint : CrabrixTheme.muted)
                .frame(width: 43, height: 43)
                .background((unlocked ? tint : CrabrixTheme.muted).opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text("METHOD \((index + 1).formatted(.number.precision(.integerLength(2))))")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(unlocked ? tint : CrabrixTheme.muted)
                Text(method.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(CrabrixTheme.primary.opacity(unlocked ? 1 : 0.55))
                    .lineLimit(2)
                Text(method.subtitle)
                    .font(.caption2)
                    .foregroundStyle(CrabrixTheme.muted)
                    .lineLimit(2)
            }

            Spacer(minLength: 5)

            VStack(alignment: .trailing, spacing: 5) {
                Text("\(completed)/10")
                    .font(.caption2.monospaced().bold())
                    .foregroundStyle(unlocked ? tint : CrabrixTheme.muted)
                ProgressView(value: Double(completed), total: 10)
                    .tint(tint)
                    .frame(width: 48)
                Image(systemName: "chevron.right")
                    .font(.caption2.bold())
                    .foregroundStyle(CrabrixTheme.muted)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CrabrixTheme.panel, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 15).stroke(CrabrixTheme.border) }
    }
}

private enum AlgorithmMethodPalette {
    static func tint(at index: Int) -> Color {
        let colors: [Color] = [
            CrabrixTheme.indigo,
            CrabrixTheme.violet,
            CrabrixTheme.blue,
            CrabrixTheme.cyan,
            CrabrixTheme.mint,
            CrabrixTheme.amber,
            CrabrixTheme.coral,
        ]
        return colors[index % colors.count]
    }
}

/// Pure geometry for the algorithms path. Labels and nodes stay inside their
/// container even on an iPhone mini or a narrow iPad Split View.
enum AlgorithmMethodPathLayout {
    static let edgeInset: CGFloat = 7
    static let nodeDiameter: CGFloat = 72
    static let labelGap: CGFloat = 7
    static let rowHeight: CGFloat = 122

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
        return min(205, available, max(104, width * 0.46))
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

    private static func clamp(_ value: CGFloat, _ minimum: CGFloat, _ maximum: CGFloat) -> CGFloat {
        min(max(value, minimum), maximum)
    }
}

private extension AlgorithmDifficulty {
    var tint: Color {
        switch self {
        case .easy: CrabrixTheme.mint
        case .medium: CrabrixTheme.amber
        case .hard: CrabrixTheme.coral
        }
    }
}
