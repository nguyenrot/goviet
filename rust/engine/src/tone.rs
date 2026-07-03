//! Tone placement: which vowel of the nucleus carries the tone mark.

use crate::config::ToneStyle;
use crate::syllable::{Letter, Mark};

/// Range of the vowel nucleus inside `letters` (start..end), skipping the
/// onset — including the u of "qu" and the i of "gi" when they act as onset.
pub fn nucleus_range(letters: &[Letter]) -> Option<(usize, usize)> {
    let n = letters.len();
    let mut start = 0;
    while start < n && !letters[start].is_vowel() {
        start += 1;
    }
    if start >= n {
        return None;
    }
    // "qu" + vowel: u belongs to the onset
    if start > 0
        && letters[start - 1].base == 'q'
        && letters[start].base == 'u'
        && letters[start].mark == Mark::None
        && start + 1 < n
        && letters[start + 1].is_vowel()
    {
        start += 1;
    }
    // "gi" + vowel: i belongs to the onset (già, giá — but not gìn)
    if start > 0
        && letters[start - 1].base == 'g'
        && letters[start].base == 'i'
        && letters[start].mark == Mark::None
        && start + 1 < n
        && letters[start + 1].is_vowel()
    {
        start += 1;
    }
    let mut end = start;
    while end < n && letters[end].is_vowel() {
        end += 1;
    }
    if end == start {
        return None;
    }
    Some((start, end))
}

/// Index of the letter that should carry the tone, or None if no vowel.
pub fn tone_position(letters: &[Letter], style: ToneStyle) -> Option<usize> {
    let (start, end) = nucleus_range(letters)?;
    let nucleus = &letters[start..end];
    let has_coda = end < letters.len();

    // A marked vowel (ơ ê â ă ô ư) always carries the tone; with several
    // (ươ) the last one does.
    if let Some(i) = nucleus
        .iter()
        .rposition(|l| matches!(l.mark, Mark::Circumflex | Mark::Breve | Mark::Horn))
    {
        return Some(start + i);
    }

    match nucleus.len() {
        1 => Some(start),
        3 => Some(start + 1), // oai, uyu, khuỷu... → middle
        2 => {
            if has_coda {
                Some(start + 1) // hoàn, quỳnh
            } else {
                let pair = (nucleus[0].base, nucleus[1].base);
                let is_open_glide = matches!(pair, ('o', 'a') | ('o', 'e') | ('u', 'y'));
                if is_open_glide && style == ToneStyle::New {
                    Some(start + 1) // oà, oè, uý
                } else {
                    Some(start) // òa, úy (old style); ái, ùa, áo...
                }
            }
        }
        _ => Some(start),
    }
}
