import Foundation

/// The bridge between the first two bindings and Rust's data-modeling tools.
/// Stable lesson identifiers keep existing progress intact while the beginner
/// course grows from two short chapters into a gradual four-chapter path.
enum RustBasicsExpansion {
    static let units: [RustLearningUnit] = [
        RustLearningUnit(
            id: "expressions-flow",
            level: 2,
            title: "Expressions & Flow",
            subtitle: "Build values, call functions, and repeat work",
            lessons: [
                RustLesson(id: "types", title: "Compound Types", concept: "Tuples, arrays, and annotations", minutes: 7, exercise: .planned),
                RustLesson(id: "operators", title: "Operators & Casting", concept: "Arithmetic, overflow, and as", minutes: 7, exercise: .planned),
                RustLesson(id: "block-expressions", title: "Block Expressions", concept: "Statements, tail values, and semicolons", minutes: 6, exercise: .planned),
                RustLesson(id: "functions", title: "Functions", concept: "Returns and expression bodies", minutes: 7, exercise: .planned),
                RustLesson(id: "function-parameters", title: "Parameters", concept: "Typed inputs and arguments", minutes: 6, exercise: .planned),
                RustLesson(id: "control-flow", title: "Control Flow", concept: "if and match as expressions", minutes: 8, exercise: .planned),
                RustLesson(id: "ranges", title: "Ranges", concept: "Exclusive and inclusive boundaries", minutes: 5, exercise: .planned),
            ]
        ),
        RustLearningUnit(
            id: "small-programs",
            level: 3,
            title: "Small Programs",
            subtitle: "Combine the pieces before data modeling",
            lessons: [
                RustLesson(id: "loops", title: "Loops", concept: "for, while, loop, break, and continue", minutes: 7, exercise: .planned),
                RustLesson(id: "parsing", title: "Parsing Values", concept: "Turning text into typed data", minutes: 7, exercise: .planned),
                RustLesson(id: "references-intro", title: "First References", concept: "Borrowing for read-only access", minutes: 7, exercise: .planned),
                RustLesson(id: "methods-intro", title: "Using Methods", concept: "Dot syntax and chained transformations", minutes: 6, exercise: .planned),
                RustLesson(id: "recoverable-errors", title: "Handling Failure", concept: "Result without panic", minutes: 8, exercise: .planned),
                RustLesson(id: "debugging-values", title: "Inspecting Values", concept: "Debug, dbg!, and stderr", minutes: 6, exercise: .planned),
                RustLesson(id: "comments-docs", title: "Comments & Docs", concept: "/// doc comments and examples", minutes: 5, exercise: .planned),
            ]
        ),
    ]

    static let writing: [String: RustLessonWriting] = [
        "print-formatting": RustLessonWriting(
            summary: "Formatting lets one checked template describe exactly how values become text.",
            explanation: "A format string is checked while the program compiles. Named captures keep simple output readable, positional placeholders are useful when order matters, and width or alignment specifiers make tables predictable. The values are not glued into the string at runtime by guesswork: every placeholder must match an argument the macro can see.",
            exampleCaption: "Names can be captured directly inside a checked format string.",
            exampleCode: """
            let name = "Ferris";
            let builds = 4;
            println!("{name} ran {builds} builds");
            println!("{builds:>3}");
            """,
            task: "Print a name and a build count, then align the number to the right.",
            success: "stdout contains both values and the compiler reports no missing argument.",
            rule: "Every formatting placeholder must have a value known to println!.",
            practiceCode: """
            let language = "Rust";
            println!("Learning {language}");
            """,
            question: "When is the format string checked?",
            answers: [
                "Only after the user sees stdout",
                "While println! expands during compilation",
                "Only when a placeholder is missing",
            ],
            correctAnswer: 1,
            feedback: "println! is a macro, so malformed placeholders become compiler errors."
        ),
        "number-types": RustLessonWriting(
            summary: "A numeric type states the range, precision, and operations a value supports.",
            explanation: "Rust does not silently mix unrelated numeric types. Signed integers can represent negatives, unsigned integers spend the whole range above zero, usize is designed for indexes and lengths, and floating-point values trade exact decimal representation for range. Start with inference, then annotate where the domain or an API requires a specific type.",
            exampleCaption: "The annotations document three different jobs.",
            exampleCode: """
            let files: usize = 4;
            let temperature: f64 = 21.5;
            let mask: u8 = 0b1010;
            println!("{files} {temperature} {mask}");
            """,
            task: "Choose a type for a count, a temperature, and one byte of flags.",
            success: "Each value uses a type that fits its real job without a broad cast.",
            rule: "Numeric conversions are explicit because ranges and precision differ.",
            practiceCode: """
            let left: u32 = 4;
            let right: i32 = 2;
            let total = left + right;
            """,
            question: "Why is the addition rejected?",
            answers: [
                "Rust cannot add integers",
                "u32 and i32 are distinct types",
                "Only usize supports addition",
            ],
            correctAnswer: 1,
            feedback: "Convert deliberately only after deciding which range and sign rule the result needs."
        ),
        "booleans-comparisons": RustLessonWriting(
            summary: "Conditions are real bool values, never numbers pretending to be true or false.",
            explanation: "Comparisons such as ==, <, and >= produce bool. Logical && and || combine conditions and short-circuit, so the right side runs only when it can affect the answer. The ! operator negates a bool. Requiring an actual bool prevents the accidental truthiness rules that make 0, empty strings, and null behave differently across languages.",
            exampleCaption: "The name says what must be true before work starts.",
            exampleCode: """
            let builds = 4;
            let errors = 0;
            let ready = builds > 0 && errors == 0;
            if ready {
                println!("ready");
            }
            """,
            task: "Combine two comparisons into one clearly named condition.",
            success: "The branch runs only when both requirements are true.",
            rule: "if requires bool; Rust has no implicit numeric truthiness.",
            practiceCode: """
            let count = 3;
            if count {
                println!("items");
            }
            """,
            question: "What must replace count in the condition?",
            answers: [
                "A comparison such as count > 0",
                "count as bool",
                "Nothing; every nonzero integer is true",
            ],
            correctAnswer: 0,
            feedback: "Write the condition you mean explicitly, such as count > 0."
        ),
        "chars-and-text": RustLessonWriting(
            summary: "A char is one Unicode scalar value; &str is a borrowed sequence of UTF-8 bytes.",
            explanation: "Single quotes create a char and double quotes create string text. A visible character can occupy several UTF-8 bytes, so text length is not automatically the number of symbols a person sees. Use chars() when you need Unicode scalar values and bytes() when the encoding bytes themselves are the subject.",
            exampleCaption: "The crab is one char but several UTF-8 bytes.",
            exampleCode: """
            let crab: char = '🦀';
            let word: &str = "Rust";
            println!("{crab} {}", word.len());
            """,
            task: "Print one char and compare byte length with chars().count().",
            success: "You can explain why a Unicode symbol may occupy more than one byte.",
            rule: "String indexing by an arbitrary byte is forbidden because UTF-8 boundaries matter.",
            practiceCode: """
            let text = "🦀";
            println!("{}", text.len());
            """,
            question: "What does len() report for &str?",
            answers: [
                "Visible symbols",
                "UTF-8 bytes",
                "Words",
            ],
            correctAnswer: 1,
            feedback: "Use text.chars().count() when Unicode scalar values are the unit you need."
        ),
        "compiler-feedback": RustLessonWriting(
            summary: "A rustc diagnostic is structured evidence: location, cause, and often a useful next move.",
            explanation: "Start at the primary span rather than the first line of prose. Then compare the expected and found types, read labels attached to nearby expressions, and treat help text as a candidate rather than a command. Fix the earliest root error first; many later messages are consequences that disappear after one correct edit.",
            exampleCaption: "The annotation creates an expected type rustc can compare.",
            exampleCode: """
            fn main() {
                let count: u32 = "four";
                println!("{count}");
            }
            """,
            task: "Identify the primary span, expected type, and found type before editing.",
            success: "Your explanation names the mismatch and the smallest intentional fix.",
            rule: "Repair the first causal error before chasing its downstream messages.",
            practiceCode: """
            let enabled: bool = 1;
            """,
            question: "Which part of the diagnostic is the best starting point?",
            answers: [
                "The primary source span and expected/found pair",
                "The final warning in the file",
                "Any suggested cast, applied automatically",
            ],
            correctAnswer: 0,
            feedback: "The primary span anchors the message to the expression that established the conflict."
        ),
        "block-expressions": RustLessonWriting(
            summary: "A block can perform statements and then produce one final value.",
            explanation: "Most Rust syntax is expression-oriented. The last expression in a block becomes its value when it has no semicolon. Adding a semicolon changes that expression into a statement and the block then produces (), the unit value. This one rule explains function returns, if branches, match arms, and scoped calculations.",
            exampleCaption: "The final multiplication becomes the value of the block.",
            exampleCode: """
            let score = {
                let base = 7;
                base * 2
            };
            println!("{score}");
            """,
            task: "Calculate a value inside a block and return it without return.",
            success: "The binding receives the tail expression's numeric value.",
            rule: "No semicolon means a tail value; a semicolon turns it into ().",
            practiceCode: """
            let value = {
                let base = 3;
                base + 1;
            };
            """,
            question: "What type does value have?",
            answers: ["i32", "bool", "()"],
            correctAnswer: 2,
            feedback: "The semicolon discards the numeric value, leaving the block's unit value."
        ),
        "function-parameters": RustLessonWriting(
            summary: "A function signature is a compact contract for every caller.",
            explanation: "Rust requires every parameter type to be written, which lets the body and every call be checked independently. Arguments are the concrete values passed at a call site; parameters are the named inputs in the definition. Passing an owned type may move it, while a reference lets the function borrow it — a distinction later lessons develop in depth.",
            exampleCaption: "Both inputs and the output are visible before reading the body.",
            exampleCode: """
            fn area(width: u32, height: u32) -> u32 {
                width * height
            }

            let result = area(4, 3);
            """,
            task: "Write a two-parameter function and call it with matching arguments.",
            success: "The signature communicates exactly which values enter and leave.",
            rule: "Parameters need explicit types; arguments must satisfy them.",
            practiceCode: """
            fn double(value: u32) -> u32 {
                value * 2
            }
            let answer = double("4");
            """,
            question: "Why is the call rejected?",
            answers: [
                "The argument is &str but the parameter is u32",
                "Functions cannot accept literals",
                "double must return String",
            ],
            correctAnswer: 0,
            feedback: "The call site must provide the u32 promised by the parameter type."
        ),
        "ranges": RustLessonWriting(
            summary: "Range syntax makes boundaries visible instead of hiding an off-by-one rule.",
            explanation: "The range 0..3 contains 0, 1, and 2; its upper bound is excluded. The inclusive form 1..=3 also contains 3. Half-open ranges fit indexing because a length can be used directly as the excluded end. Inclusive ranges are useful when both endpoints belong to the domain.",
            exampleCaption: "The two ranges have different upper-bound rules.",
            exampleCode: """
            for index in 0..3 {
                println!("index {index}");
            }
            for value in 1..=3 {
                println!("value {value}");
            }
            """,
            task: "Choose one half-open and one inclusive range and predict every value.",
            success: "The output has no missing or accidental extra endpoint.",
            rule: "a..b excludes b; a..=b includes b.",
            practiceCode: """
            let values: Vec<_> = (2..5).collect();
            """,
            question: "Which values are collected?",
            answers: ["2, 3, 4", "2, 3, 4, 5", "3, 4, 5"],
            correctAnswer: 0,
            feedback: "The upper bound of .. is excluded, so 5 is not part of the range."
        ),
        "loops": RustLessonWriting(
            summary: "Choose the loop form that states why repetition ends.",
            explanation: "for consumes an iterator, while repeats while a condition remains true, and loop has no condition at all. A loop expression can return a value with break value. continue skips directly to the next iteration. Selecting the narrowest form makes termination easier to see and accidental infinite work harder to write.",
            exampleCaption: "break returns count as the value of the loop expression.",
            exampleCode: """
            let mut count = 0;
            let answer = loop {
                count += 1;
                if count == 3 { break count; }
            };
            println!("{answer}");
            """,
            task: "Use loop with a valued break, then rewrite a fixed pass as for.",
            success: "Each loop has a visible reason to stop and prints the expected count.",
            rule: "Prefer for for iteration; use loop when break defines the exit.",
            practiceCode: """
            let value = loop {
                break 7;
            };
            """,
            question: "What is stored in value?",
            answers: ["()", "7", "true"],
            correctAnswer: 1,
            feedback: "A value after break becomes the value produced by the loop expression."
        ),
        "parsing": RustLessonWriting(
            summary: "Parsing crosses from untrusted text into a type with explicit success or failure.",
            explanation: "parse is generic: the destination type tells it what grammar to use. Because arbitrary text may be invalid, the result is Result rather than a bare value. A type annotation or turbofish such as parse::<i32>() resolves the target type, after which match, ?, or another deliberate policy handles failure.",
            exampleCaption: "The annotation tells parse which numeric type to produce.",
            exampleCode: """
            let parsed: Result<i32, _> = "42".parse();
            match parsed {
                Ok(value) => println!("{value}"),
                Err(error) => println!("{error}"),
            }
            """,
            task: "Parse one valid and one invalid integer and handle both outcomes.",
            success: "Invalid text follows an error branch instead of crashing the program.",
            rule: "Parsing returns Result because input text is not guaranteed to fit the target type.",
            practiceCode: """
            let value = "42".parse();
            """,
            question: "What information is missing?",
            answers: [
                "The numeric target type",
                "A mutable string",
                "A loop around parse",
            ],
            correctAnswer: 0,
            feedback: "Annotate the binding or call parse::<i32>() so inference has a target."
        ),
        "references-intro": RustLessonWriting(
            summary: "A shared reference lets a function read a value while the caller keeps ownership.",
            explanation: "The & symbol creates a borrow. A shared reference such as &str permits reading but not mutation, and it does not own the value it points to. Passing a reference avoids a move, so the original binding remains usable after the call. Later ownership lessons add the precise aliasing rules and mutable references.",
            exampleCaption: "length borrows text, so main can print it again.",
            exampleCode: """
            fn length(text: &str) -> usize {
                text.len()
            }

            let name = String::from("Crabrix");
            println!("{} {name}", length(&name));
            """,
            task: "Pass text to a function by reference and use the owner afterward.",
            success: "The caller retains ownership and no clone is needed.",
            rule: "&T borrows T for read-only use without transferring ownership.",
            practiceCode: """
            fn show(text: String) {
                println!("{text}");
            }
            let name = String::from("Ferris");
            show(name);
            println!("{name}");
            """,
            question: "What signature keeps name usable?",
            answers: [
                "fn show(text: &str)",
                "fn show(mut text: String)",
                "fn show(text: Box<String>)",
            ],
            correctAnswer: 0,
            feedback: "Borrowing &str lets show read the text without taking its String owner."
        ),
        "methods-intro": RustLessonWriting(
            summary: "Method syntax puts an operation beside the value it acts on.",
            explanation: "A method call uses dot syntax, and Rust automatically borrows or dereferences the receiver when the signature makes that unambiguous. Chaining is readable when each step produces the value the next step expects. Watch ownership: some methods borrow the receiver, while others consume it and return a new value.",
            exampleCaption: "trim borrows; to_uppercase creates a new owned String.",
            exampleCode: """
            let name = String::from(" crab ");
            let clean = name.trim().to_uppercase();
            println!("{clean}");
            """,
            task: "Chain two text methods and identify which step allocates a new String.",
            success: "You can tell whether each receiver is borrowed or consumed.",
            rule: "Read a method's self parameter to learn its ownership effect.",
            practiceCode: """
            let text = String::from("rust");
            let size = text.len();
            println!("{text} {size}");
            """,
            question: "Why is text still usable after len()?",
            answers: [
                "len borrows self rather than consuming it",
                "usize restores the String",
                "All methods copy their receiver",
            ],
            correctAnswer: 0,
            feedback: "The receiver is &self, so the method reads through a temporary borrow."
        ),
        "recoverable-errors": RustLessonWriting(
            summary: "Result keeps expected failure in the function's type instead of turning it into a crash.",
            explanation: "A function returning Result<T, E> makes callers handle both success and failure. match is the clearest first tool because both branches stay visible. The ? operator becomes useful once a surrounding function also returns a compatible Result. panic and expect are better reserved for broken invariants or controlled examples, not routine bad input.",
            exampleCaption: "The caller chooses what an invalid number means for this program.",
            exampleCode: """
            fn half(raw: &str) -> Result<i32, String> {
                let value = raw.parse::<i32>()
                    .map_err(|_| "not a number".to_string())?;
                Ok(value / 2)
            }
            """,
            task: "Return a descriptive Result for invalid input and handle it at the caller.",
            success: "Bad text produces a normal error value, not a panic.",
            rule: "Use Result for failure the caller can reasonably respond to.",
            practiceCode: """
            fn read(raw: &str) -> i32 {
                raw.parse().unwrap()
            }
            """,
            question: "Why is Result a better return type here?",
            answers: [
                "Invalid external text is an expected possibility",
                "Result parses faster",
                "Integers can only be returned inside Result",
            ],
            correctAnswer: 0,
            feedback: "Let the caller decide how to recover instead of forcing a panic."
        ),
        "debugging-values": RustLessonWriting(
            summary: "Debug output is evidence for development, not part of the program's user-facing result.",
            explanation: "The {:?} formatter uses the Debug trait. dbg! prints the expression, source location, and value to stderr, then returns the value unchanged. Borrow with dbg!(&value) when you want to inspect an owned value without moving it. Remove noisy probes or replace them with deliberate logging before shipping.",
            exampleCaption: "Borrowing lets dbg! inspect the Vec without consuming it.",
            exampleCode: """
            let items = vec!["crab", "rust"];
            dbg!(&items);
            println!("{} items", items.len());
            """,
            task: "Inspect an intermediate value and keep the program's stdout stable.",
            success: "The debug probe appears on stderr and the value remains usable.",
            rule: "dbg! returns its argument and writes diagnostic output to stderr.",
            practiceCode: """
            let name = String::from("Ferris");
            dbg!(name);
            println!("{name}");
            """,
            question: "Which edit keeps name usable?",
            answers: ["dbg!(&name)", "dbg!(mut name)", "dbg!(name.clone)"] ,
            correctAnswer: 0,
            feedback: "Pass a shared reference so the debug probe does not take ownership."
        ),
    ]

    static let termPairs: [TermTrainPair] = [
        TermTrainPair(id: "format-placeholder", term: "Format placeholder", description: "A compile-checked slot such as {name} inside println!.", topic: "print-formatting"),
        TermTrainPair(id: "numeric-suffix", term: "Numeric suffix", description: "A literal ending such as 10_u8 that fixes its concrete type.", topic: "number-types"),
        TermTrainPair(id: "boolean-expression", term: "Boolean expression", description: "A comparison or logical combination whose type is exactly bool.", topic: "booleans-comparisons"),
        TermTrainPair(id: "unicode-char", term: "char", description: "One Unicode scalar value, written with single quotes.", topic: "chars-and-text"),
        TermTrainPair(id: "compiler-span", term: "Compiler span", description: "The source range a diagnostic labels as evidence for an error.", topic: "compiler-feedback"),
        TermTrainPair(id: "block-value", term: "Block value", description: "The final expression produced when its semicolon is omitted.", topic: "block-expressions"),
        TermTrainPair(id: "function-parameter", term: "Function parameter", description: "A typed name in a definition that every argument must satisfy.", topic: "function-parameters"),
        TermTrainPair(id: "inclusive-range", term: "Inclusive range", description: "The a..=b form whose upper endpoint belongs to the iteration.", topic: "ranges"),
        TermTrainPair(id: "loop-expression", term: "loop", description: "Unconditional repetition that can produce a value through break.", topic: "loops"),
        TermTrainPair(id: "parse-target", term: "parse::<T>()", description: "Converts text toward an explicit target type and returns Result.", topic: "parsing"),
        TermTrainPair(id: "shared-reference", term: "Shared reference", description: "An &T borrow that permits reading without taking ownership.", topic: "references-intro"),
        TermTrainPair(id: "method-syntax", term: "Method syntax", description: "A dot call whose self parameter reveals borrowing or consumption.", topic: "methods-intro"),
        TermTrainPair(id: "recoverable-error", term: "Recoverable error", description: "An expected failure represented as Err so the caller can respond.", topic: "recoverable-errors"),
        TermTrainPair(id: "debug-macro", term: "dbg!", description: "Prints a source location and Debug value to stderr, then returns it.", topic: "debugging-values"),
    ]
}
