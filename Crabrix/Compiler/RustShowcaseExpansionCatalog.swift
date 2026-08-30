import Foundation

/// Guided, editable projects added after the original showcase catalogue.
/// Each package includes a README with a concrete extension challenge, so the
/// examples are learning projects rather than code that can only be watched.
enum RustShowcaseExpansionCatalog {
    private static func guided(
        id: String,
        title: String,
        detail: String,
        systemImage: String,
        category: RustShowcaseCategory,
        difficulty: RustShowcaseDifficulty,
        concepts: [String],
        challenge: String,
        source: String
    ) -> RustShowcaseProject {
        let conceptList = concepts.map { "- \($0)" }.joined(separator: "\n")
        let readme = """
        # \(title)

        \(detail).

        ## Concepts

        \(conceptList)

        ## Your challenge

        \(challenge)

        ## Proof

        Run the starter first, predict the changed output, make one focused
        edit, and Run again with the bundled compiler.
        """
        return RustShowcaseProject(
            id: id,
            title: title,
            detail: detail,
            systemImage: systemImage,
            category: category,
            difficulty: difficulty,
            concepts: concepts,
            project: CrabrixProject(
                name: id,
                files: [
                    "Cargo.toml": RustShowcaseCatalog.manifest(name: id),
                    "README.md": readme,
                    "src/main.rs": source,
                ],
                entryFile: "src/main.rs",
                provenance: nil
            )
        )
    }

    static let projects: [RustShowcaseProject] = [
        guided(
            id: "budget-planner",
            title: "Budget Planner",
            detail: "Model expenses and calculate category totals",
            systemImage: "banknote.fill",
            category: .data,
            difficulty: .starter,
            concepts: ["struct", "iterators", "f64"],
            challenge: "Add a category field, then print one subtotal per category before the grand total.",
            source: """
            #[derive(Debug)]
            struct Expense {
                label: &'static str,
                amount: f64,
            }

            fn main() {
                let expenses = [
                    Expense { label: "rent", amount: 850.0 },
                    Expense { label: "food", amount: 126.4 },
                    Expense { label: "books", amount: 42.5 },
                ];
                let total: f64 = expenses.iter()
                    .map(|expense| expense.amount)
                    .sum();

                println!("MONTHLY BUDGET");
                for expense in &expenses {
                    println!("{:<10} {:>8.2}", expense.label, expense.amount);
                }
                println!("{:<10} {:>8.2}", "total", total);
            }
            """
        ),
        guided(
            id: "todo-board",
            title: "Todo Board",
            detail: "Track work with structs and an explicit state enum",
            systemImage: "checklist",
            category: .data,
            difficulty: .starter,
            concepts: ["enum", "struct", "filter"],
            challenge: "Add a Blocked state and print a separate count for every state without using string status values.",
            source: """
            #[derive(Debug, Clone, Copy, PartialEq)]
            enum State {
                Todo,
                Doing,
                Done,
            }

            #[derive(Debug)]
            struct Task {
                title: &'static str,
                state: State,
            }

            fn main() {
                let tasks = [
                    Task { title: "learn match", state: State::Done },
                    Task { title: "repair E0502", state: State::Doing },
                    Task { title: "write tests", state: State::Todo },
                ];
                for task in &tasks {
                    println!("{:?}  {}", task.state, task.title);
                }
                let done = tasks.iter()
                    .filter(|task| task.state == State::Done)
                    .count();
                println!("done {done}/{}", tasks.len());
            }
            """
        ),
        guided(
            id: "caesar-cipher",
            title: "Caesar Cipher",
            detail: "Transform ASCII text one character at a time",
            systemImage: "lock.rotation",
            category: .text,
            difficulty: .starter,
            concepts: ["char", "map", "modulo"],
            challenge: "Support uppercase letters and write a decode function that restores the original message.",
            source: """
            fn shift(character: char, amount: u8) -> char {
                if !character.is_ascii_lowercase() {
                    return character;
                }
                let offset = character as u8 - b'a';
                (b'a' + (offset + amount) % 26) as char
            }

            fn encode(text: &str, amount: u8) -> String {
                text.chars()
                    .map(|character| shift(character, amount))
                    .collect()
            }

            fn main() {
                let message = "rust makes ownership visible";
                let encoded = encode(message, 5);
                println!("plain   {message}");
                println!("cipher  {encoded}");
            }
            """
        ),
        guided(
            id: "palindrome-inspector",
            title: "Palindrome Inspector",
            detail: "Normalize Unicode text before comparing it",
            systemImage: "textformat.abc.dottedunderline",
            category: .text,
            difficulty: .starter,
            concepts: ["chars", "filter", "reverse"],
            challenge: "Return the normalized text with the verdict and add three more punctuation-heavy test phrases.",
            source: """
            fn normalized(text: &str) -> String {
                text.chars()
                    .filter(|ch| ch.is_alphanumeric())
                    .flat_map(char::to_lowercase)
                    .collect()
            }

            fn is_palindrome(text: &str) -> bool {
                let clean = normalized(text);
                clean.chars().eq(clean.chars().rev())
            }

            fn main() {
                for phrase in [
                    "Never odd or even",
                    "Rust trusts rustc",
                    "Was it a rat I saw?",
                ] {
                    println!("{:<22} {}", phrase, is_palindrome(phrase));
                }
            }
            """
        ),
        guided(
            id: "unit-converter",
            title: "Unit Converter",
            detail: "Keep formulas in small typed functions",
            systemImage: "ruler.fill",
            category: .math,
            difficulty: .starter,
            concepts: ["functions", "f64", "formatting"],
            challenge: "Add kilometres-to-miles and reject physically impossible Kelvin temperatures with Result.",
            source: """
            fn celsius_to_fahrenheit(value: f64) -> f64 {
                value * 9.0 / 5.0 + 32.0
            }

            fn kilograms_to_pounds(value: f64) -> f64 {
                value * 2.204_622_621_8
            }

            fn main() {
                for value in [-20.0, 0.0, 21.5, 100.0] {
                    println!(
                        "{value:>6.1} C = {:>6.1} F",
                        celsius_to_fahrenheit(value)
                    );
                }
                println!("5 kg = {:.2} lb", kilograms_to_pounds(5.0));
            }
            """
        ),
        guided(
            id: "ascii-histogram",
            title: "ASCII Histogram",
            detail: "Turn numeric data into a terminal chart",
            systemImage: "chart.bar.fill",
            category: .graphics,
            difficulty: .starter,
            concepts: ["arrays", "repeat", "formatting"],
            challenge: "Scale values larger than 20 into a fixed-width bar and label the maximum row.",
            source: """
            fn bar(value: usize) -> String {
                "█".repeat(value)
            }

            fn main() {
                let samples = [
                    ("Mon", 4),
                    ("Tue", 9),
                    ("Wed", 6),
                    ("Thu", 12),
                    ("Fri", 8),
                ];
                println!("LOCAL BUILDS");
                for (day, count) in samples {
                    println!("{day} {:<12} {count}", bar(count));
                }
            }
            """
        ),
        guided(
            id: "dice-lab",
            title: "Dice Lab",
            detail: "Simulate repeatable dice rolls with an LCG",
            systemImage: "dice.fill",
            category: .games,
            difficulty: .starter,
            concepts: ["arrays", "wrapping", "simulation"],
            challenge: "Roll two dice, chart the totals from 2 through 12, and explain why the distribution is not flat.",
            source: """
            fn next(seed: &mut u32) -> u32 {
                *seed = seed
                    .wrapping_mul(1_664_525)
                    .wrapping_add(1_013_904_223);
                *seed
            }

            fn main() {
                let mut seed = 0xC0FFEE;
                let mut counts = [0_u32; 6];
                for _ in 0..120 {
                    let face = (next(&mut seed) % 6) as usize;
                    counts[face] += 1;
                }
                for (index, count) in counts.iter().enumerate() {
                    println!("{}  {:>3}", index + 1, count);
                }
            }
            """
        ),
        guided(
            id: "tic-tac-toe-referee",
            title: "Tic-Tac-Toe Referee",
            detail: "Evaluate a board with indexed winning lines",
            systemImage: "number.square.fill",
            category: .games,
            difficulty: .intermediate,
            concepts: ["arrays", "Option", "patterns"],
            challenge: "Detect a draw separately from an unfinished board and validate that turn counts are legal.",
            source: """
            fn winner(board: &[char; 9]) -> Option<char> {
                let lines = [
                    [0, 1, 2], [3, 4, 5], [6, 7, 8],
                    [0, 3, 6], [1, 4, 7], [2, 5, 8],
                    [0, 4, 8], [2, 4, 6],
                ];
                for [a, b, c] in lines {
                    let mark = board[a];
                    if mark != ' '
                        && mark == board[b]
                        && mark == board[c]
                    {
                        return Some(mark);
                    }
                }
                None
            }

            fn main() {
                let board = [
                    'X', 'O', 'X',
                    'O', 'X', ' ',
                    'X', ' ', 'O',
                ];
                for row in board.chunks(3) {
                    println!("{}|{}|{}", row[0], row[1], row[2]);
                }
                println!("winner: {:?}", winner(&board));
            }
            """
        ),
        guided(
            id: "log-analyzer",
            title: "Log Analyzer",
            detail: "Filter structured log lines and count levels",
            systemImage: "doc.text.magnifyingglass",
            category: .systems,
            difficulty: .starter,
            concepts: ["lines", "split_once", "match"],
            challenge: "Parse the component after the level, then report the component with the most errors.",
            source: """
            fn main() {
                let log = "INFO compiler ready\n\
            WARN cache cold\n\
            ERROR parser failed\n\
            INFO cache warm\n\
            ERROR linker failed";
                let mut counts = [0_u32; 3];
                for line in log.lines() {
                    let level = line.split_once(' ')
                        .map(|pair| pair.0)
                        .unwrap_or("UNKNOWN");
                    match level {
                        "INFO" => counts[0] += 1,
                        "WARN" => counts[1] += 1,
                        "ERROR" => counts[2] += 1,
                        _ => {}
                    }
                }
                println!("info  {}", counts[0]);
                println!("warn  {}", counts[1]);
                println!("error {}", counts[2]);
            }
            """
        ),
        guided(
            id: "inventory-ledger",
            title: "Inventory Ledger",
            detail: "Apply typed stock transactions to a BTreeMap",
            systemImage: "shippingbox.and.arrow.backward.fill",
            category: .data,
            difficulty: .intermediate,
            concepts: ["enum", "BTreeMap", "entry"],
            challenge: "Return an error when a sale would make stock negative and leave the ledger unchanged.",
            source: """
            use std::collections::BTreeMap;

            enum Transaction {
                Receive(&'static str, i32),
                Sell(&'static str, i32),
            }

            fn apply(
                stock: &mut BTreeMap<&'static str, i32>,
                transaction: Transaction,
            ) {
                let (item, change) = match transaction {
                    Transaction::Receive(item, count) => (item, count),
                    Transaction::Sell(item, count) => (item, -count),
                };
                *stock.entry(item).or_insert(0) += change;
            }

            fn main() {
                let mut stock = BTreeMap::new();
                for transaction in [
                    Transaction::Receive("keyboard", 12),
                    Transaction::Receive("mouse", 20),
                    Transaction::Sell("keyboard", 3),
                ] {
                    apply(&mut stock, transaction);
                }
                for (item, count) in stock {
                    println!("{item:<10} {count:>3}");
                }
            }
            """
        ),
        guided(
            id: "maze-bfs",
            title: "Maze Pathfinder",
            detail: "Find a shortest grid path with breadth-first search",
            systemImage: "point.topleft.down.to.point.bottomright.curvepath",
            category: .algorithms,
            difficulty: .intermediate,
            concepts: ["VecDeque", "grid", "BFS"],
            challenge: "Store each cell's predecessor and print the actual shortest route over the maze.",
            source: """
            use std::collections::VecDeque;

            const MAZE: [&str; 7] = [
                "############",
                "#S   #     #",
                "###  # ### #",
                "#    #   # #",
                "# #### # # #",
                "#      #  G#",
                "############",
            ];

            fn main() {
                let start = (1_usize, 1_usize);
                let goal = (5_usize, 10_usize);
                let mut distance = [[usize::MAX; 12]; 7];
                let mut queue = VecDeque::from([start]);
                distance[start.0][start.1] = 0;

                while let Some((row, col)) = queue.pop_front() {
                    for (dr, dc) in [(1_i32, 0_i32), (-1, 0), (0, 1), (0, -1)] {
                        let next_row = (row as i32 + dr) as usize;
                        let next_col = (col as i32 + dc) as usize;
                        let open = MAZE[next_row].as_bytes()[next_col] != b'#';
                        if open && distance[next_row][next_col] == usize::MAX {
                            distance[next_row][next_col] = distance[row][col] + 1;
                            queue.push_back((next_row, next_col));
                        }
                    }
                }
                println!("shortest path: {} steps", distance[goal.0][goal.1]);
            }
            """
        ),
        guided(
            id: "markdown-outline",
            title: "Markdown Outline",
            detail: "Extract headings into an indented document map",
            systemImage: "list.bullet.indent",
            category: .text,
            difficulty: .starter,
            concepts: ["lines", "trim", "slices"],
            challenge: "Reject heading jumps such as level 1 directly to level 3 and return a useful line number.",
            source: """
            fn main() {
                let markdown = "# Crabrix\n\
            Intro text\n\
            ## Build\n\
            ### Packages\n\
            ## Learn\n\
            ### Practice";

                for line in markdown.lines() {
                    let marks = line.chars()
                        .take_while(|ch| *ch == '#')
                        .count();
                    if marks == 0 {
                        continue;
                    }
                    let title = line[marks..].trim();
                    println!("{}- {title}", "  ".repeat(marks - 1));
                }
            }
            """
        ),
        guided(
            id: "command-parser",
            title: "Command Parser",
            detail: "Turn terminal text into a typed command enum",
            systemImage: "apple.terminal.fill",
            category: .systems,
            difficulty: .intermediate,
            concepts: ["enum", "Result", "splitn"],
            challenge: "Add quoted task titles and return a precise error for an unfinished quote.",
            source: """
            #[derive(Debug)]
            enum Command {
                Add(String),
                Done(usize),
                List,
            }

            fn parse(input: &str) -> Result<Command, String> {
                let mut parts = input.trim().splitn(2, ' ');
                match (parts.next(), parts.next()) {
                    (Some("add"), Some(title)) => {
                        Ok(Command::Add(title.to_string()))
                    }
                    (Some("done"), Some(index)) => index
                        .parse()
                        .map(Command::Done)
                        .map_err(|_| "bad index".to_string()),
                    (Some("list"), None) => Ok(Command::List),
                    _ => Err("unknown command".to_string()),
                }
            }

            fn main() {
                for input in ["add learn ownership", "done 2", "list", "erase"] {
                    match parse(input) {
                        Ok(Command::Add(title)) => println!("add: {title}"),
                        Ok(Command::Done(index)) => println!("done: {index}"),
                        Ok(Command::List) => println!("list"),
                        Err(error) => println!("error: {error}"),
                    }
                }
            }
            """
        ),
        guided(
            id: "checksum-lab",
            title: "Checksum Lab",
            detail: "Compute a deterministic FNV-1a content fingerprint",
            systemImage: "number.circle.fill",
            category: .systems,
            difficulty: .starter,
            concepts: ["bytes", "wrapping", "hash"],
            challenge: "Hash several project files in sorted path order so renaming or editing any file changes one project fingerprint.",
            source: """
            fn fnv1a(bytes: &[u8]) -> u64 {
                let mut hash = 0xcbf2_9ce4_8422_2325_u64;
                for byte in bytes {
                    hash ^= u64::from(*byte);
                    hash = hash.wrapping_mul(0x100_0000_01b3);
                }
                hash
            }

            fn main() {
                for text in ["rust", "Rust", "rust!"] {
                    println!("{text:<5} {:016x}", fnv1a(text.as_bytes()));
                }
            }
            """
        ),
        guided(
            id: "task-scheduler",
            title: "Task Scheduler",
            detail: "Order jobs and build a deterministic timeline",
            systemImage: "calendar.badge.clock",
            category: .simulation,
            difficulty: .intermediate,
            concepts: ["sort_by_key", "struct", "timeline"],
            challenge: "Add release times and make the scheduler choose the shortest available job instead of sorting once.",
            source: """
            #[derive(Debug)]
            struct Job {
                name: &'static str,
                priority: u8,
                duration: u32,
            }

            fn main() {
                let mut jobs = vec![
                    Job { name: "docs", priority: 2, duration: 3 },
                    Job { name: "build", priority: 1, duration: 8 },
                    Job { name: "tests", priority: 1, duration: 5 },
                    Job { name: "archive", priority: 3, duration: 2 },
                ];
                jobs.sort_by_key(|job| (job.priority, job.duration));

                let mut clock = 0;
                for job in jobs {
                    let start = clock;
                    clock += job.duration;
                    println!("{:>2}..{:>2}  {}", start, clock, job.name);
                }
            }
            """
        ),
        guided(
            id: "vending-state-machine",
            title: "Vending State Machine",
            detail: "Encode valid machine transitions with enums",
            systemImage: "button.programmable.square.fill",
            category: .simulation,
            difficulty: .intermediate,
            concepts: ["enum", "match", "state machine"],
            challenge: "Add sold-out inventory and make an invalid purchase preserve both credit and stock.",
            source: """
            #[derive(Debug, Clone, Copy)]
            enum State {
                Waiting,
                Credit(u32),
            }

            #[derive(Debug, Clone, Copy)]
            enum Event {
                Insert(u32),
                Buy { price: u32 },
                Cancel,
            }

            fn transition(state: State, event: Event) -> State {
                match (state, event) {
                    (State::Waiting, Event::Insert(value)) => {
                        State::Credit(value)
                    }
                    (State::Credit(total), Event::Insert(value)) => {
                        State::Credit(total + value)
                    }
                    (State::Credit(total), Event::Buy { price })
                        if total >= price => State::Credit(total - price),
                    (_, Event::Cancel) => State::Waiting,
                    (state, _) => state,
                }
            }

            fn main() {
                let events = [
                    Event::Insert(50),
                    Event::Insert(25),
                    Event::Buy { price: 60 },
                    Event::Cancel,
                ];
                let mut state = State::Waiting;
                for event in events {
                    state = transition(state, event);
                    println!("{state:?}");
                }
            }
            """
        ),
        guided(
            id: "weather-station",
            title: "Weather Station",
            detail: "Summarize sensor samples without losing units",
            systemImage: "sensor.fill",
            category: .data,
            difficulty: .intermediate,
            concepts: ["newtype", "fold", "statistics"],
            challenge: "Represent Celsius as a newtype and reject an empty sample slice with Result.",
            source: """
            #[derive(Debug, Clone, Copy)]
            struct Sample {
                celsius: f64,
                humidity: u8,
            }

            fn main() {
                let samples = [
                    Sample { celsius: 21.4, humidity: 58 },
                    Sample { celsius: 22.1, humidity: 55 },
                    Sample { celsius: 20.8, humidity: 61 },
                    Sample { celsius: 23.0, humidity: 52 },
                ];
                let average = samples.iter()
                    .map(|sample| sample.celsius)
                    .sum::<f64>() / samples.len() as f64;
                let driest = samples.iter()
                    .min_by_key(|sample| sample.humidity)
                    .unwrap();
                println!("average {average:.1} C");
                println!("driest  {}%", driest.humidity);
            }
            """
        ),
        guided(
            id: "rpn-calculator",
            title: "RPN Calculator",
            detail: "Evaluate typed tokens with a checked stack",
            systemImage: "function",
            category: .algorithms,
            difficulty: .advanced,
            concepts: ["Result", "stack", "parsing"],
            challenge: "Add division-by-zero protection and require exactly one value to remain after evaluation.",
            source: """
            fn evaluate(input: &str) -> Result<f64, String> {
                let mut stack = Vec::new();
                for token in input.split_whitespace() {
                    match token {
                        "+" | "-" | "*" | "/" => {
                            let right = stack.pop()
                                .ok_or("missing right operand")?;
                            let left = stack.pop()
                                .ok_or("missing left operand")?;
                            let value = match token {
                                "+" => left + right,
                                "-" => left - right,
                                "*" => left * right,
                                "/" => left / right,
                                _ => unreachable!(),
                            };
                            stack.push(value);
                        }
                        number => stack.push(
                            number.parse::<f64>()
                                .map_err(|_| format!("bad token: {number}"))?
                        ),
                    }
                }
                stack.pop().ok_or("empty expression".to_string())
            }

            fn main() {
                for expression in ["3 4 +", "5 2 * 8 +", "9 3 / 2 -"] {
                    println!("{expression:<12} {:?}", evaluate(expression));
                }
            }
            """
        ),
        guided(
            id: "event-bus",
            title: "Event Bus",
            detail: "Dispatch one event to different trait objects",
            systemImage: "dot.radiowaves.left.and.right",
            category: .systems,
            difficulty: .advanced,
            concepts: ["trait object", "Vec<Box<_>>", "dispatch"],
            challenge: "Let handlers subscribe to selected event kinds and return collected messages instead of printing directly.",
            source: """
            #[derive(Debug)]
            enum Event {
                BuildPassed,
                Diagnostic(String),
            }

            trait Handler {
                fn handle(&mut self, event: &Event);
            }

            struct Counter(usize);

            impl Handler for Counter {
                fn handle(&mut self, _event: &Event) {
                    self.0 += 1;
                    println!("events seen: {}", self.0);
                }
            }

            struct Reporter;

            impl Handler for Reporter {
                fn handle(&mut self, event: &Event) {
                    match event {
                        Event::BuildPassed => println!("build passed"),
                        Event::Diagnostic(text) => println!("diagnostic: {text}"),
                    }
                }
            }

            fn main() {
                let mut handlers: Vec<Box<dyn Handler>> = vec![
                    Box::new(Counter(0)),
                    Box::new(Reporter),
                ];
                let events = [
                    Event::BuildPassed,
                    Event::Diagnostic("E0502".to_string()),
                ];
                for event in &events {
                    for handler in &mut handlers {
                        handler.handle(event);
                    }
                }
            }
            """
        ),
        guided(
            id: "word-chain-game",
            title: "Word Chain Game",
            detail: "Validate turn order and reject repeated words",
            systemImage: "link.circle.fill",
            category: .games,
            difficulty: .intermediate,
            concepts: ["HashSet", "windows", "validation"],
            challenge: "Return a typed error that distinguishes duplicate words from a broken letter connection.",
            source: """
            use std::collections::HashSet;

            fn validate(words: &[&str]) -> Result<(), String> {
                let mut seen = HashSet::new();
                for word in words {
                    if !seen.insert(word.to_lowercase()) {
                        return Err(format!("repeated word: {word}"));
                    }
                }
                for pair in words.windows(2) {
                    let left = pair[0].chars().last();
                    let right = pair[1].chars().next();
                    if left != right {
                        return Err(format!(
                            "{} does not connect to {}",
                            pair[0], pair[1]
                        ));
                    }
                }
                Ok(())
            }

            fn main() {
                let good = ["crab", "borrow", "rust", "trait"];
                let bad = ["rust", "trait", "thread", "rust"];
                println!("good: {:?}", validate(&good));
                println!("bad:  {:?}", validate(&bad));
            }
            """
        ),
    ]
}
