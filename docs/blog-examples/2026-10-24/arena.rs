use std::sync::atomic::{AtomicU64, Ordering};
static NEXT_ARENA: AtomicU64 = AtomicU64::new(1);

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
struct Handle { arena: u64, index: usize, generation: u64 }
struct Slot<T> { generation: u64, value: Option<T> }
struct Arena<T> { identity: u64, slots: Vec<Slot<T>>, free: Vec<usize> }
impl<T> Arena<T> {
    fn new() -> Option<Self> {
        let identity = loop {
            let current = NEXT_ARENA.load(Ordering::Relaxed);
            let next = current.checked_add(1)?;
            if NEXT_ARENA.compare_exchange_weak(current, next,
                Ordering::Relaxed, Ordering::Relaxed).is_ok() { break current; }
        };
        Some(Self { identity, slots: Vec::new(), free: Vec::new() })
    }
    fn insert(&mut self, value: T) -> Handle {
        let index = if let Some(index) = self.free.pop() {
            self.slots[index].value = Some(value);
            index
        } else {
            let index = self.slots.len();
            self.slots.push(Slot { generation: 0, value: Some(value) });
            index
        };
        Handle { arena: self.identity, index, generation: self.slots[index].generation }
    }
    fn slot(&self, handle: Handle) -> Option<&Slot<T>> {
        if handle.arena != self.identity { return None; }
        self.slots.get(handle.index).filter(|slot| slot.generation == handle.generation)
    }
    fn get(&self, handle: Handle) -> Option<&T> { self.slot(handle)?.value.as_ref() }
    fn get_mut(&mut self, handle: Handle) -> Option<&mut T> {
        if handle.arena != self.identity { return None; }
        let slot = self.slots.get_mut(handle.index)?;
        if slot.generation != handle.generation { return None; }
        slot.value.as_mut()
    }
    fn remove(&mut self, handle: Handle) -> Option<T> {
        if handle.arena != self.identity { return None; }
        let slot = self.slots.get_mut(handle.index)?;
        if slot.generation != handle.generation { return None; }
        let value = slot.value.take()?;
        if let Some(next) = slot.generation.checked_add(1) {
            slot.generation = next;
            self.free.push(handle.index);
        } // An exhausted generation permanently retires this slot.
        Some(value)
    }
}
fn main() {
    let mut arena = Arena::new().unwrap();
    let old = arena.insert(String::from("draft"));
    assert_eq!(arena.remove(old).as_deref(), Some("draft"));
    let current = arena.insert(String::from("replacement"));
    assert_eq!(old.index, current.index);
    assert_ne!(old.generation, current.generation);
    assert!(arena.get(old).is_none());
    arena.get_mut(current).unwrap().push_str(" page");
    assert_eq!(arena.get(current).map(String::as_str), Some("replacement page"));
    let other: Arena<String> = Arena::new().unwrap();
    assert!(other.get(current).is_none());
    println!("stale handles rejected: ok");
}
#[test]
fn generation_exhaustion_retires_the_slot() {
    let mut arena = Arena::new().unwrap();
    let first = arena.insert("last occupant");
    arena.slots[first.index].generation = u64::MAX; // Test-only boundary fixture.
    let final_handle = Handle { generation: u64::MAX, ..first };
    assert_eq!(arena.remove(final_handle), Some("last occupant"));
    assert!(arena.remove(final_handle).is_none());
    let next = arena.insert("new slot");
    assert_ne!(next.index, final_handle.index);
    assert!(arena.get(final_handle).is_none());
}
#[test]
fn double_remove_does_not_duplicate_a_free_slot() {
    let mut arena = Arena::new().unwrap();
    let old = arena.insert(7);
    assert_eq!(arena.remove(old), Some(7));
    assert_eq!(arena.remove(old), None);
    let a = arena.insert(8);
    let b = arena.insert(9);
    assert_ne!(a.index, b.index);
    assert_eq!(arena.get(a), Some(&8));
    assert_eq!(arena.get(b), Some(&9));
}
