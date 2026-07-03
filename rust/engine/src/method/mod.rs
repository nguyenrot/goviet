//! Input-method key classification (Telex / Simple Telex / VNI).

pub mod telex;
pub mod vni;

use crate::config::Method;
use crate::syllable::Tone;

/// What a key means for the current input method, before context is applied.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum KeyClass {
    /// Apply a tone (sắc/huyền/hỏi/ngã/nặng).
    Tone(Tone),
    /// Remove the tone (telex z, VNI 0).
    ToneRemove,
    /// Circumflex on a specific vowel (telex: the doubled a/e/o).
    Circ(char),
    /// Circumflex on whichever of a/e/o is present (VNI 6).
    CircAny,
    /// Telex w: horn on u/o (both of a trailing "uo"), breve on a, standalone ư.
    W,
    /// VNI 7: horn on u/o.
    Horn,
    /// VNI 8: breve on a.
    Breve,
    /// dd → đ (telex d, VNI 9).
    StrokeD,
    /// Plain letter/content with no modifier meaning.
    Plain,
}

/// Classify a lowercase char for the given method. `word_empty` matters for
/// VNI, where digits at word start are literal.
pub fn classify(method: Method, c: char, word_empty: bool) -> KeyClass {
    match method {
        Method::Telex | Method::SimpleTelex => telex::classify(c),
        Method::Vni => vni::classify(c, word_empty),
    }
}
