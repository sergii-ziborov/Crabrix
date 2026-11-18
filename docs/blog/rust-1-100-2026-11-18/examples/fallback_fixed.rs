fn load<T: Default>() -> Result<T, String> {
    Ok(T::default())
}

fn run() -> Result<(), String> {
    // Before: `load()?;` and `T` came from never-type fallback.
    // Rust 1.99: denied by the `dependency_on_unit_never_type_fallback` lint.
    // Rust 1.100: error[E0277]: the trait bound `!: Default` is not satisfied.
    load::<()>()?; // name the value you are discarding
    Ok(())
}

fn main() {
    run().unwrap();
    println!("ran");
}
