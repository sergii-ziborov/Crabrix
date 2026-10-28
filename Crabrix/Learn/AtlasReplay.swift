import CryptoKit
import Foundation

enum AtlasReplayError: LocalizedError {
    case invalid(String)
    case unavailable
    case changedSource
    var errorDescription: String? {
        switch self {
        case let .invalid(detail): "This recording could not be verified: \(detail)."
        case .unavailable: "Download this Atlas section to replay its examples offline."
        case .changedSource: "This recording belongs to another version of the example. Update the course and its recording; your own projects remain unchanged."
        }
    }
}

/// Numbers stay in the publisher's exact Rust display text, never Double/NSNumber.
indirect enum AtlasValue: Decodable, Equatable, Sendable {
    case scalar(String)
    case list([AtlasValue], tuple: Bool)
    case set([AtlasValue])
    case map([[AtlasValue]])
    case named(String, AtlasValue)

    private enum Keys: String, CodingKey { case kind, text, items, tuple, entries, name, value }
    init(from decoder: Decoder) throws {
        guard decoder.codingPath.count <= 128 else { throw AtlasReplayError.invalid("value nesting limit") }
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "scalar": self = .scalar(try c.decode(String.self, forKey: .text))
        case "list": self = .list(try c.decode([AtlasValue].self, forKey: .items),
                                 tuple: try c.decodeIfPresent(Bool.self, forKey: .tuple) ?? false)
        case "set": self = .set(try c.decode([AtlasValue].self, forKey: .items))
        case "map": self = .map(try c.decode([[AtlasValue]].self, forKey: .entries))
        case "named": self = .named(try c.decode(String.self, forKey: .name),
                                   try c.decode(AtlasValue.self, forKey: .value))
        default: throw AtlasReplayError.invalid("unknown value kind")
        }
    }

    func validate(nodes: inout Int, depth: Int = 0) throws {
        nodes += 1
        guard nodes <= 100_000, depth <= 32 else { throw AtlasReplayError.invalid("value budget") }
        switch self {
        case let .scalar(text):
            guard text.utf8.count <= 16_384 else { throw AtlasReplayError.invalid("scalar size") }
        case let .list(items, _), let .set(items):
            guard items.count <= 4_096 else { throw AtlasReplayError.invalid("collection size") }
            for item in items { try item.validate(nodes: &nodes, depth: depth + 1) }
        case let .map(entries):
            guard entries.count <= 4_096 else { throw AtlasReplayError.invalid("map size") }
            for pair in entries {
                guard pair.count == 2 else { throw AtlasReplayError.invalid("map pair") }
                for item in pair { try item.validate(nodes: &nodes, depth: depth + 1) }
            }
        case let .named(name, value):
            guard name.utf8.count <= 512 else { throw AtlasReplayError.invalid("value name") }
            try value.validate(nodes: &nodes, depth: depth + 1)
        }
    }

    var text: String {
        switch self {
        case let .scalar(text): text
        case let .list(items, tuple):
            (tuple ? "(" : "[") + items.map(\.text).joined(separator: ", ") + (tuple ? ")" : "]")
        case let .set(items): "{" + items.map(\.text).joined(separator: ", ") + "}"
        case let .map(entries): "{" + entries.map { $0.map(\.text).joined(separator: ": ") }.joined(separator: ", ") + "}"
        case let .named(name, value): name + value.text
        }
    }
}

struct AtlasReplay: Decodable, Sendable {
    struct Site: Decodable, Sendable {
        struct Edge: Decodable, Sendable { let collection: String; let from: String; let to: String }
        let line: Int
        let function: String
        let statement: String
        let edge: Edge?
    }
    struct Value: Decodable, Sendable { let type: String; let data: AtlasValue }
    struct Local: Decodable, Sendable {
        let name: String
        let value: Int
        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            name = try c.decode(String.self); value = try c.decode(Int.self)
            guard c.isAtEnd else { throw AtlasReplayError.invalid("local reference") }
        }
    }
    struct StackFrame: Decodable, Sendable {
        let function: String
        /// Recording-local activation ID; recursion can exceed source line count.
        let activation: Int
        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            function = try c.decode(String.self); activation = try c.decode(Int.self)
            guard c.isAtEnd else { throw AtlasReplayError.invalid("stack frame") }
        }
    }
    struct Frame: Decodable, Sendable {
        let site: Int
        let stack: [StackFrame]
        let locals: [Local]
    }
    struct Verification: Decodable, Sendable {
        let stdoutMatchesOriginal: Bool
        let independentOracle: Bool
        let omittedCaptures: Int
    }
    let version: Int
    let key: String
    let sourceHash: String
    let pattern: String
    let category: String
    let title: String
    let idea: String
    let complexity: String
    let source: String
    let input: String
    let stdout: String
    let sites: [Site]
    let values: [Value]
    let frames: [Frame]
    let verification: Verification

    static func decode(_ bytes: Data, expectedSource: String, expectedKey: String) throws -> Self {
        guard bytes.count <= 2 * 1_024 * 1_024 else { throw AtlasReplayError.invalid("recording size") }
        let replay = try JSONDecoder().decode(Self.self, from: bytes)
        guard replay.version == 1, replay.key == expectedKey,
              replay.source == expectedSource, replay.sourceHash == digest(Data(expectedSource.utf8)),
              replay.key == "\(replay.pattern)-\(replay.sourceHash.prefix(16))"
        else { throw AtlasReplayError.changedSource }
        try replay.validate()
        return replay
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    static func slug(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 128
            && value.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
    }
    private func validate() throws {
        let lines = source.components(separatedBy: "\n").count
        guard Self.slug(pattern), Self.slug(category), source.utf8.count <= 128 * 1_024,
              title.utf8.count <= 512, idea.utf8.count <= 8_192, complexity.utf8.count <= 8_192,
              input.utf8.count <= 8_192, stdout.utf8.count <= 64 * 1_024,
              !sites.isEmpty, sites.count <= 5_000, values.count <= 10_000,
              frames.count >= 2, frames.count <= 50_000,
              verification.stdoutMatchesOriginal, verification.independentOracle,
              verification.omittedCaptures >= 0 else { throw AtlasReplayError.invalid("recording profile") }
        var nodes = 0
        for value in values {
            guard value.type.utf8.count <= 1_024 else { throw AtlasReplayError.invalid("type size") }
            try value.data.validate(nodes: &nodes)
        }
        for site in sites {
            guard (1...lines).contains(site.line), !site.function.isEmpty,
                  site.function.utf8.count <= 512, site.statement.utf8.count <= 16_384
            else { throw AtlasReplayError.invalid("source location") }
            if let edge = site.edge {
                guard [edge.collection, edge.from, edge.to].allSatisfy({ $0.utf8.count <= 512 })
                else { throw AtlasReplayError.invalid("edge description") }
            }
        }
        for frame in frames {
            guard sites.indices.contains(frame.site), !frame.stack.isEmpty,
                  frame.stack.count <= 128, frame.locals.count <= 256,
                  sites[frame.site].function == frame.stack.last?.function,
                  Set(frame.locals.map(\.name)).count == frame.locals.count,
                  frame.locals.allSatisfy({ !$0.name.isEmpty && $0.name.utf8.count <= 512 && values.indices.contains($0.value) }),
                  frame.stack.allSatisfy({ !$0.function.isEmpty && $0.function.utf8.count <= 512 && $0.activation > 0 })
            else { throw AtlasReplayError.invalid("execution frame") }
        }
    }
}

struct AtlasRecording: Sendable {
    let replay: AtlasReplay
    let lessonID: String
    let packDigest: String
    let packVersion: String
    let courseContentVersion: String
    let previousFrameIndices: [Int?]

    init(replay: AtlasReplay, lessonID: String, packDigest: String, packVersion: String,
         courseContentVersion: String) {
        self.replay = replay; self.lessonID = lessonID; self.packDigest = packDigest
        self.packVersion = packVersion; self.courseContentVersion = courseContentVersion
        var last: [Int: Int] = [:], previous: [Int?] = []
        for (index, frame) in replay.frames.enumerated() {
            let invocation = frame.stack.last!.activation
            previous.append(last[invocation]); last[invocation] = index
        }
        previousFrameIndices = previous
    }
}
