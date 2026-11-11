//! The record: one line per tools/call in the state directory, numbers
//! and names only (the review's M4). Never a title, an argument or a
//! receipt; a password field is not in the digest. A record that cannot
//! be written never stops the call.

use crate::gate::plain;
use serde_json::{Map, Value};
use std::io::Write;
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt, PermissionsExt};
use std::path::PathBuf;

pub fn path() -> Option<PathBuf> {
    let base = std::env::var("XDG_STATE_HOME")
        .ok()
        .filter(|s| s.starts_with('/'))
        .map(PathBuf::from)
        .or_else(|| std::env::var("HOME").ok().map(|h| PathBuf::from(h).join(".local/state")))?;
    Some(base.join("spark-shell").join("audit"))
}

/// The canonical arguments (keys sorted, no password field) as 12 hex digits.
pub fn digest(schema: &Value, args: &Map<String, Value>) -> String {
    let p = plain(schema, args);
    let sorted: std::collections::BTreeMap<_, _> = p.into_iter().collect();
    crate::sha256::hex(serde_json::to_string(&sorted).unwrap_or_default().as_bytes())[..12].to_string()
}

/// The line: the time, who asked (person, model, undo), the provider, the tool, the digest, whether it was refused.
pub fn line(ts: u64, who: &str, provider: &str, tool: &str, digest: &str, is_error: bool) -> String {
    format!(
        "{}\t{}\t{}\t{}\t{}\t{}\n",
        ts,
        who,
        provider,
        tool,
        digest,
        if is_error { "refused" } else { "done" }
    )
}

pub fn record(who: &str, provider: &str, tool: &str, schema: &Value, args: &Map<String, Value>, is_error: bool) {
    let Some(p) = path() else { return };
    let ts = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let l = line(ts, who, provider, tool, &digest(schema, args), is_error);
    if let Some(dir) = p.parent() {
        let _ = std::fs::DirBuilder::new().recursive(true).mode(0o700).create(dir);
    }
    if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).mode(0o600).open(&p) {
        let _ = f.set_permissions(std::fs::Permissions::from_mode(0o600));
        let _ = f.write_all(l.as_bytes());
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn the_digest_leaves_the_password_out_and_ignores_the_order() {
        let s = json!({"properties": {"name": {"type": "string"}, "password": {"type": "string", "format": "password"}}});
        let a = json!({"name": "cafe", "password": "hunter2"}).as_object().unwrap().clone();
        let b = json!({"name": "cafe"}).as_object().unwrap().clone();
        assert_eq!(digest(&s, &a), digest(&s, &b));
        assert_eq!(digest(&s, &b).len(), 12);
        let l = line(1, "model", "wifi", "wifi_connect", &digest(&s, &a), false);
        assert!(!l.contains("cafe") && !l.contains("hunter2"));
        assert_eq!(l.split('\t').count(), 6);
    }
}
