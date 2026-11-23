import Foundation

/// "Learn with AI": static setup steps, prompts and copy/share actions that
/// connect a learner's own agent to the public, read-only Crabrix Academy MCP.
///
/// Nothing here reads or writes progress. The app keeps "Data Not Collected":
/// no SDK, no events, no analytics. The only network request is the optional
/// status check in `AcademyAIStatusClient`, made when the Learn with AI screen
/// appears.
enum AcademyAIFeature {
    /// Build-time switch. `false` hides both entry points (the Academy library
    /// card and "Learn this lesson with AI" on lessons).
    static let isEnabled = true

    /// Remote, read-only Academy MCP (Streamable HTTP, no sign-in). Same URL as
    /// `ACADEMY_MCP_URL` in the website's `site/lib/ai-learning.ts`.
    static let mcpURL = "https://crabrix.com/mcp/academy"
    /// The first Crabrix MCP release with the `crabrix_academy_*` tools.
    static let sdkVersion = "0.6.0"
    /// Run-time pause switch (PLAN.md, Phase 7).
    static let statusURL = URL(string: "https://crabrix.com/api/academy/v1/status.json")!
    static let websiteOrigin = "https://crabrix.com"

    static func lessonURL(courseID: String, lessonID: String) -> String {
        "\(websiteOrigin)/learn/\(courseID)/\(lessonID)/"
    }
}

/// `{courseId, lessonId}` as used by the AI Learning State and the Academy API.
struct AILearningLessonRef: Equatable, Hashable, Sendable, Encodable {
    let courseId: String
    let lessonId: String
}

/// The agents a learner can connect, in the website's order.
enum AcademyAIClient: String, CaseIterable, Identifiable, Sendable {
    case claude
    case claudeCode = "claude-code"
    case codex
    case cursor
    case other

    var id: String { rawValue }

    var name: String {
        switch self {
        case .claude: "Claude"
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .other: "Other MCP client"
        }
    }

    /// A client that can be opened from this device.
    var openLink: (title: String, url: URL)? {
        switch self {
        case .claude: ("Open Claude", URL(string: "https://claude.ai/new")!)
        case .codex: ("Open ChatGPT", URL(string: "https://chatgpt.com/codex")!)
        case .claudeCode, .cursor, .other: nil
        }
    }

    /// Set up on a computer rather than on this iPhone or iPad.
    var computerNote: String? {
        switch self {
        case .claude: nil
        case .claudeCode: "Claude Code runs on a computer. Copy the command here and run it there."
        case .codex: "These commands set up Codex on a computer (the Codex CLI and IDE extension). Run them there."
        case .cursor: "Cursor runs on a computer. Copy the configuration here and add it there."
        case .other: nil
        }
    }

    enum Block: Equatable, Sendable {
        /// Inline Markdown (bold, emphasis, `code`).
        case text(String)
        /// A command, URL or configuration with its own copy button.
        case code(String, copyTitle: String, accessibilityLabel: String)
    }

    /// The website's connection steps for this client, unchanged in substance.
    var steps: [Block] {
        let url = AcademyAIFeature.mcpURL
        let sdk = AcademyAIFeature.sdkVersion
        switch self {
        case .claude:
            return [
                .text("In Claude on the web, desktop or mobile: **Customize → Connectors → + → Add custom connector**. Name it *Crabrix Academy* and paste this URL:"),
                .code(url, copyTitle: "Copy URL", accessibilityLabel: "Copy the Crabrix Academy MCP URL"),
                .text("No sign-in. Then start a chat with one of the prompts below. A connector you add on the web is also available in the Claude app on your phone or tablet."),
            ]
        case .claudeCode:
            return [
                .text("Add the Academy as a remote MCP server:"),
                .code("claude mcp add --transport http crabrix-academy \(url)",
                      copyTitle: "Copy command", accessibilityLabel: "Copy the Claude Code command"),
                .text("Or install the Crabrix plugin (\(sdk) or newer). It adds a local Academy server, the `crabrix-learn-rust` skill and the shared Playground; an existing installation keeps its handoff skill and rooms."),
                .code("/plugin marketplace add sergii-ziborov/crabrix-sdk\n/plugin install crabrix@crabrix",
                      copyTitle: "Copy plugin commands", accessibilityLabel: "Copy the Crabrix plugin commands for Claude Code"),
            ]
        case .codex:
            return [
                .code("codex mcp add crabrix-academy --url \(url)",
                      copyTitle: "Copy command", accessibilityLabel: "Copy the Codex command"),
                .text("To run the Academy locally instead (Node.js 22 or newer):"),
                .code("codex mcp add crabrix-academy -- npx -y crabrix@\(sdk) academy",
                      copyTitle: "Copy local command", accessibilityLabel: "Copy the Codex command for a local Academy server"),
                .text("Your existing `crabrix` server for Playground rooms stays as it is."),
            ]
        case .cursor:
            return [
                .text("Add this server to `~/.cursor/mcp.json`, then restart Cursor:"),
                .code(Self.cursorConfiguration, copyTitle: "Copy JSON", accessibilityLabel: "Copy the Cursor configuration JSON"),
            ]
        case .other:
            return [
                .text("Add a remote MCP server with Streamable HTTP and no authentication:"),
                .code(url, copyTitle: "Copy URL", accessibilityLabel: "Copy the Crabrix Academy MCP URL"),
                .text("Clients that run local servers can start the same read-only tools with this command (Node.js 22 or newer). Playground rooms keep using the `crabrix` server you may already have."),
                .code("npx -y crabrix@\(sdk) academy",
                      copyTitle: "Copy command", accessibilityLabel: "Copy the command for a local Academy server"),
            ]
        }
    }

    static let cursorConfiguration = """
    {
      "mcpServers": {
        "crabrix-academy": {
          "url": "\(AcademyAIFeature.mcpURL)"
        }
      }
    }
    """
}

/// Public lesson details for "Learn this lesson with AI". No learner data.
struct AcademyAILessonContext: Equatable, Sendable {
    let courseID: String
    let lessonID: String
    let title: String
    /// The lesson's rule, or its concept when a pack has no rule.
    let goal: String
    /// The lesson has a compiler lab in the app (anything but a planned lesson).
    let hasLab: Bool

    var url: String { AcademyAIFeature.lessonURL(courseID: courseID, lessonID: lessonID) }
    var reference: AILearningLessonRef { AILearningLessonRef(courseId: courseID, lessonId: lessonID) }

    init(courseID: String, lessonID: String, title: String, goal: String, hasLab: Bool) {
        self.courseID = courseID
        self.lessonID = lessonID
        self.title = title
        self.goal = goal
        self.hasLab = hasLab
    }

    init(courseID: String, lesson: RustLesson, rule: String) {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(courseID: courseID, lessonID: lesson.id, title: lesson.title,
                  goal: trimmed.isEmpty ? lesson.concept : trimmed, hasLab: lesson.hasCompilerLab)
    }
}

enum AcademyAIPrompts {
    struct Prompt: Identifiable, Equatable, Sendable {
        let id: String
        let title: String
        let text: String
    }

    /// The website's four prompts (`learningPrompts` in `site/lib/ai-learning.ts`).
    static let all: [Prompt] = [
        Prompt(id: "beginner", title: "Beginner",
               text: "Teach me Rust through Crabrix Academy. Start from the basics, give me practical exercises, and help me understand each concept before moving on."),
        Prompt(id: "nodejs", title: "Node.js developer",
               text: "I am experienced with Node.js and TypeScript. Teach me Rust through Crabrix Academy using concepts familiar to backend developers. Give me practical exercises and use the Crabrix Playground when appropriate."),
        Prompt(id: "c", title: "C developer",
               text: "I have experience with C. Teach me Rust through memory management, ownership, borrowing, lifetimes and system programming. Use Crabrix Academy lessons and practical examples."),
        continueLearning,
    ]

    static let continueLearning = Prompt(
        id: "continue", title: "Continue learning",
        text: "Help me continue my Crabrix Rust learning using my available progress and previous exercises. Do not assume I have completed lessons unless the learning state confirms it."
    )

    /// "Continue learning" with the learner's exported state, only when they
    /// chose to include it; otherwise the plain prompt.
    static func continuePrompt(stateJSON: String?) -> String {
        guard let stateJSON else { return continueLearning.text }
        return [
            continueLearning.text,
            "",
            "My Crabrix learning state is below (crabrix.ai-learning-state, version 1), exported from the Crabrix app. Its officialProgress is a read-only copy of the lessons Crabrix checked on my device: use it to know what I have done, never change it, and do not count anything else as passed. You can pass the completed lesson IDs to crabrix_academy_next.",
            "",
            "```json",
            stateJSON,
            "```",
        ].joined(separator: "\n")
    }

    /// Mirrors `lessonPrompt()` in `site/lib/ai-learning.ts`. In the app the
    /// practice line points at the lesson's own compiler lab when it has one,
    /// and otherwise at the web Playground through the agent's tool.
    static func lessonPrompt(_ lesson: AcademyAILessonContext) -> String {
        let practice = lesson.hasLab
            ? "Practice: give me the lesson's exercise (crabrix_academy_get_exercise); I will write and run the code in this lesson's compiler lab in the Crabrix app, where Crabrix checks it."
            : "Practice: open the Crabrix Playground for this lesson (crabrix_academy_open_playground) and I will write the code there. If it has no Playground starter, give me the lesson's exercise (crabrix_academy_get_exercise)."
        return [
            "I'm learning Rust with Crabrix Academy. Teach me this lesson with the Crabrix Academy tools.",
            "Lesson: \(lesson.title) (courseId \"\(lesson.courseID)\", lessonId \"\(lesson.lessonID)\")",
            "Link: \(lesson.url)",
            "Goal: \(lesson.goal.replacingOccurrences(of: "`", with: ""))",
            practice,
            "Explain it step by step for my level, let me write the code myself, give hints before any solution, and do not mark anything as passed: only Crabrix checks do that.",
        ].joined(separator: "\n")
    }

    /// The website's "What your agent can and cannot do".
    static let honestLimits = [
        "It teaches from real Crabrix lessons and links each one, so you can always read the original.",
        "It gives hints before solutions and shows a full solution only when you ask for it.",
        "Its review is an AI review. Only Crabrix checks in the app record a lesson as passed, and the agent cannot change your progress.",
        "It knows what you have finished only if you tell it. Nothing is synchronised between your devices and your agent automatically.",
        "Code runs on your device: in the Playground or the app, and through an agent only after you allow it there.",
        "Whatever you paste into a chat goes to your agent’s model provider under its own terms.",
    ]
}
