//! VNI key table.

use super::KeyClass;
use crate::syllable::Tone;

pub fn classify(c: char, word_empty: bool) -> KeyClass {
    if word_empty {
        return KeyClass::Plain; // digits at word start are literal
    }
    match c {
        '1' => KeyClass::Tone(Tone::Acute),
        '2' => KeyClass::Tone(Tone::Grave),
        '3' => KeyClass::Tone(Tone::Hook),
        '4' => KeyClass::Tone(Tone::Tilde),
        '5' => KeyClass::Tone(Tone::Dot),
        '0' => KeyClass::ToneRemove,
        '6' => KeyClass::CircAny,
        '7' => KeyClass::Horn,
        '8' => KeyClass::Breve,
        '9' => KeyClass::StrokeD,
        _ => KeyClass::Plain,
    }
}
