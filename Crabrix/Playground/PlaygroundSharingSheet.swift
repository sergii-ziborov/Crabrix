import SwiftUI
import UniformTypeIdentifiers

struct PlaygroundSharingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: CompilerViewModel
    @State private var lifetime = 3600
    @State private var creating = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label("Code together, run locally", systemImage: "person.2.wave.2.fill")
                        .font(.title2.bold())
                    Text("Share source through an encrypted temporary link. Guests open it in Crabrix or in the browser without an account. Run and Check execute on each participant’s device.")
                        .foregroundStyle(CrabrixTheme.muted)
                    if let session = model.playgroundSession {
                        PlaygroundSessionDetails(session: session, onLeave: model.leavePlayground)
                        Divider()
                        NavigationLink { PlaygroundAgentView(session: session, model: model) } label: {
                            Label("Connect AI agent", systemImage: "sparkles").frame(maxWidth: .infinity)
                        }.buttonStyle(.bordered).disabled(session.expired)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Link lifetime").font(.subheadline.weight(.semibold))
                            Picker("Link lifetime", selection: $lifetime) {
                                Text("1 hour").tag(3600); Text("4 hours").tag(14400)
                                Text("12 hours").tag(43200); Text("24 hours").tag(86400)
                            }.pickerStyle(.segmented)
                            Text("The timer starts when you create the link.")
                                .font(.caption).foregroundStyle(CrabrixTheme.muted)
                        }
                        Text("Source only: up to 16 files, 64 KiB per file and 128 KiB total. Packages, generated files and images are excluded. The server holds encrypted data in memory; a restart can end a room early.")
                            .font(.caption).foregroundStyle(CrabrixTheme.muted)
                        Button {
                            creating = true; failure = nil
                            Task {
                                do { try await model.createPlayground(lifetimeSeconds: lifetime) }
                                catch { failure = error.localizedDescription }
                                creating = false
                            }
                        } label: {
                            Label(creating ? "Encrypting source…" : "Create Playground link", systemImage: "link")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(CrabrixTheme.blue).disabled(creating)
                    }
                    if let failure { Text(failure).foregroundStyle(CrabrixTheme.coral) }
                    Text("Anyone holding the interview link can edit. Share the view-only link to let someone read and run without changing the room. Opening a link does not extend its lifetime. A saved copy on your device remains available after expiry.")
                        .font(.caption).foregroundStyle(CrabrixTheme.muted)
                }
                .padding(22).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }
            .background(CrabrixTheme.background).foregroundStyle(CrabrixTheme.primary)
            .navigationTitle("Share Playground").navigationBarTitleDisplayMode(.inline)
            .toolbar { CrabrixModalCloseAction(label: "Close Playground sharing", isDisabled: creating) { dismiss() } }
        }
    }
}
/// AI agents only: a local agent link to this room and the on-device execution permission.
/// The key sits after # in the link, so only Crabrix MCP on the agent's computer can use it.
private struct PlaygroundAgentView: View {
    /// How to add Crabrix MCP once, for the agents that run it on the user's computer.
    static let agentSetups = [
        ("Claude Code", "/plugin marketplace add sergii-ziborov/crabrix-sdk\n/plugin install crabrix@crabrix"),
        ("Codex", "codex mcp add crabrix -- npx -y crabrix@0.5.0"),
        ("Cursor", "~/.cursor/mcp.json → \"crabrix\": { \"command\": \"npx\", \"args\": [\"-y\", \"crabrix@0.5.0\"] }"),
    ]
    @ObservedObject var session: PlaygroundLiveSession
    @ObservedObject var model: CompilerViewModel
    @State private var readOnly: Bool
    @State private var link: URL?
    @State private var failure: String?
    @State private var copied = false
    init(session: PlaygroundLiveSession, model: CompilerViewModel) {
        self.session = session; self.model = model
        _readOnly = State(initialValue: !session.canShareAgentEdit)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label("Connect AI agent", systemImage: "sparkles").font(.title2.bold())
                Text("Give this link to an AI agent with Crabrix MCP on its computer. Paste it into the agent’s chat: the agent joins the room as a participant, and the room’s key stays in the link and on that computer.")
                    .foregroundStyle(CrabrixTheme.muted)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Add Crabrix MCP once").font(.subheadline.weight(.semibold))
                    ForEach(Self.agentSetups, id: \.0) { agent, setup in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(agent).font(.callout.weight(.semibold))
                            Text(setup).font(.caption.monospaced()).foregroundStyle(CrabrixTheme.muted).textSelection(.enabled)
                        }
                    }
                    Text("Needs Node.js 22 or newer. People use the links in Share instead.").font(.caption).foregroundStyle(CrabrixTheme.muted)
                }
                if session.canShareAgentEdit && session.canShareAgentView {
                    Picker("Agent access", selection: $readOnly) { Text("Edit").tag(false); Text("View only").tag(true) }.pickerStyle(.segmented)
                } else {
                    Label(readOnly ? "View only" : "Edit", systemImage: readOnly ? "eye" : "pencil").font(.subheadline)
                }
                Text("Expires with the room at \(session.link.expiresAt.formatted(date: .abbreviated, time: .shortened))").font(.caption)
                if let link {
                    ShareLink(item: link.absoluteString) { Label("Share agent link", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).tint(CrabrixTheme.blue).disabled(session.expired)
                    Button {
                        UIPasteboard.general.setItems([[UTType.plainText.identifier: link.absoluteString]], options: [.expirationDate: session.link.expiresAt])
                        copied = true
                    } label: { Label(copied ? "Copied" : "Copy agent link", systemImage: copied ? "checkmark" : "doc.on.doc").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered).disabled(session.expired)
                } else if failure == nil {
                    ProgressView("Preparing agent link…").frame(maxWidth: .infinity)
                }
                if let failure { Text(failure).foregroundStyle(CrabrixTheme.coral) }
                if let runtime = model.playgroundRuntime { PlaygroundRuntimePermissions(runtime: runtime) }
            }
            .padding(22).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .background(CrabrixTheme.background).foregroundStyle(CrabrixTheme.primary)
        .navigationTitle("Connect AI agent").navigationBarTitleDisplayMode(.inline)
        .task(id: readOnly) {
            link = nil; failure = nil; copied = false
            do {
                let url = try await session.agentLink(readOnly: readOnly)
                if !Task.isCancelled { link = url }
            } catch {
                if !Task.isCancelled { failure = error.localizedDescription }
            }
        }
    }
}
private struct PlaygroundRuntimePermissions: View {
    @ObservedObject var runtime: PlaygroundRuntimeHost
    private func groupedKey(_ value: String) -> String { stride(from: 0, to: value.count, by: 8).map { String(value.dropFirst($0).prefix(8)) }.joined(separator: " ") }
    @State private var operations: Set<String> = ["check", "build", "run", "debug"]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Label("MCP · Run on this device", systemImage: "desktopcomputer.and.arrow.down").font(.headline)
            Text("Off until you allow a controller below. Only shared standard-library Rust and local modules run here. Cargo manifests, private files, packages and native libraries require ordinary local Run. Participants can read reported shared output. Jobs stop after two minutes, including pauses.").font(.caption).foregroundStyle(CrabrixTheme.muted)
            Text("Device key: \(groupedKey(runtime.fingerprint))").font(.caption2.monospaced()).textSelection(.enabled)
            if let grant = runtime.grant {
                Text("Allowed: \(grant.name) · \(grant.operations.joined(separator: ", "))").font(.subheadline)
                Text(Date(timeIntervalSince1970: Double(grant.expires) / 1000), format: .dateTime).font(.caption)
                Button("Revoke execution permission", role: .destructive) { runtime.revoke() }.buttonStyle(.bordered)
            }
            ForEach(runtime.requests, id: \.controller) { request in
                VStack(alignment: .leading, spacing: 10) {
                    Text(request.name).font(.headline)
                    Text(groupedKey(request.controller)).font(.caption2.monospaced()).textSelection(.enabled)
                    ForEach(request.operations, id: \.self) { operation in
                        Toggle(operation.capitalized, isOn: Binding(get: { operations.contains(operation) }, set: { if $0 { operations.insert(operation) } else { operations.remove(operation) } }))
                    }
                    Button("Allow selected operations · 10 min") { runtime.allow(request, operations: request.operations.filter { operations.contains($0) }) }
                        .buttonStyle(.borderedProminent).tint(CrabrixTheme.blue).disabled(operations.intersection(request.operations).isEmpty)
                }
            }
            Text(runtime.notice).font(.caption).foregroundStyle(CrabrixTheme.muted)
            ForEach(runtime.jobs, id: \.id) { job in Text("Shared \(job.operation) · \(job.state) · \(job.stage)").font(.caption) }
            if runtime.working { Button("Stop Shared job") { runtime.stopOwned() }.buttonStyle(.bordered) }
        }
    }
}
private struct PlaygroundSessionDetails: View {
    @ObservedObject var session: PlaygroundLiveSession
    let onLeave: () -> Void
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.link.expiresAt > context.date ? "Expires in \(Int(session.link.expiresAt.timeIntervalSince(context.date)).formatted()) seconds" : "Playground expired")
                        .font(.headline.monospacedDigit())
                    Text(session.link.expiresAt, format: .dateTime).font(.caption)
                }
            }
            Text(session.status).font(.callout)
            Label("\(session.participants) / 4 participants", systemImage: "person.2")
            ShareLink(item: session.link.url) {
                Label(session.link.isReadOnly ? "Share view-only Playground link" : "Share interview Playground link", systemImage: "square.and.arrow.up")
            }.buttonStyle(.borderedProminent).tint(CrabrixTheme.blue).disabled(session.expired)
            if let view = session.viewAccess {
                let link = PlaygroundLink(id: session.link.id, key: session.link.key, access: view, expiresAt: session.link.expiresAt, isReadOnly: true)
                ShareLink(item: link.url) { Label("Share view-only link", systemImage: "eye") }.buttonStyle(.bordered).disabled(session.expired)
            }
            Button("Keep local copy & leave room", action: onLeave).buttonStyle(.bordered)
            if session.owner != nil {
                Button("End this room for everyone", role: .destructive) {
                    Task { do { try await session.closeRoom() } catch { self.error = error.localizedDescription } }
                }.disabled(session.expired)
            }
            if let error { Text(error).foregroundStyle(CrabrixTheme.coral) }
        }
    }
}
