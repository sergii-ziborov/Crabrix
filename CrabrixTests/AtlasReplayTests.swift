import XCTest
import ZIPFoundation
@testable import Crabrix

final class AtlasReplayTests: XCTestCase {
    private var fixtures: URL {
        Bundle(for: Self.self).url(forResource: "AtlasReplay", withExtension: nil)!
    }
    private func temporary() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "atlas-qa-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func catalog() throws -> CourseCatalogPayload {
        try CoursePackVerifier.catalog(bytes: Data(contentsOf: fixtures.appending(path: "catalog.v1.json")),
            keyring: CourseBootstrap().keyring(), lastAcceptedSequence: 0)
    }
    private func library(_ root: URL) throws -> AtlasReplayLibrary {
        try AtlasReplayLibrary(root: root.appending(path: "material"), cacheRoot: root.appending(path: "cache"),
            catalogBytes: Data(contentsOf: fixtures.appending(path: "catalog.v1.json")))
    }
    private func bytes(_ archive: Archive, _ path: String) throws -> Data {
        var result = Data()
        _ = try archive.extract(try XCTUnwrap(archive[path])) { result.append($0) }
        return result
    }

    func testEverySignedSectionAndAll600LessonRecordingsLoadWithoutNetwork() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let library = try library(root)
        var lessons = 0, recordings = Set<String>(), observedKinds = Set<String>()
        for entry in try catalog().courses {
            let method = String(entry.courseID.dropFirst(6))
            let before = try await library.section(method); XCTAssertFalse(before.isInstalled)
            try await library.install(method,
                descriptor: Data(contentsOf: fixtures.appending(path: entry.descriptorURL.lastPathComponent)),
                archive: fixtures.appending(path: entry.archiveURL.lastPathComponent))
            let after = try await library.section(method); XCTAssertTrue(after.isInstalled)
            let archive = try Archive(url: fixtures.appending(path: entry.archiveURL.lastPathComponent), accessMode: .read)
            let index = try JSONDecoder().decode(AtlasReplayLibrary.Index.self, from: bytes(archive, "index.json"))
            for (id, item) in index.lessons {
                let raw = try JSONSerialization.jsonObject(with: bytes(archive, "traces/\(item.key).json")) as! [String: Any]
                let source = raw["source"] as! String
                let recording = try await library.recording(method: method, lessonID: id, source: source)
                XCTAssertEqual(recording.replay.sourceHash, item.sourceHash)
                XCTAssertEqual(recording.replay.category, method)
                XCTAssertEqual(recording.previousFrameIndices.count, recording.replay.frames.count)
                for (i, previous) in recording.previousFrameIndices.enumerated() {
                    if let previous {
                        XCTAssertLessThan(previous, i)
                        XCTAssertEqual(recording.replay.frames[i].stack.last?.activation,
                                       recording.replay.frames[previous].stack.last?.activation)
                    }
                }
                for value in recording.replay.values {
                    switch value.data {
                    case .scalar: observedKinds.insert("scalar")
                    case .list: observedKinds.insert("list")
                    case .map: observedKinds.insert("map")
                    case .named: observedKinds.insert("named")
                    case .set: observedKinds.insert("set")
                    }
                }
                lessons += 1; recordings.insert(recording.replay.key)
            }
        }
        XCTAssertEqual(lessons, 600); XCTAssertEqual(recordings.count, 400)
        XCTAssertEqual(observedKinds, Set(["scalar", "list", "map", "named", "set"]))
    }

    func testStaleSourceTamperingAndRemovalKeepPersonalWorkAndProgress() async throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appending(path: "personal.rs"), progress = root.appending(path: "progress.json")
        try Data("fn main() { println!(\"my edited program\"); }".utf8).write(to: project)
        try Data("{\"completed\":true}".utf8).write(to: progress)
        let library = try library(root), entry = try XCTUnwrap(catalog().courses.first)
        let method = String(entry.courseID.dropFirst(6))
        let archiveURL = fixtures.appending(path: entry.archiveURL.lastPathComponent)
        let descriptor = try Data(contentsOf: fixtures.appending(path: entry.descriptorURL.lastPathComponent))
        try await library.install(method, descriptor: descriptor, archive: archiveURL)
        let archive = try Archive(url: archiveURL, accessMode: .read)
        let index = try JSONDecoder().decode(AtlasReplayLibrary.Index.self, from: bytes(archive, "index.json"))
        let lesson = try XCTUnwrap(index.lessons.first)
        let trace = try bytes(archive, "traces/\(lesson.value.key).json")
        let source = (try JSONSerialization.jsonObject(with: trace) as! [String: Any])["source"] as! String
        do {
            _ = try await library.recording(method: method, lessonID: lesson.key, source: source + "\n// changed")
            XCTFail("Stale source accepted")
        } catch AtlasReplayError.changedSource { }
        let base = root.appending(path: "material/\(entry.courseID)/en/\(entry.contentVersion)")
        let path = base.appending(path: "traces/\(lesson.value.key).json")
        try Data("{}".utf8).write(to: path)
        do {
            _ = try await library.recording(method: method, lessonID: lesson.key, source: source)
            XCTFail("Modified recording accepted")
        } catch { XCTAssertTrue(error.localizedDescription.contains("digest")) }
        try await library.remove(method)
        let section = try await library.section(method); XCTAssertFalse(section.isInstalled)
        XCTAssertEqual(try String(contentsOf: project, encoding: .utf8), "fn main() { println!(\"my edited program\"); }")
        XCTAssertEqual(try String(contentsOf: progress, encoding: .utf8), "{\"completed\":true}")
        try await library.install(method, descriptor: descriptor, archive: archiveURL)
        _ = try await library.recording(method: method, lessonID: lesson.key, source: source)
        var altered = descriptor; altered[altered.startIndex] ^= 1
        do { try await library.install(method, descriptor: altered, archive: archiveURL); XCTFail("Modified signature accepted") }
        catch { }
        _ = try await library.recording(method: method, lessonID: lesson.key, source: source)
    }

    func testExactLargeIntegersAndMalformedExecutionReferences() throws {
        let exact = "18446744073709551615"
        let scalar = try JSONDecoder().decode(AtlasValue.self, from: Data("{\"kind\":\"scalar\",\"text\":\"\(exact)\"}".utf8))
        XCTAssertEqual(scalar.text, exact)
        XCTAssertThrowsError(try JSONDecoder().decode(AtlasValue.self, from: Data("{\"kind\":\"scalar\",\"text\":18446744073709551615}".utf8)))
        var nested = AtlasValue.scalar("0")
        for _ in 0..<34 { nested = .named("Nested", nested) }
        var nodes = 0
        XCTAssertThrowsError(try nested.validate(nodes: &nodes))
        let entry = try XCTUnwrap(catalog().courses.first)
        let archive = try Archive(url: fixtures.appending(path: entry.archiveURL.lastPathComponent), accessMode: .read)
        let index = try JSONDecoder().decode(AtlasReplayLibrary.Index.self, from: bytes(archive, "index.json"))
        let key = try XCTUnwrap(index.lessons.first?.value.key)
        let data = try bytes(archive, "traces/\(key).json")
        let original = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let source = original["source"] as! String
        var altered = original
        altered["frames"] = [["site": 999_999, "stack": [["main", 1]], "locals": []],
                             ["site": 0, "stack": [["main", 1]], "locals": []]]
        XCTAssertThrowsError(try AtlasReplay.decode(JSONSerialization.data(withJSONObject: altered),
                                                   expectedSource: source, expectedKey: key))
        altered = original; altered["values"] = [["type": "i32", "data": ["kind": "map", "entries": [[]]]]]
        XCTAssertThrowsError(try AtlasReplay.decode(JSONSerialization.data(withJSONObject: altered),
                                                   expectedSource: source, expectedKey: key))
    }

    func testGraphDirectionsWeightsAndLinkedNodesRetainRecordedMeaning() throws {
        let graph = try XCTUnwrap(AtlasGraph(value: .list([
            .list([.list([.scalar("1"), .scalar("18446744073709551615")], tuple: true)], tuple: false),
            .list([.list([.scalar("0"), .scalar("11")], tuple: true),
                   .list([.scalar("1"), .scalar("13")], tuple: true)], tuple: false)
        ], tuple: false)))
        XCTAssertEqual(graph.count, 2)
        XCTAssertEqual(graph.edges.map { "\($0.from)→\($0.to):\($0.weight ?? "")" },
                       ["0→1:18446744073709551615", "1→0:11", "1→1:13"])
        XCTAssertNil(AtlasGraph(value: .list([.list([.scalar("9")], tuple: false)], tuple: false)))
        func node(_ value: String, next: AtlasValue) -> AtlasValue {
            .named("Some", .list([.named("Node", .map([
                [.scalar("value"), .scalar(value)], [.scalar("next"), next]
            ]))], tuple: true))
        }
        let tree = try XCTUnwrap(AtlasTree(value: node("1", next: node("2", next: node("3", next: .scalar("None"))))))
        XCTAssertEqual(tree.nodes.map(\.label), ["1", "2", "3"])
        XCTAssertEqual(tree.edges.map(\.label), ["next", "next"])
        XCTAssertEqual(tree.edges.count, 2)
        XCTAssertTrue(tree.nodes.allSatisfy { $0.x >= 0 && $0.x <= tree.width && $0.y >= 0 && $0.y <= tree.height })
        XCTAssertNil(AtlasTree(value: .scalar("None")))
    }

    @MainActor
    func testPreparedLessonCopyChangesRunsAndDebugsWithoutReusingOriginalRecording() async throws {
        let bootstrap = try CourseBootstrap()
        let entries = CourseUpdatePlanner.latestCompatible(in: try bootstrap.bundledCatalog(), appVersion: bootstrap.appVersion)
        let entry = try XCTUnwrap(entries["algorithms|en"])
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let archive = caches.appending(path: "Crabrix/CourseDownloads/\(entry.archiveSHA256).zip")
        guard FileManager.default.fileExists(atPath: archive.path) else {
            throw XCTSkip("Prepare the actual public algorithms course with the Simulator UI fixture first; this case itself never downloads.")
        }
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let descriptor = try Data(contentsOf: fixtures.appending(path: "current-algorithms.descriptor.json"))
        XCTAssertEqual(AtlasReplay.digest(descriptor), entry.descriptorSHA256)
        let installer = try CourseInstaller(root: root.appending(path: "course"), appVersion: bootstrap.appVersion)
        _ = try await installer.install(descriptorBytes: descriptor, downloadedArchive: archive, keyring: bootstrap.keyring())
        let repository = try await installer.loadRepository(keyring: bootstrap.keyring())
        let lessonID = "algorithm.linear-scan.model", method = "scans"
        let session = try XCTUnwrap(CourseSession(lessonID: lessonID, repository: repository))
        let original = try XCTUnwrap(repository.writing(for: lessonID)?.exampleCode)
        let library = try library(root)
        let replayEntry = try XCTUnwrap(catalog().courses.first { $0.courseID == "atlas-scans" })
        try await library.install(method,
            descriptor: Data(contentsOf: fixtures.appending(path: replayEntry.descriptorURL.lastPathComponent)),
            archive: fixtures.appending(path: replayEntry.archiveURL.lastPathComponent))
        let recording = try await library.recording(method: method, lessonID: lessonID, source: original)
        let suite = "AtlasCopyQA-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let projects = ProjectLibrary(storageURL: root.appending(path: "personal-index.json"))
        let model = CompilerViewModel(projectLibrary: projects, userDefaults: defaults)
        let completed = model.completedLessonIDs
        XCTAssertTrue(model.openAtlasRecording(recording, session: session))
        XCTAssertNil(model.activeLessonID)
        XCTAssertEqual(model.source, original)
        XCTAssertEqual(model.provenance?.course?.recording?.sourceHash, recording.replay.sourceHash)
        model.source = model.source.replacingOccurrences(of: "&[4, 9, -2, 7]", with: "&[4, -9, -2, 7]")
        XCTAssertNotEqual(model.source, original)
        model.run()
        try await wait(model)
        XCTAssertTrue(model.result?.succeeded == true, model.result?.detail ?? "No result")
        XCTAssertEqual(model.result?.stdout, "1\n")
        model.debug()
        var observedPause = false
        let start = ContinuousClock.now
        while model.isBusy || model.isCompilerDraining {
            guard start.duration(to: .now) < .seconds(90) else {
                model.cancelBuild(); XCTFail("Personal Debug did not finish"); return
            }
            if model.debugPause != nil { observedPause = true; model.resumeDebug(.continue) }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(observedPause)
        XCTAssertTrue(model.result?.succeeded == true, model.result?.detail ?? "No Debug result")
        XCTAssertEqual(model.result?.stdout, "1\n")
        XCTAssertEqual(recording.replay.stdout, "2\n")
        XCTAssertEqual(model.completedLessonIDs, completed)
        XCTAssertTrue(model.lessonAttemptEvidence.isEmpty)
        await model.retryProjectSave()
        let exported = model.exportProject()
        let restored = try JSONDecoder().decode(CrabrixProject.self, from: JSONEncoder().encode(exported))
        XCTAssertEqual(restored.files, exported.files)
        XCTAssertEqual(restored.provenance?.course?.recording?.input, recording.replay.input)
        XCTAssertEqual(restored.provenance?.course?.lessonID, lessonID)
        try await library.remove(method)
        XCTAssertEqual(model.source, exported.files[exported.entryFile])
        XCTAssertEqual(model.completedLessonIDs, completed)
        XCTAssertEqual(repository.writing(for: lessonID)?.exampleCode, original)
    }

    @MainActor
    private func wait(_ model: CompilerViewModel) async throws {
        let start = ContinuousClock.now
        while model.isBusy || model.isCompilerDraining {
            guard start.duration(to: .now) < .seconds(90) else {
                model.cancelBuild(); XCTFail("Personal run did not finish"); return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
