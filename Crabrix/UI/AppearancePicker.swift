import SwiftUI

struct AppearancePicker: View {
    @Binding var selection: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        [GridItem(.adaptive(
            minimum: dynamicTypeSize.isAccessibilitySize ? 240 : 108,
            maximum: dynamicTypeSize.isAccessibilitySize ? 640 : 152
        ), spacing: 8)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(CrabrixAppearance.allCases) { appearance in
                let selected = selection == appearance.rawValue
                Button {
                    selection = appearance.rawValue
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 5) {
                            Text(appearance.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .font(.caption)
                                .foregroundStyle(selected ? CrabrixTheme.coral : CrabrixTheme.muted)
                        }
                        HStack(spacing: 5) {
                            Image(systemName: appearance.systemImage)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(CrabrixTheme.muted)
                            ForEach(Array(appearance.previewColors.enumerated()), id: \.offset) { _, color in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(color)
                                    .frame(width: 16, height: 6)
                            }
                        }
                        .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                    .foregroundStyle(CrabrixTheme.primary)
                    .background(selected ? CrabrixTheme.raised : CrabrixTheme.panel)
                    .clipShape(CrabrixCardShape(cornerRadius: 10))
                    .overlay {
                        CrabrixCardShape(cornerRadius: 10)
                            .stroke(selected ? CrabrixTheme.coral : CrabrixTheme.border,
                                    lineWidth: selected ? 1.5 : 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(appearance.title) appearance")
                .accessibilityIdentifier("appearance-\(appearance.rawValue)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .frame(maxWidth: 680, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension CrabrixAppearance {
    var previewColors: [Color] {
        let hex: [String] = switch self {
        case .system: ["#F4F7FB", "#8595AA", "#0C1015"]
        case .light: ["#F4F7FB", "#FF6345", "#69B3FF"]
        case .dark: ["#0C1015", "#FF6345", "#69B3FF"]
        case .amberCircuit: ["#17140D", "#FFBF33", "#D19E47"]
        case .cyberpunk: ["#081420", "#FA4D5C", "#4FE0F2"]
        }
        return hex.map(Color.init(crabrixHex:))
    }
}
