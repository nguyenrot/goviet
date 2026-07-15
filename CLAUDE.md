# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

GõViệt — a Vietnamese input method (IME) for macOS in the style of Unikey on Windows: a menu-bar background app that intercepts keystrokes system-wide via CGEventTap. Rust engine (pure logic) + Swift shell (macOS integration). User-facing docs (README, packaging, docs/) are written in Vietnamese; keep that convention.

## Commands

Prereqs: Xcode, Rust via rustup, `brew install xcodegen cbindgen`.

```bash
make test      # cargo fmt --check + test + clippy --all-targets -- -D warnings
make core      # universal arm64+x86_64 Rust lib + regenerate goviet.h
make install   # full pipeline: core → xcodegen → xcodebuild → codesign → /Applications → open
make dmg       # package build/GoViet-<version>.dmg
make watch     # stream runtime logs (subsystem com.kynguyen.goviet)
```

Single test (from `rust/`): `cargo test --test corpus_test english_restore`, or a unit test by name, e.g. `cargo test -p goviet-engine permutation_tone_position`.

Most engine tests are **data-driven TSV corpora** in `rust/engine/tests/corpus/*.tsv` (format: `keystrokes<TAB>expected`; `⌫` = backspace, `⎋` = escape). To cover a new typing scenario, add a TSV row to the matching corpus rather than writing new test code. `known_limitations.tsv` documents accepted UniKey-compatible misbehavior (English words that are valid Vietnamese syllables) — don't "fix" entries there without understanding the tradeoff.

The Swift shell has no automated tests; after significant shell changes run the manual matrix in `docs/TESTING.md` (per-app typing checks, tap watchdog recovery, permission persistence).

## Architecture

Keystroke flow: CGEventTap callback (`macos/Sources/Tap/EventTapManager.swift`) → `EngineBridge.processKey` → C ABI `vk_process_key` (`rust/ffi/src/lib.rs`) → `Engine::process_key` (`rust/engine/src/engine.rs`) → returns an `Action` (`PassThrough` or `Replace { backspaces, text, forward }`) → `TextInjector` posts synthetic backspaces + text. Fast/Chromium paths post at the tap point; the paced `.slow` path runs on a serial worker while the tap defers later physical events to preserve ordering without callback timeouts.

- **`rust/engine`** — pure Vietnamese input logic, zero macOS dependencies. `engine.rs` is the per-word state machine; `compose.rs`/`tone.rs`/`syllable.rs` handle Telex/VNI composition and tone placement; `validation.rs` (`valid_prefix`) is the syllable-spelling gate that drives auto-restore of English words; `macros.rs` (abbreviation expansion), `autocaps.rs` (sentence capitalization), `config.rs` (config parsed from JSON — **the Swift `SettingsStore` mirrors this JSON shape**; change them together).
- **`rust/ffi`** — C ABI over a single global `Mutex<Engine>`; results return by value (fixed `[u16; 256]` buffer, `VK_ACTION_REPLACE_LARGE` + `vk_copy_pending_text` for overflow) so the hot path never allocates across the boundary. After changing this crate's public surface, run `make core` to regenerate `macos/Generated/goviet.h`.
- **`macos/`** — Swift shell. `Tap/` owns the event tap on a dedicated thread with a watchdog that polls `tapIsEnabled` ("a non-nil tap is not a healthy tap"). `Inject/AppProfiles.swift` picks a per-bundle-id injection strategy: `.fast` default, `.slow` for terminals/Spotlight, `.selectAndRetype` for Chromium (omnibox autocomplete fights backspace bursts). `State/` holds per-app EN/VN mode memory, the ⌃⇧ toggle hotkey, secure-input detection, and settings persistence.

Generated artifacts are gitignored and must not be edited by hand: `macos/GoViet.xcodeproj/` comes from `xcodegen` reading `macos/project.yml` (edit the yml), and `macos/Generated/goviet.h` comes from cbindgen.

## Invariants

- **Signing identity is pinned** (`IDENTITY ?= Apple Development` in the Makefile) because macOS ties the Accessibility (TCC) permission to the code identity. Never sign ad-hoc and don't let Xcode sign (the xcodebuild step runs with `CODE_SIGNING_ALLOWED=NO`; only the Makefile `sign` target signs with hardened runtime). If permissions get stuck: `tccutil reset Accessibility com.kynguyen.goviet`.
- Every synthesized event is stamped with the `kGoVietEventMarker` ("GVIT") so the tap callback ignores the app's own events — this is the anti-race mechanism; preserve it in any new injection path.
- Behavior is modeled on UniKey and lessons from other IMEs, but no code was taken from GPL projects — see `docs/ATTRIBUTION.md` before borrowing anything.
