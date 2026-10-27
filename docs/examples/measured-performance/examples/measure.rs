use measured_performance::{count_owned, count_borrowed, fixture};
use std::{hint::black_box, time::Instant};

const SCANS: usize = 32;
const SAMPLES: usize = 21;

#[inline(never)]
fn batch(function: fn(&str) -> usize, input: &str) -> u128 {
    let start = Instant::now();
    for _ in 0..SCANS {
        black_box(function(black_box(input)));
    }
    start.elapsed().as_nanos()
}

fn main() {
    let input = fixture(24_000);
    assert_eq!(count_owned(&input), 9_000);
    assert_eq!(count_borrowed(&input), 9_000);
    for _ in 0..8 {
        black_box(count_owned(black_box(&input)));
        black_box(count_borrowed(black_box(&input)));
    }
    let mut owned = Vec::with_capacity(SAMPLES);
    let mut borrowed = Vec::with_capacity(SAMPLES);
    for sample in 0..SAMPLES {
        let (a, b) = if sample % 2 == 0 {
            let a = batch(count_owned, &input);
            let b = batch(count_borrowed, &input);
            (a, b)
        } else {
            let b = batch(count_borrowed, &input);
            let a = batch(count_owned, &input);
            (a, b)
        };
        owned.push(a);
        borrowed.push(b);
    }
    eprintln!("fixture_bytes={}, lines=24000, warnings=9000, scans_per_batch={SCANS}, samples={SAMPLES}, debug_assertions={}", input.len(), cfg!(debug_assertions));
    println!("variant,sample,scans,total_ns");
    for sample in 0..SAMPLES {
        println!("owned,{sample},{SCANS},{}", owned[sample]);
        println!("borrowed,{sample},{SCANS},{}", borrowed[sample]);
    }
}
