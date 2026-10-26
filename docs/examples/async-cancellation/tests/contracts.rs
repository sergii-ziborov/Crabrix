use cancellation_boundaries::{SubmitError, submit_before, finish_or_abort, observe_progress};
use tokio::{sync::{mpsc, oneshot}, time::{Duration, Instant}};

#[tokio::test(start_paused = true)]
async fn expired_deadline_does_not_consume_spare_capacity() {
    let (sender, mut receiver) = mpsc::channel(1);
    let result = submit_before(&sender, 9, Instant::now()).await;
    assert_eq!(result, Err(SubmitError::Deadline(9)));
    assert!(matches!(receiver.try_recv(), Err(mpsc::error::TryRecvError::Empty)));
    assert_eq!(sender.capacity(), 1);
}

#[tokio::test(start_paused = true)]
async fn closed_receiver_returns_original_payload() {
    let (sender, receiver) = mpsc::channel(1);
    drop(receiver);
    let result = submit_before(&sender, String::from("keep me"), Instant::now() + Duration::from_secs(1)).await;
    assert_eq!(result, Err(SubmitError::Closed("keep me".into())));
}

#[tokio::test(start_paused = true)]
async fn spare_capacity_accepts_one_job() {
    let (sender, mut receiver) = mpsc::channel(1);
    assert_eq!(submit_before(&sender, 11, Instant::now() + Duration::from_secs(1)).await, Ok(()));
    assert_eq!(receiver.recv().await, Some(11));
    assert!(matches!(receiver.try_recv(), Err(mpsc::error::TryRecvError::Empty)));
}

#[tokio::test(start_paused = true)]
async fn released_capacity_preserves_both_jobs_in_order() {
    let (sender, mut receiver) = mpsc::channel(1);
    sender.try_send(1).unwrap();
    let deadline = Instant::now() + Duration::from_secs(3);
    let (result, first) = tokio::join!(
        submit_before(&sender, 2, deadline),
        async { tokio::task::yield_now().await; receiver.recv().await },
    );
    assert_eq!(first, Some(1));
    assert_eq!(result, Ok(()));
    assert_eq!(receiver.recv().await, Some(2));
}

#[tokio::test(start_paused = true)]
async fn timed_out_task_is_aborted_and_joined() {
    assert_eq!(finish_or_abort().await.unwrap(), None);
}

#[tokio::test(start_paused = true)]
async fn progress_ticks_do_not_restart_the_work() {
    let start = Instant::now();
    assert_eq!(observe_progress().await, 7);
    assert_eq!(Instant::now() - start, Duration::from_secs(1));
}

#[tokio::test]
async fn dropping_a_handle_leaves_its_task_running() {
    let (started_tx, started_rx) = oneshot::channel();
    let (release_tx, release_rx) = oneshot::channel();
    let (done_tx, done_rx) = oneshot::channel();
    let task = tokio::spawn(async move {
        started_tx.send(()).unwrap();
        release_rx.await.unwrap();
        done_tx.send(42).unwrap();
    });
    started_rx.await.unwrap();
    drop(task);
    release_tx.send(()).unwrap();
    assert_eq!(done_rx.await.unwrap(), 42);
}
