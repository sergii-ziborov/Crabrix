import Foundation

struct RustSemanticContext: Sendable {
    let project: CrabrixProject
    let revision: WorkspaceRevision
    let edition: String
    let plan: CargoBuildPlan
}

struct RustSemanticWorkspace: Codable, Sendable {
    struct File: Codable, Sendable { let path: String; let text: String }
    struct Crate: Codable, Sendable {
        let root: String
        let dependencies: [String: String]
        let edition: String
        let kind: String
        let name: String
        let features: [String]
    }
    let files: [File]
    let crates: [Crate]
    var warnings: [String] = []
}

enum RustSemanticAction: String, CaseIterable, Identifiable, Sendable {
    case definition, references, hover, signature, complete, rename
    var id: String { rawValue }
    var title: String {
        switch self {
        case .definition: "Go to definition"
        case .references: "Find project references"
        case .hover: "Type and documentation"
        case .signature: "Call signature"
        case .complete: "Complete this symbol"
        case .rename: "Rename with preview"
        }
    }
}

struct RustSemanticRange: Codable, Equatable, Sendable {
    let start: Int
    let end: Int
    let unit: String
}
struct RustSemanticEdit: Codable, Equatable, Sendable {
    let range: RustSemanticRange
    let insert: String
}
struct RustSemanticTarget: Decodable, Sendable {
    let file: String
    let range: RustSemanticRange
    let name: String?
    let description: String?
    let declaration: Bool?
}
struct RustSemanticFileChange: Codable, Sendable {
    let file: String
    let edits: [RustSemanticEdit]
}
struct RustSemanticCompletion: Decodable, Identifiable, Sendable {
    let id = UUID()
    let label: String
    let detail: String?
    let kind: String
    let edits: [RustSemanticEdit]
    let imports: [String]
    private enum CodingKeys: String, CodingKey { case label, detail, kind, edits, imports }
}
struct RustSemanticResult: Decodable, Sendable {
    struct Hover: Decodable, Sendable { let text: String; let range: RustSemanticRange }
    struct Signature: Decodable, Sendable { let text: String; let activeParameter: Int?; let parameters: [String] }
    struct Annotation: Decodable, Sendable { let label: String; let description: String?; let needsConfirmation: Bool }
    let targets: [RustSemanticTarget]?
    let references: [RustSemanticTarget]?
    let hover: Hover?
    let signature: Signature?
    let items: [RustSemanticCompletion]?
    let files: [RustSemanticFileChange]?
    let edits: [RustSemanticEdit]?
    let annotations: [Annotation]?
    let text: String?
    let readOnly: Bool?
}
struct RustSemanticEnvelope: Decodable, Sendable {
    let ok: Bool
    let result: RustSemanticResult?
    let error: String?
    let memoryBytes: Int?
    func validated() throws -> RustSemanticResult {
        guard ok, let result else { throw RustSemanticError.unavailable(error ?? "Information is unavailable for this source.") }
        return result
    }
}

struct RustSemanticProposal: Identifiable, Sendable {
    struct ReviewedEdit: Identifiable, Sendable {
        let id = UUID()
        let line: Int
        let before: String
        let after: String
    }
    let id = UUID()
    let before: [String: String]
    let after: [String: String]
    let changedPaths: [String]
    let reviewed: [String: [ReviewedEdit]]

    init(files: [String: String], changes: [RustSemanticFileChange]) throws {
        guard !changes.isEmpty, changes.count <= 2048, Set(changes.map(\.file)).count == changes.count else {
            throw RustSemanticError.unavailable("No unambiguous project edits were produced.")
        }
        var result = files
        var totalEdits = 0
        var reviewed: [String: [ReviewedEdit]] = [:]
        for change in changes {
            try Task.checkCancellation()
            guard !change.file.hasPrefix("__lib/"), !change.file.hasPrefix("__dep/"),
                  let source = files[change.file], !change.edits.isEmpty else {
                throw RustSemanticError.unavailable("Library and generated declarations are read-only in this analysis profile.")
            }
            totalEdits += change.edits.count
            guard totalEdits <= 4096 else { throw RustSemanticError.unavailable("The edit preview exceeds its change budget.") }
            result[change.file] = try RustSemanticText.applying(change.edits, to: source)
            let bytes = Array(source.utf8)
            var previousStart = 0, line = 1
            for edit in change.edits.sorted(by: { $0.range.start < $1.range.start }) {
                guard edit.range.end - edit.range.start <= 4096, edit.insert.utf8.count <= 4096 else {
                    throw RustSemanticError.unavailable("An individual change exceeds the 4 KiB review profile. Source was kept unchanged.")
                }
                line += bytes[previousStart..<edit.range.start].reduce(0) { $0 + ($1 == 10 ? 1 : 0) }
                previousStart = edit.range.start
                reviewed[change.file, default: []].append(.init(line: line,
                    before: String(decoding: bytes[edit.range.start..<edit.range.end], as: UTF8.self), after: edit.insert))
            }
        }
        try ProjectFilePolicy.validate(result)
        before = files; after = result
        self.reviewed = reviewed
        changedPaths = changes.map(\.file).filter { files[$0] != result[$0] }.sorted()
        guard !changedPaths.isEmpty else { throw RustSemanticError.unavailable("The proposed change does not alter project source.") }
    }
}

enum RustSemanticText {
    static func utf8Offset(_ utf16: Int, in text: String) throws -> Int {
        guard utf16 >= 0 else { throw RustSemanticError.unavailable("Invalid editor position.") }
        var units = 0, bytes = 0
        for scalar in text.unicodeScalars {
            if units == utf16 { return bytes }
            let width = scalar.value > 0xFFFF ? 2 : 1
            guard units + width <= utf16 else { throw RustSemanticError.unavailable("The cursor splits a Unicode character.") }
            units += width
            bytes += scalar.value <= 0x7F ? 1 : scalar.value <= 0x7FF ? 2 : scalar.value <= 0xFFFF ? 3 : 4
        }
        guard units == utf16 else { throw RustSemanticError.unavailable("The editor position is outside the source.") }
        return bytes
    }

    static func applying(_ edits: [RustSemanticEdit], to source: String) throws -> String {
        var bytes = Array(source.utf8)
        guard edits.count <= 4096, edits.reduce(0, { $0 + $1.insert.utf8.count }) <= 8 * 1024 * 1024 else {
            throw RustSemanticError.unavailable("The edit budget is exceeded.")
        }
        let sorted = edits.enumerated().sorted {
            if $0.element.range.start != $1.element.range.start { return $0.element.range.start < $1.element.range.start }
            if $0.element.range.end != $1.element.range.end { return $0.element.range.end < $1.element.range.end }
            return $0.offset < $1.offset
        }
        var end = 0
        for (_, edit) in sorted {
            let range = edit.range
            guard range.unit == "utf8", range.start >= end, range.end >= range.start, range.end <= bytes.count,
                  (range.start == bytes.count || bytes[range.start] & 0xC0 != 0x80),
                  (range.end == bytes.count || bytes[range.end] & 0xC0 != 0x80) else {
                throw RustSemanticError.unavailable("Analysis returned overlapping or invalid Unicode edits. Source was kept.")
            }
            end = range.end
        }
        for (_, edit) in sorted.reversed() { bytes.replaceSubrange(edit.range.start..<edit.range.end, with: edit.insert.utf8) }
        guard let result = String(bytes: bytes, encoding: .utf8) else { throw RustSemanticError.unavailable("The edit does not preserve UTF-8 source.") }
        return result
    }

    static func location(offset: Int, in source: String) -> (line: Int, column: Int)? {
        let bytes = Array(source.utf8)
        guard offset >= 0, offset <= bytes.count,
              let prefix = String(bytes: bytes[..<offset], encoding: .utf8) else { return nil }
        let lines = prefix.split(separator: "\n", omittingEmptySubsequences: false)
        return (lines.count, (lines.last.map(String.init) ?? "").utf16.count + 1)
    }
}
