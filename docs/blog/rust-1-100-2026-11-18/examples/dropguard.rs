use std::mem::DropGuard;
use std::num::ParseIntError;

#[derive(Debug, Default)]
struct Shelf {
    items: Vec<(String, u32)>,
    log: Vec<String>,
}

/// Stocks every `name:count` entry, or leaves `items` exactly as it was.
fn stock_all(shelf: &mut Shelf, batch: &[&str]) -> Result<usize, String> {
    let before = shelf.items.len();
    let mut shelf = DropGuard::new(shelf, move |shelf: &mut Shelf| {
        shelf.items.truncate(before);
        shelf.log.push(format!("rolled back to {before} items"));
    });

    for entry in batch {
        let Some((name, count)) = entry.split_once(':') else {
            return Err(format!("{entry:?} is not name:count")); // early return
        };
        let count: u32 = count.trim().parse().map_err(|e: ParseIntError| e.to_string())?; // `?`
        shelf.items.push((name.trim().to_string(), count)); // `DerefMut` reaches the shelf
    }

    let shelf = DropGuard::dismiss(shelf); // success: keep the changes
    shelf.log.push(format!("stocked {}", batch.len()));
    Ok(shelf.items.len())
}

fn main() {
    let mut shelf = Shelf::default();
    println!("{:?}", stock_all(&mut shelf, &["bolts:40", "nuts:25"]));
    println!("{:?}", stock_all(&mut shelf, &["washers:10", "rivets"]));
    println!("{:?}", stock_all(&mut shelf, &["springs:3", "pins:many"]));
    println!("items: {:?}", shelf.items);
    println!("log:   {:?}", shelf.log);
}
