use std::path::Path;

fn main() {
    // Like `strip_prefix`, but returns the input unchanged when the prefix is absent.
    for line in ["v1.100.0", "1.99.1"] {
        println!("{line} -> {}", line.trim_prefix('v'));
    }

    let file = Path::new("crates/report/src/lib.rs");
    println!("{}", file.trim_prefix("crates").display());

    // Build a vector from its index without a separate push loop.
    let squares = Vec::from_fn(5, |i| i * i);
    println!("{squares:?}");

    let mut dark = false;
    dark.toggle();
    println!("dark mode: {dark}");

    // Map the boxed value; the standard library reuses the allocation when possible.
    let celsius = Box::new(21.5_f64);
    let fahrenheit = Box::map(celsius, |c| c * 9.0 / 5.0 + 32.0);
    println!("{fahrenheit}");
}
