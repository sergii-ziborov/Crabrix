import SwiftUI
import UIKit

/// Render the validated Rust Canvas output palette in the native Output view.
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

enum CrabrixAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark
    case cyberpunk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Auto"
        case .light: "Light"
        case .dark: "Dark"
        case .cyberpunk: "Cyberpunk"
        }
    }

    var systemImage: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.stars.fill"
        case .cyberpunk: "bolt.shield.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark, .cyberpunk: .dark
        }
    }
}

enum CrabrixTheme {
    static var isCyberpunk: Bool {
        UserDefaults.standard.string(forKey: "crabrix.appearance")
            == CrabrixAppearance.cyberpunk.rawValue
    }

    static var background: Color { adaptive(
        light: UIColor(red: 0.956, green: 0.969, blue: 0.984, alpha: 1),
        dark: UIColor(red: 0.045, green: 0.063, blue: 0.083, alpha: 1),
        cyber: UIColor(red: 0.020, green: 0.024, blue: 0.039, alpha: 1)
    ) }
    static var editor: Color { adaptive(
        light: UIColor(red: 0.985, green: 0.990, blue: 0.996, alpha: 1),
        dark: UIColor(red: 0.052, green: 0.071, blue: 0.092, alpha: 1),
        cyber: UIColor(red: 0.027, green: 0.031, blue: 0.043, alpha: 1)
    ) }
    static var panel: Color { adaptive(
        light: .white,
        dark: UIColor(red: 0.071, green: 0.094, blue: 0.122, alpha: 1),
        cyber: UIColor(red: 0.055, green: 0.067, blue: 0.094, alpha: 1)
    ) }
    static var raised: Color { adaptive(
        light: UIColor(red: 0.902, green: 0.929, blue: 0.957, alpha: 1),
        dark: UIColor(red: 0.095, green: 0.125, blue: 0.157, alpha: 1),
        cyber: UIColor(red: 0.086, green: 0.106, blue: 0.149, alpha: 1)
    ) }
    static var border: Color { adaptive(
        light: UIColor.black.withAlphaComponent(0.11),
        dark: UIColor.white.withAlphaComponent(0.11),
        cyber: UIColor(red: 1.0, green: 0.73, blue: 0.0, alpha: 0.36)
    ) }
    static var primary: Color { adaptive(
        light: UIColor(red: 0.075, green: 0.102, blue: 0.145, alpha: 1),
        dark: .white,
        cyber: UIColor(red: 0.94, green: 0.97, blue: 0.98, alpha: 1)
    ) }
    static var muted: Color { adaptive(
        light: UIColor(red: 0.35, green: 0.40, blue: 0.47, alpha: 1),
        dark: UIColor(red: 0.53, green: 0.58, blue: 0.64, alpha: 1),
        cyber: UIColor(red: 0.65, green: 0.74, blue: 0.79, alpha: 1)
    ) }
    static var coral: Color { isCyberpunk ? Color(red: 1.0, green: 0.73, blue: 0.0) : Color(red: 1.0, green: 0.39, blue: 0.27) }
    static var mint: Color { isCyberpunk ? Color(red: 0.15, green: 0.91, blue: 0.60) : Color(red: 0.42, green: 0.83, blue: 0.66) }
    static var blue: Color { isCyberpunk ? Color(red: 0.30, green: 0.91, blue: 1.0) : Color(red: 0.41, green: 0.70, blue: 1.0) }
    static var amber: Color { isCyberpunk ? Color(red: 1.0, green: 0.73, blue: 0.0) : Color(red: 0.95, green: 0.72, blue: 0.34) }
    static var violet: Color { isCyberpunk ? Color(red: 1.0, green: 0.30, blue: 0.65) : Color(red: 0.67, green: 0.45, blue: 0.98) }
    static var cyan: Color { isCyberpunk ? Color(red: 0.30, green: 0.91, blue: 1.0) : Color(red: 0.25, green: 0.82, blue: 0.82) }
    static var indigo: Color { isCyberpunk ? Color(red: 0.64, green: 0.80, blue: 1.0) : Color(red: 0.45, green: 0.49, blue: 1.0) }
    static var danger: Color { isCyberpunk ? Color(red: 0.73, green: 0.10, blue: 0.18) : Color(red: 0.77, green: 0.14, blue: 0.18) }

    static func adaptive(light: UIColor, dark: UIColor, cyber: UIColor) -> Color {
        if isCyberpunk { return Color(uiColor: cyber) }
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

extension RustCourseTheme {
    var primaryColor: Color {
        if CrabrixTheme.isCyberpunk { return CrabrixTheme.coral }
        switch self {
        case .basics: CrabrixTheme.mint
        case .ownership: CrabrixTheme.coral
        case .projects: CrabrixTheme.blue
        case .concurrency: CrabrixTheme.amber
        case .systems: CrabrixTheme.violet
        case .interview: CrabrixTheme.cyan
        case .algorithms: CrabrixTheme.indigo
        }
    }

    var secondaryColor: Color {
        if CrabrixTheme.isCyberpunk {
            switch self {
            case .basics: return CrabrixTheme.cyan
            case .ownership: return CrabrixTheme.amber
            case .projects: return CrabrixTheme.violet
            case .concurrency: return CrabrixTheme.coral
            case .systems: return CrabrixTheme.blue
            case .interview: return CrabrixTheme.mint
            case .algorithms: return CrabrixTheme.amber
            }
        }
        switch self {
        case .basics: return Color(red: 0.20, green: 0.61, blue: 0.55)
        case .ownership: return Color(red: 0.82, green: 0.22, blue: 0.27)
        case .projects: return Color(red: 0.25, green: 0.48, blue: 0.94)
        case .concurrency: return Color(red: 0.84, green: 0.45, blue: 0.14)
        case .systems: return Color(red: 0.43, green: 0.32, blue: 0.82)
        case .interview: return Color(red: 0.08, green: 0.58, blue: 0.64)
        case .algorithms: return Color(red: 0.29, green: 0.30, blue: 0.78)
        }
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
    @ViewBuilder
    func crabrixPanel(cornerRadius: CGFloat = 12) -> some View {
        background(CrabrixTheme.panel)
            .clipShape(CrabrixCardShape(cornerRadius: cornerRadius))
            .overlay {
                CrabrixCardShape(cornerRadius: cornerRadius)
                    .stroke(CrabrixTheme.border, lineWidth: CrabrixTheme.isCyberpunk ? 1.5 : 1)
            }
    }
}

struct CrabrixCardShape: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        guard CrabrixTheme.isCyberpunk else {
            return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: rect)
        }
        let cut = min(cornerRadius, rect.width / 8, rect.height / 4)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cut))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + cut, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - cut))
        path.closeSubpath()
        return path
    }
}

struct CrabrixControlShape: Shape {
    enum Classic { case circle, capsule }
    let classic: Classic

    func path(in rect: CGRect) -> Path {
        if CrabrixTheme.isCyberpunk {
            return CrabrixCardShape(cornerRadius: 10).path(in: rect)
        }
        switch classic {
        case .circle: return Circle().path(in: rect)
        case .capsule: return Capsule().path(in: rect)
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
