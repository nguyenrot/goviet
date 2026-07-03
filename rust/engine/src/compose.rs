//! The composer: applies one key to the current word state.
//! Modifiers (tones/marks) only apply when the result stays a valid
//! Vietnamese syllable prefix; otherwise the key lands as a literal.

use crate::config::{Config, Method, ToneStyle};
use crate::method::{classify, telex, KeyClass};
use crate::syllable::{render_letter, parse_char, Letter, Mark, Tone};
use crate::tone::{nucleus_range, tone_position};
use crate::validation::valid_prefix;

/// What happened when a key was applied.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Applied {
    /// A modifier transformed the word.
    Modified,
    /// A modifier was undone (double-tap revert); the key landed literally.
    Reverted,
    /// A modifier could not apply (invalid result); the key landed literally.
    Rejected,
    /// Plain content appended.
    Appended,
}

#[derive(Debug, Clone, Default)]
pub struct Composer {
    pub letters: Vec<Letter>,
    pub tone: Tone,
}

impl Composer {
    pub fn new() -> Self {
        Composer { letters: Vec::new(), tone: Tone::None }
    }

    pub fn clear(&mut self) {
        self.letters.clear();
        self.tone = Tone::None;
    }

    pub fn is_empty(&self) -> bool {
        self.letters.is_empty()
    }

    /// Render the composed word (NFC precomposed chars).
    pub fn render(&self, style: ToneStyle) -> String {
        let pos = if self.tone != Tone::None {
            tone_position(&self.letters, style)
        } else {
            None
        };
        self.letters
            .iter()
            .enumerate()
            .map(|(i, l)| {
                let t = if Some(i) == pos { self.tone } else { Tone::None };
                render_letter(l, t)
            })
            .collect()
    }

    /// Rebuild state from rendered text (used after a manual backspace).
    pub fn from_rendered(s: &str) -> Self {
        let mut letters = Vec::new();
        let mut tone = Tone::None;
        for c in s.chars() {
            let (l, t) = parse_char(c);
            if t != Tone::None {
                tone = t;
            }
            letters.push(l);
        }
        Composer { letters, tone }
    }

    /// Replace the whole word with literal letters (auto/ESC restore).
    pub fn set_literal(&mut self, raw: &[char]) {
        self.letters = raw
            .iter()
            .map(|&c| {
                let upper = c.is_uppercase();
                Letter::plain(c.to_lowercase().next().unwrap_or(c), upper)
            })
            .collect();
        self.tone = Tone::None;
    }

    fn push_plain(&mut self, lower: char, upper: bool) {
        self.letters.push(Letter::plain(lower, upper));
        self.normalize_uo();
    }

    /// ưo followed by anything → ươ ("tuwon" → tươn, "tuwoi" → tươi).
    fn normalize_uo(&mut self) {
        let n = self.letters.len();
        if n < 3 {
            return;
        }
        for i in 0..n - 1 {
            let horn_u = self.letters[i].base == 'u' && self.letters[i].mark == Mark::Horn;
            let plain_o = self.letters[i + 1].base == 'o' && self.letters[i + 1].mark == Mark::None;
            if horn_u && plain_o && i + 2 < n {
                self.letters[i + 1].mark = Mark::Horn;
            }
        }
    }

    /// Apply one typed character. `force_upper` implements auto-capitalize.
    pub fn apply_key(&mut self, c: char, force_upper: bool, cfg: &Config) -> Applied {
        let upper = c.is_uppercase() || force_upper;
        let lower = c.to_lowercase().next().unwrap_or(c);

        // Quick telex: cc→ch, gg→gi, kk→kh, nn→ng, pp→ph, qq→qu, tt→th
        if cfg.quick_telex
            && matches!(cfg.method, Method::Telex | Method::SimpleTelex)
            && self.letters.len() == 1
            && self.letters[0].base == lower
            && self.letters[0].mark == Mark::None
        {
            if let Some(second) = telex::quick_digraph(lower) {
                self.push_plain(second, false);
                return Applied::Modified;
            }
        }

        match classify(cfg.method, lower, self.letters.is_empty()) {
            KeyClass::Tone(t) => self.apply_tone(t, lower, upper),
            KeyClass::ToneRemove => {
                if self.tone != Tone::None {
                    self.tone = Tone::None;
                    Applied::Modified
                } else {
                    self.push_plain(lower, upper);
                    Applied::Appended
                }
            }
            KeyClass::Circ(v) => self.apply_circ(Some(v), lower, upper),
            KeyClass::CircAny => self.apply_circ(None, lower, upper),
            KeyClass::W => self.apply_w(lower, upper, cfg),
            KeyClass::Horn => self.apply_horn_or_breve(true, lower, upper),
            KeyClass::Breve => self.apply_horn_or_breve(false, lower, upper),
            KeyClass::StrokeD => self.apply_stroke(lower, upper),
            KeyClass::Plain => {
                self.push_plain(lower, upper);
                Applied::Appended
            }
        }
    }

    fn apply_tone(&mut self, t: Tone, lower: char, upper: bool) -> Applied {
        let has_nucleus = nucleus_range(&self.letters).is_some();
        if !has_nucleus || !valid_prefix(&self.letters, Tone::None) {
            self.push_plain(lower, upper);
            return if self.letters.len() > 1 { Applied::Rejected } else { Applied::Appended };
        }
        if self.tone == t {
            // double-tap revert: remove tone, key lands literally
            self.tone = Tone::None;
            self.push_plain(lower, upper);
            return Applied::Reverted;
        }
        let old = self.tone;
        self.tone = t;
        if valid_prefix(&self.letters, self.tone) {
            Applied::Modified
        } else {
            self.tone = old;
            self.push_plain(lower, upper);
            Applied::Rejected
        }
    }

    /// Circumflex: telex doubled vowel (target base = Some(v)) or VNI 6 (any a/e/o).
    fn apply_circ(&mut self, target: Option<char>, lower: char, upper: bool) -> Applied {
        let idx = self.find_nucleus_target(|l| match target {
            Some(v) => l.base == v,
            None => matches!(l.base, 'a' | 'e' | 'o'),
        });
        let Some(i) = idx else {
            self.push_plain(lower, upper);
            return Applied::Appended;
        };
        match self.letters[i].mark {
            Mark::Circumflex => {
                self.letters[i].mark = Mark::None;
                self.push_plain(lower, upper);
                Applied::Reverted
            }
            Mark::None | Mark::Breve | Mark::Horn => {
                self.try_mark(i, Mark::Circumflex, lower, upper)
            }
            Mark::Stroke => {
                self.push_plain(lower, upper);
                Applied::Appended
            }
        }
    }

    /// An adjacent u+o inside the nucleus (nguoi, muon, thuo...) horns as a
    /// pair → ươ, if the result stays a valid prefix.
    fn try_horn_uo_pair(&mut self) -> bool {
        let Some((start, end)) = nucleus_range(&self.letters) else {
            return false;
        };
        for i in start..end.saturating_sub(1) {
            let u = self.letters[i];
            let o = self.letters[i + 1];
            if u.base == 'u'
                && o.base == 'o'
                && o.mark == Mark::None
                && matches!(u.mark, Mark::None | Mark::Horn)
            {
                self.letters[i].mark = Mark::Horn;
                self.letters[i + 1].mark = Mark::Horn;
                if valid_prefix(&self.letters, self.tone) {
                    return true;
                }
                self.letters[i].mark = u.mark;
                self.letters[i + 1].mark = o.mark;
            }
        }
        false
    }

    /// Telex w: horn u/o (an adjacent "uo" gets horned as a pair), breve a,
    /// or standalone ư at word start / after a bare onset.
    fn apply_w(&mut self, lower: char, upper: bool, cfg: &Config) -> Applied {
        if self.try_horn_uo_pair() {
            return Applied::Modified;
        }
        if let Some(i) = self.find_nucleus_target(|l| matches!(l.base, 'u' | 'o' | 'a')) {
            let want = if self.letters[i].base == 'a' { Mark::Breve } else { Mark::Horn };
            return match self.letters[i].mark {
                m if m == want => {
                    if self.letters[i].from_w {
                        // standalone-w ư reverts to a literal w
                        self.letters[i] = Letter::plain('w', self.letters[i].upper);
                        Applied::Reverted
                    } else {
                        self.letters[i].mark = Mark::None;
                        self.push_plain(lower, upper);
                        Applied::Reverted
                    }
                }
                Mark::Stroke => {
                    self.push_plain(lower, upper);
                    Applied::Appended
                }
                _ => self.try_mark(i, want, lower, upper),
            };
        }
        // Standalone w → ư (classic telex only), after nothing or a bare onset
        let bare_onset = self.letters.iter().all(|l| !l.is_vowel())
            && valid_prefix(&self.letters, Tone::None);
        if cfg.method == Method::Telex && bare_onset {
            self.letters.push(Letter { base: 'u', mark: Mark::Horn, upper, from_w: true });
            return Applied::Modified;
        }
        self.push_plain(lower, upper);
        Applied::Appended
    }

    /// VNI 7 (horn on u/o) and 8 (breve on a).
    fn apply_horn_or_breve(&mut self, horn: bool, lower: char, upper: bool) -> Applied {
        if horn && self.try_horn_uo_pair() {
            return Applied::Modified;
        }
        let pred = |l: &Letter| if horn { matches!(l.base, 'u' | 'o') } else { l.base == 'a' };
        let want = if horn { Mark::Horn } else { Mark::Breve };
        if let Some(i) = self.find_nucleus_target(pred) {
            return match self.letters[i].mark {
                m if m == want => {
                    self.letters[i].mark = Mark::None;
                    self.push_plain(lower, upper);
                    Applied::Reverted
                }
                Mark::Stroke => {
                    self.push_plain(lower, upper);
                    Applied::Appended
                }
                _ => self.try_mark(i, want, lower, upper),
            };
        }
        self.push_plain(lower, upper);
        if self.letters.len() > 1 { Applied::Rejected } else { Applied::Appended }
    }

    /// dd → đ (stroke on a word-initial d, typable from anywhere in the word).
    fn apply_stroke(&mut self, lower: char, upper: bool) -> Applied {
        if let Some(first) = self.letters.first().copied() {
            if first.base == 'd' {
                if first.mark == Mark::Stroke {
                    self.letters[0].mark = Mark::None;
                    self.push_plain(lower, upper);
                    return Applied::Reverted;
                }
                if first.mark == Mark::None {
                    self.letters[0].mark = Mark::Stroke;
                    if upper {
                        self.letters[0].upper = true; // dD / DD → Đ
                    }
                    if valid_prefix(&self.letters, self.tone) {
                        return Applied::Modified;
                    }
                    self.letters[0].mark = Mark::None;
                    self.letters[0].upper = first.upper;
                    self.push_plain(lower, upper);
                    return Applied::Rejected;
                }
            }
        }
        self.push_plain(lower, upper);
        Applied::Appended
    }

    /// Search the nucleus from the end for a letter matching `pred`.
    fn find_nucleus_target(&self, pred: impl Fn(&Letter) -> bool) -> Option<usize> {
        let (start, end) = nucleus_range(&self.letters)?;
        (start..end).rev().find(|&i| pred(&self.letters[i]))
    }

    /// Set a mark if the result stays a valid prefix; otherwise land literally.
    fn try_mark(&mut self, i: usize, mark: Mark, lower: char, upper: bool) -> Applied {
        let old = self.letters[i].mark;
        self.letters[i].mark = mark;
        if valid_prefix(&self.letters, self.tone) {
            Applied::Modified
        } else {
            self.letters[i].mark = old;
            self.push_plain(lower, upper);
            Applied::Rejected
        }
    }
}
