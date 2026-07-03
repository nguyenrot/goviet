//! Sentence tracking for auto-capitalization.

#[derive(Debug, Default, Clone, Copy)]
pub struct SentenceState {
    pending: bool,
}

impl SentenceState {
    /// A word-break character was committed.
    pub fn on_break(&mut self, c: char) {
        if matches!(c, '.' | '!' | '?' | '\n') {
            self.pending = true;
        }
        // spaces/other punctuation keep the pending state
    }

    /// First content char of a new word; returns true if it should be
    /// capitalized. Digits consume the pending state without capitalizing.
    pub fn on_word_start(&mut self, c: char) -> bool {
        if !self.pending {
            return false;
        }
        self.pending = false;
        c.is_alphabetic()
    }

    pub fn reset(&mut self) {
        self.pending = false;
    }
}
