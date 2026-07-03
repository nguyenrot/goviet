//! Letter/Mark/Tone model and rendering tables for Vietnamese.

/// Diacritic mark attached to a single letter (not the tone).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Mark {
    None,
    Circumflex, // â ê ô
    Breve,      // ă
    Horn,       // ơ ư
    Stroke,     // đ
}

/// Tone applied to the whole syllable; rendered on one vowel.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Tone {
    #[default]
    None,
    Acute, // sắc
    Grave, // huyền
    Hook,  // hỏi
    Tilde, // ngã
    Dot,   // nặng
}

impl Tone {
    pub fn index(self) -> usize {
        match self {
            Tone::None => 0,
            Tone::Acute => 1,
            Tone::Grave => 2,
            Tone::Hook => 3,
            Tone::Tilde => 4,
            Tone::Dot => 5,
        }
    }
}

/// One letter of the word being composed. `base` is the plain lowercase
/// letter as typed ('a'..'z'); anything else (digits, symbols kept as word
/// content) passes through rendering unchanged.
#[derive(Debug, Clone, Copy)]
pub struct Letter {
    pub base: char,
    pub mark: Mark,
    pub upper: bool,
    /// This ư came from a standalone telex "w" (revert must give back 'w').
    pub from_w: bool,
}

impl Letter {
    pub fn plain(base: char, upper: bool) -> Self {
        Letter { base, mark: Mark::None, upper, from_w: false }
    }

    pub fn is_vowel(&self) -> bool {
        matches!(self.base, 'a' | 'e' | 'i' | 'o' | 'u' | 'y') && self.mark != Mark::Stroke
    }
}

const A_PLAIN: [char; 6] = ['a', 'á', 'à', 'ả', 'ã', 'ạ'];
const A_CIRC: [char; 6] = ['â', 'ấ', 'ầ', 'ẩ', 'ẫ', 'ậ'];
const A_BREVE: [char; 6] = ['ă', 'ắ', 'ằ', 'ẳ', 'ẵ', 'ặ'];
const E_PLAIN: [char; 6] = ['e', 'é', 'è', 'ẻ', 'ẽ', 'ẹ'];
const E_CIRC: [char; 6] = ['ê', 'ế', 'ề', 'ể', 'ễ', 'ệ'];
const I_PLAIN: [char; 6] = ['i', 'í', 'ì', 'ỉ', 'ĩ', 'ị'];
const O_PLAIN: [char; 6] = ['o', 'ó', 'ò', 'ỏ', 'õ', 'ọ'];
const O_CIRC: [char; 6] = ['ô', 'ố', 'ồ', 'ổ', 'ỗ', 'ộ'];
const O_HORN: [char; 6] = ['ơ', 'ớ', 'ờ', 'ở', 'ỡ', 'ợ'];
const U_PLAIN: [char; 6] = ['u', 'ú', 'ù', 'ủ', 'ũ', 'ụ'];
const U_HORN: [char; 6] = ['ư', 'ứ', 'ừ', 'ử', 'ữ', 'ự'];
const Y_PLAIN: [char; 6] = ['y', 'ý', 'ỳ', 'ỷ', 'ỹ', 'ỵ'];

fn table_for(base: char, mark: Mark) -> Option<&'static [char; 6]> {
    match (base, mark) {
        ('a', Mark::None) => Some(&A_PLAIN),
        ('a', Mark::Circumflex) => Some(&A_CIRC),
        ('a', Mark::Breve) => Some(&A_BREVE),
        ('e', Mark::None) => Some(&E_PLAIN),
        ('e', Mark::Circumflex) => Some(&E_CIRC),
        ('i', Mark::None) => Some(&I_PLAIN),
        ('o', Mark::None) => Some(&O_PLAIN),
        ('o', Mark::Circumflex) => Some(&O_CIRC),
        ('o', Mark::Horn) => Some(&O_HORN),
        ('u', Mark::None) => Some(&U_PLAIN),
        ('u', Mark::Horn) => Some(&U_HORN),
        ('y', Mark::None) => Some(&Y_PLAIN),
        _ => None,
    }
}

/// Render one letter with an optional tone (NFC precomposed).
pub fn render_letter(l: &Letter, tone: Tone) -> char {
    let lower = if l.base == 'd' && l.mark == Mark::Stroke {
        'đ'
    } else if let Some(t) = table_for(l.base, l.mark) {
        t[tone.index()]
    } else {
        l.base
    };
    if l.upper {
        lower.to_uppercase().next().unwrap_or(lower)
    } else {
        lower
    }
}

/// Parse one rendered char back into (Letter, Tone). Unknown chars come back
/// as plain letters with no tone.
pub fn parse_char(c: char) -> (Letter, Tone) {
    let upper = c.is_uppercase();
    let lc = c.to_lowercase().next().unwrap_or(c);
    if lc == 'đ' {
        return (
            Letter { base: 'd', mark: Mark::Stroke, upper, from_w: false },
            Tone::None,
        );
    }
    for base in ['a', 'e', 'i', 'o', 'u', 'y'] {
        for mark in [Mark::None, Mark::Circumflex, Mark::Breve, Mark::Horn] {
            if let Some(t) = table_for(base, mark) {
                if let Some(idx) = t.iter().position(|&x| x == lc) {
                    let tone = [Tone::None, Tone::Acute, Tone::Grave, Tone::Hook, Tone::Tilde, Tone::Dot][idx];
                    return (Letter { base, mark, upper, from_w: false }, tone);
                }
            }
        }
    }
    (Letter::plain(lc, upper), Tone::None)
}
