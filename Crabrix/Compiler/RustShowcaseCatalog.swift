import Foundation

/// The second half of the project library.
///
/// These live apart from the four original showcases so the catalogue can keep
/// growing without turning `RustSamples` into one unreadable file. Every project
/// is std-only and compiles with the bundled toolchain.
enum RustShowcaseCatalog {
    static func manifest(name: String) -> String {
        """
        [package]
        name = "\(name)"
        version = "0.1.0"
        edition = "2024"

        [dependencies]
        """
    }

    private static func single(
        id: String,
        title: String,
        detail: String,
        systemImage: String,
        category: RustShowcaseCategory,
        difficulty: RustShowcaseDifficulty,
        concepts: [String],
        source: String
    ) -> RustShowcaseProject {
        RustShowcaseProject(
            id: id,
            title: title,
            detail: detail,
            systemImage: systemImage,
            category: category,
            difficulty: difficulty,
            concepts: concepts,
            project: CrabrixProject(
                name: id,
                files: ["Cargo.toml": manifest(name: id), "src/main.rs": source],
                entryFile: "src/main.rs",
                provenance: nil
            )
        )
    }

    static let projects: [RustShowcaseProject] = [
        single(
            id: "fizzbuzz-match",
            title: "FizzBuzz by Match",
            detail: "The classic, written the way Rust wants it",
            systemImage: "number.square.fill",
            category: .algorithms,
            difficulty: .starter,
            concepts: ["match", "tuples", "ranges"],
            source: """
            fn classify(value: u32) -> String {
                match (value % 3, value % 5) {
                    (0, 0) => "FizzBuzz".to_string(),
                    (0, _) => "Fizz".to_string(),
                    (_, 0) => "Buzz".to_string(),
                    _ => value.to_string(),
                }
            }

            fn main() {
                for value in 1..=20 {
                    println!("{:>2} -> {}", value, classify(value));
                }
            }
            """
        ),
        single(
            id: "temperature-table",
            title: "Temperature Table",
            detail: "Formatting, floats, and a tidy aligned table",
            systemImage: "thermometer.medium",
            category: .data,
            difficulty: .starter,
            concepts: ["floats", "formatting", "iterators"],
            source: """
            fn to_fahrenheit(celsius: f64) -> f64 {
                celsius * 9.0 / 5.0 + 32.0
            }

            fn main() {
                println!("{:>8} {:>12} {:>10}", "CELSIUS", "FAHRENHEIT", "KELVIN");
                for step in 0..=10 {
                    let celsius = -20.0 + f64::from(step) * 5.0;
                    println!(
                        "{:>8.1} {:>12.1} {:>10.2}",
                        celsius,
                        to_fahrenheit(celsius),
                        celsius + 273.15
                    );
                }
            }
            """
        ),
        single(
            id: "prime-sieve",
            title: "Prime Sieve",
            detail: "Sieve of Eratosthenes over a boolean Vec",
            systemImage: "square.grid.3x3.fill",
            category: .algorithms,
            difficulty: .starter,
            concepts: ["Vec", "loops", "algorithms"],
            source: """
            fn sieve(limit: usize) -> Vec<usize> {
                let mut is_prime = vec![true; limit + 1];
                is_prime[0] = false;
                if limit >= 1 {
                    is_prime[1] = false;
                }

                let mut value = 2;
                while value * value <= limit {
                    if is_prime[value] {
                        let mut multiple = value * value;
                        while multiple <= limit {
                            is_prime[multiple] = false;
                            multiple += value;
                        }
                    }
                    value += 1;
                }

                is_prime
                    .iter()
                    .enumerate()
                    .filter(|(_, prime)| **prime)
                    .map(|(index, _)| index)
                    .collect()
            }

            fn main() {
                let primes = sieve(200);
                println!("{} primes below 200", primes.len());
                for chunk in primes.chunks(10) {
                    let row: Vec<String> = chunk.iter().map(|p| format!("{p:>4}")).collect();
                    println!("{}", row.join(" "));
                }
            }
            """
        ),
        single(
            id: "roman-numerals",
            title: "Roman Numerals",
            detail: "Two-way conversion with slices and folds",
            systemImage: "textformat.abc",
            category: .algorithms,
            difficulty: .intermediate,
            concepts: ["slices", "String", "fold"],
            source: """
            const TABLE: [(u32, &str); 13] = [
                (1000, "M"), (900, "CM"), (500, "D"), (400, "CD"),
                (100, "C"), (90, "XC"), (50, "L"), (40, "XL"),
                (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I"),
            ];

            fn to_roman(mut value: u32) -> String {
                let mut out = String::new();
                for (amount, symbol) in TABLE {
                    while value >= amount {
                        out.push_str(symbol);
                        value -= amount;
                    }
                }
                out
            }

            fn from_roman(text: &str) -> i64 {
                let digits: Vec<i64> = text
                    .chars()
                    .map(|c| match c {
                        'I' => 1, 'V' => 5, 'X' => 10, 'L' => 50,
                        'C' => 100, 'D' => 500, 'M' => 1000,
                        _ => 0,
                    })
                    .collect();

                // Signed, because a subtractive pair such as IV starts by
                // going negative before the larger digit is added.
                let mut total: i64 = 0;
                for (index, value) in digits.iter().enumerate() {
                    match digits.get(index + 1) {
                        Some(next) if next > value => total -= value,
                        _ => total += value,
                    }
                }
                total
            }

            fn main() {
                for value in [4, 9, 14, 40, 1987, 2024] {
                    let roman = to_roman(value);
                    println!("{value:>4} -> {roman:<10} -> {}", from_roman(&roman));
                }
            }
            """
        ),
        single(
            id: "run-length-encoder",
            title: "Run-Length Encoder",
            detail: "Compress and expand a string, round-trip checked",
            systemImage: "arrow.left.and.right.square.fill",
            category: .text,
            difficulty: .intermediate,
            concepts: ["chars", "String", "assert"],
            source: """
            fn encode(input: &str) -> String {
                let mut out = String::new();
                let mut chars = input.chars().peekable();

                while let Some(current) = chars.next() {
                    let mut run = 1;
                    while chars.peek() == Some(&current) {
                        chars.next();
                        run += 1;
                    }
                    out.push_str(&run.to_string());
                    out.push(current);
                }
                out
            }

            fn decode(input: &str) -> String {
                let mut out = String::new();
                let mut count = String::new();

                for character in input.chars() {
                    if character.is_ascii_digit() {
                        count.push(character);
                    } else {
                        let run: usize = count.parse().unwrap_or(1);
                        out.push_str(&character.to_string().repeat(run));
                        count.clear();
                    }
                }
                out
            }

            fn main() {
                let original = "aaabccddddde";
                let packed = encode(original);
                let restored = decode(&packed);

                println!("original  {original}");
                println!("encoded   {packed}");
                println!("decoded   {restored}");
                assert_eq!(original, restored);
                println!("round trip verified");
            }
            """
        ),
        single(
            id: "matrix-multiply",
            title: "Matrix Multiply",
            detail: "Nested Vec maths with a printed result grid",
            systemImage: "squareshape.split.3x3",
            category: .math,
            difficulty: .intermediate,
            concepts: ["Vec<Vec<T>>", "indexing", "math"],
            source: """
            type Matrix = Vec<Vec<i32>>;

            fn multiply(left: &Matrix, right: &Matrix) -> Matrix {
                let rows = left.len();
                let inner = right.len();
                let cols = right[0].len();
                let mut out = vec![vec![0_i32; cols]; rows];

                for row in 0..rows {
                    for col in 0..cols {
                        let mut sum: i32 = 0;
                        for k in 0..inner {
                            sum += left[row][k] * right[k][col];
                        }
                        out[row][col] = sum;
                    }
                }
                out
            }

            fn show(label: &str, matrix: &Matrix) {
                println!("{label}");
                for row in matrix {
                    let cells: Vec<String> = row.iter().map(|v| format!("{v:>6}")).collect();
                    println!("  [{}]", cells.join(" "));
                }
            }

            fn main() {
                let a: Matrix = vec![vec![1, 2, 3], vec![4, 5, 6]];
                let b: Matrix = vec![vec![7, 8], vec![9, 10], vec![11, 12]];
                show("A", &a);
                show("B", &b);
                show("A x B", &multiply(&a, &b));
            }
            """
        ),
        single(
            id: "mandelbrot-ascii",
            title: "Mandelbrot in ASCII",
            detail: "Escape-time fractal drawn with characters",
            systemImage: "circle.hexagongrid.fill",
            category: .graphics,
            difficulty: .intermediate,
            concepts: ["floats", "nested loops", "math"],
            source: """
            const SHADES: [char; 8] = [' ', '.', ':', '-', '=', '+', '*', '#'];

            fn escape(cx: f64, cy: f64, limit: u32) -> u32 {
                let (mut x, mut y) = (0.0_f64, 0.0_f64);
                let mut step = 0;
                while x * x + y * y <= 4.0 && step < limit {
                    let next_x = x * x - y * y + cx;
                    y = 2.0 * x * y + cy;
                    x = next_x;
                    step += 1;
                }
                step
            }

            fn main() {
                let limit = 60;
                for row in 0..24 {
                    let mut line = String::new();
                    for col in 0..64 {
                        let cx = -2.2 + f64::from(col) * 3.0 / 64.0;
                        let cy = -1.2 + f64::from(row) * 2.4 / 24.0;
                        let steps = escape(cx, cy, limit);
                        let index = (steps as usize * (SHADES.len() - 1)) / limit as usize;
                        line.push(SHADES[index]);
                    }
                    println!("{line}");
                }
            }
            """
        ),
        single(
            id: "game-of-life",
            title: "Game of Life",
            detail: "Conway's automaton stepped and printed",
            systemImage: "square.grid.4x3.fill",
            category: .simulation,
            difficulty: .intermediate,
            concepts: ["grids", "wrapping", "simulation"],
            source: """
            const WIDTH: usize = 32;
            const HEIGHT: usize = 16;

            fn neighbours(grid: &[[bool; WIDTH]; HEIGHT], row: usize, col: usize) -> usize {
                let mut count = 0;
                for delta_row in [HEIGHT - 1, 0, 1] {
                    for delta_col in [WIDTH - 1, 0, 1] {
                        if delta_row == 0 && delta_col == 0 {
                            continue;
                        }
                        let r = (row + delta_row) % HEIGHT;
                        let c = (col + delta_col) % WIDTH;
                        if grid[r][c] {
                            count += 1;
                        }
                    }
                }
                count
            }

            fn step(grid: &[[bool; WIDTH]; HEIGHT]) -> [[bool; WIDTH]; HEIGHT] {
                let mut next = [[false; WIDTH]; HEIGHT];
                for row in 0..HEIGHT {
                    for col in 0..WIDTH {
                        next[row][col] = matches!(
                            (grid[row][col], neighbours(grid, row, col)),
                            (true, 2) | (true, 3) | (false, 3)
                        );
                    }
                }
                next
            }

            fn main() {
                let mut grid = [[false; WIDTH]; HEIGHT];
                // A glider.
                for (row, col) in [(0, 1), (1, 2), (2, 0), (2, 1), (2, 2)] {
                    grid[row][col] = true;
                }

                for generation in 0..4 {
                    println!("generation {generation}");
                    for row in grid.iter() {
                        let line: String = row.iter().map(|&on| if on { '#' } else { '.' }).collect();
                        println!("{line}");
                    }
                    println!();
                    grid = step(&grid);
                }
            }
            """
        ),
        single(
            id: "binary-search-tree",
            title: "Binary Search Tree",
            detail: "Box, Option, and recursion building a real tree",
            systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill",
            category: .data,
            difficulty: .advanced,
            concepts: ["Box", "Option", "recursion"],
            source: """
            #[derive(Default)]
            struct Node {
                value: i32,
                left: Option<Box<Node>>,
                right: Option<Box<Node>>,
            }

            impl Node {
                fn new(value: i32) -> Self {
                    Node { value, left: None, right: None }
                }

                fn insert(&mut self, value: i32) {
                    let branch = if value < self.value {
                        &mut self.left
                    } else {
                        &mut self.right
                    };
                    match branch {
                        Some(node) => node.insert(value),
                        None => *branch = Some(Box::new(Node::new(value))),
                    }
                }

                fn in_order(&self, out: &mut Vec<i32>) {
                    if let Some(left) = &self.left {
                        left.in_order(out);
                    }
                    out.push(self.value);
                    if let Some(right) = &self.right {
                        right.in_order(out);
                    }
                }

                fn depth(&self) -> usize {
                    let left = self.left.as_ref().map_or(0, |n| n.depth());
                    let right = self.right.as_ref().map_or(0, |n| n.depth());
                    1 + left.max(right)
                }
            }

            fn main() {
                let mut root = Node::new(50);
                for value in [30, 70, 20, 40, 60, 80, 35, 45] {
                    root.insert(value);
                }

                let mut sorted = Vec::new();
                root.in_order(&mut sorted);
                println!("in order  {sorted:?}");
                println!("depth     {}", root.depth());
            }
            """
        ),
        single(
            id: "state-machine",
            title: "Traffic State Machine",
            detail: "Enums that make an invalid transition impossible",
            systemImage: "arrow.triangle.branch",
            category: .simulation,
            difficulty: .intermediate,
            concepts: ["enums", "match", "state"],
            source: """
            #[derive(Debug, Clone, Copy, PartialEq)]
            enum Light {
                Red,
                Green,
                Yellow,
            }

            impl Light {
                fn next(self) -> Light {
                    match self {
                        Light::Red => Light::Green,
                        Light::Green => Light::Yellow,
                        Light::Yellow => Light::Red,
                    }
                }

                fn seconds(self) -> u32 {
                    match self {
                        Light::Red => 30,
                        Light::Green => 25,
                        Light::Yellow => 5,
                    }
                }
            }

            fn main() {
                let mut light = Light::Red;
                let mut clock = 0;

                for _ in 0..6 {
                    println!("t={clock:>3}s  {:?} for {}s", light, light.seconds());
                    clock += light.seconds();
                    light = light.next();
                }
                println!("cycle returns to {:?}", light);
            }
            """
        ),
        single(
            id: "csv-report",
            title: "CSV Report",
            detail: "Parse embedded rows into structs and summarise",
            systemImage: "tablecells.badge.ellipsis",
            category: .data,
            difficulty: .intermediate,
            concepts: ["structs", "parsing", "Result"],
            source: """
            #[derive(Debug)]
            struct Sale {
                region: String,
                product: String,
                units: u32,
                unit_price: f64,
            }

            impl Sale {
                fn total(&self) -> f64 {
                    f64::from(self.units) * self.unit_price
                }
            }

            fn parse(line: &str) -> Option<Sale> {
                let mut fields = line.split(',');
                Some(Sale {
                    region: fields.next()?.trim().to_string(),
                    product: fields.next()?.trim().to_string(),
                    units: fields.next()?.trim().parse().ok()?,
                    unit_price: fields.next()?.trim().parse().ok()?,
                })
            }

            fn main() {
                let raw = "\\
            north, keyboard, 12, 49.99
            south, monitor, 4, 219.50
            north, mouse, 30, 19.95
            east, monitor, 7, 219.50
            south, keyboard, 9, 49.99";

                let sales: Vec<Sale> = raw.lines().filter_map(parse).collect();
                println!("{} rows parsed", sales.len());

                let mut regions: Vec<&str> = sales.iter().map(|s| s.region.as_str()).collect();
                regions.sort_unstable();
                regions.dedup();

                for region in regions {
                    let total: f64 = sales
                        .iter()
                        .filter(|s| s.region == region)
                        .map(Sale::total)
                        .sum();
                    println!("{region:<8} {total:>10.2}");
                }
            }
            """
        ),
        single(
            id: "tokenizer",
            title: "Expression Tokenizer",
            detail: "Turn arithmetic text into typed tokens",
            systemImage: "curlybraces.square.fill",
            category: .text,
            difficulty: .advanced,
            concepts: ["enums", "chars", "peekable"],
            source: """
            #[derive(Debug, PartialEq)]
            enum Token {
                Number(f64),
                Plus,
                Minus,
                Star,
                Slash,
                LeftParen,
                RightParen,
            }

            fn tokenize(input: &str) -> Result<Vec<Token>, String> {
                let mut tokens = Vec::new();
                let mut chars = input.chars().peekable();

                while let Some(&character) = chars.peek() {
                    match character {
                        ' ' => { chars.next(); }
                        '+' => { chars.next(); tokens.push(Token::Plus); }
                        '-' => { chars.next(); tokens.push(Token::Minus); }
                        '*' => { chars.next(); tokens.push(Token::Star); }
                        '/' => { chars.next(); tokens.push(Token::Slash); }
                        '(' => { chars.next(); tokens.push(Token::LeftParen); }
                        ')' => { chars.next(); tokens.push(Token::RightParen); }
                        digit if digit.is_ascii_digit() || digit == '.' => {
                            let mut number = String::new();
                            while let Some(&next) = chars.peek() {
                                if next.is_ascii_digit() || next == '.' {
                                    number.push(next);
                                    chars.next();
                                } else {
                                    break;
                                }
                            }
                            let value = number
                                .parse()
                                .map_err(|_| format!("bad number: {number}"))?;
                            tokens.push(Token::Number(value));
                        }
                        other => return Err(format!("unexpected character: {other}")),
                    }
                }
                Ok(tokens)
            }

            fn main() {
                for input in ["3 + 4 * (2 - 1)", "10 / 2.5", "1 + $"] {
                    match tokenize(input) {
                        Ok(tokens) => println!("{input:<18} -> {} tokens {:?}", tokens.len(), tokens),
                        Err(error) => println!("{input:<18} -> error: {error}"),
                    }
                }
            }
            """
        ),
        single(
            id: "generic-stack",
            title: "Generic Stack",
            detail: "One data structure, any type, with trait bounds",
            systemImage: "square.stack.3d.down.right.fill",
            category: .systems,
            difficulty: .advanced,
            concepts: ["generics", "traits", "Option"],
            source: """
            use std::fmt::Debug;

            struct Stack<T> {
                items: Vec<T>,
            }

            impl<T: Debug> Stack<T> {
                fn new() -> Self {
                    Stack { items: Vec::new() }
                }

                fn push(&mut self, item: T) {
                    self.items.push(item);
                }

                fn pop(&mut self) -> Option<T> {
                    self.items.pop()
                }

                fn peek(&self) -> Option<&T> {
                    self.items.last()
                }

                fn len(&self) -> usize {
                    self.items.len()
                }

                fn describe(&self, label: &str) {
                    println!("{label:<10} len={} top={:?}", self.len(), self.peek());
                }
            }

            fn main() {
                let mut numbers: Stack<i32> = Stack::new();
                for value in [3, 1, 4, 1, 5] {
                    numbers.push(value);
                }
                numbers.describe("numbers");

                let mut words: Stack<&str> = Stack::new();
                for word in ["rust", "is", "explicit"] {
                    words.push(word);
                }
                words.describe("words");

                while let Some(word) = words.pop() {
                    println!("popped {word}");
                }
                words.describe("drained");
            }
            """
        ),
        single(
            id: "iterator-pipeline",
            title: "Iterator Pipeline",
            detail: "One lazy chain from raw text to a ranked result",
            systemImage: "line.3.horizontal.decrease.circle.fill",
            category: .algorithms,
            difficulty: .intermediate,
            concepts: ["iterators", "closures", "sorting"],
            source: """
            fn main() {
                let log = "\\
            GET /index 200 12
            POST /login 401 48
            GET /assets 200 3
            GET /index 200 27
            POST /login 200 51
            GET /missing 404 8";

                let entries: Vec<(&str, u32, u32)> = log
                    .lines()
                    .filter_map(|line| {
                        let mut parts = line.split_whitespace();
                        let _method = parts.next()?;
                        let path = parts.next()?;
                        let status: u32 = parts.next()?.parse().ok()?;
                        let millis: u32 = parts.next()?.parse().ok()?;
                        Some((path, status, millis))
                    })
                    .collect();

                let ok = entries.iter().filter(|(_, status, _)| *status == 200).count();
                let slowest = entries.iter().max_by_key(|(_, _, millis)| *millis);
                let total: u32 = entries.iter().map(|(_, _, millis)| millis).sum();

                println!("requests   {}", entries.len());
                println!("succeeded  {ok}");
                println!("total time {total}ms");
                if let Some((path, status, millis)) = slowest {
                    println!("slowest    {path} ({status}) {millis}ms");
                }
            }
            """
        ),
        single(
            id: "error-pipeline",
            title: "Error Pipeline",
            detail: "A custom error type propagated with ?",
            systemImage: "exclamationmark.triangle.fill",
            category: .systems,
            difficulty: .advanced,
            concepts: ["Result", "From", "Display"],
            source: """
            use std::fmt;

            #[derive(Debug)]
            enum ConfigError {
                Missing(String),
                NotANumber { key: String, value: String },
                OutOfRange { key: String, value: u32 },
            }

            impl fmt::Display for ConfigError {
                fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
                    match self {
                        ConfigError::Missing(key) => write!(formatter, "missing key `{key}`"),
                        ConfigError::NotANumber { key, value } => {
                            write!(formatter, "`{key}` is not a number: {value}")
                        }
                        ConfigError::OutOfRange { key, value } => {
                            write!(formatter, "`{key}` is out of range: {value}")
                        }
                    }
                }
            }

            fn lookup<'a>(source: &'a str, key: &str) -> Result<&'a str, ConfigError> {
                source
                    .lines()
                    .find_map(|line| line.split_once('='))
                    .filter(|(name, _)| name.trim() == key)
                    .map(|(_, value)| value.trim())
                    .ok_or_else(|| ConfigError::Missing(key.to_string()))
            }

            fn port(source: &str) -> Result<u32, ConfigError> {
                let raw = lookup(source, "port")?;
                let value: u32 = raw.parse().map_err(|_| ConfigError::NotANumber {
                    key: "port".to_string(),
                    value: raw.to_string(),
                })?;
                if !(1..=65535).contains(&value) {
                    return Err(ConfigError::OutOfRange { key: "port".to_string(), value });
                }
                Ok(value)
            }

            fn main() {
                for source in ["port = 8080", "port = eighty", "port = 99999", "host = local"] {
                    match port(source) {
                        Ok(value) => println!("{source:<16} -> ok: {value}"),
                        Err(error) => println!("{source:<16} -> {error}"),
                    }
                }
            }
            """
        ),
        single(
            id: "guessing-oracle",
            title: "Guessing Oracle",
            detail: "Deterministic binary search plays its own game",
            systemImage: "questionmark.diamond.fill",
            category: .games,
            difficulty: .starter,
            concepts: ["Ordering", "loops", "binary search"],
            source: """
            use std::cmp::Ordering;

            fn main() {
                let secret = 73_u32;
                let (mut low, mut high) = (1_u32, 100_u32);
                let mut attempts = 0;

                loop {
                    let guess = low + (high - low) / 2;
                    attempts += 1;

                    match guess.cmp(&secret) {
                        Ordering::Equal => {
                            println!("guess {attempts:>2}: {guess} — correct");
                            break;
                        }
                        Ordering::Less => {
                            println!("guess {attempts:>2}: {guess} — too low");
                            low = guess + 1;
                        }
                        Ordering::Greater => {
                            println!("guess {attempts:>2}: {guess} — too high");
                            high = guess - 1;
                        }
                    }
                }

                println!("found in {attempts} guesses out of 100 possibilities");
            }
            """
        ),
    ]
}
