//! The engine state machine: keystrokes in, edit actions out.

use crate::autocaps::SentenceState;
use crate::compose::{Applied, Composer};
use crate::config::Config;
use crate::keys::{self, KeyInput};
use crate::macros::MacroTable;
use crate::validation::valid_prefix;

/// Words longer than this stop being treated as Vietnamese (URLs, passwords).
const MAX_WORD_LEN: usize = 32;

/// What the shell must do with the keystroke.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Action {
    /// Let the original event through untouched.
    PassThrough,
    /// Consume the event; delete `backspaces` chars then insert `text`.
    /// When `forward` is set, re-post the original key event afterwards
    /// (used by macro expansion so the space/enter still lands).
    Replace {
        backspaces: usize,
        text: String,
        forward: bool,
    },
}

#[derive(Debug)]
pub struct Engine {
    cfg: Config,
    macros: MacroTable,
    /// Raw typed chars of the current word (case as typed).
    raw: Vec<char>,
    comp: Composer,
    /// Word was (auto/ESC) restored — engine is inert until the next break.
    restored: bool,
    /// Auto-restore is off for this word (revert/reject/backspace happened).
    suppress_restore: bool,
    /// `raw` faithfully mirrors keystrokes (false after backspace surgery).
    esc_ok: bool,
    /// The first letter was uppercased by sentence capitalization rather than
    /// typed uppercase. English restore must preserve this presentation.
    auto_capitalized: bool,
    sentence: SentenceState,
}

impl Default for Engine {
    fn default() -> Self {
        Engine::new()
    }
}

impl Engine {
    pub fn new() -> Self {
        Engine {
            cfg: Config::default(),
            macros: MacroTable::default(),
            raw: Vec::new(),
            comp: Composer::new(),
            restored: false,
            suppress_restore: false,
            esc_ok: true,
            auto_capitalized: false,
            sentence: SentenceState::default(),
        }
    }

    pub fn set_config(&mut self, cfg: Config) {
        self.cfg = cfg;
        self.reset_word();
    }

    pub fn config(&self) -> &Config {
        &self.cfg
    }

    pub fn set_macros(&mut self, table: MacroTable) {
        self.macros = table;
    }

    /// Forget the current word but keep sentence tracking (word committed
    /// or deleted in place).
    fn clear_word(&mut self) {
        self.raw.clear();
        self.comp.clear();
        self.restored = false;
        self.suppress_restore = false;
        self.esc_ok = true;
        self.auto_capitalized = false;
    }

    /// Caret moved (click, arrows, app switch): forget the word silently.
    pub fn reset_word(&mut self) {
        self.clear_word();
        self.sentence.reset();
    }

    pub fn clear_all(&mut self) {
        self.reset_word();
    }

    fn composed(&self) -> String {
        self.comp.render(self.cfg.tone_style)
    }

    fn raw_string(&self) -> String {
        self.raw.iter().collect()
    }

    /// Literal keystrokes as they should remain on screen. Unlike `raw_string`,
    /// this preserves sentence auto-capitalization while ignoring Telex/VNI
    /// transformations.
    fn literal_string(&self) -> String {
        self.raw
            .iter()
            .enumerate()
            .map(|(i, &c)| {
                if i == 0 && self.auto_capitalized {
                    c.to_uppercase().next().unwrap_or(c)
                } else {
                    c
                }
            })
            .collect()
    }

    fn restore_literal_preserving_capitalization(&mut self) {
        self.comp.set_literal(&self.raw);
        if !self.auto_capitalized {
            return;
        }
        if let Some(first) = self.comp.letters.first_mut() {
            first.upper = true;
        }
    }

    pub fn process_key(&mut self, k: KeyInput) -> Action {
        if !self.cfg.enabled {
            return Action::PassThrough;
        }
        if k.with_command {
            self.reset_word();
            return Action::PassThrough;
        }
        match k.keycode {
            keys::KC_BACKSPACE => return self.handle_backspace(),
            keys::KC_ESCAPE => return self.handle_escape(),
            keys::KC_RETURN | keys::KC_ENTER => return self.handle_break('\n'),
            keys::KC_TAB => return self.handle_break('\t'),
            keys::KC_FORWARD_DELETE => {
                self.reset_word();
                return Action::PassThrough;
            }
            kc if keys::is_nav_keycode(kc) => {
                self.reset_word();
                return Action::PassThrough;
            }
            _ => {}
        }
        let Some(c) = k.ch else {
            return Action::PassThrough; // function/media keys
        };
        if c.is_alphanumeric() {
            self.handle_content(c)
        } else if c.is_control() {
            self.reset_word();
            Action::PassThrough
        } else {
            self.handle_break(c)
        }
    }

    fn handle_content(&mut self, c: char) -> Action {
        let prev = self.composed();
        let force_upper = self.cfg.auto_capitalize
            && self.comp.is_empty()
            && self.sentence.on_word_start(c)
            && !c.is_uppercase();
        if !self.cfg.auto_capitalize {
            // still consume pending state so a later toggle can't misfire
            self.sentence.on_word_start(c);
        }
        if force_upper {
            self.auto_capitalized = true;
        }
        self.raw.push(c);

        if self.restored || self.comp.letters.len() >= MAX_WORD_LEN {
            let upper = c.is_uppercase();
            let lower = c.to_lowercase().next().unwrap_or(c);
            self.comp
                .letters
                .push(crate::syllable::Letter::plain(lower, upper));
            self.restored = true;
            return self.diff(&prev, c);
        }

        let outcome = self.comp.apply_key(c, force_upper, &self.cfg);
        // Only a double-tap revert (intentional literal: "uww" → uw, "aaa"
        // → aa) turns auto-restore off. A rejected modifier must NOT: in
        // "world" the rejected 'r' would otherwise block the restore that
        // turns "ưo.." back into "wor..".
        if outcome == Applied::Reverted {
            self.suppress_restore = true;
        }

        // English auto-restore: a transformation happened earlier but the
        // word can no longer be Vietnamese → put the raw keystrokes back.
        // Macro triggers like "đc"/"đn"/"òh" are not valid syllables, so they
        // must be exempt or the shortcut is restored to "ddc" before space.
        if self.cfg.english_auto_restore
            && !self.suppress_restore
            && !self.restored
            && c.is_ascii_alphabetic()
            && outcome == Applied::Appended
            && self.is_word_transformed()
            && !valid_prefix(&self.comp.letters, self.comp.tone)
            && !self.matches_macro(&self.composed())
        {
            self.restore_literal_preserving_capitalization();
            self.restored = true;
        }
        if !c.is_ascii_alphanumeric() {
            // non-ascii content (é from other layouts...) — leave it alone
            self.suppress_restore = true;
        }
        self.diff(&prev, c)
    }

    fn is_word_transformed(&self) -> bool {
        self.composed() != self.literal_string()
    }

    fn matches_macro(&self, word: &str) -> bool {
        self.cfg.macros_enabled && self.macros.contains(word)
    }

    fn diff(&self, prev: &str, typed: char) -> Action {
        let new = self.composed();
        let p: Vec<char> = prev.chars().collect();
        let n: Vec<char> = new.chars().collect();
        let mut lcp = 0;
        while lcp < p.len() && lcp < n.len() && p[lcp] == n[lcp] {
            lcp += 1;
        }
        let backspaces = p.len() - lcp;
        let text: String = n[lcp..].iter().collect();
        if backspaces == 0 && text.chars().eq(std::iter::once(typed)) {
            return Action::PassThrough;
        }
        Action::Replace { backspaces, text, forward: false }
    }

    fn handle_backspace(&mut self) -> Action {
        if self.comp.is_empty() {
            return Action::PassThrough;
        }
        let prev = self.composed();
        let mut chars: Vec<char> = prev.chars().collect();
        chars.pop();
        if chars.is_empty() {
            self.clear_word();
        } else {
            let truncated: String = chars.iter().collect();
            self.comp = Composer::from_rendered(&truncated);
            self.raw = chars;
            self.esc_ok = false;
            self.suppress_restore = true;
            self.auto_capitalized = false;
            // A restored (inert) word becomes Vietnamese-typable again once the
            // offending suffix is deleted: if what remains is a valid syllable
            // prefix, re-enable composition so the next modifier key transforms
            // ("muowa"⌫⌫ → "muo", then "w" → "mươ"). A remainder that is still
            // not Vietnamese ("user"⌫ → "use") stays inert.
            if self.restored && valid_prefix(&self.comp.letters, self.comp.tone) {
                self.restored = false;
            }
        }
        Action::PassThrough
    }

    fn handle_escape(&mut self) -> Action {
        let composed = self.composed();
        let auto_capitalization_only = self.auto_capitalized && composed == self.literal_string();
        if self.cfg.esc_restores_raw
            && (!self.restored || auto_capitalization_only)
            && self.esc_ok
            && !self.comp.is_empty()
            && composed != self.raw_string()
        {
            let text = self.raw_string();
            self.comp.set_literal(&self.raw);
            self.auto_capitalized = false;
            self.restored = true;
            return Action::Replace {
                backspaces: composed.chars().count(),
                text,
                forward: false,
            };
        }
        self.reset_word();
        Action::PassThrough
    }

    fn handle_break(&mut self, c: char) -> Action {
        let mut action = Action::PassThrough;
        if self.cfg.macros_enabled && !self.macros.is_empty() && !self.comp.is_empty() {
            let word = self.composed();
            if let Some(expansion) = self.macros.expand(&word) {
                action = Action::Replace {
                    backspaces: word.chars().count(),
                    text: expansion,
                    forward: true,
                };
            }
        }
        // Commit-restore: the word was transformed but is not a valid
        // Vietnamese syllable ("two" → "tưo") → give the raw keys back.
        if action == Action::PassThrough
            && self.cfg.english_auto_restore
            && !self.restored
            && !self.suppress_restore
            && !self.comp.is_empty()
        {
            let word = self.composed();
            let literal = self.literal_string();
            if word != literal
                && !crate::validation::valid_full(&self.comp.letters, self.comp.tone)
            {
                action = Action::Replace {
                    backspaces: word.chars().count(),
                    text: literal,
                    forward: true,
                };
            }
        }
        self.sentence.on_break(c);
        self.clear_word();
        action
    }
}
