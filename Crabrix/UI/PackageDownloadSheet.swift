import SwiftUI

struct PackageDownloadSheet: View {
    @ObservedObject var model: CompilerViewModel
    @Environment(\.dismiss) private var dismiss

    private var completed: Int {
        model.packageTransfers.filter { $0.state == .ready || $0.state == .cached }.count
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        if model.cargoStage.isWorking { ProgressView() }
                        Text(model.cargoStage.label).font(.callout)
                    }
                    if !model.packageTransfers.isEmpty {
                        ProgressView(value: Double(completed), total: Double(model.packageTransfers.count))
                        Text("\(completed) of \(model.packageTransfers.count) packages available")
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Close this window to keep working. Downloads continue in the background; verified packages are kept for offline builds.")
                }
                Section("Packages and dependencies") {
                    ForEach(model.packageTransfers) { row in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(alignment: .top, spacing: 10) {
                                statusIcon(row.state)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(row.package.description).font(.callout.monospaced().weight(.semibold))
                                    Text(statusLabel(row.state)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            if !row.dependencies.isEmpty {
                                DisclosureGroup("Depends on \(row.dependencies.count) packages") {
                                    ForEach(row.dependencies, id: \.self) { dependency in
                                        Text(dependency.description).font(.caption.monospaced())
                                    }
                                }
                                .font(.caption)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Preparing packages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
    }

    @ViewBuilder private func statusIcon(_ state: PackageTransferRow.State) -> some View {
        switch state {
        case .downloading, .verifying: ProgressView().controlSize(.small)
        case .ready, .cached: Image(systemName: "checkmark.circle.fill").foregroundStyle(CrabrixTheme.mint)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(CrabrixTheme.coral)
        case .waiting: Image(systemName: "circle.dotted").foregroundStyle(.secondary)
        }
    }

    private func statusLabel(_ state: PackageTransferRow.State) -> String {
        switch state {
        case .waiting: "Waiting"
        case .downloading: "Acquiring source archive"
        case .verifying: "Checksum verified · unpacking source"
        case .ready: "Source ready"
        case .cached: "Already available locally"
        case let .failed(reason): reason
        }
    }
}
