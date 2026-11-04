fn square_sum(values: &[i32]) -> Option<i64> {
    values.iter().try_fold(0_i64, |sum, &value| {
        let wide = i64::from(value);
        sum.checked_add(wide.checked_mul(wide)?)
    })
}
fn main() {
    assert_eq!(square_sum(&[]), Some(0));
    assert_eq!(square_sum(&[-3, 0, 4]), Some(25));
    assert_eq!(square_sum(&[i32::MIN]), Some(4_611_686_018_427_387_904));
    assert_eq!(square_sum(&[i32::MIN, i32::MIN]), None);
    println!("CPU reference: all checks passed");
}
