import SwiftUI
import ZIPFoundation

struct ToolchainNotice: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let summary: String
    let archive: String
    let documents: [String]
}

enum ToolchainNoticeCatalog {
    static func load() throws -> [ToolchainNotice] {
        try ["ToolchainPrimaryIndex", "ToolchainVendorIndex", "RustfmtNoticeIndex", "GitCoreNoticeIndex"].flatMap { name in
            guard let url = Bundle.main.url(forResource: name, withExtension: "json")
                    ?? Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "RustTools")
                    ?? Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "GitCore") else {
                throw CocoaError(.fileNoSuchFile)
            }
            return try JSONDecoder().decode([ToolchainNotice].self, from: Data(contentsOf: url))
        }
    }

    static func text(archive name: String, path: String) throws -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "zip")
                ?? Bundle.main.url(forResource: name, withExtension: "zip", subdirectory: "RustTools")
                ?? Bundle.main.url(forResource: name, withExtension: "zip", subdirectory: "GitCore") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let archive = try Archive(url: url, accessMode: .read)
        guard let entry = archive[path], entry.type == .file, entry.uncompressedSize <= 4 * 1024 * 1024 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var data = Data()
        let checksum = try archive.extract(entry) { data.append($0) }
        guard checksum == entry.checksum, let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return text
    }
}

struct ToolchainNoticesView: View {
    @State private var notices: [ToolchainNotice] = []
    @State private var search = ""
    @State private var failed = false

    private var matching: [ToolchainNotice] {
        search.isEmpty ? notices : notices.filter {
            $0.name.localizedCaseInsensitiveContains(search) || $0.summary.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                Text("Original compiler/sysroot, rustfmt and native Git dependency notices. All files are bundled for offline reading; inventories also include source-only and build-time dependencies. The formatter archive includes unmodified MPL option-ext sources; the Git archive contains the complete configured source package.")
                    .font(.subheadline)
                    .foregroundStyle(CrabrixTheme.muted)
                    .padding(.bottom, 8)
                if let archive = Bundle.main.url(forResource: "RustfmtVendorNotices", withExtension: "zip", subdirectory: "RustTools") {
                    ShareLink("Export formatter notices and MPL source", item: archive)
                        .font(.subheadline)
                        .padding(.bottom, 8)
                }
                if let archive = Bundle.main.url(forResource: "CrabrixGitCoreSource", withExtension: "zip", subdirectory: "GitCore") {
                    ShareLink("Export native Git source and notices", item: archive)
                        .font(.subheadline)
                        .padding(.bottom, 8)
                }
                if failed {
                    Text("The bundled toolchain notice index could not be read.")
                }
                ForEach(matching) { notice in
                    NavigationLink { ToolchainNoticeDocumentView(notice: notice) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(notice.name).font(.subheadline.weight(.semibold))
                            Text(notice.summary).font(.caption).foregroundStyle(CrabrixTheme.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .crabrixPanel(cornerRadius: 12)
                    }
                    .buttonStyle(.plain)
                }
                if !failed && !search.isEmpty && matching.isEmpty {
                    Text("No matching components.").foregroundStyle(CrabrixTheme.muted)
                }
            }
            .frame(maxWidth: 760)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .background(CrabrixTheme.background.ignoresSafeArea())
        .foregroundStyle(CrabrixTheme.primary)
        .navigationTitle("Compiler dependency notices")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Component or license")
        .task {
            do { notices = try ToolchainNoticeCatalog.load() }
            catch { failed = true }
        }
    }
}

private struct ToolchainNoticeDocumentView: View {
    let notice: ToolchainNotice
    @State private var texts: [String: String] = [:]
    @State private var failed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(notice.summary).foregroundStyle(CrabrixTheme.muted)
                if failed { Text("A bundled notice file could not be read.") }
                ForEach(notice.documents, id: \.self) { path in
                    if let text = texts[path] {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(path).font(.caption.bold()).foregroundStyle(CrabrixTheme.muted)
                            Text(text).font(.system(size: 12, design: .monospaced))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: 760, alignment: .leading)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .background(CrabrixTheme.background.ignoresSafeArea())
        .foregroundStyle(CrabrixTheme.primary)
        .navigationTitle(notice.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                var loaded: [String: String] = [:]
                for path in notice.documents {
                    loaded[path] = try ToolchainNoticeCatalog.text(archive: notice.archive, path: path)
                }
                texts = loaded
            } catch { failed = true }
        }
    }
}
