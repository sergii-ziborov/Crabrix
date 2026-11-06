import SwiftUI
import UniformTypeIdentifiers

/// Do not accept new learning while a previous restore is still unfinished:
/// retrying that journal on launch must never overwrite newly earned progress.
struct LearningRecoveryView: View {
    @ObservedObject var backup: LearningBackupCoordinator
    @State private var confirmPrevious = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label("Finish learning recovery", systemImage: "clock.arrow.circlepath").font(.title2.bold())
                Text("An interrupted restore couldn’t finish. Your recovery files have been kept. Retry before continuing so new learning isn’t overwritten.")
                if let error = backup.errorMessage { Text(error).font(.callout).foregroundStyle(CrabrixTheme.muted) }
                Button("Retry recovery") { backup.retryRecovery() }
                    .buttonStyle(.borderedProminent).tint(CrabrixTheme.blue).foregroundStyle(CrabrixTheme.onAccent)
                Button("Use progress from before the restore") { confirmPrevious = true }.buttonStyle(.bordered)
                Text("Your projects are kept separately. If device storage is full, free some space in iOS Settings, then retry.")
                    .font(.callout).foregroundStyle(CrabrixTheme.muted)
            }.padding(24).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }
        .disabled(backup.isWorking)
        .foregroundStyle(CrabrixTheme.primary).background(CrabrixTheme.background.ignoresSafeArea())
        .confirmationDialog("Return to progress saved before this restore?", isPresented: $confirmPrevious, titleVisibility: .visible) {
            Button("Use previous learning progress") { backup.retryRecovery(usePreviousProgress: true) }
        }
    }
}

struct LearningProgressDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let bytes = configuration.file.regularFileContents,
              bytes.count <= LearningBackupCodec.maximumEncodedBytes else { throw LearningBackupError.tooLarge }
        data = bytes
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct LearningBackupView: View {
    @EnvironmentObject private var backup: LearningBackupCoordinator
    @State private var importing = false
    @State private var exporting = false
    @State private var document = LearningProgressDocument()
    @State private var preview: LearningProgressSnapshot?
    @State private var confirmation = false
    @State private var notice: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Label("Keep your learning", systemImage: "icloud.and.arrow.up")
                    .font(.title2.bold())
                Text("Lesson completion, rating, achievements and practice history can travel with you. Project files are saved separately.")
                    .foregroundStyle(CrabrixTheme.muted)
                Toggle("Automatic private iCloud backup", isOn: Binding(
                    get: { backup.automatic }, set: backup.setAutomatic))
                    .tint(CrabrixTheme.mint).accessibilityIdentifier("learning-backup-icloud")
                Text("Optional. Uses your Apple iCloud account, without a Crabrix account. Copies from other installations appear here after Apple syncs them. Restoring always asks first.")
                    .font(.callout).foregroundStyle(CrabrixTheme.muted)
                Text(backup.status).font(.callout).accessibilityIdentifier("learning-backup-status")
                HStack {
                    Button { backup.saveNow() } label: { Label("Back up now", systemImage: "arrow.clockwise") }
                    Spacer()
                    Button { backup.requestRefresh() } label: { Image(systemName: "arrow.down.icloud") }
                        .accessibilityLabel("Refresh available backups")
                }.buttonStyle(.bordered)
                Divider()
                Text("A file, just in case").font(.headline)
                Text("Save a .crabrixprogress file to Files or iCloud Drive. Keep this copy before reinstalling. It contains your learning history and is not password protected.")
                    .font(.callout).foregroundStyle(CrabrixTheme.muted)
                ViewThatFits(in: .horizontal) {
                    HStack { exportButton; importButton }
                    VStack(alignment: .leading) { exportButton; importButton }
                }
                Divider()
                Text("Available recovery copies").font(.headline)
                if backup.copies.isEmpty {
                    Text("No completed learning in the available copies yet. Enable iCloud backup on your previous installation to make a copy available after reinstalling.")
                        .font(.callout).foregroundStyle(CrabrixTheme.muted)
                }
                ForEach(backup.copies.prefix(12)) { copy in
                    Button { preview = copy } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath").foregroundStyle(CrabrixTheme.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(copy.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                                Text("\(copy.completedLessonIDs.count) lessons · \(copy.flashcards.count) reviewed cards · \(copy.deviceFamily)")
                                    .font(.caption).foregroundStyle(CrabrixTheme.muted)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                        }.padding(15).background(CrabrixTheme.panel, in: RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(.plain)
                }
                if let notice { Text(notice).font(.callout).foregroundStyle(CrabrixTheme.mint) }
            }
            .padding(22).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .background(CrabrixTheme.background.ignoresSafeArea())
        .foregroundStyle(CrabrixTheme.primary)
        .navigationTitle("Learning backup").navigationBarTitleDisplayMode(.inline)
        .task { backup.start(); backup.requestRefresh() }
        .fileExporter(isPresented: $exporting, document: document, contentType: .data,
                      defaultFilename: "Crabrix learning.crabrixprogress") { result in
            switch result {
            case .success: notice = "Recovery file saved."
            case .failure(let error): backup.errorMessage = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                preview = try LearningBackupCodec.decode(LearningBackupCodec.readFile(url))
            } catch { backup.errorMessage = error.localizedDescription }
        }
        .sheet(item: $preview) { copy in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Label("Review recovery copy", systemImage: "clock.arrow.circlepath").font(.title2.bold())
                        Text(copy.createdAt.formatted(date: .complete, time: .shortened))
                        Text("\(copy.completedLessonIDs.count) completed lessons\n\(copy.flashcards.count) reviewed flashcards\n\(copy.termTrainSessions) Term Train sessions\n\(copy.codeRecallSessions) Code Recall sessions\n\(copy.flashcardSessions) flashcard sessions")
                        Text("This replaces learning progress on this device. Your current progress is saved as “Before restore” first. Project files, accounts and runtime permissions stay as they are. Missing courses can be downloaded again in Learn.")
                            .foregroundStyle(CrabrixTheme.muted)
                        Button("Restore this copy") { confirmation = true }
                            .buttonStyle(.borderedProminent).tint(CrabrixTheme.blue)
                            .foregroundStyle(CrabrixTheme.onAccent)
                            .disabled(backup.isWorking)
                            .accessibilityIdentifier("learning-backup-restore")
                    }.padding(24).frame(maxWidth: 620).frame(maxWidth: .infinity)
                }
                .foregroundStyle(CrabrixTheme.primary).background(CrabrixTheme.background.ignoresSafeArea())
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { preview = nil }.labelStyle(.iconOnly) } }
                .confirmationDialog("Replace learning progress with this copy?", isPresented: $confirmation, titleVisibility: .visible) {
                    Button("Restore learning progress", role: .destructive) {
                        do { try backup.restore(copy); preview = nil; notice = "Learning progress restored." }
                        catch { backup.errorMessage = error.localizedDescription; preview = nil }
                    }
                }
            }
        }
        .alert("Learning backup", isPresented: Binding(get: { backup.errorMessage != nil }, set: { if !$0 { backup.errorMessage = nil } })) {
            Button("OK", role: .cancel) { backup.errorMessage = nil }
        } message: { Text(backup.errorMessage ?? "The backup could not be saved.") }
    }

    private var exportButton: some View {
        Button {
            do { document = LearningProgressDocument(data: try backup.exportData()); exporting = true }
            catch { backup.errorMessage = error.localizedDescription }
        } label: { Label("Export recovery file", systemImage: "square.and.arrow.up") }
        .buttonStyle(.bordered).accessibilityIdentifier("learning-backup-export")
    }

    private var importButton: some View {
        Button { importing = true } label: { Label("Import file", systemImage: "square.and.arrow.down") }
            .buttonStyle(.bordered).accessibilityIdentifier("learning-backup-import")
    }
}
