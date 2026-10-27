import SwiftUI

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
