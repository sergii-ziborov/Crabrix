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
    // Preserve the saved gold theme while giving the new palette its own ID.
    case amberCircuit = "cyberpunk"
    case cyberpunk = "cyberpunkNeon"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Auto"
        case .light: "Light"
        case .dark: "Dark"
        case .amberCircuit: "Amber Circuit"
        case .cyberpunk: "Cyberpunk"
        }
    }

    var systemImage: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.stars.fill"
        case .amberCircuit: "cpu.fill"
        case .cyberpunk: "bolt.shield.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark, .amberCircuit, .cyberpunk: .dark
        }
    }
}

enum CrabrixTheme {
    static var appearance: CrabrixAppearance {
        UserDefaults.standard.string(forKey: "crabrix.appearance")
            .flatMap(CrabrixAppearance.init(rawValue:)) ?? .system
    }

    static var isCyberpunk: Bool { appearance == .cyberpunk }
    static var isAmberCircuit: Bool { appearance == .amberCircuit }
    static var usesAngularPanels: Bool { isCyberpunk || isAmberCircuit }

    static var background: Color { adaptive(
        light: UIColor(red: 0.956, green: 0.969, blue: 0.984, alpha: 1),
        dark: UIColor(red: 0.045, green: 0.063, blue: 0.083, alpha: 1),
        amber: UIColor(red: 0.035, green: 0.031, blue: 0.020, alpha: 1),
        neon: UIColor(red: 0.025, green: 0.047, blue: 0.080, alpha: 1)
    ) }
    static var editor: Color { adaptive(
        light: UIColor(red: 0.985, green: 0.990, blue: 0.996, alpha: 1),
        dark: UIColor(red: 0.052, green: 0.071, blue: 0.092, alpha: 1),
        amber: UIColor(red: 0.047, green: 0.043, blue: 0.031, alpha: 1),
        neon: UIColor(red: 0.027, green: 0.043, blue: 0.071, alpha: 1)
    ) }
    static var panel: Color { adaptive(
        light: .white,
        dark: UIColor(red: 0.071, green: 0.094, blue: 0.122, alpha: 1),
        amber: UIColor(red: 0.090, green: 0.078, blue: 0.051, alpha: 1),
        neon: UIColor(red: 0.082, green: 0.055, blue: 0.090, alpha: 1)
    ) }
    static var raised: Color { adaptive(
        light: UIColor(red: 0.902, green: 0.929, blue: 0.957, alpha: 1),
        dark: UIColor(red: 0.095, green: 0.125, blue: 0.157, alpha: 1),
        amber: UIColor(red: 0.145, green: 0.122, blue: 0.075, alpha: 1),
        neon: UIColor(red: 0.165, green: 0.078, blue: 0.125, alpha: 1)
    ) }
    static var border: Color { adaptive(
        light: UIColor.black.withAlphaComponent(0.11),
        dark: UIColor.white.withAlphaComponent(0.11),
        amber: UIColor(red: 1.0, green: 0.73, blue: 0.0, alpha: 0.36),
        neon: UIColor(red: 0.95, green: 0.25, blue: 0.37, alpha: 0.44)
    ) }
    static var primary: Color { adaptive(
        light: UIColor(red: 0.075, green: 0.102, blue: 0.145, alpha: 1),
        dark: .white,
        amber: UIColor(red: 1.0, green: 0.965, blue: 0.87, alpha: 1),
        neon: UIColor(red: 0.92, green: 0.97, blue: 0.99, alpha: 1)
    ) }
    static var muted: Color { adaptive(
        light: UIColor(red: 0.35, green: 0.40, blue: 0.47, alpha: 1),
        dark: UIColor(red: 0.53, green: 0.58, blue: 0.64, alpha: 1),
        amber: UIColor(red: 0.81, green: 0.76, blue: 0.64, alpha: 1),
        neon: UIColor(red: 0.70, green: 0.79, blue: 0.84, alpha: 1)
    ) }
    /// Ink for bright filled controls, independent of light/dark surface text.
    static let onAccent = Color(red: 0.005, green: 0.008, blue: 0.012)

    static var coral: Color { accent(
        regular: Color(red: 1.0, green: 0.39, blue: 0.27),
        amber: Color(red: 1.0, green: 0.75, blue: 0.20),
        neon: Color(red: 0.98, green: 0.30, blue: 0.36)
    ) }
    static var mint: Color { accent(
        regular: Color(red: 0.42, green: 0.83, blue: 0.66),
        amber: Color(red: 0.60, green: 0.85, blue: 0.64),
        neon: Color(red: 0.40, green: 0.91, blue: 0.79)
    ) }
    static var blue: Color { accent(
        regular: Color(red: 0.41, green: 0.70, blue: 1.0),
        amber: Color(red: 0.90, green: 0.79, blue: 0.54),
        neon: Color(red: 0.31, green: 0.88, blue: 0.95)
    ) }
    static var lessonCode: Color { adaptive(
        light: UIColor(red: 0.04, green: 0.32, blue: 0.65, alpha: 1),
        dark: UIColor(red: 0.55, green: 0.79, blue: 1.0, alpha: 1),
        amber: UIColor(red: 1.0, green: 0.83, blue: 0.43, alpha: 1),
        neon: UIColor(red: 0.40, green: 0.89, blue: 0.96, alpha: 1)
    ) }
    static var amber: Color { accent(
        regular: Color(red: 0.95, green: 0.72, blue: 0.34),
        amber: Color(red: 1.0, green: 0.75, blue: 0.20),
        neon: Color(red: 0.96, green: 0.85, blue: 0.44)
    ) }
    static var violet: Color { accent(
        regular: Color(red: 0.67, green: 0.45, blue: 0.98),
        amber: Color(red: 0.85, green: 0.69, blue: 0.50),
        neon: Color(red: 0.79, green: 0.64, blue: 1.0)
    ) }
    static var cyan: Color { accent(
        regular: Color(red: 0.25, green: 0.82, blue: 0.82),
        amber: Color(red: 0.60, green: 0.84, blue: 0.80),
        neon: Color(red: 0.31, green: 0.88, blue: 0.95)
    ) }
    static var indigo: Color { accent(
        regular: Color(red: 0.45, green: 0.49, blue: 1.0),
        amber: Color(red: 0.80, green: 0.75, blue: 0.57),
        neon: Color(red: 0.58, green: 0.72, blue: 1.0)
    ) }
    static var danger: Color { accent(
        regular: Color(red: 0.77, green: 0.14, blue: 0.18),
        amber: Color(red: 0.64, green: 0.12, blue: 0.16),
        neon: Color(red: 0.62, green: 0.12, blue: 0.26)
    ) }

    private static func accent(regular: Color, amber: Color, neon: Color) -> Color {
        switch appearance {
        case .amberCircuit: amber
        case .cyberpunk: neon
        default: regular
        }
    }

    static func adaptive(light: UIColor, dark: UIColor, amber: UIColor, neon: UIColor) -> Color {
        switch appearance {
        case .amberCircuit: return Color(uiColor: amber)
        case .cyberpunk: return Color(uiColor: neon)
        default:
            return Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark ? dark : light
            })
        }
    }
}

extension RustCourseTheme {
    var primaryColor: Color {
        if CrabrixTheme.usesAngularPanels { return CrabrixTheme.coral }
        return switch self {
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
        if CrabrixTheme.isAmberCircuit {
            return Color(red: 0.82, green: 0.62, blue: 0.28)
        }
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
                    .stroke(CrabrixTheme.border, lineWidth: CrabrixTheme.usesAngularPanels ? 1.5 : 1)
            }
    }
}

/// Use the system toolbar background once; adding a bordered button inside it
/// creates a second rim on current iOS versions.
struct CrabrixModalCloseAction: ToolbarContent {
    var label = "Close"
    var isDisabled = false
    let action: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button(label, systemImage: "xmark", action: action)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(CrabrixTheme.primary)
                .accessibilityLabel(label)
                .disabled(isDisabled)
        }
    }
}

struct CrabrixModalSaveButton: View {
    var isSaving = false
    let action: () -> Void

    var body: some View {
        Button(isSaving ? "Saving…" : "Save", action: action)
            .buttonStyle(.borderedProminent)
            .tint(CrabrixTheme.blue)
            .foregroundStyle(Color.black)
    }
}

struct CrabrixCardShape: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        guard CrabrixTheme.usesAngularPanels else {
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
        if CrabrixTheme.usesAngularPanels {
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
