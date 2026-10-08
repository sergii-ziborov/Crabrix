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

    /// Device Hub can report the hinge state while omitting its division
    /// region. Keep the Duo layout available in that case.
    static func horizontal(
        in geometry: GeometryProxy,
        hingePartiallyOpen: Bool,
        hingeGlobalY: CGFloat
    ) -> CGRect? {
        if let region = horizontal(in: geometry) { return region }
        guard hingePartiallyOpen,
              geometry.size.height > geometry.size.width else { return nil }
        // The full app container owns the hinge coordinate. Nested readers
        // begin below the header, and UIScreen.main may describe one panel.
        let hingeY = hingeGlobalY - geometry.frame(in: .global).minY
        return CGRect(
            x: 0,
            y: hingeY,
            width: geometry.size.width,
            height: 12
        )
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

/// The editor dock is the first view that sees the fold. Share the global Y
/// coordinate of its tabletop tab row so drawers stop directly above it.
struct TabletopTabsGlobalYPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = nextValue() ?? value
    }
}
