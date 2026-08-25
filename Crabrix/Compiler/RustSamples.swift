enum RustSamples {
    static let broken = """
    fn main() {
        let mut items = vec!["crab", "rust"];
        let first = &items[0];
        items.push("compiler");
        println!("{first}");
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
