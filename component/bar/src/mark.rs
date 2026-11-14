//! Spark's mark on disk: the approved artwork in the `asset` folder beside spark-shell, never redrawn.

use crate::bar;
use std::os::unix::fs::DirBuilderExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

/// Spark's mark at `px` device pixels, the dark ground's or the light one's: the PNG nearest the size at
/// or above it; past the largest, the SVG drawn at the size by rsvg-convert into a cache under
/// XDG_RUNTIME_DIR, else the largest PNG, scaled. None when the assets are not there.
pub fn file(spark_shell: &str, dark: bool, px: i32) -> Option<String> {
    let dir = Path::new(spark_shell).parent().filter(|d| !d.as_os_str().is_empty())?.join("asset");
    let file = dir.join(bar::mark_file(dark, px));
    let largest = dir.join(bar::mark_file(dark, bar::MARK_PNGS[bar::MARK_PNGS.len() - 1]));
    let drawn = if file.extension().is_some_and(|e| e == "svg") {
        svg_at(&file, px)
    } else {
        Some(file).filter(|f| f.is_file())
    };
    drawn
        .or_else(|| Some(largest).filter(|f| f.is_file()))
        .map(|f| f.to_string_lossy().into_owned())
}

/// An SVG drawn at `px` square by rsvg-convert, kept under XDG_RUNTIME_DIR and drawn again only when the SVG is
/// newer than what is kept. None without rsvg-convert, the runtime folder or a PNG out of it.
fn svg_at(svg: &Path, px: i32) -> Option<PathBuf> {
    let run = std::env::var_os("XDG_RUNTIME_DIR").filter(|d| !d.is_empty())?;
    let made = std::fs::metadata(svg).and_then(|m| m.modified()).ok()?;
    let dir = PathBuf::from(run).join("spark-shell-bar.icons");
    std::fs::DirBuilder::new().recursive(true).mode(0o700).create(&dir).ok()?;
    let name = format!("{}-{px}.png", svg.file_stem()?.to_string_lossy());
    let out = dir.join(&name);
    if std::fs::metadata(&out).and_then(|m| m.modified()).is_ok_and(|kept| kept >= made) {
        return Some(out);
    }
    let size = px.clamp(8, 512).to_string();
    let got = Command::new("rsvg-convert")
        .args(["-w", &size, "-h", &size])
        .arg(svg)
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()
        .ok()?;
    if !got.status.success() || !got.stdout.starts_with(b"\x89PNG\r\n\x1a\n") {
        return None;
    }
    let part = dir.join(format!(".{name}.{}", std::process::id()));
    std::fs::write(&part, &got.stdout).ok()?;
    std::fs::rename(&part, &out).ok()?;
    Some(out)
}
