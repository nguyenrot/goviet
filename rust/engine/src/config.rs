//! Engine configuration — single source of truth, mirrored in Swift as JSON.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Method {
    Telex,
    SimpleTelex,
    Vni,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ToneStyle {
    /// òa, úy — kiểu cũ (UniKey default)
    Old,
    /// oà, uý — kiểu mới (sách giáo khoa 2022)
    New,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Config {
    pub enabled: bool,
    pub method: Method,
    pub tone_style: ToneStyle,
    pub quick_telex: bool,
    pub english_auto_restore: bool,
    pub esc_restores_raw: bool,
    pub auto_capitalize: bool,
    pub macros_enabled: bool,
}

impl Default for Config {
    fn default() -> Self {
        Config {
            enabled: true,
            method: Method::Telex,
            tone_style: ToneStyle::Old,
            quick_telex: false,
            english_auto_restore: true,
            esc_restores_raw: true,
            auto_capitalize: false,
            macros_enabled: true,
        }
    }
}
