
#[derive(Debug, PartialEq)]
pub struct Report {
    pub label: String,
    pub accepted: Vec<i32>,
    pub rejected: Vec<usize>,
}

pub fn analyze(label: &str, inputs: &[&str]) -> Report {
    let mut report = Report {
        label: label.to_owned(),
        accepted: Vec::new(),
        rejected: Vec::new(),
    };

    for (index, input) in inputs.iter().enumerate() {
        match input.trim().parse::<i32>() {
            Ok(value) => report.accepted.push(value),
            Err(_) => report.rejected.push(index + 1),
        }
    }

    report
}
