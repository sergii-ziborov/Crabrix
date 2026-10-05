import SwiftUI

enum LearningRoute: Hashable {
    case courses
    case course(String)
    case lesson(String)
    case examples
    case example(String)
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
        if value.hasPrefix("example:") {
            return [.examples, .example(String(value.dropFirst("example:".count)))]
        }
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
    @State private var lessonSession: CourseSession?
    @State private var examplesSnapshot: LoadedCourse?
    @State private var appliedLaunchRoute = false
    let completedLessonIDs: Set<String>
    let lessonAnswerIndices: [String: Int]
    let onStartLesson: (RustLesson, CourseSession) -> Void
    let onCompleteLesson: (RustLesson) -> Void
    let onResetCourseProgress: (Set<String>) -> Void
    let onAnswerLesson: (RustLesson, Int, Bool) -> Void
    let onOpenExample: (RustShowcaseProject, String, String) -> Void

    var body: some View {
        NavigationStack(path: $navigationPath) {
            CourseLibraryView(
                navigationPath: $navigationPath,
                completedLessonIDs: completedLessonIDs,
                showsPractice: true,
                onOpenWeakTopic: openWeakTopic
            )
            .navigationDestination(for: LearningRoute.self) { route in
                destination(for: route)
            }
            .onChange(of: navigationPath) { _, path in
                if path.contains(.examples) {
                    if examplesSnapshot == nil {
                        examplesSnapshot = academy.repository?.loaded["examples"]
                            ?? academy.repository?.loaded["projects"]
                    }
                } else {
                    examplesSnapshot = nil
                }
                let lessonID = path.compactMap { route -> String? in
                    if case let .lesson(id) = route { return id }
                    return nil
                }.last
                if let lessonID {
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
                if route == [.courses] {
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
            CourseLibraryView(
                navigationPath: $navigationPath,
                completedLessonIDs: completedLessonIDs,
                showsPractice: false,
                onOpenWeakTopic: openWeakTopic
            )
        case .examples:
            if let snapshot = examplesSnapshot
                ?? academy.repository?.loaded["examples"]
                ?? academy.repository?.loaded["projects"],
               !snapshot.showcases.isEmpty {
                ProjectLibraryView(projects: snapshot.showcases) { project in
                    navigationPath.append(.example(project.id))
                }
            } else {
                ContentUnavailableView("Code examples unavailable", systemImage: "square.stack.3d.up.slash")
            }
        case let .example(exampleID):
            if let snapshot = examplesSnapshot
                ?? academy.repository?.loaded["examples"]
                ?? academy.repository?.loaded["projects"],
               let project = snapshot.showcases.first(where: { $0.id == exampleID }) {
                ExampleDetailView(project: project) {
                    onOpenExample(project, snapshot.course.id, snapshot.contentVersion)
                }
            } else {
                ContentUnavailableView("Example unavailable", systemImage: "curlybraces")
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
                    onShowAchievements: {
                        navigationPath.append(.profile)
                    },
                    onAnswer: { index, correct in
                        onAnswerLesson(lesson, index, correct)
                    }
                )
                .id(lesson.id)
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

    private func openWeakTopic(_ topic: String) {
        guard let repository = academy.repository,
              let lesson = repository.lesson(id: topic),
              let course = repository.course(containing: topic)
        else { return }
        navigationPath = [.course(course.id), .lesson(lesson.id)]
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

}

private struct CourseLibraryView: View {
    @Binding var navigationPath: [LearningRoute]
    @EnvironmentObject private var academy: AcademyContentStore
    @EnvironmentObject private var progress: CrabrixProgressStore
    @AppStorage("crabrix.learn.trainingSessions") private var trainingSessions = 0
    @AppStorage("crabrix.learn.recallSessions") private var recallSessions = 0
    @State private var pendingDownload: CourseCatalogPayload.Entry?
    @State private var pendingRemoval: (id: String, title: String)?
    let completedLessonIDs: Set<String>
    let showsPractice: Bool
    let onOpenWeakTopic: (String) -> Void

    private let columns = [GridItem(.adaptive(minimum: 260), spacing: 14)]

    private var installed: [RustCourse] {
        academy.repository?.courses.filter { $0.id != "examples" } ?? []
    }

    private var examplesInstalled: Bool {
        academy.repository?.loaded["examples"] != nil
    }

    private var examplesEntry: CourseCatalogPayload.Entry? {
        academy.catalog?.courses.filter { $0.courseID == "examples" }.max { lhs, rhs in
            (SemanticVersion(lhs.contentVersion) ?? SemanticVersion(major: 0, minor: 0, patch: 0))
                < (SemanticVersion(rhs.contentVersion) ?? SemanticVersion(major: 0, minor: 0, patch: 0))
        }
    }

    private var newerExamplesEntry: CourseCatalogPayload.Entry? {
        guard let entry = examplesEntry,
              let current = academy.repository?.loaded["examples"].map(\.contentVersion),
              let availableVersion = SemanticVersion(entry.contentVersion),
              let installedVersion = SemanticVersion(current),
              availableVersion > installedVersion else { return nil }
        return entry
    }

    private var available: [CourseCatalogPayload.Entry] {
        let installedIDs = Set(installed.map(\.id))
        let entries = academy.catalog?.courses.filter {
            $0.courseID != "examples" && !installedIDs.contains($0.courseID)
        } ?? []
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
                        Text("My courses").font(.title2.bold())
                        ForEach(installed) { course in
                            installedRow(course)
                        }
                    }
                }

                if examplesEntry != nil || examplesInstalled {
                    examplesSection
                }

                if showsPractice && !installed.isEmpty {
                    practiceGrid
                    if TopicMasteryStore.shared.summary.seen > 0 {
                        WeakTopicsCard(onSelect: onOpenWeakTopic)
                    }
                }

                if !available.isEmpty {
                    availableSection
                }

                if let error = academy.errorMessage {
                    ContentUnavailableView(
                        "Academy unavailable", systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                    Button("Retry") { Task { await academy.prepare() } }
                } else if academy.repository == nil {
                    ProgressView("Preparing Academy")
                } else if available.isEmpty && installed.isEmpty && examplesEntry == nil
                            && !examplesInstalled {
                    ContentUnavailableView("Course list unavailable", systemImage: "wifi.slash")
                    Button("Retry") { Task { await academy.checkForUpdates() } }
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 20)
            .frame(maxWidth: 660)
            .frame(maxWidth: .infinity)
        }
        .background(CrabrixTheme.background.ignoresSafeArea())
        .foregroundStyle(CrabrixTheme.primary)
        .navigationTitle(showsPractice ? "Learn" : "Courses")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if showsPractice { await academy.checkForUpdates() }
        }
        .toolbar {
            if showsPractice && !installed.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: LearningRoute.profile) {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel("Learning profile")
                }
            }
        }
        .confirmationDialog(
            pendingDownload?.courseID == "examples" ? "Download Code Examples?" : "Download course?",
            isPresented: Binding(
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
            Text("The selected material will be available offline after verification.")
        }
        .confirmationDialog(
            "Remove \(pendingRemoval?.title ?? "download")?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ), titleVisibility: .visible
        ) {
            if let removal = pendingRemoval {
                Button("Remove downloaded material", role: .destructive) {
                    pendingRemoval = nil
                    Task { await academy.deleteInstalled(courseID: removal.id, language: "en") }
                }
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("Saved projects and learning progress will stay on this device.")
        }
    }

    private var examplesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Code Examples").font(.title2.bold())
            if examplesInstalled {
                SwipeRevealCard(onDelete: { requestRemoval("examples", title: "Code Examples") }) {
                    HStack(spacing: 8) {
                        NavigationLink(value: LearningRoute.examples) {
                            HStack(spacing: 12) {
                                examplesIcon
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("46 open examples").font(.headline)
                                    Label("Offline", systemImage: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(CrabrixTheme.mint)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(CrabrixTheme.coral)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Browse 46 Code Examples, available offline")
                        Menu {
                            Button("Browse examples", systemImage: "square.stack.3d.up") {
                                navigationPath.append(.examples)
                            }
                            if let entry = newerExamplesEntry {
                                Button("Download latest examples", systemImage: "arrow.down.circle") {
                                    pendingDownload = entry
                                }
                            }
                            Button("Remove download", systemImage: "trash", role: .destructive) {
                                requestRemoval("examples", title: "Code Examples")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .frame(width: 40, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Code Examples options")
                    }
                    .padding(15)
                    .crabrixPanel(cornerRadius: 16)
                }
            } else if let entry = examplesEntry {
                HStack(spacing: 12) {
                    examplesIcon
                    VStack(alignment: .leading, spacing: 4) {
                        Text("46 open examples").font(.headline)
                        Text("Download to browse and open in Code")
                            .font(.caption)
                            .foregroundStyle(CrabrixTheme.muted)
                    }
                    Spacer(minLength: 0)
                    VStack(spacing: 3) {
                        Button { pendingDownload = entry } label: {
                            Label("Download", systemImage: "arrow.down.circle.fill")
                        }
                        .buttonStyle(.bordered)
                        .tint(CrabrixTheme.coral)
                        .font(.caption.bold())
                        .accessibilityLabel("Download 46 Code Examples for offline use")
                        Text(ByteCountFormatter.string(
                            fromByteCount: Int64(entry.archiveBytes), countStyle: .file
                        ))
                        .font(.caption2.monospaced())
                        .foregroundStyle(CrabrixTheme.muted)
                    }
                }
                .padding(15)
                .crabrixPanel(cornerRadius: 16)
            }
            if !examplesInstalled, let entry = examplesEntry,
               let transfer = academy.transfers["examples|" + entry.language] {
                transferView(transfer, entry: entry)
            }
        }
    }

    private var examplesIcon: some View {
        Image("CodeExamplesIcon")
            .resizable()
            .scaledToFit()
            .frame(width: 52, height: 52)
            .frame(width: 42, height: 42)
            .clipped()
            .accessibilityHidden(true)
    }

    private func requestRemoval(_ courseID: String, title: String) {
        pendingRemoval = (courseID, title)
    }

    private func installedRow(_ course: RustCourse) -> some View {
        let lessons = course.units.flatMap(\.lessons)
        let completed = lessons.filter { completedLessonIDs.contains($0.id) }.count
        return SwipeRevealCard(onDelete: { requestRemoval(course.id, title: course.title) }) {
          VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                NavigationLink(value: LearningRoute.course(course.id)) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            courseIcon(course.id, fallback: course.systemImage,
                                       tint: course.theme.primaryColor)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(course.title)
                                    .font(.headline)
                                    .lineLimit(2)
                                Label("Offline", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(CrabrixTheme.mint)
                            }
                            Spacer(minLength: 4)
                            Text(completed == 0 ? "Start" : (completed == lessons.count ? "Review" : "Continue"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(course.theme.primaryColor)
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(course.theme.primaryColor)
                        }
                        HStack {
                            Text("\(completed) of \(lessons.count) lessons")
                            Spacer()
                            Text("\(Int((Double(completed) / Double(max(lessons.count, 1)) * 100).rounded()))%")
                        }
                        .font(.caption.monospaced())
                        .foregroundStyle(CrabrixTheme.muted)
                        ProgressView(value: Double(completed), total: Double(max(lessons.count, 1)))
                            .tint(course.theme.primaryColor)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(course.title), \(completed) of \(lessons.count) lessons complete, available offline")
                Menu {
                    Button("Open course", systemImage: "book") {
                        navigationPath.append(.course(course.id))
                    }
                    Button("Remove download", systemImage: "trash", role: .destructive) {
                        requestRemoval(course.id, title: course.title)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 36, height: 44)
                }
                .accessibilityLabel("Manage download for \(course.title)")
            }
            if course.id == "projects", academy.repository?.loaded["projects"]?.showcases.isEmpty == false {
                NavigationLink("Open Code Examples", value: LearningRoute.examples)
                    .font(.caption.weight(.semibold))
            }
          }
          .padding(15)
          .crabrixPanel(cornerRadius: 16)
        }
    }

    private var availableSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(installed.isEmpty ? "Choose a course" : "Explore courses")
                .font(.title2.bold())
            ForEach(available, id: \.courseID) { entry in
                let preview = Self.preview(entry.courseID)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        courseIcon(entry.courseID, fallback: preview.icon, tint: CrabrixTheme.coral)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(preview.title).font(.headline)
                            Text(preview.subtitle)
                                .font(.caption)
                                .foregroundStyle(CrabrixTheme.muted)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        VStack(spacing: 3) {
                            Button { pendingDownload = entry } label: {
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
                .crabrixPanel(cornerRadius: 14)
            }
        }
    }

    private var practiceGrid: some View {
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

    private func icon(_ name: String, tint: Color) -> some View {
        Image(systemName: name)
            .font(.title3)
            .foregroundStyle(tint)
            .frame(width: 42, height: 42)
            .background(tint.opacity(0.12), in: CrabrixCardShape(cornerRadius: 11))
    }

    @ViewBuilder
    private func courseIcon(_ courseID: String, fallback: String, tint: Color) -> some View {
        if let assetName = Self.courseIconAsset(for: courseID) {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(width: 51, height: 51)
                .frame(width: 42, height: 42)
                .clipped()
                .background(tint.opacity(0.08), in: CrabrixCardShape(cornerRadius: 11))
                .accessibilityHidden(true)
        } else {
            icon(fallback, tint: tint)
        }
    }

    private static func courseIconAsset(for id: String) -> String? {
        switch id {
        case "basics": "CourseBasicsIcon"
        case "ownership": "CourseOwnershipIcon"
        case "projects": "CourseProjectsIcon"
        case "concurrency": "CourseConcurrencyIcon"
        case "systems": "CourseSystemsIcon"
        case "interview": "CourseInterviewIcon"
        case "algorithms": "CourseAlgorithmsIcon"
        default: nil
        }
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
        case "projects": ("Cargo & Real Projects", "Modules, packages, and reliable Rust apps", "shippingbox.fill")
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

/// Reveals the same destructive action exposed by the options menu without
/// making a vertical library scroll depend on a List container.
private struct SwipeRevealCard<Content: View>: View {
    @State private var revealed = false
    let onDelete: () -> Void
    let content: Content

    init(onDelete: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.onDelete = onDelete
        self.content = content()
    }

    var body: some View {
        content
            .offset(x: revealed ? -90 : 0)
            .simultaneousGesture(
                DragGesture(minimumDistance: 20).onEnded { gesture in
                    guard abs(gesture.translation.width) > abs(gesture.translation.height) * 1.3 else {
                        return
                    }
                    if gesture.translation.width < -45 {
                        withAnimation(.easeOut(duration: 0.2)) { revealed = true }
                    } else if gesture.translation.width > 35 {
                        withAnimation(.easeOut(duration: 0.2)) { revealed = false }
                    }
                }
            )
            .background(alignment: .trailing) {
                GeometryReader { geometry in
                    Button {
                        revealed = false
                        onDelete()
                    } label: {
                        Label("Remove", systemImage: "trash")
                            .font(.caption.bold())
                            .frame(width: 90, height: geometry.size.height)
                    }
                    .foregroundStyle(.white)
                    .background(CrabrixTheme.danger)
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityLabel("Remove downloaded material")
                }
            }
            .clipShape(CrabrixCardShape(cornerRadius: 16))
            .accessibilityAction(named: "Remove download", onDelete)
    }
}
