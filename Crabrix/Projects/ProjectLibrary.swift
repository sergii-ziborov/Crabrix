import Foundation

/// Durable storage for every user project.
///
/// A project lives in its own directory and is never evicted for being old.
/// The index is only an accelerator: if it is damaged, the individual project
/// directories remain independently decodable and the index is rebuilt.
actor ProjectStore {
    enum StoreError: LocalizedError {
        case invalidProjectPath(String)
        case missingProject(UUID)

        var errorDescription: String? {
            switch self {
            case let .invalidProjectPath(path):
                "The project contains an unsafe file path: \(path)"
            case let .missingProject(id):
                "Project \(id.uuidString) is no longer available on this device."
            }
        }
    }

    private struct ProjectMetadata: Codable {
        static let currentVersion = 2

        let version: Int
        let id: UUID
        let name: String
        let entryFile: String
        let provenance: CrabrixProject.Provenance?
        let projectDescription: String?
        let tags: [String]?
        let folder: String?
        let kind: CrabrixProject.Kind?
        let isFavorite: Bool?
        let updatedAt: Date
        let lastBuild: ProjectBuildRecord?

        init(
            project: CrabrixProject,
            updatedAt: Date,
            lastBuild: ProjectBuildRecord?
        ) {
            version = Self.currentVersion
            id = project.id
            name = project.name
            entryFile = project.entryFile
            provenance = project.provenance
            projectDescription = project.projectDescription
            tags = project.tags
            folder = project.folder
            kind = project.kind
            isFavorite = project.isFavorite
            self.updatedAt = updatedAt
            self.lastBuild = lastBuild
        }
    }

    private struct ProjectIndex: Codable {
        static let currentVersion = 1

        var version = ProjectIndex.currentVersion
        var projects: [IndexEntry]
    }

    private struct IndexEntry: Codable {
        let id: UUID
        var name: String
        var updatedAt: Date
    }

    private let rootURL: URL
    private let projectsURL: URL
    private let indexURL: URL
    private let fileManager: FileManager

    init(rootURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? fileManager.temporaryDirectory
            self.rootURL = applicationSupport
                .appending(path: "Crabrix", directoryHint: .isDirectory)
        }
        projectsURL = self.rootURL.appending(path: "projects", directoryHint: .isDirectory)
        indexURL = self.rootURL.appending(path: "project-index.json")
    }

    @discardableResult
    func save(
        project: CrabrixProject,
        lastBuild: ProjectBuildRecord?,
        at date: Date = Date()
    ) throws -> ProjectLibraryItem {
        try prepareStorage()
        try recoverInterruptedTransactions()
        try validate(project)

        let destination = directory(for: project.id)
        let existing = try? loadProject(from: destination)
        let effectiveLastBuild = lastBuild ?? existing?.lastBuild
        let staging = projectsURL.appending(
            path: ".staging-\(project.id.uuidString)-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let backup = projectsURL.appending(
            path: ".backup-\(project.id.uuidString)-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )

        do {
            try writeSnapshot(
                project: project,
                lastBuild: effectiveLastBuild,
                updatedAt: date,
                to: staging
            )

            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.moveItem(at: destination, to: backup)
            }

            do {
                try fileManager.moveItem(at: staging, to: destination)
            } catch {
                if fileManager.fileExists(atPath: backup.path),
                   !fileManager.fileExists(atPath: destination.path) {
                    try? fileManager.moveItem(at: backup, to: destination)
                }
                throw error
            }

            if fileManager.fileExists(atPath: backup.path) {
                try installRecoverySnapshot(from: backup, in: destination)
                try? fileManager.removeItem(at: backup)
            }
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }

        try updateIndex(projectID: project.id, name: project.name, updatedAt: date)
        return ProjectLibraryItem(
            project: project,
            lastOpenedAt: date,
            lastBuild: effectiveLastBuild
        )
    }

    func project(id: UUID) throws -> ProjectLibraryItem? {
        try prepareStorage()
        try recoverInterruptedTransactions()
        let url = directory(for: id)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try loadProject(from: url)
    }

    func allProjects() throws -> [ProjectLibraryItem] {
        try prepareStorage()
        try recoverInterruptedTransactions()
        let entries = try loadOrRebuildIndex()
        var result: [ProjectLibraryItem] = []
        for entry in entries.sorted(by: { $0.updatedAt > $1.updatedAt }) {
            if let item = try? loadProject(from: directory(for: entry.id)) {
                result.append(item)
            }
        }
        return result
    }

    /// Deletion is intentionally explicit. No age, count, or recency policy
    /// calls this method.
    func delete(projectID: UUID) throws {
        try prepareStorage()
        let url = directory(for: projectID)
        guard fileManager.fileExists(atPath: url.path) else {
            throw StoreError.missingProject(projectID)
        }
        try fileManager.removeItem(at: url)
        var index = try loadOrRebuildIndex()
        index.removeAll { $0.id == projectID }
        try persistIndex(index)
    }

    private func prepareStorage() throws {
        try fileManager.createDirectory(at: projectsURL, withIntermediateDirectories: true)
    }

    private func directory(for id: UUID) -> URL {
        projectsURL.appending(path: id.uuidString.lowercased(), directoryHint: .isDirectory)
    }

    private func validate(_ project: CrabrixProject) throws {
        for path in project.files.keys {
            let components = path.split(separator: "/", omittingEmptySubsequences: false)
            guard !path.isEmpty,
                  !path.hasPrefix("/"),
                  !path.contains("\\"),
                  !path.contains("\0"),
                  !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
            else { throw StoreError.invalidProjectPath(path) }
        }
        guard project.files[project.entryFile] != nil else {
            throw StoreError.invalidProjectPath(project.entryFile)
        }
    }

    private func writeSnapshot(
        project: CrabrixProject,
        lastBuild: ProjectBuildRecord?,
        updatedAt: Date,
        to directory: URL
    ) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let filesURL = directory.appending(path: "files", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: filesURL, withIntermediateDirectories: true)

        for (path, source) in project.files.sorted(by: { $0.key < $1.key }) {
            let url = try projectFileURL(path, beneath: filesURL)
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(source.utf8).write(to: url, options: .atomic)
        }

        let metadata = ProjectMetadata(
            project: project,
            updatedAt: updatedAt,
            lastBuild: lastBuild
        )
        try encoder().encode(metadata).write(
            to: directory.appending(path: "project.json"),
            options: .atomic
        )
    }

    private func loadProject(from directory: URL) throws -> ProjectLibraryItem {
        do {
            return try decodeProjectSnapshot(at: directory)
        } catch {
            let recovery = directory
                .appending(path: "recovery", directoryHint: .isDirectory)
                .appending(path: "previous", directoryHint: .isDirectory)
            guard fileManager.fileExists(atPath: recovery.path) else { throw error }
            return try decodeProjectSnapshot(at: recovery)
        }
    }

    private func decodeProjectSnapshot(at directory: URL) throws -> ProjectLibraryItem {
        let metadata = try decoder().decode(
            ProjectMetadata.self,
            from: Data(contentsOf: directory.appending(path: "project.json"))
        )
        let files = try readFiles(
            beneath: directory.appending(path: "files", directoryHint: .isDirectory)
        )
        let project = CrabrixProject(
            id: metadata.id,
            name: metadata.name,
            files: files,
            entryFile: metadata.entryFile,
            provenance: metadata.provenance,
            projectDescription: metadata.projectDescription ?? "",
            tags: metadata.tags ?? [],
            folder: metadata.folder,
            kind: metadata.kind ?? .general,
            isFavorite: metadata.isFavorite ?? false
        )
        try validate(project)
        return ProjectLibraryItem(
            project: project,
            lastOpenedAt: metadata.updatedAt,
            lastBuild: metadata.lastBuild
        )
    }

    private func readFiles(beneath filesURL: URL) throws -> [String: String] {
        guard let enumerator = fileManager.enumerator(
            at: filesURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [:] }

        var result: [String: String] = [:]
        let rootPath = filesURL.standardizedFileURL.path
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            let path = String(url.standardizedFileURL.path.dropFirst(rootPath.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard data.count <= LocalProjectLoader.maximumFileBytes,
                  let source = String(data: data, encoding: .utf8)
            else { continue }
            result[path] = source
        }
        return result
    }

    private func projectFileURL(_ path: String, beneath root: URL) throws -> URL {
        var result = root
        for component in path.split(separator: "/") {
            result.append(path: String(component))
        }
        let standardizedRoot = root.standardizedFileURL.path + "/"
        guard result.standardizedFileURL.path.hasPrefix(standardizedRoot) else {
            throw StoreError.invalidProjectPath(path)
        }
        return result
    }

    private func installRecoverySnapshot(from old: URL, in current: URL) throws {
        let recovery = current
            .appending(path: "recovery", directoryHint: .isDirectory)
            .appending(path: "previous", directoryHint: .isDirectory)
        try? fileManager.removeItem(at: recovery)
        try fileManager.createDirectory(
            at: recovery.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(at: recovery, withIntermediateDirectories: true)
        try fileManager.copyItem(
            at: old.appending(path: "project.json"),
            to: recovery.appending(path: "project.json")
        )
        try fileManager.copyItem(
            at: old.appending(path: "files", directoryHint: .isDirectory),
            to: recovery.appending(path: "files", directoryHint: .isDirectory)
        )
    }

    /// If the process stopped after moving the old snapshot aside but before
    /// committing the staged one, restore that valid backup on next access.
    private func recoverInterruptedTransactions() throws {
        let children = try fileManager.contentsOfDirectory(
            at: projectsURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsSubdirectoryDescendants]
        )
        let backups = children.filter { $0.lastPathComponent.hasPrefix(".backup-") }
            .sorted {
                let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                return left > right
            }

        for backup in backups {
            guard let item = try? decodeProjectSnapshot(at: backup) else {
                try? fileManager.removeItem(at: backup)
                continue
            }
            let destination = directory(for: item.id)
            if !fileManager.fileExists(atPath: destination.path) {
                try fileManager.moveItem(at: backup, to: destination)
            } else {
                try? fileManager.removeItem(at: backup)
            }
        }

        for staging in children where staging.lastPathComponent.hasPrefix(".staging-") {
            try? fileManager.removeItem(at: staging)
        }
    }

    private func updateIndex(projectID: UUID, name: String, updatedAt: Date) throws {
        var entries = try loadOrRebuildIndex()
        if let index = entries.firstIndex(where: { $0.id == projectID }) {
            entries[index].name = name
            entries[index].updatedAt = updatedAt
        } else {
            entries.append(IndexEntry(id: projectID, name: name, updatedAt: updatedAt))
        }
        try persistIndex(entries)
    }

    private func loadOrRebuildIndex() throws -> [IndexEntry] {
        if fileManager.fileExists(atPath: indexURL.path),
           let data = try? Data(contentsOf: indexURL),
           let index = try? decoder().decode(ProjectIndex.self, from: data),
           index.version == ProjectIndex.currentVersion {
            let existing = index.projects.filter {
                fileManager.fileExists(atPath: directory(for: $0.id).path)
            }
            let indexedIDs = Set(existing.map(\.id))
            let discovered = try scanProjectDirectories().filter { !indexedIDs.contains($0.id) }
            if discovered.isEmpty { return existing }
            let rebuilt = existing + discovered
            try persistIndex(rebuilt)
            return rebuilt
        }

        let rebuilt = try scanProjectDirectories()
        try persistIndex(rebuilt)
        return rebuilt
    }

    private func scanProjectDirectories() throws -> [IndexEntry] {
        let children = try fileManager.contentsOfDirectory(
            at: projectsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )
        return children.compactMap { url in
            guard let item = try? loadProject(from: url) else { return nil }
            return IndexEntry(
                id: item.id,
                name: item.project.name,
                updatedAt: item.lastOpenedAt
            )
        }
    }

    private func persistIndex(_ entries: [IndexEntry]) throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let index = ProjectIndex(projects: entries.sorted { $0.updatedAt > $1.updatedAt })
        try encoder().encode(index).write(to: indexURL, options: .atomic)
    }

    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// A bounded list of references to durable projects. Removing an entry here
/// never removes the project itself.
actor RecentProjectIndex {
    struct Entry: Codable, Equatable, Sendable {
        let projectID: UUID
        var lastOpenedAt: Date
    }

    private struct State: Codable {
        static let currentVersion = 1

        var version = State.currentVersion
        var entries: [Entry]
    }

    private let storageURL: URL
    private let maximumCount: Int
    private var cachedState: State?

    init(storageURL: URL, maximumCount: Int = 20) {
        self.storageURL = storageURL
        self.maximumCount = maximumCount
    }

    func entries() throws -> [Entry] {
        try state().entries.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    }

    func touch(projectID: UUID, at date: Date = Date()) throws {
        var current = try state()
        current.entries.removeAll { $0.projectID == projectID }
        current.entries.insert(Entry(projectID: projectID, lastOpenedAt: date), at: 0)
        if current.entries.count > maximumCount {
            current.entries.removeLast(current.entries.count - maximumCount)
        }
        try persist(current)
    }

    func replace(with entries: [Entry]) throws {
        var seen: Set<UUID> = []
        let unique = entries
            .sorted { $0.lastOpenedAt > $1.lastOpenedAt }
            .filter { seen.insert($0.projectID).inserted }
        try persist(State(entries: Array(unique.prefix(maximumCount))))
    }

    func remove(projectID: UUID) throws {
        var current = try state()
        current.entries.removeAll { $0.projectID == projectID }
        try persist(current)
    }

    private func state() throws -> State {
        if let cachedState { return cachedState }
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            let state = State(entries: [])
            cachedState = state
            return state
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode(State.self, from: Data(contentsOf: storageURL)),
              decoded.version == State.currentVersion
        else {
            let state = State(entries: [])
            cachedState = state
            return state
        }
        cachedState = decoded
        return decoded
    }

    private func persist(_ state: State) throws {
        try FileManager.default.createDirectory(
            at: storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(state).write(to: storageURL, options: .atomic)
        cachedState = state
    }
}

/// Compatibility facade used by the UI. Durable storage and recency are
/// deliberately separate actors even though callers often need both.
actor ProjectLibrary {
    private struct LegacyProject: Codable {
        let name: String
        let files: [String: String]
        let entryFile: String
        let provenance: CrabrixProject.Provenance?
    }

    private struct LegacyItem: Codable {
        let id: UUID
        let project: LegacyProject
        let lastOpenedAt: Date
        let lastBuild: ProjectBuildRecord?
    }

    private struct LegacyState: Codable {
        var items: [LegacyItem]
    }

    private let rootURL: URL
    private let legacyAndRecentURL: URL
    private let store: ProjectStore
    private let recent: RecentProjectIndex
    private var migrationChecked = false

    init(storageURL: URL? = nil) {
        if let storageURL {
            rootURL = storageURL.deletingLastPathComponent()
            legacyAndRecentURL = storageURL
        } else {
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.temporaryDirectory
            rootURL = applicationSupport
                .appending(path: "Crabrix", directoryHint: .isDirectory)
            legacyAndRecentURL = rootURL.appending(path: "recent-projects.json")
        }
        store = ProjectStore(rootURL: rootURL)
        recent = RecentProjectIndex(storageURL: legacyAndRecentURL)
    }

    func items() async throws -> [ProjectLibraryItem] {
        try await ensureLegacyMigration()
        return try await resolvedRecentItems()
    }

    func allItems() async throws -> [ProjectLibraryItem] {
        try await ensureLegacyMigration()
        return try await store.allProjects()
    }

    func project(id: UUID) async throws -> ProjectLibraryItem? {
        try await ensureLegacyMigration()
        guard var item = try await store.project(id: id) else { return nil }
        let now = Date()
        try await recent.touch(projectID: id, at: now)
        item.lastOpenedAt = now
        return item
    }

    @discardableResult
    func record(
        project: CrabrixProject,
        lastBuild: ProjectBuildRecord?
    ) async throws -> [ProjectLibraryItem] {
        try await ensureLegacyMigration()
        let now = Date()
        _ = try await store.save(project: project, lastBuild: lastBuild, at: now)
        try await recent.touch(projectID: project.id, at: now)
        return try await resolvedRecentItems()
    }

    func delete(projectID: UUID) async throws {
        try await ensureLegacyMigration()
        try await store.delete(projectID: projectID)
        try await recent.remove(projectID: projectID)
    }

    /// Persists organization metadata without pretending the project was
    /// opened. This keeps Recent useful while folders and favorites can be
    /// managed from the full My Projects library.
    @discardableResult
    func update(
        project: CrabrixProject,
        lastBuild: ProjectBuildRecord?
    ) async throws -> ProjectLibraryItem {
        try await ensureLegacyMigration()
        return try await store.save(
            project: project,
            lastBuild: lastBuild,
            at: Date()
        )
    }

    private func resolvedRecentItems() async throws -> [ProjectLibraryItem] {
        let entries = try await recent.entries()
        var result: [ProjectLibraryItem] = []
        for entry in entries {
            guard var item = try await store.project(id: entry.projectID) else { continue }
            item.lastOpenedAt = entry.lastOpenedAt
            result.append(item)
        }
        return result
    }

    /// Migrates the old ten-item payload once. Its `ProjectLibraryItem.id`
    /// becomes the durable ProjectID, so existing installations do not fork
    /// identity on update.
    private func ensureLegacyMigration() async throws {
        guard !migrationChecked else { return }
        defer { migrationChecked = true }
        guard FileManager.default.fileExists(atPath: legacyAndRecentURL.path) else { return }

        let data = try Data(contentsOf: legacyAndRecentURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let legacy = try? decoder.decode(LegacyState.self, from: data) else { return }

        var recentEntries: [RecentProjectIndex.Entry] = []
        for item in legacy.items {
            let project = CrabrixProject(
                id: item.id,
                name: item.project.name,
                files: item.project.files,
                entryFile: item.project.entryFile,
                provenance: item.project.provenance
            )
            _ = try await store.save(
                project: project,
                lastBuild: item.lastBuild,
                at: item.lastOpenedAt
            )
            recentEntries.append(
                RecentProjectIndex.Entry(
                    projectID: project.id,
                    lastOpenedAt: item.lastOpenedAt
                )
            )
        }

        let recoveryURL = rootURL
            .appending(path: "recovery", directoryHint: .isDirectory)
            .appending(path: "recent-projects-v1.json")
        try FileManager.default.createDirectory(
            at: recoveryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: recoveryURL.path) {
            try data.write(to: recoveryURL, options: .atomic)
        }
        try await recent.replace(with: recentEntries)
    }
}
