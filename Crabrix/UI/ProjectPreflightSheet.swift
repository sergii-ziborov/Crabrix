import SwiftUI

struct ProjectPreflightSheet: View {
    @ObservedObject var model: CompilerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var report: ProjectPreflight?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let report {
                        Label(report.target, systemImage: "cpu").font(.headline)
                        Text(report.entry).font(.callout.monospaced()).textSelection(.enabled)
                        Text(report.filesAccepted ? "Project file policy accepted. Editing files does not require a successful build." : "Project files need attention; see the reasons below.")
                            .foregroundStyle(CrabrixTheme.muted)
                        Text("Editable project: 2,048 files · 2 MiB per file · 16,000,000 UTF-8 bytes total. Shared rooms have a separate, smaller budget.")
                            .font(.caption).foregroundStyle(CrabrixTheme.muted)
                        if let edition = report.edition { Text("Rust edition \(edition)").font(.caption.monospaced()) }
                        Text(report.graphSummary).foregroundStyle(CrabrixTheme.muted)
                        if let features = report.features {
                            Text(features.isEmpty ? "Root features: none" : "Root features: " + features.joined(separator: ", "))
                                .font(.caption.monospaced()).textSelection(.enabled)
                        }
                        ForEach(report.operations) { operation in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(operation.title).font(.headline)
                                    Spacer(minLength: 8)
                                    Label(operation.state.rawValue.capitalized, systemImage: icon(operation.state))
                                        .font(.caption.weight(.semibold)).foregroundStyle(color(operation.state))
                                }
                                Text(operation.detail).font(.callout).foregroundStyle(CrabrixTheme.muted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                            .crabrixPanel(cornerRadius: 16)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("preflight-\(operation.kind.rawValue)")
                        }
                        ForEach(report.issues) { issue in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(issue.origin.rawValue).font(.caption.weight(.bold)).foregroundStyle(issue.blocked.isEmpty ? CrabrixTheme.blue : CrabrixTheme.amber)
                                Text(issue.detail).font(.callout).textSelection(.enabled)
                            }
                        }
                        if !report.dependencies.isEmpty {
                            Text("Exact prepared graph").font(.headline)
                            Text("Source availability below is recorded at graph preparation. The compiler revalidates files and archives before use.")
                                .font(.caption).foregroundStyle(CrabrixTheme.muted)
                            ForEach(report.dependencies) { dependency in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(dependency.package).font(.headline.monospaced())
                                    Text(dependency.status + (dependency.sourcePrepared ? " · source prepared" : " · source preparation needed"))
                                    Text("Features: " + (dependency.features.isEmpty ? "none" : dependency.features.joined(separator: ", ")))
                                    if let fingerprint = dependency.fingerprint { Text("Fingerprint: " + fingerprint) }
                                }.font(.caption.monospaced()).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(16).crabrixPanel(cornerRadius: 16)
                            }
                        }
                        Text("Snapshot \(report.revision.sourceTreeHash.prefix(12)) · read-only inspection. Unknown results stay unverified. No code was compiled or executed by this report.")
                            .font(.caption.monospaced()).foregroundStyle(CrabrixTheme.muted)
                    } else { ProgressView("Inspecting project…") }
                }
                .padding(20).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
            }
            .background(CrabrixTheme.background.ignoresSafeArea()).foregroundStyle(CrabrixTheme.primary)
            .navigationTitle("Project preflight").navigationBarTitleDisplayMode(.inline)
            .toolbar { CrabrixModalCloseAction(label: "Close project preflight") { dismiss() } }
            .task(id: model.preflightRefreshKey) {
                report = nil
                let input = model.preflightInput()
                let value = await Task.detached(priority: .userInitiated) { ProjectPreflight.inspect(input) }.value
                guard !Task.isCancelled, model.workspaceRevision == input.revision else { return }
                report = value
            }
        }
    }
    private func icon(_ state: ProjectPreflight.State) -> String {
        switch state { case .verified: "checkmark.seal"; case .blocked: "exclamationmark.triangle"; case .unverified: "questionmark.circle" }
    }
    private func color(_ state: ProjectPreflight.State) -> Color {
        switch state { case .verified: CrabrixTheme.mint; case .blocked: CrabrixTheme.amber; case .unverified: CrabrixTheme.muted }
    }
}

struct CargoFeaturePreviewSheet: View {
    @ObservedObject var model: CompilerViewModel
    let proposal: CargoFeatureProposal
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Review Cargo.toml").font(.title2.bold())
                    Text("This proposes the parser-only syn profile. It changes available crate features; review it against your code before applying.")
                        .foregroundStyle(CrabrixTheme.muted)
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(proposal.removed.enumerated()), id: \.offset) { _, line in
                            Text("− " + line).foregroundStyle(CrabrixTheme.coral)
                        }
                        ForEach(Array(proposal.inserted.enumerated()), id: \.offset) { _, line in
                            Text("+ " + line).foregroundStyle(CrabrixTheme.mint)
                        }
                    }.font(.callout.monospaced()).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(16).crabrixPanel()
                    Text("The complete original manifest will also be saved at:").foregroundStyle(CrabrixTheme.muted)
                    Text(proposal.backupPath).font(.caption.monospaced()).textSelection(.enabled)
                    Text("No packages are downloaded by Apply. Prepare the new graph afterward.").font(.caption).foregroundStyle(CrabrixTheme.muted)
                    if let message { Text(message).foregroundStyle(CrabrixTheme.amber) }
                    Button("Apply reviewed feature profile") {
                        if model.applyCargoFeatureProposal(proposal) { dismiss() }
                        else { message = model.projectTransfer.isFailure ? "Could not apply this preview. Check the project status and reopen the preview." : "Project changed; reopen the preview." }
                    }.buttonStyle(.borderedProminent).tint(CrabrixTheme.blue).foregroundStyle(CrabrixTheme.onAccent)
                        .disabled(model.isBusy || model.isProjectOperationInProgress || model.playgroundIsReadOnly)
                        .accessibilityIdentifier("cargo-feature-apply")
                }.padding(20).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
            }.background(CrabrixTheme.background.ignoresSafeArea()).foregroundStyle(CrabrixTheme.primary)
                .navigationTitle("Feature profile").navigationBarTitleDisplayMode(.inline)
                .toolbar { CrabrixModalCloseAction(label: "Close feature profile preview") { dismiss() } }
        }
    }
}
