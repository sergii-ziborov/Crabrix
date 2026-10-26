use tokio::{
    sync::mpsc,
    time::{timeout_at, Instant},
};

#[derive(Debug, PartialEq, Eq)]
pub enum SubmitError<T> {
    Deadline(T),
    Closed(T),
}

pub async fn submit_before<T>(
    sender: &mpsc::Sender<T>,
    job: T,
    deadline: Instant,
) -> Result<(), SubmitError<T>> {
    // Our admission policy rejects an already expired request.
    if Instant::now() >= deadline {
        return Err(SubmitError::Deadline(job));
    }

    let permit = match timeout_at(deadline, sender.reserve()).await {
        Err(_) => return Err(SubmitError::Deadline(job)),
        Ok(Err(_)) => return Err(SubmitError::Closed(job)),
        Ok(Ok(permit)) => permit,
    };

    // Capacity can become ready close to the deadline.
    if Instant::now() >= deadline {
        return Err(SubmitError::Deadline(job));
    }
    permit.send(job);
    Ok(())
}


use tokio::{task::JoinError, time::{timeout, Duration}};

pub async fn finish_or_abort() -> Result<Option<u32>, JoinError> {
    let mut task = tokio::spawn(async {
        tokio::time::sleep(Duration::from_secs(60)).await;
        42_u32
    });

    match timeout(Duration::from_secs(2), &mut task).await {
        Ok(result) => result.map(Some),
        Err(_) => {
            task.abort();
            match task.await {
                Err(error) if error.is_cancelled() => Ok(None),
                Err(error) => Err(error),
                Ok(value) => Ok(Some(value)), // completion won the race
            }
        }
    }
}


pub async fn observe_progress() -> u32 {
    let work = async {
        tokio::time::sleep(tokio::time::Duration::from_secs(1)).await;
        7_u32
    };
    tokio::pin!(work);
    let mut ticks = tokio::time::interval(
        tokio::time::Duration::from_millis(100),
    );
    loop {
        tokio::select! {
            value = &mut work => return value,
            _ = ticks.tick() => { /* refresh progress only */ }
        }
    }
}


#[cfg(test)]
mod tests {
    use super::*;
    use tokio::time::Duration;

    #[tokio::test(start_paused = true)]
    async fn full_queue_returns_the_unaccepted_job() {
        let (sender, mut receiver) = mpsc::channel(1);
        sender.try_send(String::from("first")).unwrap();
        let result = submit_before(
            &sender,
            String::from("second"),
            Instant::now() + Duration::from_secs(3),
        ).await;
        assert_eq!(result, Err(SubmitError::Deadline("second".into())));
        assert_eq!(receiver.recv().await.as_deref(), Some("first"));
        assert!(matches!(
            receiver.try_recv(),
            Err(mpsc::error::TryRecvError::Empty)
        ));
    }
}
