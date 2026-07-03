//! Data-driven corpus tests: each TSV row is `keystrokes<TAB>expected`.
//! Keystrokes are fed through the Engine; the resulting edit actions are
//! applied to a simulated screen buffer which must equal `expected`.
//! Special keys: ⌫ backspace, ⎋ escape.

use goviet_engine::{Action, Config, Engine, KeyInput, MacroTable, Method, ToneStyle};

const KC_BACKSPACE: u16 = 51;
const KC_ESCAPE: u16 = 53;

fn feed(engine: &mut Engine, buf: &mut String, c: char) {
    let (keycode, ch) = match c {
        '⌫' => (KC_BACKSPACE, None),
        '⎋' => (KC_ESCAPE, None),
        _ => (0u16, Some(c)),
    };
    let action = engine.process_key(KeyInput { keycode, ch, with_command: false });
    match action {
        Action::PassThrough => match c {
            '⌫' => {
                buf.pop();
            }
            '⎋' => {}
            _ => buf.push(c),
        },
        Action::Replace { backspaces, text, forward } => {
            for _ in 0..backspaces {
                buf.pop();
            }
            buf.push_str(&text);
            if forward && !matches!(c, '⌫' | '⎋') {
                buf.push(c);
            }
        }
    }
}

fn type_string(engine: &mut Engine, input: &str) -> String {
    let mut buf = String::new();
    for c in input.chars() {
        feed(engine, &mut buf, c);
    }
    buf
}

fn run_corpus(file: &str, cfg: Config, macros_json: Option<&str>) {
    let path = format!("{}/tests/corpus/{}", env!("CARGO_MANIFEST_DIR"), file);
    let data = std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {path}: {e}"));
    let mut failures = Vec::new();
    for (ln, line) in data.lines().enumerate() {
        let line = line.trim_end_matches('\r');
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let mut parts = line.splitn(2, '\t');
        let (input, expected) = (parts.next().unwrap(), parts.next().unwrap_or(""));
        let mut engine = Engine::new();
        engine.set_config(cfg.clone());
        if let Some(json) = macros_json {
            engine.set_macros(MacroTable::from_json(json));
        }
        let got = type_string(&mut engine, input);
        if got != expected {
            failures.push(format!(
                "{file}:{}: typed {input:?} → got {got:?}, want {expected:?}",
                ln + 1
            ));
        }
    }
    assert!(failures.is_empty(), "\n{}", failures.join("\n"));
}

fn telex_cfg() -> Config {
    Config { method: Method::Telex, tone_style: ToneStyle::Old, ..Config::default() }
}

#[test]
fn telex_basic() {
    run_corpus("telex_basic.tsv", telex_cfg(), None);
}

#[test]
fn vni_basic() {
    let cfg = Config { method: Method::Vni, ..telex_cfg() };
    run_corpus("vni_basic.tsv", cfg, None);
}

#[test]
fn english_restore() {
    run_corpus("english_restore.tsv", telex_cfg(), None);
}

#[test]
fn edge_cases() {
    run_corpus("edge_cases.tsv", telex_cfg(), None);
}

#[test]
fn known_limitations() {
    // Locks in the documented UniKey-compatible tradeoffs so any behavior
    // change is a conscious decision, not an accident.
    run_corpus("known_limitations.tsv", telex_cfg(), None);
}

#[test]
fn quick_telex() {
    let cfg = Config { quick_telex: true, ..telex_cfg() };
    run_corpus("quick_telex.tsv", cfg, None);
}

#[test]
fn tone_styles() {
    // three columns: style<TAB>keystrokes<TAB>expected
    let path = format!("{}/tests/corpus/tone_styles.tsv", env!("CARGO_MANIFEST_DIR"));
    let data = std::fs::read_to_string(&path).unwrap();
    let mut failures = Vec::new();
    for (ln, line) in data.lines().enumerate() {
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let cols: Vec<&str> = line.splitn(3, '\t').collect();
        let (style, input, expected) = (cols[0], cols[1], cols[2]);
        let cfg = Config {
            tone_style: if style == "new" { ToneStyle::New } else { ToneStyle::Old },
            ..telex_cfg()
        };
        let mut engine = Engine::new();
        engine.set_config(cfg);
        let got = type_string(&mut engine, input);
        if got != expected {
            failures.push(format!(
                "tone_styles.tsv:{}: [{style}] {input:?} → {got:?}, want {expected:?}",
                ln + 1
            ));
        }
    }
    assert!(failures.is_empty(), "\n{}", failures.join("\n"));
}

#[test]
fn macros_expand() {
    let json = r#"{"btw": "by the way", "vn": "Việt Nam", "mail": "phamkynguyen753@gmail.com"}"#;
    run_corpus("macros.tsv", telex_cfg(), Some(json));
}

#[test]
fn auto_capitalize() {
    let cfg = Config { auto_capitalize: true, ..telex_cfg() };
    run_corpus("autocaps.tsv", cfg, None);
}

#[test]
fn permutation_tone_position() {
    // The tone key may come right after the nucleus or at the end of the
    // word — the result must be identical.
    let cases = [
        (vec!["vieejt", "vieetj"], "việt"),
        (vec!["hoawjc", "hoacwj", "hoawcj"], "hoặc"),
        (vec!["truowngf", "truwowngf", "truowfng"], "trường"),
        (vec!["toans", "toasn"], "toán"),
        (vec!["nguyeenx", "nguyeexn"], "nguyễn"),
    ];
    for (inputs, want) in cases {
        for input in inputs {
            let mut engine = Engine::new();
            engine.set_config(telex_cfg());
            let got = type_string(&mut engine, input);
            assert_eq!(got, want, "input {input:?}");
        }
    }
}

#[test]
fn long_word_goes_inert() {
    let mut engine = Engine::new();
    engine.set_config(telex_cfg());
    let input = "b".repeat(40);
    let got = type_string(&mut engine, &input);
    // must not panic and must not keep transforming forever
    assert_eq!(got, input);
}

#[test]
fn disabled_engine_passes_everything() {
    let mut engine = Engine::new();
    engine.set_config(Config { enabled: false, ..telex_cfg() });
    let got = type_string(&mut engine, "vieejt nam");
    assert_eq!(got, "vieejt nam");
}
