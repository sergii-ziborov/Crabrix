import XCTest
@testable import Crabrix

final class RustLessonProgressionTests: XCTestCase {
    private func successfulRun(stdout: String) -> CompilationResult {
        CompilationResult(
            succeeded: true,
            phase: .run,
            exitCode: 0,
            diagnostics: [],
            stdout: stdout,
            stderr: "",
            duration: .milliseconds(1),
            detail: "fixture"
        )
    }

    func testCatalogFindsCourseAndLessonByStableIdentifiers() throws {
        let course = try XCTUnwrap(RustCourseCatalog.course(id: "basics"))
        let lesson = try XCTUnwrap(RustCourseCatalog.lesson(id: "variables"))

        XCTAssertEqual(course.title, "Rust Basics")
        XCTAssertEqual(lesson.title, "Variables")
        XCTAssertEqual(
            RustCourseCatalog.course(containingLessonID: lesson.id)?.id,
            course.id
        )
    }

    func testCatalogReturnsNilForUnknownIdentifiers() {
        XCTAssertNil(RustCourseCatalog.course(id: "missing-course"))
        XCTAssertNil(RustCourseCatalog.lesson(id: "missing-lesson"))
        XCTAssertNil(RustCourseCatalog.course(containingLessonID: "missing-lesson"))
    }

    func testSuccessfulFirstLessonUnlocksVariables() throws {
        let basics = try XCTUnwrap(RustCourseCatalog.courses.first { $0.id == "basics" })

        XCTAssertEqual(
            RustLessonProgression.nextLessonID(
                in: basics.units,
                completedLessonIDs: ["hello-rust"]
            ),
            "variables"
        )
        XCTAssertEqual(
            RustLessonProgression.completedCount(
                in: basics.units,
                completedLessonIDs: ["hello-rust"]
            ),
            1
        )
    }

    func testRustBasicsIsAFullGradualTwentyEightLessonCourse() throws {
        let basics = try XCTUnwrap(RustCourseCatalog.course(id: "basics"))
        let lessons = RustLessonProgression.lessons(in: basics.units)

        XCTAssertEqual(basics.units.count, 4)
        XCTAssertEqual(lessons.count, 28)
        XCTAssertEqual(lessons.prefix(2).map(\.id), ["hello-rust", "variables"])
        XCTAssertEqual(lessons.last?.id, "derive")
    }

    func testCourseCompletesWhenEveryLessonIDIsRecorded() throws {
        let basics = try XCTUnwrap(RustCourseCatalog.courses.first { $0.id == "basics" })
        let completed = Set(RustLessonProgression.lessons(in: basics.units).map(\.id))

        XCTAssertNil(
            RustLessonProgression.nextLessonID(
                in: basics.units,
                completedLessonIDs: completed
            )
        )
        // Derived rather than hardcoded, so growing the curriculum does not
        // break a test that is really about the counting logic.
        XCTAssertEqual(
            RustLessonProgression.completedCount(
                in: basics.units,
                completedLessonIDs: completed
            ),
            completed.count
        )
        XCTAssertGreaterThan(completed.count, 0)
    }

    func testSuccessfulRunDoesNotCompleteUnchangedHelloStarter() throws {
        let lesson = try XCTUnwrap(RustCourseCatalog.lesson(id: "hello-rust"))
        let project = CrabrixProject(
            name: "hello",
            files: ["main.rs": RustSamples.helloLesson],
            entryFile: "main.rs",
            provenance: nil
        )
        let hash = WorkspaceRevision.capture(
            project: project,
            generation: 0,
            toolchainID: "test"
        ).sourceTreeHash

        let validation = LessonEvidenceValidator.validateCompilerAttempt(
            evidence: lesson.evidence,
            result: successfulRun(stdout: "Hello, Crabrix!\n"),
            project: project,
            initialSourceTreeHash: hash,
            currentSourceTreeHash: hash,
            observedDiagnosticCodes: []
        )

        XCTAssertFalse(validation.passed)
        XCTAssertTrue(validation.detail.contains("unchanged"))
    }

    func testEditedHelloOutputPassesItsSpecificValidator() throws {
        let lesson = try XCTUnwrap(RustCourseCatalog.lesson(id: "hello-rust"))
        let project = CrabrixProject(
            name: "hello",
            files: ["main.rs": "fn main() { println!(\"Hello, Ferris!\"); }"],
            entryFile: "main.rs",
            provenance: nil
        )
        let validation = LessonEvidenceValidator.validateCompilerAttempt(
            evidence: lesson.evidence,
            result: successfulRun(stdout: "Hello, Ferris!\n"),
            project: project,
            initialSourceTreeHash: "starter-hash",
            currentSourceTreeHash: "edited-hash",
            observedDiagnosticCodes: []
        )

        XCTAssertTrue(validation.passed)
    }

    func testBorrowRepairRequiresARepairAndPreservedBehavior() throws {
        let lesson = try XCTUnwrap(RustCourseCatalog.lesson(id: "borrowing"))
        let project = CrabrixProject(
            name: "borrow",
            files: ["main.rs": RustSamples.runnable],
            entryFile: "main.rs",
            provenance: nil
        )
        let unchanged = LessonEvidenceValidator.validateCompilerAttempt(
            evidence: lesson.evidence,
            result: successfulRun(stdout: "crab\n"),
            project: project,
            initialSourceTreeHash: "same",
            currentSourceTreeHash: "same",
            observedDiagnosticCodes: []
        )
        XCTAssertFalse(unchanged.passed)

        let fixedBeforeEverRunning = LessonEvidenceValidator.validateCompilerAttempt(
            evidence: lesson.evidence,
            result: successfulRun(stdout: "crab\n"),
            project: project,
            initialSourceTreeHash: "starter",
            currentSourceTreeHash: "fixed",
            observedDiagnosticCodes: []
        )
        XCTAssertTrue(fixedBeforeEverRunning.passed, fixedBeforeEverRunning.detail)

        let provenRepair = LessonEvidenceValidator.validateCompilerAttempt(
            evidence: lesson.evidence,
            result: successfulRun(stdout: "crab\n"),
            project: project,
            initialSourceTreeHash: "before",
            currentSourceTreeHash: "after",
            observedDiagnosticCodes: ["E0502"]
        )
        XCTAssertTrue(provenRepair.passed)
    }

    private func repairAttempt(
        source: String, stdout: String = "crab\n", automaticRepairFingerprint: String? = nil
    ) throws -> LessonEvidenceValidation {
        LessonEvidenceValidator.validateCompilerAttempt(
            evidence: try XCTUnwrap(RustCourseCatalog.lesson(id: "borrowing")).evidence,
            result: successfulRun(stdout: stdout),
            project: CrabrixProject(name: "borrow", files: ["main.rs": source], entryFile: "main.rs", provenance: nil),
            initialSourceTreeHash: "starter",
            currentSourceTreeHash: "fixed",
            observedDiagnosticCodes: ["E0502"],
            automaticRepairFingerprint: automaticRepairFingerprint
        )
    }

    func testCommentsCannotSatisfyRepairFragments() throws {
        let commented = "// items.push(\nfn main() { println!(\"crab\"); }"
        XCTAssertFalse(try repairAttempt(source: commented).passed)
        let blockCommented = "/* outer /* items.push( */ */ fn main() { println!(\"crab\"); }"
        XCTAssertFalse(try repairAttempt(source: blockCommented).passed)
    }

    func testAppliedRepairIsNotEvidenceUntilTheCodeDiffers() throws {
        let applied = "fn main() {\n    let mut items = vec![];\n    println!(\"{items:?}\");\n    items.push(\"crab\");\n    println!(\"crab\");\n}\n"
        let appliedCode = LessonSourceText.fingerprint(in: ["main.rs": applied])

        XCTAssertFalse(try repairAttempt(source: applied, automaticRepairFingerprint: appliedCode).passed)
        // Comments and spacing do not make the same program the learner's own.
        XCTAssertFalse(try repairAttempt(
            source: "// mine\n" + applied.replacingOccurrences(of: "    ", with: "  "),
            automaticRepairFingerprint: appliedCode
        ).passed)
        XCTAssertTrue(try repairAttempt(
            source: applied.replacingOccurrences(of: "\"crab\");\n    println", with: "\"crab\".to_string());\n    println"),
            automaticRepairFingerprint: appliedCode
        ).passed)
    }

    func testCommentStrippingLeavesLiteralsAlone() {
        func stripped(_ source: String) -> String { LessonSourceText.strippingComments(source) }

        XCTAssertEqual(stripped("a // gone\nb"), "a \nb")
        XCTAssertEqual(stripped("a /* gone /* nested */ still gone */ b"), "a   b")
        XCTAssertEqual(stripped(#"let s = "// kept /* kept */";"#), #"let s = "// kept /* kept */";"#)
        XCTAssertEqual(stripped(#"let s = "esc \" // kept"; // gone"#), #"let s = "esc \" // kept"; "#)
        XCTAssertEqual(stripped(##"let s = r#"a " // kept"#; // gone"##), ##"let s = r#"a " // kept"#; "##)
        XCTAssertEqual(stripped(#"let s = br"// kept"; // gone"#), #"let s = br"// kept"; "#)
        XCTAssertEqual(stripped(#"let q = '"'; // gone"#), #"let q = '"'; "#)
        XCTAssertEqual(stripped(#"let q = '\''; // gone"#), #"let q = '\''; "#)
        XCTAssertEqual(stripped("fn f<'a>(x: &'a str) {} // gone"), "fn f<'a>(x: &'a str) {} ")
        XCTAssertEqual(stripped("let c = 'é'; // gone 🦀\nlet d = \"🦀\";"), "let c = 'é'; \nlet d = \"🦀\";")
        XCTAssertEqual(stripped("let r#type = 1; let bar = 2; // gone"), "let r#type = 1; let bar = 2; ")
    }

    func testAnswerOrderIsAStablePermutationOfTheLessonID() {
        for count in 0...8 {
            let order = LessonAnswerOrder.displayOrder(lessonID: "borrowing", count: count)
            XCTAssertEqual(order.sorted(), Array(0..<count))
            XCTAssertEqual(order, LessonAnswerOrder.displayOrder(lessonID: "borrowing", count: count))
        }
        // Pinned, because a change here reorders every lesson a learner has seen.
        XCTAssertEqual(LessonAnswerOrder.displayOrder(lessonID: "borrowing", count: 4), [1, 0, 2, 3])
        XCTAssertEqual(LessonAnswerOrder.displayOrder(lessonID: "algorithm.trie.model", count: 4), [3, 0, 1, 2])
    }

    func testAnswerOrderStopsTheCorrectAnswerBeingPredictableByPosition() {
        let lessons = RustCourseCatalog.courses.flatMap(\.units).flatMap(\.lessons)
        var positions = [Int: Int]()
        var checked = 0
        for lesson in lessons {
            guard let writing = RustLessonLibrary.writing(for: lesson.id) else { continue }
            let order = LessonAnswerOrder.displayOrder(lessonID: lesson.id, count: writing.answers.count)
            let position = order.firstIndex(of: writing.correctAnswer)
            positions[position ?? -1, default: 0] += 1
            checked += 1
        }
        XCTAssertGreaterThan(checked, 700)
        XCTAssertNil(positions[-1])
        // Authored data puts 400 of these at index 0 and 200 at index 1.
        for (position, count) in positions {
            XCTAssertLessThan(Double(count) / Double(checked), 0.45, "position \(position)")
        }
    }

    func testCompletedLessonAlwaysReopensAnswered() {
        func state(_ saved: Int?, completed: Bool) -> (selected: Int?, lastWrong: Int?) {
            LessonAnswerRestoration.state(savedAnswer: saved, isCompleted: completed, correctAnswer: 2)
        }

        // The saved index no longer matches, as after a pack moves the answer.
        XCTAssertEqual(state(0, completed: true).selected, 2)
        XCTAssertNil(state(0, completed: true).lastWrong)
        XCTAssertEqual(state(99, completed: true).selected, 2)
        // Older installations saved no answer.
        XCTAssertEqual(state(nil, completed: true).selected, 2)
        XCTAssertEqual(state(2, completed: false).selected, 2)
        // An unfinished lesson may still be retried.
        XCTAssertNil(state(0, completed: false).selected)
        XCTAssertEqual(state(0, completed: false).lastWrong, 0)
        XCTAssertNil(state(nil, completed: false).selected)
        XCTAssertNil(state(nil, completed: false).lastWrong)
    }

    func testMarkdownKeepsMultiplicationSigns() throws {
        func rendered(_ prose: String) throws -> String {
            String(try AttributedString(
                markdown: LessonProseFormatting.escapingMultiplicationSigns(prose),
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            ).characters)
        }

        XCTAssertEqual(try rendered("O(rows*cols) time · O(rows*cols) space"), "O(rows*cols) time · O(rows*cols) space")
        XCTAssertEqual(try rendered("(sq)*sq and (n*2^n)"), "(sq)*sq and (n*2^n)")
        XCTAssertEqual(try rendered("3 * 4 and checked_* returns"), "3 * 4 and checked_* returns")
        // Real emphasis still parses.
        XCTAssertEqual(try rendered("a **bold** and *italic* word"), "a bold and italic word")
    }

    func testLockedLessonIsNotOpenButCompletedAndFirstUnfinishedAre() throws {
        let course = try XCTUnwrap(RustCourseCatalog.course(id: "basics"))
        let lessons = course.units.flatMap(\.lessons)
        func isOpen(_ index: Int, completed: Set<String>) -> Bool {
            RustLessonProgression.isOpen(
                .init(courseID: course.id, lessonID: lessons[index].id),
                completedLessonIDs: completed, courses: [course]
            )
        }

        // Weak Topics opened lesson 5 out of order, and finishing it leads here.
        let outOfOrder: Set<String> = [lessons[5].id]
        XCTAssertFalse(isOpen(6, completed: outOfOrder))
        XCTAssertTrue(isOpen(0, completed: outOfOrder))
        XCTAssertTrue(isOpen(5, completed: outOfOrder))

        let inOrder = Set(lessons[...4].map(\.id))
        XCTAssertTrue(isOpen(5, completed: inOrder))
        XCTAssertFalse(isOpen(6, completed: inOrder))
    }
}

final class RustCurriculumCoverageTests: XCTestCase {
    private var allLessons: [RustLesson] {
        RustCourseCatalog.courses.flatMap { $0.units.flatMap(\.lessons) }
    }

    func testLessonIdentifiersAreUnique() {
        let ids = allLessons.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate lesson ids break navigation and progress")
    }

    func testEveryUnitIsReachableFromACourse() {
        let used = Set(RustCourseCatalog.courses.flatMap { $0.units.map(\.id) })
        let defined = Set(RustLearningPath.units.map(\.id))
        XCTAssertTrue(
            defined.subtracting(used).isEmpty,
            "unreachable units: \(defined.subtracting(used).sorted())"
        )
    }

    func testCurriculumCoversTheCoreOfTheLanguage() {
        let ids = Set(allLessons.map(\.id))
        // The topics a Rust course cannot claim completeness without.
        let required = [
            "ownership", "borrowing", "lifetimes", "slices", "copy-clone", "drop-order",
            "structs", "enums", "option-result", "collections", "strings", "pattern-matching",
            "generics", "traits", "closures", "iterators", "associated-types",
            "modules", "testing", "errors", "dependencies", "workspaces",
            "box", "rc-refcell", "deref-drop", "cycles",
            "concurrency", "channels", "shared-state", "send-sync",
            "futures", "async-runtime", "declarative-macros", "proc-macros",
            "unsafe", "ffi", "performance",
        ]
        let missing = required.filter { !ids.contains($0) }
        XCTAssertTrue(missing.isEmpty, "curriculum is missing: \(missing)")
    }

    func testEveryLessonHasNonEmptyMetadata() {
        for lesson in allLessons {
            XCTAssertFalse(lesson.title.trimmingCharacters(in: .whitespaces).isEmpty, lesson.id)
            XCTAssertFalse(lesson.concept.trimmingCharacters(in: .whitespaces).isEmpty, lesson.id)
            XCTAssertGreaterThan(lesson.minutes, 0, lesson.id)
        }
    }

    func testEveryLessonDeclaresAnExplicitEvidenceType() {
        XCTAssertEqual(allLessons.count, 742)
        for lesson in allLessons {
            switch lesson.evidence {
            case .compilerRun, .repair, .algorithmChallenge, .reasoning:
                break
            }
        }
    }

    func testWrittenLessonContentIsComplete() {
        for lesson in allLessons where !lesson.id.hasPrefix("algorithm.") {
            guard let writing = RustLessonLibrary.writing(for: lesson.id) else { continue }
            XCTAssertFalse(writing.summary.isEmpty, lesson.id)
            XCTAssertFalse(writing.explanation.isEmpty, lesson.id)
            XCTAssertFalse(writing.exampleCode.isEmpty, lesson.id)
            XCTAssertEqual(writing.answers.count, 3, "\(lesson.id) should offer three answers")
            XCTAssertTrue(
                writing.answers.indices.contains(writing.correctAnswer),
                "\(lesson.id) has an out-of-range correct answer"
            )
            // Snippets are read on a phone, so lines have to fit.
            for line in writing.exampleCode.split(separator: "\n", omittingEmptySubsequences: false) {
                XCTAssertLessThanOrEqual(
                    line.count, 52,
                    "\(lesson.id) example line is too wide for a phone: \(line)"
                )
            }
        }
    }
}
