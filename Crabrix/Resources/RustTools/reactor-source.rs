//! WASI reactor exposing rustfmt to `@scalar/rust-fmt`.
//!
//! The module is instantiated once and `run` is called per format, so source,
//! configuration and result cross through the preopened `/work` directory
//! rather than through linear memory. `/work` is the shim's in-memory
//! filesystem on the JavaScript side, so nothing here touches a real disk.
//!
//! Configuration arrives as `key=value` lines and is applied with rustfmt's own
//! `Config::override_value`, which is the same code path as `rustfmt --config
//! key=value`. So the option names, the value grammar and the defaults are all
//! rustfmt's, and there is no second copy of them on this side to fall out of
//! step with the tool's.
//!
//! Note that rustfmt's `load_config` is deliberately *not* used: every path
//! through it reaches `fs::canonicalize`, which Rust's standard library does
//! not implement on `wasm32-wasip1` at all, so a `rustfmt.toml` on the
//! JavaScript side could never be read this way.

use std::fs;

use rustfmt_nightly::{Config, Edition, EmitMode, Input, Session, StyleEdition, Verbosity, Version};

const INPUT: &str = "/work/input.rs";
const CONFIG: &str = "/work/config";
const OUTPUT: &str = "/work/output.rs";

/// Formatting succeeded and `/work/output.rs` holds the result.
const STATUS_OK: i32 = 0;
/// `/work/input.rs` was missing or was not valid UTF-8.
const STATUS_NO_INPUT: i32 = 1;
/// A configuration key or value was not one rustfmt accepts.
const STATUS_BAD_CONFIG: i32 = 2;
/// The source did not parse, or rustfmt reported an operational error.
const STATUS_FORMAT_FAILED: i32 = 3;
/// Formatting reported success but nothing could be written back.
const STATUS_NO_OUTPUT: i32 = 4;

/// Formats `/work/input.rs` into `/work/output.rs`, returning one of the
/// statuses above. Diagnostics go to stderr, which the JavaScript side collects
/// and turns into the thrown error's message.
#[unsafe(no_mangle)]
pub extern "C" fn run() -> i32 {
    let Ok(source) = fs::read_to_string(INPUT) else {
        eprintln!("rust_fmt: no source at {INPUT}");
        return STATUS_NO_INPUT;
    };

    let overrides = match read_overrides() {
        Ok(overrides) => overrides,
        Err(message) => {
            eprintln!("rust_fmt: {message}");
            return STATUS_BAD_CONFIG;
        }
    };

    let mut config = match build_config(&overrides) {
        Ok(config) => config,
        Err(message) => {
            eprintln!("rust_fmt: {message}");
            return STATUS_BAD_CONFIG;
        }
    };

    // Emit the formatted text to the session's writer, and keep rustfmt from
    // narrating on the way - stderr is reserved for real diagnostics.
    config.set().emit_mode(EmitMode::Stdout);
    config.set().verbose(Verbosity::Quiet);

    let mut formatted = Vec::new();
    let mut session = Session::new(config, Some(&mut formatted));

    let format_failed = match session.format(Input::Text(source)) {
        Ok(_report) => {
            // A returned report is not by itself success: rustfmt collects
            // parse errors into the session rather than failing the call, which
            // is how rustfmt itself decides its exit code.
            session.has_operational_errors() || session.has_parsing_errors()
        }
        Err(error) => {
            eprintln!("rust_fmt: {error}");
            true
        }
    };

    // The session borrows `formatted` until it is dropped, and the emitter only
    // finishes writing when it goes.
    drop(session);

    if format_failed {
        return STATUS_FORMAT_FAILED;
    }

    if let Err(error) = fs::write(OUTPUT, &formatted) {
        eprintln!("rust_fmt: could not write {OUTPUT}: {error}");
        return STATUS_NO_OUTPUT;
    }

    STATUS_OK
}

/// Reads `/work/config` as `key=value` lines.
///
/// An absent file means "no overrides", which is the common case - it is not an
/// error. Values keep everything after the first `=`, since a few rustfmt
/// options take values that contain one.
fn read_overrides() -> Result<Vec<(String, String)>, String> {
    let Ok(contents) = fs::read_to_string(CONFIG) else {
        return Ok(Vec::new());
    };

    contents
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .map(|line| {
            let (key, value) = line
                .split_once('=')
                .ok_or_else(|| format!("malformed config line, expected key=value: {line}"))?;
            Ok((key.trim().to_owned(), value.trim().to_owned()))
        })
        .collect()
}

/// Builds a `Config` from the overrides.
///
/// `style_edition`, `edition` and `version` are pulled out first because they
/// decide which set of defaults every *other* option starts from, per RFC 3338.
/// This mirrors what rustfmt's own CLI does with `--config`.
fn build_config(overrides: &[(String, String)]) -> Result<Config, String> {
    let lookup = |name: &str| {
        overrides
            .iter()
            .find(|(key, _)| key == name)
            .map(|(_, value)| value.as_str())
    };

    let style_edition: Option<StyleEdition> = parse("style_edition", lookup("style_edition"))?;
    let edition: Option<Edition> = parse("edition", lookup("edition"))?;
    let version: Option<Version> = parse("version", lookup("version"))?;

    let mut config = Config::default_for_possible_style_edition(style_edition, edition, version);

    for (key, value) in overrides {
        // `override_value` panics on an unknown key or an unparseable value,
        // and a panic here is a trapped instance rather than a caught error, so
        // everything is checked against rustfmt's own validator first.
        if !Config::is_valid_key_val(key, value) {
            return Err(format!("invalid config: {key}={value}"));
        }
        config.override_value(key, value);
    }

    Ok(config)
}

/// Parses one of the three options that select a default set, naming the option
/// in the error rather than letting a bare parse failure through.
fn parse<T: std::str::FromStr>(name: &str, raw: Option<&str>) -> Result<Option<T>, String> {
    raw.map(|value| {
        value
            .parse()
            .map_err(|_| format!("invalid value for {name}: {value}"))
    })
    .transpose()
}
