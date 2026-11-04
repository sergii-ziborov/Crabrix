#[derive(Debug, PartialEq)]
struct Batch {
    name: String,
    readings: Vec<i32>,
    negative_count: usize,
}
fn make_batch(label: &str, readings: &[i32]) -> Batch {
    Batch {
        name: label.to_owned(),
        readings: readings.to_vec(),
        negative_count: readings.iter().filter(|&&n| n < 0).count(),
    }
}
fn main() {
    let batch = make_batch("lab 🦀", &[4, -2, 9]);
    assert_eq!(batch.name, "lab 🦀");
    assert_eq!(batch.readings, [4, -2, 9]);
    assert_eq!(batch.negative_count, 1);
    let empty = make_batch("", &[]);
    assert_eq!(empty.readings.len(), 0);
    assert_eq!(empty.negative_count, 0);
    println!("{batch:?}");
    println!("debug fixture: all checks passed");
}
