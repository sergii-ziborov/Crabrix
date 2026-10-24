use std::collections::BTreeMap;
#[derive(Clone, Debug, PartialEq)]
struct Attempt { lesson: String, passed: bool, points: u64 }
#[derive(Default)]
struct Ledger { attempts: BTreeMap<String, Attempt>, score: u64 }
#[derive(Debug, PartialEq)]
enum Record { Added, Duplicate }
#[derive(Debug, PartialEq)]
enum Error { Invalid, Conflict, Full, Overflow }
impl Ledger {
    fn record(&mut self, id: &str, attempt: Attempt) -> Result<Record, Error> {
        if id.is_empty() || id.len() > 128 || attempt.lesson.is_empty()
            || attempt.lesson.len() > 256 || attempt.points > 100
            || (!attempt.passed && attempt.points != 0) { return Err(Error::Invalid); }
        if let Some(previous) = self.attempts.get(id) {
            return if previous == &attempt { Ok(Record::Duplicate) }
                else { Err(Error::Conflict) };
        }
        if self.attempts.len() >= 50_000 { return Err(Error::Full); }
        let next_score = self.score.checked_add(attempt.points).ok_or(Error::Overflow)?;
        self.attempts.insert(id.to_owned(), attempt);
        self.score = next_score;
        Ok(Record::Added)
    }
}
fn main() {
    let mut ledger = Ledger::default();
    let a = Attempt { lesson: "ownership-1".into(), passed: true, points: 20 };
    assert_eq!(ledger.record("attempt-1", a.clone()), Ok(Record::Added));
    assert_eq!(ledger.record("attempt-1", a), Ok(Record::Duplicate));
    assert_eq!(ledger.score, 20);
    let conflict = Attempt { lesson: "ownership-1".into(), passed: true, points: 30 };
    assert_eq!(ledger.record("attempt-1", conflict), Err(Error::Conflict));
    assert_eq!(ledger.score, 20);
    println!("one attempt, one award: ok");
}
