import SwiftUI

/// One redistributed component and the exact files that license it.
struct BundledLicense: Identifiable, Sendable {
    let id: String
    let name: String
    let summary: String
    /// Bundle resource names, without the `.txt` extension, in reading order.
    let documents: [String]

    var documentTitles: [String] {
        documents.map { $0.replacingOccurrences(of: "\(id)-", with: "") }
    }
}

enum BundledLicenseCatalog {
    /// Everything Crabrix redistributes, with the full text of each licence
    /// shipped in the app rather than linked. A compiler that works offline has
    /// to be able to show its notices offline too.
    static let all: [BundledLicense] = [
        BundledLicense(
            id: "Rust",
            name: "Rust compiler and standard library",
            summary: "The Rust Project Contributors · Apache-2.0 or MIT, at your option",
            documents: ["Rust-COPYRIGHT", "Rust-LICENSE-MIT", "Rust-LICENSE-APACHE"]
        ),
        BundledLicense(
            id: "wasm-rustc",
            name: "wasm-rustc (artifacts-test-7)",
            summary: "Forest Anderson · MIT",
            documents: ["wasm-rustc-LICENSE"]
        ),
        BundledLicense(
            id: "WasmKit",
            name: "WasmKit 0.3.1",
            summary: "Akio Yasui · MIT, with Apache-2.0 attributions in its notice",
            documents: ["WasmKit-LICENSE", "WasmKit-NOTICE"]
        ),
        BundledLicense(
            id: "ZIPFoundation",
            name: "ZIPFoundation 0.9.20",
            summary: "Thomas Zoechling · MIT",
            documents: ["ZIPFoundation-LICENSE"]
        ),
        BundledLicense(
            id: "swift-system",
            name: "Swift System 1.8.1",
            summary: "Apple · Apache-2.0 with Runtime Library Exception",
            documents: ["swift-system-LICENSE"]
        ),
        BundledLicense(
            id: "swift-collections",
            name: "Swift Collections 1.6.0",
            summary: "Apple · Apache-2.0 with Runtime Library Exception",
            documents: ["swift-collections-LICENSE"]
        ),
        BundledLicense(
            id: "swift-atomics",
            name: "Swift Atomics 1.3.1",
            summary: "Apple · Apache-2.0 with Runtime Library Exception",
            documents: ["swift-atomics-LICENSE"]
        ),
        BundledLicense(
            id: "swift-argument-parser",
            name: "Swift Argument Parser 1.8.2",
            summary: "Apple · Apache-2.0 with Runtime Library Exception",
            documents: ["swift-argument-parser-LICENSE"]
        ),
        BundledLicense(
            id: "swift-log",
            name: "SwiftLog 1.15.0",
            summary: "Apple · Apache-2.0",
            documents: ["swift-log-LICENSE", "swift-log-NOTICE"]
        ),
        BundledLicense(
            id: "swift-nio",
            name: "SwiftNIO 2.101.3",
            summary: "Apple · Apache-2.0",
            documents: ["swift-nio-LICENSE", "swift-nio-NOTICE"]
        ),
    ]

    static func text(forDocument name: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        return text
    }

    /// Documents that are declared but missing from the bundle. Empty is the
    /// only acceptable answer in a shipped build.
    static var missingDocuments: [String] {
        all.flatMap(\.documents).filter { text(forDocument: $0) == nil }
    }
}

/// The open-source notices, read from the copies bundled with the app.
///
/// Shipped in the bundle rather than fetched, so the attributions and the full
/// licence texts are readable with no network — which is the only version of
/// "included with the app" that actually holds for a compiler that works
/// offline.
struct LicensesView: View {
    @State private var notices: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("FULL LICENCE TEXTS")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(CrabrixTheme.muted)

                VStack(spacing: 8) {
                    ForEach(BundledLicenseCatalog.all) { license in
                        NavigationLink {
                            LicenseDocumentView(license: license)
                        } label: {
                            LicenseRow(license: license)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider().overlay(CrabrixTheme.border)

                Text("NOTICES")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(CrabrixTheme.muted)

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

private struct LicenseRow: View {
    let license: BundledLicense

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(license.name)
                    .font(.subheadline.weight(.semibold))
                Text(license.summary)
                    .font(.caption)
                    .foregroundStyle(CrabrixTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(CrabrixTheme.muted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .crabrixPanel(cornerRadius: 12)
    }
}

/// The verbatim licence and notice files for one component.
private struct LicenseDocumentView: View {
    let license: BundledLicense

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(Array(license.documents.enumerated()), id: \.element) { index, document in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(license.documentTitles[index].uppercased())
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(CrabrixTheme.muted)
                        Text(
                            BundledLicenseCatalog.text(forDocument: document)
                                ?? "This file is missing from the app bundle."
                        )
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(CrabrixTheme.background.ignoresSafeArea())
        .foregroundStyle(CrabrixTheme.primary)
        .navigationTitle(license.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
