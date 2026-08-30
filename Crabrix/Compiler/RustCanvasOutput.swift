import Foundation

/// A tiny, bounded display protocol for Rust examples that produce something
/// more visual than console prose. A program prints one JSON line prefixed by
/// `CRABRIX_CANVAS:`; Crabrix validates it and renders the pixels natively.
/// The guest still has no UI or network access.
struct RustCanvasFrame: Equatable, Sendable {
    let title: String
    let width: Int
    let height: Int
    let palette: [String]
    let pixels: [Int]
}

struct ParsedRustCanvasOutput: Equatable, Sendable {
    let frame: RustCanvasFrame?
    let plainText: String
}

enum RustCanvasOutput {
    static let marker = "CRABRIX_CANVAS:"
    static let maximumDimension = 64
    static let maximumPixels = maximumDimension * maximumDimension

    private struct Payload: Decodable {
        let title: String?
        let width: Int
        let height: Int
        let palette: [String]
        let pixels: String
    }

    static func parse(_ stdout: String) -> ParsedRustCanvasOutput {
        var lines = stdout.components(separatedBy: .newlines)
        guard let index = lines.firstIndex(where: { $0.hasPrefix(marker) }) else {
            return ParsedRustCanvasOutput(frame: nil, plainText: stdout)
        }

        let encoded = String(lines[index].dropFirst(marker.count))
        guard let data = encoded.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let frame = validated(payload)
        else {
            return ParsedRustCanvasOutput(frame: nil, plainText: stdout)
        }

        lines.remove(at: index)
        while lines.last == "" { lines.removeLast() }
        return ParsedRustCanvasOutput(
            frame: frame,
            plainText: lines.joined(separator: "\n")
        )
    }

    private static func validated(_ payload: Payload) -> RustCanvasFrame? {
        guard (1...maximumDimension).contains(payload.width),
              (1...maximumDimension).contains(payload.height),
              payload.width * payload.height <= maximumPixels,
              (1...16).contains(payload.palette.count),
              payload.palette.allSatisfy(isHexColor),
              payload.pixels.count == payload.width * payload.height
        else { return nil }

        let pixels = payload.pixels.compactMap { character -> Int? in
            Int(String(character), radix: 16)
        }
        guard pixels.count == payload.pixels.count,
              pixels.allSatisfy({ $0 < payload.palette.count })
        else { return nil }

        let title = String(
            (payload.title ?? "Rust Canvas")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(60)
        )
        return RustCanvasFrame(
            title: title.isEmpty ? "Rust Canvas" : title,
            width: payload.width,
            height: payload.height,
            palette: payload.palette.map { $0.uppercased() },
            pixels: pixels
        )
    }

    private static func isHexColor(_ value: String) -> Bool {
        guard value.count == 7, value.first == "#" else { return false }
        return value.dropFirst().allSatisfy { character in
            character.isHexDigit
        }
    }
}
