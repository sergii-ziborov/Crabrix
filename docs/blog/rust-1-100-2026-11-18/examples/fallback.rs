fn load<T: Default>() -> Result<T, String> {
    Ok(T::default())
}

fn run() -> Result<(), String> {
    load()?; // `T` is never named, so it comes from never-type fallback
    Ok(())
}

fn main() {
    run().unwrap();
    println!("ran");
}
