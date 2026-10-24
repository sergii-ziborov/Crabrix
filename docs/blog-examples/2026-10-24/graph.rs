use std::collections::{BTreeMap, BTreeSet};
type Graph<'a> = BTreeMap<&'a str, BTreeSet<&'a str>>;
#[derive(Debug, PartialEq)]
enum PlanError<'a> {
    Unknown { package: &'a str, dependency: &'a str },
    Cycle { blocked: Vec<&'a str>, witness: Vec<&'a str> },
}
fn plan<'a>(graph: &Graph<'a>) -> Result<Vec<&'a str>, PlanError<'a>> {
    let mut remaining_count = BTreeMap::new();
    let mut consumers: BTreeMap<&str, Vec<&str>> = BTreeMap::new();
    for (&package, dependencies) in graph {
        remaining_count.insert(package, dependencies.len());
        for &dependency in dependencies {
            if !graph.contains_key(dependency) {
                return Err(PlanError::Unknown { package, dependency });
            }
            consumers.entry(dependency).or_default().push(package);
        }
    }
    let mut ready: BTreeSet<&str> = remaining_count.iter()
        .filter_map(|(&name, &count)| (count == 0).then_some(name)).collect();
    let mut order = Vec::new();
    while let Some(package) = ready.pop_first() {
        order.push(package);
        for &consumer in consumers.get(package).into_iter().flatten() {
            let count = remaining_count.get_mut(consumer).unwrap();
            *count -= 1;
            if *count == 0 { ready.insert(consumer); }
        }
    }
    if order.len() == graph.len() { return Ok(order); }
    let blocked: BTreeSet<&str> = remaining_count.iter()
        .filter_map(|(&name, &count)| (count > 0).then_some(name)).collect();
    let mut positions = BTreeMap::new();
    let mut walk = Vec::new();
    let mut current = *blocked.first().unwrap();
    let witness = loop {
        if let Some(&start) = positions.get(current) {
            let mut cycle = walk[start..].to_vec();
            cycle.push(current);
            break cycle;
        }
        positions.insert(current, walk.len());
        walk.push(current);
        current = graph[current].iter().copied()
            .find(|name| blocked.contains(*name)).unwrap();
    };
    Err(PlanError::Cycle { blocked: blocked.into_iter().collect(), witness })
}
fn graph<'a>(rows: &[(&'a str, &[&'a str])]) -> Graph<'a> {
    rows.iter().map(|(name, dependencies)|
        (*name, dependencies.iter().copied().collect())).collect()
}
fn main() {
    let inputs = graph(&[("web", &["core"]), ("cli", &["core"]),
        ("core", &["config"]), ("config", &[])]);
    assert_eq!(plan(&inputs), Ok(vec!["config", "core", "cli", "web"]));
    let cyclic = graph(&[("a", &["b"]), ("b", &["a"]), ("c", &["a"])]);
    assert_eq!(plan(&cyclic), Err(PlanError::Cycle {
        blocked: vec!["a", "b", "c"], witness: vec!["a", "b", "a"] }));
    println!("deterministic plan and cycle witness: ok");
}
#[test]
fn unknown_dependency_is_not_treated_as_a_leaf() {
    assert_eq!(plan(&graph(&[("app", &["missing"])])),
        Err(PlanError::Unknown { package: "app", dependency: "missing" }));
}
#[test]
fn empty_and_duplicate_edge_inputs_have_defined_results() {
    assert_eq!(plan(&Graph::new()), Ok(vec![]));
    assert_eq!(plan(&graph(&[("app", &["core", "core"]), ("core", &[])])),
        Ok(vec!["core", "app"]));
}
