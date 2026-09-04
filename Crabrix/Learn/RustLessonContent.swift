import Foundation

/// Written content for a lesson: what it is, why it bites, and one snippet.
///
/// This lives apart from the view so the curriculum can grow without the lesson
/// screen growing with it.
struct RustLessonWriting: Sendable {
    let summary: String
    let explanation: String
    let exampleCaption: String
    let exampleCode: String
    let task: String
    let success: String
    let rule: String
    let practiceCode: String
    let question: String
    let answers: [String]
    let correctAnswer: Int
    let feedback: String
}

enum RustLessonLibrary {
    static func writing(for id: String) -> RustLessonWriting? {
        entries[id]
            ?? RustBasicsExpansion.writing[id]
            ?? RustAdvancedExpansion.writing[id]
            ?? AlgorithmCourseCatalog.writing(for: id)
    }

    private static let entries: [String: RustLessonWriting] = [
        "hello-rust": RustLessonWriting(
            summary: "Every Rust program starts at main, but the lesson is the whole loop.",
            explanation: "Edit, compile, run, read the output — that cycle is what you will repeat for everything else. println! is a macro, so the exclamation mark means it expands into code before compilation, which is how it can check your format string at compile time rather than at runtime.",
            exampleCaption: "The format string is checked while compiling, not when it runs.",
            exampleCode: """
            fn main() {
                let name = "Crabrix";
                println!("Hello, {name}!");
            }
            """,
            task: "Change the greeting, run it locally, and read stdout.",
            success: "stdout shows your edited greeting and the build exits with code 0.",
            rule: "Execution starts in fn main(); println! writes a formatted line to stdout.",
            practiceCode: """
            fn main() {
                println!("{}", "Crabrix");
            }
            """,
            question: "Why does println! end with an exclamation mark?",
            answers: [
                "It returns a Result the caller has to handle",
                "It is a macro, expanded into code before compilation",
                "It writes to stderr rather than stdout",
            ],
            correctAnswer: 1,
            feedback: "Macros expand at compile time, which is how the format string is verified."
        ),
        "variables": RustLessonWriting(
            summary: "Bindings are immutable unless you opt in.",
            explanation: "Rust makes state changes visible in the code with mut, so a reader never has to guess whether something moves under them. Shadowing is a different tool: it creates a brand new binding with the same name, which may even have a different type, leaving the original untouched.",
            exampleCaption: "Shadowing makes a new binding; mut changes an existing one.",
            exampleCode: """
            let total = 10;        // immutable
            let total = total + 5; // shadowed
            let mut counter = 0;   // mutable
            counter += 1;
            """,
            task: "Create an immutable value, shadow it, then update one mutable counter.",
            success: "It compiles with no unused-mutation warning.",
            rule: "mut permits mutation; shadowing replaces the binding entirely.",
            practiceCode: """
            let value = 5;
            value = 6;
            """,
            question: "Why does that fail?",
            answers: [
                "5 and 6 are different types",
                "value is immutable without mut",
                "Numbers cannot be reassigned",
            ],
            correctAnswer: 1,
            feedback: "Add mut, or shadow with a second let if a new binding is what you meant."
        ),
        "types": RustLessonWriting(
            summary: "Rust checks scalar and compound types before the program runs.",
            explanation: "Tuples group a fixed number of possibly different types and are read by position. Arrays hold one type with a length known at compile time, which is exactly what lets the compiler bounds-check them and reject an out-of-range index it can see.",
            exampleCaption: "Position for a tuple, index for an array.",
            exampleCode: """
            let point: (i32, f64) = (3, 1.5);
            let scores: [u8; 4] = [90, 75, 60, 88];
            println!("{} {}", point.0, scores[2]);
            """,
            task: "Build one tuple and one array, then read a value from each.",
            success: "The output shows both values with no type mismatch.",
            rule: "A tuple mixes types by position; an array holds one type with a fixed length.",
            practiceCode: """
            let items: [i32; 3] = [1, 2, 3];
            let value = items[5];
            """,
            question: "What happens with that index?",
            answers: [
                "It compiles and panics at runtime with an index error",
                "The compiler rejects an index it can prove is out of range",
                "It wraps around to the first element like a ring buffer",
            ],
            correctAnswer: 1,
            feedback: "A constant index past a known length is a compile error, not a runtime surprise."
        ),
        "control-flow": RustLessonWriting(
            summary: "Expressions and loops model decisions without hidden coercion.",
            explanation: "Because if is an expression, both branches must produce the same type — there is no silent conversion to paper over a mismatch. loop, while, and for then express three different repetition rules: forever, until a condition fails, and over an iterator.",
            exampleCaption: "if is an expression, so both arms must agree on a type.",
            exampleCode: """
            let label = if value % 2 == 0 {
                "even"
            } else {
                "odd"
            };
            for index in 0..3 {
                println!("{index}: {label}");
            }
            """,
            task: "Use if to classify a number and for to visit a range.",
            success: "Each number prints once with the right classification.",
            rule: "if is an expression; every branch must produce the same type.",
            practiceCode: """
            let value = if flag { 1 } else { "two" };
            """,
            question: "Why is that rejected?",
            answers: [
                "The condition must be an integer, not a bool",
                "The branches produce different types",
                "An if expression cannot be bound with let",
            ],
            correctAnswer: 1,
            feedback: "An if expression has one type, so every branch has to match."
        ),
        "ownership": RustLessonWriting(
            summary: "Ownership gives every value one clear cleanup responsibility.",
            explanation: "Moves transfer that responsibility to a new binding and make the old one unusable. Copy types duplicate instead of moving, and Drop runs the moment the owner leaves scope — which is how Rust frees memory with no garbage collector and no possibility of a double free. When you genuinely need two usable values, clone() makes a second one that owns its own data.",
            exampleCaption: "The move is what makes a double free impossible.",
            exampleCode: """
            let first = String::from("crab");
            let second = first; // ownership moves
            // println!("{first}");
            // ^ error[E0382]: value moved
            println!("{second}");
            """,
            task: "Predict which binding still owns a String after an assignment.",
            success: "You can explain why no double free is possible.",
            rule: "One value, one owner; a move ends the previous binding.",
            practiceCode: """
            let a = String::from("x");
            let b = a;
            println!("{a}");
            """,
            question: "What is the smallest fix that keeps both usable?",
            answers: ["Add mut to a", "Use a.clone() for b", "Wrap a in a Box"],
            correctAnswer: 1,
            feedback: "Cloning creates a second owned String rather than moving the first."
        ),
        "borrowing": RustLessonWriting(
            summary: "Borrowing lets code use a value without taking ownership.",
            explanation: "Rust permits many shared references or exactly one mutable reference, never both. The compiler tracks the region where each borrow is actually used, so a borrow ends at its last use rather than at the end of the block — which is why moving one line is often the whole fix.",
            exampleCaption: "The borrow ends at its last use, and the push is fine after that.",
            exampleCode: """
            let mut items = vec![
                String::from("ada"),
            ];
            let first = &items[0]; // borrow
            println!("{first}");   // ...ends
            items.push(String::from("grace"));
            """,
            task: "Repair E0502 with the smallest edit that keeps the push and the printed value.",
            success: "Check passes, Run prints the first item, and the Vec is still extended.",
            rule: "Many shared borrows or one mutable borrow, never both at once.",
            practiceCode: """
            let mut items = vec![1, 2];
            let first = &items[0];
            items.push(3);
            println!("{first}");
            """,
            question: "Which edit fixes it without removing anything?",
            answers: [
                "Make items immutable",
                "Move the println! above the push",
                "Clone the whole vector",
            ],
            correctAnswer: 1,
            feedback: "Ending the shared borrow before the mutation is the minimal change."
        ),
        "slices": RustLessonWriting(
            summary: "Slices are borrowed views into contiguous data.",
            explanation: "A slice stores a pointer and a length but owns nothing, so creating one allocates no memory. Because it borrows, the compiler will not let it outlive the String or array it points into, which rules out a dangling view.",
            exampleCaption: "No allocation, and the result cannot outlive its input.",
            exampleCode: """
            fn first_word(text: &str) -> &str {
                match text.find(' ') {
                    Some(i) => &text[..i],
                    None => text,
                }
            }
            """,
            task: "Return the first word as &str without allocating.",
            success: "The slice ends before the first space and stays tied to its input.",
            rule: "A slice borrows a range; it allocates nothing.",
            practiceCode: """
            fn first(text: &str) -> &str {
                &text[..3]
            }
            """,
            question: "What does that return type mean?",
            answers: [
                "A newly allocated String the caller owns",
                "A borrowed view tied to the input's lifetime",
                "A copy of the first three bytes of the input",
            ],
            correctAnswer: 1,
            feedback: "The returned &str borrows from text, so it cannot outlive it."
        ),
        "lifetimes-intro": RustLessonWriting(
            summary: "Lifetimes describe relationships between references, not timers.",
            explanation: "An annotation does not change how long anything lives. It tells the compiler how input and output borrows are connected, so it can prove a returned reference never outlives the data behind it. Most of the time inference handles this and you write nothing at all.",
            exampleCaption: "One name ties the result to both inputs.",
            exampleCode: """
            fn longest<'a>(
                left: &'a str,
                right: &'a str,
            ) -> &'a str {
                if left.len() > right.len() {
                    left
                } else {
                    right
                }
            }
            """,
            task: "Describe which input borrow a returned reference may depend on.",
            success: "No returned reference can outlive the data it points into.",
            rule: "A lifetime annotation relates borrows; it never extends one.",
            practiceCode: """
            fn pick(a: &str, b: &str) -> &str {
                if a.len() > b.len() { a } else { b }
            }
            """,
            question: "Why does that need an annotation?",
            answers: [
                "Two inputs mean the compiler cannot tell which one the result borrows from",
                "A &str return always needs an annotation",
                "Every function that borrows must annotate its lifetimes",
            ],
            correctAnswer: 0,
            feedback: "With one input reference it is inferred; with two the relationship must be stated."
        ),
        "structs": RustLessonWriting(
            summary: "Structs give related data names and a stable shape.",
            explanation: "impl blocks attach constructors and methods to the type. The receiver spells out the ownership contract: self consumes the value, &self borrows it for reading, and &mut self borrows it for modification — so a method signature tells you what it will do before you read the body.",
            exampleCaption: "&self borrows, so the caller keeps ownership.",
            exampleCode: """
            struct Rectangle {
                width: u32,
                height: u32,
            }

            impl Rectangle {
                fn area(&self) -> u32 {
                    self.width * self.height
                }
            }
            """,
            task: "Model a Rectangle and add an area method.",
            success: "The method borrows the rectangle and prints the expected area.",
            rule: "self consumes, &self reads, &mut self modifies.",
            practiceCode: """
            impl Counter {
                fn bump(self) -> u32 { self.value + 1 }
            }
            """,
            question: "What is wrong with that receiver?",
            answers: [
                "Nothing — a method may take self by value freely",
                "self consumes the counter, so it cannot be used again",
                "It should return Self so the call can be chained",
            ],
            correctAnswer: 1,
            feedback: "&self or &mut self keeps the value usable after the call."
        ),
        "enums": RustLessonWriting(
            summary: "Enums model a value that is exactly one of several variants.",
            explanation: "match forces every variant to be handled, so adding a new state turns every incomplete match into a compile error instead of a silent bug. Variants can carry data, which lets one type model a whole state machine rather than a bag of loosely related fields.",
            exampleCaption: "Adding a variant breaks every match that does not handle it.",
            exampleCode: """
            enum Message {
                Quit,
                Move { x: i32, y: i32 },
                Write(String),
            }

            match message {
                Message::Quit => println!("quit"),
                Message::Move { x, y } => {
                    println!("move {x},{y}")
                }
                Message::Write(t) => println!("{t}"),
            }
            """,
            task: "Define a message enum and render every variant with match.",
            success: "The match is exhaustive without a wildcard hiding a case.",
            rule: "match is exhaustive: every variant must be handled.",
            practiceCode: """
            match state {
                State::Idle => run(),
                _ => {}
            }
            """,
            question: "What does the wildcard cost you?",
            answers: [
                "Nothing — a wildcard arm keeps the match exhaustive",
                "A new variant silently falls into it instead of erroring",
                "It makes the match slower by adding a runtime check",
            ],
            correctAnswer: 1,
            feedback: "A catch-all removes the compiler's help exactly when you add a state."
        ),
        "option-result": RustLessonWriting(
            summary: "Option models absence; Result models failure with a reason.",
            explanation: "Pattern matching and the ? operator keep both cases explicit without null, sentinel values, or exceptions. Reach for Option when absence is normal and expected, and Result when the caller needs to know why something did not work.",
            exampleCaption: "? returns early on the error case, keeping the happy path flat.",
            exampleCode: """
            use std::num::ParseIntError;

            fn parse_port(
                raw: &str,
            ) -> Result<u16, ParseIntError> {
                let port: u16 = raw.parse()?;
                Ok(port)
            }
            """,
            task: "Choose Option or Result for two small APIs and handle both branches.",
            success: "No unwrap is needed on the normal path.",
            rule: "Option for absence, Result when the caller needs the reason.",
            practiceCode: """
            fn find(id: u32) -> ??? {
                // nothing found is normal here
            }
            """,
            question: "Which fits 'the item may simply not exist'?",
            answers: ["Result<T, E>", "Option<T>", "A panic"],
            correctAnswer: 1,
            feedback: "There is no error to report — absence is the expected outcome."
        ),
        "collections": RustLessonWriting(
            summary: "Vec, String, and HashMap own growable data with different trade-offs.",
            explanation: "Choosing a collection is part of the model, not an afterthought: order, uniqueness, and key access all change what your code can promise. Each of these owns its data, so passing one around follows exactly the same ownership rules as any other value.",
            exampleCaption: "entry inserts a default only when the key is missing.",
            exampleCode: """
            use std::collections::HashMap;

            let mut counts: HashMap<&str, u32> =
                HashMap::new();
            for word in text.split_whitespace() {
                *counts.entry(word).or_insert(0) += 1;
            }
            """,
            task: "Count repeated words with a HashMap entry.",
            success: "The map holds the correct count for every word.",
            rule: "entry().or_insert() gives you a mutable reference either way.",
            practiceCode: """
            let mut map = HashMap::new();
            map.insert("a", map.get("a").unwrap_or(&0) + 1);
            """,
            question: "Why is entry() better here?",
            answers: [
                "It is shorter to type than a match on get()",
                "It looks the key up once instead of twice",
                "It keeps the map sorted by insertion order",
            ],
            correctAnswer: 1,
            feedback: "entry avoids a second lookup and the borrow conflict that comes with it."
        ),
        "generics": RustLessonWriting(
            summary: "Generics reuse an algorithm while keeping concrete types.",
            explanation: "Trait bounds state exactly the capabilities the generic body needs, and the compiler generates a specialised copy per concrete type. That means generics cost nothing at runtime — but a bound wider than necessary narrows who can call you.",
            exampleCaption: "The bound names only what the body actually needs.",
            exampleCode: """
            fn largest<T: PartialOrd>(
                items: &[T],
            ) -> &T {
                let mut best = &items[0];
                for item in items {
                    if item > best { best = item; }
                }
                best
            }
            """,
            task: "Write a largest function with the smallest useful trait bound.",
            success: "It works for two different ordered types.",
            rule: "Monomorphisation makes generics free at runtime.",
            practiceCode: """
            fn show<T: Clone + PartialOrd + Debug>(v: &T) {
                println!("{v:?}");
            }
            """,
            question: "What is wrong with those bounds?",
            answers: [
                "Nothing — extra bounds cost the caller nothing",
                "Only Debug is used, so the rest exclude callers for no reason",
                "Debug should be dropped and the rest kept",
            ],
            correctAnswer: 1,
            feedback: "Every unnecessary bound is a caller you turned away."
        ),
        "traits": RustLessonWriting(
            summary: "Traits define shared behaviour independently of a concrete type.",
            explanation: "A generic bound is resolved at compile time, so the call is direct and inlinable. dyn Trait defers the choice to runtime through a vtable, which costs an indirection but lets you store different concrete types together in one collection. A dyn value has no size the compiler can plan for, so it lives behind a pointer: Box<dyn Trait> is what goes into a Vec.",
            exampleCaption: "The same trait, reached two different ways.",
            exampleCode: """
            trait Shape {
                fn area(&self) -> f64;
            }

            // static dispatch, resolved at compile time
            fn a<S: Shape>(s: &S) -> f64 { s.area() }

            // dynamic dispatch, through a vtable
            fn b(s: &dyn Shape) -> f64 { s.area() }
            """,
            task: "Implement one trait for two types and compare the two call styles.",
            success: "Both produce the same behaviour and you can state the trade-off.",
            rule: "Generic bound: compile time. dyn Trait: runtime, one indirection.",
            practiceCode: """
            let shapes: Vec<???> = vec![circle, square];
            """,
            question: "What lets one Vec hold different shape types?",
            answers: ["Vec<impl Shape>", "Vec<Box<dyn Shape>>", "Vec<S: Shape>"],
            correctAnswer: 1,
            feedback: "A trait object erases the concrete type so the elements share one size."
        ),
        "lifetimes": RustLessonWriting(
            summary: "Lifetime annotations connect the borrows in a signature.",
            explanation: "Elision handles the common shapes, so you write annotations only when the relationship is genuinely ambiguous — typically when several references go in and one comes out. A struct holding a reference needs one too, because the struct cannot outlive what it borrows.",
            exampleCaption: "The struct is tied to the text it borrows.",
            exampleCode: """
            struct Excerpt<'a> {
                part: &'a str,
            }

            impl<'a> Excerpt<'a> {
                fn part(&self) -> &str {
                    self.part
                }
            }
            """,
            task: "Store a borrowed slice in a struct and explain the annotation.",
            success: "The struct cannot outlive the data it points into.",
            rule: "A struct holding a reference is bounded by that reference's lifetime.",
            practiceCode: """
            struct Holder {
                value: &str,
            }
            """,
            question: "Why is that rejected?",
            answers: [
                "A struct field can never hold a &str",
                "The struct must declare the lifetime it borrows for",
                "The value field has to be declared mut",
            ],
            correctAnswer: 1,
            feedback: "Write struct Holder<'a> { value: &'a str } so the relationship is stated."
        ),
        "iterators": RustLessonWriting(
            summary: "Iterators compose lazy transformations before consuming results.",
            explanation: "map and filter build a description of the work; nothing runs until a consumer such as collect, sum, or a for loop asks for items. That laziness is why a long chain still makes a single pass over the data instead of one pass per step.",
            exampleCaption: "Nothing runs until collect asks for items.",
            exampleCode: """
            let squares: Vec<u32> = (1..=6)
                .filter(|v| v % 2 == 0)
                .map(|v| v * v)
                .collect();
            """,
            task: "Transform a range with filter and map, then collect it.",
            success: "The Vec holds only the expected transformed values.",
            rule: "Adapters are lazy; a consumer is what makes the work happen.",
            practiceCode: """
            let names = list.iter().map(|n| n.to_uppercase());
            println!("done");
            """,
            question: "What work has been done by that point?",
            answers: [
                "Every name has already been uppercased",
                "None — nothing consumed the iterator",
                "Only the first element has been mapped",
            ],
            correctAnswer: 1,
            feedback: "map returns a lazy adapter; without a consumer it never runs."
        ),
        "modules": RustLessonWriting(
            summary: "Modules split a crate into files, and privacy shapes the surface.",
            explanation: "mod declares a module and use brings a path into scope, while pub decides what actually escapes. Cargo.toml describes the package around them — the same file the package manager reads to resolve your dependencies.",
            exampleCaption: "mod declares it; pub decides what leaves it.",
            exampleCode: """
            // src/main.rs
            mod greeter;

            fn main() {
                println!("{}", greeter::message());
            }

            // src/greeter.rs
            pub fn message() -> &'static str {
                "hello from a module"
            }
            """,
            task: "Open the multi-file project, trace mod greeter, and change its public function.",
            success: "It compiles from src/main.rs and prints the edited output.",
            rule: "Items are private by default; pub is what exposes them.",
            practiceCode: """
            mod util {
                fn helper() -> u32 { 1 }
            }
            let value = util::helper();
            """,
            question: "Why can't main call helper?",
            answers: [
                "It lives in a different file from main",
                "Items are private by default, so it needs pub",
                "A module function has to return a Result",
            ],
            correctAnswer: 1,
            feedback: "Privacy is the default; pub fn helper makes it reachable."
        ),
        "testing": RustLessonWriting(
            summary: "Tests turn behaviour into executable evidence.",
            explanation: "#[test] functions are compiled only for the test harness, so they cost nothing in a release build. Unit tests sit beside the code and can reach its private details; integration tests live in tests/ and see only the public API, which is a useful check on your own interface.",
            exampleCaption: "Tests live beside the code and can see its private parts.",
            exampleCode: """
            #[cfg(test)]
            mod tests {
                use super::*;

                #[test]
                fn adds_two_numbers() {
                    assert_eq!(add(2, 2), 4);
                }
            }
            """,
            task: "Add one success case and one boundary case for a pure function.",
            success: "Both are deterministic and fail for a deliberately broken implementation.",
            rule: "#[cfg(test)] keeps test code out of the release build entirely.",
            practiceCode: """
            #[test]
            fn works() {
                let result = compute();
            }
            """,
            question: "What is missing?",
            answers: [
                    "A return type so the harness can read the result",
                "An assertion — the test passes no matter what compute returns",
                "The #[cfg(test)] attribute above the module",
            ],
            correctAnswer: 1,
            feedback: "A test with no assertion only proves the code did not panic."
        ),
        "errors": RustLessonWriting(
            summary: "Good errors preserve context and keep recovery near the caller.",
            explanation: "Result, custom error types, and ? separate expected failure from programmer mistakes. A panic says this should never happen; a Result says the caller has a decision to make — and conflating the two is what makes error handling painful later.",
            exampleCaption: "? propagates the failure instead of ending the process.",
            exampleCode: """
            fn load(
                path: &str,
            ) -> Result<String, std::io::Error> {
                let text = std::fs::read_to_string(path)?;
                Ok(text)
            }
            """,
            task: "Replace a panic with a Result and propagate it through one caller.",
            success: "The caller handles the failure without losing its cause.",
            rule: "Panic for a bug; Result for a situation the caller can act on.",
            practiceCode: """
            fn read(path: &str) -> String {
                std::fs::read_to_string(path).unwrap()
            }
            """,
            question: "What does unwrap do to a caller here?",
            answers: [
                "Returns an empty string on failure",
                "Ends the process, removing any chance to recover",
                "Logs a warning and carries on with a default",
            ],
            correctAnswer: 1,
            feedback: "Returning Result hands the decision to whoever knows what to do."
        ),
        "concurrency": RustLessonWriting(
            summary: "Threads run in parallel, and ownership decides what may cross.",
            explanation: "thread::spawn takes a closure that must own everything it touches, which is why move appears so often. join waits for a result. Rust moves many data races from runtime accidents to compile-time errors, because a type that is unsafe to share simply cannot be sent.",
            exampleCaption: "move gives the closure ownership so it can outlive this scope.",
            exampleCode: """
            let values = vec![1, 2, 3];

            let handle = std::thread::spawn(move || {
                values.iter().sum::<i32>()
            });

            let total = handle.join().unwrap();
            println!("{total}");
            """,
            task: "Spawn a thread that owns its data and return a result with join.",
            success: "The value is computed off the main thread and joined back.",
            rule: "A spawned closure must own what it uses, hence move.",
            practiceCode: """
            let data = vec![1, 2, 3];
            std::thread::spawn(|| println!("{data:?}"));
            """,
            question: "What does the compiler ask for?",
            answers: [
                    "A return type so the thread can report back",
                "move, so the closure owns data rather than borrowing it",
                "The captured data has to be declared mut",
            ],
            correctAnswer: 1,
            feedback: "The thread may outlive this scope, so a borrow is not enough."
        ),
        "q-atomics": RustLessonWriting(
            summary: "An atomic is a value several threads may touch without a lock.",
            explanation: "Ordering is the interesting half of the answer. Relaxed guarantees only that the operation itself is indivisible; Acquire and Release pair up to publish everything written before a release to whoever performs the matching acquire; SeqCst adds a single global order and costs the most. Reaching for SeqCst everywhere is not wrong, only slow, and saying that out loud is what an interviewer wants.",
            exampleCaption: "Release publishes the writes before it; Acquire sees them.",
            exampleCode: """
            use std::sync::atomic::{AtomicBool, Ordering};

            READY.store(true, Ordering::Release);
            if READY.load(Ordering::Acquire) {
                // everything written before the store
                // is visible here
            }
            """,
            task: "Explain Relaxed, Acquire/Release, and SeqCst in one minute each.",
            success: "You can say what each ordering guarantees and what it costs.",
            rule: "Atomicity and ordering are separate promises; Relaxed gives only the first.",
            practiceCode: """
            COUNT.fetch_add(1, Ordering::Relaxed);
            """,
            question: "When is Relaxed the right choice there?",
            answers: [
                "Never — a shared counter always needs SeqCst",
                "When only the final total matters, not ordering against other data",
                "Only when a single thread touches the counter",
            ],
            correctAnswer: 1,
            feedback: "A pure statistics counter needs indivisibility, not publication."
        ),
        "q-deadlock": RustLessonWriting(
            summary: "Rust prevents data races, not deadlocks.",
            explanation: "The borrow checker knows nothing about the order in which you take locks, so two threads taking Mutex A then Mutex B, and B then A, will still hang. The standard answers are a global lock order, holding one lock at a time, using try_lock with a timeout, or removing shared state entirely by moving to channels. Knowing Rust does not solve this is the point of the question.",
            exampleCaption: "Two orders, one hang. The types all check out.",
            exampleCode: """
            // thread 1
            let _a = a.lock().unwrap();
            let _b = b.lock().unwrap();

            // thread 2
            let _b = b.lock().unwrap();
            let _a = a.lock().unwrap();
            """,
            task: "Name three ways to remove a deadlock without changing behaviour.",
            success: "Your answer includes a lock order and one lock-free alternative.",
            rule: "Data-race freedom is a compile-time guarantee; deadlock freedom is a design one.",
            practiceCode: """
            let a = first.lock().unwrap();
            let b = second.lock().unwrap();
            """,
            question: "What is the cheapest fix across the whole codebase?",
            answers: [
                "Wrap both in one Mutex, or always take them in one fixed order",
                "Use RwLock instead",
                "Add a sleep between the locks",
            ],
            correctAnswer: 0,
            feedback: "One lock, or one documented order, removes the cycle entirely."
        ),
        "q-channels-vs-mutex": RustLessonWriting(
            summary: "Share memory by communicating, or communicate by sharing memory.",
            explanation: "A channel moves ownership between threads, so there is nothing left to lock and the flow of data is visible in the code. A mutex keeps one copy that several threads mutate in place, which is better when the state is genuinely shared and read far more often than written. Choosing by shape rather than by habit is the answer being looked for.",
            exampleCaption: "The value moves; no lock is needed on either side.",
            exampleCode: """
            let (tx, rx) = std::sync::mpsc::channel();
            std::thread::spawn(move || {
                tx.send(compute()).unwrap();
            });
            let value = rx.recv().unwrap();
            """,
            task: "Pick channel or mutex for a metrics counter and for a work queue.",
            success: "Each choice names who owns the data and how often it is written.",
            rule: "Channels move ownership; a mutex shares it. Pick by data flow.",
            practiceCode: """
            // Many producers, one consumer, ordered work.
            let queue = ???;
            """,
            question: "Which fits better?",
            answers: ["Arc<Mutex<Vec<Job>>>", "An mpsc channel", "A global static"],
            correctAnswer: 1,
            feedback: "Many-producer, single-consumer is exactly what a channel is."
        ),
        "q-async-vs-threads": RustLessonWriting(
            summary: "Threads are for CPU work; async is for waiting.",
            explanation: "A thread costs a stack and a scheduler slot, which is fine for a few hundred and painful for a hundred thousand. Async tasks are state machines sharing a small pool of threads, so waiting on ten thousand sockets is cheap — but a task that computes without yielding blocks everything sharing its thread. The dividing line is whether the work waits or works.",
            exampleCaption: "Ten thousand of these is routine; ten thousand threads is not.",
            exampleCode: """
            async fn fetch(id: u32) -> Result<Body, Error> {
                let response = client.get(id).await?;
                Ok(response.body().await?)
            }
            """,
            task: "Decide between threads and async for two workloads and justify each.",
            success: "You separate waiting from computing rather than picking by fashion.",
            rule: "Async wins on concurrency; threads win on parallel computation.",
            practiceCode: """
            // Resize 500 images across 8 cores.
            let plan = ???;
            """,
            question: "Which is the better fit?",
            answers: [
                "An async runtime with 500 tasks",
                "A thread pool sized to the cores",
                "One thread per image",
            ],
            correctAnswer: 1,
            feedback: "It is CPU-bound, so parallelism is what helps, not concurrency."
        ),
        "q-blocking-async": RustLessonWriting(
            summary: "One blocking call can stall an entire async runtime.",
            explanation: "Async executors run many tasks on few threads and rely on each task yielding at an await. A synchronous file read, a long computation, or a std Mutex held across an await occupies its thread and starves every task queued behind it. The fixes are spawn_blocking, a dedicated pool, or an async-aware version of the call.",
            exampleCaption: "The blocking call is moved off the async threads.",
            exampleCode: """
            let text = tokio::task::spawn_blocking(|| {
                std::fs::read_to_string("big.csv")
            })
            .await??;
            """,
            task: "Find the blocking call in an async handler and move it off the runtime.",
            success: "No task holds an executor thread while it waits on something synchronous.",
            rule: "Never block an executor thread: yield, or move the work off it.",
            practiceCode: """
            async fn handler() {
                let data = std::fs::read("big.bin").unwrap();
            }
            """,
            question: "What does that do to the other tasks?",
            answers: [
                "Nothing — the runtime moves it to a blocking pool",
                "It holds an executor thread, stalling everything queued on it",
                "It panics because nothing polls the future",
            ],
            correctAnswer: 1,
            feedback: "The read is synchronous, so the task never yields while it runs."
        ),
        "q-cancellation": RustLessonWriting(
            summary: "In Rust, an async task is cancelled by dropping its future.",
            explanation: "There is no cancel signal to handle: the future is simply dropped at the next await point, so any state it held runs its destructors and any work in flight stops. That makes cleanup automatic but means a future must be cancel-safe — losing a half-consumed buffer or a partially applied write between awaits is the classic bug.",
            exampleCaption: "The losing branch is dropped, mid-await, with no warning.",
            exampleCode: """
            tokio::select! {
                result = read_request() => handle(result),
                _ = timeout => log("gave up"),
            }
            """,
            task: "Explain what cancel-safety means for a function that buffers between awaits.",
            success: "You can name one operation that is unsafe to cancel and why.",
            rule: "Cancellation is a drop; state between awaits must survive it or not exist.",
            practiceCode: """
            let mut buf = Vec::new();
            socket.read_buf(&mut buf).await?;
            store(buf).await?;
            """,
            question: "What breaks if that is cancelled between the two awaits?",
            answers: [
                "Nothing — Rust rolls the whole await back",
                "The bytes already read are dropped and silently lost",
                "The socket closes and the peer is notified",
            ],
            correctAnswer: 1,
            feedback: "The buffer lives in the future, so cancelling drops the read data."
        ),
        "q-stack-heap": RustLessonWriting(
            summary: "Where a value lives explains most of what Rust makes you write.",
            explanation: "The stack is a bump pointer with a size known at compile time, freed automatically as frames pop. The heap holds anything sized at runtime or outliving its frame, and needs an owner to free it. Box, Vec, and String are heap values with a small stack handle, which is exactly why moving one is cheap and cloning one is not.",
            exampleCaption: "Three words on the stack; the bytes are on the heap.",
            exampleCode: """
            let n = 42u64;             // 8 bytes, stack
            let s = String::from("x"); // ptr+len+cap
                                       // stack,
                                       // bytes heap
            """,
            task: "Say where each part of a Vec<String> lives and what a move copies.",
            success: "You can explain why moving a String is cheap but cloning it is not.",
            rule: "The stack holds the handle; the heap holds the data the handle points at.",
            practiceCode: """
            let a = vec![1u8; 1_000_000];
            let b = a;
            """,
            question: "How many bytes does that move copy?",
            answers: [
                "One million bytes, the whole buffer",
                "Three words: pointer, length, capacity",
                "None at all — a move is just a reference",
            ],
            correctAnswer: 1,
            feedback: "A move copies the handle; the heap allocation never moves."
        ),
        "q-virtual-memory": RustLessonWriting(
            summary: "Every pointer you see is virtual, and the kernel decides what it means.",
            explanation: "The MMU maps pages of your address space onto physical frames, so allocating memory usually just reserves address range. Touching a page for the first time causes a page fault the kernel resolves by finding a frame — which is why a large allocation can be instant and the first write to it slow. It also explains mmap, copy-on-write after fork, and why RSS is smaller than virtual size.",
            exampleCaption: "The reservation is cheap; the first touch is what costs.",
            exampleCode: """
            // Reserves address space, no frames yet.
            let mut buffer = Vec::with_capacity(1 << 30);
            // Each new page faults in on first write.
            buffer.push(1u8);
            """,
            task: "Explain why a huge allocation can succeed and the first write still stall.",
            success: "You mention pages, faults, and the difference between virtual and resident.",
            rule: "Allocation reserves addresses; the kernel supplies frames on first touch.",
            practiceCode: """
            // Same file, two processes, read-only.
            let map = unsafe { Mmap::map(&file)? };
            """,
            question: "What does mapping it twice cost in physical memory?",
            answers: [
                "Twice the file size, once per mapping",
                "One copy — both mappings share the same page cache frames",
                "Nothing — mapped pages are never resident",
            ],
            correctAnswer: 1,
            feedback: "Read-only file mappings share frames through the page cache."
        ),
        "q-syscalls": RustLessonWriting(
            summary: "A syscall is a controlled trip into the kernel, and it is not free.",
            explanation: "Reading a file, opening a socket, or spawning a thread all cross a privilege boundary that costs far more than a function call. That is why buffered IO exists, why writev beats many writes, and why an event loop with epoll or io_uring outperforms a read per connection. Interviewers ask this to see whether you know where the cost of IO actually is.",
            exampleCaption: "One syscall per line, versus one per buffer.",
            exampleCode: """
            // A write syscall per line.
            for line in lines { file.write_all(line)?; }

            // One syscall per full buffer.
            let mut out = BufWriter::new(file);
            for line in lines { out.write_all(line)?; }
            """,
            task: "Count the syscalls in a hot loop and remove the ones that are avoidable.",
            success: "You can point to the buffering that removed them.",
            rule: "Batch at the boundary: syscalls cost orders of magnitude more than calls.",
            practiceCode: """
            for byte in data {
                socket.write_all(&[byte])?;
            }
            """,
            question: "What is wrong with that loop?",
            answers: [
                "It is not async, so it blocks the task",
                "One syscall per byte, where one per buffer would do",
                "write_all can fail and is never checked",
            ],
            correctAnswer: 1,
            feedback: "The boundary crossing dominates; batch before you optimise anything else."
        ),
        "q-tcp-udp": RustLessonWriting(
            summary: "TCP gives you a reliable ordered stream; UDP gives you datagrams and nothing else.",
            explanation: "TCP costs a handshake, retransmission, and head-of-line blocking in exchange for delivery and order. UDP hands you a message that may vanish, arrive twice, or arrive out of order, and leaves reliability to you — which is exactly why QUIC and real-time media build their own on top of it. The right answer names the trade-off rather than declaring one better.",
            exampleCaption: "One is a stream with no message boundaries; the other is not.",
            exampleCode: """
            // Stream: framing is your problem.
            let mut stream = TcpStream::connect(addr)?;
            stream.write_all(&length.to_be_bytes())?;

            // Datagram: the boundary is the message.
            let socket = UdpSocket::bind("0.0.0.0:0")?;
            socket.send_to(&packet, addr)?;
            """,
            task: "Choose a transport for a chat protocol and for live audio, and say why.",
            success: "Each choice names the guarantee you needed and the one you gave up.",
            rule: "TCP: ordered, reliable, head-of-line blocked. UDP: messages, no promises.",
            practiceCode: """
            // Live voice: late audio is worse than none.
            let transport = ???;
            """,
            question: "Which fits?",
            answers: ["TCP", "UDP", "Either, it makes no difference"],
            correctAnswer: 1,
            feedback: "Retransmitting audio that is already too late only adds delay."
        ),
        "q-http-versions": RustLessonWriting(
            summary: "Each HTTP version fixed the blocking problem one layer lower.",
            explanation: "HTTP/1.1 sends one request at a time per connection, so browsers opened six. HTTP/2 multiplexes streams over one TCP connection, which removes application-level blocking but not TCP's — one lost packet still stalls every stream. HTTP/3 moves onto QUIC over UDP, so a lost packet stalls only its own stream, and the handshake folds into TLS.",
            exampleCaption: "Same request, three different blocking stories underneath.",
            exampleCode: """
            // h1: one in flight per connection
            // h2: many streams, one TCP connection
            // h3: many streams, QUIC over UDP
            let response = client.get(url).send().await?;
            """,
            task: "Explain what head-of-line blocking means at each layer.",
            success: "You can say which version fixes which layer, and which one it does not.",
            rule: "HTTP/2 removes application blocking; only HTTP/3 removes transport blocking.",
            practiceCode: """
            // One dropped packet, HTTP/2, ten active streams.
            """,
            question: "How many streams stall?",
            answers: [
                "One — only the stream that lost the packet",
                "All ten, because they share one TCP connection",
                "None — HTTP/2 streams are independent",
            ],
            correctAnswer: 1,
            feedback: "TCP must deliver in order, so the whole connection waits."
        ),
        "q-tls": RustLessonWriting(
            summary: "TLS gives confidentiality, integrity, and identity — in that order of confusion.",
            explanation: "The handshake authenticates the server through a certificate chain, agrees on keys with an ephemeral exchange, and switches to symmetric encryption because it is far faster. Skip the certificate check and a machine in the middle (MITM) can answer in the server's place, decrypt everything, and forward it on. Forward secrecy means recording traffic today and stealing the key tomorrow reveals nothing. Certificate pinning, mTLS, and SNI are the follow-up questions.",
            exampleCaption: "Verification is the part people disable and regret.",
            exampleCode: """
            let config = ClientConfig::builder()
                .with_root_certificates(roots)
                .with_no_client_auth();
            """,
            task: "Say what a certificate proves, and what it does not.",
            success: "You separate identity from encryption rather than treating them as one thing.",
            rule: "Encryption without verified identity protects you from nobody in particular.",
            practiceCode: """
            danger_accept_invalid_certs(true)
            """,
            question: "What does that leave you with?",
            answers: [
                "Nothing changes, it is only a warning",
                "Encryption to whoever answered — a MITM is now undetectable",
                "Slower connections",
            ],
            correctAnswer: 1,
            feedback: "Without verification the tunnel may simply terminate at the attacker."
        ),
        "q-backpressure": RustLessonWriting(
            summary: "A queue with no limit is a crash with a delay.",
            explanation: "When a producer is faster than a consumer, an unbounded channel converts a throughput problem into a memory problem and then an OOM. Backpressure means the queue has a bound and the producer waits, sheds load, or fails fast when it is full. Rust makes this explicit: a bounded sender's send is an await, which is the signal you asked for.",
            exampleCaption: "The bound is the backpressure; awaiting send is the signal.",
            exampleCode: """
            let (tx, rx) = tokio::sync::mpsc::channel(256);
            // Waits once 256 are queued, instead of
            // growing until the process dies.
            tx.send(job).await?;
            """,
            task: "Replace an unbounded queue with a bounded one and decide what happens when full.",
            success: "The system slows down under load instead of running out of memory.",
            rule: "Every queue needs a bound and a policy for what happens at that bound.",
            practiceCode: """
            let (tx, rx) = mpsc::unbounded_channel();
            """,
            question: "What does that do under sustained overload?",
            answers: [
                "Drops the oldest items to make room",
                "Grows until the process is killed for using too much memory",
                "Blocks the producer until a slot frees",
            ],
            correctAnswer: 1,
            feedback: "Unbounded means the only limit is RAM, and it fails all at once."
        ),
        "q-acid": RustLessonWriting(
            summary: "Isolation is the letter in ACID people actually get wrong.",
            explanation: "Atomicity, consistency, and durability are easy to state. Isolation is a dial: read committed still allows non-repeatable reads, repeatable read still allows phantoms in some engines, and serializable costs the most because it must behave as if transactions ran one at a time. Naming your database default is what separates a real answer from a memorised one.",
            exampleCaption: "The anomaly this allows depends entirely on the level.",
            exampleCode: """
            BEGIN;
            SELECT balance FROM account WHERE id = 1;
            -- another transaction commits here
            UPDATE account SET balance = balance - 10;
            COMMIT;
            """,
            task: "Name the anomaly each isolation level still permits.",
            success: "You can state your database default and one anomaly it allows.",
            rule: "Isolation is a spectrum; only serializable removes every anomaly.",
            practiceCode: """
            -- Read committed. Same row, read twice,
            -- one transaction.
            """,
            question: "Can the second read return a different value?",
            answers: [
                "No, a transaction sees one snapshot",
                "Yes — read committed permits non-repeatable reads",
                "Only when an explicit lock is taken",
            ],
            correctAnswer: 1,
            feedback: "Each statement sees the latest commit, so the value can move."
        ),
        "q-indexes": RustLessonWriting(
            summary: "An index is a sorted structure that trades write cost for read speed.",
            explanation: "A B-tree index turns a full scan into a logarithmic descent, which is why the leftmost-prefix rule matters: an index on (a, b) helps a query filtering on a, and on a and b, but not one filtering only on b. Every index also has to be maintained on write, so a table with ten indexes is a slow table to insert into.",
            exampleCaption: "The column order in the index decides which queries it serves.",
            exampleCode: """
            CREATE INDEX ON orders (customer_id, created_at);

            -- uses it
            WHERE customer_id = 7
            -- does not
            WHERE created_at > now() - interval '1 day'
            """,
            task: "Explain why a composite index helps one query and not another.",
            success: "You can state the leftmost-prefix rule and the write-side cost.",
            rule: "A composite index serves the leftmost prefix of its columns, nothing else.",
            practiceCode: """
            CREATE INDEX ON events (tenant_id, kind, at);
            WHERE kind = 'click' AND at > $1
            """,
            question: "Does that query use the index?",
            answers: [
                "Yes — both columns appear in the index",
                "No — tenant_id is the leftmost column and is not filtered",
                "Only if created_at is indexed on its own",
            ],
            correctAnswer: 1,
            feedback: "Skipping the leading column means the sorted order no longer helps."
        ),
        "q-cap": RustLessonWriting(
            summary: "CAP is about what happens during a partition, not a menu of three.",
            explanation: "When the network splits you either refuse writes to stay consistent, or accept them and diverge. Everything else — quorums, leader election, eventual consistency, CRDTs — is a way of choosing where on that line to sit. Saying pick two is the answer that gets followed up; saying what your system does during a partition is the one that lands.",
            exampleCaption: "The quorum is where the choice is actually made.",
            exampleCode: """
            // 5 replicas, write quorum 3, read quorum 3.
            // 3 + 3 > 5, so a read sees the last write
            // and a minority partition cannot accept
            // writes at all.
            """,
            task: "Describe what your service should do to writes during a partition.",
            success: "You give one concrete behaviour rather than restating the theorem.",
            rule: "Partitions are not optional; C versus A is what you choose when one happens.",
            practiceCode: """
            // Shopping cart, network split, user adds an item.
            """,
            question: "Which behaviour usually fits a cart?",
            answers: [
                "Reject the write to stay strongly consistent",
                "Accept it and merge the divergent carts later",
                "Fail the whole session",
            ],
            correctAnswer: 1,
            feedback: "Carts are merge-friendly, so availability is worth more than strictness."
        ),
        "q-idempotency": RustLessonWriting(
            summary: "A retry is only safe if the operation is idempotent.",
            explanation: "Networks make at-least-once the default, so the same request will arrive twice. Reads and overwrites are naturally idempotent; increments, appends, and charges are not. The fix is an idempotency key the server records with the result, so a repeat returns the first outcome instead of doing the work again. Retries also need jitter, or they synchronise into a thundering herd.",
            exampleCaption: "The key is what makes the second attempt safe.",
            exampleCode: """
            let response = client
                .post(url)
                .header("Idempotency-Key", request_id)
                .json(&payment)
                .send()
                .await?;
            """,
            task: "Make a non-idempotent endpoint safe to retry.",
            success: "A duplicate request returns the original result and charges once.",
            rule: "At-least-once delivery plus an idempotency key gives effectively-once behaviour.",
            practiceCode: """
            POST /accounts/7/balance  {"add": 10}
            """,
            question: "What goes wrong when the client retries a timeout?",
            answers: [
                "Nothing, the server deduplicates",
                "The balance is increased twice",
                "The request is rejected",
            ],
            correctAnswer: 1,
            feedback: "A relative update is not idempotent without a key to recognise it by."
        ),
        "q-caching": RustLessonWriting(
            summary: "Caching is easy; deciding when the cache is wrong is not.",
            explanation: "A TTL trades staleness for simplicity, explicit invalidation trades simplicity for correctness, and write-through trades write latency for both. The failure modes are the interesting part: a stampede when a hot key expires, and unbounded growth without an eviction policy. Naming which staleness your product can tolerate is the real answer.",
            exampleCaption: "Bounded, with a policy for what leaves and when.",
            exampleCode: """
            let cache = LruCache::new(10_000);
            if let Some(hit) = cache.get(&key) {
                return Ok(hit.clone());
            }
            let value = load(&key).await?;
            cache.put(key, value.clone());
            """,
            task: "Choose an invalidation strategy for two different kinds of data.",
            success: "Each choice names the staleness it accepts and the eviction policy.",
            rule: "Every cache needs a bound, an eviction policy, and a stated staleness budget.",
            practiceCode: """
            // One very hot key, TTL expires, 5k requests
            // per second.
            """,
            question: "What happens at the moment it expires?",
            answers: [
                "The cache refills quietly on the next read",
                "Every request misses at once and stampedes the origin",
                "Requests queue automatically behind one refill",
            ],
            correctAnswer: 1,
            feedback: "A single flight lock or early refresh is what stops the herd."
        ),
        "q-complexity": RustLessonWriting(
            summary: "Big-O tells you how something scales, not how fast it is.",
            explanation: "A linear scan of a contiguous Vec often beats a logarithmic tree for small inputs because the constant factor is cache locality. The useful answer names the input size where the asymptotic term takes over, and mentions amortised cost: push on a Vec is O(1) amortised, but the reallocation that makes it so is O(n) and happens at the worst moment.",
            exampleCaption: "Same complexity class, very different constants.",
            exampleCode: """
            // O(n), one cache line at a time
            items.iter().find(|item| item.id == id)

            // O(log n), a pointer chase per level
            tree.get(&id)
            """,
            task: "Estimate the input size at which a HashMap beats a linear scan here.",
            success: "Your answer mentions constants and cache behaviour, not only the exponent.",
            rule: "Complexity predicts growth; constants decide which one is faster today.",
            practiceCode: """
            let mut v = Vec::new();
            for item in stream { v.push(item); }
            """,
            question: "What is the cost of one push?",
            answers: [
                "Always O(1), the buffer never moves",
                "O(1) amortised, with an O(n) copy when it reallocates",
                "O(log n), like a balanced tree insert",
            ],
            correctAnswer: 1,
            feedback: "with_capacity removes the reallocation when the size is known."
        ),
        "q-hashmap": RustLessonWriting(
            summary: "A hash map is O(1) until an adversary picks your keys.",
            explanation: "Lookup cost depends on collisions, and collisions depend on the hash function. Rust's default is SipHash with a per-process random seed precisely so untrusted keys cannot be chosen to collide — the denial-of-service that plagued other languages. Swapping in a faster non-cryptographic hasher is correct for internal keys and dangerous for user input.",
            exampleCaption: "A faster hasher is a decision about trust, not only speed.",
            exampleCode: """
            use std::collections::HashMap;

            // Default: SipHash, randomly seeded.
            let mut trusted: HashMap<u32, u32> =
                HashMap::default();
            """,
            task: "Decide whether a faster hasher is safe for two different key sources.",
            success: "The choice is justified by where the keys come from.",
            rule: "Hash choice is a security decision whenever the keys are attacker-controlled.",
            practiceCode: """
            // Keys are HTTP header names from the client.
            let map: HashMap<String, String, FxBuildHasher>
            """,
            question: "What is the risk?",
            answers: [
                "None — a faster hash is strictly better",
                "Chosen keys can be made to collide, turning lookups linear",
                "It can no longer store String keys",
            ],
            correctAnswer: 1,
            feedback: "That is the classic hash-flooding denial of service."
        ),
        "q-testing-strategy": RustLessonWriting(
            summary: "Different bugs need different tests, and naming them is the answer.",
            explanation: "Unit tests pin down behaviour you already thought of. Property tests generate inputs and check an invariant, which finds the cases you did not. Fuzzing pushes malformed input at a parser until it panics. Integration tests check the seams. A candidate who reaches for all four in the right places is saying something a coverage number cannot.",
            exampleCaption: "The property holds for every input, not for three of them.",
            exampleCode: """
            #[test]
            fn roundtrip() {
                proptest!(|(value: Vec<u8>)| {
                    let encoded = encode(&value);
                    prop_assert_eq!(decode(&encoded)?, value);
                });
            }
            """,
            task: "Choose the right kind of test for a parser, a cache, and an HTTP route.",
            success: "Each choice names the class of bug it is meant to catch.",
            rule: "Examples check what you thought of; properties check what you did not.",
            practiceCode: """
            // A parser for untrusted binary input.
            """,
            question: "Which finds the crash first?",
            answers: [
                "More unit tests around the parser",
                "A fuzzer driving malformed input at it",
                "An integration test over the whole flow",
            ],
            correctAnswer: 1,
            feedback: "Fuzzing explores the malformed space no one thinks to write down."
        ),
        "q-api-design": RustLessonWriting(
            summary: "A good API makes the wrong call impossible, not merely documented.",
            explanation: "Newtypes stop two u64s being swapped, typestate stops a request being sent twice, and returning Result instead of panicking hands the decision to the caller. Semver then constrains what you may change: adding a public enum variant or a trait method is a breaking change, which is why non_exhaustive and sealed traits exist.",
            exampleCaption: "The compiler now rejects the argument order mistake.",
            exampleCode: """
            struct AccountId(u64);
            struct Amount(u64);

            fn transfer(
                from: AccountId,
                to: AccountId,
                amount: Amount,
            ) {}
            """,
            task: "Make one plausible misuse of an API impossible to express.",
            success: "The mistake becomes a compile error rather than a comment.",
            rule: "Encode the invariant in the type; documentation is not enforcement.",
            practiceCode: """
            pub enum Status { Ok, Failed }
            """,
            question: "Why can adding a variant break callers?",
            answers: [
                "It cannot — adding a variant is always safe",
                "Their exhaustive matches stop compiling — mark it non_exhaustive",
                "An enum cannot be extended after release",
            ],
            correctAnswer: 1,
            feedback: "non_exhaustive forces a wildcard, which keeps additions non-breaking."
        ),
        "q-perf-profiling": RustLessonWriting(
            summary: "Measure first: the bottleneck is almost never where it feels like it is.",
            explanation: "A profiler shows where time actually goes, and the usual answers are allocation, copying, and syscalls rather than arithmetic. In Rust specifically: check you built with --release, look for clones in a hot loop, prefer with_capacity over repeated growth, and confirm bounds checks are the problem before reaching for unsafe. A benchmark that is not statistically stable is not a benchmark.",
            exampleCaption: "The allocation per iteration is usually the whole finding.",
            exampleCode: """
            // Allocates a String on every iteration.
            for row in rows {
                out.push(format!("{}-{}", row.a, row.b));
            }
            """,
            task: "Profile a slow function and name the top cost before changing anything.",
            success: "The change you make is the one the profile pointed at.",
            rule: "Profile, change one thing, measure again. Guessing is not optimising.",
            practiceCode: """
            cargo build   # then benchmark
            """,
            question: "What is wrong before the numbers even arrive?",
            answers: [
                    "Nothing — a debug build measures the same code",
                "It is a debug build — release is often an order of magnitude apart",
                "cargo bench is required for any timing",
            ],
            correctAnswer: 1,
            feedback: "Debug disables optimisation and keeps every check; the numbers mean nothing."
        ),
        "q-ffi-abi": RustLessonWriting(
            summary: "Crossing into C means giving up every guarantee at the boundary.",
            explanation: "extern \"C\" fixes the calling convention, repr(C) fixes the layout, and everything about ownership becomes a convention you have to document. Who frees this pointer, may it be null, how long is it valid, and is it aliased are the four questions each call has to answer — and the safe wrapper you write around it is where those answers are enforced.",
            exampleCaption: "The unsafe block is small; the wrapper is where the rules live.",
            exampleCode: """
            #[repr(C)]
            pub struct Point { x: f64, y: f64 }

            extern "C" {
                fn c_len(ptr: *const u8, len: usize)
                    -> usize;
            }
            """,
            task: "Wrap one C function so no safe caller can misuse it.",
            success: "Null, lifetime, and ownership are all handled inside the wrapper.",
            rule: "repr(C) fixes layout; ownership across the boundary is documentation you enforce.",
            practiceCode: """
            let name = CString::new(input)?;
            let ptr = name.as_ptr();
            drop(name);
            c_use(ptr);
            """,
            question: "What is wrong there?",
            answers: [
                "CString cannot hold input of that length",
                "The buffer is freed before use, so ptr dangles",
                "as_ptr has to be called inside unsafe",
            ],
            correctAnswer: 1,
            feedback: "The CString must outlive every use of the pointer it lends out."
        ),
        "q-ownership": RustLessonWriting(
            summary: "Explaining ownership well means naming the guarantee, not the syntax.",
            explanation: "A strong answer says: each value has one owner, ownership moves on assignment or when passed by value, Copy types duplicate instead, and Drop runs deterministically at end of scope. That combination is what removes both double frees and the need for a garbage collector.",
            exampleCaption: "Three behaviours an interviewer is listening for.",
            exampleCode: """
            let a = String::from("x");
            let b = a;        // move: a is unusable
            let n = 5;
            let m = n;        // copy: n still usable
            {
                let _t = String::from("t");
            }                 // dropped here, deterministically
            """,
            task: "Explain ownership in under a minute, out loud.",
            success: "You name moves, Copy, and Drop without mentioning syntax first.",
            rule: "Ownership is a guarantee about cleanup, not a rule about symbols.",
            practiceCode: """
            fn take(value: String) {}
            let s = String::from("x");
            take(s);
            println!("{s}");
            """,
            question: "Why does the println fail?",
            answers: [
                "take only borrowed s, so it stays usable",
                "Passing by value moved s into the function",
                "A String cannot be printed more than once",
            ],
            correctAnswer: 1,
            feedback: "A by-value parameter takes ownership; the caller's binding is done."
        ),
        "q-borrowing": RustLessonWriting(
            summary: "The borrowing answer is about aliasing versus mutation.",
            explanation: "Say it as a rule about coexistence: you may have many readers or one writer, never both, and the compiler tracks the region where each borrow is live. That single constraint is what makes data races impossible for safe code without any runtime cost.",
            exampleCaption: "Many readers, or one writer — never at the same time.",
            exampleCode: """
            let mut v = vec![1, 2];
            let a = &v[0];
            let b = &v[1];   // two readers: fine
            println!("{a} {b}");
            v.push(3);       // writer, after the readers end
            """,
            task: "State the borrowing rule and why it prevents data races.",
            success: "You mention aliasing, mutation, and where each borrow ends.",
            rule: "Aliasing XOR mutation, checked over the region a borrow is used.",
            practiceCode: """
            let mut v = vec![1];
            let r = &mut v;
            let s = &v;
            """,
            question: "Why is that rejected?",
            answers: [
                "The vector has to be declared immutable",
                "A mutable borrow cannot coexist with a shared one",
                "A Vec cannot be borrowed twice in one scope",
            ],
            correctAnswer: 1,
            feedback: "One writer excludes all readers for as long as it is live."
        ),
        "q-lifetimes": RustLessonWriting(
            summary: "Lifetimes are about relationships, and saying so is the answer.",
            explanation: "The common misconception is that a lifetime controls how long a value lives. It does not: it is a compile-time claim about which borrows outlive which. Annotations appear only where inference cannot decide, which is why most code has none.",
            exampleCaption: "The annotation relates the inputs to the output.",
            exampleCode: """
            fn pick<'a>(
                a: &'a str,
                b: &'a str,
            ) -> &'a str {
                if a.len() > b.len() { a } else { b }
            }
            """,
            task: "Correct the claim that a lifetime extends how long data lives.",
            success: "You describe a constraint the compiler checks, not runtime behaviour.",
            rule: "A lifetime constrains borrows; it never keeps anything alive.",
            practiceCode: """
            fn dangle() -> &String {
                let s = String::from("x");
                &s
            }
            """,
            question: "Why can no annotation fix that?",
            answers: [
                "The lifetime is simply too short to name here",
                "s is dropped at the end of the function, so no borrow can be valid",
                "A String can never be returned from a function",
            ],
            correctAnswer: 1,
            feedback: "Return the String itself; a borrow of a dead local can never be sound."
        ),
        "q-option-result": RustLessonWriting(
            summary: "Pick the type that matches what the caller must decide.",
            explanation: "Option says a value may be absent and that is unremarkable. Result says an operation failed and carries why. Converting between them is routine — ok_or turns absence into an error when the caller does need a reason.",
            exampleCaption: "ok_or promotes an absence into a reported failure.",
            exampleCode: """
            fn port(map: &Config) -> Result<u16, String> {
                map.get("port")
                    .ok_or("port is missing".to_string())?
                    .parse()
                    .map_err(|_| "not a number".into())
            }
            """,
            task: "Choose between Option and Result for two APIs and justify each.",
            success: "Each choice is explained by what the caller needs to know.",
            rule: "Option: absence is normal. Result: the caller needs the reason.",
            practiceCode: """
            let value: Option<u32> = map.get("k");
            let checked: Result<u32, String> = value.???;
            """,
            question: "Which converts Option into Result?",
            answers: ["unwrap_or", "ok_or", "and_then"],
            correctAnswer: 1,
            feedback: "ok_or supplies the error value that absence alone did not carry."
        ),
        "q-send-sync": RustLessonWriting(
            summary: "Two marker traits decide what may cross a thread boundary.",
            explanation: "Send means a value may be moved to another thread; Sync means &T may be shared with one. They are inferred from a type's fields, which is why Rc is rejected at compile time while Arc is accepted — the difference is an atomic count, and the type system knows it.",
            exampleCaption: "The bound is exactly what thread::spawn asks for.",
            exampleCode: """
            fn run<F>(job: F)
            where
                F: FnOnce() + Send + 'static,
            {
                std::thread::spawn(job);
            }
            """,
            task: "Explain why Rc cannot cross threads and Arc can.",
            success: "You name the atomic reference count as the deciding detail.",
            rule: "T is Sync exactly when &T is Send.",
            practiceCode: """
            let shared = std::rc::Rc::new(1);
            std::thread::spawn(move || println!("{shared}"));
            """,
            question: "What does the compiler object to?",
            answers: [
                "Rc is not Send, because its count is not atomic",
                "The closure is missing an explicit return type",
                "An Rc value cannot be printed from a thread",
            ],
            correctAnswer: 0,
            feedback: "Arc pays for an atomic count and is therefore Send and Sync."
        ),
        "q-box-rc-arc": RustLessonWriting(
            summary: "Three pointers, three different ownership questions.",
            explanation: "Box has exactly one owner and puts the value on the heap. Rc shares ownership on a single thread with a plain count. Arc does the same across threads with an atomic count, which costs more. Choosing the narrowest one that fits is the whole answer.",
            exampleCaption: "Narrowest type that satisfies the requirement wins.",
            exampleCode: """
            // one owner, on the heap
            let boxed: Box<u32> = Box::new(1);

            // shared, single thread
            let shared = std::rc::Rc::new(1);

            // shared, across threads
            let threaded = std::sync::Arc::new(1);
            """,
            task: "Match three scenarios to the narrowest pointer that satisfies them.",
            success: "Every choice names an ownership count and a thread boundary.",
            rule: "Pick by ownership count first, then by thread boundary.",
            practiceCode: """
            // Shared by several parents, one thread only.
            type Node = ???;
            """,
            question: "Which fits?",
            answers: ["Box<Node>", "Rc<Node>", "Arc<Node>"],
            correctAnswer: 1,
            feedback: "Shared on one thread: Rc. Arc would pay for atomics you do not need."
        ),
        "q-dyn-generics": RustLessonWriting(
            summary: "Static dispatch trades code size for speed; dynamic trades the reverse.",
            explanation: "A generic bound is monomorphised: one specialised copy per concrete type, direct calls, inlinable, larger binary. dyn Trait keeps one copy and dispatches through a vtable, which is smaller and lets heterogeneous types share a collection at the cost of an indirection.",
            exampleCaption: "One is chosen while compiling, the other while running.",
            exampleCode: """
            fn draw_static<S: Shape>(s: &S) { s.draw(); }
            fn draw_dynamic(s: &dyn Shape) { s.draw(); }

            let mixed: Vec<Box<dyn Shape>> =
                vec![Box::new(circle), Box::new(square)];
            """,
            task: "Compare a generic call with a trait object and name the trade-off.",
            success: "You mention monomorphisation, binary size, and the vtable.",
            rule: "Heterogeneous collections need dyn; hot paths usually want generics.",
            practiceCode: """
            fn handle(items: &[???]) { }
            """,
            question: "Which is required for a slice of different concrete types?",
            answers: ["impl Trait", "Box<dyn Trait>", "A generic parameter"],
            correctAnswer: 1,
            feedback: "Slice elements share one size, so the concrete type must be erased."
        ),
        "q-unsafe": RustLessonWriting(
            summary: "unsafe is a claim about an invariant, not a disabled checker.",
            explanation: "It permits exactly five operations and leaves the borrow checker fully in force. A sound abstraction documents the invariant its unsafe block relies on and enforces it in the safe API, so no safe caller can ever trigger undefined behaviour.",
            exampleCaption: "The invariant is checked, then written down beside the block.",
            exampleCode: """
            pub fn first(v: &[u32]) -> Option<u32> {
                if v.is_empty() { return None; }
                // SAFETY: the check above proves index 0
                // exists for this slice.
                Some(unsafe { *v.get_unchecked(0) })
            }
            """,
            task: "Review a small unsafe wrapper and list every invariant its safe API protects.",
            success: "Safe callers cannot reach undefined behaviour by any input.",
            rule: "unsafe moves the obligation to you; it never removes it.",
            practiceCode: """
            pub fn get(v: &[u32], i: usize) -> u32 {
                unsafe { *v.get_unchecked(i) }
            }
            """,
            question: "Why is that function unsound?",
            answers: [
                "It should return an Option instead of a value",
                "A safe caller can pass any index, so the invariant is unchecked",
                "get_unchecked has been deprecated for slices",
            ],
            correctAnswer: 1,
            feedback: "A safe signature must make the invariant impossible to break."
        ),
        "operators": RustLessonWriting(
            summary: "Arithmetic in Rust is checked, and conversions are always written down.",
            explanation: "There is no implicit numeric promotion: adding a u8 to a u32 is a compile error until you convert. In a debug build an overflowing add panics rather than silently wrapping, and in release it wraps — which is why the standard library gives you checked_, wrapping_, and saturating_ variants to say which one you meant.",
            exampleCaption: "Say what should happen at the boundary instead of hoping.",
            exampleCode: """
            let a: u8 = 250;
            println!("{:?}", a.checked_add(10)); // None
            println!("{}", a.wrapping_add(10));  // 4
            println!("{}", a.saturating_add(10));// 255

            let big = 300_i32;
            let narrowed = big as u8; // truncates on purpose
            println!("{narrowed}");
            """,
            task: "Pick the right overflow strategy for a counter that must never wrap.",
            success: "The program compiles and the boundary case is handled explicitly.",
            rule: "Rust never converts numeric types for you, and overflow is a decision you make by name.",
            practiceCode: """
            let total: u8 = 200;
            let bonus: u8 = 100;
            let result = total.???_add(bonus);
            """,
            question: "Which call returns None instead of panicking or wrapping?",
            answers: ["wrapping_add", "checked_add", "saturating_add"],
            correctAnswer: 1,
            feedback: "checked_* returns Option, so the caller decides what an overflow means."
        ),
        "functions": RustLessonWriting(
            summary: "A function signature is a contract the compiler enforces at every call site.",
            explanation: "Parameter types and the return type are always written out, never inferred across a function boundary. The last expression is the return value when you leave the semicolon off, which is why an accidental semicolon turns a function into one that returns the unit type and produces a type error.",
            exampleCaption: "The final expression is the result — no `return` keyword needed.",
            exampleCode: """
            fn area(width: u32, height: u32) -> u32 {
                width * height // no semicolon: the result
            }

            fn shout(text: &str) -> String {
                let mut out = text.to_uppercase();
                out.push('!');
                out
            }
            """,
            task: "Write a function that takes two values and returns a computed one.",
            success: "It compiles with no `return` keyword and the type matches the signature.",
            rule: "The last expression without a semicolon is the return value.",
            practiceCode: """
            fn double(value: i32) -> i32 {
                value * 2;
            }
            """,
            question: "Why does that function fail to compile?",
            answers: [
                "Multiplication needs both operands to be the same width",
                "The semicolon discards the value, so it returns ()",
                "The parameters must be declared mut to be read twice",
            ],
            correctAnswer: 1,
            feedback: "A trailing semicolon turns an expression into a statement, and the function then returns ()."
        ),
        "comments-docs": RustLessonWriting(
            summary: "Doc comments are compiled, and their examples are run as tests.",
            explanation: "/// documents the item that follows and //! documents the enclosing module or crate. Code blocks inside doc comments are compiled and executed by `cargo test`, so an example that drifts out of date fails the build instead of quietly misleading the next reader.",
            exampleCaption: "This example is real: `cargo test` compiles and runs it.",
            exampleCode: """
            /// Returns the larger of two values.
            ///
            /// # Examples
            ///
            /// ```
            /// assert_eq!(larger(2, 7), 7);
            /// ```
            pub fn larger(a: i32, b: i32) -> i32 {
                if a > b { a } else { b }
            }
            """,
            task: "Document a public function and include one example.",
            success: "The example states the behaviour and would fail if the code changed.",
            rule: "A doc example is a test, so documentation cannot silently rot.",
            practiceCode: """
            /// Adds two numbers.
            ///
            /// ```
            /// assert_eq!(add(2, 2), 5);
            /// ```
            pub fn add(a: i32, b: i32) -> i32 { a + b }
            """,
            question: "What happens when you run cargo test on that?",
            answers: [
                "Nothing runs; doc comments are stripped before tests",
                "The doc test fails because 2 + 2 is not 5",
                "It prints a warning but the test suite still passes",
            ],
            correctAnswer: 1,
            feedback: "Doc examples are compiled and asserted, so a wrong example is a failing test."
        ),
        "copy-clone": RustLessonWriting(
            summary: "Copy duplicates implicitly; Clone duplicates only when you ask.",
            explanation: "Types that are cheap and have no destructor can be Copy, so assigning them leaves the original usable. Everything that owns a heap allocation is not Copy, and duplicating it means calling .clone() explicitly — the cost is visible in the source rather than hidden in an assignment.",
            exampleCaption: "The integer copies; the String would have moved without .clone().",
            exampleCode: """
            let a = 5;          // i32 is Copy
            let b = a;
            println!("{a} {b}"); // both still usable

            let s = String::from("crab");
            let t = s.clone();  // explicit deep copy
            println!("{s} {t}");
            """,
            task: "Predict which bindings stay usable after an assignment.",
            success: "You can name why one type copies and the other does not.",
            rule: "If a type owns a heap allocation it is not Copy, and duplication must be written down.",
            practiceCode: """
            let name = String::from("ada");
            let alias = name;
            println!("{name}");
            """,
            question: "How do you make that compile without changing the println?",
            answers: ["Add mut to name", "Use name.clone() for alias", "Wrap it in a Box"],
            correctAnswer: 1,
            feedback: "Cloning creates a second owned String, so the original binding stays valid."
        ),
        "drop-order": RustLessonWriting(
            summary: "Cleanup runs at a place you can point to in the source.",
            explanation: "When a value goes out of scope its Drop implementation runs, and values in a scope drop in reverse declaration order. This is deterministic — no collector decides later — which is what lets Rust manage files, locks, and sockets with the same mechanism it uses for memory.",
            exampleCaption: "Reverse order: the last thing created is the first thing dropped.",
            exampleCode: """
            struct Noisy(&'static str);

            impl Drop for Noisy {
                fn drop(&mut self) {
                    println!("dropping {}", self.0);
                }
            }

            fn main() {
                let _first = Noisy("first");
                let _second = Noisy("second");
                println!("end of scope");
            }
            """,
            task: "Predict the printed order before running it.",
            success: "You can explain why `second` is released before `first`.",
            rule: "Values drop in reverse declaration order when their scope ends.",
            practiceCode: """
            let a = Noisy("a");
            let b = Noisy("b");
            drop(a);
            println!("after explicit drop");
            """,
            question: "Which line prints last?",
            answers: ["dropping a", "after explicit drop", "dropping b"],
            correctAnswer: 2,
            feedback: "`a` is dropped early by hand; `b` still drops at the end of the scope."
        ),
        "strings": RustLessonWriting(
            summary: "Rust strings are UTF-8, so there is no cheap index by character.",
            explanation: "String owns a growable UTF-8 buffer and &str borrows one. Because a character can be several bytes, s[0] is not allowed at all: you choose .bytes(), .chars(), or a byte range you know lands on a boundary. That refusal is the point — it makes an entire class of encoding bug impossible.",
            exampleCaption: "Bytes and characters are different counts, and Rust makes you pick.",
            exampleCode: """
            let text = String::from("café");
            println!("bytes {}", text.len());          // 5
            println!("chars {}", text.chars().count()); // 4

            for (index, ch) in text.char_indices() {
                println!("{index} {ch}");
            }
            """,
            task: "Count characters rather than bytes in a string with an accent.",
            success: "The count matches what a reader would say out loud.",
            rule: "len() is bytes; use .chars() when you mean characters.",
            practiceCode: """
            let word = "naïve";
            let length = word.???;
            """,
            question: "Which gives the number of characters?",
            answers: ["word.len()", "word.chars().count()", "word.bytes().len()"],
            correctAnswer: 1,
            feedback: "len() reports UTF-8 bytes, which is larger than the character count here."
        ),
        "pattern-matching": RustLessonWriting(
            summary: "Patterns destructure data and bind its parts in one step.",
            explanation: "Patterns work in match, if let, while let, function parameters, and plain let. Guards add a condition, @ binds a value while testing it, and | matches several shapes at once. The compiler checks exhaustiveness, so a pattern set that misses a case is an error rather than a surprise at runtime.",
            exampleCaption: "One arm can test, bind, and destructure at the same time.",
            exampleCode: """
            let point = (3, -7);

            match point {
                (0, 0) => println!("origin"),
                (x, 0) | (0, x) => println!("axis at {x}"),
                (x, y) if y < 0 => println!("below: {x},{y}"),
                (x, y) => println!("somewhere: {x},{y}"),
            }
            """,
            task: "Match a tuple with a guard and a multi-pattern arm.",
            success: "Every input is covered without a catch-all hiding a real case.",
            rule: "A guard narrows an arm; the compiler still demands the set be exhaustive.",
            practiceCode: """
            let value = Some(4);
            match value {
                Some(n) if n % 2 == 0 => println!("even {n}"),
                Some(n) => println!("odd {n}"),
                None => println!("none"),
            }
            """,
            question: "What does the `if n % 2 == 0` part do?",
            answers: [
                "It replaces the pattern that precedes it",
                "Adds a condition the arm must also satisfy",
                "It makes the match non-exhaustive on its own",
            ],
            correctAnswer: 1,
            feedback: "A guard is an extra condition; exhaustiveness is still checked across the arms."
        ),
        "derive": RustLessonWriting(
            summary: "derive writes the obvious implementation so you do not have to.",
            explanation: "#[derive(Debug, Clone, PartialEq)] generates the mechanical implementation for each field. It only works when every field also implements the trait, which turns a missing capability deep in a struct into a clear compile error naming the field.",
            exampleCaption: "Four traits, no hand-written code, all checked by the compiler.",
            exampleCode: """
            #[derive(Debug, Clone, PartialEq, Default)]
            struct Config {
                host: String,
                port: u16,
            }

            let a = Config::default();
            let b = a.clone();
            println!("{a:?} equal={}", a == b);
            """,
            task: "Derive the traits a small struct needs to be printed and compared.",
            success: "The struct prints with {:?} and compares with == without manual code.",
            rule: "derive only compiles when every field also implements the trait.",
            practiceCode: """
            #[derive(Debug)]
            struct Wrapper {
                inner: NoDebug,
            }
            """,
            question: "Why does that fail?",
            answers: [
                "A struct cannot derive Debug when it has fields",
                "NoDebug does not implement Debug, so the field cannot be printed",
                "Debug always has to be written by hand for structs",
            ],
            correctAnswer: 1,
            feedback: "A derived impl is only as available as the traits of its fields."
        ),
        "closures": RustLessonWriting(
            summary: "A closure is a function that also carries the environment it captured.",
            explanation: "Rust infers whether a closure needs a shared borrow (Fn), a mutable borrow (FnMut), or ownership (FnOnce) from what the body does. `move` forces capture by value, which is what makes a closure safe to send to another thread — the ownership question is answered at compile time rather than by a convention.",
            exampleCaption: "Three closures, three different relationships with `total`.",
            exampleCode: """
            let total = 10;
            let read = || println!("total {total}"); // Fn
            read();

            let mut count = 0;
            let mut bump = || count += 1;            // FnMut
            bump();
            bump();
            println!("count {count}");
            """,
            task: "Write a closure that mutates a captured counter.",
            success: "The closure is declared mut and the counter is readable afterwards.",
            rule: "The body decides the trait: read is Fn, mutate is FnMut, consume is FnOnce.",
            practiceCode: """
            let name = String::from("ada");
            let consume = move || name;
            """,
            question: "Which trait does that closure implement?",
            answers: ["Fn", "FnMut", "FnOnce"],
            correctAnswer: 2,
            feedback: "It gives the String away, so it can only be called once."
        ),
        "iterator-impl": RustLessonWriting(
            summary: "Implementing one method gives you the whole adapter library.",
            explanation: "Iterator requires only next(); everything else — map, filter, take, zip, sum — arrives as default methods. That is why a custom sequence composes with the standard library exactly like a Vec does, without any of it knowing your type exists.",
            exampleCaption: "Only `next` is written; `take` and `sum` come for free.",
            exampleCode: """
            struct Fibonacci { a: u64, b: u64 }

            impl Iterator for Fibonacci {
                type Item = u64;

                fn next(&mut self) -> Option<u64> {
                    let value = self.a;
                    self.a = self.b;
                    self.b = value + self.b;
                    Some(value)
                }
            }

            let fib = Fibonacci { a: 0, b: 1 };
            let total: u64 = fib.take(10).sum();
            println!("{total}");
            """,
            task: "Implement Iterator for a small counter type.",
            success: "It works with at least one adapter you did not write.",
            rule: "Implement next(); the adapters are default methods on the trait.",
            practiceCode: """
            impl Iterator for Countdown {
                type Item = u32;
                fn next(&mut self) -> Option<u32> { ??? }
            }
            """,
            question: "What signals that the sequence has finished?",
            answers: ["Returning Some(0)", "Returning None", "Panicking"],
            correctAnswer: 1,
            feedback: "None ends the iteration, and every adapter respects it."
        ),
        "associated-types": RustLessonWriting(
            summary: "An associated type fixes one output type per implementation.",
            explanation: "A generic parameter lets a type implement a trait many times; an associated type lets it implement it once with a chosen output. Iterator uses Item this way, which is why you write Iterator<Item = u32> rather than passing the element type at every call site.",
            exampleCaption: "One implementation per type, so the output never has to be annotated.",
            exampleCode: """
            trait Container {
                type Item;
                fn get(&self, i: usize) -> Option<&Self::Item>;
            }

            struct Bag { values: Vec<String> }

            impl Container for Bag {
                type Item = String;
                fn get(&self, index: usize) -> Option<&String> {
                    self.values.get(index)
                }
            }
            """,
            task: "Give a trait an associated type and implement it once.",
            success: "Callers use the trait without naming the output type.",
            rule: "Associated type: one impl per type. Generic parameter: many impls per type.",
            practiceCode: """
            trait Parser {
                type Output;
                fn parse(&self, input: &str) -> Self::Output;
            }
            """,
            question: "When should you prefer a generic parameter instead?",
            answers: [
                "Never, associated types are always better",
                "When one type should implement the trait several times",
                "Only for iterators",
            ],
            correctAnswer: 1,
            feedback: "From<T> is generic precisely because a type converts from many others."
        ),
        "operator-traits": RustLessonWriting(
            summary: "Operators and conversions are ordinary traits you can implement.",
            explanation: "a + b calls Add::add, {} calls Display::fmt, and .into() calls Into, which you get for free by implementing From. Because they are normal traits, your own types participate in the same syntax as the built-in ones, and the compiler checks the result type at every use.",
            exampleCaption: "Implement From and Into arrives automatically.",
            exampleCode: """
            use std::fmt;
            use std::ops::Add;

            #[derive(Debug, Clone, Copy)]
            struct Money(i64);

            impl Add for Money {
                type Output = Money;
                fn add(self, other: Money) -> Money {
                    Money(self.0 + other.0)
                }
            }

            impl fmt::Display for Money {
                fn fmt(
                    &self,
                    f: &mut fmt::Formatter<'_>,
                ) -> fmt::Result {
                    write!(f, "{}", self.0 as f64 / 100.0)
                }
            }
            """,
            task: "Give a newtype an Add implementation and a Display implementation.",
            success: "The type adds with + and prints with {} like a built-in.",
            rule: "Implement From, and Into is generated for you — never implement both.",
            practiceCode: """
            impl From<u32> for Money {
                fn from(v: u32) -> Money {
                    Money(i64::from(v))
                }
            }
            let m: Money = 500_u32.into();
            """,
            question: "Why does .into() work without writing an Into impl?",
            answers: [
                "Into is derived alongside From automatically",
                "A blanket impl gives Into to everything that implements From",
                "The compiler special-cases .into() for every type",
            ],
            correctAnswer: 1,
            feedback: "The standard library has impl<T, U: From<T>> Into<U> for T."
        ),
        "dependencies": RustLessonWriting(
            summary: "A dependency is a version requirement, not a fixed version.",
            explanation: "\"1.2\" means any 1.x at or above 1.2, because Cargo follows SemVer: patch and minor releases must stay compatible. The resolver picks the highest match and records the exact choice in Cargo.lock, and features let one crate ship optional pieces you opt into rather than paying for by default.",
            exampleCaption: "A requirement, a feature set, and an opt-out of defaults.",
            exampleCode: """
            [dependencies]
            serde = { version = "1", features = ["derive"] }
            smallvec = "1"
            memchr = { version = "2", default-features = false }
            """,
            task: "Add a dependency with an explicit feature and resolve it.",
            success: "Cargo.lock pins an exact version that satisfies the requirement.",
            rule: "\"1.2\" means >=1.2.0 and <2.0.0; the lockfile records what was actually chosen.",
            practiceCode: """
            [dependencies]
            example = "0.4"
            """,
            question: "Which version can that requirement resolve to?",
            answers: ["0.5.0", "0.4.9", "1.0.0"],
            correctAnswer: 1,
            feedback: "Below 1.0 the minor number is the breaking one, so 0.4.x only."
        ),
        "workspaces": RustLessonWriting(
            summary: "A workspace builds several crates against one lockfile.",
            explanation: "Members share a target directory and a single resolved dependency graph, so two crates in the same workspace can never disagree about a version. Splitting a project into a library plus a thin binary is the usual first move, because it makes the library testable on its own.",
            exampleCaption: "One root manifest, many members, one shared lockfile.",
            exampleCode: """
            # Cargo.toml at the workspace root
            [workspace]
            resolver = "2"
            members = ["core", "cli"]

            # cli/Cargo.toml
            [dependencies]
            core = { path = "../core" }
            """,
            task: "Describe how you would split a project into a library and a binary.",
            success: "The library holds the logic and the binary only wires it up.",
            rule: "Workspace members share one lockfile, so versions cannot diverge.",
            practiceCode: """
            [workspace]
            members = ["core", "cli"]
            """,
            question: "What do the members share?",
            answers: [
                "Nothing, they are independent",
                "One lockfile and one target directory",
                "Their source files",
            ],
            correctAnswer: 1,
            feedback: "Shared resolution is the point: one version of each dependency across the workspace."
        ),
        "box": RustLessonWriting(
            summary: "Box moves a value to the heap behind a single owner.",
            explanation: "A recursive type has no fixed size, because each level would contain another whole level. Box has a known pointer size, so putting the recursive part behind one makes the type representable. Box also lets a function return a trait object whose concrete size is not known at the call site.",
            exampleCaption: "Without Box, this enum would need infinite size.",
            exampleCode: """
            enum Tree {
                Leaf(i32),
                Node(Box<Tree>, Box<Tree>),
            }

            fn sum(tree: &Tree) -> i32 {
                match tree {
                    Tree::Leaf(value) => *value,
                    Tree::Node(l, r) => sum(l) + sum(r),
                }
            }
            """,
            task: "Define a recursive type and total its values.",
            success: "It compiles, and you can explain why Box is required.",
            rule: "Box gives a recursive or unsized value a known, pointer-sized home.",
            practiceCode: """
            enum List {
                Cons(i32, List),
                Nil,
            }
            """,
            question: "Why does that fail to compile?",
            answers: [
                "An enum can never refer to itself, boxed or not",
                "The type would have infinite size without an indirection",
                "An i32 payload is not allowed inside an enum",
            ],
            correctAnswer: 1,
            feedback: "Box<List> makes the recursive field pointer-sized and the type finite."
        ),
        "rc-refcell": RustLessonWriting(
            summary: "Rc shares ownership; RefCell moves the borrow check to runtime.",
            explanation: "Rc<T> keeps a count and frees when it reaches zero, but only hands out shared references. Pairing it with RefCell<T> lets you mutate through that shared handle, with the borrow rules checked at runtime instead — a violation panics rather than failing to compile. Neither is thread-safe; that is Arc and Mutex.",
            exampleCaption: "Shared ownership on the outside, controlled mutation on the inside.",
            exampleCode: """
            use std::cell::RefCell;
            use std::rc::Rc;

            let shared = Rc::new(RefCell::new(vec![1, 2, 3]));
            let second = Rc::clone(&shared);

            second.borrow_mut().push(4);
            println!("{:?}", shared.borrow());
            println!("owners {}", Rc::strong_count(&shared));
            """,
            task: "Share one vector between two handles and mutate it through both.",
            success: "Both handles observe the change and the count is correct.",
            rule: "RefCell moves the borrow rules to runtime; breaking them panics.",
            practiceCode: """
            let cell = RefCell::new(5);
            let a = cell.borrow_mut();
            let b = cell.borrow_mut();
            """,
            question: "What happens on the second borrow_mut?",
            answers: ["It compiles and works", "It panics at runtime", "It is a compile error"],
            correctAnswer: 1,
            feedback: "RefCell enforces the same rule, just later and with a panic."
        ),
        "deref-drop": RustLessonWriting(
            summary: "Deref makes your type usable like a reference to another one.",
            explanation: "Implementing Deref lets the compiler insert conversions automatically, which is why &String works where &str is expected. Drop lets a type run code when it goes out of scope, and the two together are how smart pointers feel built in — a Box behaves like the value it holds and cleans up on its own.",
            exampleCaption: "Deref coercion is why `&MyBox<String>` reaches a `&str` parameter.",
            exampleCode: """
            use std::ops::Deref;

            struct MyBox<T>(T);

            impl<T> Deref for MyBox<T> {
                type Target = T;
                fn deref(&self) -> &T { &self.0 }
            }

            fn greet(name: &str) { println!("hello {name}"); }

            let boxed = MyBox(String::from("ada"));
            greet(&boxed); // &MyBox<String> -> &String -> &str
            """,
            task: "Implement Deref for a wrapper and pass it where the inner type is expected.",
            success: "The call compiles without an explicit conversion.",
            rule: "Deref coercion applies repeatedly until the types line up.",
            practiceCode: """
            impl Drop for Guard {
                fn drop(&mut self) { println!("released"); }
            }
            """,
            question: "When does that print?",
            answers: [
                "Only when you call drop() on it explicitly",
                "Automatically when the value leaves scope",
                "At program exit, once main has returned",
            ],
            correctAnswer: 1,
            feedback: "Drop runs at the end of the value's scope; std::mem::drop just ends it sooner."
        ),
        "cycles": RustLessonWriting(
            summary: "Rust prevents data races, not leaks — a cycle can still strand memory.",
            explanation: "Two Rc handles pointing at each other never reach a count of zero, so neither is freed. Weak<T> is the answer: it does not count towards ownership and must be upgraded before use, which turns a parent pointer into something that can legitimately be gone.",
            exampleCaption: "The child points back with Weak, so the cycle never forms.",
            exampleCode: """
            use std::cell::RefCell;
            use std::rc::{Rc, Weak};

            struct Node {
                value: i32,
                parent: RefCell<Weak<Node>>,
                children: RefCell<Vec<Rc<Node>>>,
            }

            let leaf = Rc::new(Node {
                value: 3,
                parent: RefCell::new(Weak::new()),
                children: RefCell::new(vec![]),
            });
            let parent = leaf.parent.borrow().upgrade();
            println!("has parent {:?}", parent.is_some());
            """,
            task: "Explain where a parent pointer should be Weak rather than Rc.",
            success: "You can name which direction owns and which merely observes.",
            rule: "Weak does not keep a value alive, so upgrade() may return None.",
            practiceCode: """
            let parent = Rc::new(Node::new());
            let child = Rc::new(Node::new());
            // child.parent = Rc::clone(&parent);
            """,
            question: "Why should the parent link be Weak?",
            answers: [
                "A Weak link is cheaper to clone than an Rc",
                "Two Rc links in a cycle never reach zero, so nothing is freed",
                "The compiler refuses to build a cyclic Rc graph",
            ],
            correctAnswer: 1,
            feedback: "Ownership should flow one way; the back-reference observes without owning."
        ),
        "channels": RustLessonWriting(
            summary: "Do not communicate by sharing memory; share memory by communicating.",
            explanation: "An mpsc channel moves values from many producers to one consumer, and the move is what makes it safe — once sent, the sender no longer owns the value. The receiver iterates until every sender is dropped, so the loop ends on its own rather than needing a sentinel message.",
            exampleCaption: "Ownership transfers with the message, so no lock is needed.",
            exampleCode: """
            use std::sync::mpsc;
            use std::thread;

            let (tx, rx) = mpsc::channel();

            for id in 0..3 {
                let tx = tx.clone();
                thread::spawn(move || {
                    tx.send(format!("worker {id}")).unwrap();
                });
            }
            drop(tx); // so the loop can end

            for message in rx {
                println!("{message}");
            }
            """,
            task: "Send results from several threads to one collector.",
            success: "The receiving loop finishes without a sentinel value.",
            rule: "The loop ends when the last sender is dropped.",
            practiceCode: """
            let (tx, rx) = mpsc::channel();
            let worker = tx.clone();
            for message in rx { println!("{message}"); }
            """,
            question: "Why might that loop never end?",
            answers: [
                "A channel receiver loops forever by design",
                "The original tx is still alive, so the channel never closes",
                "The receiver has to be declared mut to iterate",
            ],
            correctAnswer: 1,
            feedback: "Every live sender keeps the channel open; drop the ones you do not use."
        ),
        "shared-state": RustLessonWriting(
            summary: "Arc shares the value; Mutex makes mutation through it safe.",
            explanation: "Arc<T> is Rc with an atomic count so it can cross threads. Mutex<T> holds the data itself rather than guarding it by convention, so the only way to reach the value is to lock — and the guard unlocks when it drops, which means a forgotten unlock is not a bug you can write.",
            exampleCaption: "The data lives inside the lock, so unlocked access is unrepresentable.",
            exampleCode: """
            use std::sync::{Arc, Mutex};
            use std::thread;

            let counter = Arc::new(Mutex::new(0));
            let mut handles = vec![];

            for _ in 0..8 {
                let counter = Arc::clone(&counter);
                handles.push(thread::spawn(move || {
                    *counter.lock().unwrap() += 1;
                }));
            }
            for handle in handles { handle.join().unwrap(); }
            println!("{}", *counter.lock().unwrap());
            """,
            task: "Increment one counter from several threads.",
            success: "The final total equals the number of increments, every run.",
            rule: "The lock guard unlocks on drop, so there is no unlock to forget.",
            practiceCode: """
            let counter = Rc::new(Mutex::new(0));
            thread::spawn(move || {
                *counter.lock().unwrap() += 1;
            });
            """,
            question: "Why does that fail to compile?",
            answers: [
                "A Mutex cannot hold a plain integer counter",
                "Rc is not Send, so it cannot move to another thread",
                "lock() is unsafe and needs an unsafe block",
            ],
            correctAnswer: 1,
            feedback: "Rc uses a non-atomic count; Arc is the thread-safe version."
        ),
        "send-sync": RustLessonWriting(
            summary: "Two auto traits decide what may cross a thread boundary.",
            explanation: "Send means a value can be moved to another thread; Sync means &T can be shared with one. Both are inferred from a type's fields, so you rarely write them — but they are why Rc is rejected at compile time while Arc is accepted, and why a whole class of race is a type error.",
            exampleCaption: "The bound is what the thread API asks for, spelled out.",
            exampleCode: """
            fn spawn_it<F>(job: F)
            where
                F: FnOnce() + Send + 'static,
            {
                std::thread::spawn(job);
            }

            // Arc<i32> is Send + Sync, so this is accepted.
            let value = std::sync::Arc::new(7);
            spawn_it(move || println!("{value}"));
            """,
            task: "Name why one shared pointer crosses threads and the other does not.",
            success: "You can explain the difference in terms of the count, not the API.",
            rule: "T is Sync exactly when &T is Send.",
            practiceCode: """
            let cell = std::cell::RefCell::new(0);
            std::thread::spawn(move || {
                *cell.borrow_mut() += 1;
            });
            """,
            question: "What stops that?",
            answers: [
                "RefCell is not Sync, and its runtime check is not atomic",
                "A closure is not allowed to capture a cell type",
                "borrow_mut needs an unsafe block to compile",
            ],
            correctAnswer: 0,
            feedback: "RefCell's borrow flag is not synchronised, so sharing it across threads is rejected."
        ),
        "futures": RustLessonWriting(
            summary: "An async function returns a future that has not run yet.",
            explanation: "Calling an async fn does nothing on its own: it builds a state machine that makes progress only when polled. .await yields at that point, letting the executor run something else while the operation is pending — which is how one thread can service thousands of waits.",
            exampleCaption: "Nothing happens until the future is awaited or spawned.",
            exampleCode: """
            async fn fetch(id: u32) -> String {
                format!("record {id}")
            }

            async fn run() {
                let pending = fetch(7); // nothing ran yet
                let value = pending.await; // now it runs
                println!("{value}");
            }
            """,
            task: "Explain what a call to an async fn actually produces.",
            success: "You can say why the body has not executed at that point.",
            rule: "Futures are lazy: no poll, no progress.",
            practiceCode: """
            async fn work() { println!("working"); }

            fn main() {
                work();
            }
            """,
            question: "What does that print?",
            answers: ["working, printed as soon as the future is built", "Nothing — the future is never awaited", "It panics"],
            correctAnswer: 1,
            feedback: "The future is created and dropped without ever being polled."
        ),
        "async-runtime": RustLessonWriting(
            summary: "Rust ships the async syntax but not the engine that drives it.",
            explanation: "The language defines Future and .await; polling, timers, and I/O readiness come from a runtime you choose, such as tokio or async-std. That keeps async usable on an embedded target with no allocator, at the cost of one decision you have to make per project.",
            exampleCaption: "The runtime attribute is what actually polls the future to completion.",
            exampleCode: """
            // Cargo.toml
            // tokio = { version = "1", features = ["full"] }

            #[tokio::main]
            async fn main() {
                let value = compute().await;
                println!("{value}");
            }

            async fn compute() -> u32 { 42 }
            """,
            task: "Describe what the runtime provides that the language does not.",
            success: "You can name polling, waking, and I/O readiness as runtime concerns.",
            rule: "std defines Future; the executor is a library decision.",
            practiceCode: """
            async fn main() {
                println!("hi");
            }
            """,
            question: "Why is that not a valid program entry point?",
            answers: [
                "main is not allowed to print before awaiting",
                "main cannot be async without a runtime to poll it",
                "async fn is still unstable in this edition",
            ],
            correctAnswer: 1,
            feedback: "Something has to drive the future, and that something is the runtime."
        ),
        "async-patterns": RustLessonWriting(
            summary: "Concurrency inside one task comes from combinators, not threads.",
            explanation: "join runs futures at the same time and waits for all of them; select takes whichever finishes first. Dropping a future cancels it at its last await point, which is a real advantage over threads — but it means anything that must not be interrupted needs to be written with that in mind.",
            exampleCaption: "join overlaps the waits instead of adding them up.",
            exampleCode: """
            use tokio::join;

            async fn load_user() -> &'static str { "ada" }
            async fn load_orders() -> usize { 3 }

            async fn run() {
                let (user, orders) =
                    join!(load_user(), load_orders());
                println!("{user} has {orders} orders");
            }
            """,
            task: "Run two independent awaits concurrently rather than in sequence.",
            success: "Total time is the slower of the two, not their sum.",
            rule: "Dropping a future cancels it at its last await point.",
            practiceCode: """
            let a = load_user().await;
            let b = load_orders().await;
            """,
            question: "What is wrong with that if the two are independent?",
            answers: [
                "Nothing — two awaits already overlap by default",
                "They run one after the other, so the waits add up",
                "await cannot appear twice in one function",
            ],
            correctAnswer: 1,
            feedback: "Sequential awaits serialise work that could have overlapped."
        ),
        "declarative-macros": RustLessonWriting(
            summary: "macro_rules! matches syntax patterns and expands to code.",
            explanation: "A declarative macro takes token trees, not values, so it can accept a variable number of arguments and shapes a function cannot. Fragment specifiers such as expr and ident say what each capture must be, and the expansion is type-checked afterwards like any other code.",
            exampleCaption: "One rule, any number of arguments, all checked after expansion.",
            exampleCode: """
            macro_rules! maximum {
                ($first:expr) => { $first };
                ($first:expr, $($rest:expr),+) => {
                    { let rest = maximum!($($rest),+);
                  if $first > rest { $first }
                      else { rest } }
                };
            }

            println!("{}", maximum!(3, 9, 2, 7));
            """,
            task: "Write a macro that accepts a variable number of expressions.",
            success: "It expands correctly for one, two, and many arguments.",
            rule: "Macros work on tokens before type checking, which is why they can vary in arity.",
            practiceCode: """
            macro_rules! square {
                ($value:???) => { $value * $value };
            }
            """,
            question: "Which fragment specifier accepts any expression?",
            answers: ["ident", "expr", "tt"],
            correctAnswer: 1,
            feedback: "expr captures a whole expression and keeps its grouping."
        ),
        "proc-macros": RustLessonWriting(
            summary: "A procedural macro is a compiler plugin written in Rust.",
            explanation: "It receives a TokenStream and returns one, running as a real program during compilation — which is why it lives in its own crate compiled for the host machine. That host requirement is exactly why a device-local compiler cannot execute one, and why #[derive(Serialize)] needs a desktop toolchain.",
            exampleCaption: "A separate crate, marked as a proc-macro, built for the host.",
            exampleCode: """
            # my-derive/Cargo.toml
            [lib]
            proc-macro = true

            // my-derive/src/lib.rs
            use proc_macro::TokenStream;

            #[proc_macro_derive(Hello)]
            pub fn derive_hello(
                input: TokenStream,
            ) -> TokenStream {
                // parse input, generate an impl, return it
                TokenStream::new()
            }
            """,
            task: "Explain why a proc macro cannot run inside Crabrix.",
            success: "You can name the host-compilation requirement as the reason.",
            rule: "Proc macros execute at compile time, so they need a host-native build.",
            practiceCode: """
            #[derive(Serialize)]
            struct Config { port: u16 }
            """,
            question: "What does that derive need at build time?",
            answers: [
                "Only the serde crate as a normal dependency",
                "A proc-macro crate compiled for and run on the host",
                "Nothing special — derives are built into rustc",
            ],
            correctAnswer: 1,
            feedback: "serde_derive is a program the compiler runs, not just a library it links."
        ),
        "cfg-features": RustLessonWriting(
            summary: "cfg decides which code is compiled at all.",
            explanation: "#[cfg(...)] removes code before type checking, so a platform-specific branch costs nothing on other targets and does not even have to compile there. Cargo features are the same mechanism driven from the manifest, which is how one crate serves both a no_std embedded user and a full desktop one.",
            exampleCaption: "Two implementations, one compiled per target.",
            exampleCode: """
            #[cfg(target_os = "wasi")]
            fn platform() -> &'static str { "wasi" }

            #[cfg(not(target_os = "wasi"))]
            fn platform() -> &'static str { "native" }

            #[cfg(feature = "extras")]
            mod extras;
            """,
            task: "Gate a function on a target predicate and on a feature.",
            success: "The other branch is absent from the build, not merely unused.",
            rule: "cfg removes code before compilation; a disabled branch never has to be valid.",
            practiceCode: """
            [features]
            default = ["std"]
            std = []
            """,
            question: "What does `default-features = false` do at the call site?",
            answers: [
                "Disables the crate for this build entirely",
                "Skips the default feature set, so `std` is not enabled",
                "Enables every feature the crate declares",
            ],
            correctAnswer: 1,
            feedback: "You then opt back in to exactly the features you want."
        ),
        "unsafe": RustLessonWriting(
            summary: "unsafe unlocks five operations; it does not turn off the borrow checker.",
            explanation: "Inside an unsafe block you may dereference a raw pointer, call an unsafe function, access a mutable static, implement an unsafe trait, and read a union field. Everything else is checked exactly as before. The block is a promise that you have verified an invariant the compiler cannot, which is why the convention is to write that invariant down as a SAFETY comment.",
            exampleCaption: "A small block, and the reason it is sound written next to it.",
            exampleCode: """
            fn first(slice: &[u32]) -> Option<u32> {
                if slice.is_empty() {
                    return None;
                }
                // SAFETY: the check above guarantees
                // that index 0 exists.
                Some(unsafe { *slice.get_unchecked(0) })
            }
            """,
            task: "Wrap an unchecked operation in a safe API that cannot be misused.",
            success: "No safe caller can trigger undefined behaviour.",
            rule: "unsafe is a claim about an invariant, not permission to skip the rules.",
            practiceCode: """
            let value = unsafe { *pointer };
            """,
            question: "What must be true for that to be sound?",
            answers: [
                "Nothing — unsafe makes any dereference legal",
                "The pointer is non-null, aligned, and points at a live, initialised value",
                "The pointer has to be declared mut before it is dereferenced",
            ],
            correctAnswer: 1,
            feedback: "unsafe moves the obligation to you; it does not remove it."
        ),
        "ffi": RustLessonWriting(
            summary: "Rust calls C directly, once both sides agree on the layout.",
            explanation: "extern \"C\" selects the C calling convention and #[repr(C)] fixes field order so a struct matches its C counterpart. Every call is unsafe because the compiler cannot see the other side, and ownership must be agreed explicitly — who allocates, who frees, and how long a borrowed pointer stays valid.",
            exampleCaption: "A declaration, a layout guarantee, and one unsafe call.",
            exampleCode: """
            #[repr(C)]
            struct Point { x: f64, y: f64 }

            extern "C" {
                fn abs(value: i32) -> i32;
            }

            fn main() {
                // SAFETY: abs needs only a valid i32.
                let value = unsafe { abs(-42) };
                println!("{value}");
            }
            """,
            task: "Declare a foreign function and describe who owns any memory it returns.",
            success: "The ownership contract is written down, not assumed.",
            rule: "repr(C) fixes layout; without it Rust may reorder fields.",
            practiceCode: """
            struct Point { x: f64, y: f64 }

            extern "C" { fn distance(p: Point) -> f64; }
            """,
            question: "What is missing?",
            answers: [
                    "Nothing — Rust already matches the C layout",
                "#[repr(C)] — Rust does not guarantee field order otherwise",
                "The struct has to be declared pub for the C side",
            ],
            correctAnswer: 1,
            feedback: "Without repr(C) the layout is unspecified and the C side may read the wrong bytes."
        ),
        "performance": RustLessonWriting(
            summary: "Rust is fast by default; the wins left are allocation and algorithm.",
            explanation: "Iterator chains compile to roughly the same code as a hand-written loop, so readability is rarely the cost. What does cost is allocating in a hot loop, cloning to satisfy the borrow checker, and choosing the wrong container. Reserve capacity when the size is known, borrow instead of cloning, and measure in release — a debug build is not evidence.",
            exampleCaption: "One allocation instead of a resize on nearly every push.",
            exampleCode: """
            let mut values = Vec::with_capacity(1_000);
            for index in 0..1_000 {
                values.push(index * 2);
            }

            // Borrow instead of cloning to read.
            fn total(values: &[usize]) -> usize {
                values.iter().sum()
            }
            """,
            task: "Find one clone or one allocation in a loop and remove it.",
            success: "Behaviour is unchanged and the allocation count drops.",
            rule: "Measure a release build; debug numbers say nothing about optimized code.",
            practiceCode: """
            fn shout(items: &Vec<String>) -> Vec<String> {
                items.clone().iter()
                    .map(|s| s.to_uppercase())
                    .collect()
            }
            """,
            question: "Which change removes the wasted work?",
            answers: [
                "Take &[String] and drop the clone",
                "Return a reference to the first name",
                "Use a HashMap",
            ],
            correctAnswer: 0,
            feedback: "The clone is never needed: map already produces new Strings."
        ),
        "idioms": RustLessonWriting(
            summary: "Rust's patterns push mistakes from runtime to compile time.",
            explanation: "A newtype gives a bare value a meaning the type system can enforce, so a UserId cannot be passed where an OrderId belongs. A builder makes many optional parameters readable, and typestate encodes a protocol in types so calling a method in the wrong order simply does not compile.",
            exampleCaption: "Two integers that can no longer be confused for each other.",
            exampleCode: """
            #[derive(Debug, Clone, Copy, PartialEq)]
            struct UserId(u64);

            #[derive(Debug, Clone, Copy, PartialEq)]
            struct OrderId(u64);

            fn load_user(id: UserId) -> String {
                format!("user {}", id.0)
            }

            // load_user(OrderId(7)) would not compile.
            println!("{}", load_user(UserId(7)));
            """,
            task: "Wrap a primitive in a newtype and pass it through one function.",
            success: "Mixing it with another id of the same underlying type fails to compile.",
            rule: "A newtype costs nothing at runtime and buys a real compile-time guarantee.",
            practiceCode: """
            fn transfer(from: u64, to: u64, amount: u64) { }
            transfer(amount, from, to);
            """,
            question: "What does a newtype fix here?",
            answers: [
                "Nothing, the arguments are the same type",
                "Distinct types make a wrong argument order a compile error",
                "It removes a runtime check, so it is faster",
            ],
            correctAnswer: 1,
            feedback: "Three bare u64s are interchangeable; AccountId and Amount are not."
        ),
    ]
}
