import Foundation

struct RustLearningUnit: Identifiable, Sendable {
    let id: String
    let level: Int
    let title: String
    let subtitle: String
    let lessons: [RustLesson]
}

struct RustLesson: Identifiable, Sendable {
    enum Exercise: Sendable {
        case runnable
        case borrowDiagnostic
        case multiFile
        case algorithmChallenge
        case planned
    }

    let id: String
    let title: String
    let concept: String
    let minutes: Int
    let exercise: Exercise
}

enum LessonOutputMatcher: Codable, Equatable, Sendable {
    case exact(String)
    case contains(String)
    case differsFrom(String)

    func matches(_ output: String) -> Bool {
        switch self {
        case let .exact(expected): output == expected
        case let .contains(fragment): output.contains(fragment)
        case let .differsFrom(starter): !output.isEmpty && output != starter
        }
    }

    /// An algorithm harness prints its verdict last, so a leftover debug
    /// `println!` before it must not fail a correct solution. Everything except
    /// `exact` already allows surrounding output.
    func matchesFinalLines(_ output: String) -> Bool {
        guard case let .exact(expected) = self else { return matches(output) }
        let verdict = expected.trimmingCharacters(in: .newlines)
        let trimmed = output.trimmingCharacters(in: .newlines)
        return trimmed == verdict || trimmed.hasSuffix("\n" + verdict)
    }

    /// What the lesson is actually waiting for, in one line.
    ///
    /// The failure used to say only that stdout "does not yet prove the
    /// requested behavior" — and the lesson text is a screen away by then, so
    /// there was no way to know which behaviour was meant.
    var requirement: String {
        switch self {
        case let .exact(expected):
            "Expected stdout: \(Self.quoted(expected))"
        case let .contains(fragment):
            "stdout has to contain \(Self.quoted(fragment))"
        case .differsFrom:
            "stdout has to change from what the starter project printed"
        }
    }

    private static func quoted(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .newlines)
        let shortened = trimmed.count > 120
            ? trimmed.prefix(117) + "…"
            : trimmed[...]
        return "“\(shortened)”"
    }
}

/// The proof a lesson requires. A successful process exit is only one input;
/// it is never, by itself, a universal lesson validator.
enum LessonEvidence: Equatable, Sendable {
    case compilerRun(
        expectedOutput: LessonOutputMatcher,
        requiresSourceChange: Bool,
        requiredFiles: [String]
    )
    case repair(
        removesDiagnostic: String,
        expectedOutput: LessonOutputMatcher,
        requiredSourceFragments: [String]
    )
    case algorithmChallenge(
        expectedOutput: LessonOutputMatcher,
        requiredSourceFragments: [String],
        forbiddenSourceFragments: [String]
    )
    case reasoning(correctAnswer: Int)
}

enum LessonAttemptResult: String, Codable, Equatable, Sendable {
    case passed
    case failed
}

/// The exact course session and workspace used to check one exercise. A pack
/// update cannot retroactively change this evidence's validator or toolchain.
struct LessonAttemptIdentity: Codable, Equatable, Sendable {
    let courseID: String
    let language: String
    let contentVersion: String
    let lessonID: String
    let exerciseID: String
    let validatorVersion: String
    let toolchainID: String
    let projectID: UUID
    let projectRevision: String
}

/// Persisted evidence contains hashes and compiler facts, never the learner's
/// source code.
struct LessonAttemptEvidence: Codable, Equatable, Sendable {
    static let validatorVersion = "lesson-evidence-1"

    let lessonID: String
    let projectRevision: String
    let validatorVersion: String
    let compilerVersion: String?
    let result: LessonAttemptResult
    let diagnosticCodes: [String]
    let stdoutHash: String?
    let completedAt: Date
    /// Absent only on evidence written before CoursePack identity was stored.
    /// Those records must be attributed to a verified legacy snapshot, not
    /// silently assigned the latest downloaded content version.
    let identity: LessonAttemptIdentity?

    init(lessonID: String, projectRevision: String, validatorVersion: String,
         compilerVersion: String?, result: LessonAttemptResult,
         diagnosticCodes: [String], stdoutHash: String?, completedAt: Date,
         identity: LessonAttemptIdentity? = nil) {
        self.lessonID = lessonID
        self.projectRevision = projectRevision
        self.validatorVersion = validatorVersion
        self.compilerVersion = compilerVersion
        self.result = result
        self.diagnosticCodes = diagnosticCodes
        self.stdoutHash = stdoutHash
        self.completedAt = completedAt
        self.identity = identity
    }
}

struct LessonEvidenceValidation: Equatable, Sendable {
    let passed: Bool
    let detail: String
}

/// Source text as the compiler sees it, for the checks that look at what a
/// learner wrote. Comments are not code: they can neither supply a required
/// fragment nor trip a forbidden one.
enum LessonSourceText {
    /// Removes `//` and nested `/* */` comments, leaving string, raw string and
    /// character literals untouched. Every delimiter is ASCII, so scanning UTF-8
    /// bytes cannot split a multi-byte character.
    static func strippingComments(_ source: String) -> String {
        let bytes = Array(source.utf8)
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count)
        var index = 0

        func isIdentifier(_ byte: UInt8) -> Bool {
            byte == 0x5F || (byte >= 0x30 && byte <= 0x39)
                || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A) || byte >= 0x80
        }
        func copy(until end: Int) {
            let stop = min(end, bytes.count)
            output.append(contentsOf: bytes[index..<stop])
            index = stop
        }
        /// A literal prefix only counts when it starts a token: `r` in `bar"` does not.
        func startsToken(at position: Int) -> Bool {
            position == 0 || !isIdentifier(bytes[position - 1])
        }

        while index < bytes.count {
            let byte = bytes[index]
            let next = index + 1 < bytes.count ? bytes[index + 1] : 0
            switch byte {
            case 0x2F where next == 0x2F: // line comment
                while index < bytes.count, bytes[index] != 0x0A { index += 1 }
            case 0x2F where next == 0x2A: // block comment, which Rust nests
                var depth = 1
                index += 2
                while index < bytes.count, depth > 0 {
                    let current = bytes[index]
                    let following = index + 1 < bytes.count ? bytes[index + 1] : 0
                    if current == 0x2F, following == 0x2A { depth += 1; index += 2 }
                    else if current == 0x2A, following == 0x2F { depth -= 1; index += 2 }
                    else { index += 1 }
                }
                output.append(0x20)
            case 0x22: // string
                var end = index + 1
                while end < bytes.count, bytes[end] != 0x22 {
                    end += bytes[end] == 0x5C ? 2 : 1
                }
                copy(until: end + 1)
            case 0x27: // character literal or lifetime
                if next == 0x5C {
                    var end = index + 2
                    if end < bytes.count { end += 1 }
                    while end < bytes.count, bytes[end] != 0x27, bytes[end] != 0x0A { end += 1 }
                    copy(until: end + 1)
                } else if let close = (2...5).first(where: {
                    index + $0 < bytes.count && bytes[index + $0] == 0x27
                }), close == 2 || next >= 0x80 {
                    copy(until: index + close + 1)
                } else {
                    copy(until: index + 1)
                }
            case 0x72 where startsToken(at: index)
                || (index > 0 && (bytes[index - 1] == 0x62 || bytes[index - 1] == 0x63)
                    && startsToken(at: index - 1)): // r"", r#""#, br"", cr""
                var open = index + 1
                while open < bytes.count, bytes[open] == 0x23 { open += 1 }
                guard open < bytes.count, bytes[open] == 0x22 else {
                    copy(until: index + 1)
                    continue
                }
                let hashes = open - index - 1
                var end = open + 1
                while end < bytes.count {
                    if bytes[end] == 0x22,
                       (0..<hashes).allSatisfy({ end + 1 + $0 < bytes.count && bytes[end + 1 + $0] == 0x23 }) {
                        break
                    }
                    end += 1
                }
                copy(until: end + 1 + hashes)
            default:
                output.append(byte)
                index += 1
            }
        }
        return String(decoding: output, as: UTF8.self)
    }

    /// The `.rs` sources as compact code: comments, whitespace, reference
    /// lifetimes and `pub(...)` restrictions removed. None of those change what a
    /// validated signature means, and the harness has already compiled against it.
    static func normalizedCode(in files: [String: String]) -> String {
        files.keys.filter { $0.hasSuffix(".rs") }.sorted().compactMap { files[$0] }
            .map(normalized).joined(separator: "\n")
    }

    /// Identifies a program without keeping its source, for evidence that outlives
    /// the session. Comments and spacing do not change it.
    static func fingerprint(in files: [String: String]) -> String {
        WorkspaceRevision.contentHash(normalizedCode(in: files))
    }

    static func contains(_ fragment: String, in code: String) -> Bool {
        let compact = compacted(fragment)
        guard !compact.isEmpty else { return true }
        // `input: &str` requires a `&str` binding. Its name is the learner's choice.
        if let colon = compact.firstIndex(of: ":"),
           compact[..<colon].allSatisfy({ $0 == "_" || $0.isLetter || $0.isNumber }),
           colon != compact.startIndex,
           !compact[compact.index(after: colon)...].hasPrefix(":") {
            let binding = compact[colon...]
            var searchStart = code.startIndex
            while let found = code.range(of: binding, range: searchStart..<code.endIndex) {
                if found.lowerBound > code.startIndex {
                    let before = code[code.index(before: found.lowerBound)]
                    if before == "_" || before.isLetter || before.isNumber { return true }
                }
                searchStart = found.upperBound
            }
            return false
        }
        return code.contains(compact)
    }

    private static func normalized(_ source: String) -> String {
        compacted(
            strippingComments(source)
                .replacingOccurrences(
                    of: #"&'[A-Za-z_][A-Za-z0-9_]*\s+"#, with: "&", options: .regularExpression
                )
                .replacingOccurrences(
                    of: #"\bpub\s*\(\s*(crate|self|super|in\s[^)]*)\s*\)"#, with: "pub ",
                    options: .regularExpression
                )
        )
    }

    private static func compacted(_ text: String) -> String {
        String(text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }
            .map(Character.init))
    }
}

/// A challenge harness proves it ran to the end only by printing its verdict,
/// and a learner can print that same text and exit before the harness compares
/// a single case. The packs are signed and cannot change, so the app appends a
/// private token to the verdict in the copy it compiles. The token never reaches
/// the learner's project, and the visible output is restored afterwards.
enum LessonHarnessNonce {
    struct Run: Equatable, Sendable {
        let nonce: String
        let verdict: String
    }

    static func instrument(
        verificationSource: String, expectedOutput: String, nonce: String
    ) -> (source: String, run: Run)? {
        let verdict = expectedOutput.trimmingCharacters(in: .newlines)
        guard !verdict.isEmpty,
              !verdict.contains(where: { "\n\"\\{}".contains($0) }) else { return nil }
        let literal = "println!(\"\(verdict)\");"
        guard verificationSource.components(separatedBy: literal).count == 2 else { return nil }
        return (
            verificationSource.replacingOccurrences(
                of: literal, with: "println!(\"\(verdict) \(nonce)\");"
            ),
            Run(nonce: nonce, verdict: verdict)
        )
    }

    /// Returns the output the learner should see, and whether the harness itself
    /// printed the last thing in it.
    static func reveal(stdout: String, run: Run) -> (stdout: String, completed: Bool) {
        let completed = stdout.hasSuffix("\(run.verdict) \(run.nonce)\n")
        return (stdout.replacingOccurrences(of: " \(run.nonce)", with: ""), completed)
    }

    static func make() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }
}

enum LessonEvidenceValidator {
    static func validateCompilerAttempt(
        evidence: LessonEvidence,
        result: CompilationResult,
        project: CrabrixProject,
        initialSourceTreeHash: String?,
        currentSourceTreeHash: String,
        observedDiagnosticCodes: Set<String>,
        automaticRepairFingerprint: String? = nil,
        harnessCompleted: Bool? = nil
    ) -> LessonEvidenceValidation {
        guard result.succeeded, result.phase == .run else {
            return LessonEvidenceValidation(
                passed: false,
                detail: "Run the lesson project successfully to produce compiler evidence."
            )
        }

        switch evidence {
        case let .compilerRun(output, requiresSourceChange, requiredFiles):
            if requiresSourceChange, initialSourceTreeHash == currentSourceTreeHash {
                return LessonEvidenceValidation(
                    passed: false,
                    detail: "The starter project ran unchanged. Make the requested edit and run again."
                )
            }
            let missingFiles = requiredFiles.filter { project.files[$0] == nil }
            guard missingFiles.isEmpty else {
                return LessonEvidenceValidation(
                    passed: false,
                    detail: "Required lesson files are missing: \(missingFiles.joined(separator: ", "))."
                )
            }
            guard output.matches(result.stdout) else {
                return LessonEvidenceValidation(
                    passed: false,
                    detail: "The program ran, but its output is not what this lesson asks for. "
                        + output.requirement + "."
                )
            }
            return LessonEvidenceValidation(
                passed: true,
                detail: "The edited project compiled and its stdout matched this lesson's validator."
            )

        case let .repair(code, output, requiredFragments):
            // The starter is what produces this diagnostic, so a changed tree
            // that compiles has repaired it even if it was never run broken.
            guard observedDiagnosticCodes.contains(code)
                    || initialSourceTreeHash != currentSourceTreeHash else {
                return LessonEvidenceValidation(
                    passed: false,
                    detail: "Reproduce \(code) first, then repair that exact diagnostic."
                )
            }
            guard !result.diagnostics.contains(where: { $0.code == code }) else {
                return LessonEvidenceValidation(
                    passed: false,
                    detail: "\(code) is still present."
                )
            }
            if let automaticRepairFingerprint,
               automaticRepairFingerprint == LessonSourceText.fingerprint(in: project.files) {
                return LessonEvidenceValidation(
                    passed: false,
                    detail: "Apply to main.rs made this fix for you, so it does not count as your evidence. "
                        + "Undo it and repair \(code) yourself, or restart the lab, then run again."
                )
            }
            let source = LessonSourceText.normalizedCode(in: project.files)
            let missingFragments = requiredFragments.filter { !LessonSourceText.contains($0, in: source) }
            guard missingFragments.isEmpty else {
                return LessonEvidenceValidation(
                    passed: false,
                    detail: "The repair removed required behavior from the starter project."
                )
            }
            guard output.matches(result.stdout) else {
                return LessonEvidenceValidation(
                    passed: false,
                    detail: "\(code) is gone, but the program no longer behaves as it should. "
                        + output.requirement + "."
                )
            }
            return LessonEvidenceValidation(
                passed: true,
                detail: "\(code) was reproduced, removed, and the expected behavior still ran."
            )

        case let .algorithmChallenge(output, requiredFragments, forbiddenFragments):
            guard initialSourceTreeHash != currentSourceTreeHash else {
                return LessonEvidenceValidation(
                    passed: false,
                    detail: "The starter is unchanged. Implement the supplied function, then run it again."
                )
            }
            let code = LessonSourceText.normalizedCode(in: project.files)
            let missingFragments = requiredFragments.filter { !LessonSourceText.contains($0, in: code) }
            guard missingFragments.isEmpty else {
                return LessonEvidenceValidation(
                    passed: false,
                    detail: "Keep the supplied public function required by this lab."
                )
            }
            let remainingPlaceholders = forbiddenFragments.filter { LessonSourceText.contains($0, in: code) }
            guard remainingPlaceholders.isEmpty else {
                return LessonEvidenceValidation(
                    passed: false,
                    detail: "Replace the starter todo! placeholder with your solution."
                )
            }
            if harnessCompleted == false {
                return LessonEvidenceValidation(
                    passed: false,
                    detail: "The program stopped before the verification harness finished. "
                        + "Return from the supplied function instead of exiting the process."
                )
            }
            guard harnessCompleted == true || output.matchesFinalLines(result.stdout) else {
                return LessonEvidenceValidation(
                    passed: false,
                    detail: "The program ran, but the verification cases did not pass yet."
                )
            }
            return LessonEvidenceValidation(
                passed: true,
                detail: "rustc accepted the solution and the verification harness completed."
            )

        case .reasoning:
            return LessonEvidenceValidation(
                passed: false,
                detail: "This lesson is completed by its explanation question, not by a generic Run."
            )
        }
    }
}

extension RustLesson {
    var hasCompilerLab: Bool {
        if case .planned = exercise { return false }
        return true
    }
}

#if DEBUG || CRABRIX_LEGACY_FIXTURES
extension RustLesson {
    var evidence: LessonEvidence {
        switch exercise {
        case .runnable:
            .compilerRun(
                expectedOutput: .differsFrom("Hello, Crabrix!\n"),
                requiresSourceChange: true,
                requiredFiles: ["main.rs"]
            )
        case .borrowDiagnostic:
            .repair(
                removesDiagnostic: "E0502",
                expectedOutput: .contains("crab"),
                requiredSourceFragments: ["items.push(", "println!"]
            )
        case .multiFile:
            .compilerRun(
                expectedOutput: .differsFrom("hello from two Rust files\n"),
                requiresSourceChange: true,
                requiredFiles: ["Cargo.toml", "src/main.rs", "src/greeter.rs"]
            )
        case .algorithmChallenge:
            if let challenge = AlgorithmCourseCatalog.challenge(for: id) {
                .algorithmChallenge(
                    expectedOutput: .exact(challenge.expectedOutput),
                    requiredSourceFragments: challenge.requiredSourceFragments,
                    forbiddenSourceFragments: challenge.forbiddenSourceFragments
                )
            } else {
                .reasoning(correctAnswer: RustLessonLibrary.writing(for: id)?.correctAnswer ?? 0)
            }
        case .planned:
            .reasoning(correctAnswer: RustLessonLibrary.writing(for: id)?.correctAnswer ?? 1)
        }
    }
}

enum RustLearningPath {
    static let units: [RustLearningUnit] = [
        RustLearningUnit(
            id: "foundations",
            level: 1,
            title: "Rust Foundations",
            subtitle: "Read, edit, compile, and trust rustc",
            lessons: [
                RustLesson(id: "hello-rust", title: "Hello, Rust", concept: "Functions and stdout", minutes: 4, exercise: .runnable),
                RustLesson(id: "variables", title: "Variables", concept: "let, mut, and shadowing", minutes: 6, exercise: .planned),
                RustLesson(id: "print-formatting", title: "Printing Values", concept: "Format strings and placeholders", minutes: 5, exercise: .planned),
                RustLesson(id: "number-types", title: "Numbers", concept: "Integer and floating-point types", minutes: 6, exercise: .planned),
                RustLesson(id: "booleans-comparisons", title: "Booleans", concept: "Comparisons and logical operators", minutes: 5, exercise: .planned),
                RustLesson(id: "chars-and-text", title: "Characters & Text", concept: "char, &str, and Unicode", minutes: 6, exercise: .planned),
                RustLesson(id: "compiler-feedback", title: "Reading rustc", concept: "Expected, found, spans, and help", minutes: 6, exercise: .planned),
            ]
        ),
    ] + RustBasicsExpansion.units + [
        RustLearningUnit(
            id: "ownership",
            level: 5,
            title: "Ownership & Borrowing",
            subtitle: "The ideas that make Rust different",
            lessons: [
                RustLesson(id: "ownership", title: "Ownership", concept: "Moves and scope", minutes: 8, exercise: .planned),
                RustLesson(id: "borrowing", title: "Borrowing", concept: "References and E0502", minutes: 9, exercise: .borrowDiagnostic),
                RustLesson(id: "slices", title: "Slices", concept: "Borrowed views into data", minutes: 8, exercise: .planned),
                RustLesson(id: "copy-clone", title: "Copy & Clone", concept: "When a value duplicates instead of moving", minutes: 8, exercise: .planned),
                RustLesson(id: "drop-order", title: "Drop & Scope", concept: "Deterministic cleanup without a GC", minutes: 8, exercise: .planned),
                RustLesson(id: "lifetimes-intro", title: "Lifetime Intuition", concept: "Why references stay valid", minutes: 10, exercise: .planned),
            ]
        ),
        RustLearningUnit(
            id: "modeling",
            level: 4,
            title: "Modeling Data",
            subtitle: "Make invalid states harder to express",
            lessons: [
                RustLesson(id: "structs", title: "Structs", concept: "Named data and methods", minutes: 8, exercise: .planned),
                RustLesson(id: "enums", title: "Enums & Match", concept: "Variants and exhaustive handling", minutes: 10, exercise: .planned),
                RustLesson(id: "option-result", title: "Option & Result", concept: "Explicit absence and failure", minutes: 10, exercise: .planned),
                RustLesson(id: "collections", title: "Collections", concept: "Vec, String, and HashMap", minutes: 9, exercise: .planned),
                RustLesson(id: "strings", title: "Strings & UTF-8", concept: "String, &str, chars, and bytes", minutes: 10, exercise: .planned),
                RustLesson(id: "pattern-matching", title: "Pattern Matching", concept: "Destructuring, guards, and bindings", minutes: 11, exercise: .planned),
                RustLesson(id: "derive", title: "Derive Macros", concept: "Debug, Clone, PartialEq, and Default", minutes: 8, exercise: .planned),
            ]
        ),
        RustLearningUnit(
            id: "abstraction",
            level: 6,
            title: "Rust Abstractions",
            subtitle: "Reuse without hiding the cost",
            lessons: [
                RustLesson(id: "generics", title: "Generics", concept: "Reusable types and functions", minutes: 10, exercise: .planned),
                RustLesson(id: "traits", title: "Traits", concept: "Shared behavior and bounds", minutes: 11, exercise: .planned),
                RustLesson(id: "lifetimes", title: "Lifetimes", concept: "Relationships between borrows", minutes: 12, exercise: .planned),
                RustLesson(id: "closures", title: "Closures", concept: "Fn, FnMut, FnOnce, and capture", minutes: 11, exercise: .planned),
                RustLesson(id: "iterators", title: "Iterators", concept: "Lazy transformations", minutes: 11, exercise: .planned),
                RustLesson(id: "iterator-impl", title: "Writing an Iterator", concept: "impl Iterator and the next method", minutes: 11, exercise: .planned),
                RustLesson(id: "associated-types", title: "Associated Types", concept: "One output type per implementation", minutes: 11, exercise: .planned),
                RustLesson(id: "operator-traits", title: "Operator Traits", concept: "Add, Display, From, and Into", minutes: 11, exercise: .planned),
            ]
        ),
        RustLearningUnit(
            id: "projects",
            level: 7,
            title: "Real Projects",
            subtitle: "Cargo-shaped code beyond one file",
            lessons: [
                RustLesson(id: "modules", title: "Modules", concept: "Cargo.toml and sibling files", minutes: 9, exercise: .multiFile),
                RustLesson(id: "testing", title: "Testing", concept: "Unit and integration tests", minutes: 10, exercise: .planned),
                RustLesson(id: "errors", title: "Error Design", concept: "Propagation and custom errors", minutes: 11, exercise: .planned),
                RustLesson(id: "dependencies", title: "Dependencies", concept: "crates.io, SemVer, and features", minutes: 10, exercise: .planned),
                RustLesson(id: "workspaces", title: "Workspaces", concept: "Many crates, one lockfile", minutes: 9, exercise: .planned),
            ]
        ),
        RustLearningUnit(
            id: "pointers",
            level: 8,
            title: "Smart Pointers",
            subtitle: "Ownership shapes beyond a plain value",
            lessons: [
                RustLesson(id: "box", title: "Box<T>", concept: "Heap allocation and recursive types", minutes: 9, exercise: .planned),
                RustLesson(id: "rc-refcell", title: "Rc & RefCell", concept: "Shared ownership and interior mutability", minutes: 12, exercise: .planned),
                RustLesson(id: "deref-drop", title: "Deref & Drop", concept: "Making a type behave like a reference", minutes: 10, exercise: .planned),
                RustLesson(id: "cycles", title: "Reference Cycles", concept: "Weak<T> and leaks Rust cannot prevent", minutes: 11, exercise: .planned),
            ]
        ),
        RustLearningUnit(
            id: "threads",
            level: 9,
            title: "Fearless Concurrency",
            subtitle: "Share data across threads without data races",
            lessons: [
                RustLesson(id: "concurrency", title: "Threads", concept: "spawn, join, and move closures", minutes: 11, exercise: .planned),
                RustLesson(id: "channels", title: "Channels", concept: "Message passing with mpsc", minutes: 11, exercise: .planned),
                RustLesson(id: "shared-state", title: "Shared State", concept: "Mutex, RwLock, and Arc", minutes: 12, exercise: .planned),
                RustLesson(id: "send-sync", title: "Send & Sync", concept: "The traits behind thread safety", minutes: 11, exercise: .planned),
            ]
        ),
        RustLearningUnit(
            id: "async",
            level: 10,
            title: "Async Rust",
            subtitle: "Concurrency without a thread per task",
            lessons: [
                RustLesson(id: "futures", title: "Futures", concept: "async fn, await, and laziness", minutes: 12, exercise: .planned),
                RustLesson(id: "async-runtime", title: "Runtimes", concept: "Why async needs an executor", minutes: 11, exercise: .planned),
                RustLesson(id: "async-patterns", title: "Async Patterns", concept: "join, select, and cancellation", minutes: 12, exercise: .planned),
            ]
        ),
        RustLearningUnit(
            id: "meta",
            level: 11,
            title: "Macros & Metaprogramming",
            subtitle: "Code that writes code, checked by the compiler",
            lessons: [
                RustLesson(id: "declarative-macros", title: "macro_rules!", concept: "Pattern-based code generation", minutes: 12, exercise: .planned),
                RustLesson(id: "proc-macros", title: "Procedural Macros", concept: "Derive, attribute, and function macros", minutes: 12, exercise: .planned),
                RustLesson(id: "cfg-features", title: "cfg & Features", concept: "Compiling different code per target", minutes: 10, exercise: .planned),
            ]
        ),
        RustLearningUnit(
            id: "systems",
            level: 12,
            title: "Systems Rust",
            subtitle: "The unchecked edges, handled carefully",
            lessons: [
                RustLesson(id: "unsafe", title: "unsafe Rust", concept: "Five powers and their invariants", minutes: 13, exercise: .planned),
                RustLesson(id: "ffi", title: "FFI", concept: "extern \"C\", repr(C), and raw pointers", minutes: 13, exercise: .planned),
                RustLesson(id: "performance", title: "Performance", concept: "Allocation, iterators, and measuring", minutes: 12, exercise: .planned),
                RustLesson(id: "idioms", title: "Rust Idioms", concept: "Newtype, builder, and typestate", minutes: 11, exercise: .planned),
            ]
        ),
    ] + RustAdvancedExpansion.allUnits
}
#endif
