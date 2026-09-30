import CryptoKit
import Foundation

/// Loads only activated, previously verified CoursePack directories.
struct InstalledCourseRepository: CourseRepository {
    let courses: [RustCourse]
    let loaded: [String: LoadedCourse]

    init(root: URL, records: [InstalledCourseRecord], keyring: CourseKeyring) throws {
        var collected: [String: LoadedCourse] = [:]
        var lessonIDs = Set<String>()
        for record in records {
            let course = try Self.load(root: root, record: record, keyring: keyring)
            guard collected[course.course.id] == nil else {
                throw CoursePackError.manifestMismatch("duplicate course ID")
            }
            for lesson in course.course.units.flatMap(\.lessons) {
                guard lessonIDs.insert(lesson.id).inserted else {
                    throw CoursePackError.manifestMismatch("duplicate lesson \(lesson.id)")
                }
            }
            collected[course.course.id] = course
        }
        loaded = collected
        courses = collected.values.sorted { $0.order < $1.order }.map(\.course)
    }

    func writing(for lessonID: String) -> RustLessonWriting? {
        loaded.values.lazy.compactMap { $0.writing[lessonID] }.first
    }

    func depth(for lessonID: String) -> RustLessonDepth? {
        loaded.values.lazy.compactMap { $0.depth[lessonID] }.first
    }

    func evidence(for lessonID: String) -> LessonEvidence? {
        loaded.values.lazy.compactMap { $0.evidence[lessonID] }.first
    }

    func starterProject(for lessonID: String) -> CourseProjectTemplate? {
        loaded.values.lazy.compactMap { $0.projects[lessonID] }.first
    }

    func challenge(for lessonID: String) -> CourseChallengeDTO? {
        loaded.values.lazy.compactMap { $0.challenges[lessonID] }.first
    }

    func termPairs() -> [CourseTermPairDTO] {
        loaded.values.flatMap(\.terms).sorted { $0.order < $1.order }
    }

    private static func load(root: URL, record: InstalledCourseRecord,
                             keyring: CourseKeyring) throws -> LoadedCourse {
        let courseID = try component(record.courseID)
        let language = try component(record.language)
        let version = try component(record.contentVersion)
        let directory = root.appending(path: "\(courseID)/\(language)/\(version)")
        let descriptorBytes = try Data(base64Encoded: record.descriptorBase64)
            .unwrap(or: CoursePackError.invalidEnvelope)
        let (payload, keyID) = try CoursePackVerifier.signedPayload(
            descriptorBytes, domain: CoursePackVerifier.descriptorDomain, keyring: keyring
        )
        let descriptor = try JSONDecoder().decode(CourseDescriptorPayload.self, from: payload)
        guard descriptor.courseID == courseID, descriptor.language == language,
              descriptor.contentVersion == version,
              descriptor.archiveSHA256 == record.archiveSHA256,
              keyID == record.keyID else { throw CoursePackError.invalidEnvelope }
        let manifestURL = directory.appending(path: "manifest.json")
        let manifest = try JSONDecoder().decode(CoursePackManifest.self,
                                                 from: Data(contentsOf: manifestURL))
        guard manifest.schemaVersion == 1, manifest.courseID == courseID,
              manifest.language == language, manifest.contentVersion == version else {
            throw CoursePackError.manifestMismatch("manifest.json")
        }
        try verifyInstalledTree(directory: directory, manifest: manifest)

        func decode<T: Decodable>(_ path: String, as _: T.Type) throws -> T {
            try JSONDecoder().decode(T.self, from: Data(contentsOf: directory.appending(path: path)))
        }

        let source: CourseDTO = try decode("course.json", as: CourseDTO.self)
        guard source.id == courseID, source.language == language,
              source.contentVersion == version,
              let theme = RustCourseTheme(rawValue: source.theme) else {
            throw CoursePackError.manifestMismatch("course.json")
        }
        var units: [RustLearningUnit] = []
        var writings: [String: RustLessonWriting] = [:]
        var depths: [String: RustLessonDepth] = [:]
        var evidence: [String: LessonEvidence] = [:]
        var projects: [String: CourseProjectTemplate] = [:]
        var challenges: [String: CourseChallengeDTO] = [:]
        for (unitOrder, unitID) in source.unitIDs.enumerated() {
            let safeUnit = try component(unitID)
            let unit: CourseUnitDTO = try decode("units/\(safeUnit).json", as: CourseUnitDTO.self)
            guard unit.id == unitID, unit.parentID == courseID, unit.order == unitOrder else {
                throw CoursePackError.manifestMismatch("unit \(unitID)")
            }
            var lessons: [RustLesson] = []
            for (lessonOrder, lessonID) in unit.lessonIDs.enumerated() {
                let safeLesson = try component(lessonID)
                let lesson: CourseLessonDTO = try decode("lessons/\(safeLesson).json",
                                                         as: CourseLessonDTO.self)
                let check: CourseCheckDTO = try decode("checks/\(safeLesson).json",
                                                       as: CourseCheckDTO.self)
                guard lesson.id == lessonID, lesson.parentID == unitID,
                      lesson.order == lessonOrder,
                      writings[lessonID] == nil else {
                    throw CoursePackError.manifestMismatch("lesson \(lessonID)")
                }
                let writing = try lesson.writing.runtimeWriting()
                let proof = try check.evidence.runtimeEvidence()
                if case let .reasoning(correctAnswer) = proof,
                   correctAnswer != writing.correctAnswer {
                    throw CoursePackError.manifestMismatch("answer \(lessonID)")
                }
                writings[lessonID] = writing
                depths[lessonID] = try lesson.depth.runtimeDepth()
                evidence[lessonID] = proof
                lessons.append(try lesson.runtimeLesson())
                if let challenge = check.challenge {
                    guard challenge.lessonID == lessonID else {
                        throw CoursePackError.manifestMismatch("challenge \(lessonID)")
                    }
                    challenges[lessonID] = challenge
                }
                if manifest.files.contains(where: { $0.path == "projects/\(lessonID)/project.json" }) {
                    struct Metadata: Decodable { let name: String; let entryFile: String }
                    let prefix = "projects/\(safeLesson)/"
                    let metadata: Metadata = try decode(prefix + "project.json", as: Metadata.self)
                    var files: [String: String] = [:]
                    for item in manifest.files where item.path.hasPrefix(prefix) && item.path != prefix + "project.json" {
                        let relative = String(item.path.dropFirst(prefix.count))
                        files[relative] = try String(contentsOf: directory.appending(path: item.path),
                                                     encoding: .utf8)
                    }
                    guard files[metadata.entryFile] != nil else {
                        throw CoursePackError.manifestMismatch("project \(lessonID)")
                    }
                    projects[lessonID] = CourseProjectTemplate(
                        name: metadata.name, entryFile: metadata.entryFile, files: files
                    )
                }
            }
            units.append(RustLearningUnit(
                id: unit.id, level: unit.level, title: unit.title,
                subtitle: unit.subtitle, lessons: lessons
            ))
        }
        let terms: [CourseTermPairDTO] = try decode("terms.json", as: [CourseTermPairDTO].self)
        let runtime = RustCourse(
            id: source.id, level: source.level, title: source.title,
            subtitle: source.subtitle, systemImage: source.systemImage,
            theme: theme, units: units
        )
        return LoadedCourse(
            course: runtime, order: source.order, writing: writings, depth: depths, evidence: evidence,
            projects: projects, challenges: challenges, terms: terms,
            contentVersion: version, archiveSHA256: record.archiveSHA256
        )
    }

    private static func verifyInstalledTree(directory: URL, manifest: CoursePackManifest) throws {
        let files = try FileManager.default.subpathsOfDirectory(atPath: directory.path)
        var actual = Set<String>()
        for path in files {
            let safe = try CoursePackVerifier.validatedPath(path)
            let url = directory.appending(path: safe)
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw CoursePackError.unsafeArchive(safe) }
            if values.isRegularFile == true { actual.insert(safe) }
        }
        let expected = Set(manifest.files.map(\.path)).union(["manifest.json"])
        guard actual == expected, manifest.files.count + 1 == actual.count else {
            throw CoursePackError.manifestMismatch("installed tree")
        }
        guard manifest.files.count <= CoursePackVerifier.maximumEntries else {
            throw CoursePackError.sizeLimit
        }
        var total = 0
        for item in manifest.files {
            let path = try CoursePackVerifier.validatedPath(item.path)
            guard item.bytes >= 0, item.bytes <= CoursePackVerifier.maximumFileBytes else {
                throw CoursePackError.sizeLimit
            }
            total += item.bytes
            guard total <= CoursePackVerifier.maximumUnpackedBytes else { throw CoursePackError.sizeLimit }
            let url = directory.appending(path: path)
            let bytes = try Data(contentsOf: url)
            guard bytes.count == item.bytes,
                  SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == item.sha256
            else { throw CoursePackError.manifestMismatch(path) }
        }
    }

    private static func component(_ value: String) throws -> String {
        let safe = try CoursePackVerifier.validatedPath(value)
        guard !safe.contains("/") else { throw CoursePackError.unsafeArchive(value) }
        return safe
    }
}

private extension Optional {
    func unwrap(or error: Error) throws -> Wrapped {
        guard let self else { throw error }
        return self
    }
}
