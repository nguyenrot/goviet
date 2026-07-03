//! Telex key table.

use super::KeyClass;
use crate::syllable::Tone;

pub fn classify(c: char) -> KeyClass {
    match c {
        's' => KeyClass::Tone(Tone::Acute),
        'f' => KeyClass::Tone(Tone::Grave),
        'r' => KeyClass::Tone(Tone::Hook),
        'x' => KeyClass::Tone(Tone::Tilde),
        'j' => KeyClass::Tone(Tone::Dot),
        'z' => KeyClass::ToneRemove,
        'a' | 'e' | 'o' => KeyClass::Circ(c),
        'w' => KeyClass::W,
        'd' => KeyClass::StrokeD,
        _ => KeyClass::Plain,
    }
}

/// Quick telex digraphs: first key of the word doubled → digraph onset.
pub fn quick_digraph(first: char) -> Option<char> {
    match first {
        'c' => Some('h'), // cc → ch
        'g' => Some('i'), // gg → gi
        'k' => Some('h'), // kk → kh
        'p' => Some('h'), // pp → ph
        'q' => Some('u'), // qq → qu
        't' => Some('h'), // tt → th
        'n' => Some('g'), // nn → ng
        _ => None,
    }
}
