import SwiftUI

struct LessonDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let lesson: RustLesson
    let isCompleted: Bool
    let onStart: () -> Void
    let onComplete: () -> Void

    private var brief: RustLessonBrief { lesson.brief }
    private var isLive: Bool {
        if case .planned = lesson.exercise { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero
                    explanation
                    objectives
                    assignment
                    nextStep
                }
                .padding(22)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .background(CrabrixTheme.background.ignoresSafeArea())
            .foregroundStyle(CrabrixTheme.primary)
            .navigationTitle("Lesson")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: brief.systemImage)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(brief.tint)
                .frame(width: 62, height: 62)
                .background(brief.tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 18))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(isLive ? "COMPILER LAB" : "LESSON PREVIEW")
                        .font(.caption2.monospaced().bold())
                        .foregroundStyle(brief.tint)
                    Text("· \(lesson.minutes) MIN")
                        .font(.caption2.monospaced())
                        .foregroundStyle(CrabrixTheme.muted)
                }
                Text(lesson.title)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                Text(lesson.concept)
                    .font(.subheadline)
                    .foregroundStyle(CrabrixTheme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [brief.tint.opacity(0.13), CrabrixTheme.panel],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20)
        )
        .overlay { RoundedRectangle(cornerRadius: 20).stroke(brief.tint.opacity(0.3)) }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Why this matters", systemImage: "book.pages.fill")
                .font(.headline)
            Text(brief.summary)
                .foregroundStyle(CrabrixTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text(brief.explanation)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var objectives: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("YOU WILL PRACTICE")
                .font(.caption.monospaced().bold())
                .foregroundStyle(CrabrixTheme.blue)
            ForEach(brief.objectives, id: \.self) { objective in
                Label(objective, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(CrabrixTheme.primary)
                    .labelStyle(LessonObjectiveLabelStyle())
            }
        }
        .padding(18)
        .background(CrabrixTheme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(CrabrixTheme.border) }
    }

    private var assignment: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("YOUR TASK", systemImage: "scope")
                .font(.caption.monospaced().bold())
                .foregroundStyle(CrabrixTheme.coral)
            Text(brief.task)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Label(brief.success, systemImage: "flag.checkered")
                .font(.subheadline)
                .foregroundStyle(CrabrixTheme.mint)
                .fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("Need a hint?") {
                Text(brief.hint)
                    .padding(.top, 8)
                    .foregroundStyle(CrabrixTheme.muted)
            }
            .font(.subheadline)
        }
        .padding(18)
        .background(CrabrixTheme.coral.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(CrabrixTheme.coral.opacity(0.28)) }
    }

    @ViewBuilder
    private var nextStep: some View {
        if isLive {
            Button {
                onStart()
            } label: {
                Label("Open this lab", systemImage: "hammer.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
            .tint(CrabrixTheme.coral)
        } else {
            Label(
                isCompleted ? "Concept lesson completed" : "Read the task, then continue to the next lesson",
                systemImage: isCompleted ? "checkmark.seal.fill" : "book.fill"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isCompleted ? CrabrixTheme.mint : CrabrixTheme.amber)

            if !isCompleted {
                Button(action: onComplete) {
                    Label("Complete lesson", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent)
                .tint(CrabrixTheme.amber)
            }
        }
    }
}

private struct LessonObjectiveLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 9) {
            configuration.icon.foregroundStyle(CrabrixTheme.mint)
            configuration.title
        }
    }
}

private struct RustLessonBrief {
    let summary: String
    let explanation: String
    let objectives: [String]
    let task: String
    let success: String
    let hint: String
    let systemImage: String
    let tint: Color
}

private extension RustLesson {
    var brief: RustLessonBrief {
        let content: (String, String, String, String)
        switch id {
        case "hello-rust":
            content = ("Every Rust program starts at main, but the useful lesson is the full edit → compile → execute loop.", "println! is a macro: the exclamation mark tells Rust that it expands code before compilation.", "Change the greeting, run it locally, and inspect stdout.", "stdout contains your edited greeting and the build exits with code 0.")
        case "variables":
            content = ("Bindings are immutable unless you explicitly opt into mutation.", "Rust makes state changes visible in code with mut; shadowing creates a new binding instead of changing the old one.", "Create an immutable value, shadow it, then update one mutable counter.", "The final values compile without an unused-mutation warning.")
        case "types":
            content = ("Rust checks scalar and compound types before the program runs.", "Tuples group different types while arrays keep one type and a fixed length.", "Build one tuple and one array, then read a value from each.", "The output shows both selected values with no type mismatch.")
        case "control-flow":
            content = ("Expressions and loops let Rust model decisions without hidden coercion.", "if branches must agree on a type, while loop, while, and for express different repetition rules.", "Use if to classify a number and for to visit a range.", "Each number is printed exactly once with the right classification.")
        case "ownership", "q-ownership":
            content = ("Ownership gives every value one clear cleanup responsibility.", "Moves transfer that responsibility; Copy types duplicate their value, and Drop runs when the owner leaves scope.", "Predict which binding still owns a String after an assignment, then make the program compile.", "You can explain why no double-free is possible.")
        case "borrowing", "q-borrowing":
            content = ("Borrowing lets code use a value without taking ownership.", "Rust permits many shared references or one mutable reference at a time. The compiler tracks where their uses overlap.", "Repair E0502 with the smallest edit while preserving the push and printed value.", "Check passes, Run prints the original first item, and the Vec is still extended.")
        case "slices":
            content = ("Slices are borrowed views into contiguous data.", "A slice stores a pointer and length but does not own the String or array it views.", "Write a function that returns the first word as &str without allocating.", "The returned slice ends before the first space and stays tied to its input.")
        case "lifetimes-intro", "lifetimes", "q-lifetimes":
            content = ("Lifetimes describe relationships between references, not timers attached to values.", "Annotations tell the compiler how input and output borrows are connected when inference is ambiguous.", "Describe which input borrow a returned reference may depend on.", "No returned reference can outlive the data it points into.")
        case "structs":
            content = ("Structs give related data names and a stable shape.", "impl blocks attach constructors and methods while ownership rules remain visible in self, &self, and &mut self.", "Model a Rectangle and add an area method.", "The method borrows the rectangle and prints the expected area.")
        case "enums":
            content = ("Enums model a value that is exactly one of several variants.", "match forces every variant to be handled, making state transitions explicit.", "Define a message enum and render every variant with match.", "The match is exhaustive without a wildcard hiding a case.")
        case "option-result", "q-option-result":
            content = ("Option represents absence; Result represents an operation that can fail with information.", "Pattern matching and the ? operator keep both cases explicit without sentinel values.", "Choose Option or Result for two small APIs and handle both branches.", "No unwrap is required on the normal execution path.")
        case "collections":
            content = ("Vec, String, and HashMap own growable data with different lookup trade-offs.", "Choosing a collection is part of the model: order, uniqueness, and key access all matter.", "Count repeated words with a HashMap entry.", "The final map contains the correct count for every word.")
        case "generics":
            content = ("Generics reuse an algorithm while keeping concrete types at compile time.", "Trait bounds state the capabilities that the generic body needs.", "Write a largest function with the smallest useful trait bound.", "It works for two concrete ordered types.")
        case "traits", "q-dyn-generics":
            content = ("Traits define shared behavior independently of a concrete type.", "Generic bounds use static dispatch; dyn Trait uses runtime dispatch and a stable interface.", "Implement one trait for two types and compare a generic call with a trait object.", "Both paths produce the same behavior and you can name their trade-off.")
        case "iterators":
            content = ("Iterators compose lazy transformations before consuming results.", "map and filter do no work until a consumer such as collect, sum, or a loop requests items.", "Transform a range with filter and map, then collect it.", "The resulting Vec contains only the expected transformed values.")
        case "modules":
            content = ("Modules split a crate into files while privacy controls the public surface.", "mod declares a module and use brings a path into scope; Cargo.toml describes the package around them.", "Open the multi-file project, trace mod greeter, and change its public function.", "The project compiles from src/main.rs and prints the edited module output.")
        case "testing":
            content = ("Tests turn behavior into executable evidence.", "#[test] functions run in the test harness; unit tests can inspect private details while integration tests use the public API.", "Add one success case and one boundary case for a pure function.", "Both tests are deterministic and fail for a deliberately broken implementation.")
        case "errors":
            content = ("Good errors preserve context and keep recovery decisions near the caller.", "Result, custom error types, and ? separate expected failure from programmer mistakes.", "Replace a panic with a Result and propagate it through one caller.", "The caller handles the failure without losing its cause.")
        case "concurrency", "q-send-sync":
            content = ("Rust moves many data races from runtime accidents to compile-time errors.", "Send and Sync describe when ownership or shared access can safely cross thread boundaries.", "Identify why Rc cannot cross threads, then choose an appropriate shared type.", "The design has explicit ownership and no unsynchronised mutation.")
        case "q-box-rc-arc":
            content = ("Box, Rc, and Arc answer different ownership and allocation questions.", "Box has one owner, Rc shares ownership on one thread, and Arc uses atomic reference counting across threads.", "Match three scenarios to the narrowest pointer type that satisfies them.", "Every choice explains ownership count and thread boundary.")
        case "q-unsafe":
            content = ("unsafe permits a small set of unchecked operations; it does not disable the borrow checker everywhere.", "A sound abstraction documents and enforces the invariants its unsafe block relies on.", "Review a tiny unsafe wrapper and list every invariant its safe API must protect.", "Safe callers cannot trigger undefined behavior.")
        default:
            content = ("This lesson isolates one Rust idea so you can reason about it before writing a larger program.", "Use the compiler feedback as evidence: read the message, change one assumption, and check again.", "Explain \(concept.lowercased()) in your own words, then sketch the smallest code example.", "The example compiles and its result matches your explanation.")
        }

        return RustLessonBrief(
            summary: content.0,
            explanation: content.1,
            objectives: [concept, "Read the relevant compiler evidence", "Make one intentional code change"],
            task: content.2,
            success: content.3,
            hint: "Start from the ownership and type of each value. Prefer the smallest edit that makes the compiler agree with your intent.",
            systemImage: lessonIcon,
            tint: lessonTint
        )
    }

    private var lessonIcon: String {
        switch exercise {
        case .runnable: "terminal.fill"
        case .borrowDiagnostic: "link.badge.plus"
        case .multiFile: "folder.fill.badge.gearshape"
        case .planned: "book.closed.fill"
        }
    }

    private var lessonTint: Color {
        switch exercise {
        case .runnable: CrabrixTheme.mint
        case .borrowDiagnostic: CrabrixTheme.coral
        case .multiFile: CrabrixTheme.blue
        case .planned: CrabrixTheme.amber
        }
    }
}
