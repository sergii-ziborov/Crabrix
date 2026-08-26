import Foundation

actor ProjectLibrary {
    private struct State: Codable {
        var items: [ProjectLibraryItem]
    }

    private let storageURL: URL
    private var cachedState: State?
    private let maximumRecentProjects = 10

    init(storageURL: URL? = nil) {
        if let storageURL {
            self.storageURL = storageURL
        } else {
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.temporaryDirectory
            self.storageURL = applicationSupport
                .appending(path: "Crabrix", directoryHint: .isDirectory)
                .appending(path: "recent-projects.json")
        }
    }

    func items() throws -> [ProjectLibraryItem] {
        try state().items.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    }

    func project(id: UUID) throws -> ProjectLibraryItem? {
        try state().items.first { $0.id == id }
    }

    @discardableResult
    func record(
        project: CrabrixProject,
        lastBuild: ProjectBuildRecord?
    ) throws -> [ProjectLibraryItem] {
        var current = try state()
        let key = projectKey(project)
        if let index = current.items.firstIndex(where: { projectKey($0.project) == key }) {
            current.items[index].project = project
            current.items[index].lastOpenedAt = Date()
            if let lastBuild { current.items[index].lastBuild = lastBuild }
        } else {
            current.items.append(
                ProjectLibraryItem(
                    id: UUID(),
                    project: project,
                    lastOpenedAt: Date(),
                    lastBuild: lastBuild
                )
            )
        }
        current.items.sort { $0.lastOpenedAt > $1.lastOpenedAt }
        if current.items.count > maximumRecentProjects {
            current.items.removeLast(current.items.count - maximumRecentProjects)
        }
        try persist(current)
        return current.items
    }

    private func state() throws -> State {
        if let cachedState { return cachedState }
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            let state = State(items: [])
            cachedState = state
            return state
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let state = try decoder.decode(State.self, from: Data(contentsOf: storageURL))
        cachedState = state
        return state
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

    private func projectKey(_ project: CrabrixProject) -> String {
        if let provenance = project.provenance,
           provenance.source == .github,
           let owner = provenance.owner,
           let repository = provenance.repository {
            return "github:\(owner.lowercased())/\(repository.lowercased())@\(provenance.reference ?? "HEAD")"
        }
        return "local:\(project.name.lowercased())"
    }
}
