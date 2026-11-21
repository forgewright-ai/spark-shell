//! The shell and the native components must give the same colors to each shipped look.
use spark_theme::animation::Colors;
use spark_theme::palette::Palette;
use std::{collections::HashMap, env, fs, path::Path, process::Command};

#[test]
fn every_gallery_palette_matches_the_launcher() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let mut count = 0;
    for entry in fs::read_dir(root.join("gallery/theme")).unwrap() {
        let path = entry.unwrap().path();
        if path.extension().and_then(|s| s.to_str()) != Some("env") {
            continue;
        }
        // theme_load reads the palette and exports its resolved keys. No desktop, user files or installation.
        let shell = Command::new("sh")
            .current_dir(&root)
            .env_clear()
            .env("PATH", env::var_os("PATH").unwrap())
            .env("HOME", "/dev/null")
            .env("LC_ALL", "C")
            .args([
                "-ec",
                r#"
                REPO=$PWD
                . ./src/config.sh
                . ./src/terminal.sh
                . ./src/undo.sh
                . ./src/look.sh
                THEME_ENV=$1 WALLPAPER=none ALPHA=1 FONT=mono:size=12
                theme_load
                env
            "#,
                "gallery",
            ])
            .arg(&path)
            .output()
            .unwrap();
        assert!(shell.status.success(), "{}: {}", path.display(), String::from_utf8_lossy(&shell.stderr));
        let text = String::from_utf8(shell.stdout).unwrap();
        let keys: HashMap<_, _> = text.lines().filter_map(|line| line.split_once('=')).collect();
        let get = |k: &str| keys.get(k).map(|v| (*v).to_owned());
        let artwork = Colors::from_theme(get);
        assert_eq!(Some(&artwork), Colors::from_panel(get).as_ref(), "{}", path.display());
        let panel = Palette::from(get);
        assert_eq!(
            panel.ramp(),
            Some([artwork.surface, artwork.muted, artwork.accent, artwork.fg]),
            "{}",
            path.display()
        );
        let older_launcher = Palette::from(|k| if k == "PANEL_BAND" { None } else { get(k) });
        assert_eq!(panel.band, older_launcher.band, "{}", path.display());
        count += 1;
    }
    assert!(count > 0, "the gallery is empty");
}
