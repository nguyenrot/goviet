//! Gõ tắt (text macros): trigger → expansion, matched at word commit.

use std::collections::HashMap;

#[derive(Debug, Default, Clone)]
pub struct MacroTable {
    map: HashMap<String, String>,
}

impl MacroTable {
    pub fn from_json(json: &str) -> Self {
        let map: HashMap<String, String> = serde_json::from_str(json).unwrap_or_default();
        let map = map
            .into_iter()
            .map(|(k, v)| (k.to_lowercase(), v))
            .collect();
        MacroTable { map }
    }

    pub fn is_empty(&self) -> bool {
        self.map.is_empty()
    }

    /// Look up `word` case-insensitively; adapt the expansion's case to how
    /// the trigger was typed (ALL CAPS / Capitalized / as-is).
    pub fn expand(&self, word: &str) -> Option<String> {
        let expansion = self.map.get(&word.to_lowercase())?;
        let chars: Vec<char> = word.chars().collect();
        let all_upper = chars.len() > 1 && chars.iter().all(|c| !c.is_lowercase());
        let first_upper = chars.first().is_some_and(|c| c.is_uppercase());
        if all_upper {
            Some(expansion.to_uppercase())
        } else if first_upper {
            let mut out = String::with_capacity(expansion.len());
            let mut cs = expansion.chars();
            if let Some(f) = cs.next() {
                out.extend(f.to_uppercase());
            }
            out.push_str(cs.as_str());
            Some(out)
        } else {
            Some(expansion.clone())
        }
    }
}
