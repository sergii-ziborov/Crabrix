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
