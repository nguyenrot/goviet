//! goviet-engine: pure Vietnamese input engine (no macOS dependencies).
//!
//! Keystrokes go in, edit operations come out. The macOS shell decides how
//! to inject the edits into the focused app.

pub mod autocaps;
pub mod compose;
pub mod config;
pub mod engine;
pub mod keys;
pub mod macros;
pub mod method;
pub mod syllable;
pub mod tone;
pub mod validation;

pub use config::{Config, Method, ToneStyle};
pub use engine::{Action, Engine};
pub use keys::KeyInput;
pub use macros::MacroTable;

/// Parse a config JSON string (the Swift side mirrors this shape).
pub fn config_from_json(s: &str) -> Option<Config> {
    serde_json::from_str(s).ok()
}
