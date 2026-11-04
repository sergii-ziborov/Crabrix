#[unsafe(no_mangle)]
pub extern "C" fn crabrix_is_even(value: u32) -> bool {
    value % 2 == 0
}
