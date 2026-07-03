//! C ABI for the GõViệt engine. All state lives behind one mutex; results
//! return by value so the hot path never allocates across the boundary.

use std::ffi::CStr;
use std::os::raw::c_char;
use std::sync::{Mutex, OnceLock};

use goviet_engine::{Action, Config, Engine, KeyInput, MacroTable};

pub const TEXT_CAP: usize = 256;

pub const VK_ACTION_PASS: u8 = 0;
pub const VK_ACTION_REPLACE: u8 = 1;
pub const VK_ACTION_REPLACE_LARGE: u8 = 3;

/// Result of processing one keystroke.
#[repr(C)]
pub struct VkResult {
    /// 0 = pass through, 1 = replace, 3 = replace with large text
    /// (fetch via vk_copy_pending_text).
    pub action: u8,
    /// Re-post the original key event after injecting (macro expansion).
    pub forward: u8,
    /// Number of characters to delete before inserting.
    pub backspaces: u16,
    /// UTF-16 code units used in `text`.
    pub text_len: u16,
    pub text: [u16; TEXT_CAP],
}

impl VkResult {
    fn pass() -> Self {
        VkResult { action: VK_ACTION_PASS, forward: 0, backspaces: 0, text_len: 0, text: [0; TEXT_CAP] }
    }
}

struct State {
    engine: Engine,
    pending: Vec<u16>,
}

fn state() -> &'static Mutex<State> {
    static STATE: OnceLock<Mutex<State>> = OnceLock::new();
    STATE.get_or_init(|| Mutex::new(State { engine: Engine::new(), pending: Vec::new() }))
}

fn lock() -> std::sync::MutexGuard<'static, State> {
    state().lock().unwrap_or_else(|poisoned| poisoned.into_inner())
}

/// # Safety
/// None required; initializes global state.
#[no_mangle]
pub extern "C" fn vk_init() {
    let _ = state();
}

/// # Safety
/// `json` must be a valid NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn vk_set_config_json(json: *const c_char) {
    if json.is_null() {
        return;
    }
    let Ok(s) = CStr::from_ptr(json).to_str() else { return };
    if let Ok(cfg) = serde_json_config(s) {
        lock().engine.set_config(cfg);
    }
}

fn serde_json_config(s: &str) -> Result<Config, ()> {
    goviet_engine::config_from_json(s).ok_or(())
}

/// # Safety
/// `json` must be a valid NUL-terminated UTF-8 string holding an object of
/// {"trigger": "expansion", ...}.
#[no_mangle]
pub unsafe extern "C" fn vk_set_macros_json(json: *const c_char) {
    if json.is_null() {
        return;
    }
    let Ok(s) = CStr::from_ptr(json).to_str() else { return };
    lock().engine.set_macros(MacroTable::from_json(s));
}

/// Fast path used by the toggle hotkey.
#[no_mangle]
pub extern "C" fn vk_set_enabled(enabled: u8) {
    let mut st = lock();
    let mut cfg = st.engine.config().clone();
    cfg.enabled = enabled != 0;
    st.engine.set_config(cfg);
}

/// flags: bit0 = any of Cmd/Ctrl/Opt held.
#[no_mangle]
pub extern "C" fn vk_process_key(keycode: u16, ch: u32, flags: u8) -> VkResult {
    let mut st = lock();
    let input = KeyInput {
        keycode,
        ch: char::from_u32(ch).filter(|c| *c != '\0'),
        with_command: flags & 1 != 0,
    };
    match st.engine.process_key(input) {
        Action::PassThrough => VkResult::pass(),
        Action::Replace { backspaces, text, forward } => {
            let units: Vec<u16> = text.encode_utf16().collect();
            let mut r = VkResult::pass();
            r.forward = u8::from(forward);
            r.backspaces = backspaces.min(u16::MAX as usize) as u16;
            if units.len() <= TEXT_CAP {
                r.action = VK_ACTION_REPLACE;
                r.text_len = units.len() as u16;
                r.text[..units.len()].copy_from_slice(&units);
            } else {
                r.action = VK_ACTION_REPLACE_LARGE;
                r.text_len = units.len().min(u16::MAX as usize) as u16;
                st.pending = units;
            }
            r
        }
    }
}

/// Copy the pending large text (action == 3) into `buf`; returns units copied.
/// # Safety
/// `buf` must point to at least `cap` writable u16s.
#[no_mangle]
pub unsafe extern "C" fn vk_copy_pending_text(buf: *mut u16, cap: usize) -> usize {
    if buf.is_null() {
        return 0;
    }
    let mut st = lock();
    let n = st.pending.len().min(cap);
    std::ptr::copy_nonoverlapping(st.pending.as_ptr(), buf, n);
    st.pending.clear();
    n
}

/// Caret moved (mouse click / app switch): drop the current word.
#[no_mangle]
pub extern "C" fn vk_reset_word() {
    lock().engine.reset_word();
}

#[no_mangle]
pub extern "C" fn vk_clear_all() {
    lock().engine.clear_all();
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn smoke_type_viet_through_c_abi() {
        vk_init();
        vk_clear_all();
        let mut buf: Vec<u16> = Vec::new();
        for c in "vieejt".chars() {
            let r = vk_process_key(0, c as u32, 0);
            match r.action {
                VK_ACTION_PASS => {
                    let mut u = [0u16; 2];
                    buf.extend_from_slice(c.encode_utf16(&mut u));
                }
                VK_ACTION_REPLACE => {
                    for _ in 0..r.backspaces {
                        buf.pop();
                    }
                    buf.extend_from_slice(&r.text[..r.text_len as usize]);
                }
                _ => panic!("unexpected action"),
            }
        }
        assert_eq!(String::from_utf16(&buf).unwrap(), "việt");
        vk_clear_all();
    }

    #[test]
    fn command_modifier_passes_through() {
        vk_init();
        vk_clear_all();
        let r = vk_process_key(0, 'a' as u32, 1);
        assert_eq!(r.action, VK_ACTION_PASS);
        vk_clear_all();
    }
}
