import SwiftUI

struct LessonDetailView: View {
    let lesson: RustLesson
    let isCompleted: Bool
    let onStart: () -> Void
    let onComplete: () -> Void

    @State private var page = 0
    @State private var selectedAnswer: Int?

    private var brief: RustLessonBrief { lesson.brief }
    private var practice: RustLessonPractice { lesson.lessonPractice }
    private var isLive: Bool {
        if case .planned = lesson.exercise { return false }
        return true
    }

    var body: some View {
        VStack(spacing: 0) {
            progressHeader

            TabView(selection: $page) {
                conceptPage.tag(0)
                practicePage.tag(1)
                readyPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            Divider().overlay(CrabrixTheme.border)
            navigationFooter
        }
        .background {
            ZStack {
                CrabrixTheme.background.ignoresSafeArea()
                LinearGradient(
                    colors: [brief.tint.opacity(0.08), .clear, CrabrixTheme.blue.opacity(0.04)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
        }
        .foregroundStyle(CrabrixTheme.primary)
        .navigationTitle(lesson.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var progressHeader: some View {
        VStack(spacing: 10) {
            HStack {
                Text("LESSON · STEP \(page + 1) OF 3")
                    .font(.caption2.monospaced().bold())
                    .foregroundStyle(brief.tint)
                Spacer()
                Label("\(lesson.minutes) MIN", systemImage: "clock.fill")
                    .font(.caption2.monospaced())
                    .foregroundStyle(CrabrixTheme.muted)
            }

            HStack(spacing: 7) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index <= page ? brief.tint : CrabrixTheme.border)
                        .frame(height: 5)
                        .animation(.easeInOut(duration: 0.2), value: page)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(CrabrixTheme.panel.opacity(0.96))
    }

    private var conceptPage: some View {
        lessonScrollPage {
            LessonPageHeading(
                step: "01 · UNDERSTAND",
                title: lesson.title,
                subtitle: lesson.concept,
                systemImage: brief.systemImage,
                tint: brief.tint
            )

            LessonCard(title: "Why this matters", systemImage: "book.pages.fill", tint: brief.tint) {
                Text(brief.summary)
                    .font(.title3.weight(.semibold))
                Text(brief.explanation)
                    .foregroundStyle(CrabrixTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LessonCard(title: "The rule", systemImage: "lightbulb.fill", tint: CrabrixTheme.amber) {
                Text(practice.rule)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
            }

            objectives
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

    private var practicePage: some View {
        lessonScrollPage {
            LessonPageHeading(
                step: "02 · PRACTICE",
                title: "Make the rule concrete",
                subtitle: brief.task,
                systemImage: "hand.tap.fill",
                tint: CrabrixTheme.blue
            )

            VStack(alignment: .leading, spacing: 10) {
                Text("CODE SNAPSHOT")
                    .font(.caption2.monospaced().bold())
                    .foregroundStyle(CrabrixTheme.blue)
                Text(practice.code)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(CrabrixTheme.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 14))
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("QUICK CHECK")
                    .font(.caption2.monospaced().bold())
                    .foregroundStyle(CrabrixTheme.coral)
                Text(practice.question)
                    .font(.title3.bold())

                ForEach(Array(practice.answers.enumerated()), id: \.offset) { index, answer in
                    answerButton(answer, at: index)
                }

                if let selectedAnswer {
                    Label(
                        selectedAnswer == practice.correctAnswer
                            ? "Correct — \(practice.feedback)"
                            : "Not quite — \(practice.feedback)",
                        systemImage: selectedAnswer == practice.correctAnswer
                            ? "checkmark.circle.fill"
                            : "arrow.counterclockwise.circle.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(
                        selectedAnswer == practice.correctAnswer
                            ? CrabrixTheme.mint
                            : CrabrixTheme.amber
                    )
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
            .background(CrabrixTheme.panel, in: RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).stroke(CrabrixTheme.border) }
        }
    }

    private var readyPage: some View {
        lessonScrollPage {
            LessonPageHeading(
                step: "03 · APPLY",
                title: isLive ? "Ready for the compiler" : "Lock in the idea",
                subtitle: isLive
                    ? "Use real rustc output as evidence."
                    : "Finish this lesson and unlock the next node.",
                systemImage: isLive ? "hammer.fill" : "checkmark.seal.fill",
                tint: CrabrixTheme.mint
            )

            LessonCard(title: "Success looks like", systemImage: "flag.checkered", tint: CrabrixTheme.mint) {
                Text(brief.success)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Label(
                    isLive ? "The bundled compiler checks the final result." : "Your course map records this lesson locally.",
                    systemImage: isLive ? "cpu.fill" : "internaldrive.fill"
                )
                .font(.subheadline)
                .foregroundStyle(CrabrixTheme.muted)
            }

            LessonCard(title: "Hint before you go", systemImage: "sparkles", tint: CrabrixTheme.amber) {
                Text(brief.hint)
                    .foregroundStyle(CrabrixTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isCompleted {
                Label("Already completed — you can review it any time.", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(CrabrixTheme.mint)
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CrabrixTheme.mint.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func answerButton(_ answer: String, at index: Int) -> some View {
        let isSelected = selectedAnswer == index
        return Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                selectedAnswer = index
            }
        } label: {
            HStack(spacing: 12) {
                Text(String(UnicodeScalar(65 + index)!))
                    .font(.caption.monospaced().bold())
                    .foregroundStyle(isSelected ? CrabrixTheme.background : CrabrixTheme.muted)
                    .frame(width: 28, height: 28)
                    .background(isSelected ? brief.tint : CrabrixTheme.border, in: Circle())
                Text(answer)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.leading)
                Spacer()
                if isSelected {
                    Image(systemName: index == practice.correctAnswer ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(index == practice.correctAnswer ? CrabrixTheme.mint : CrabrixTheme.amber)
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity)
            .background(isSelected ? brief.tint.opacity(0.10) : CrabrixTheme.background.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 13))
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .stroke(isSelected ? brief.tint : CrabrixTheme.border)
            }
        }
        .buttonStyle(.plain)
    }

    private var navigationFooter: some View {
        HStack(spacing: 12) {
            if page > 0 {
                Button {
                    withAnimation(.easeInOut) { page -= 1 }
                } label: {
                    Label("Back", systemImage: "arrow.left")
                        .frame(minWidth: 90)
                }
                .buttonStyle(.bordered)
            }

            Spacer(minLength: 0)

            if page < 2 {
                Button {
                    withAnimation(.easeInOut) { page += 1 }
                } label: {
                    Label(
                        page == 0 ? "Try a quick check" : "Review result",
                        systemImage: "arrow.right"
                    )
                    .frame(minWidth: 180)
                }
                .buttonStyle(.borderedProminent)
                .tint(brief.tint)
                .disabled(page == 1 && selectedAnswer == nil)
            } else {
                Button(action: isLive ? onStart : onComplete) {
                    Label(
                        isLive
                            ? "Open compiler lab"
                            : (isCompleted ? "Back to course" : "Complete lesson"),
                        systemImage: isLive ? "hammer.fill" : "checkmark.circle.fill"
                    )
                    .frame(minWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .tint(isLive ? CrabrixTheme.coral : CrabrixTheme.mint)
            }
        }
        .font(.headline)
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
    }

    private func lessonScrollPage<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                content()
            }
            .padding(22)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct LessonPageHeading: View {
    let step: String
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 64, height: 64)
                .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 18))
            VStack(alignment: .leading, spacing: 6) {
                Text(step)
                    .font(.caption2.monospaced().bold())
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(CrabrixTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct LessonCard<Content: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    let content: Content

    init(
        title: String,
        systemImage: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CrabrixTheme.panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(tint.opacity(0.25)) }
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

private struct RustLessonPractice {
    let rule: String
    let code: String
    let question: String
    let answers: [String]
    let correctAnswer: Int
    let feedback: String
}

private extension RustLesson {
    var lessonPractice: RustLessonPractice {
        switch id {
        case "hello-rust":
            RustLessonPractice(
                rule: "Execution starts in fn main(); println! writes a formatted line to stdout.",
                code: """
                fn main() {
                    println!("Hello, Crabrix!");
                }
                """,
                question: "Which line produces visible program output?",
                answers: ["fn main() {", "println!(\"Hello, Crabrix!\");", "The closing brace"],
                correctAnswer: 1,
                feedback: "println! expands before compilation and writes the final line to stdout."
            )

        case "variables":
            RustLessonPractice(
                rule: "let is immutable by default, let mut permits updates, and shadowing creates a new binding.",
                code: """
                let crabs = 1;
                let crabs = crabs + 1; // shadow
                let mut clicks = 0;
                clicks += 1;           // mutate
                """,
                question: "Which declaration permits changing the same binding later?",
                answers: ["let total = 1;", "let mut total = 1;", "let total = total + 1;"],
                correctAnswer: 1,
                feedback: "mut is the explicit permission to update that binding; shadowing creates a different one."
            )

        case "borrowing", "q-borrowing":
            RustLessonPractice(
                rule: "At one moment Rust allows many shared references or one mutable reference — never both.",
                code: """
                let first = &items[0];
                println!("{first}");
                items.push("compiler");
                """,
                question: "Why is the push valid in this order?",
                answers: ["The shared borrow is no longer used", "Vec never moves", "push is immutable"],
                correctAnswer: 0,
                feedback: "Non-lexical lifetimes end the shared borrow after its final use."
            )

        case "modules":
            RustLessonPractice(
                rule: "mod declares a module; pub exposes selected items; use shortens a path without changing privacy.",
                code: """
                mod greeter;
                use greeter::message;

                fn main() { println!("{}", message()); }
                """,
                question: "What makes message callable from main.rs?",
                answers: ["The file name alone", "A pub declaration in greeter", "Cargo.lock"],
                correctAnswer: 1,
                feedback: "The module exists through mod, but the function must also be public to its caller."
            )

        default:
            RustLessonPractice(
                rule: brief.explanation,
                code: "// Build the smallest example for:\n// \(concept)",
                question: "What is the best next step when your model and rustc disagree?",
                answers: ["Add unsafe", "Read the diagnostic and make one intentional edit", "Ignore the warning"],
                correctAnswer: 1,
                feedback: "Small, evidence-driven changes make the compiler part of the learning loop."
            )
        }
    }
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
