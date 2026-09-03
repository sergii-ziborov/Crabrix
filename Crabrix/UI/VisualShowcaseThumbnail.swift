import SwiftUI

/// A still of what a canvas project actually prints when it runs.
///
/// The library used to draw one hash-seeded rainbow grid behind every visual
/// project. It said nothing about any of them, two projects looked identical,
/// and next to the rest of the interface it read as static. These are each
/// project's own palette and its own pixel rule, ported from the Rust in
/// `RustVisualShowcaseCatalog`, so a card shows the picture its program makes.
enum VisualShowcaseArtwork {
    struct Artwork: Sendable, Equatable {
        let width: Int
        let height: Int
        /// The palette the project declares in its own source.
        let palette: [String]
        /// One palette index per pixel, row-major.
        let indices: [Int]

        var background: Color { Color(crabrixHex: palette.first ?? "#000000") }

        func color(at index: Int) -> Color {
            Color(crabrixHex: palette[min(max(indices[index], 0), palette.count - 1)])
        }
    }

    static func artwork(for projectID: String) -> Artwork? {
        switch projectID {
        case "pixel-sunset": pixelSunset()
        case "cellular-garden": cellularGarden()
        case "mandelbrot-canvas": mandelbrot()
        case "constellation-map": constellation()
        case "terrain-map": terrain()
        case "color-waves": colorWaves()
        default: nil
        }
    }

    // MARK: - Ports of the catalogue's Rust

    private static func pixelSunset() -> Artwork {
        let width = 24, height = 16
        var indices: [Int] = []
        for y in 0..<height {
            for x in 0..<width {
                let dx = x - 17
                let dy = y - 6
                let sun = dx * dx + dy * dy <= 9
                let color: Int
                if sun {
                    color = 4
                } else if y < 5 {
                    color = 1
                } else if y < 9 {
                    color = 2
                } else if abs(x - 17) < 3 {
                    color = 4
                } else if (x + y) % 4 == 0 {
                    color = 5
                } else {
                    color = 3
                }
                indices.append(color)
            }
        }
        return Artwork(
            width: width,
            height: height,
            palette: ["#111827", "#312E81", "#F97316", "#0F766E", "#FDE68A", "#22D3EE"],
            indices: indices
        )
    }

    private static func cellularGarden() -> Artwork {
        let width = 24, height = 16
        var grid = [Bool](repeating: false, count: width * height)
        for (x, y) in [
            (4, 5), (5, 6), (3, 7), (4, 7), (5, 7),
            (14, 4), (15, 4), (16, 4), (16, 5),
        ] {
            grid[y * width + x] = true
        }

        func neighbours(_ x: Int, _ y: Int) -> Int {
            var total = 0
            for dy in -1...1 {
                for dx in -1...1 where !(dx == 0 && dy == 0) {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                    if grid[ny * width + nx] { total += 1 }
                }
            }
            return total
        }

        var indices: [Int] = []
        for y in 0..<height {
            for x in 0..<width {
                let count = neighbours(x, y)
                let alive = count == 3 || (grid[y * width + x] && count == 2)
                indices.append(alive ? 2 : 0)
            }
        }
        return Artwork(
            width: width,
            height: height,
            palette: ["#071A13", "#166534", "#4ADE80"],
            indices: indices
        )
    }

    private static func mandelbrot() -> Artwork {
        let width = 32, height = 20
        var indices: [Int] = []
        for py in 0..<height {
            for px in 0..<width {
                let cx = Double(px) / Double(width) * 3.2 - 2.2
                let cy = Double(py) / Double(height) * 2.2 - 1.1
                var x = 0.0, y = 0.0, step = 0
                while x * x + y * y <= 4.0 && step < 30 {
                    let nextX = x * x - y * y + cx
                    y = 2.0 * x * y + cy
                    x = nextX
                    step += 1
                }
                indices.append(step == 30 ? 0 : 1 + step * 5 / 30)
            }
        }
        return Artwork(
            width: width,
            height: height,
            palette: ["#020617", "#1E1B4B", "#4338CA", "#7C3AED", "#EC4899", "#FDE047"],
            indices: indices
        )
    }

    private static func constellation() -> Artwork {
        let width = 24, height = 16
        var indices = [Int](repeating: 0, count: width * height)
        for (x, y, brightness) in [
            (3, 4, 2), (8, 2, 1), (11, 7, 2),
            (15, 5, 1), (19, 3, 2), (20, 11, 1),
            (6, 12, 2), (13, 13, 1),
        ] {
            indices[y * width + x] = brightness == 2 ? 3 : 2
            if x + 1 < width { indices[y * width + x + 1] = 1 }
        }
        return Artwork(
            width: width,
            height: height,
            palette: ["#020617", "#334155", "#93C5FD", "#FFFFFF"],
            indices: indices
        )
    }

    private static func terrain() -> Artwork {
        let width = 24, height = 16

        // The same wrapping u32 arithmetic the Rust uses, so the island is the
        // island the compiler draws rather than something that merely rhymes.
        func noise(_ x: UInt32, _ y: UInt32) -> UInt32 {
            var value = (x &* 374_761_393) ^ (y &* 668_265_263)
            value = (value ^ (value >> 13)) &* 1_274_126_177
            return value ^ (value >> 16)
        }

        var indices: [Int] = []
        for y in 0..<height {
            for x in 0..<width {
                let edge = min(min(x, width - 1 - x), min(y, height - 1 - y))
                let value = Int(noise(UInt32(x), UInt32(y)) % 100) + edge * 8
                let color: Int
                switch value {
                case 0...38: color = 0
                case 39...56: color = 1
                case 57...82: color = 2
                case 83...112: color = 3
                default: color = 4
                }
                indices.append(color)
            }
        }
        return Artwork(
            width: width,
            height: height,
            palette: ["#082F49", "#0EA5E9", "#FDE68A", "#22C55E", "#F8FAFC"],
            indices: indices
        )
    }

    private static func colorWaves() -> Artwork {
        let width = 32, height = 16
        var indices: [Int] = []
        for y in 0..<height {
            for x in 0..<width {
                let wave = (
                    sin(Double(x) * 0.45)
                        + cos(Double(y) * 0.70)
                        + sin(Double(x + y) * 0.18)
                ) / 3.0
                let color = Int(((wave + 1.0) * 2.5).rounded())
                indices.append(min(max(color, 0), 5))
            }
        }
        return Artwork(
            width: width,
            height: height,
            palette: ["#172554", "#1D4ED8", "#06B6D4", "#34D399", "#FACC15", "#FB7185"],
            indices: indices
        )
    }
}

/// Draws one canvas project's still at the size its pixels actually have.
///
/// The picture keeps its own proportions and is never stretched or cropped: a
/// fractal that has been squashed into a banner says less about the project
/// than a small, correct one. The card centres it, so the thumbnail reads as a
/// framed piece of the program's output rather than as wallpaper.
struct VisualShowcaseThumbnail: View {
    let projectID: String

    var body: some View {
        if let artwork = VisualShowcaseArtwork.artwork(for: projectID) {
            Canvas { context, size in
                context.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .color(artwork.background)
                )
                let cell = min(
                    size.width / CGFloat(artwork.width),
                    size.height / CGFloat(artwork.height)
                )
                let originX = (size.width - cell * CGFloat(artwork.width)) / 2
                let originY = (size.height - cell * CGFloat(artwork.height)) / 2
                for row in 0..<artwork.height {
                    for column in 0..<artwork.width {
                        context.fill(
                            Path(CGRect(
                                x: originX + CGFloat(column) * cell,
                                y: originY + CGFloat(row) * cell,
                                width: cell + 0.5,
                                height: cell + 0.5
                            )),
                            with: .color(artwork.color(at: row * artwork.width + column))
                        )
                    }
                }
            }
            .aspectRatio(
                CGFloat(artwork.width) / CGFloat(artwork.height),
                contentMode: .fit
            )
            .accessibilityHidden(true)
        } else {
            LinearGradient(
                colors: [CrabrixTheme.raised, CrabrixTheme.panel],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .aspectRatio(3.0 / 2.0, contentMode: .fit)
            .accessibilityHidden(true)
        }
    }
}

/// One reading of a `#RRGGBB` palette entry, shared by the Output canvas and
/// the library thumbnails so both show a project in the same colours.
extension Color {
    init(crabrixHex value: String) {
        let hex = String(value.dropFirst())
        let number = UInt64(hex, radix: 16) ?? 0
        self.init(
            .sRGB,
            red: Double((number >> 16) & 0xFF) / 255,
            green: Double((number >> 8) & 0xFF) / 255,
            blue: Double(number & 0xFF) / 255,
            opacity: 1
        )
    }
}
