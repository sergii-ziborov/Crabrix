import SwiftUI

struct CargoDependencyCatalogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = CrateCatalogViewModel()

    let onAdd: (String, String) -> Bool

    var body: some View {
        NavigationStack {
            Group {
                if let error = model.errorMessage, model.results.isEmpty {
                    ContentUnavailableView {
                        Label("Could not load crates.io", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try Again") { model.retry() }
                            .buttonStyle(.borderedProminent)
                    }
                } else if model.results.isEmpty, !model.isLoading {
                    ContentUnavailableView.search(text: model.query)
                } else {
                    catalog
                }
            }
            .background(CrabrixTheme.background.ignoresSafeArea())
            .foregroundStyle(CrabrixTheme.primary)
            .navigationTitle("Cargo packages")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $model.query, prompt: "Search crates.io")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) { sortMenu }
            }
            .navigationDestination(for: CrateSearchResult.self) { crate in
                CratePackageView(crate: crate) { version in
                    guard onAdd(crate.name, version) else { return false }
                    dismiss()
                    return true
                }
            }
        }
        .task { await model.start() }
        .onChange(of: model.query) { _, _ in model.scheduleSearch() }
        .onChange(of: model.sort) { _, _ in model.scheduleSearch() }
    }

    private var catalog: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                HStack(spacing: 8) {
                    Label(
                        model.query.isEmpty ? "Explore crates" : "Search results",
                        systemImage: "shippingbox.fill"
                    )
                    .font(.headline)
                    .foregroundStyle(CrabrixTheme.amber)
                    Spacer()
                    if model.isLoading {
                        ProgressView().tint(CrabrixTheme.coral)
                    }
                    Text("\(model.total.formatted()) packages")
                        .font(.caption.monospaced())
                        .foregroundStyle(CrabrixTheme.muted)
                }
                .padding(.bottom, 4)

                ForEach(model.results) { crate in
                    NavigationLink(value: crate) {
                        CrateSearchCard(crate: crate)
                    }
                    .buttonStyle(.plain)
                }

                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(CrabrixTheme.amber)
                        .padding(.vertical, 12)
                }
            }
            .padding(18)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            Label(
                "Package discovery uses crates.io. Compiler runs remain local and offline.",
                systemImage: "network"
            )
            .font(.caption2)
            .foregroundStyle(CrabrixTheme.muted)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(.regularMaterial)
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $model.sort) {
                ForEach(CratesIOSort.allCases) { sort in
                    Label(sort.title, systemImage: sort.systemImage).tag(sort)
                }
            }
        } label: {
            Label(model.sort.title, systemImage: "arrow.up.arrow.down.circle")
        }
    }
}

private struct CrateSearchCard: View {
    let crate: CrateSearchResult

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "shippingbox.fill")
                .font(.title3)
                .foregroundStyle(CrabrixTheme.amber)
                .frame(width: 42, height: 42)
                .background(CrabrixTheme.amber.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(crate.name)
                        .font(.headline.monospaced())
                        .foregroundStyle(CrabrixTheme.primary)
                    Text(crate.maxVersion)
                        .font(.caption.monospaced().bold())
                        .foregroundStyle(CrabrixTheme.blue)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(CrabrixTheme.muted)
                }

                Text(crate.description ?? "No package description")
                    .font(.subheadline)
                    .foregroundStyle(CrabrixTheme.muted)
                    .lineLimit(2)

                HStack(spacing: 15) {
                    Label(
                        CrateCountFormatter.compact(crate.downloads),
                        systemImage: "arrow.down.circle.fill"
                    )
                    .accessibilityLabel("\(CrateCountFormatter.exact(crate.downloads)) total downloads")
                    if let recent = crate.recentDownloads {
                        Label(
                            "\(CrateCountFormatter.compact(recent)) recent",
                            systemImage: "chart.line.uptrend.xyaxis"
                        )
                        .accessibilityLabel("\(CrateCountFormatter.exact(recent)) recent downloads")
                    }
                    CrateOwnersLabel(crateName: crate.name)
                }
                .font(.caption2.monospaced())
                .foregroundStyle(CrabrixTheme.muted)
            }
        }
        .padding(14)
        .crabrixPanel(cornerRadius: 14)
    }
}

private struct CrateOwnersLabel: View {
    let crateName: String
    @State private var owners: [CrateOwner] = []

    var body: some View {
        Group {
            if owners.isEmpty {
                Label("Owners…", systemImage: "person.2")
                    .redacted(reason: .placeholder)
            } else {
                Label(
                    owners.prefix(2).map(\.displayName).joined(separator: ", "),
                    systemImage: "person.2.fill"
                )
                .lineLimit(1)
            }
        }
        .task(id: crateName) {
            owners = (try? await CratesIOClient.shared.owners(for: crateName)) ?? []
        }
    }
}

private struct CratePackageView: View {
    @StateObject private var model: CratePackageViewModel
    @State private var validationMessage: String?
    let onAdd: (String) -> Bool

    init(crate: CrateSearchResult, onAdd: @escaping (String) -> Bool) {
        _model = StateObject(wrappedValue: CratePackageViewModel(crate: crate))
        self.onAdd = onAdd
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                packageHeader
                ownersSection
                versionsSection
            }
            .padding(20)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(CrabrixTheme.background.ignoresSafeArea())
        .foregroundStyle(CrabrixTheme.primary)
        .navigationTitle(model.crate.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { addBar }
        .task { await model.load() }
    }

    private var packageHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "shippingbox.fill")
                    .font(.title)
                    .foregroundStyle(CrabrixTheme.amber)
                    .frame(width: 54, height: 54)
                    .background(CrabrixTheme.amber.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.crate.name).font(.title2.monospaced().bold())
                    Text(model.crate.description ?? "No package description")
                        .font(.subheadline)
                        .foregroundStyle(CrabrixTheme.muted)
                }
            }

            HStack(spacing: 18) {
                packageMetric(
                    CrateCountFormatter.compact(model.crate.downloads),
                    label: "total downloads",
                    icon: "arrow.down.circle.fill"
                )
                if let recent = model.crate.recentDownloads {
                    packageMetric(
                        CrateCountFormatter.compact(recent),
                        label: "recent",
                        icon: "chart.line.uptrend.xyaxis"
                    )
                }
                Spacer()
                if let raw = model.crate.repository, let url = URL(string: raw) {
                    Link(destination: url) {
                        Label("Repository", systemImage: "arrow.up.right.square")
                    }
                    .font(.caption.bold())
                }
            }
        }
        .padding(16)
        .crabrixPanel(cornerRadius: 16)
    }

    private func packageMetric(_ value: String, label: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(value, systemImage: icon).font(.headline.monospaced())
            Text(label).font(.caption2).foregroundStyle(CrabrixTheme.muted)
        }
    }

    @ViewBuilder
    private var ownersSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Owners", systemImage: "person.2.fill").font(.headline)
            if model.isLoading, model.owners.isEmpty {
                ProgressView().tint(CrabrixTheme.coral)
            } else if model.owners.isEmpty {
                Text("Owner information is unavailable.")
                    .font(.caption)
                    .foregroundStyle(CrabrixTheme.muted)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.owners) { owner in
                            Label(owner.displayName, systemImage: "person.crop.circle.fill")
                                .font(.caption.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(CrabrixTheme.raised, in: Capsule())
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var versionsSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("Choose a version", systemImage: "list.bullet.rectangle")
                    .font(.headline)
                Spacer()
                Text("\(model.versions.filter { !$0.yanked }.count) available")
                    .font(.caption.monospaced())
                    .foregroundStyle(CrabrixTheme.muted)
            }

            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(CrabrixTheme.amber)
            } else if model.isLoading {
                ProgressView("Loading versions…").tint(CrabrixTheme.coral)
            } else {
                LazyVStack(spacing: 7) {
                    ForEach(model.versions) { version in
                        Button {
                            guard !version.yanked else { return }
                            model.selectedVersion = version.num
                        } label: {
                            versionRow(version)
                        }
                        .buttonStyle(.plain)
                        .disabled(version.yanked)
                    }
                }
            }
        }
    }

    private func versionRow(_ version: CrateVersion) -> some View {
        HStack(spacing: 11) {
            Image(systemName: model.selectedVersion == version.num
                  ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(model.selectedVersion == version.num
                                 ? CrabrixTheme.mint : CrabrixTheme.muted)
            Text(version.num)
                .font(.subheadline.monospaced().bold())
            if version.yanked {
                Text("YANKED")
                    .font(.caption2.monospaced().bold())
                    .foregroundStyle(CrabrixTheme.coral)
            }
            Spacer()
            if let rust = version.rustVersion {
                Label("Rust \(rust)", systemImage: "hammer.fill")
            }
            Label(
                CrateCountFormatter.compact(version.downloads),
                systemImage: "arrow.down.circle"
            )
        }
        .font(.caption)
        .foregroundStyle(version.yanked ? CrabrixTheme.muted : CrabrixTheme.primary)
        .padding(.horizontal, 13)
        .frame(minHeight: 46)
        .background(
            model.selectedVersion == version.num
                ? CrabrixTheme.mint.opacity(0.08) : CrabrixTheme.panel,
            in: RoundedRectangle(cornerRadius: 11)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .stroke(
                    model.selectedVersion == version.num
                        ? CrabrixTheme.mint.opacity(0.5) : CrabrixTheme.border
                )
        }
    }

    private var addBar: some View {
        VStack(spacing: 6) {
            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(CrabrixTheme.amber)
            }
            Button {
                guard let version = model.selectedVersion else { return }
                if !onAdd(version) {
                    validationMessage = "Could not update the active Cargo.toml."
                }
            } label: {
                Label(
                    model.selectedVersion.map { "Add \(model.crate.name) \($0)" }
                        ?? "Choose a version",
                    systemImage: "plus.circle.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(CrabrixTheme.blue)
            .disabled(model.selectedVersion == nil || model.isLoading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }
}
