import SwiftUI

enum LearningRoute: Hashable {
    case courses
    case course(String)
    case lesson(String)
    case examples
    case profile

    /// Opens a Learn screen straight from a launch argument, the same way
    /// `-CrabrixTab` opens a tab. Store screenshots are captured this way so
    /// the same frames come out of every build.
    static func launchArgument(repository: any CourseRepository) -> [LearningRoute] {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-CrabrixLearn"),
              index + 1 < arguments.count
        else { return [] }

        let value = arguments[index + 1]
        if value == "courses" { return [.courses] }
        if value == "profile" { return [.profile] }
        if value == "examples" { return [.examples] }
        if let course = repository.course(id: value) { return [.course(course.id)] }
        if let lesson = repository.lesson(id: value),
           let course = repository.course(containing: lesson.id) {
            return [.course(course.id), .lesson(lesson.id)]
        }
        return []
    }
}

struct LearningHubView: View {
    @Binding var navigationPath: [LearningRoute]
    @EnvironmentObject private var academy: AcademyContentStore
    @EnvironmentObject private var progress: CrabrixProgressStore
    @AppStorage("crabrix.learn.trainingSessions") private var trainingSessions = 0
    @AppStorage("crabrix.learn.recallSessions") private var recallSessions = 0
    @State private var lessonSession: CourseSession?
    @State private var examplesSnapshot: LoadedCourse?
    @State private var appliedLaunchRoute = false
    @State private var initialCatalogRoot: Bool?
    let completedLessonIDs: Set<String>
    let lessonAnswerIndices: [String: Int]
    let onStartLesson: (RustLesson, CourseSession) -> Void
    let onCompleteLesson: (RustLesson) -> Void
    let onResetCourseProgress: (Set<String>) -> Void
    let onAnswerLesson: (RustLesson, Int, Bool) -> Void
    let onOpenExample: (RustShowcaseProject, String) -> Void

    private let columns = [GridItem(.adaptive(minimum: 260), spacing: 16)]

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
            if initialCatalogRoot == true {
                CourseLibraryView()
            } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !(academy.repository?.courses.isEmpty ?? true) { hero }
                    NavigationLink(value: LearningRoute.courses) {
                        HStack(spacing: 14) {
                            Image(systemName: "books.vertical.fill")
                                .font(.title2)
                                .foregroundStyle(CrabrixTheme.coral)
                                .frame(width: 48, height: 48)
                                .background(CrabrixTheme.coral.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Courses").font(.headline)
                                Text("Choose and download for offline learning")
                                    .font(.caption)
                                    .foregroundStyle(CrabrixTheme.muted)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .foregroundStyle(CrabrixTheme.coral)
                        }
                        .padding(16)
                        .background(CrabrixTheme.panel, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    if !(academy.repository?.courses.isEmpty ?? true) {
                    WeakTopicsCard { topic in
                        guard let repository = academy.repository,
                              let lesson = repository.lesson(id: topic),
                              let course = repository.course(containing: topic)
                        else { return }
                        navigationPath = [.course(course.id), .lesson(lesson.id)]
                    }

                    LazyVGrid(columns: columns, spacing: 14) {
                        NavigationLink {
                            QuickPracticeView()
                        } label: {
                            LearningPracticeCard(
                                title: "Quick Practice",
                                subtitle: "Choose · match · arrange code by dragging",
                                badge: "5 MIN",
                                systemImage: "bolt.fill",
                                tint: CrabrixTheme.amber
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            TermMatchTrainView { trainingSessions += 1 }
                        } label: {
                            LearningPracticeCard(
                                title: "Term Train",
                                subtitle: "Connect Rust terms with short descriptions",
                                badge: trainingSessions == 0 ? "NEW" : "\(trainingSessions) RUNS",
                                systemImage: "link",
                                tint: CrabrixTheme.mint
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            CodeRecallView { recallSessions += 1 }
                        } label: {
                            LearningPracticeCard(
                                title: "Code Recall",
                                subtitle: "Memorise a snippet, then rebuild it line by line",
                                badge: progress.state.codeRecallBestLevel > 0
                                    ? "BEST \(progress.state.codeRecallBestLevel)"
                                    : "NEW",
                                systemImage: "brain.head.profile",
                                tint: CrabrixTheme.blue
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    }

                    if let error = academy.errorMessage {
                        ContentUnavailableView(
                            "Academy unavailable", systemImage: "exclamationmark.triangle",
                            description: Text(error)
                        )
                        Button("Retry") { Task { await academy.prepare() } }
                    } else if academy.repository == nil {
                        ProgressView("Preparing Academy")
                    }
                }
                .padding(22)
                .frame(maxWidth: 920)
                .frame(maxWidth: .infinity)
            }
            .background(CrabrixTheme.background.ignoresSafeArea())
            .foregroundStyle(CrabrixTheme.primary)
            .navigationTitle("Learn Rust")
            }
            }
            .navigationDestination(for: LearningRoute.self) { route in
                destination(for: route)
            }
            .onChange(of: navigationPath) { _, path in
                if case .examples = path.last {
                    if examplesSnapshot == nil { examplesSnapshot = academy.repository?.loaded["projects"] }
                } else {
                    examplesSnapshot = nil
                }
                if case let .lesson(lessonID) = path.last {
                    if lessonSession?.lessonID != lessonID,
                       let repository = academy.repository {
                        lessonSession = CourseSession(lessonID: lessonID, repository: repository)
                    }
                } else {
                    lessonSession = nil
                }
            }
            .onChange(of: academy.repository?.courses.count) { _, _ in
                if lessonSession == nil,
                   case let .lesson(lessonID) = navigationPath.last,
                   let repository = academy.repository {
                    lessonSession = CourseSession(lessonID: lessonID, repository: repository)
                }
            }
            .task(id: academy.repository?.courses.count) {
                if initialCatalogRoot == nil, let repository = academy.repository {
                    initialCatalogRoot = repository.courses.isEmpty
                }
                guard !appliedLaunchRoute,
                      let repository = academy.repository else { return }
                let arguments = ProcessInfo.processInfo.arguments
                var route = LearningRoute.launchArgument(repository: repository)
                if arguments.contains("-CrabrixLibrary") || arguments.contains("-CrabrixCanvasGallery") {
                    route = [.examples]
                }
                if let argument = arguments.first(where: { $0.hasPrefix("--crabrix-auto-lesson=") }) {
                    let lessonID = String(argument.dropFirst("--crabrix-auto-lesson=".count))
                    if let lesson = repository.lesson(id: lessonID),
                       let course = repository.course(containing: lesson.id) {
                        route = [.course(course.id), .lesson(lesson.id)]
                    }
                }
                guard !route.isEmpty else { return }
                if route == [.courses], initialCatalogRoot == true {
                    appliedLaunchRoute = true
                    return
                }
                appliedLaunchRoute = true
                // Wait until NavigationStack is mounted before setting its bound path.
                await Task.yield()
                navigationPath = route
            }
        }
    }

    @ViewBuilder
    private func destination(for route: LearningRoute) -> some View {
        switch route {
        case .courses:
            CourseLibraryView()
        case .examples:
            if let snapshot = examplesSnapshot ?? academy.repository?.loaded["projects"],
               !snapshot.showcases.isEmpty {
                ProjectLibraryView(projects: snapshot.showcases) { project in
                    onOpenExample(project, snapshot.contentVersion)
                }
            } else {
                ContentUnavailableView("Examples unavailable", systemImage: "square.stack.3d.up.slash")
            }
        case let .course(courseID):
            if let course = academy.repository?.course(id: courseID) {
                LearnPathView(
                    units: course.units,
                    courseTitle: course.title,
                    courseTheme: course.theme,
                    completedLessonIDs: completedLessonIDs,
                    unlockScope: course.id == "algorithms" ? .independentUnits : .course,
                    onResetProgress: {
                        onResetCourseProgress(Set(course.units.flatMap(\.lessons).map(\.id)))
                    },
                    onOpenLesson: { lesson in
                        navigationPath.append(.lesson(lesson.id))
                    }
                )
            } else {
                ContentUnavailableView("Course unavailable", systemImage: "book.closed")
            }

        case .profile:
            ProfileView(completedLessonIDs: completedLessonIDs)

        case let .lesson(lessonID):
            if let repository = lessonSession?.repository ?? academy.repository,
               let lesson = repository.lesson(id: lessonID),
               let writing = repository.writing(for: lessonID),
               let depth = repository.depth(for: lessonID),
               let course = repository.course(containing: lessonID),
               let session = lessonSession ?? CourseSession(lessonID: lessonID, repository: repository) {
                let isReview = completedLessonIDs.contains(lesson.id)
                LessonDetailView(
                    lesson: lesson,
                    writing: writing,
                    lessonDepth: depth,
                    courseTheme: course.theme,
                    isCompleted: isReview,
                    savedAnswer: lessonAnswerIndices[lesson.id],
                    onStart: { onStartLesson(lesson, session) },
                    onComplete: {
                        completeAndContinue(from: lesson)
                    },
                    onAnswer: { index, correct in
                        onAnswerLesson(lesson, index, correct)
                    }
                )
                .id(session.token)
            } else {
                ContentUnavailableView("Lesson unavailable", systemImage: "book.closed")
            }
        }
    }

    private func returnToCourse(containing lesson: RustLesson) {
        guard let course = academy.repository?.course(containing: lesson.id) else {
            navigationPath = []
            return
        }
        navigationPath = [.course(course.id)]
    }

    private func completeAndContinue(from lesson: RustLesson) {
        onCompleteLesson(lesson)
        let completed = completedLessonIDs.union([lesson.id])
        if let course = academy.repository?.course(containing: lesson.id),
           course.id == "algorithms" {
            let methodLessons = course.units.first { $0.lessons.contains { $0.id == lesson.id } }?.lessons ?? []
            if let position = methodLessons.firstIndex(where: { $0.id == lesson.id }),
               methodLessons.indices.contains(position + 1) {
                let next = methodLessons[position + 1]
                navigationPath = [.course("algorithms"), .lesson(next.id)]
            } else {
                navigationPath = [.course("algorithms")]
            }
            return
        }
        guard let courses = academy.repository?.courses,
              let step = RustLessonProgression.nextStep(
                after: lesson.id, completedLessonIDs: completed, courses: courses
              ), step.lessonID != lesson.id else {
            returnToCourse(containing: lesson)
            return
        }
        navigationPath = [.course(step.courseID), .lesson(step.lessonID)]
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 18) {
                Image(systemName: "map.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(CrabrixTheme.mint)
                    .frame(width: 70, height: 70)
                    .background(CrabrixTheme.mint.opacity(0.13), in: RoundedRectangle(cornerRadius: 20))
                VStack(alignment: .leading, spacing: 5) {
                    Text("CRABRIX ACADEMY")
                        .font(.caption.monospaced().bold())
                        .foregroundStyle(CrabrixTheme.coral)
                    Text("Learn Rust by building")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Short explanations, compiler-backed labs across the curriculum, and a visible next step.")
                        .foregroundStyle(CrabrixTheme.muted)
                }
                Spacer(minLength: 0)
            }

            if !(academy.repository?.courses.isEmpty ?? true) {
            VStack(spacing: 7) {
                HStack {
                    Label("OVERALL PROGRESS", systemImage: "chart.line.uptrend.xyaxis")
                    Spacer()
                    Text("\(completedLessonCount) / \(totalLessonCount) lessons · \(progressPercent)%")
                }
                .font(.caption.monospaced().bold())
                .foregroundStyle(CrabrixTheme.muted)
                ProgressView(value: Double(completedLessonCount), total: Double(max(totalLessonCount, 1)))
                    .tint(CrabrixTheme.mint)
            }

            Divider().overlay(CrabrixTheme.border)

            NavigationLink(value: LearningRoute.profile) {
                ratingStrip
            }
            .buttonStyle(.plain)
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [CrabrixTheme.blue.opacity(0.12), CrabrixTheme.panel],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20).stroke(CrabrixTheme.border) }
    }

    private var ratingStrip: some View {
        let rank = progress.rank
        return HStack(spacing: 12) {
            Image(systemName: rank.systemImage)
                .font(.headline)
                .foregroundStyle(CrabrixTheme.amber)
                .frame(width: 38, height: 38)
                .background(
                    CrabrixTheme.amber.opacity(0.14),
                    in: RoundedRectangle(cornerRadius: 11)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text("RATING")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(CrabrixTheme.muted)
                Text(CrabrixPointsFormatter.string(progress.state.totalPoints))
                    .font(.title3.bold())
                    .monospacedDigit()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(rank.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(CrabrixTheme.mint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                ProgressView(value: rank.progress(points: progress.state.totalPoints))
                    .tint(CrabrixTheme.amber)
                Text("\(progress.earnedAchievements.count)/\(progress.allAchievements.count) achievements")
                    .font(.caption2.monospaced())
                    .foregroundStyle(CrabrixTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(CrabrixTheme.muted)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Rating \(progress.state.totalPoints), rank \(rank.title). Open profile."
        )
    }

    private var totalLessonCount: Int {
        academy.repository?.courses.flatMap(\.units).flatMap(\.lessons).count ?? 0
    }

    private var completedLessonCount: Int {
        let allLessonIDs = Set(academy.repository?.courses.flatMap(\.units).flatMap(\.lessons).map(\.id) ?? [])
        return completedLessonIDs.intersection(allLessonIDs).count
    }

    private var progressPercent: Int {
        guard totalLessonCount > 0 else { return 0 }
        return Int((Double(completedLessonCount) / Double(totalLessonCount) * 100).rounded())
    }

}

private struct CourseLibraryView: View {
    @EnvironmentObject private var academy: AcademyContentStore
    @State private var pendingDownload: CourseCatalogPayload.Entry?

    private var installed: [RustCourse] { academy.repository?.courses ?? [] }

    private var available: [CourseCatalogPayload.Entry] {
        let installedIDs = Set(installed.map(\.id))
        let entries = academy.catalog?.courses.filter { !installedIDs.contains($0.courseID) } ?? []
        return Dictionary(grouping: entries, by: \.courseID).values.compactMap { versions in
            versions.max { lhs, rhs in
                (SemanticVersion(lhs.contentVersion) ?? SemanticVersion(major: 0, minor: 0, patch: 0))
                    < (SemanticVersion(rhs.contentVersion) ?? SemanticVersion(major: 0, minor: 0, patch: 0))
            }
        }.sorted { Self.order($0.courseID) < Self.order($1.courseID) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !installed.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Downloaded").font(.title2.bold())
                        ForEach(installed) { course in
                            HStack(spacing: 10) {
                                NavigationLink(value: LearningRoute.course(course.id)) {
                                    HStack(spacing: 12) {
                                        icon(course.systemImage, tint: course.theme.primaryColor)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(course.title).font(.headline)
                                            Label("Available offline", systemImage: "checkmark.circle.fill")
                                                .font(.caption)
                                                .foregroundStyle(CrabrixTheme.mint)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.right")
                                            .font(.caption.bold())
                                            .foregroundStyle(CrabrixTheme.muted)
                                    }
                                }
                                .buttonStyle(.plain)
                                Menu {
                                    Button("Remove download", role: .destructive) {
                                        Task { await academy.deleteInstalled(courseID: course.id, language: "en") }
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .frame(width: 36, height: 36)
                                }
                                .accessibilityLabel("Manage download for \(course.title)")
                            }
                            .padding(12)
                            .background(CrabrixTheme.panel, in: RoundedRectangle(cornerRadius: 14))
                            if course.id == "projects" {
                                NavigationLink("Open 46 Examples", value: LearningRoute.examples)
                                    .font(.caption.weight(.semibold))
                                    .padding(.leading, 12)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Available").font(.title2.bold())
                    ForEach(available, id: \.courseID) { entry in
                        let preview = Self.preview(entry.courseID)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                icon(preview.icon, tint: CrabrixTheme.coral)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(preview.title).font(.headline)
                                    Text(preview.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(CrabrixTheme.muted)
                                        .lineLimit(2)
                                }
                                Spacer(minLength: 0)
                                VStack(spacing: 3) {
                                    Button {
                                        pendingDownload = entry
                                    } label: {
                                        Label("Download", systemImage: "arrow.down.circle.fill")
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(CrabrixTheme.coral)
                                    .font(.caption.bold())
                                    .accessibilityLabel("Download \(preview.title) for offline use")
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(entry.archiveBytes), countStyle: .file))
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(CrabrixTheme.muted)
                                }
                            }
                            if let transfer = academy.transfers[entry.courseID + "|" + entry.language] {
                                transferView(transfer, entry: entry)
                            }
                        }
                        .padding(14)
                        .background(CrabrixTheme.panel, in: RoundedRectangle(cornerRadius: 14))
                    }
                    if available.isEmpty && installed.isEmpty {
                        ContentUnavailableView("Course list unavailable", systemImage: "wifi.slash")
                        Button("Retry") { Task { await academy.checkForUpdates() } }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(CrabrixTheme.background.ignoresSafeArea())
        .navigationTitle("Courses")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Download course?", isPresented: Binding(
                get: { pendingDownload != nil },
                set: { if !$0 { pendingDownload = nil } }
            ), titleVisibility: .visible
        ) {
            if let entry = pendingDownload {
                Button("Download \(ByteCountFormatter.string(fromByteCount: Int64(entry.archiveBytes), countStyle: .file))") {
                    academy.download(entry)
                    pendingDownload = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingDownload = nil }
        } message: {
            Text("The selected course will be available offline after verification.")
        }
    }

    private func icon(_ name: String, tint: Color) -> some View {
        Image(systemName: name)
            .font(.title3)
            .foregroundStyle(tint)
            .frame(width: 42, height: 42)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
    }

    @ViewBuilder
    private func transferView(_ state: AcademyContentStore.TransferState,
                              entry: CourseCatalogPayload.Entry) -> some View {
        switch state {
        case let .downloading(received, total):
            HStack {
                ProgressView(value: Double(received), total: Double(max(total, 1)))
                Button("Pause") {
                    academy.cancelDownload(courseID: entry.courseID, language: entry.language)
                }
            }
        case .verifying:
            ProgressView("Verifying")
        case .installed:
            Label("Available offline", systemImage: "checkmark.circle.fill")
                .foregroundStyle(CrabrixTheme.mint)
        case let .failed(message):
            VStack(alignment: .leading, spacing: 6) {
                Text(message).font(.caption).foregroundStyle(CrabrixTheme.muted)
                Button("Resume") { pendingDownload = entry }
            }
        }
    }

    private static func order(_ id: String) -> Int {
        ["basics", "ownership", "projects", "concurrency", "systems", "interview", "algorithms"]
            .firstIndex(of: id) ?? Int.max
    }

    private static func preview(_ id: String) -> (title: String, subtitle: String, icon: String) {
        switch id {
        case "basics": ("Rust Basics", "Start writing reliable Rust", "leaf.fill")
        case "ownership": ("Ownership Mastery", "Borrowing, lifetimes and traits", "lock.fill")
        case "projects": ("Cargo & Real Projects", "Projects, packages and 46 Examples", "shippingbox.fill")
        case "concurrency": ("Concurrency & Async", "Threads, channels and async Rust", "arrow.triangle.2.circlepath")
        case "systems": ("Macros & Systems Rust", "Unsafe, FFI and performance", "cpu.fill")
        case "interview": ("Rust Interview Prep", "Explain and practise core ideas", "person.crop.rectangle.stack.fill")
        case "algorithms": ("Algorithm Atlas", "200 patterns and Rust challenges", "square.grid.3x3.fill")
        default: (id.replacingOccurrences(of: "-", with: " ").capitalized, "Rust course", "book.closed.fill")
        }
    }
}

private struct LearningPracticeCard: View {
    let title: String
    let subtitle: String
    let badge: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 48, height: 48)
                .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(CrabrixTheme.muted)
                    .lineLimit(2)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 5) {
                Text(badge)
                    .font(.caption2.monospaced().bold())
                    .foregroundStyle(tint)
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title3)
                    .foregroundStyle(tint)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(tint.opacity(0.3)) }
    }
}
