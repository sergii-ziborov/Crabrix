import SwiftUI
import UIKit

@MainActor
final class AtlasReplayLoader: ObservableObject {
    @Published private(set) var section: AtlasReplayLibrary.Section?
    @Published private(set) var recording: AtlasRecording?
    @Published private(set) var isWorking = false
    @Published private(set) var received = 0
    @Published private(set) var total = 0
    @Published private(set) var message: String?
    private var job: Task<Void, Never>?
    private var identity = UUID()

    func inspect(method: String, lesson: String, source: String) async {
        do {
            let library = try AtlasReplayLibrary.shared.get()
            let section = try await library.section(method)
            guard !Task.isCancelled else { return }
            self.section = section
            if section.isInstalled {
                let recording = try await library.recording(method: method, lessonID: lesson, source: source)
                guard !Task.isCancelled else { return }
                self.recording = recording
            }
        } catch { if !Task.isCancelled { message = error.localizedDescription } }
    }
    func download(method: String, lesson: String, source: String) {
        operate { [weak self] id in
            let library = try AtlasReplayLibrary.shared.get()
            let observer = self
            try await library.download(method) { received, total in
                Task { @MainActor in
                    guard let observer, observer.identity == id, observer.isWorking else { return }
                    observer.received = received; observer.total = total
                }
            }
            try Task.checkCancellation()
            await self?.inspect(method: method, lesson: lesson, source: source)
        }
    }
    func remove(method: String) {
        operate { [weak self] _ in
            let library = try AtlasReplayLibrary.shared.get()
            try await library.remove(method)
            let section = try await library.section(method)
            self?.recording = nil; self?.section = section
        }
    }
    func stop() { job?.cancel(); if isWorking { message = "Stopping…" } }
    private func operate(_ operation: @escaping @MainActor (UUID) async throws -> Void) {
        guard !isWorking else { return }
        let id = UUID(); identity = id; isWorking = true; message = nil; received = 0; total = 0
        job = Task { [weak self] in
            guard let self else { return }
            defer { if identity == id { isWorking = false; job = nil } }
            do { try await operation(id); try Task.checkCancellation() }
            catch { if identity == id { message = error is CancellationError ? "Stopped. Prepared recordings remain available." : error.localizedDescription } }
        }
    }
}

struct AtlasReplayScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var loader = AtlasReplayLoader()
    let method: String
    let lessonID: String
    let source: String
    let variation: String
    let onOpenCopy: (AtlasRecording) -> Void
    @State private var step = 0
    @State private var playing = false
    @State private var speed = 850
    @State private var selectedCollection = ""
    @State private var availableWidth: CGFloat = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let recording = loader.recording {
                        playback(recording)
                    } else {
                        acquisition
                    }
                    if let message = loader.message {
                        Text(message).font(.subheadline).foregroundStyle(CrabrixTheme.muted)
                            .accessibilityIdentifier("atlas-replay-message")
                    }
                    if loader.isWorking {
                        HStack {
                            if loader.total > 0 {
                                ProgressView(value: Double(loader.received), total: Double(loader.total))
                                Text(ByteCountFormatter.string(fromByteCount: Int64(loader.received), countStyle: .file))
                                    .font(.caption.monospaced())
                            } else { ProgressView(); Text("Verifying section…").font(.subheadline) }
                            Button("Stop") { loader.stop() }
                        }
                    }
                }
                .padding(22).frame(maxWidth: 1100).frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("atlas-replay-scroll")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let recording = loader.recording {
                    controls(recording.replay)
                        .padding(.horizontal, 22).padding(.vertical, 8)
                        .frame(maxWidth: 1100).frame(maxWidth: .infinity)
                        .background(CrabrixTheme.background)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
            .background(CrabrixTheme.background.ignoresSafeArea())
            .foregroundStyle(CrabrixTheme.primary)
            .tint(CrabrixTheme.blue)
            .navigationTitle("Algorithm replay").navigationBarTitleDisplayMode(.inline)
            .toolbar { CrabrixModalCloseAction(label: "Close algorithm replay") { dismiss() } }
            .task { await loader.inspect(method: method, lesson: lessonID, source: source) }
            .task(id: playing) {
                guard playing else { return }
                do {
                    while !Task.isCancelled, playing, let recording = loader.recording,
                          step < recording.replay.frames.count {
                        try await Task.sleep(for: .milliseconds(speed))
                        guard !Task.isCancelled, playing else { return }
                        step += 1
                    }
                    playing = false
                } catch { }
            }
            .onChange(of: loader.recording?.replay.key) { _, _ in step = 0; playing = false; selectedCollection = "" }
            .onChange(of: scenePhase) { _, phase in if phase != .active { playing = false } }
            .onDisappear { playing = false; loader.stop() }
        }
    }

    private var acquisition: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Follow the original example", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.title2.bold())
            Text("Step through a verified recording with its Rust source, call stack and data. Playback works offline after downloading this section. Editing a personal copy uses ordinary Run or Debug.")
                .foregroundStyle(CrabrixTheme.muted)
            if let section = loader.section {
                if section.isInstalled {
                    Label("Section is prepared", systemImage: "checkmark.seal").foregroundStyle(CrabrixTheme.mint)
                    Text("If this example changed, update its course. Remove and download the recording section again if its verification fails.")
                        .font(.caption).foregroundStyle(CrabrixTheme.muted)
                    Button("Remove downloaded section", role: .destructive) { loader.remove(method: method) }
                        .disabled(loader.isWorking)
                } else {
                    Button {
                        loader.download(method: method, lesson: lessonID, source: source)
                    } label: {
                        Label("Download section · \(ByteCountFormatter.string(fromByteCount: Int64(section.downloadBytes), countStyle: .file))",
                              systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.borderedProminent).tint(CrabrixTheme.blue)
                        .foregroundStyle(CrabrixTheme.onAccent).disabled(loader.isWorking)
                        .accessibilityIdentifier("atlas-download-section")
                }
            } else { ProgressView("Reading signed section list…") }
            Text("Optional data only. Removing a section keeps your progress and personal projects.")
                .font(.caption).foregroundStyle(CrabrixTheme.muted)
        }.padding(18).crabrixPanel()
    }

    private func controls(_ replay: AtlasReplay) -> some View {
        let complete = step >= replay.frames.count
        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button { seek(0) } label: { Image(systemName: "arrow.counterclockwise").frame(width: 30, height: 30) }
                    .accessibilityLabel("Restart replay").disabled(step == 0)
                Button { seek(step - 1) } label: { Image(systemName: "chevron.left").frame(width: 30, height: 30) }
                    .accessibilityLabel("Previous replay step").disabled(step == 0)
                Button {
                    if complete { step = 0 }
                    playing.toggle()
                } label: {
                    Label(playing ? "Pause" : "Play", systemImage: playing ? "pause.fill" : "play.fill")
                        .frame(minWidth: 72, minHeight: 30)
                }.buttonStyle(.borderedProminent).tint(CrabrixTheme.blue).foregroundStyle(CrabrixTheme.onAccent)
                    .accessibilityIdentifier("atlas-replay-play")
                Button { seek(step + 1) } label: { Image(systemName: "chevron.right").frame(width: 30, height: 30) }
                    .accessibilityLabel("Next replay step").disabled(complete)
            }.buttonStyle(.bordered)
            HStack {
                Text(complete ? "Finished · \(replay.frames.count) steps" : "Step \(step + 1) / \(replay.frames.count)")
                    .font(.caption.monospaced()).accessibilityIdentifier("atlas-replay-step")
                Spacer()
                Picker("Playback speed", selection: $speed) {
                    Text("Slow").tag(1600); Text("Normal").tag(850); Text("Fast").tag(300)
                }.pickerStyle(.menu).font(.caption)
            }
            Slider(value: Binding(get: { Double(step) }, set: { seek(Int($0)) }),
                   in: 0...Double(replay.frames.count), step: 1)
                .accessibilityLabel("Execution step").tint(CrabrixTheme.blue)
        }.padding(16).crabrixPanel()
    }

    private func playback(_ recording: AtlasRecording) -> some View {
        let replay = recording.replay
        let complete = step >= replay.frames.count
        let index = min(step, replay.frames.count - 1)
        let frame = replay.frames[index], site = replay.sites[frame.site]
        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Label("VERIFIED RECORDING · OFFLINE", systemImage: "checkmark.seal.fill")
                    .font(.caption.monospaced().bold()).foregroundStyle(CrabrixTheme.mint)
                Text(replay.title).font(.title2.bold())
                Text(replay.idea).foregroundStyle(CrabrixTheme.muted)
                Text(replay.complexity).font(.caption).foregroundStyle(CrabrixTheme.muted)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(complete ? "Execution finished" : "\(site.function) · before line \(site.line)")
                    .font(.headline).accessibilityIdentifier("atlas-replay-location")
                if complete { HighlightedCodeBlock(code: replay.stdout, filePath: "stdout.txt") }
                else { HighlightedCodeBlock(code: site.statement) }
                Text("Values show the state before this statement. Next follows the recorded execution; it does not run your edited program.")
                    .font(.caption).foregroundStyle(CrabrixTheme.muted)
            }.padding(16).crabrixPanel()
            if availableWidth > 820 {
                HStack(alignment: .top, spacing: 18) {
                    dataPane(recording, index: index).frame(maxWidth: .infinity)
                    codePane(replay, site: site, frame: frame, complete: complete).frame(maxWidth: .infinity)
                }
            } else {
                dataPane(recording, index: index)
                codePane(replay, site: site, frame: frame, complete: complete)
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("Try your own version").font(.headline)
                Text(variation).font(.subheadline).foregroundStyle(CrabrixTheme.muted)
                Button("Open personal copy in Code", systemImage: "curlybraces") {
                    playing = false; dismiss(); onOpenCopy(recording)
                }.buttonStyle(.borderedProminent).tint(CrabrixTheme.blue).foregroundStyle(CrabrixTheme.onAccent)
                    .accessibilityIdentifier("atlas-open-personal-copy")
                Text("The copy starts with this exact input and original source. Change it, then use Run or Debug. This recording remains attached to the original example.")
                    .font(.caption).foregroundStyle(CrabrixTheme.muted)
            }.padding(18).crabrixPanel()
            DisclosureGroup("Recording and download details") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Course \(recording.courseContentVersion) · recording pack \(recording.packVersion)")
                    Text("Recorded with native Rust 1.99.0. Personal projects run on wasm32-wasip1; target-sized values such as usize may have different limits. Use ordinary Debug to inspect execution on this device.")
                    Text("Original source SHA-256\n\(replay.sourceHash)").font(.caption.monospaced()).textSelection(.enabled)
                    if replay.verification.omittedCaptures > 0 {
                        Text("\(replay.verification.omittedCaptures) unsupported captures were omitted during recording. Only captured values are shown.")
                    }
                    Button("Remove downloaded section", role: .destructive) {
                        playing = false; loader.remove(method: method)
                    }.disabled(loader.isWorking)
                }.font(.caption).foregroundStyle(CrabrixTheme.muted).padding(.vertical, 8)
            }
        }
    }
    private func seek(_ value: Int) {
        playing = false; step = max(0, min(loader.recording?.replay.frames.count ?? 0, value))
    }
    private func dataPane(_ recording: AtlasRecording, index: Int) -> some View {
        let replay = recording.replay, frame = replay.frames[index]
        let locals = Dictionary(uniqueKeysWithValues: frame.locals.map { ($0.name, replay.values[$0.value].data) })
        let previous: [String: AtlasValue] = recording.previousFrameIndices[index].map { previous in
            Dictionary(uniqueKeysWithValues: replay.frames[previous].locals.map { ($0.name, replay.values[$0.value].data) })
        } ?? [:]
        let collections = frame.locals.filter { if case .scalar = replay.values[$0.value].data { false } else { true } }
        let selected = collections.first(where: { $0.name == selectedCollection })
            ?? ["dp", "graph", "g", "adj", "grid", "matrix", "root", "head", "tree", "values", "a", "nums", "data"]
                .lazy.compactMap { name in collections.first { $0.name == name } }.first
            ?? collections.first
        return VStack(alignment: .leading, spacing: 14) {
            Text("Data & variables").font(.headline)
            Text("Blue: current index · Green: changed value").font(.caption2).foregroundStyle(CrabrixTheme.muted)
            DisclosureGroup("Fixed example input") {
                Text(replay.input).font(.caption.monospaced()).textSelection(.enabled).padding(.vertical, 8)
            }.font(.subheadline)
            if let selected {
                Picker("Inspect collection", selection: Binding(get: { selected.name }, set: { selectedCollection = $0 })) {
                    ForEach(collections, id: \.name) { Text($0.name).tag($0.name) }
                }.pickerStyle(.menu)
                AtlasValueView(name: selected.name, value: replay.values[selected.value].data,
                    previous: previous[selected.name], locals: locals, edge: replay.sites[frame.site].edge)
            }
            ForEach(frame.locals.filter { if case .scalar = replay.values[$0.value].data { true } else { false } }, id: \.name) { local in
                let value = replay.values[local.value]
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(local.name).font(.subheadline.monospaced().bold())
                        Text(value.type).font(.caption2.monospaced()).foregroundStyle(CrabrixTheme.muted)
                    }
                    Spacer()
                    Text(value.data.text).font(.subheadline.monospaced()).textSelection(.enabled)
                        .foregroundStyle(previous[local.name].map { $0 != value.data } == true ? CrabrixTheme.mint : CrabrixTheme.primary)
                }.padding(.vertical, 5)
            }
            if frame.locals.isEmpty {
                Label("Local values appear as they enter scope.", systemImage: "curlybraces")
                    .foregroundStyle(CrabrixTheme.muted).font(.subheadline)
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).crabrixPanel()
    }
    private func codePane(_ replay: AtlasReplay, site: AtlasReplay.Site, frame: AtlasReplay.Frame, complete: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Original Rust source").font(.headline)
            AtlasSourceListing(source: replay.source, activeLine: complete ? nil : site.line)
            Text("Call stack").font(.headline)
            ForEach(Array(frame.stack.enumerated()), id: \.offset) { _, call in
                Text("\(call.function) · call \(call.activation)").font(.caption.monospaced())
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).crabrixPanel()
    }
}

private struct AtlasSourceListing: View {
    let source: String
    let activeLine: Int?
    @State private var lines: [AttributedString] = []
    var body: some View {
        ScrollViewReader { reader in
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(lines.indices, id: \.self) { i in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(i + 1)").font(.caption.monospaced()).foregroundStyle(CrabrixTheme.muted).frame(width: 30, alignment: .trailing)
                            Text(lines[i]).fixedSize(horizontal: true, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.padding(.vertical, 4).padding(.horizontal, 5)
                            .background(activeLine == i + 1 ? CrabrixTheme.blue.opacity(0.18) : .clear)
                            .id(i + 1)
                    }
                }.padding(.vertical, 6)
            }.frame(height: 250).background(SyntaxTheme.background)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .task(id: source) {
                    let full = NSAttributedString(SyntaxTheme.attributedString(source))
                    let raw = source as NSString
                    var offset = 0, styled: [AttributedString] = []
                    while offset < raw.length {
                        let range = raw.lineRange(for: NSRange(location: offset, length: 0))
                        var content = range
                        while content.length > 0 {
                            let code = raw.character(at: content.location + content.length - 1)
                            guard let scalar = UnicodeScalar(code), CharacterSet.newlines.contains(scalar) else { break }
                            content.length -= 1
                        }
                        styled.append(AttributedString(full.attributedSubstring(from: content)))
                        offset = NSMaxRange(range)
                    }
                    lines = styled
                    if let activeLine { reader.scrollTo(activeLine, anchor: .center) }
                }
                .onChange(of: activeLine) { _, line in if let line { reader.scrollTo(line, anchor: .center) } }
                .accessibilityLabel("Recorded source with current line \(activeLine.map(String.init) ?? "finished")")
        }
    }
}
