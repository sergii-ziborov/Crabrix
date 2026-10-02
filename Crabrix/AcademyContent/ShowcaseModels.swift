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

/// Metadata stays in the signed CoursePack; guest Rust sources are ordinary
/// files next to this JSON and never become Swift literals in the app binary.
struct ShowcaseProjectDTO: Decodable, Sendable {
    struct Project: Decodable, Sendable {
        let name: String
        let entryFile: String
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

    func runtimeProject(files: [String: String]) throws -> RustShowcaseProject {
        guard let category = RustShowcaseCategory(rawValue: category),
              let difficulty = RustShowcaseDifficulty(rawValue: difficulty),
              !title.isEmpty, !detail.isEmpty, !systemImage.isEmpty,
              !project.name.isEmpty, !concepts.isEmpty,
              contentDigest.count == 64,
              contentDigest.allSatisfy({ "0123456789abcdef".contains($0) }),
              files[project.entryFile] != nil, files["Cargo.toml"] != nil else {
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
            contentDigest: contentDigest
        )
    }
}
