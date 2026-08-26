import SwiftUI

enum CrabrixTheme {
    static let background = Color(red: 0.045, green: 0.063, blue: 0.083)
    static let panel = Color(red: 0.071, green: 0.094, blue: 0.122)
    static let raised = Color(red: 0.095, green: 0.125, blue: 0.157)
    static let border = Color.white.opacity(0.11)
    static let muted = Color(red: 0.53, green: 0.58, blue: 0.64)
    static let coral = Color(red: 1.0, green: 0.39, blue: 0.27)
    static let mint = Color(red: 0.42, green: 0.83, blue: 0.66)
    static let blue = Color(red: 0.41, green: 0.70, blue: 1.0)
    static let amber = Color(red: 0.95, green: 0.72, blue: 0.34)
}

enum CrabrixBuildInfo {
    #if DEBUG
    static let runTiming = "Debug builds can take about one minute. The normal Xcode Run scheme uses optimized Release."
    static let checkTiming = "A Debug check usually takes 15–20 seconds."
    #else
    static let runTiming = "The optimized local build usually completes in a few seconds."
    static let checkTiming = "The optimized local check usually completes in a few seconds."
    #endif
}

extension View {
    func crabrixPanel(cornerRadius: CGFloat = 12) -> some View {
        background(CrabrixTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(CrabrixTheme.border, lineWidth: 1)
            }
    }
}

extension Duration {
    var crabrixDescription: String {
        let parts = components
        let seconds = Double(parts.seconds) + Double(parts.attoseconds) / 1_000_000_000_000_000_000
        if seconds < 1 {
            return "\(Int(seconds * 1_000)) ms"
        }
        return String(format: "%.2f s", seconds)
    }
}
