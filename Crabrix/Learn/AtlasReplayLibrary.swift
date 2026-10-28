import Foundation

/// Optional, signed data packs use a separate root/index from courses and progress.
/// Only a selected recording is decoded for playback. No source is executed here.
actor AtlasReplayLibrary {
    struct Index: Decodable {
        struct Lesson: Decodable { let key: String; let sourceHash: String }
        struct Recording: Decodable { let sha256: String; let bytes: Int }
        let version: Int
        let methodID: String
        let title: String
        let courseContentVersion: String
        let lessons: [String: Lesson]
        let recordings: [String: Recording]
    }
    struct Section: Sendable {
        let method: String
        let downloadBytes: Int
        let isInstalled: Bool
    }
    private struct Job { let id: UUID; let task: Task<InstalledCourseRecord, Error> }
    static let shared = Result { try AtlasReplayLibrary() }
    private let root: URL
    private let cacheRoot: URL
    private let keyring: CourseKeyring
    private let catalog: CourseCatalogPayload
    private let installer: CourseInstaller
    private let downloader: CourseDownloadManager
    private var jobs: [String: Job] = [:]
    private var removing = Set<String>()

    init(root: URL? = nil, cacheRoot: URL? = nil, keyring: CourseKeyring? = nil,
         catalogBytes: Data? = nil, bundle: Bundle = .main) throws {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let resolvedRoot = root ?? support.appending(path: "Crabrix/AtlasReplays")
        let resolvedCache = cacheRoot ?? caches.appending(path: "Crabrix/AtlasReplayDownloads")
        let trustedKeys = try keyring ?? CourseBootstrap(bundle: bundle).keyring()
        let bytes: Data
        if let catalogBytes { bytes = catalogBytes }
        else {
            guard let url = bundle.url(forResource: "AtlasReplayCatalog", withExtension: "json")
            else { throw AtlasReplayError.invalid("missing section catalog") }
            bytes = try Self.read(url, maximum: 256 * 1_024)
        }
        guard bytes.count <= 256 * 1_024 else { throw AtlasReplayError.invalid("catalog size") }
        let catalog = try CoursePackVerifier.catalog(bytes: bytes, keyring: trustedKeys, lastAcceptedSequence: 0)
        guard catalog.courses.count == 20,
              Set(catalog.courses.map(\.courseID)).count == 20,
              catalog.courses.allSatisfy({
                  $0.courseID.hasPrefix("atlas-") && AtlasReplay.slug(String($0.courseID.dropFirst(6)))
                    && $0.language == "en" && $0.requiredCapabilities == ["atlas-replay-v1"]
                    && $0.archiveBytes <= 8 * 1_024 * 1_024
                    && SemanticVersion($0.contentVersion) != nil
              }) else { throw AtlasReplayError.invalid("section catalog") }
        self.root = resolvedRoot; self.cacheRoot = resolvedCache
        self.keyring = trustedKeys; self.catalog = catalog
        installer = try CourseInstaller(root: resolvedRoot)
        downloader = try CourseDownloadManager(cacheRoot: resolvedCache)
    }

    func section(_ method: String) async throws -> Section {
        let entry = try entry(method)
        let installed = try await installer.installed()
        return Section(method: method, downloadBytes: entry.archiveBytes,
                       isInstalled: installed.contains { matches($0, entry) })
    }

    func download(_ method: String, progress: (@Sendable (Int, Int) -> Void)? = nil) async throws {
        guard jobs[method] == nil, !removing.contains(method) else {
            throw AtlasReplayError.invalid("another operation is using this section")
        }
        let entry = try entry(method), id = UUID()
        let task = Task { [downloader, installer, keyring] in
            let downloaded = try await downloader.download(entry, progress: progress)
            try Task.checkCancellation()
            let record = try await installer.install(descriptorBytes: downloaded.descriptor,
                downloadedArchive: downloaded.archive, keyring: keyring)
            try Task.checkCancellation()
            return record
        }
        jobs[method] = Job(id: id, task: task)
        defer { if jobs[method]?.id == id { jobs[method] = nil } }
        _ = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    /// Used by deterministic qualification and Files-free bundled test fixtures.
    /// The same installer verifies signatures, inventory and bytes as downloads.
    func install(_ method: String, descriptor: Data, archive: URL) async throws {
        let entry = try entry(method)
        guard AtlasReplay.digest(descriptor) == entry.descriptorSHA256 else {
            throw CoursePackError.archiveDigestMismatch
        }
        let record = try await installer.install(descriptorBytes: descriptor,
            downloadedArchive: archive, keyring: keyring)
        guard matches(record, entry) else { throw CoursePackError.manifestMismatch("section identity") }
    }

    func remove(_ method: String) async throws {
        let entry = try entry(method)
        guard removing.insert(method).inserted else { return }
        defer { removing.remove(method) }
        if let job = jobs[method] { job.task.cancel(); _ = await job.task.result }
        try await installer.uninstall(courseID: entry.courseID, language: entry.language)
        for suffix in [".zip", ".partial", ".transfer.json"] {
            let path = cacheRoot.appending(path: entry.archiveSHA256 + suffix)
            if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
        }
    }

    func recording(method: String, lessonID: String, source: String) async throws -> AtlasRecording {
        let entry = try entry(method)
        guard let record = try await installer.installed().first(where: { matches($0, entry) })
        else { throw AtlasReplayError.unavailable }
        guard let descriptorBytes = Data(base64Encoded: record.descriptorBase64) else {
            throw CoursePackError.invalidEnvelope
        }
        guard AtlasReplay.digest(descriptorBytes) == entry.descriptorSHA256 else {
            throw CoursePackError.archiveDigestMismatch
        }
        let (payload, _) = try CoursePackVerifier.signedPayload(descriptorBytes,
            domain: CoursePackVerifier.descriptorDomain, keyring: keyring)
        let descriptor = try JSONDecoder().decode(CourseDescriptorPayload.self, from: payload)
        let directory = root.appending(path: "\(entry.courseID)/\(entry.language)/\(entry.contentVersion)")
        let indexData = try Self.read(directory.appending(path: "index.json"), maximum: 256 * 1_024)
        guard AtlasReplay.digest(indexData) == descriptor.courseDigest else {
            throw AtlasReplayError.invalid("section index digest")
        }
        let index = try JSONDecoder().decode(Index.self, from: indexData)
        guard index.version == 1, index.methodID == method,
              index.lessons.count <= 60, index.recordings.count <= 40,
              SemanticVersion(index.courseContentVersion) != nil,
              let lesson = index.lessons[lessonID],
              AtlasReplay.slug(lesson.key), let item = index.recordings[lesson.key],
              item.bytes > 0, item.bytes <= 2 * 1_024 * 1_024
        else { throw AtlasReplayError.invalid("lesson index") }
        guard lesson.sourceHash == AtlasReplay.digest(Data(source.utf8)) else {
            throw AtlasReplayError.changedSource
        }
        let traceData = try Self.read(directory.appending(path: "traces/\(lesson.key).json"), maximum: item.bytes)
        guard traceData.count == item.bytes, AtlasReplay.digest(traceData) == item.sha256 else {
            throw AtlasReplayError.invalid("recording digest")
        }
        let replay = try AtlasReplay.decode(traceData, expectedSource: source, expectedKey: lesson.key)
        guard replay.category == method else { throw AtlasReplayError.invalid("recording section") }
        return AtlasRecording(replay: replay, lessonID: lessonID, packDigest: entry.archiveSHA256,
            packVersion: entry.contentVersion, courseContentVersion: index.courseContentVersion)
    }

    private func entry(_ method: String) throws -> CourseCatalogPayload.Entry {
        guard AtlasReplay.slug(method),
              let entry = catalog.courses.first(where: { $0.courseID == "atlas-\(method)" })
        else { throw AtlasReplayError.invalid("unknown section") }
        return entry
    }
    private func matches(_ record: InstalledCourseRecord, _ entry: CourseCatalogPayload.Entry) -> Bool {
        record.courseID == entry.courseID && record.language == entry.language
            && record.contentVersion == entry.contentVersion && record.archiveSHA256 == entry.archiveSHA256
    }
    private static func read(_ url: URL, maximum: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let bytes = values.fileSize, bytes <= maximum else {
            throw AtlasReplayError.invalid("file size or kind")
        }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let data = try file.read(upToCount: maximum + 1) ?? Data()
        guard data.count == bytes, data.count <= maximum else { throw AtlasReplayError.invalid("file changed") }
        return data
    }
}
