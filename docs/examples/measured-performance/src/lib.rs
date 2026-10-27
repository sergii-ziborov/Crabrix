pub fn count_owned(input: &str) -> usize {
    input.lines()
        .map(|line| line.trim().to_ascii_lowercase())
        .filter(|line| line.starts_with("warn:"))
        .count()
}

pub fn count_borrowed(input: &str) -> usize {
    input.lines()
        .filter(|line| {
            line.trim().as_bytes().get(..5)
                .is_some_and(|prefix| prefix.eq_ignore_ascii_case(b"warn:"))
        })
        .count()
}

pub fn fixture(lines: usize) -> String {
    let rows = [
        "info: startup\n",
        " WARN: cache miss \n",
        "\twArN: network slow\r\n",
        "warning: long label\n",
        "🙂 plain text\n",
        "warn\n",
        "\u{3000}WARN: ユニコード\u{3000}\n",
        "debug: done\n",
    ];
    let mut text = String::new();
    for index in 0..lines {
        text.push_str(rows[index % rows.len()]);
    }
    text
}

#[cfg(test)]
mod tests {
    use super::*;
    fn expect(input: &str, count: usize) {
        assert_eq!(count_owned(input), count);
        assert_eq!(count_borrowed(input), count);
    }
    #[test] fn empty_input() { expect("", 0); }
    #[test] fn mixed_case() { expect("warn:a\nWARN:b\nwArN:c\ninfo:d", 3); }
    #[test] fn exact_prefix() { expect("warn\nwarn:\nwarning:\nwarn :\nWArN:now", 2); }
    #[test] fn whitespace_and_crlf() { expect(" \tWARN: one\r\n\u{3000}warn: two\u{3000}\r\n", 2); }
    #[test] fn multibyte_prefixes() { expect("é\n🙂\nß\n警告:\nİwarn:\n\u{3000}WaRn: ü", 1); }
    #[test] fn blank_and_final_lines() { expect("\n \nwarn: final", 1); }
    #[test] fn complete_fixture() { expect(&fixture(24_000), 9_000); }
    #[test] fn deterministic_differential_cases() {
        let atoms = ["", "w", "W", "warn", "WARN:", "WaRn:payload", "info:", "🙂", " \t", "\r\n"];
        for a in atoms { for b in atoms { for c in atoms {
            let text = format!("{a}{b}{c}");
            assert_eq!(count_owned(&text), count_borrowed(&text), "{text:?}");
        } } }
    }
}
