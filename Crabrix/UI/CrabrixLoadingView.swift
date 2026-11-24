import SwiftUI

/// The app's one loading look: a spinner beside its label.
///
/// `ProgressView("…")` stacks the spinner above the label and takes its
/// parent's alignment, so in the app's leading-aligned stacks it sat off to the
/// left with the spinner floating over the middle of the text. This keeps the
/// two on one line and places them deliberately:
/// - `.row` sits at the leading edge of a list or card, where content follows.
/// - `.centered` takes the full width (and, where the parent offers it, the
///   full height) and centres itself, for a screen or section that is waiting.
struct CrabrixLoadingView: View {
    enum Placement { case row, centered }

    let title: String
    var placement: Placement = .row
    var tint: Color = CrabrixTheme.coral

    init(_ title: String, placement: Placement = .row, tint: Color = CrabrixTheme.coral) {
        self.title = title
        self.placement = placement
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(tint)
            Text(title)
                .font(placement == .centered ? .callout : .subheadline)
                .foregroundStyle(CrabrixTheme.muted)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .frame(maxWidth: .infinity,
               minHeight: placement == .centered ? 160 : nil,
               maxHeight: placement == .centered ? .infinity : nil,
               alignment: placement == .centered ? .center : .leading)
    }
}
