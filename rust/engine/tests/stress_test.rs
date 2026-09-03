use goviet_engine::{Action, Config, Engine, KeyInput, Method, ToneStyle};

const KC_BACKSPACE: u16 = 51;
const KC_ESCAPE: u16 = 53;
const KC_LEFT: u16 = 123;

/// Small deterministic generator: reproducible in CI and intentionally free
/// of a fuzzing dependency so it also runs in the normal `make test` path.
fn next(seed: &mut u64) -> u64 {
    *seed = seed.wrapping_mul(6_364_136_223_846_793_005).wrapping_add(1);
    *seed
}

fn apply(engine: &mut Engine, screen: &mut String, input: KeyInput) {
    let action = engine.process_key(input);
    match action {
        Action::PassThrough => match input.keycode {
            KC_BACKSPACE => {
                screen.pop();
            }
            KC_ESCAPE | KC_LEFT => {}
            _ if input.with_command => {}
            _ => {
                if let Some(c) = input.ch {
                    screen.push(c);
                }
            }
        },
        Action::Replace { backspaces, text, forward } => {
            let available = screen.chars().count();
            assert!(
                backspaces <= available,
                "engine requested {backspaces} backspaces with only {available} visible chars"
            );
            for _ in 0..backspaces {
                screen.pop();
            }
            screen.push_str(&text);
            if forward {
                if let Some(c) = input.ch {
                    screen.push(c);
                }
            }
        }
    }
}

#[test]
fn randomized_edit_sequences_never_over_delete_or_panic() {
    const CONTENT: &[char] = &[
        'a', 'd', 'e', 'i', 'o', 'u', 'y', 'w', 's', 'f', 'r', 'x', 'j', 'z', 'n', 'g', 'h',
        't', 'A', 'D', 'W', '1', '6', '7', '8', '9', 'é', '😀', ' ', '.', ',', '!', '?', '\n',
        '\t',
    ];
    let configurations = [
        Config::default(),
        Config { method: Method::SimpleTelex, quick_telex: true, ..Config::default() },
        Config { method: Method::Vni, tone_style: ToneStyle::New, ..Config::default() },
        Config {
            english_auto_restore: false,
            auto_capitalize: true,
            ..Config::default()
        },
    ];

    for (config_index, config) in configurations.into_iter().enumerate() {
        let mut seed = 0x4756_4954_u64 ^ config_index as u64;
        for _ in 0..2_000 {
            let mut engine = Engine::new();
            engine.set_config(config.clone());
            let mut screen = String::new();

            for _ in 0..80 {
                let choice = next(&mut seed) % 32;
                let input = match choice {
                    0..=2 => KeyInput {
                        keycode: KC_BACKSPACE,
                        ch: None,
                        with_command: false,
                    },
                    3 => KeyInput { keycode: KC_ESCAPE, ch: None, with_command: false },
                    4 => KeyInput { keycode: KC_LEFT, ch: None, with_command: false },
                    5 => KeyInput { keycode: 0, ch: Some('a'), with_command: true },
                    _ => {
                        let c = CONTENT[(next(&mut seed) as usize) % CONTENT.len()];
                        KeyInput { keycode: 0, ch: Some(c), with_command: false }
                    }
                };
                apply(&mut engine, &mut screen, input);

                if next(&mut seed).is_multiple_of(97) {
                    engine.reset_word();
                }
            }
        }
    }
}
