use crabrix_proc_macro_identity::keep;

keep! {
    fn answer() -> u32 { 42 }
}

fn main() {
    assert_eq!(answer(), 42);
    println!("macro identity: {}", answer());
}
