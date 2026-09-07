import SwiftUI
import UIKit

/// What part of Crabrix went wrong, which is most of what triage needs.
enum ProblemArea: String, CaseIterable, Identifiable, Sendable {
    case building = "Building or running code"
    case editor = "The editor"
    case packages = "Packages and crates.io"
    case learning = "Lessons and courses"
    case projects = "Projects, import, or export"
    case somethingElse = "Something else"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .building: "hammer.fill"
        case .editor: "chevron.left.forwardslash.chevron.right"
        case .packages: "shippingbox.fill"
        case .learning: "graduationcap.fill"
        case .projects: "folder.fill"
        case .somethingElse: "questionmark.circle.fill"
        }
    }

    /// The one thing worth asking for in this area beyond "what happened".
    var hint: String {
        switch self {
        case .building: "Which project, and what the compiler printed."
        case .editor: "What you were typing, and what the editor did instead."
        case .packages: "The crate and version you asked for."
        case .learning: "The lesson or course, and the step number."
        case .projects: "Where the project came from — new, GitHub, or Files."
        case .somethingElse: "Whatever you were doing when it went wrong."
        }
    }
}

/// The facts about this install that a bug report is useless without.
///
/// Deliberately not in here: the device's name, which is often a person's
/// name; anything identifying the install; and a single character of anyone's
/// code. What is here is what tells a crash on an old iPhone apart from a
/// crash everywhere.
struct ProblemReportEnvironment: Equatable, Sendable {
    let appVersion: String
    let appBuild: String
    let systemVersion: String
    let deviceModel: String
    let rustcVersion: String
    let toolchainArtifact: String
    let target: String
    let toolchainIsReady: Bool

    static func current(toolchainIsReady: Bool) -> ProblemReportEnvironment {
        ProblemReportEnvironment(
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—",
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—",
            systemVersion: UIDevice.current.systemVersion,
            deviceModel: Self.modelIdentifier,
            rustcVersion: CargoToolchain.semanticVersionLabel,
            toolchainArtifact: CargoToolchain.bundledVersion,
            target: RustTargetSpec.wasm32WasiP1.triple,
            toolchainIsReady: toolchainIsReady
        )
    }

    /// `iPhone14,4` rather than the marketing name: it says exactly which
    /// hardware, and it says nothing about who owns it.
    static var modelIdentifier: String {
        var info = utsname()
        uname(&info)
        let machine = info.machine
        let identifier = withUnsafePointer(to: machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: machine)) {
                String(validatingCString: $0) ?? ""
            }
        }
        return identifier.isEmpty ? "unknown" : identifier
    }

    var lines: [String] {
        [
            "Crabrix \(appVersion) (build \(appBuild))",
            "iOS \(systemVersion) on \(deviceModel)",
            "rustc \(rustcVersion), target \(target)",
            "Toolchain \(toolchainArtifact), \(toolchainIsReady ? "installed" : "missing")",
        ]
    }
}

/// A bug report, as text, before anything is sent anywhere.
///
/// The report is composed here and handed to Mail or the pasteboard. Crabrix
/// has no reporting endpoint and opens no connection of its own: nothing
/// leaves the device unless the reader presses send in their own mail app.
struct ProblemReport: Equatable {
    var area: ProblemArea = .building
    var whatHappened = ""
    var whatIExpected = ""
    var includesEnvironment = true

    /// A report with nothing written in it is not a report.
    var isReady: Bool {
        !whatHappened.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var subject: String {
        "Crabrix — \(area.rawValue)"
    }

    func body(_ environment: ProblemReportEnvironment) -> String {
        var sections: [String] = [
            "What happened\n\(whatHappened.trimmingCharacters(in: .whitespacesAndNewlines))"
        ]

        let expected = whatIExpected.trimmingCharacters(in: .whitespacesAndNewlines)
        if !expected.isEmpty {
            sections.append("What I expected\n\(expected)")
        }

        if includesEnvironment {
            sections.append("App and device\n" + environment.lines.joined(separator: "\n"))
        }

        return sections.joined(separator: "\n\n") + "\n"
    }

    /// The whole report as one mail draft, opened in the reader's mail app so
    /// they see every word before it goes anywhere.
    func mailURL(_ environment: ProblemReportEnvironment, to address: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body(environment)),
        ]
        // Mail treats a raw + in a query as a space; the report has none today,
        // and this keeps a pasted `a + b` from arriving as `a   b`.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }
}

/// Reporting a problem, without an account and without a network call.
struct ProblemReportView: View {
    let toolchainIsReady: Bool

    @State private var report = ProblemReport()
    @State private var environment = ProblemReportEnvironment.current(toolchainIsReady: true)
    @State private var isShowingDetails = false
    @State private var copied = false
    @State private var addressCopied = false
    @State private var mailUnavailable = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                areaPicker
                descriptionFields
                environmentCard
                actions
                reachUs
            }
            .padding(22)
            .frame(maxWidth: 850)
            .frame(maxWidth: .infinity)
        }
        .background(CrabrixTheme.background.ignoresSafeArea())
        .foregroundStyle(CrabrixTheme.primary)
        .navigationTitle("Report a problem")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            environment = .current(toolchainIsReady: toolchainIsReady)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "ladybug.fill")
                .font(.title2)
                .foregroundStyle(CrabrixTheme.coral)
                .frame(width: 48, height: 48)
                .background(CrabrixTheme.coral.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 3) {
                Text("Something not working?")
                    .font(.title3.bold())
                    .fixedSize(horizontal: false, vertical: true)
                Text("Write it down here and it opens as a mail draft you can read before sending.")
                    .font(.caption)
                    .foregroundStyle(CrabrixTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var areaPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHERE IT WENT WRONG")
                .font(.caption2.monospaced().bold())
                .foregroundStyle(CrabrixTheme.muted)

            ForEach(ProblemArea.allCases) { area in
                Button {
                    report.area = area
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: area.icon)
                            .foregroundStyle(report.area == area ? CrabrixTheme.coral : CrabrixTheme.muted)
                            .frame(width: 24)
                        Text(area.rawValue)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: report.area == area ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(report.area == area ? CrabrixTheme.coral : CrabrixTheme.border)
                    }
                    .padding(.vertical, 9)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 11)
                            .fill(report.area == area ? CrabrixTheme.coral.opacity(0.12) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(report.area == area ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(18)
        .crabrixPanel(cornerRadius: 16)
    }

    private var descriptionFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("What happened")
                    .font(.subheadline.bold())
                Text(report.area.hint)
                    .font(.caption2)
                    .foregroundStyle(CrabrixTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("", text: $report.whatHappened, axis: .vertical)
                    .lineLimit(4...10)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(CrabrixTheme.editor, in: RoundedRectangle(cornerRadius: 11))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11).stroke(CrabrixTheme.border, lineWidth: 1)
                    )
                    .accessibilityLabel("What happened")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("What you expected")
                    .font(.subheadline.bold())
                Text("Optional, but it is often the whole bug.")
                    .font(.caption2)
                    .foregroundStyle(CrabrixTheme.muted)
                TextField("", text: $report.whatIExpected, axis: .vertical)
                    .lineLimit(2...6)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(CrabrixTheme.editor, in: RoundedRectangle(cornerRadius: 11))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11).stroke(CrabrixTheme.border, lineWidth: 1)
                    )
                    .accessibilityLabel("What you expected")
            }
        }
        .padding(18)
        .crabrixPanel(cornerRadius: 16)
    }

    private var environmentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $report.includesEnvironment) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Include app and device details", systemImage: "info.circle.fill")
                        .font(.subheadline)
                    Text("Version, iOS, model, and which toolchain is installed. No project, no code, no name.")
                        .font(.caption2)
                        .foregroundStyle(CrabrixTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(CrabrixTheme.mint)

            if report.includesEnvironment {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { isShowingDetails.toggle() }
                } label: {
                    Label(
                        isShowingDetails ? "Hide what will be attached" : "Show what will be attached",
                        systemImage: isShowingDetails ? "eye.slash" : "eye"
                    )
                    .font(.caption.bold())
                    .foregroundStyle(CrabrixTheme.blue)
                }
                .buttonStyle(.plain)

                if isShowingDetails {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(environment.lines, id: \.self) { line in
                            Text(line)
                                .font(.caption2.monospaced())
                                .foregroundStyle(CrabrixTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(CrabrixTheme.editor, in: RoundedRectangle(cornerRadius: 11))
                }
            }
        }
        .padding(18)
        .crabrixPanel(cornerRadius: 16)
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                sendByMail()
            } label: {
                Label("Write the email", systemImage: "envelope.fill")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.borderedProminent)
            .tint(CrabrixTheme.coral)
            .disabled(!report.isReady)

            Button {
                UIPasteboard.general.string = report.body(environment)
                withAnimation { copied = true }
            } label: {
                Label(copied ? "Copied" : "Copy the report", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.bordered)
            .disabled(!report.isReady)

            if mailUnavailable {
                Text("No mail app answered. The report is on the clipboard instead, and the button below puts the support address there too, so you can send it from anywhere.")
                    .font(.caption2)
                    .foregroundStyle(CrabrixTheme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Nothing is sent by Crabrix itself. The draft opens in your mail app, and it goes only when you send it.")
                .font(.caption2)
                .foregroundStyle(CrabrixTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .crabrixPanel(cornerRadius: 16)
    }

    private var reachUs: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Other ways to reach a human")
                .font(.subheadline.bold())
            Link(destination: CrabrixLinks.support) {
                Label("Support page — known issues and release notes", systemImage: "lifepreserver.fill")
                    .font(.caption)
                    .foregroundStyle(CrabrixTheme.blue)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // The address is behind a button rather than printed here. It is
            // one person's inbox, and a screen full of plain-text addresses is
            // what scrapers and screenshots carry away.
            Button {
                UIPasteboard.general.string = CrabrixLinks.supportEmail
                withAnimation { addressCopied = true }
            } label: {
                Label(
                    addressCopied ? "Support address copied" : "Copy the support address",
                    systemImage: addressCopied ? "checkmark" : "envelope"
                )
                .font(.caption)
                .foregroundStyle(addressCopied ? CrabrixTheme.mint : CrabrixTheme.blue)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Copies the email address that support reports are sent to")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .crabrixPanel(cornerRadius: 16)
    }

    private func sendByMail() {
        guard let url = report.mailURL(environment, to: CrabrixLinks.supportEmail) else { return }
        openURL(url) { accepted in
            guard !accepted else { return }
            // A device with no mail account set up still deserves a way out.
            UIPasteboard.general.string = report.body(environment)
            withAnimation { mailUnavailable = true }
        }
    }
}
