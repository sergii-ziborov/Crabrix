use kameo::prelude::*;
use std::time::Duration;

#[derive(Actor, Default)]
struct Ledger {
    count: u64,
    total: u64,
}

struct Record(u64);
struct Snapshot;

impl Message<Record> for Ledger {
    type Reply = u64;

    async fn handle(&mut self, message: Record, _: &mut Context<Self, Self::Reply>) -> Self::Reply {
        self.count += 1;
        self.total = self.total.checked_add(message.0).expect("bounded input");
        self.count
    }
}

impl Message<Snapshot> for Ledger {
    type Reply = (u64, u64);

    async fn handle(&mut self, _: Snapshot, _: &mut Context<Self, Self::Reply>) -> Self::Reply {
        (self.count, self.total)
    }
}

fn main() {
    tokio::runtime::Builder::new_current_thread()
        .enable_time()
        .build()
        .expect("local runtime")
        .block_on(async {
            let mut workers = tokio::task::JoinSet::new();
            for worker in 0..16_u64 {
                workers.spawn(async move {
                    let actor = Ledger::spawn(Ledger::default());
                    for sequence in 0..64_u64 {
                        let count = actor.ask(Record(worker * 64 + sequence)).await.expect("record");
                        assert_eq!(count, sequence + 1);
                        if sequence % 16 == 0 {
                            tokio::task::yield_now().await;
                        }
                    }
                    let snapshot = actor.ask(Snapshot).await.expect("snapshot");
                    actor.stop_gracefully().await.expect("stop actor");
                    actor.wait_for_shutdown().await;
                    snapshot
                });
            }
            let aggregate = tokio::time::timeout(Duration::from_secs(5), async {
                let mut count = 0;
                let mut total = 0;
                while let Some(result) = workers.join_next().await {
                    let (worker_count, worker_total) = result.expect("worker task");
                    count += worker_count;
                    total += worker_total;
                }
                (count, total)
            })
            .await
            .expect("workers finish within the guest deadline");
            assert_eq!(aggregate, (1024, 523_776));
            println!("kameo offline: actors=16 records=1024 sum=523776");
        });
}
