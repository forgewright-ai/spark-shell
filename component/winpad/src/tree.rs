//! sway's tree, read: the small steps the buttons and the order share.

use crate::pad::Rect;
use serde_json::Value;

pub(crate) fn num(v: &Value) -> i32 {
    v.as_i64().unwrap_or(0) as i32
}

pub(crate) fn rect_of(v: &Value) -> Rect {
    Rect::new(num(&v["x"]), num(&v["y"]), num(&v["width"]), num(&v["height"]))
}

pub(crate) fn kids(n: &Value) -> impl Iterator<Item = &Value> {
    n["nodes"]
        .as_array()
        .into_iter()
        .flatten()
        .chain(n["floating_nodes"].as_array().into_iter().flatten())
}
