//! macOS virtual keycodes and the key model crossing the FFI boundary.

pub const KC_RETURN: u16 = 36;
pub const KC_TAB: u16 = 48;
pub const KC_BACKSPACE: u16 = 51;
pub const KC_ESCAPE: u16 = 53;
pub const KC_ENTER: u16 = 76;
pub const KC_FORWARD_DELETE: u16 = 117;

/// Keys that move the caret: the current word is no longer under it.
pub fn is_nav_keycode(k: u16) -> bool {
    matches!(k, 115 | 116 | 119 | 121 | 123 | 124 | 125 | 126)
}

/// One keystroke as seen by the engine. `ch` is the character already
/// resolved by macOS for the active layout (case included).
#[derive(Debug, Clone, Copy)]
pub struct KeyInput {
    pub keycode: u16,
    pub ch: Option<char>,
    /// Any of Cmd/Ctrl/Opt held → shortcuts, never text.
    pub with_command: bool,
}
