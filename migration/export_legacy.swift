import CryptoKit
import Foundation

@main
enum LegacyAcademyExport {
    static func main() throws {
        guard CommandLine.arguments.count == 4 else {
            fputs("usage: legacy-export <source-sha> <content-version> <output-json>\n", stderr)
            exit(2)
        }
        let sourceSHA = CommandLine.arguments[1]
        let contentVersion = CommandLine.arguments[2]
        let output = URL(fileURLWithPath: CommandLine.arguments[3])
        var courses: [[String: Any]] = []
        var allIDs: [String: Set<String>] = [:]
        var collisions: [String] = []
        var missingWriting: [String] = []
        var missingChallenges: [String] = []

        func remember(_ kind: String, _ id: String) {
            if !(allIDs[kind, default: []].insert(id).inserted) {
                collisions.append("\(kind):\(id)")
            }
        }

        for (courseIndex, course) in RustCourseCatalog.courses.enumerated() {
            remember("course", course.id)
            var units: [[String: Any]] = []
            for (unitIndex, unit) in course.units.enumerated() {
                remember("unit", unit.id)
                var lessons: [[String: Any]] = []
                for (lessonIndex, lesson) in unit.lessons.enumerated() {
                    remember("lesson", lesson.id)
                    guard let writing = RustLessonLibrary.writing(for: lesson.id) else {
                        missingWriting.append(lesson.id)
                        continue
                    }
                    let depth = RustLessonDepthCatalog.depth(for: lesson)
                    var entry: [String: Any] = [
                        "id": lesson.id,
                        "parentID": unit.id,
                        "order": lessonIndex,
                        "title": lesson.title,
                        "concept": lesson.concept,
                        "minutes": lesson.minutes,
                        "exerciseKind": exerciseKind(lesson.exercise),
                        "writing": writingJSON(writing),
                        "depth": depthJSON(depth),
                        "evidence": evidenceJSON(lesson.evidence),
                    ]
                    if let pattern = AlgorithmCourseCatalog.pattern(forLessonID: lesson.id),
                       let stage = AlgorithmCourseCatalog.stage(forLessonID: lesson.id) {
                        entry["algorithm"] = [
                            "patternID": pattern.id,
                            "stage": stage.rawValue,
                            "difficulty": pattern.difficulty.rawValue,
                            "categoryID": pattern.categoryID,
                            "categoryTitle": pattern.categoryTitle,
                            "idea": pattern.idea,
                            "useCases": pattern.useCases,
                            "complexity": pattern.complexity,
                            "task": pattern.task,
                            "visibleInput": pattern.visibleInput,
                            "expectedAnswer": pattern.expectedAnswer,
                            "rustSketch": pattern.rustSketch,
                        ] as [String: Any]
                    }
                    if case .algorithmChallenge = lesson.exercise {
                        if let challenge = AlgorithmCourseCatalog.challenge(for: lesson.id) {
                            entry["challenge"] = challengeJSON(challenge)
                            entry["starterProject"] = projectJSON(
                                name: challenge.projectName,
                                entryFile: "solution.rs",
                                files: ["solution.rs": challenge.source]
                            )
                        } else {
                            missingChallenges.append(lesson.id)
                        }
                    } else {
                        switch lesson.exercise {
                        case .runnable:
                            entry["starterProject"] = projectJSON(name: "hello-crabrix", entryFile: "main.rs", files: ["main.rs": RustSamples.helloLesson])
                        case .borrowDiagnostic:
                            entry["starterProject"] = projectJSON(name: "borrow-lab", entryFile: "main.rs", files: ["main.rs": RustSamples.broken])
                        case .multiFile:
                            entry["starterProject"] = projectJSON(name: "modules-lab", entryFile: "src/main.rs", files: [
                                "Cargo.toml": RustSamples.cargoManifest,
                                "src/main.rs": RustSamples.multiFileMain,
                                "src/greeter.rs": RustSamples.multiFileGreeter,
                            ])
                        case .planned, .algorithmChallenge: break
                        }
                    }
                    entry["contentDigest"] = digest(entry)
                    lessons.append(entry)
                }
                var unitEntry: [String: Any] = [
                    "id": unit.id, "parentID": course.id, "order": unitIndex,
                    "level": unit.level, "title": unit.title,
                    "subtitle": unit.subtitle, "lessons": lessons,
                ]
                if course.id == "algorithms", let category = AlgorithmCourseCatalog.category(id: unit.id.replacingOccurrences(of: "algorithms-", with: "")) {
                    unitEntry["algorithmMethod"] = [
                        "id": category.id, "title": category.title,
                        "subtitle": category.subtitle,
                        "systemImage": category.systemImage,
                        "achievementTitle": category.achievementTitle,
                        "patternIDs": category.patterns.map(\.id),
                    ] as [String: Any]
                }
                unitEntry["contentDigest"] = digest(unitEntry)
                units.append(unitEntry)
            }
            var courseEntry: [String: Any] = [
                "id": course.id, "order": courseIndex, "language": "en",
                "contentVersion": contentVersion, "level": course.level,
                "title": course.title, "subtitle": course.subtitle,
                "systemImage": course.systemImage, "theme": course.theme.rawValue,
                "units": units,
            ]
            courseEntry["contentDigest"] = digest(courseEntry)
            courses.append(courseEntry)
        }

        let showcase = RustShowcaseLibrary.projects.enumerated().map { index, item -> [String: Any] in
            var entry: [String: Any] = [
                "id": item.id, "order": index, "title": item.title,
                "detail": item.detail, "systemImage": item.systemImage,
                "category": item.category.rawValue,
                "difficulty": item.difficulty.rawValue,
                "concepts": item.concepts,
                "project": projectJSON(name: item.project.name, entryFile: item.project.entryFile, files: item.project.files),
            ]
            entry["contentDigest"] = digest(entry)
            return entry
        }
        let termPairs = (
            RustBasicsExpansion.termPairs + RustAdvancedExpansion.termPairs + AlgorithmCourseCatalog.termPairs
        ).enumerated().map { index, pair -> [String: Any] in
            ["id": pair.id, "order": index, "term": pair.term,
             "description": pair.description, "topic": pair.topic]
        }
        let totals: [String: Int] = [
            "courses": courses.count,
            "units": courses.reduce(0) { $0 + ($1["units"] as! [[String: Any]]).count },
            "lessons": courses.reduce(0) { total, course in
                total + (course["units"] as! [[String: Any]]).reduce(0) { $0 + ($1["lessons"] as! [[String: Any]]).count }
            },
            "algorithmPatterns": AlgorithmCourseCatalog.patterns.count,
            "algorithmChallenges": AlgorithmCourseCatalog.challengeCount,
            "showcaseProjects": showcase.count,
            "termPairs": termPairs.count,
        ]
        var document: [String: Any] = [
            "schemaVersion": 1, "sourceSHA": sourceSHA,
            "contentVersion": contentVersion, "courses": courses,
            "showcaseProjects": showcase, "termPairs": termPairs,
            "totals": totals,
            "integrity": [
                "idCollisions": collisions.sorted(),
                "missingLessonWriting": missingWriting.sorted(),
                "missingChallenges": missingChallenges.sorted(),
            ],
            "media": [] as [String],
        ]
        document["contentDigest"] = digest(document)
        let data = try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys, .prettyPrinted, .fragmentsAllowed])
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: output, options: .atomic)
        print("Exported \(totals) to \(output.path)")
        if !collisions.isEmpty || !missingWriting.isEmpty || !missingChallenges.isEmpty { exit(1) }
    }

    private static func digest(_ object: [String: Any]) -> String {
        let bytes = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed])
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    private static func exerciseKind(_ exercise: RustLesson.Exercise) -> String {
        switch exercise {
        case .runnable: "runnable"
        case .borrowDiagnostic: "borrowDiagnostic"
        case .multiFile: "multiFile"
        case .algorithmChallenge: "algorithmChallenge"
        case .planned: "planned"
        }
    }

    private static func writingJSON(_ writing: RustLessonWriting) -> [String: Any] {
        ["summary": writing.summary, "explanation": writing.explanation,
         "exampleCaption": writing.exampleCaption, "exampleCode": writing.exampleCode,
         "task": writing.task, "success": writing.success, "rule": writing.rule,
         "practiceCode": writing.practiceCode, "question": writing.question,
         "answers": writing.answers, "correctAnswer": writing.correctAnswer,
         "feedback": writing.feedback]
    }

    private static func depthJSON(_ depth: RustLessonDepth) -> [String: Any] {
        ["traceSteps": depth.traceSteps.map { ["title": $0.title, "detail": $0.detail] },
         "misconception": depth.misconception, "correction": depth.correction,
         "transferChallenge": depth.transferChallenge,
         "connections": depth.connections.map { [
            "direction": $0.direction == .previous ? "previous" : "next",
            "title": $0.title, "concept": $0.concept,
         ] }]
    }

    private static func matcherJSON(_ matcher: LessonOutputMatcher) -> [String: Any] {
        switch matcher {
        case let .exact(value): ["kind": "exact", "value": value]
        case let .contains(value): ["kind": "contains", "value": value]
        case let .differsFrom(value): ["kind": "differsFrom", "value": value]
        }
    }

    private static func evidenceJSON(_ evidence: LessonEvidence) -> [String: Any] {
        switch evidence {
        case let .compilerRun(output, changed, files):
            ["kind": "compilerRun", "expectedOutput": matcherJSON(output),
             "requiresSourceChange": changed, "requiredFiles": files]
        case let .repair(code, output, fragments):
            ["kind": "repair", "removesDiagnostic": code,
             "expectedOutput": matcherJSON(output), "requiredSourceFragments": fragments]
        case let .algorithmChallenge(output, required, forbidden):
            ["kind": "algorithmChallenge", "expectedOutput": matcherJSON(output),
             "requiredSourceFragments": required, "forbiddenSourceFragments": forbidden]
        case let .reasoning(answer):
            ["kind": "reasoning", "correctAnswer": answer]
        }
    }

    private static func challengeJSON(_ challenge: AlgorithmChallenge) -> [String: Any] {
        ["lessonID": challenge.lessonID, "patternID": challenge.patternID,
         "projectName": challenge.projectName, "source": challenge.source,
         "verificationSource": challenge.verificationSource,
         "verificationCases": challenge.verificationCases.map { [
            "kind": $0.kind.rawValue, "input": $0.input,
            "expectedAnswer": $0.expectedAnswer,
         ] },
         "expectedOutput": challenge.expectedOutput,
         "requiredSourceFragments": challenge.requiredSourceFragments,
         "forbiddenSourceFragments": challenge.forbiddenSourceFragments]
    }

    private static func projectJSON(name: String, entryFile: String, files: [String: String]) -> [String: Any] {
        ["name": name, "entryFile": entryFile, "files": files]
    }
}
