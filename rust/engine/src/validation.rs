//! Vietnamese syllable validation: onsets, rhymes, tone-coda constraints.
//! Powers English auto-restore and modifier applicability checks.

use crate::syllable::{Letter, Mark, Tone};

/// Valid syllable onsets (phụ âm đầu), written form.
const ONSETS: &[&str] = &[
    "b", "c", "ch", "d", "đ", "g", "gh", "gi", "h", "k", "kh", "l", "m", "n",
    "ng", "ngh", "nh", "p", "ph", "qu", "r", "s", "t", "th", "tr", "v", "x",
];

/// Valid written rhymes (vần = nucleus incl. semivowel glides + consonant coda).
/// Marked vowels (ă â ê ô ơ ư) appear literally; tones are checked separately.
const RHYMES: &[&str] = &[
    // a
    "a", "ac", "ach", "ai", "am", "an", "ang", "anh", "ao", "ap", "at", "au", "ay",
    // ă (requires coda)
    "ăc", "ăm", "ăn", "ăng", "ăp", "ăt",
    // â (requires coda/glide)
    "âc", "âm", "ân", "âng", "âp", "ât", "âu", "ây",
    // e
    "e", "ec", "em", "en", "eng", "eo", "ep", "et",
    // ê
    "ê", "êch", "êm", "ên", "ênh", "êp", "êt", "êu",
    // i
    "i", "ia", "ich", "im", "in", "inh", "ip", "it", "iu",
    "iêc", "iêm", "iên", "iêng", "iêp", "iêt", "iêu",
    // o
    "o", "oa", "oac", "oach", "oai", "oam", "oan", "oang", "oanh", "oao", "oap",
    "oat", "oay", "oăc", "oăm", "oăn", "oăng", "oăt", "oc", "oe", "oen", "oeo",
    "oet", "oi", "om", "on", "ong", "ooc", "oong", "op", "ot",
    // ô
    "ô", "ôc", "ôi", "ôm", "ôn", "ông", "ôp", "ôt",
    // ơ
    "ơ", "ơi", "ơm", "ơn", "ơp", "ơt",
    // u
    "u", "ua", "uc", "ui", "um", "un", "ung", "up", "ut",
    "uân", "uâng", "uât", "uây",
    "uê", "uêch", "uênh",
    "uơ",
    "uôc", "uôi", "uôm", "uôn", "uông", "uôt",
    "uy", "uya", "uych", "uyên", "uyêt", "uyn", "uynh", "uyp", "uyt", "uyu",
    // ư
    "ư", "ưa", "ưc", "ưi", "ưng", "ưt", "ưu",
    "ươc", "ươi", "ươm", "ươn", "ương", "ươp", "ươt", "ươu",
    // y (also rhymes reached after the "qu" onset: quýt, quỳnh, quých)
    "y", "ych", "yêm", "yên", "yêng", "yêt", "yêu", "ynh", "yt",
];

fn is_vowel_char(c: char) -> bool {
    matches!(
        c,
        'a' | 'e' | 'i' | 'o' | 'u' | 'y'
            | 'ă' | 'â' | 'ê' | 'ô' | 'ơ' | 'ư'
    )
}

/// Rhyme ends in a stop coda (p t c ch) → tone must be sắc or nặng.
fn has_stop_coda(rhyme: &str) -> bool {
    rhyme.ends_with('p') || rhyme.ends_with('t') || rhyme.ends_with('c') || rhyme.ends_with("ch")
}

/// Render letters to a toneless lowercase string (marks included).
pub fn toneless_lower(letters: &[Letter]) -> String {
    letters
        .iter()
        .map(|l| crate::syllable::render_letter(&Letter { upper: false, ..*l }, Tone::None))
        .collect()
}

/// "gh"/"ngh" may only precede i, e, ê (orthography rule that catches
/// mistyped English without hurting real Vietnamese).
fn onset_orthography_ok(onset: &str, rest: &str) -> bool {
    if onset == "gh" || onset == "ngh" {
        match rest.chars().next() {
            Some(c) => matches!(c, 'i' | 'e' | 'ê'),
            None => true, // still a prefix, rest unknown
        }
    } else {
        true
    }
}

/// Try to split `s` as onset + rest for every plausible onset (longest first),
/// calling `check(rest)`; also accepts `s` being a prefix of an onset.
fn any_parse(s: &str, check: impl Fn(&str) -> bool) -> bool {
    // s itself may be an incomplete onset ("q", "ng", "ngh", "t", "th"...)
    if ONSETS.iter().any(|o| o.starts_with(s)) {
        return true;
    }
    let mut onsets: Vec<&str> = ONSETS.to_vec();
    onsets.push(""); // empty onset
    onsets.sort_by_key(|o| std::cmp::Reverse(o.len()));
    for onset in onsets {
        if let Some(rest) = s.strip_prefix(onset) {
            if !onset_orthography_ok(onset, rest) {
                continue;
            }
            // rest must be vowels followed by consonants only
            let vowel_end = rest
                .char_indices()
                .find(|(_, c)| !is_vowel_char(*c))
                .map(|(i, _)| i)
                .unwrap_or(rest.len());
            let coda = &rest[vowel_end..];
            if coda.chars().any(is_vowel_char) {
                continue; // vowel after coda started → structurally invalid
            }
            if check(rest) {
                return true;
            }
        }
    }
    false
}

/// Can `letters` (+ current tone) still grow into a valid Vietnamese syllable?
pub fn valid_prefix(letters: &[Letter], tone: Tone) -> bool {
    // Any non a-z base (w, digits, stray symbols) disqualifies immediately,
    // except đ which must sit in onset position (checked via parse below).
    if letters
        .iter()
        .any(|l| !l.base.is_ascii_lowercase())
    {
        return false;
    }
    let s = toneless_lower(letters);
    if s.is_empty() {
        return true;
    }
    any_parse(&s, |rest| {
        if rest.is_empty() {
            return true;
        }
        // Transitional state: "ưo" becomes "ươ" as soon as the next letter
        // arrives (tuwong → tưo → tươn), so accept it as a prefix.
        if rest == "ưo" {
            return true;
        }
        RHYMES.iter().any(|r| {
            if !r.starts_with(rest) {
                return false;
            }
            // Tone constraint only enforceable once the coda is complete;
            // if rest == full rhyme with stop coda, tone must be sắc/nặng/none.
            if *r == rest && has_stop_coda(r) {
                matches!(tone, Tone::None | Tone::Acute | Tone::Dot)
            } else {
                true
            }
        })
    })
}

/// Is `letters` (+ tone) a complete, valid Vietnamese syllable?
pub fn valid_full(letters: &[Letter], tone: Tone) -> bool {
    if letters.iter().any(|l| !l.base.is_ascii_lowercase()) {
        return false;
    }
    let s = toneless_lower(letters);
    if s.is_empty() {
        return false;
    }
    any_parse(&s, |rest| {
        if rest.is_empty() {
            return false; // onset alone is not a syllable
        }
        RHYMES.iter().any(|r| {
            *r == rest
                && (!has_stop_coda(r) || matches!(tone, Tone::Acute | Tone::Dot))
        })
    })
}

/// True if the word contains any letter carrying a mark or the tone is set —
/// i.e. rendering differs from the raw latin letters.
pub fn is_transformed(letters: &[Letter], tone: Tone) -> bool {
    tone != Tone::None || letters.iter().any(|l| l.mark != Mark::None)
}
