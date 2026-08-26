import SwiftUI
import UIKit

enum CrabrixAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Auto"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var systemImage: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.stars.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum CrabrixTheme {
    static let background = adaptive(
        light: UIColor(red: 0.956, green: 0.969, blue: 0.984, alpha: 1),
        dark: UIColor(red: 0.045, green: 0.063, blue: 0.083, alpha: 1)
    )
    static let editor = adaptive(
        light: UIColor(red: 0.985, green: 0.990, blue: 0.996, alpha: 1),
        dark: UIColor(red: 0.052, green: 0.071, blue: 0.092, alpha: 1)
    )
    static let panel = adaptive(
        light: .white,
        dark: UIColor(red: 0.071, green: 0.094, blue: 0.122, alpha: 1)
    )
    static let raised = adaptive(
        light: UIColor(red: 0.902, green: 0.929, blue: 0.957, alpha: 1),
        dark: UIColor(red: 0.095, green: 0.125, blue: 0.157, alpha: 1)
    )
    static let border = adaptive(
        light: UIColor.black.withAlphaComponent(0.11),
        dark: UIColor.white.withAlphaComponent(0.11)
    )
    static let primary = adaptive(
        light: UIColor(red: 0.075, green: 0.102, blue: 0.145, alpha: 1),
        dark: .white
    )
    static let muted = adaptive(
        light: UIColor(red: 0.35, green: 0.40, blue: 0.47, alpha: 1),
        dark: UIColor(red: 0.53, green: 0.58, blue: 0.64, alpha: 1)
    )
    static let coral = Color(red: 1.0, green: 0.39, blue: 0.27)
    static let mint = Color(red: 0.42, green: 0.83, blue: 0.66)
    static let blue = Color(red: 0.41, green: 0.70, blue: 1.0)
    static let amber = Color(red: 0.95, green: 0.72, blue: 0.34)

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
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
