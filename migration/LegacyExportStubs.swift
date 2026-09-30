// These signatures allow the legacy curriculum models to run in a standalone
// exporter. The exporter never calls the compiler evidence validator.
import Foundation

struct CrabrixProject: Sendable {
    enum Kind { case visual }
    let name: String
    let files: [String: String]
    let entryFile: String
    init(
        name: String, files: [String: String], entryFile: String, provenance: String?,
        projectDescription: String = "", tags: [String] = [], folder: String? = nil,
        kind: Kind = .visual
    ) {
        self.name = name
        self.files = files
        self.entryFile = entryFile
    }
}

struct CompilationResult {
    enum Phase { case run }
    struct Diagnostic { let code: String? }
    let succeeded: Bool
    let phase: Phase
    let stdout: String
    let diagnostics: [Diagnostic]
}

struct TermTrainPair {
    let id: String
    let term: String
    let description: String
    let topic: String
    init(id: String, term: String, description: String, topic: String? = nil) {
        self.id = id
        self.term = term
        self.description = description
        self.topic = topic ?? id
    }
}
