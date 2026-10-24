use std::{future::Future, pin::Pin, sync::{Arc, atomic::{AtomicBool, Ordering}}, task::{Context, Poll, Wake, Waker}};

#[derive(Default)]
struct Notice(AtomicBool);
impl Wake for Notice {
    fn wake(self: Arc<Self>) { self.0.store(true, Ordering::Release); }
    fn wake_by_ref(self: &Arc<Self>) { self.0.store(true, Ordering::Release); }
}
#[derive(Debug, PartialEq)]
enum Turn<T> { Ready(T), Stalled, BudgetUsed }

// A bounded demonstration driver, not a runtime or an I/O event loop.
fn drive<F: Future>(mut future: Pin<&mut F>, polls: usize) -> Turn<F::Output> {
    let notice = Arc::new(Notice::default());
    let waker = Waker::from(notice.clone());
    let mut cx = Context::from_waker(&waker);
    for _ in 0..polls {
        notice.0.store(false, Ordering::Release);
        match future.as_mut().poll(&mut cx) {
            Poll::Ready(value) => return Turn::Ready(value),
            Poll::Pending if !notice.0.load(Ordering::Acquire) => return Turn::Stalled,
            Poll::Pending => {}
        }
    }
    Turn::BudgetUsed
}
struct Sum { next: u32, limit: u32, total: u64 }
impl Future for Sum {
    type Output = u64;
    fn poll(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<u64> {
        for _ in 0..128 {
            if self.next == self.limit { return Poll::Ready(self.total); }
            self.total += u64::from(self.next);
            self.next += 1;
        }
        if self.next == self.limit { Poll::Ready(self.total) }
        else { cx.waker().wake_by_ref(); Poll::Pending }
    }
}
fn main() {
    let mut sum = std::pin::pin!(Sum { next: 0, limit: 1_000, total: 0 });
    assert_eq!(drive(sum.as_mut(), 1), Turn::BudgetUsed);
    assert_eq!(drive(sum.as_mut(), 16), Turn::Ready(499_500));
    let mut pending = std::pin::pin!(std::future::pending::<()>());
    assert_eq!(drive(pending.as_mut(), 4), Turn::Stalled);
    println!("bounded turns: ok");
}
