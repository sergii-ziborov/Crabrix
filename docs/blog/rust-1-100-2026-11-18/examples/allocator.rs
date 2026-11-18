use std::alloc::{AllocError, Allocator, Layout, System};
use std::cell::Cell;
use std::ptr::NonNull;

/// Forwards to the system allocator and records what one workload asked for.
#[derive(Default)]
struct Meter {
    live: Cell<usize>,
    peak: Cell<usize>,
    calls: Cell<usize>,
}

unsafe impl Allocator for Meter {
    fn allocate(&self, layout: Layout) -> Result<NonNull<[u8]>, AllocError> {
        let block = System.allocate(layout)?;
        self.calls.set(self.calls.get() + 1);
        self.live.set(self.live.get() + layout.size());
        self.peak.set(self.peak.get().max(self.live.get()));
        Ok(block)
    }

    unsafe fn deallocate(&self, ptr: NonNull<u8>, layout: Layout) {
        self.live.set(self.live.get() - layout.size());
        unsafe { System.deallocate(ptr, layout) }
    }
}

fn main() {
    let meter = Meter::default();
    {
        // `&Meter` is an allocator too, so the collection borrows the meter.
        let mut ids = Vec::with_capacity_in(2, &meter);
        ids.extend(1..=100_u32);
        let label = Box::new_in(*b"report", &meter);
        println!("{} ids, label {:?}", ids.len(), std::str::from_utf8(&*label).unwrap());
    }
    println!(
        "calls {}, peak {} bytes, live after drop {} bytes",
        meter.calls.get(),
        meter.peak.get(),
        meter.live.get()
    );
}
