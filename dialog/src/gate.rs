//! The gate: what the host checks before any tools/call it sends, the
//! same rules spark-shell's want and provide hold (the review's H2, H3).
//! Every rule is a named refusal with a test.

use crate::model::{Call, Rows, Tool};
use serde_json::{Map, Value};

/// A call's arguments against its tool's input schema: an object, no
/// argument the schema lacks, every required one there, each of its type.
pub fn schema_ok(schema: &Value, args: &Map<String, Value>) -> Result<(), String> {
    let props = schema.get("properties").and_then(Value::as_object).cloned().unwrap_or_default();
    for k in args.keys() {
        if !props.contains_key(k) {
            return Err(format!("no argument {}", k));
        }
    }
    for r in schema.get("required").and_then(Value::as_array).cloned().unwrap_or_default() {
        if let Some(k) = r.as_str() {
            if !args.contains_key(k) {
                return Err(format!("missing {}", k));
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
                    && !s.chars().any(char::is_control)
            }),
            "integer" => v.as_i64().map(|n| in_range(p, n as f64)),
            "number" => v.as_f64().map(|n| in_range(p, n)),
            "boolean" => v.as_bool().map(|_| true),
            _ => Some(false),
        };
        if ok != Some(true) {
            return Err(format!("{} is not what the tool takes", k));
        }
    }
    Ok(())
}

fn in_range(p: &Value, n: f64) -> bool {
    p.get("minimum").and_then(Value::as_f64).map(|m| n >= m).unwrap_or(true) && p.get("maximum").and_then(Value::as_f64).map(|m| n <= m).unwrap_or(true)
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

/// A step from the model (or an undo from a result), before it runs:
/// the tool is in the provider's tools now, its arguments fit the schema,
/// and where the provider's rows name things with that tool, the step
/// names one of them exactly.
pub fn step(tools: &[Tool], rows: &Rows, c: &Call) -> Result<(), String> {
    let t = tools
        .iter()
        .find(|t| t.name == c.name)
        .ok_or_else(|| format!("{} is not a step here now", c.name))?;
    schema_ok(&t.schema, &c.arguments)?;
    let required: Vec<String> = t
        .schema
        .get("required")
        .and_then(Value::as_array)
        .map(|a| a.iter().filter_map(Value::as_str).map(String::from).collect())
        .unwrap_or_default();
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
    let mine = plain(&t.schema, &c.arguments);
    if naming.iter().any(|x| plain(&t.schema, &x.arguments) == mine) {
        Ok(())
    } else {
        Err(format!("{} names nothing listed now", c.name))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::Row;
    use serde_json::json;

    fn tool(name: &str, schema: Value) -> Tool {
        Tool {
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
        };
        (
            vec![tool("wifi_connect", s), tool("out_level", lv)],
            Rows {
                title: "wifi".into(),
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
        };
        assert_eq!(step(&t, &r, &c).unwrap_err(), "wifi_forget is not a step here now");
    }

    #[test]
    fn an_argument_outside_the_schema_is_refused() {
        let (t, r) = wifi();
        let c = Call {
            name: "wifi_connect".into(),
            arguments: args(json!({"name": "cafe", "x": 1})),
            ask: vec![],
        };
        assert_eq!(step(&t, &r, &c).unwrap_err(), "no argument x");
        let c = Call {
            name: "out_level".into(),
            arguments: args(json!({"level": 300})),
            ask: vec![],
        };
        assert_eq!(step(&t, &r, &c).unwrap_err(), "level is not what the tool takes");
        let c = Call {
            name: "out_level".into(),
            arguments: Map::new(),
            ask: vec![],
        };
        assert_eq!(step(&t, &r, &c).unwrap_err(), "missing level");
    }

    #[test]
    fn a_name_must_be_a_rows_own() {
        let (t, r) = wifi();
        let ok = Call {
            name: "wifi_connect".into(),
            arguments: args(json!({"name": "cafe", "password": "x"})),
            ask: vec![],
        };
        assert!(step(&t, &r, &ok).is_ok(), "the password is not part of the match");
        let no = Call {
            name: "wifi_connect".into(),
            arguments: args(json!({"name": "evil twin"})),
            ask: vec![],
        };
        assert_eq!(step(&t, &r, &no).unwrap_err(), "wifi_connect names nothing listed now");
        let free = Call {
            name: "out_level".into(),
            arguments: args(json!({"level": 30})),
            ask: vec![],
        };
        assert!(step(&t, &r, &free).is_ok(), "a level names no row");
    }

    #[test]
    fn a_row_that_asks_for_the_name_binds_no_name() {
        let tools = vec![Tool {
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
