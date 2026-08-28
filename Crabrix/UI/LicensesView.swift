import SwiftUI

/// The open-source notices, read from the copy bundled with the app.
///
/// Shipped in the bundle rather than fetched, so the attributions are readable
/// with no network — which is the only version of "included with the app" that
/// actually holds for a compiler that works offline.
struct LicensesView: View {
    @State private var notices: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let notices {
                    Text(notices)
                        .font(.system(size: 13, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("The notices file could not be read from the app bundle.")
                        .foregroundStyle(CrabrixTheme.muted)
                }
            }
            .padding(20)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(CrabrixTheme.background.ignoresSafeArea())
        .foregroundStyle(CrabrixTheme.primary)
        .navigationTitle("Open-source licenses")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard notices == nil else { return }
            notices = Self.load()
        }
    }

    static func load() -> String? {
        guard let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        return text
    }
}
