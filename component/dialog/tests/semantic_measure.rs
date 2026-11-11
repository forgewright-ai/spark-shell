//! Semantic search measured on the real thing (v0.130): the providers spark-shell starts, the dialog's own
//! candidates, the model spark-shell serves, and the frozen requests in test/semantic_cases.json. Run by hand with
//! a scratch home, as test/semantic_measure.sh does; CI skips it (it needs the model).
use serde_json::{json, Value};
use spark_dialog::app::{App, Config, Helper, Item, Job, DESTS, SETTINGS};
use spark_dialog::mcp::Server;
use spark_dialog::semantic;
use std::sync::mpsc::sync_channel;
use std::time::{Duration, Instant};

/// The sections spark-shell's dialog starts, in its order (dialog_sections, then files and clock).
const SECTIONS: &[&str] = &[
    "apps",
    "printers",
    "layout",
    "notes",
    "reminders",
    "window",
    "display",
    "keyboard",
    "pointer",
    "notifications",
    "out",
    "mic",
    "bt",
    "wifi",
    "storage",
    "theme",
    "bar",
    "power",
    "tools",
    "files",
    "about",
    "clock",
];

/// The names a case may give the thing it wants: a place, a setting, a tools page, a row's own step, a step.
fn ids(app: &App, it: &Item) -> Vec<String> {
    match it {
        Item::Dest(d) => vec![format!("page:{}", DESTS[*d].name)],
        Item::Setting(i) => vec![format!("page:settings/{}", SETTINGS[*i].0)],
        Item::Apps(_) => vec!["apps_open".into()],
        Item::Step(_, name) => vec![name.clone()],
        Item::Row(p, r) => {
            let prov = &app.providers[*p];
            let row = &prov.rows.rows[*r];
            let mut out = vec![format!("row:{}/{}", prov.label, row.id)];
            if prov.label == "tools" {
                out.push(format!("page:tools/{}", row.text));
            }
            out.extend(row.tool.iter().map(|c| c.name.clone()));
            out
        }
        _ => vec![],
    }
}

#[test]
#[ignore]
fn semantic_search_on_the_frozen_requests() {
    let (Ok(repo), Ok(sock), Ok(cases)) = (
        std::env::var("SPARK_SHELL_REPO"),
        std::env::var("SPARK_SHELL_SEMANTIC_SOCK"),
        std::env::var("SPARK_SHELL_SEMANTIC_CASES"),
    ) else {
        panic!("SPARK_SHELL_REPO, SPARK_SHELL_SEMANTIC_SOCK and SPARK_SHELL_SEMANTIC_CASES name what to measure");
    };
    let cases: Vec<(String, Vec<String>)> = serde_json::from_str(&std::fs::read_to_string(cases).unwrap()).unwrap();
    let (tx, rx) = sync_channel(256);
    let labels: Vec<String> = SECTIONS.iter().map(|s| s.to_string()).collect();
    let cfg = Config {
        talk: false,
        spark_shell: format!("{}/spark-shell", repo),
        ..Config::default()
    };
    let mut app = App::new(cfg, &labels);
    for (i, label) in SECTIONS.iter().enumerate() {
        let argv = vec![format!("{}/spark-shell", repo), "provide".into(), label.to_string()];
        if let Ok(s) = Server::spawn(i, label, &argv, tx.clone()) {
            app.servers.push(s);
        }
    }
    app.start();
    let end = Instant::now() + Duration::from_secs(60);
    while Instant::now() < end && app.providers.iter().any(|p| p.dead.is_none() && !p.ready) {
        if let Ok(m) = rx.recv_timeout(Duration::from_millis(50)) {
            app.incoming(m);
        }
        app.tick(Instant::now());
    }
    // the app catalog, as the dialog reads it at the home (its tick asks for it there)
    if !app.jobs.iter().any(|j| matches!(j, Job::RunInput(Helper::Apps(_), ..))) {
        app.apps_request(json!({"op": "catalog"}));
    }
    for j in std::mem::take(&mut app.jobs) {
        if let Job::RunInput(Helper::Apps(serial), argv, input) = j {
            let out = spark_dialog::helper::invoke_apps(&argv, input);
            app.helper(Helper::Apps(serial), out);
        }
    }
    let (items, texts): (Vec<Item>, Vec<String>) = app.candidates().into_iter().unzip();
    let ready: Vec<&str> = app.providers.iter().filter(|p| p.ready).map(|p| p.label.as_str()).collect();
    let t0 = Instant::now();
    semantic::rank(&sock, "", &texts).unwrap();
    let mut out = format!(
        "{} candidates from {} ready providers ({}), {} apps; their vectors made in {:.1} s\n\n",
        items.len(),
        ready.len(),
        ready.join(" "),
        app.apps.entries.len(),
        t0.elapsed().as_secs_f32()
    );
    let (mut first, mut five, mut lit_right, mut lit_wrong, mut asks, mut through, mut ms) = (0, 0, 0, 0, 0, 0, vec![]);
    let mut fills: Vec<(String, usize, String)> = vec![];
    let real = cases.iter().filter(|(_, ok)| !ok.is_empty()).count();
    for (words, ok) in &cases {
        let t = Instant::now();
        let scores = semantic::rank(&sock, words, &texts).unwrap();
        ms.push(t.elapsed().as_millis());
        let mut best: Vec<(f32, &Item)> = scores.into_iter().zip(&items).collect();
        best.sort_by(|a, b| b.0.total_cmp(&a.0));
        let hit = |k: usize| best.iter().take(k).any(|(_, it)| ids(&app, it).iter().any(|i| ok.contains(i)));
        let top = best[0].1;
        let lit = best[0].0 >= semantic::LIT;
        let said = format!("{:.3} {}", best[0].0, ids(&app, top).first().cloned().unwrap_or_default());
        if ok.is_empty() {
            through += lit as usize;
            out += &format!("{} {:<45} {}\n", if lit { "lit" } else { "ask" }, words, said);
            continue;
        }
        if let (true, Item::Step(p, name)) = (lit, top) {
            fills.push((words.clone(), *p, name.clone()));
        }
        first += hit(1) as usize;
        five += hit(semantic::TOP) as usize;
        match (lit, hit(1)) {
            (true, true) => lit_right += 1,
            (true, false) => lit_wrong += 1,
            (false, _) => asks += 1,
        }
        out += &format!(
            "{} {:<45} {}\n",
            if hit(1) {
                "+"
            } else if hit(semantic::TOP) {
                "5"
            } else {
                "-"
            },
            words,
            said
        );
    }
    ms.sort();
    out += &format!(
        "\n{} requests: right first {}, in the first {} {}; lit and right {}, lit and wrong {}, left to the ask row {}\n\
         {} words that ask the desktop nothing: lit {} (the rest go to the ask row)\n\
         a query: median {} ms, slowest {} ms\n",
        real,
        first,
        semantic::TOP,
        five,
        lit_right,
        lit_wrong,
        asks,
        cases.len() - real,
        through,
        ms[ms.len() / 2],
        ms[ms.len() - 1]
    );
    // slot filling: each lit step, its values read by the real spark as the dialog asks (SPARK_SHELL_MEASURE_SPARK)
    if let Ok(spark) = std::env::var("SPARK_SHELL_MEASURE_SPARK") {
        out += "\nslot filling, the lit steps that take values:\n";
        for (words, p, name) in &fills {
            let tool = app.providers[*p].tools.iter().find(|t| &t.name == name).unwrap().clone();
            if tool.schema.get("properties").and_then(Value::as_object).is_none_or(|m| m.is_empty()) {
                continue;
            }
            let one = json!({"tools": [{"name": tool.name, "title": tool.title, "description": tool.description, "inputSchema": tool.schema}]});
            let argv = vec![
                spark.clone(),
                "steps".into(),
                "--about".into(),
                app.fill_about(*p, &tool, words),
                "--".into(),
                words.clone(),
            ];
            let t = Instant::now();
            let got = spark_dialog::helper::invoke(&argv, one.to_string()).unwrap_or_else(|e| e);
            let v: Value = serde_json::from_str(&got).unwrap_or(Value::Null);
            let steps = v.get("steps").and_then(Value::as_array).cloned().unwrap_or_default();
            let said = match steps.first() {
                Some(s) => format!("{} {}", name, s["arguments"]),
                None => format!("{}: no step, its values asked", name),
            };
            out += &format!("  {:<45} {:4.1} s  {}\n", words, t.elapsed().as_secs_f32(), said);
        }
    }
    print!("{}", out);
    if let Ok(path) = std::env::var("SPARK_SHELL_SEMANTIC_OUT") {
        std::fs::write(path, &out).unwrap();
    }
}
