import SwiftUI

/// Active reserved regions describe the usable space, including the Duo fold.
/// A nil region also covers older iOS versions and ordinary iPhone/iPad screens.
enum AdaptiveFold {
    static func vertical(in geometry: GeometryProxy) -> CGRect? {
        division(in: geometry) { $0.height > $0.width * 2 }
    }

    static func horizontal(in geometry: GeometryProxy) -> CGRect? {
        division(in: geometry) { $0.width > $0.height * 2 }
    }

    private static func division(
        in geometry: GeometryProxy,
        matching orientation: (CGRect) -> Bool
    ) -> CGRect? {
        #if CRABRIX_DUO_SDK
        if #available(iOS 27.1, *) {
            return geometry.reservedRegions(kind: .division)
                .map(\.frame)
                .first { $0.intersects(CGRect(origin: .zero, size: geometry.size))
                    && orientation($0) }
        }
        #endif
        return nil
    }
}

/// The editor dock is the first view that sees the fold. Share its global Y
/// coordinate so overlays outside the dock can stop at the same hinge.
struct TabletopFoldGlobalYPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = nextValue() ?? value
    }
}
