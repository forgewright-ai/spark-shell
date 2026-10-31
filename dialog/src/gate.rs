//! The gate: what the host checks before any tools/call it sends, the
//! same rules spark-shell's want and provide hold (the review's H2, H3).
//! Every rule is a named refusal with a test.

use crate::model::{Call, Rows, Tool};
use serde_json::{Map, Value};

/// A call's arguments against its tool's input schema: an object, no
/// argument the schema lacks, every required one there, each of its type.
/// Each refusal is plain words about the argument, never the tool.
pub fn schema_ok(schema: &Value, args: &Map<String, Value>) -> Result<(), String> {
    let props = schema.get("properties").and_then(Value::as_object).cloned().unwrap_or_default();
    for k in args.keys() {
        if !props.contains_key(k) {
            return Err(format!("it takes no {}", k));
        }
    }
    for r in schema.get("required").and_then(Value::as_array).cloned().unwrap_or_default() {
        if let Some(k) = r.as_str() {
            if !args.contains_key(k) {
                return Err(format!("it needs a {}", k));
            }
        }
    }
    for (k, v) in args {
        let p = &props[k];
        let ty = p.get("type").and_then(Value::as_str).unwrap_or("");
        let ok = match ty {
            "string" => v.as_str().map(|s| {
                let n = s.chars().count();
                n >= p.get("minLength").and_then(Value::as_u64).unwrap_or(0) as usize
                    && n <= p.get("maxLength").and_then(Value::as_u64).unwrap_or(256) as usize
                    && p.get("enum")
                        .and_then(Value::as_array)
                        .map(|e| e.iter().any(|x| x.as_str() == Some(s)))
                        .unwrap_or(true)
                    && text_controls_ok(p, s)
            }),
            "integer" => v.as_i64().map(|n| in_range(p, n as f64)),
            "number" => v.as_f64().map(|n| in_range(p, n)),
            "boolean" => v.as_bool().map(|_| true),
            _ => Some(false),
        };
        if ok != Some(true) {
            let said = v.as_str().map(str::to_string).unwrap_or_else(|| v.to_string());
            return Err(if secret(k, Some(p)) || said.chars().any(char::is_control) {
                format!("that is not a {} it takes", k)
            } else {
                format!("{} is not a {} it takes", crate::scrub::cut_words(&crate::scrub::scrub(&said), 40), k)
            });
        }
    }
    Ok(())
}

/// Literal text fields may carry ordinary text whitespace. Names, commands
/// and other strings keep the original no-controls rule.
pub fn plain_text(prop: &Value) -> bool {
    prop.get("type").and_then(Value::as_str) == Some("string") && prop.get("contentMediaType").and_then(Value::as_str) == Some("text/plain")
}

pub fn text_controls_ok(prop: &Value, text: &str) -> bool {
    let plain = plain_text(prop);
    text.chars().all(|c| !c.is_control() || (plain && matches!(c, '\n' | '\r' | '\t')))
}

fn in_range(p: &Value, n: f64) -> bool {
    p.get("minimum").and_then(Value::as_f64).map(|m| n >= m).unwrap_or(true) && p.get("maximum").and_then(Value::as_f64).map(|m| n <= m).unwrap_or(true)
}

/// Check the structured result against the provider's declared output schema.
/// Results are data: text may contain newlines. Unsupported schema constructs
/// fail explicitly instead of silently pretending to validate them.
pub fn result_ok(schema: &Value, value: &Value) -> Result<(), String> {
    fn valid(s: &Value, v: &Value, depth: usize) -> bool {
        if depth > 12 || !s.is_object() {
            return false;
        }
        if s.as_object().unwrap().keys().any(|k| {
            ![
                "type",
                "title",
                "description",
                "properties",
                "required",
                "additionalProperties",
                "items",
                "minItems",
                "maxItems",
                "minLength",
                "maxLength",
                "minimum",
                "maximum",
                "enum",
                "format",
            ]
            .contains(&k.as_str())
        }) {
            return false;
        }
        // Password is a privacy annotation; other formats are not validated here.
        if s.get("format").is_some_and(|f| f.as_str() != Some("password") || s["type"] != "string") {
            return false;
        }
        if s.get("enum").and_then(Value::as_array).is_some_and(|a| !a.contains(v)) {
            return false;
        }
        match s["type"].as_str() {
            Some("object") => v.as_object().is_some_and(|o| {
                if s["required"]
                    .as_array()
                    .is_some_and(|a| a.iter().any(|k| !k.as_str().is_some_and(|k| o.contains_key(k))))
                {
                    return false;
                }
                o.iter().all(|(k, x)| {
                    if let Some(p) = s["properties"].get(k) {
                        return valid(p, x, depth + 1);
                    }
                    match s.get("additionalProperties") {
                        Some(Value::Bool(false)) => false,
                        Some(p) if p.is_object() => valid(p, x, depth + 1),
                        Some(Value::Bool(true)) | None => true,
                        _ => false,
                    }
                })
            }),
            Some("array") => v.as_array().is_some_and(|a| {
                a.len() >= s["minItems"].as_u64().unwrap_or(0) as usize
                    && a.len() <= s["maxItems"].as_u64().unwrap_or(1024) as usize
                    && a.iter().all(|x| s.get("items").is_some_and(|p| valid(p, x, depth + 1)))
            }),
            Some("string") => v.as_str().is_some_and(|x| {
                x.chars().count() >= s["minLength"].as_u64().unwrap_or(0) as usize && x.chars().count() <= s["maxLength"].as_u64().unwrap_or(65536) as usize
            }),
            Some("integer") => v.as_i64().is_some_and(|n| in_range(s, n as f64)),
            Some("number") => v.as_f64().is_some_and(|n| in_range(s, n)),
            Some("boolean") => v.is_boolean(),
            Some("null") => v.is_null(),
            _ => false,
        }
    }
    if valid(schema, value, 0) {
        Ok(())
    } else {
        Err("the structured result does not match its declared schema; the action may have happened".into())
    }
}

/// The arguments with every password field gone: what a row is matched
/// against, what a record digests, what the exchange may show.
pub fn plain(schema: &Value, args: &Map<String, Value>) -> Map<String, Value> {
    let props = schema.get("properties").and_then(Value::as_object).cloned().unwrap_or_default();
    args.iter()
        .filter(|(k, _)| !secret(k, props.get(*k)))
        .map(|(k, v)| (k.clone(), v.clone()))
        .collect()
}

/// The credential words: a field so named is never shown, kept or digested, marked or not.
pub const CREDENTIAL_WORDS: &[&str] = &["password", "passphrase", "psk", "token", "secret", "pin", "code"];

pub fn secret(name: &str, prop: Option<&Value>) -> bool {
    let n = name.to_ascii_lowercase();
    prop.and_then(|p| p.get("format")).and_then(Value::as_str) == Some("password") || CREDENTIAL_WORDS.iter().any(|w| n.contains(w))
}

/// A provider result stays local if it carries a named credential. Keep
/// safe native receipts, but never forward a partly stripped success as
/// though it were the provider's complete result. The walk is bounded;
/// unfamiliar depth or size stops continuation too.
#[derive(Default)]
pub struct ResultPrivacy {
    pub private: bool,
    incomplete: bool,
    values: Vec<String>,
}

impl ResultPrivacy {
    pub fn extend(&mut self, other: Self) {
        self.private |= other.private;
        self.incomplete |= other.incomplete;
        self.values.extend(other.values);
    }

    pub fn text_safe(&self, text: &str) -> bool {
        !self.incomplete && !self.values.iter().any(|v| text.contains(v)) && !result_privacy(None, &Value::String(text.into())).private
    }
}

pub fn result_privacy(schema: Option<&Value>, result: &Value) -> ResultPrivacy {
    fn scan(value: &Value, schema: Option<&Value>, marked: bool, depth: usize, left: &mut usize, found: &mut ResultPrivacy) {
        if depth > 12 || *left == 0 {
            found.private = true;
            found.incomplete = true;
            return;
        }
        *left -= 1;
        let marked = marked || schema.and_then(|s| s.get("format")).and_then(Value::as_str) == Some("password");
        found.private |= marked;
        match value {
            Value::Object(object) => {
                for (key, value) in object {
                    let prop = schema.and_then(|s| s.get("properties")).and_then(|p| p.get(key));
                    let prop = prop.or_else(|| schema.and_then(|s| s.get("additionalProperties")).filter(|s| s.is_object()));
                    scan(value, prop, marked || secret(key, prop), depth + 1, left, found);
                    if found.incomplete {
                        break;
                    }
                }
            }
            Value::Array(array) => {
                for value in array {
                    scan(value, schema.and_then(|s| s.get("items")), marked, depth + 1, left, found);
                    if found.incomplete {
                        break;
                    }
                }
            }
            Value::String(text) if marked => {
                if !text.is_empty() {
                    found.values.push(text.clone());
                }
            }
            Value::String(text) if text.trim_start().starts_with(['{', '[']) => {
                if let Ok(value) = serde_json::from_str::<Value>(text) {
                    scan(&value, None, false, depth + 1, left, found);
                }
            }
            Value::Bool(_) | Value::Number(_) if marked => found.values.push(value.to_string()),
            _ => {}
        }
    }
    let mut found = ResultPrivacy::default();
    let mut left = 4096;
    scan(result, schema, false, 0, &mut left, &mut found);
    found
}

/// A name the rows hold the step to: a free string (a network, a device, a window, a layout).
/// A value the schema bounds, an enum or a number, is held by the schema alone (#50).
/// The required arguments a tool names one of the rows by: free strings, no enum, no secret.
pub(crate) fn name_keys(schema: &Value) -> Vec<String> {
    schema
        .get("required")
        .and_then(Value::as_array)
        .map(|a| a.iter().filter_map(Value::as_str).filter(|k| is_name(schema, k)).map(String::from).collect())
        .unwrap_or_default()
}

/// A path argument: the rows' paths are its allowlist, not the name gate's.
pub fn is_path(schema: &Value, k: &str) -> bool {
    schema.pointer(&format!("/properties/{}/format", k)).and_then(Value::as_str) == Some("path")
}

pub(crate) fn is_name(schema: &Value, k: &str) -> bool {
    let Some(p) = schema.pointer(&format!("/properties/{}", k)) else {
        return false;
    };
    p.get("type").and_then(Value::as_str) == Some("string") && p.get("enum").is_none() && !secret(k, Some(p))
}

/// Narrow a single existing-item argument to the exact values displayed by
/// its rows. This carries the host's name gate into generation; labels are
/// never substituted for opaque identifiers. Creation and numeric controls
/// retain their schemas. The execution gate still checks fresh rows later.
/// A step from the model (or an undo from a result), before it runs:
/// the tool is in the provider's tools now, its arguments fit the schema,
/// and where the provider's rows name things with that tool, the step
/// names one of them exactly. A level, a size or minutes are no names:
/// the rows' few steps of a value (brighter, dimmer) are not all it takes.
/// What it says is plain words, never a tool's name.
pub fn step(tools: &[Tool], rows: &Rows, c: &Call) -> Result<(), String> {
    let t = tools
        .iter()
        .find(|t| t.name == c.name)
        .ok_or_else(|| "this is not offered here now".to_string())?;
    schema_ok(&t.schema, &c.arguments)?;
    let required: Vec<String> = t
        .schema
        .get("required")
        .and_then(Value::as_array)
        .map(|a| a.iter().filter_map(Value::as_str).map(String::from).collect())
        .unwrap_or_default();
    // a path: the rows are the allowlist (#112). Every argument the schema marks as a path, required
    // or not, is a path some row's step holds, or the folder on screen itself; the four lines hold
    // in the provider besides
    let paths: Vec<&str> = rows
        .rows
        .iter()
        .flat_map(|r| r.tool.iter().chain(r.more.iter()))
        .flat_map(|x| x.arguments.values().filter_map(Value::as_str))
        .chain(rows.here.as_deref())
        .collect();
    for (k, v) in &c.arguments {
        if t.schema.pointer(&format!("/properties/{}/format", k)).and_then(Value::as_str) != Some("path") {
            continue;
        }
        let Some(p) = v.as_str() else { continue };
        if !paths.contains(&p) {
            let name = p.rsplit('/').next().unwrap_or(p);
            return Err(format!("{} is not in the list now", crate::scrub::cut_words(&crate::scrub::scrub(name), 40)));
        }
    }
    let names: Vec<&String> = required.iter().filter(|k| is_name(&t.schema, k) && !is_path(&t.schema, k)).collect();
    if names.is_empty() {
        return Ok(());
    }
    // a row that asks the person for the argument (a name to save under) names nothing: what is
    // typed there is free, so a step from the model with its own name passes the same way (#25)
    let naming: Vec<&Call> = rows
        .rows
        .iter()
        .flat_map(|r| r.tool.iter().chain(r.more.iter()).chain(r.step.iter().flat_map(|st| [&st.less, &st.more])))
        .filter(|x| x.name == c.name && required.iter().all(|k| x.arguments.contains_key(k) && !x.ask.contains(k)))
        .collect();
    if naming.is_empty() {
        return Ok(());
    }
    if naming.iter().any(|x| names.iter().all(|k| x.arguments.get(*k) == c.arguments.get(*k))) {
        return Ok(());
    }
    let said = names.iter().find_map(|k| c.arguments.get(*k).and_then(Value::as_str)).unwrap_or("that");
    // the one in use is a state row, no step (theme:show:nord): asked for again, its provider says it is on
    if rows.rows.iter().any(|r| r.tool.is_none() && r.id == format!("{}:show:{}", rows.title, said)) {
        return Ok(());
    }
    Err(format!("{} is not in the list now", said))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::Row;
    use serde_json::json;

    fn tool(name: &str, schema: Value) -> Tool {
        Tool {
            description: String::new(),
            output_schema: None,
            name: name.into(),
            title: String::new(),
            schema,
            read_only: false,
            destructive: true,
        }
    }
    fn args(v: Value) -> Map<String, Value> {
        v.as_object().unwrap().clone()
    }

    #[test]
    fn literal_text_whitespace_requires_an_explicit_schema_marker() {
        let ordinary = json!({"type":"object","properties":{"text":{"type":"string","maxLength":16384}},"required":["text"]});
        let mut literal = ordinary.clone();
        literal["properties"]["text"]["contentMediaType"] = json!("text/plain");
        for code in (0..32).chain(127..160) {
            let c = char::from_u32(code).unwrap();
            let value = args(json!({"text":format!("first{}second", c)}));
            assert!(schema_ok(&ordinary, &value).is_err());
            assert_eq!(schema_ok(&literal, &value).is_ok(), matches!(c, '\n' | '\r' | '\t'));
        }
        assert!(schema_ok(&literal, &args(json!({"text":"x".repeat(16384)}))).is_ok());
        assert!(schema_ok(&literal, &args(json!({"text":"x".repeat(16385)}))).is_err());
        literal["properties"]["text"]["contentMediaType"] = json!("text/html");
        assert!(schema_ok(&literal, &args(json!({"text":"first\nsecond"}))).is_err());
    }
    fn wifi() -> (Vec<Tool>, Rows) {
        let s = json!({"type": "object", "properties": {"name": {"type": "string", "minLength": 1, "maxLength": 256}, "password": {"type": "string", "format": "password"}}, "required": ["name"], "additionalProperties": false});
        let lv = json!({"type": "object", "properties": {"level": {"type": "integer", "minimum": 0, "maximum": 100}}, "required": ["level"]});
        let row = Row {
            id: "wifi:connect cafe".into(),
            sign: "ring".into(),
            text: "cafe".into(),
            tool: Some(Call {
                name: "wifi_connect".into(),
                arguments: args(json!({"name": "cafe"})),
                ask: vec![],
                said: None,
                pick: None,
            }),
            more: vec![],
            columns: vec![],
            children: None,
            group: None,
            swatch: None,
            pick: None,
            date: None,
            chip: vec![],
            step: None,
            preview: None,
            page: None,
            film: None,
        };
        (
            vec![tool("wifi_connect", s), tool("out_level", lv)],
            Rows {
                title: "wifi".into(),
                here: None,
                state: None,
                rows: vec![row],
                short: vec![],
            },
        )
    }

    #[test]
    fn a_tool_not_listed_is_refused() {
        let (t, r) = wifi();
        let c = Call {
            name: "wifi_forget".into(),
            arguments: Map::new(),
            ask: vec![],
            said: None,
            pick: None,
        };
        assert_eq!(step(&t, &r, &c).unwrap_err(), "this is not offered here now");
    }

    #[test]
    fn an_argument_outside_the_schema_is_refused() {
        let (t, r) = wifi();
        let c = Call {
            name: "wifi_connect".into(),
            arguments: args(json!({"name": "cafe", "x": 1})),
            ask: vec![],
            said: None,
            pick: None,
        };
        assert_eq!(step(&t, &r, &c).unwrap_err(), "it takes no x");
        let c = Call {
            name: "out_level".into(),
            arguments: args(json!({"level": 300})),
            ask: vec![],
            said: None,
            pick: None,
        };
        assert_eq!(step(&t, &r, &c).unwrap_err(), "300 is not a level it takes");
        let c = Call {
            name: "out_level".into(),
            arguments: Map::new(),
            ask: vec![],
            said: None,
            pick: None,
        };
        assert_eq!(step(&t, &r, &c).unwrap_err(), "it needs a level");
    }

    #[test]
    fn a_name_must_be_a_rows_own() {
        let (t, r) = wifi();
        let ok = Call {
            name: "wifi_connect".into(),
            arguments: args(json!({"name": "cafe", "password": "x"})),
            ask: vec![],
            said: None,
            pick: None,
        };
        assert!(step(&t, &r, &ok).is_ok(), "the password is not part of the match");
        let no = Call {
            name: "wifi_connect".into(),
            arguments: args(json!({"name": "evil twin"})),
            ask: vec![],
            said: None,
            pick: None,
        };
        assert_eq!(step(&t, &r, &no).unwrap_err(), "evil twin is not in the list now");
        let free = Call {
            name: "out_level".into(),
            arguments: args(json!({"level": 30})),
            ask: vec![],
            said: None,
            pick: None,
        };
        assert!(step(&t, &r, &free).is_ok(), "a level names no row");
    }

    #[test]
    fn the_one_in_use_is_named_by_its_state_row() {
        // "theme gruvbox-dark" while gruvbox-dark is on: its row is a state, no step; asked again it is no
        // stranger to the list, and its provider answers that it is on
        let tools = vec![Tool {
            description: String::new(),
            output_schema: None,
            name: "theme_palette".into(),
            title: "theme NAME".into(),
            schema: json!({"type": "object", "properties": {"name": {"type": "string", "minLength": 1}}, "required": ["name"], "additionalProperties": false}),
            destructive: false,
            read_only: false,
        }];
        let r = crate::model::rows(r#"{"title":"theme","rows":[
            {"id":"theme:show:gruvbox-dark","sign":"check","text":"gruvbox-dark","tool":null,"more":[],"columns":[],"children":null},
            {"id":"theme:nord","sign":"ring","text":"nord","tool":{"name":"theme_palette","arguments":{"name":"nord"}},"more":[],"columns":[],"children":null}]}"#)
        .unwrap();
        let named = |n: &str| Call {
            name: "theme_palette".into(),
            arguments: args(json!({"name": n})),
            ask: vec![],
            said: None,
            pick: None,
        };
        assert!(step(&tools, &r, &named("gruvbox-dark")).is_ok(), "the one in use");
        assert!(step(&tools, &r, &named("nord")).is_ok(), "a listed one");
        assert_eq!(step(&tools, &r, &named("rainbow")).unwrap_err(), "rainbow is not in the list now");
    }

    #[test]
    fn a_value_the_schema_bounds_is_no_name_even_where_rows_list_its_steps() {
        // the screen's rows list brighter and dimmer; "dim display 25%" asks for 25 (#50)
        let tools = vec![Tool {
            description: String::new(),
            output_schema: None,
            name: "display_brightness".into(),
            title: "display brightness N".into(),
            schema: json!({"type": "object", "properties": {"level": {"type": "string", "enum": ["up", "down", "10", "25", "30"]}}, "required": ["level"], "additionalProperties": false}),
            destructive: false,
            read_only: false,
        }];
        let r = crate::model::rows(r#"{"title":"display","rows":[
            {"id":"display:brighter","sign":"blank","text":"brighter","tool":{"name":"display_brightness","arguments":{"level":"up"}},"more":[],"columns":[],"children":null},
            {"id":"display:dimmer","sign":"blank","text":"dimmer","tool":{"name":"display_brightness","arguments":{"level":"down"}},"more":[],"columns":[],"children":null}]}"#)
        .unwrap();
        let c = Call {
            name: "display_brightness".into(),
            arguments: args(json!({"level": "25"})),
            ask: vec![],
            said: None,
            pick: None,
        };
        assert!(step(&tools, &r, &c).is_ok(), "25 is the schema's to hold, not the rows'");
        let bad = Call {
            name: "display_brightness".into(),
            arguments: args(json!({"level": "200"})),
            ask: vec![],
            said: None,
            pick: None,
        };
        assert_eq!(step(&tools, &r, &bad).unwrap_err(), "200 is not a level it takes", "the schema still holds it");
    }

    #[test]
    fn a_row_that_asks_for_the_name_binds_no_name() {
        let tools = vec![Tool {
            description: String::new(),
            output_schema: None,
            name: "theme_save".into(),
            title: "theme save NAME".into(),
            schema: json!({"type": "object", "properties": {"name": {"type": "string", "minLength": 1, "maxLength": 256}}, "required": ["name"], "additionalProperties": false}),
            destructive: false,
            read_only: false,
        }];
        let r = crate::model::rows(r#"{"title":"theme","rows":[{"id":"theme:save","sign":"blank","text":"save this look as","tool":{"name":"theme_save","arguments":{"name":""},"ask":["name"]},"more":[],"columns":[],"children":null}]}"#).unwrap();
        let c = Call {
            name: "theme_save".into(),
            arguments: args(json!({"name": "brazilian flag"})),
            ask: vec![],
            said: None,
            pick: None,
        };
        assert!(step(&tools, &r, &c).is_ok(), "the save row asks for its name, so a typed one is free");
    }

    #[test]
    fn the_credential_words_are_secret() {
        for w in CREDENTIAL_WORDS {
            assert!(secret(w, None), "{}", w);
        }
        assert!(secret("x", Some(&json!({"format": "password"}))));
        assert!(!secret("name", None));
        let p = plain(
            &json!({"properties": {"password": {"format": "password"}}}),
            &args(json!({"name": "a", "password": "b", "token": "c"})),
        );
        assert_eq!(Value::Object(p), json!({"name": "a"}));
    }
}

#[cfg(test)]
mod path_tests {
    use super::*;
    use crate::model::{Call, Row, Tool};
    use serde_json::json;

    #[test]
    fn a_path_argument_must_be_a_path_a_row_holds_or_the_folder_itself() {
        let path = json!({"type": "string", "minLength": 2, "maxLength": 4096, "format": "path"});
        let schema = json!({"type": "object", "properties": {"path": path, "to": path}, "required": ["path", "to"], "additionalProperties": false});
        let tools = vec![Tool {
            description: String::new(),
            output_schema: None,
            name: "files_move".into(),
            title: "files move PATH".into(),
            schema,
            read_only: false,
            destructive: false,
        }];
        let call = |p: &str| Call {
            name: "files_move".into(),
            arguments: json!({"path": p}).as_object().unwrap().clone(),
            ask: vec![],
            said: None,
            pick: Some("to".into()),
        };
        let rows = Rows {
            title: "~".into(),
            state: None,
            here: Some("/h".into()),
            rows: vec![Row {
                id: "f".into(),
                sign: "blank".into(),
                text: "a.txt".into(),
                tool: None,
                more: vec![call("/h/a.txt")],
                columns: vec![],
                children: None,
                group: None,
                swatch: None,
                pick: None,
                date: None,
                chip: vec![],
                step: None,
                preview: None,
                page: None,
                film: None,
            }],
            short: vec![],
        };
        let step_with = |p: &str, to: &str| Call {
            name: "files_move".into(),
            arguments: json!({"path": p, "to": to}).as_object().unwrap().clone(),
            ask: vec![],
            said: None,
            pick: None,
        };
        assert!(step(&tools, &rows, &step_with("/h/a.txt", "/h")).is_ok(), "a row's path, and the folder itself");
        assert_eq!(
            step(&tools, &rows, &step_with("/etc/passwd", "/h")).unwrap_err(),
            "passwd is not in the list now"
        );
        assert_eq!(step(&tools, &rows, &step_with("/h/a.txt", "/tmp")).unwrap_err(), "tmp is not in the list now");
    }
}
