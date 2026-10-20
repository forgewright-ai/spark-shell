// The tests' own pieces: the two palettes the records name, a stub MCP
// server on in-process pipes, and a pump that feeds its messages to the app.
#![allow(dead_code)]

use ratatui::buffer::{Buffer, CellDiffOption};
use ratatui::style::{Color, Modifier};
use serde_json::{json, Value};
use spark_dialog::app::{App, Config};
use spark_dialog::mcp::{Incoming, Server};
use spark_dialog::palette::Palette;
use spark_dialog::scrub::cells;
use std::io::{BufRead, BufReader, Write};
use std::sync::mpsc::{sync_channel, Receiver};
use std::time::{Duration, Instant};

pub fn palette(name: &str) -> Palette {
    let t: &[(&str, &str)] = match name {
        "tokyonight-night" => &[
            ("HEX_FG", "c0caf5"),
            ("HEX_ACCENT", "7aa2f7"),
            ("PANEL_MUTED", "7b84ae"),
            ("PANEL_BG", "282a38"),
            ("PANEL_HI", "373a4b"),
            ("HEX_ANSI_1", "f7768e"),
            ("HEX_ANSI_2", "9ece6a"),
        ],
        _ => &[
            ("HEX_FG", "657b83"),
            ("HEX_ACCENT", "268bd2"),
            ("PANEL_MUTED", "839497"),
            ("PANEL_BG", "f0ebdb"),
            ("PANEL_HI", "e2e0d2"),
            ("HEX_ANSI_1", "dc322f"),
            ("HEX_ANSI_2", "859900"),
        ],
    };
    Palette::from(|k| t.iter().find(|(a, _)| *a == k).map(|(_, v)| v.to_string()))
}

pub type Script = Box<dyn FnMut(&Value, &mut dyn FnMut(Value)) + Send>;

/// A stub provider: `script` answers each request it is sent (it may send
/// requests and notifications of its own through the writer it is handed).
pub fn stub(idx: usize, label: &str, mut script: Script, tx: std::sync::mpsc::SyncSender<Incoming>) -> Server {
    let (from_host, to_stub) = std::io::pipe().unwrap();
    let (from_stub, to_host) = std::io::pipe().unwrap();
    std::thread::spawn(move || {
        let mut out = to_host;
        let r = BufReader::new(from_host);
        for line in r.lines() {
            let Ok(line) = line else { return };
            let Ok(v) = serde_json::from_str::<Value>(&line) else { continue };
            let mut send = |m: Value| {
                let _ = writeln!(out, "{}", m);
                let _ = out.flush();
            };
            script(&v, &mut send);
        }
    });
    Server::on_pipes(idx, label, from_stub, to_stub, tx)
}

pub fn result(id: &Value, r: Value) -> Value {
    json!({"jsonrpc": "2.0", "id": id, "result": r})
}

/// The ordinary answers: initialize, tools, rows; None for anything else.
pub fn ordinary(label: &str, v: &Value, tools: &Value, rows: &Value) -> Option<Value> {
    let id = v.get("id")?;
    match v.get("method")?.as_str()? {
        "initialize" => Some(result(
            id,
            json!({"protocolVersion": "2025-06-18", "capabilities": {"tools": {}, "resources": {"subscribe": true}}, "serverInfo": {"name": label, "title": format!("{} now", label), "version": "1"}}),
        )),
        "tools/list" => Some(result(id, json!({"tools": tools}))),
        "resources/read" => Some(result(
            id,
            json!({"contents": [{"uri": format!("spark-shell://{}/rows", label), "mimeType": "application/json", "text": rows.to_string()}]}),
        )),
        "resources/subscribe" => Some(result(id, json!({}))),
        _ => None,
    }
}

pub fn app_with(labels: &[&str]) -> (App, Receiver<Incoming>, std::sync::mpsc::SyncSender<Incoming>) {
    let (tx, rx) = sync_channel(256);
    let cfg = Config {
        model: false,
        talk: false,
        ..Config::default()
    };
    let app = App::new(cfg, &labels.iter().map(|s| s.to_string()).collect::<Vec<_>>());
    (app, rx, tx)
}

/// Feed the app what the stubs say until `done` holds, two seconds at most.
pub fn pump(app: &mut App, rx: &Receiver<Incoming>, done: impl Fn(&App) -> bool) -> bool {
    let end = Instant::now() + Duration::from_secs(2);
    while Instant::now() < end {
        if done(app) {
            return true;
        }
        if let Ok(m) = rx.recv_timeout(Duration::from_millis(20)) {
            app.incoming(m);
        }
        app.tick(Instant::now());
    }
    done(app)
}

/// A rendered buffer as HTML in its real colors, for a person to look at
/// before a golden is kept and for the design system's preview: one span
/// per run of one style, a glyph outside ASCII held to one cell, the
/// mark's cells one image (`mark`, its URL).
pub fn html_runs(buf: &Buffer, pal: &Palette, caption: &str, mark: &str) -> String {
    let hex = |c: Color, d: Color| match if c == Color::Reset { d } else { c } {
        Color::Rgb(r, g, b) => format!("#{:02x}{:02x}{:02x}", r, g, b),
        _ => "inherit".into(),
    };
    let esc = |s: &str| s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;");
    let mut out = format!(
        "<div><p style=\"color:{};font-size:13px;margin:0 0 8px\">{}</p><div style=\"background:{};padding:19px 2ch;white-space:pre;width:{}ch;line-height:19px\">",
        hex(pal.muted, pal.muted),
        esc(caption),
        hex(pal.surface, pal.surface),
        buf.area.width
    );
    let (w, h) = (buf.area.width, buf.area.height);
    for y in 0..h {
        let mut run = String::new();
        let mut style = String::new();
        let mut skip = 0;
        let mut x = 0;
        while x < w {
            let c = &buf[(x, y)];
            if c.diff_option == CellDiffOption::Skip {
                let mut n = 0;
                while x < w && buf[(x, y)].diff_option == CellDiffOption::Skip {
                    n += 1;
                    x += 1;
                }
                if !run.is_empty() {
                    out.push_str(&format!("<span style=\"{}\">{}</span>", style, run));
                    run.clear();
                }
                out.push_str(&format!("<img src=\"{}\" alt=\"\" style=\"display:inline-block;width:{}ch;height:19px;vertical-align:bottom;object-fit:contain;object-position:left\">", esc(mark), n));
                continue;
            }
            if skip > 0 {
                skip -= 1;
                x += 1;
                continue;
            }
            let sym = c.symbol();
            let sym = if sym.is_empty() { " " } else { sym };
            skip = cells(sym).saturating_sub(1);
            let bold = if c.modifier.contains(Modifier::BOLD) { "font-weight:700;" } else { "" };
            let st = format!("color:{};background:{};{}", hex(c.fg, pal.fg), hex(c.bg, pal.surface), bold);
            if st != style && !run.is_empty() {
                out.push_str(&format!("<span style=\"{}\">{}</span>", style, run));
                run.clear();
            }
            style = st;
            if sym.is_ascii() {
                run.push_str(&esc(sym));
            } else {
                run.push_str(&format!(
                    "<span style=\"display:inline-block;width:{}ch;text-align:center\">{}</span>",
                    cells(sym).max(1),
                    esc(sym)
                ));
            }
            x += 1;
        }
        if !run.is_empty() {
            out.push_str(&format!("<span style=\"{}\">{}</span>", style, run));
        }
        out.push('\n');
    }
    out.push_str("</div></div>");
    out
}
