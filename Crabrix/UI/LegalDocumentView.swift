import SwiftUI

struct BundledLegalDocument: Decodable, Identifiable, Sendable {
    struct Block: Decodable, Sendable {
        let kind: String
        let text: String
    }
    let id: String
    let title: String
    let updated: String
    let sourceURL: URL
    let blocks: [Block]
}

enum BundledLegalDocuments {
    static func load(bundle: Bundle = .main) throws -> [BundledLegalDocument] {
        guard let url = bundle.url(forResource: "LegalDocuments", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode([BundledLegalDocument].self, from: Data(contentsOf: url))
    }
}

/// A generated copy of the same legal documents published on crabrix.com.
/// All prose is bundled; opening it never requires a connection or account.
struct LegalDocumentView: View {
    let documentID: String
    @State private var document: BundledLegalDocument?
    @State private var failed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let document {
                    Text("BUNDLED COPY · UPDATED \(document.updated)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(CrabrixTheme.muted)
                    ForEach(Array(document.blocks.enumerated()), id: \.offset) { _, block in
                        blockView(block)
                    }
                    Divider().overlay(CrabrixTheme.border)
                    Link("Read the current website copy", destination: document.sourceURL)
                        .foregroundStyle(CrabrixTheme.blue)
                } else if failed {
                    Text("This document could not be read from the app bundle.")
                        .foregroundStyle(CrabrixTheme.muted)
                    Link("Open the legal pages", destination: CrabrixLinks.terms)
                } else {
                    ProgressView()
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: 760, alignment: .leading)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .background(CrabrixTheme.background.ignoresSafeArea())
        .foregroundStyle(CrabrixTheme.primary)
        .navigationTitle(document?.title ?? "About & legal")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard document == nil else { return }
            do {
                document = try BundledLegalDocuments.load().first { $0.id == documentID }
                failed = document == nil
            } catch {
                failed = true
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: BundledLegalDocument.Block) -> some View {
        let text = (try? AttributedString(markdown: block.text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(block.text)
        switch block.kind {
        case "h2", "h3":
            Text(text)
                .font(block.kind == "h2" ? .title3.bold() : .headline)
                .padding(.top, 12)
        case "li":
            HStack(alignment: .top, spacing: 10) {
                Text("•").foregroundStyle(CrabrixTheme.mint)
                Text(text).frame(maxWidth: .infinity, alignment: .leading)
            }
        case "pre":
            Text(block.text)
                .font(.system(size: 13, design: .monospaced))
                .fixedSize(horizontal: false, vertical: true)
        default:
            Text(text)
                .foregroundStyle(CrabrixTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
