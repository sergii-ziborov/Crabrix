import SwiftUI

enum LearningRoute: Hashable {
    case courses
    case course(String)
    case lesson(String)
    case examples
    case example(String)
    case profile
    /// Learn with AI. Navigation state only; routes are never persisted.
    case learnWithAI

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
        if value == "with-ai" { return AcademyAIFeature.isEnabled ? [.learnWithAI] : [] }
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
    /// Lessons the learner finished themselves.
    let completedLessonIDs: Set<String>
    /// Lessons a completed bridge lesson vouches for: target → bridge lesson.
    var creditedLessonIDs: [String: String] = [:]
    let lessonAnswerIndices: [String: Int]
    let onStartLesson: (RustLesson, CourseSession) -> Void
    let onCompleteLesson: (RustLesson) -> Void
    let onResetCourseProgress: (Set<String>) -> Void
    let onAnswerLesson: (RustLesson, Int, Bool) -> Void
    let onOpenExample: (RustShowcaseProject, String, String) -> Void
    let onOpenCompanion: (CourseProjectTemplate, CourseSession) -> Void
    let onOpenReplay: (AtlasRecording, CourseSession) -> Void

    /// Completed or credited: what the course path counts as done.
    private var learnedLessonIDs: Set<String> {
        LessonCredits.learned(completed: completedLessonIDs, credited: creditedLessonIDs)
    }

    /// "Known from C" per credited lesson, from the bridge course that granted it.
    private var creditLabels: [String: String] {
        let repository = academy.repository
        return creditedLessonIDs.mapValues { source in
            LessonCredits.knownLabel(forCourseTitle: repository?.course(containing: source)?.title)
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            CourseLibraryView(
                navigationPath: $navigationPath,
                completedLessonIDs: learnedLessonIDs,
                showsPractice: true,
                onOpenWeakTopic: openWeakTopic,
                officialCompletedLessonIDs: completedLessonIDs
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
                    LearningLinkController.shared.lessonDidOpen(lessonID: lessonID, repository: academy.repository)
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
                completedLessonIDs: learnedLessonIDs,
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
                    completedLessonIDs: learnedLessonIDs,
                    creditLabels: creditLabels,
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

        case .learnWithAI:
            if AcademyAIFeature.isEnabled {
                LearnWithAIView(currentLesson: nil, progress: aiLearningProgress())
            } else {
                ContentUnavailableView("Learn with AI unavailable", systemImage: "sparkles")
            }

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
                    illustration: repository.illustration(for: lessonID),
                    bridge: repository.bridge(for: lessonID),
                    bridgeCreditTitles: repository.creditTargets(for: lessonID)
                        .compactMap { repository.lesson(id: $0)?.title },
                    knownFrom: isReview ? nil : creditLabels[lessonID],
                    courseTheme: course.theme,
                    isCompleted: isReview,
                    savedAnswer: lessonAnswerIndices[lesson.id],
                    replayMethod: course.id == "algorithms"
                        ? course.units.first(where: { $0.lessons.contains(where: { $0.id == lessonID }) })
                            .map { String($0.id.dropFirst("algorithms-".count)) } : nil,
                    onOpenReplay: { recording in onOpenReplay(recording, session) },
                    onStart: { onStartLesson(lesson, session) },
                    onOpenCompanion: repository.workflowCompanion(for: lessonID).map { template in
                        { onOpenCompanion(template, session) }
                    },
                    onComplete: {
                        completeAndContinue(from: lesson)
                    },
                    onShowAchievements: {
                        navigationPath.append(.profile)
                    },
                    onAnswer: { index, correct in
                        onAnswerLesson(lesson, index, correct)
                    },
                    learnWithAI: AcademyAIFeature.isEnabled
                        ? LessonAIContext(
                            lesson: AcademyAILessonContext(courseID: course.id, lesson: lesson, rule: writing.rule),
                            progress: aiLearningProgress()
                        ) : nil
                )
                .id(lesson.id)
            } else {
                ContentUnavailableView("Lesson unavailable", systemImage: "book.closed")
            }
        }
    }

    /// Read only when the learner exports with "Include my completed lessons"
    /// on: the two progress sets this view already holds, and which installed
    /// course each lesson belongs to.
    private func aiLearningProgress() -> @MainActor () -> AILearningState.Progress {
        let completed = completedLessonIDs
        let credited = creditedLessonIDs
        let courses = academy.repository?.courses ?? []
        return { AILearningState.Progress(completed: completed, credited: credited, courses: courses) }
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
        let completed = learnedLessonIDs.union([lesson.id])
            .union(academy.repository?.creditTargets(for: lesson.id) ?? [])
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
              ), step.lessonID != lesson.id,
              // A lesson opened out of order, as from Weak Topics, must not lead
              // straight into a lesson the course map still shows as locked.
              RustLessonProgression.isOpen(step, completedLessonIDs: completed, courses: courses) else {
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
    @AppStorage("crabrix.learn.flashcardSessions") private var flashcardSessions = 0
    @State private var pendingDownload: CourseCatalogPayload.Entry?
    @State private var confirmUpdateAll = false
    @State private var pendingRemoval: (id: String, title: String)?
    /// The one library card whose swipe actions are showing.
    @State private var openSwipeCard: String?
    let completedLessonIDs: Set<String>
    let showsPractice: Bool
    let onOpenWeakTopic: (String) -> Void
    /// The app's own completions (no credits): "From your AI tutor" marks an
    /// assignment done only when its lesson is here.
    var officialCompletedLessonIDs: Set<String> = []
    @ObservedObject private var learningLink = LearningLinkController.shared

    private let columns = [GridItem(.adaptive(minimum: 260), spacing: 14)]

    private var installed: [RustCourse] {
        academy.repository?.courses.filter { $0.id != "examples" } ?? []
    }

    private var examplesInstalled: Bool {
        academy.repository?.loaded["examples"] != nil
    }

    private var examplesEntry: CourseCatalogPayload.Entry? {
        academy.availableDownloads.first { entry in
            entry.courseID == "examples" && !unavailableIDs.contains(entry.courseID)
        }
    }

    private var unavailableIDs: Set<String> {
        Set(academy.unavailableCourses.map(\.courseID))
    }

    private var newerExamplesEntry: CourseCatalogPayload.Entry? {
        academy.updateEntry(for: "examples")
    }

    private var available: [CourseCatalogPayload.Entry] {
        academy.availableDownloads.filter { $0.courseID != "examples" && !unavailableIDs.contains($0.courseID) }
            .sorted { Self.order($0.courseID) < Self.order($1.courseID) }
    }

    private var updates: [CourseCatalogPayload.Entry] {
        academy.availableUpdates.sorted { Self.order($0.courseID) < Self.order($1.courseID) }
    }

    /// An extra, optional entry; hidden by `AcademyAIFeature.isEnabled`.
    private var showsLearnWithAI: Bool {
        AcademyAIFeature.isEnabled && academy.repository != nil && academy.errorMessage == nil
    }

    private var pendingIsUpdate: Bool {
        pendingDownload.flatMap { academy.repository?.loaded[$0.courseID] } != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if showsPractice && AcademyAIFeature.isEnabled && !learningLink.tutorPlan.isEmpty,
                   academy.repository != nil {
                    TutorPlanCard(
                        link: learningLink,
                        catalog: learningLink.catalog,
                        completedLessonIDs: officialCompletedLessonIDs,
                        onOpen: openTutorLesson
                    )
                }

                if !updates.isEmpty { updateSummary }

                if !academy.unavailableCourses.isEmpty { unavailableSection }

                if !installed.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("My courses").font(.title2.bold())
                        ForEach(installed) { course in
                            installedRow(course, showsSwipeHint: course.id == installed.first?.id)
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

                if showsLearnWithAI && !installed.isEmpty { learnWithAISection }

                if !available.isEmpty {
                    availableSection
                }

                if showsLearnWithAI && installed.isEmpty { learnWithAISection }

                if let catalogError = academy.catalogError {
                    HStack(spacing: 8) {
                        Image(systemName: "wifi.slash")
                        Text("Could not check for new lessons: \(catalogError)")
                            .font(.caption)
                        Button("Retry") { Task { await academy.checkForUpdates() } }
                            .font(.caption.bold())
                    }
                    .foregroundStyle(CrabrixTheme.muted)
                }

                if let error = academy.errorMessage {
                    ContentUnavailableView(
                        "Academy unavailable", systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                    Button("Retry") { Task { await academy.prepare() } }
                } else if academy.repository == nil {
                    CrabrixLoadingView("Preparing Academy…", placement: .centered)
                } else if available.isEmpty && installed.isEmpty && examplesEntry == nil
                            && !examplesInstalled && academy.unavailableCourses.isEmpty {
                    ContentUnavailableView("Course list unavailable", systemImage: "wifi.slash")
                    Button("Retry") { Task { await academy.checkForUpdates() } }
                }
            }
            .padding(.vertical, 20)
            .crabrixPageContent()
        }
        .refreshable { await academy.checkForUpdates() }
        .background(CrabrixTheme.background.ignoresSafeArea())
        .foregroundStyle(CrabrixTheme.primary)
        .navigationTitle(showsPractice ? "Learn" : "Courses")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Returns at once; does nothing unless a learning link is connected.
            LearningLinkController.shared.learnDidAppear()
            await academy.checkForUpdates()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await academy.checkForUpdates() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(academy.checkingForUpdates)
                .accessibilityLabel("Check for lesson updates")
            }
            if showsPractice && !installed.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: LearningRoute.profile) {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel("Learning profile")
                }
            }
        }
        // Alerts, because a confirmation dialog points an arrow at the last
        // touch here, which is often not the course being asked about.
        .alert(
            pendingIsUpdate ? "Update lessons?" : "Download course?",
            isPresented: Binding(
                get: { pendingDownload != nil },
                set: { if !$0 { pendingDownload = nil } }
            )
        ) {
            if let entry = pendingDownload {
                Button("\(pendingIsUpdate ? "Update" : "Download") \(ByteCountFormatter.string(fromByteCount: Int64(entry.archiveBytes), countStyle: .file))") {
                    academy.download(entry)
                    pendingDownload = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingDownload = nil }
        } message: {
            Text(pendingIsUpdate
                 ? "The new lessons will replace the installed version after verification. Your progress and projects stay on this device."
                 : "The selected material will be available offline after verification.")
        }
        .alert("Update all courses?", isPresented: $confirmUpdateAll) {
            Button("Update \(updates.count) courses") { academy.updateAll() }
            Button("Cancel", role: .cancel) { confirmUpdateAll = false }
        } message: {
            let bytes = updates.reduce(Int64(0)) { $0 + Int64($1.archiveBytes) }
            Text("Downloads \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)). Saved progress and projects stay on this device.")
        }
        .alert(
            "Remove \(pendingRemoval?.title ?? "download")?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            )
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

    private var unavailableSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Needs attention").font(.title2.bold())
            ForEach(academy.unavailableCourses) { course in
                let preview = Self.preview(course.courseID)
                let entry = academy.latestEntry(for: course.courseID, language: course.language)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        courseIcon(course.courseID, fallback: preview.icon, tint: CrabrixTheme.amber)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(preview.title).font(.headline)
                            Text("This download could not be opened. Your progress and projects are safe.")
                                .font(.caption)
                                .foregroundStyle(CrabrixTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(course.reason)
                                .font(.caption2)
                                .foregroundStyle(CrabrixTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 8) {
                        if let entry {
                            Button("Download again") { pendingDownload = entry }
                                .buttonStyle(.bordered)
                                .tint(CrabrixTheme.coral)
                                .accessibilityLabel("Download \(preview.title) again")
                        }
                        Button("Remove download", role: .destructive) {
                            requestRemoval(course.courseID, title: preview.title)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Remove \(preview.title) download")
                    }
                    .font(.caption.bold())
                    if let entry, let transfer = academy.transfers[course.id] {
                        transferView(transfer, entry: entry)
                    }
                }
                .padding(14)
                .crabrixPanel(cornerRadius: 14)
                .accessibilityIdentifier("learn-unavailable-\(course.courseID)")
            }
        }
    }

    private var updateSummary: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.title3)
                .foregroundStyle(CrabrixTheme.mint)
            VStack(alignment: .leading, spacing: 3) {
                Text("New lessons available").font(.headline)
                Text("\(updates.count) course\(updates.count == 1 ? "" : "s") ready to update. Your progress stays saved.")
                    .font(.caption)
                    .foregroundStyle(CrabrixTheme.muted)
            }
            Spacer(minLength: 0)
            Button(academy.updatingAll ? "Updating" : "Update all") {
                confirmUpdateAll = true
            }
            .buttonStyle(.borderedProminent)
            .foregroundStyle(CrabrixTheme.onAccent)
            .tint(CrabrixTheme.mint)
            .disabled(academy.updatingAll)
        }
        .padding(15)
        .crabrixPanel(cornerRadius: 16)
    }

    private var examplesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Code Examples").font(.title2.bold())
            if examplesInstalled {
                SwipeRevealCard(id: "examples", openID: $openSwipeCard, actions: examplesSwipeActions) {
                    HStack(spacing: 8) {
                        SwipeCardLink(open: { navigationPath.append(.examples) }) {
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
                        }
                        .accessibilityLabel("Browse 46 Code Examples, available offline")
                        .swipeCardAccessibilityActions(examplesSwipeActions)
                    }
                    .padding(15)
                    .crabrixPanel(cornerRadius: 16)
                }
                if let entry = newerExamplesEntry {
                    updateAction(entry, currentVersion: academy.repository?.loaded["examples"]?.contentVersion)
                        .padding(12)
                        .crabrixPanel(cornerRadius: 14)
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

    /// The same route the course map and Weak Topics use.
    private func openTutorLesson(courseID: String, lessonID: String) {
        guard let repository = academy.repository,
              let lesson = repository.lesson(id: lessonID),
              let course = repository.course(containing: lesson.id), course.id == courseID
        else { return }
        navigationPath = [.course(course.id), .lesson(lesson.id)]
    }

    /// Swipe a card from right to left for what the "⋯" menu used to hold.
    private var examplesSwipeActions: [SwipeCardAction] {
        var actions: [SwipeCardAction] = []
        if let entry = newerExamplesEntry {
            actions.append(SwipeCardAction(id: "update", title: "Update", systemImage: "arrow.down.circle",
                                           tint: CrabrixTheme.mint, accessibilityName: "Download latest examples") {
                pendingDownload = entry
            })
        }
        actions.append(.remove(accessibilityName: "Remove download") {
            requestRemoval("examples", title: "Code Examples")
        })
        return actions
    }

    private func installedRow(_ course: RustCourse, showsSwipeHint: Bool = false) -> some View {
        let lessons = course.units.flatMap(\.lessons)
        let completed = lessons.filter { completedLessonIDs.contains($0.id) }.count
        let actions: [SwipeCardAction] = [
            .remove(accessibilityName: "Remove \(course.title) download") {
                requestRemoval(course.id, title: course.title)
            },
        ]
        return SwipeRevealCard(id: "course-\(course.id)", openID: $openSwipeCard, showsHint: showsSwipeHint,
                               actions: actions) {
          VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                SwipeCardLink(open: { navigationPath.append(.course(course.id)) }) {
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
                }
                .accessibilityLabel("Open \(course.title), \(completed) of \(lessons.count) lessons complete, available offline")
                .accessibilityIdentifier("learn-open-course-\(course.id)")
                .swipeCardAccessibilityActions(actions)
            }
            if course.id == "projects", academy.repository?.loaded["projects"]?.showcases.isEmpty == false {
                NavigationLink("Open Code Examples", value: LearningRoute.examples)
                    .font(.caption.weight(.semibold))
            }
            if let entry = academy.updateEntry(for: course.id) {
                updateAction(entry, currentVersion: academy.repository?.loaded[course.id]?.contentVersion)
            }
          }
          .padding(15)
          .crabrixPanel(cornerRadius: 16)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("learn-course-\(course.id)")
    }

    private func updateAction(_ entry: CourseCatalogPayload.Entry,
                              currentVersion: String?) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(CrabrixTheme.mint)
                Text("New content: \(currentVersion ?? "installed") → \(entry.contentVersion)")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                Button("Update") { pendingDownload = entry }
                    .buttonStyle(.bordered)
                    .tint(CrabrixTheme.mint)
                    .disabled(academy.updatingAll)
                    .accessibilityLabel("Update \(Self.preview(entry.courseID).title) lessons")
            }
            if let transfer = academy.transfers[entry.courseID + "|" + entry.language] {
                transferView(transfer, entry: entry)
            }
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

    private var learnWithAISection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Learn with AI").font(.title2.bold())
            NavigationLink(value: LearningRoute.learnWithAI) {
                LearningPracticeCard(
                    title: "Learn with your AI agent",
                    subtitle: "Claude, Codex or Cursor teach from these lessons · optional",
                    badge: "NEW",
                    systemImage: "sparkles",
                    tint: CrabrixTheme.blue
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Learn with AI. Connect Claude, Codex or Cursor to Crabrix Academy. Optional")
            .accessibilityIdentifier("learn-with-ai")
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
            .accessibilityIdentifier("learn-quick-practice")

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
            .accessibilityIdentifier("learn-term-train")

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
            .accessibilityIdentifier("learn-code-recall")

            NavigationLink {
                // Credited lessons join too, so spaced review checks the credit.
                FlashcardsView(completedLessonIDs: completedLessonIDs) { flashcardSessions += 1 }
            } label: {
                LearningPracticeCard(
                    title: "Flashcards",
                    subtitle: "Flip ideas from completed lessons, then space your reviews",
                    badge: flashcardSessions == 0 ? "NEW" : "\(flashcardSessions) RUNS",
                    systemImage: "rectangle.stack.fill",
                    tint: CrabrixTheme.coral
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("learn-flashcards")
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
            CrabrixLoadingView("Verifying…")
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
        ["basics", "rust-for-c-developers", "rust-for-nodejs-developers", "ownership", "projects",
         "concurrency", "systems", "interview", "algorithms"]
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
        case "rust-for-c-developers":
            ("Rust for C Developers", "Bridges · C habits next to Rust, credits known lessons", "arrow.left.arrow.right")
        case "rust-for-nodejs-developers":
            ("Rust for Node.js Developers", "Bridges · JavaScript next to Rust, credits known lessons", "arrow.left.arrow.right")
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

/// One action behind a library card, shown when the card is swiped from right
/// to left (what the "⋯" menu used to hold).
struct SwipeCardAction: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let tint: Color
    /// What VoiceOver offers as a named action on the card.
    let accessibilityName: String
    let perform: () -> Void

    init(id: String, title: String, systemImage: String, tint: Color,
         accessibilityName: String, perform: @escaping () -> Void) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.accessibilityName = accessibilityName
        self.perform = perform
    }

    static func remove(accessibilityName: String, perform: @escaping () -> Void) -> SwipeCardAction {
        SwipeCardAction(id: "remove", title: "Remove", systemImage: "trash", tint: CrabrixTheme.danger,
                        accessibilityName: accessibilityName, perform: perform)
    }
}

extension View {
    /// Swipes are invisible to VoiceOver and Switch Control, so every swipe
    /// action is also a named accessibility action on the card's main element.
    func swipeCardAccessibilityActions(_ actions: [SwipeCardAction]) -> some View {
        accessibilityActions {
            ForEach(actions) { action in
                Button(action.accessibilityName, action: action.perform)
            }
        }
    }
}

/// The part of a swipeable card that opens it. A Button or NavigationLink still
/// fires when a horizontal swipe ends inside it, so swiping a card used to open
/// the course; a tap gesture fails as soon as the finger moves.
private struct SwipeCardLink<Label: View>: View {
    let open: () -> Void
    let label: Label

    init(open: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.open = open
        self.label = label()
    }

    var body: some View {
        label
            .contentShape(Rectangle())
            .onTapGesture(perform: open)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, open)
    }
}

/// A library card that follows the finger when swiped from right to left and
/// settles open on its actions or closed again, like a list row's swipe
/// actions, without making the vertical library depend on a List. One card is
/// open at a time (`openID`); tapping an open card closes it instead of opening
/// the course. The first card can peek once so the gesture is discoverable now
/// that the "⋯" button is gone.
private struct SwipeRevealCard<Content: View>: View {
    let id: String
    @Binding var openID: String?
    var showsHint = false
    let actions: [SwipeCardAction]
    let content: Content

    @GestureState private var drag: SwipeDrag = .idle
    @State private var hintOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("crabrix.learn.swipeHintShown.v1") private var hintShown = false

    private let actionWidth: CGFloat = 84

    init(id: String, openID: Binding<String?>, showsHint: Bool = false, actions: [SwipeCardAction],
         @ViewBuilder content: () -> Content) {
        self.id = id
        self._openID = openID
        self.showsHint = showsHint
        self.actions = actions
        self.content = content()
    }

    private enum SwipeDrag: Equatable {
        case idle, vertical
        case horizontal(CGFloat)
    }

    private var revealWidth: CGFloat { actionWidth * CGFloat(actions.count) }
    private var isOpen: Bool { openID == id }

    private var offset: CGFloat {
        var x = isOpen ? -revealWidth : 0
        if case let .horizontal(dx) = drag { x += dx }
        x += hintOffset
        // A little give past either end, then it stops.
        if x > 0 { return min(x * 0.25, 12) }
        if x < -revealWidth { return -revealWidth - min((-revealWidth - x) * 0.25, 18) }
        return x
    }

    var body: some View {
        content
            .overlay {
                if isOpen {
                    // An open card closes on a tap instead of opening the course.
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { close() }
                        .accessibilityHidden(true)
                }
            }
            .offset(x: offset)
            .simultaneousGesture(swipe)
            .background(alignment: .trailing) { actionButtons }
            .clipShape(CrabrixCardShape(cornerRadius: 16))
            .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.86), value: drag)
            .task(id: showsHint) { await peekOnce() }
    }

    private var actionButtons: some View {
        HStack(spacing: 0) {
            ForEach(actions) { action in
                Button {
                    close()
                    action.perform()
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: action.systemImage).font(.body.weight(.semibold))
                        Text(action.title).font(.caption.bold())
                    }
                    .foregroundStyle(.white)
                    .frame(width: actionWidth)
                    .frame(maxHeight: .infinity)
                    .background(action.tint)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true) // offered as named actions on the card
            }
        }
        .frame(width: revealWidth)
        .frame(maxHeight: .infinity)
        .opacity(offset < -1 ? 1 : 0)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($drag) { value, state, _ in
                switch state {
                case .idle:
                    let dx = value.translation.width, dy = value.translation.height
                    state = abs(dx) > abs(dy) * 1.2 ? .horizontal(dx) : .vertical
                case .horizontal:
                    state = .horizontal(value.translation.width)
                case .vertical:
                    break
                }
            }
            .onEnded { value in
                let dx = value.translation.width, dy = value.translation.height
                guard abs(dx) > abs(dy) * 1.2 else { return }
                let start: CGFloat = isOpen ? -revealWidth : 0
                let predicted = start + value.predictedEndTranslation.width
                withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                    if predicted < -revealWidth / 2 {
                        openID = id
                    } else if isOpen {
                        openID = nil
                    }
                }
            }
    }

    private func close() {
        guard isOpen else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { openID = nil }
    }

    /// Once per install, the first card slides to show its action and back.
    private func peekOnce() async {
        guard showsHint, !hintShown, !reduceMotion,
              !ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("-Crabrix") || $0.hasPrefix("--crabrix") })
        else { return }
        try? await Task.sleep(for: .milliseconds(900))
        guard !Task.isCancelled, openID == nil else { return }
        hintShown = true
        withAnimation(.easeOut(duration: 0.35)) { hintOffset = -min(revealWidth, 64) }
        try? await Task.sleep(for: .milliseconds(650))
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { hintOffset = 0 }
    }
}
