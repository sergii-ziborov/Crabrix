import Foundation

/// How an installed Academy example is grouped and how hard it reads.
enum RustShowcaseCategory: String, CaseIterable, Identifiable, Sendable {
    case graphics
    case algorithms
    case data
    case text
    case simulation
    case systems
    case math
    case games

    var id: String { rawValue }

    var title: String {
        switch self {
        case .graphics: "Graphics"
        case .algorithms: "Algorithms"
        case .data: "Data"
        case .text: "Text"
        case .simulation: "Simulation"
        case .systems: "Systems"
        case .math: "Math"
        case .games: "Games"
        }
    }

    var systemImage: String {
        switch self {
        case .graphics: "paintpalette.fill"
        case .algorithms: "function"
        case .data: "tablecells.fill"
        case .text: "text.alignleft"
        case .simulation: "waveform.path.ecg"
        case .systems: "cpu.fill"
        case .math: "x.squareroot"
        case .games: "gamecontroller.fill"
        }
    }
}

enum RustShowcaseDifficulty: String, CaseIterable, Identifiable, Sendable {
    case starter
    case intermediate
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .starter: "Starter"
        case .intermediate: "Intermediate"
        case .advanced: "Advanced"
        }
    }

    var order: Int {
        switch self {
        case .starter: 0
        case .intermediate: 1
        case .advanced: 2
        }
    }
}

struct RustShowcaseProject: Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
    let category: RustShowcaseCategory
    let difficulty: RustShowcaseDifficulty
    let concepts: [String]
    let project: CrabrixProject
    let contentDigest: String
    let illustration: ShowcaseIllustration?

    var isGuided: Bool { project.files["README.md"] != nil }
    var isVisual: Bool {
        project.files.values.contains {
            $0.contains(RustCanvasOutput.marker)
        }
    }

    /// Everything a search box should look at.
    var searchHaystack: String {
        ([title, detail, category.title, difficulty.title] + concepts)
            .joined(separator: " ")
            .lowercased()
    }
}

struct ShowcaseIllustration: Sendable {
    let url: URL
    let alt: String
    let caption: String
}

struct ExampleGuideSection: Identifiable, Sendable {
    let title: String
    let body: String
    var id: String { title }

    static func sections(in readme: String) -> [Self] {
        let visible = Set(["What to notice", "What this project does", "How it works",
                           "Try it", "Your challenge", "Challenge"])
        var sections: [Self] = []
        var heading: String?
        var lines: [String] = []
        func flush() {
            guard let heading, visible.contains(heading) else { return }
            let body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { sections.append(Self(title: heading, body: body)) }
        }
        for line in readme.components(separatedBy: .newlines) {
            if line.hasPrefix("## ") {
                flush()
                heading = String(line.dropFirst(3))
                lines = []
            } else if heading != nil {
                lines.append(line)
            }
        }
        flush()
        return sections
    }
}

/// Metadata stays in the signed CoursePack; guest Rust sources are ordinary
/// files next to this JSON and never become Swift literals in the app binary.
struct ShowcaseProjectDTO: Decodable, Sendable {
    struct Project: Decodable, Sendable {
        let name: String
        let entryFile: String
    }
    struct Illustration: Decodable, Sendable {
        let path: String
        let alt: String
        let caption: String
    }

    let id: String
    let title: String
    let detail: String
    let systemImage: String
    let category: String
    let difficulty: String
    let concepts: [String]
    let order: Int
    let contentDigest: String
    let project: Project
    let illustration: Illustration?

    func runtimeProject(files: [String: String], illustrationURL: URL?) throws -> RustShowcaseProject {
        guard let category = RustShowcaseCategory(rawValue: category),
              let difficulty = RustShowcaseDifficulty(rawValue: difficulty),
              !title.isEmpty, !detail.isEmpty, !systemImage.isEmpty,
              !project.name.isEmpty, !concepts.isEmpty,
              contentDigest.count == 64,
              contentDigest.allSatisfy({ "0123456789abcdef".contains($0) }),
              files[project.entryFile] != nil, files["Cargo.toml"] != nil,
              illustration == nil || (illustrationURL != nil &&
                  !(illustration?.alt.isEmpty ?? true) &&
                  !(illustration?.caption.isEmpty ?? true)) else {
            throw CoursePackError.manifestMismatch("library project \(id)")
        }
        let isVisual = files.values.contains { $0.contains(RustCanvasOutput.marker) }
        return RustShowcaseProject(
            id: id, title: title, detail: detail, systemImage: systemImage,
            category: category, difficulty: difficulty, concepts: concepts,
            project: CrabrixProject(
                name: project.name, files: files, entryFile: project.entryFile,
                provenance: nil, folder: isVisual ? "Visual Gallery" : nil,
                kind: isVisual ? .visual : .general
            ),
            contentDigest: contentDigest,
            illustration: illustration.flatMap { item in
                illustrationURL.map { ShowcaseIllustration(url: $0, alt: item.alt, caption: item.caption) }
            }
        )
    }
}
