import SwiftUI

struct LearningHubView: View {
    let completedLessonIDs: Set<String>
    let onOpenLesson: (RustLesson) -> Void

    private let columns = [GridItem(.adaptive(minimum: 260), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    hero

                    NavigationLink {
                        QuickPracticeView()
                    } label: {
                        HStack(spacing: 15) {
                            Image(systemName: "bolt.fill")
                                .font(.title2)
                                .foregroundStyle(CrabrixTheme.amber)
                                .frame(width: 48, height: 48)
                                .background(CrabrixTheme.amber.opacity(0.13), in: RoundedRectangle(cornerRadius: 14))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Quick Practice")
                                    .font(.headline)
                                Text("Choose · match · arrange code by dragging")
                                    .font(.caption)
                                    .foregroundStyle(CrabrixTheme.muted)
                            }
                            Spacer()
                            Text("5 MIN")
                                .font(.caption2.monospaced().bold())
                                .foregroundStyle(CrabrixTheme.amber)
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.title3)
                                .foregroundStyle(CrabrixTheme.amber)
                        }
                        .padding(16)
                        .background(CrabrixTheme.amber.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay { RoundedRectangle(cornerRadius: 16).stroke(CrabrixTheme.amber.opacity(0.3)) }
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Choose a course")
                            .font(.title2.bold())
                        Text("Start with the level you need. Each course has its own visual lesson path.")
                            .font(.subheadline)
                            .foregroundStyle(CrabrixTheme.muted)
                    }

                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(Array(RustCourseCatalog.courses.enumerated()), id: \.element.id) { index, course in
                            NavigationLink {
                                LearnPathView(
                                    units: course.units,
                                    courseTitle: course.title,
                                    completedLessonIDs: completedLessonIDs,
                                    onOpenLesson: onOpenLesson
                                )
                            } label: {
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
        }
    }

    private var hero: some View {
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

    private func tint(at index: Int) -> Color {
        [CrabrixTheme.mint, CrabrixTheme.coral, CrabrixTheme.blue, CrabrixTheme.amber][index % 4]
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
