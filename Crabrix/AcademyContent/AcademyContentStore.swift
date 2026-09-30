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
    @Published private(set) var transfers: [String: TransferState] = [:]
    private var preparing: Task<InstalledCourseRepository, Error>?
    private var downloadTasks: [String: Task<Void, Never>] = [:]

    func prepare() async {
        guard repository == nil else { return }
        if let preparing {
            _ = try? await preparing.value
            return
        }
        loading = true
        let task = Task {
            let bootstrap = try CourseBootstrap()
            return try await bootstrap.activateBundledBaseline()
        }
        preparing = task
        defer { loading = false; preparing = nil }
        do {
            repository = try await task.value
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func checkForUpdates() async {
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
        let key = entry.courseID + "|" + entry.language
        guard downloadTasks[key] == nil else { return }
        transfers[key] = .downloading(0, entry.archiveBytes)
        downloadTasks[key] = Task { [weak self] in
            guard let self else { return }
            defer { downloadTasks[key] = nil }
            do {
                let bootstrap = try CourseBootstrap()
                let manager = try CourseDownloadManager()
                let (descriptor, archive) = try await manager.download(entry) { received, total in
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
    }

    func cancelDownload(courseID: String, language: String) {
        downloadTasks[courseID + "|" + language]?.cancel()
    }
}
