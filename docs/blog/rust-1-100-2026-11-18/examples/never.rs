use std::collections::HashMap;

trait Settings {
    type Error;
    fn get(&self, key: &str) -> Result<Option<String>, Self::Error>;
}

/// Settings already loaded into memory: reading them cannot fail.
struct Loaded(HashMap<String, String>);

impl Settings for Loaded {
    type Error = !;
    fn get(&self, key: &str) -> Result<Option<String>, !> {
        Ok(self.0.get(key).cloned())
    }
}

/// Settings read from text supplied by a user: a line can be malformed.
struct Text(String);

impl Settings for Text {
    type Error = String;
    fn get(&self, key: &str) -> Result<Option<String>, String> {
        for (number, line) in self.0.lines().enumerate() {
            let Some((name, value)) = line.split_once('=') else {
                return Err(format!("line {}: expected key=value", number + 1));
            };
            if name.trim() == key {
                return Ok(Some(value.trim().to_string()));
            }
        }
        Ok(None)
    }
}

fn theme<S: Settings>(settings: &S) -> Result<String, S::Error> {
    Ok(settings.get("theme")?.unwrap_or_else(|| "system".to_string()))
}

fn main() {
    let loaded = Loaded(HashMap::from([("theme".to_string(), "dark".to_string())]));
    // The error type is `!`, so this pattern is irrefutable: no unwrap, no dead branch.
    let Ok(current) = theme(&loaded);
    println!("loaded: {current}");

    let text = Text("font = mono\ntheme light".to_string());
    match theme(&text) {
        Ok(value) => println!("text: {value}"),
        Err(message) => println!("text error: {message}"),
    }
}
