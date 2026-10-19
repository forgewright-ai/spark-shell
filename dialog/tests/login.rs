// The login screen: greetd's whole flow against a stub greetd on a
// socket pair, and the golden renders of its three views in the two
// palettes the records name, at the box's 176 by 49 cells.
// UPDATE_GOLDEN=1 writes the files after a change that was looked at.
mod common;
use common::palette;
use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use serde_json::{json, Value};
use spark_dialog::greetd::{self, Outcome, Secret};
use spark_dialog::login::{Field, Key, Login, Note, Power, View};
use spark_dialog::login_ui;
use std::os::unix::net::UnixStream;

/// A stub greetd: `answers` is what it says after each message it reads,
/// in order; it hands back every message it was sent.
fn stub(answers: Vec<Value>) -> (UnixStream, std::thread::JoinHandle<Vec<Value>>) {
    let (ours, mut theirs) = UnixStream::pair().unwrap();
    let h = std::thread::spawn(move || {
        let mut got = vec![];
        for a in answers {
            match greetd::recv(&mut theirs) {
                Ok(v) => got.push(v),
                Err(_) => break,
            }
            greetd::send(&mut theirs, a.to_string().as_bytes()).unwrap();
        }
        got
    });
    (ours, h)
}

fn secret(s: &str) -> Secret {
    let mut p = Secret::new();
    for c in s.chars() {
        p.push(c);
    }
    p
}

fn shell() -> Vec<String> {
    vec!["/bin/bash".into(), "-l".into()]
}

#[test]
fn a_right_password_starts_the_session() {
    let (mut s, h) = stub(vec![
        json!({"type": "auth_message", "auth_message_type": "secret", "auth_message": "Password: "}),
        json!({"type": "success"}),
        json!({"type": "success"}),
    ]);
    let env = vec!["SPARK_SHELL_SESSION=shell".to_string()];
    assert_eq!(greetd::log_in(&mut s, "w", &secret("pw"), &shell(), &env), Outcome::Started);
    let got = h.join().unwrap();
    assert_eq!(got[0], json!({"type": "create_session", "username": "w"}));
    assert_eq!(got[1], json!({"type": "post_auth_message_response", "response": "pw"}));
    assert_eq!(
        got[2],
        json!({"type": "start_session", "cmd": ["/bin/bash", "-l"], "env": ["SPARK_SHELL_SESSION=shell"]})
    );
}

#[test]
fn an_info_message_is_answered_with_nothing() {
    let (mut s, h) = stub(vec![
        json!({"type": "auth_message", "auth_message_type": "info", "auth_message": "Last login: today"}),
        json!({"type": "auth_message", "auth_message_type": "secret", "auth_message": "Password: "}),
        json!({"type": "success"}),
        json!({"type": "success"}),
    ]);
    assert_eq!(greetd::log_in(&mut s, "w", &secret("pw"), &shell(), &[]), Outcome::Started);
    let got = h.join().unwrap();
    assert_eq!(got[1], json!({"type": "post_auth_message_response", "response": null}));
    assert_eq!(got[3]["env"], json!([]));
}

#[test]
fn a_wrong_password_cancels_the_session() {
    let (mut s, h) = stub(vec![
        json!({"type": "auth_message", "auth_message_type": "secret", "auth_message": "Password: "}),
        json!({"type": "error", "error_type": "auth_error", "description": "pam_authenticate: AUTH_ERR"}),
        json!({"type": "success"}),
    ]);
    assert_eq!(greetd::log_in(&mut s, "w", &secret("nope"), &shell(), &[]), Outcome::Wrong);
    let got = h.join().unwrap();
    assert_eq!(got[2], json!({"type": "cancel_session"}));
}

#[test]
fn a_second_prompt_is_refused() {
    let (mut s, h) = stub(vec![
        json!({"type": "auth_message", "auth_message_type": "secret", "auth_message": "Password: "}),
        json!({"type": "auth_message", "auth_message_type": "secret", "auth_message": "Code: "}),
        json!({"type": "success"}),
    ]);
    assert_eq!(greetd::log_in(&mut s, "w", &secret("pw"), &shell(), &[]), Outcome::More);
    let got = h.join().unwrap();
    assert_eq!(got[2], json!({"type": "cancel_session"}));
}

#[test]
fn another_error_carries_greetd_words_on_one_line() {
    let (mut s, _h) = stub(vec![
        json!({"type": "error", "error_type": "error", "description": "no\nsuch user \u{1b}[2J"}),
        json!({"type": "success"}),
    ]);
    match greetd::log_in(&mut s, "x", &secret("pw"), &shell(), &[]) {
        Outcome::Failed(why) => assert_eq!(why, "nosuch user [2J"),
        o => panic!("{:?}", o),
    }
}

#[test]
fn a_closed_socket_is_a_failure_not_a_hang() {
    let (mut s, theirs) = UnixStream::pair().unwrap();
    drop(theirs);
    assert!(matches!(greetd::log_in(&mut s, "w", &secret("pw"), &shell(), &[]), Outcome::Failed(_)));
}

/// The screen in its real colors over the palette's wallpaper, for a person to look at before a golden is kept.
fn html(b: &Buffer, p: &spark_dialog::palette::Palette, pal: &str) -> String {
    use ratatui::style::{Color, Modifier};
    let hex = |c: Color| match c {
        Color::Rgb(r, g, b) => format!("#{:02x}{:02x}{:02x}", r, g, b),
        _ => "transparent".into(),
    };
    let wall = if pal == "tokyonight-night" { "skyline" } else { "morning" };
    let fg = hex(p.fg);
    let mut out = format!(
        "<!doctype html><meta charset=utf-8><style>body{{margin:0;width:1920px;height:1080px;background:url(../wall/{}.png) center/cover;font:18px 'DejaVu Sans Mono',Menlo,monospace;line-height:22px}}.r{{height:22px;white-space:pre}}.r span{{display:inline-block;height:22px;vertical-align:top}}</style><body>",
        wall
    );
    for y in 0..b.area.height {
        out.push_str("<div class=r>");
        for x in 0..b.area.width {
            let c = &b[(x, y)];
            let sym = c.symbol();
            let col = if c.fg == Color::Reset { fg.clone() } else { hex(c.fg) };
            let bold = if c.modifier.contains(Modifier::BOLD) { "font-weight:700;" } else { "" };
            out.push_str(&format!(
                "<span style=\"width:1ch;color:{};background:{};{}\">{}</span>",
                col,
                hex(c.bg),
                bold,
                if sym.is_empty() || sym == " " {
                    "&nbsp;".to_string()
                } else {
                    sym.replace('&', "&amp;").replace('<', "&lt;")
                }
            ));
        }
        out.push_str("</div>");
    }
    out
}

const CLOCK: &str = "Sunday, October 18 \u{b7} 14:32";

fn base() -> Login {
    let mut l = Login::new("void", "Void Linux \u{b7} kernel 6.18.54");
    l.spark = Some(true);
    l.can_restart = true;
    l.can_shutdown = true;
    l.user = "ada".into();
    l.field = Field::Password;
    l
}

fn render(l: &Login, name: &str) {
    let mut grids = vec![];
    for pal in ["tokyonight-night", "solarized-light"] {
        let p = palette(pal);
        let mut b = Buffer::empty(Rect::new(0, 0, 176, 49));
        login_ui::draw(l, &p, CLOCK, &mut b);
        if let Ok(dir) = std::env::var("RENDER_HTML") {
            std::fs::write(format!("{}/{}-{}.html", dir, name, pal), html(&b, &p, pal)).unwrap();
        }
        let s = login_ui::snapshot(&b, &p);
        assert!(!s.contains('?'), "{} in {}: a color that is no slot of the palette\n{}", name, pal, s);
        grids.push(s);
    }
    assert_eq!(grids[0], grids[1], "{}: the two palettes draw different grids", name);
    let path = format!("{}/tests/golden/{}.txt", env!("CARGO_MANIFEST_DIR"), name);
    if std::env::var("UPDATE_GOLDEN").is_ok() {
        std::fs::write(&path, &grids[0]).unwrap();
    }
    let want = std::fs::read_to_string(&path).unwrap_or_default();
    assert_eq!(grids[0], want, "{} differs from {} (UPDATE_GOLDEN=1 after looking at it)", name, path);
}

#[test]
fn login_typing_the_password() {
    let mut l = base();
    for c in "secret-pw".chars() {
        l.key(Key::Char(c));
    }
    render(&l, "login");
}

#[test]
fn login_after_a_wrong_password() {
    let mut l = base();
    l.outcome(Outcome::Wrong);
    assert!(matches!(l.note, Some(Note::Wrong(_))));
    render(&l, "login-wrong");
}

#[test]
fn login_shut_down_asks_for_yes() {
    let mut l = base();
    l.key(Key::F(12));
    assert_eq!(l.view, View::Confirm(Power::Shutdown));
    render(&l, "login-off");
}

#[test]
fn login_with_no_desktop_and_no_spark() {
    let mut l = base();
    l.desktop = false;
    l.spark = None;
    l.can_restart = false;
    render(&l, "login-shell");
}
