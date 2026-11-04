#[derive(Debug, PartialEq)]
struct Report {
    label: String,
    accepted: Vec<i32>,
    rejected: Vec<usize>,
}
fn analyze(label: &str, inputs: &[&str]) -> Report {
    let mut report = Report {
        label: label.to_owned(),
        accepted: Vec::new(),
        rejected: Vec::new(),
    };
    for (index, input) in inputs.iter().enumerate() {
        match input.trim().parse::<i32>() {
            Ok(n) => report.accepted.push(n),
            Err(_) => report.rejected.push(index + 1),
        }
    }
    report
}
fn main() {
    let report = analyze("lab 🦀", &["4", " -2 ", "bad", "2147483648"]);
    assert_eq!(report.accepted, [4, -2]);
    assert_eq!(report.rejected, [3, 4]);
    assert_eq!(report.label, "lab 🦀");
    println!("{report:?}");
    println!("agent lab: all checks passed");
}
