import SwiftUI

enum LearningRoute: Hashable {
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
    @State private var pendingDownload: CourseCatalogPayload.Entry?
    @State private var isManagingDownloads = false
    let completedLessonIDs: Set<String>
    let lessonAnswerIndices: [String: Int]
    let onStartLesson: (RustLesson, CourseSession) -> Void
    let onCompleteLesson: (RustLesson) -> Void
    let onAnswerLesson: (RustLesson, Int, Bool) -> Void
    let onOpenExample: (RustShowcaseProject, String) -> Void

    private let columns = [GridItem(.adaptive(minimum: 260), spacing: 16)]

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    hero
                    examplesCard
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

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Choose a course")
                            .font(.title2.bold())
                        Text("Start with the level you need. Each course has its own visual lesson path.")
                            .font(.subheadline)
                            .foregroundStyle(CrabrixTheme.muted)
                        Button("Check for course updates") {
                            Task { await academy.checkForUpdates() }
                        }
                        .font(.subheadline)
                        Button("Manage course downloads") {
                            isManagingDownloads = true
                        }
                        .font(.subheadline)
                        if let error = academy.catalogError {
                            Text("Update check unavailable: \(error)")
                                .font(.caption)
                                .foregroundStyle(CrabrixTheme.muted)
                        }
                    }

                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(academy.repository?.courses ?? []) { course in
                            VStack(alignment: .leading, spacing: 8) {
                                NavigationLink(value: LearningRoute.course(course.id)) {
                                    CourseCard(course: course)
                                }
                                .buttonStyle(.plain)
                                HStack {
                                    let version = academy.repository?.loaded[course.id]?.contentVersion ?? "—"
                                    Text("Installed · English · v\(version)")
                                        .font(.caption)
                                        .foregroundStyle(CrabrixTheme.muted)
                                    Spacer()
                                    if let entry = availableUpdate(for: course.id, installedVersion: version) {
                                        Button("Update") { pendingDownload = entry }
                                            .font(.caption.bold())
                                    }
                                }
                                if let transfer = academy.transfers[course.id + "|en"] {
                                    transferView(transfer, courseID: course.id)
                                }
                            }
                        }
                        ForEach(availableUninstalled.filter { $0.courseID != "projects" }, id: \.courseID) { entry in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(entry.courseID.replacingOccurrences(of: "-", with: " ").capitalized)
                                    .font(.headline)
                                Text("Available · \(entry.language) · v\(entry.contentVersion)")
                                    .font(.caption)
                                    .foregroundStyle(CrabrixTheme.muted)
                                Button("Download · \(ByteCountFormatter.string(fromByteCount: Int64(entry.archiveBytes), countStyle: .file))") {
                                    pendingDownload = entry
                                }
                                .font(.caption.bold())
                                if let transfer = academy.transfers[entry.courseID + "|" + entry.language] {
                                    transferView(transfer, courseID: entry.courseID)
                                }
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(CrabrixTheme.panel, in: RoundedRectangle(cornerRadius: 16))
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
            .navigationDestination(for: LearningRoute.self) { route in
                destination(for: route)
            }
            .sheet(isPresented: $isManagingDownloads) {
                NavigationStack {
                    List {
                        ForEach(academy.repository?.courses ?? []) { course in
                            let version = academy.repository?.loaded[course.id]?.contentVersion ?? "—"
                            VStack(alignment: .leading, spacing: 6) {
                                Text(course.title).font(.headline)
                                Text("Installed · English · v\(version)")
                                    .font(.caption)
                                    .foregroundStyle(CrabrixTheme.muted)
                                Button("Delete local course material", role: .destructive) {
                                    Task { await academy.deleteInstalled(courseID: course.id, language: "en") }
                                }
                            }
                        }
                    }
                    .navigationTitle("Course downloads")
                    .toolbar {
                        Button("Done") { isManagingDownloads = false }
                    }
                    .safeAreaInset(edge: .bottom) {
                        Text("Projects, attempts, and progress stay on this device. An open lesson keeps its current content until you leave it.")
                            .font(.caption)
                            .padding()
                    }
                }
            }
            .confirmationDialog(
                "Download course update?", isPresented: Binding(
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
                Text("The course remains available while its signed update downloads and verifies.")
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
        }
    }

    @ViewBuilder
    private func transferView(_ state: AcademyContentStore.TransferState,
                              courseID: String) -> some View {
        switch state {
        case let .downloading(received, total):
            HStack {
                ProgressView(value: Double(received), total: Double(max(total, 1)))
                Button("Pause") { academy.cancelDownload(courseID: courseID, language: "en") }
            }
        case .verifying:
            ProgressView("Verifying course")
        case .installed:
            Text("Update installed")
                .font(.caption)
                .foregroundStyle(CrabrixTheme.mint)
        case let .failed(message):
            HStack {
                Text(message).font(.caption).foregroundStyle(CrabrixTheme.muted)
                if let entry = academy.catalog?.courses.first(where: {
                    $0.courseID == courseID && $0.language == "en"
                }) {
                    Button("Resume") { pendingDownload = entry }
                }
            }
        }
    }

    private func availableUpdate(for courseID: String,
                                 installedVersion: String) -> CourseCatalogPayload.Entry? {
        guard let current = SemanticVersion(installedVersion) else { return nil }
        return academy.catalog?.courses
            .filter { $0.courseID == courseID && $0.language == "en" }
            .filter { SemanticVersion($0.contentVersion).map { $0 > current } ?? false }
            .max { lhs, rhs in
                (SemanticVersion(lhs.contentVersion) ?? current)
                    < (SemanticVersion(rhs.contentVersion) ?? current)
            }
    }

    private var availableUninstalled: [CourseCatalogPayload.Entry] {
        let installed = Set(academy.repository?.courses.map(\.id) ?? [])
        let entries = academy.catalog?.courses.filter { !installed.contains($0.courseID) } ?? []
        return Dictionary(grouping: entries, by: \.courseID).values.compactMap { versions in
            versions.max { lhs, rhs in
                (SemanticVersion(lhs.contentVersion) ?? SemanticVersion(major: 0, minor: 0, patch: 0))
                    < (SemanticVersion(rhs.contentVersion) ?? SemanticVersion(major: 0, minor: 0, patch: 0))
            }
        }.sorted { $0.courseID < $1.courseID }
    }

    @ViewBuilder
    private var examplesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Examples", systemImage: "curlybraces.square")
                .font(.title3.bold())
            if let installed = academy.repository?.loaded["projects"] {
                Text("\(installed.showcases.count) editable Rust examples · installed v\(installed.contentVersion)")
                    .font(.subheadline)
                    .foregroundStyle(CrabrixTheme.muted)
                NavigationLink(value: LearningRoute.examples) {
                    Label("Open examples", systemImage: "arrow.right")
                }
                .font(.subheadline.bold())
                if let update = availableUpdate(for: "projects", installedVersion: installed.contentVersion) {
                    Button("Update · \(ByteCountFormatter.string(fromByteCount: Int64(update.archiveBytes), countStyle: .file))") {
                        pendingDownload = update
                    }
                    .font(.caption)
                }
            } else if let entry = availableUninstalled.first(where: { $0.courseID == "projects" }) {
                Text("Install the Projects course and its editable examples. Source stays in the Academy package until you copy an example into My Projects.")
                    .font(.subheadline)
                    .foregroundStyle(CrabrixTheme.muted)
                Button("Download · \(ByteCountFormatter.string(fromByteCount: Int64(entry.archiveBytes), countStyle: .file))") {
                    pendingDownload = entry
                }
                .font(.subheadline.bold())
            }
            if let transfer = academy.transfers["projects|en"] {
                transferView(transfer, courseID: "projects")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CrabrixTheme.panel, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func destination(for route: LearningRoute) -> some View {
        switch route {
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

private struct CourseCard: View {
    let course: RustCourse

    private var lessonCount: Int { course.units.flatMap(\.lessons).count }
    private var tint: Color { course.theme.primaryColor }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Image(systemName: course.systemImage)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .frame(width: 50, height: 50)
                    .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 14))
                Spacer()
                Text(course.level)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(tint.opacity(0.11), in: Capsule())
            }

            Text(course.title)
                .font(.title3.bold())
            Text(course.subtitle)
                .font(.caption)
                .foregroundStyle(CrabrixTheme.muted)
                .lineLimit(3)

            Spacer(minLength: 0)

            HStack {
                Label(
                    course.id == "algorithms" ? "200 patterns" : "\(course.units.count) units",
                    systemImage: "square.stack.3d.up.fill"
                )
                Label(
                    course.id == "algorithms" ? "600 steps" : "\(lessonCount) lessons",
                    systemImage: "checklist"
                )
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title3)
                    .foregroundStyle(tint)
            }
            .font(.caption2.monospaced())
            .foregroundStyle(CrabrixTheme.muted)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 225, alignment: .leading)
        .background(
            LinearGradient(
                colors: [tint.opacity(0.08), CrabrixTheme.panel],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(tint.opacity(0.28)) }
    }
}
