mod readings;

fn main() {
    println!("readings lab ready 🦀");

    let normal = readings::analyze("normal", &[" 42 ", "-17", "+3", "0"]);
    assert_eq!(normal.label, "normal");
    assert_eq!(normal.accepted, vec![42, -17, 3, 0]);
    assert_eq!(normal.rejected, Vec::<usize>::new());

    let mixed = readings::analyze(
        "mixed",
        &["", "   ", "bad", "2147483648", "-2147483649", " 7 ", "\t-2\n"],
    );
    assert_eq!(mixed.accepted, vec![7, -2]);
    assert_eq!(mixed.rejected, vec![1, 2, 3, 4, 5]);

    let limits = readings::analyze("limits", &["-2147483648", "2147483647"]);
    assert_eq!(limits.accepted, vec![i32::MIN, i32::MAX]);
    assert_eq!(limits.rejected, Vec::<usize>::new());

    let empty = readings::analyze("", &[]);
    assert_eq!(empty.label, "");
    assert_eq!(empty.accepted, Vec::<i32>::new());
    assert_eq!(empty.rejected, Vec::<usize>::new());

    let unicode = {
        let label = String::from("Дані 東京 🦀");
        readings::analyze(&label, &["\u{2003}8\u{2003}"])
    };
    assert_eq!(unicode.label, "Дані 東京 🦀");
    assert_eq!(unicode.accepted, vec![8]);
    assert_eq!(unicode.rejected, Vec::<usize>::new());

    println!("two-agent-checks=passed 🦀");
}
