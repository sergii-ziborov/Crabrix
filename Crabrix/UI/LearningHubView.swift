import SwiftUI

enum LearningRoute: Hashable {
    case course(String)
    case lesson(String)
}

struct LearningHubView: View {
    @Binding var navigationPath: [LearningRoute]
    @AppStorage("crabrix.learn.trainingSessions") private var trainingSessions = 0
    let completedLessonIDs: Set<String>
    let onStartLesson: (RustLesson) -> Void
    let onCompleteLesson: (RustLesson) -> Void

    private let columns = [GridItem(.adaptive(minimum: 260), spacing: 16)]

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    hero

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
                                badge: trainingSessions == 0 ? "NEW" : "\(trainingSessions) SETS",
                                systemImage: "link",
                                tint: CrabrixTheme.mint
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
                    }

                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(Array(RustCourseCatalog.courses.enumerated()), id: \.element.id) { index, course in
                            NavigationLink(value: LearningRoute.course(course.id)) {
                                CourseCard(course: course, tint: tint(at: index))
                            }
                            .buttonStyle(.plain)
                        }
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
        }
    }

    @ViewBuilder
    private func destination(for route: LearningRoute) -> some View {
        switch route {
        case let .course(courseID):
            if let course = RustCourseCatalog.course(id: courseID) {
                LearnPathView(
                    units: course.units,
                    courseTitle: course.title,
                    completedLessonIDs: completedLessonIDs,
                    onOpenLesson: { lesson in
                        navigationPath.append(.lesson(lesson.id))
                    }
                )
            } else {
                ContentUnavailableView("Course unavailable", systemImage: "book.closed")
            }

        case let .lesson(lessonID):
            if let lesson = RustCourseCatalog.lesson(id: lessonID) {
                LessonDetailView(
                    lesson: lesson,
                    isCompleted: completedLessonIDs.contains(lesson.id),
                    onStart: { onStartLesson(lesson) },
                    onComplete: {
                        onCompleteLesson(lesson)
                        returnToCourse(containing: lesson)
                    }
                )
            } else {
                ContentUnavailableView("Lesson unavailable", systemImage: "book.closed")
            }
        }
    }

    private func returnToCourse(containing lesson: RustLesson) {
        guard let course = RustCourseCatalog.course(containingLessonID: lesson.id) else {
            navigationPath = []
            return
        }
        navigationPath = [.course(course.id)]
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
                    Text("Short explanations, compiler-checked labs, and a visible next step.")
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

    private var totalLessonCount: Int {
        RustCourseCatalog.courses.flatMap(\.units).flatMap(\.lessons).count
    }

    private var completedLessonCount: Int {
        let allLessonIDs = Set(RustCourseCatalog.courses.flatMap(\.units).flatMap(\.lessons).map(\.id))
        return completedLessonIDs.intersection(allLessonIDs).count
    }

    private var progressPercent: Int {
        guard totalLessonCount > 0 else { return 0 }
        return Int((Double(completedLessonCount) / Double(totalLessonCount) * 100).rounded())
    }

    private func tint(at index: Int) -> Color {
        [CrabrixTheme.mint, CrabrixTheme.coral, CrabrixTheme.blue, CrabrixTheme.amber][index % 4]
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
    let tint: Color

    private var lessonCount: Int { course.units.flatMap(\.lessons).count }

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
                Label("\(course.units.count) units", systemImage: "square.stack.3d.up.fill")
                Label("\(lessonCount) lessons", systemImage: "checklist")
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
