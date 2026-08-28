enum RustSamples {
    static let cargoManifest = """
    [package]
    name = "modules-lab"
    version = "0.1.0"
    edition = "2024"

    [dependencies]
    """

    static let runnable = """
    fn main() {
        let mut items = vec!["crab", "rust"];
        let first = &items[0];
        println!("{first}");
        items.push("compiler");
    }
    """

    static let broken = """
    fn main() {
        let mut items = vec!["crab", "rust"];
        let first = &items[0];
        items.push("compiler");
        println!("{first}");
    }
    """

    static let multiFileMain = """
    mod greeter;

    fn main() {
        println!("{}", greeter::message());
    }
    """

    static let multiFileGreeter = """
    pub fn message() -> &'static str {
        "hello from two Rust files"
    }
    """

    static let memoryPressure = """
    fn main() {
        let mut bytes = vec![0_u8; 80 * 1024 * 1024];
        for index in (0..bytes.len()).step_by(4096) {
            bytes[index] = (index % 251) as u8;
        }
        println!("{}", bytes[bytes.len() - 4096]);
    }
    """

    static let practice = """
    fn main() {
        let mut names = vec!["Ada", "Linus"];
        let first = &names[0];
        names.push("Ferris");
        println!("{first}");
    }
    """
}

/// How a library project is grouped and how hard it reads.
enum RustShowcaseCategory: String, CaseIterable, Identifiable, Sendable {
    case graphics
    case algorithms
    case data
    case text
    case simulation
    case systems
    case math
    case games

    var id: String { rawValue }

    var title: String {
        switch self {
        case .graphics: "Graphics"
        case .algorithms: "Algorithms"
        case .data: "Data"
        case .text: "Text"
        case .simulation: "Simulation"
        case .systems: "Systems"
        case .math: "Math"
        case .games: "Games"
        }
    }

    var systemImage: String {
        switch self {
        case .graphics: "paintpalette.fill"
        case .algorithms: "function"
        case .data: "tablecells.fill"
        case .text: "text.alignleft"
        case .simulation: "waveform.path.ecg"
        case .systems: "cpu.fill"
        case .math: "x.squareroot"
        case .games: "gamecontroller.fill"
        }
    }
}

enum RustShowcaseDifficulty: String, CaseIterable, Identifiable, Sendable {
    case starter
    case intermediate
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .starter: "Starter"
        case .intermediate: "Intermediate"
        case .advanced: "Advanced"
        }
    }

    var order: Int {
        switch self {
        case .starter: 0
        case .intermediate: 1
        case .advanced: 2
        }
    }
}

struct RustShowcaseProject: Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
    let category: RustShowcaseCategory
    let difficulty: RustShowcaseDifficulty
    let concepts: [String]
    let project: CrabrixProject

    /// Everything a search box should look at.
    var searchHaystack: String {
        ([title, detail, category.title, difficulty.title] + concepts)
            .joined(separator: " ")
            .lowercased()
    }
}

enum RustShowcaseLibrary {
    /// The four original showcases plus the wider catalogue.
    static let projects: [RustShowcaseProject] = featured + RustShowcaseCatalog.projects

    /// Shown first on the library screen.
    static let featured: [RustShowcaseProject] = [
        RustShowcaseProject(
            id: "ferris-pixel-art",
            title: "Ferris Pixel Art",
            detail: "Render a crab from strings and iterators",
            systemImage: "paintpalette.fill",
            category: .graphics,
            difficulty: .starter,
            concepts: ["arrays", "iterators", "stdout"],
            project: CrabrixProject(
                name: "ferris-pixel-art",
                files: [
                    "Cargo.toml": manifest(name: "ferris-pixel-art"),
                    "src/main.rs": """
                    fn main() {
                        let ferris = [
                            r"        _~^~^~_",
                            r"    \\) /  o o  \\ (/",
                            r"      '_   -   _'",
                            r"      / '-----' \\",
                            r"     /  /     \\  \\",
                            r"    /__/       \\__\\",
                        ];

                        println!("CRABRIX PIXEL LAB\\n");
                        ferris.iter().for_each(|line| println!("{line}"));
                        println!("\\n  fearless Rust, one line at a time");
                    }
                    """,
                ],
                entryFile: "src/main.rs",
                provenance: nil
            )
        ),
        RustShowcaseProject(
            id: "orbit-dashboard",
            title: "Orbit Dashboard",
            detail: "A terminal UI built from a local module",
            systemImage: "gauge.with.dots.needle.67percent",
            category: .graphics,
            difficulty: .intermediate,
            concepts: ["modules", "formatting", "functions"],
            project: CrabrixProject(
                name: "orbit-dashboard",
                files: [
                    "Cargo.toml": manifest(name: "orbit-dashboard"),
                    "src/main.rs": """
                    mod ui;

                    fn main() {
                        println!("╭──── CRABRIX ORBIT CONTROL ────╮");
                        for (name, value) in [("fuel", 82), ("signal", 67), ("oxygen", 94)] {
                            println!("│ {:<8} {} {:>3}% │", name, ui::bar(value), value);
                        }
                        println!("╰──────── all systems local ────╯");
                    }
                    """,
                    "src/ui.rs": """
                    pub fn bar(percent: usize) -> String {
                        let filled = percent / 10;
                        format!("{}{}", "■".repeat(filled), "·".repeat(10 - filled))
                    }
                    """,
                ],
                entryFile: "src/main.rs",
                provenance: nil
            )
        ),
        RustShowcaseProject(
            id: "constellation-generator",
            title: "Constellation Generator",
            detail: "Deterministic generative art with no network",
            systemImage: "sparkles",
            category: .graphics,
            difficulty: .intermediate,
            concepts: ["algorithms", "String", "loops"],
            project: CrabrixProject(
                name: "constellation-generator",
                files: [
                    "Cargo.toml": manifest(name: "constellation-generator"),
                    "src/main.rs": """
                    fn main() {
                        let (width, height) = (38_u32, 12_u32);
                        let mut seed = 0xC0FFEE_u32;
                        println!("CRABRIX NIGHT SKY");
                        for _ in 0..height {
                            let mut row = String::new();
                            for _ in 0..width {
                                seed = seed.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
                                row.push(match seed % 29 { 0 => '✦', 1..=3 => '·', _ => ' ' });
                            }
                            println!("│{row}│");
                        }
                    }
                    """,
                ],
                entryFile: "src/main.rs",
                provenance: nil
            )
        ),
        RustShowcaseProject(
            id: "word-lab",
            title: "Word Lab",
            detail: "Build a sorted frequency chart with std",
            systemImage: "chart.bar.xaxis",
            category: .data,
            difficulty: .starter,
            concepts: ["BTreeMap", "ownership", "collections"],
            project: CrabrixProject(
                name: "word-lab",
                files: [
                    "Cargo.toml": manifest(name: "word-lab"),
                    "src/main.rs": """
                    use std::collections::BTreeMap;

                    fn main() {
                        let phrase = "rust makes systems fearless rust makes ideas real";
                        let mut counts = BTreeMap::new();
                        for word in phrase.split_whitespace() {
                            *counts.entry(word).or_insert(0) += 1;
                        }
                        println!("WORD LAB");
                        for (word, count) in counts {
                            println!("{word:>9}  {}", "█".repeat(count));
                        }
                    }
                    """,
                ],
                entryFile: "src/main.rs",
                provenance: nil
            )
        ),
    ]

    private static func manifest(name: String) -> String {
        """
        [package]
        name = "\(name)"
        version = "0.1.0"
        edition = "2024"

        [dependencies]
        """
    }
}
