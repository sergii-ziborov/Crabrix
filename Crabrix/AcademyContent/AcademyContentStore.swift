import Foundation
import SwiftUI

@MainActor
final class AcademyContentStore: ObservableObject {
    enum TransferState: Equatable {
        case downloading(Int, Int)
        case verifying
        case installed
        case failed(String)
    }

    @Published private(set) var repository: InstalledCourseRepository?
    @Published private(set) var loading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var catalog: CourseCatalogPayload?
    @Published private(set) var catalogError: String?
    @Published private(set) var checkingForUpdates = false
    @Published private(set) var updatingAll = false
    @Published private(set) var transfers: [String: TransferState] = [:]
    private let initialInstallMode: CourseInitialInstallMode
    private var preparing: Task<InstalledCourseRepository, Error>?
    private var downloadTasks: [String: Task<Void, Never>] = [:]
    private var bulkUpdateTask: Task<Void, Never>?

    private var latestCompatible: [String: CourseCatalogPayload.Entry] {
        let appVersion = (try? CourseBootstrap().appVersion)
            ?? SemanticVersion(major: 0, minor: 0, patch: 0)
        return CourseUpdatePlanner.latestCompatible(in: catalog, appVersion: appVersion)
    }

    private var installedVersions: [String: String] {
        guard let repository else { return [:] }
        return Dictionary(uniqueKeysWithValues: repository.loaded.values.map {
            ("\($0.course.id)|\($0.language)", $0.contentVersion)
        })
    }

    var availableUpdates: [CourseCatalogPayload.Entry] {
        CourseUpdatePlanner.updates(latest: latestCompatible, installedVersions: installedVersions)
    }

    var availableDownloads: [CourseCatalogPayload.Entry] {
        latestCompatible.filter { installedVersions[$0.key] == nil }.map(\.value)
    }

    func updateEntry(for courseID: String, language: String = "en") -> CourseCatalogPayload.Entry? {
        availableUpdates.first { $0.courseID == courseID && $0.language == language }
    }

    init(initialInstallMode: CourseInitialInstallMode) {
        self.initialInstallMode = initialInstallMode
    }

    func prepare() async {
        guard repository == nil else { return }
        if let preparing {
            _ = try? await preparing.value
            return
        }
        loading = true
        let task = Task {
            let bootstrap = try CourseBootstrap()
            return try await bootstrap.activateBundledBaseline(for: initialInstallMode)
        }
        preparing = task
        defer { loading = false; preparing = nil }
        do {
            repository = try await task.value
            if catalog == nil, let bootstrap = try? CourseBootstrap(),
               let keyring = try? bootstrap.keyring() {
                let client = CourseCatalogClient(
                    stateURL: bootstrap.root.appending(path: "catalog-state.json"),
                    keyring: keyring
                )
                catalog = (try? await client.current()) ?? (try? bootstrap.bundledCatalog())
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func checkForUpdates() async {
        guard !checkingForUpdates else { return }
        checkingForUpdates = true
        defer { checkingForUpdates = false }
        do {
            let bootstrap = try CourseBootstrap()
            let client = CourseCatalogClient(
                stateURL: bootstrap.root.appending(path: "catalog-state.json"),
                keyring: try bootstrap.keyring()
            )
            catalog = try await client.refresh()
            catalogError = nil
        } catch {
            catalogError = error.localizedDescription
        }
    }

    func download(_ entry: CourseCatalogPayload.Entry) {
        _ = startDownload(entry)
    }

    func updateAll() {
        guard bulkUpdateTask == nil else { return }
        let entries = availableUpdates.sorted { $0.courseID < $1.courseID }
        guard !entries.isEmpty else { return }
        updatingAll = true
        bulkUpdateTask = Task { [weak self] in
            guard let self else { return }
            for entry in entries {
                if let task = startDownload(entry) { await task.value }
            }
            updatingAll = false
            bulkUpdateTask = nil
        }
    }

    @discardableResult
    private func startDownload(_ entry: CourseCatalogPayload.Entry) -> Task<Void, Never>? {
        let key = entry.courseID + "|" + entry.language
        guard latestCompatible[key]?.archiveSHA256 == entry.archiveSHA256 else {
            transfers[key] = .failed("The course catalog changed. Refresh and try again.")
            return nil
        }
        if let task = downloadTasks[key] { return task }
        transfers[key] = .downloading(0, entry.archiveBytes)
        let task = Task { [weak self] in
            guard let self else { return }
            defer { downloadTasks[key] = nil }
            do {
                let bootstrap = try CourseBootstrap()
                let manager = try CourseDownloadManager()
                let (descriptor, archive) = try await manager.download(entry) { [weak self] received, total in
                    Task { @MainActor [weak self] in
                        self?.transfers[key] = .downloading(received, total)
                    }
                }
                transfers[key] = .verifying
                let installer = try CourseInstaller(root: bootstrap.root, appVersion: bootstrap.appVersion)
                _ = try await installer.install(
                    descriptorBytes: descriptor, downloadedArchive: archive,
                    keyring: bootstrap.keyring()
                )
                repository = try await bootstrap.loadInstalled()
                transfers[key] = .installed
            } catch {
                transfers[key] = .failed(Task.isCancelled
                    ? "Download paused. Tap Resume to continue."
                    : error.localizedDescription)
            }
        }
        downloadTasks[key] = task
        return task
    }

    func cancelDownload(courseID: String, language: String) {
        downloadTasks[courseID + "|" + language]?.cancel()
    }

    func deleteInstalled(courseID: String, language: String) async {
        let key = courseID + "|" + language
        guard downloadTasks[key] == nil else {
            errorMessage = "Pause the current course download before removing its local material."
            return
        }
        do {
            let bootstrap = try CourseBootstrap()
            let installer = try CourseInstaller(root: bootstrap.root, appVersion: bootstrap.appVersion)
            try await installer.uninstall(courseID: courseID, language: language)
            repository = try await bootstrap.loadInstalled()
            transfers.removeValue(forKey: key)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
