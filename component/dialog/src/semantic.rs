//! Semantic search (v0.130): the rows ranked by what the words typed mean, not only by the letters they share. A
//! small embedding model, EmbeddingGemma 2, turns a row's words and the words typed into vectors; the closer two
//! vectors, the closer the meaning. spark-shell serves the model with llama.cpp's server on a Unix socket in the
//! session's private folder (`spark-shell semantic start`). The dialog asks it over that socket with std alone (no
//! HTTP crate: deny.toml), and keeps each row's vector on disk, so a row is turned into a vector once.

use crate::sha256;
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};
use std::io::{Read, Write};
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::{Duration, Instant};

/// The best meaning match is lit when it is this close or closer, and no row is named by the words. Measured on
/// 50 requests and 23 words that ask the desktop nothing: 49 of the 50 kept, 5 of the 23 let through.
pub const LIT: f32 = 0.72;
/// A meaning match is shown among the matches when it is this close or closer.
pub const SHOWN: f32 = 0.65;
/// The meaning matches shown at most.
pub const TOP: usize = 5;
/// A near tie (#250): a section's own setting this close to its row or step at the top goes first, so it is lit.
/// `change theme` found the moving wallpaper's switch at 0.828 and the theme at 0.821: every row of a section says
/// its name. Measured on the 75 requests of test/semantic_cases.json and semantic_cases_apps.json: the right one
/// first 56 times, not 52, and none lost; 0.01 does as well there, 0.02 leaves room.
pub const TIE: f32 = 0.02;

/// The prompts the model's card asks for: a row is a document, the words typed are a search query.
const DOC: &str = "title: none | text: ";
const QUERY: &str = "task: search result | query: ";
/// Rows turned into vectors in one request.
const BATCH: usize = 32;
/// How long one request may take: the first one turns every row into a vector.
const WAIT: Duration = Duration::from_secs(30);
/// The largest answer read.
const MAX: u64 = 16 << 20;
const HEAD: &str = "spark-shell semantic 1";

/// The rows' vectors: those on disk, those made since, and the ones this run asked about (the only ones saved).
struct Index {
    model: String,
    vecs: HashMap<String, Vec<f32>>,
    used: HashSet<String>,
    dirty: bool,
}

static INDEX: Mutex<Option<Index>> = Mutex::new(None);

/// How close in meaning `query` is to each of `texts`, in their order: about 1 the same, 0 nothing alike. An empty
/// query only turns the texts into vectors, for the requests to come.
pub fn rank(sock: &str, query: &str, texts: &[String]) -> Result<Vec<f32>, String> {
    let sock = Path::new(sock);
    let mut guard = INDEX.lock().map_err(|_| "semantic search failed before".to_string())?;
    if guard.is_none() {
        let model = model_id(sock)?;
        let vecs = cache_path().map(|p| load(&p, &model)).unwrap_or_default();
        *guard = Some(Index {
            model,
            vecs,
            used: HashSet::new(),
            dirty: false,
        });
    }
    let ix = guard.as_mut().expect("the index was made above");
    let keys: Vec<String> = texts.iter().map(|t| sha256::hex(t.as_bytes())).collect();
    let mut missing: Vec<usize> = vec![];
    let mut asked: HashSet<&str> = HashSet::new();
    for (i, k) in keys.iter().enumerate() {
        if !ix.vecs.contains_key(k) && asked.insert(k) {
            missing.push(i);
        }
    }
    for chunk in missing.chunks(BATCH) {
        let docs: Vec<String> = chunk.iter().map(|&i| format!("{}{}", DOC, texts[i])).collect();
        for (&i, v) in chunk.iter().zip(embed(sock, &docs)?) {
            ix.vecs.insert(keys[i].clone(), v);
            ix.dirty = true;
        }
    }
    ix.used.extend(keys.iter().cloned());
    if ix.dirty {
        if let Some(p) = cache_path() {
            save(&p, &ix.model, &ix.vecs, &ix.used);
        }
        ix.dirty = false;
    }
    if query.trim().is_empty() {
        return Ok(vec![]);
    }
    let q = embed(sock, &[format!("{}{}", QUERY, query.trim())])?
        .pop()
        .ok_or("semantic search answered nothing")?;
    Ok(keys.iter().map(|k| dot(&q, &ix.vecs[k])).collect())
}

fn dot(a: &[f32], b: &[f32]) -> f32 {
    if a.len() != b.len() {
        return 0.0;
    }
    a.iter().zip(b).map(|(x, y)| x * y).sum()
}

/// A vector at length 1, so a dot product is the cosine.
fn unit(v: Vec<f32>) -> Vec<f32> {
    let n = v.iter().map(|x| x * x).sum::<f32>().sqrt();
    if n == 0.0 {
        return v;
    }
    v.into_iter().map(|x| x / n).collect()
}

/// The model the server runs: the cache is that model's, and goes when it changes.
fn model_id(sock: &Path) -> Result<String, String> {
    let v = http(sock, "GET", "/v1/models", "")?;
    Ok(v.pointer("/data/0/id").and_then(Value::as_str).unwrap_or("unknown").to_string())
}

fn embed(sock: &Path, inputs: &[String]) -> Result<Vec<Vec<f32>>, String> {
    let v = http(sock, "POST", "/v1/embeddings", &json!({ "input": inputs }).to_string())?;
    let mut data: Vec<&Value> = v.get("data").and_then(Value::as_array).map(|a| a.iter().collect()).unwrap_or_default();
    data.sort_by_key(|d| d.get("index").and_then(Value::as_u64).unwrap_or(0));
    let out: Vec<Vec<f32>> = data
        .iter()
        .map(|d| {
            let e = d.get("embedding").and_then(Value::as_array).cloned().unwrap_or_default();
            unit(e.iter().filter_map(Value::as_f64).map(|x| x as f32).collect())
        })
        .collect();
    if out.len() != inputs.len() || out.iter().any(Vec::is_empty) {
        return Err("semantic search answered short".into());
    }
    Ok(out)
}

/// One request over the socket, its JSON answer. HTTP/1.1, one request a connection.
fn http(sock: &Path, method: &str, path: &str, body: &str) -> Result<Value, String> {
    let mut s = UnixStream::connect(sock).map_err(|e| format!("no semantic search here: {}", e))?;
    s.set_read_timeout(Some(WAIT)).map_err(|e| e.to_string())?;
    s.set_write_timeout(Some(WAIT)).map_err(|e| e.to_string())?;
    let req = format!(
        "{} {} HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        method,
        path,
        body.len(),
        body
    );
    s.write_all(req.as_bytes()).map_err(|e| e.to_string())?;
    let mut raw = vec![];
    // one deadline for the whole answer, not one a read: a server that trickles cannot hold the index
    let end = Instant::now() + WAIT;
    let mut buf = [0u8; 65536];
    loop {
        let n = s.read(&mut buf).map_err(|e| e.to_string())?;
        if n == 0 {
            break;
        }
        raw.extend_from_slice(&buf[..n]);
        if raw.len() as u64 > MAX || Instant::now() > end {
            return Err("semantic search answered too much, or too slowly".into());
        }
    }
    serde_json::from_slice(&body_of(&raw)?).map_err(|_| "semantic search answered no JSON".into())
}

/// An HTTP answer's body: refused unless it is a 200; a chunked one put back together.
pub fn body_of(raw: &[u8]) -> Result<Vec<u8>, String> {
    let at = find(raw, b"\r\n\r\n").ok_or("semantic search answered nothing")?;
    let head = String::from_utf8_lossy(&raw[..at]).to_lowercase();
    let status = head.split_whitespace().nth(1).unwrap_or("");
    if status != "200" {
        return Err(format!("semantic search answered {}", status));
    }
    let body = &raw[at + 4..];
    if head.lines().any(|l| l.starts_with("transfer-encoding:") && l.contains("chunked")) {
        dechunk(body)
    } else {
        Ok(body.to_vec())
    }
}

fn dechunk(mut b: &[u8]) -> Result<Vec<u8>, String> {
    let mut out = vec![];
    loop {
        let at = find(b, b"\r\n").ok_or("a broken chunk")?;
        let size = String::from_utf8_lossy(&b[..at]);
        let n = usize::from_str_radix(size.split(';').next().unwrap_or("").trim(), 16).map_err(|_| "a broken chunk")?;
        b = &b[at + 2..];
        if n == 0 {
            return Ok(out);
        }
        if b.len().saturating_sub(2) < n {
            return Err("a short chunk".into()); // a size no answer holds, however large, never overflows
        }
        out.extend_from_slice(&b[..n]);
        b = &b[n + 2..];
    }
}

fn find(hay: &[u8], needle: &[u8]) -> Option<usize> {
    hay.windows(needle.len()).position(|w| w == needle)
}

/// The vectors on disk: $XDG_CACHE_HOME/spark-shell/semantic.vec, beside files.names.
fn cache_path() -> Option<PathBuf> {
    let base = std::env::var_os("XDG_CACHE_HOME")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").filter(|v| !v.is_empty()).map(|h| PathBuf::from(h).join(".cache")))?;
    Some(base.join("spark-shell").join("semantic.vec"))
}

/// The vectors kept for `model`; none when the file is missing, broken, or another model's. A record is the row's
/// sha256 in hex, the vector's length (u32, little endian), then each value (f32, little endian).
pub fn load(path: &Path, model: &str) -> HashMap<String, Vec<f32>> {
    let mut out = HashMap::new();
    let Ok(raw) = std::fs::read(path) else { return out };
    let mut lines = raw.splitn(3, |&c| c == b'\n');
    if lines.next() != Some(HEAD.as_bytes()) || lines.next() != Some(model.as_bytes()) {
        return out;
    }
    let mut b = lines.next().unwrap_or(&[]);
    while b.len() >= 68 {
        let key = String::from_utf8_lossy(&b[..64]).into_owned();
        let n = u32::from_le_bytes([b[64], b[65], b[66], b[67]]) as usize;
        let Some(end) = n.checked_mul(4).and_then(|x| x.checked_add(68)).filter(|&e| e <= b.len()) else {
            return HashMap::new(); // a cut file: none of it is trusted
        };
        let v = b[68..end].as_chunks::<4>().0.iter().map(|c| f32::from_le_bytes(*c)).collect();
        out.insert(key, v);
        b = &b[end..];
    }
    out
}

/// The vectors of the rows this run asked about, written whole and then moved into place, private to you.
pub fn save(path: &Path, model: &str, vecs: &HashMap<String, Vec<f32>>, used: &HashSet<String>) {
    use std::os::unix::fs::OpenOptionsExt;
    let mut out = format!("{}\n{}\n", HEAD, model).into_bytes();
    let mut keys: Vec<&String> = used.iter().filter(|k| k.len() == 64 && vecs.contains_key(*k)).collect();
    keys.sort();
    for k in keys {
        let v = &vecs[k];
        out.extend_from_slice(k.as_bytes());
        out.extend_from_slice(&(v.len() as u32).to_le_bytes());
        for x in v {
            out.extend_from_slice(&x.to_le_bytes());
        }
    }
    let Some(dir) = path.parent() else { return };
    if std::fs::create_dir_all(dir).is_err() {
        return;
    }
    let tmp = path.with_extension(format!("vec.{}.new", std::process::id())); // two dialogs saving never share it
    let wrote = std::fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o600)
        .open(&tmp)
        .and_then(|mut f| f.write_all(&out));
    if wrote.is_ok() {
        let _ = std::fs::rename(&tmp, path);
    } else {
        let _ = std::fs::remove_file(&tmp);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_body_whole_or_in_chunks() {
        let raw = b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n{}";
        assert_eq!(body_of(raw).unwrap(), b"{}");
        let raw = b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n3\r\n{\"a\r\n4\r\n\":1}\r\n0\r\n\r\n";
        assert_eq!(body_of(raw).unwrap(), b"{\"a\":1}");
        assert!(body_of(b"HTTP/1.1 503 Loading\r\n\r\n{}").unwrap_err().contains("503"));
        assert!(body_of(b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n9\r\n{}").is_err());
        // a size no answer holds is refused, never an overflow
        assert!(body_of(b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nffffffffffffffff\r\nab\r\n0\r\n\r\n").is_err());
    }

    #[test]
    fn the_cache_keeps_what_was_used_for_its_model() {
        let dir = std::env::temp_dir().join(format!("semantic-test-{}", std::process::id()));
        let path = dir.join("semantic.vec");
        let (a, b) = (sha256::hex(b"a"), sha256::hex(b"b"));
        let vecs = HashMap::from([(a.clone(), vec![1.0, 0.5]), (b.clone(), vec![0.0, 1.0])]);
        save(&path, "m1", &vecs, &HashSet::from([a.clone()]));
        let back = load(&path, "m1");
        assert_eq!(back.len(), 1, "a row this run did not ask about is not kept");
        assert_eq!(back[&a], vec![1.0, 0.5]);
        assert!(load(&path, "m2").is_empty(), "another model's vectors are not this one's");
        let mut cut = std::fs::read(&path).unwrap();
        cut.truncate(cut.len() - 3);
        std::fs::write(&path, cut).unwrap();
        assert!(load(&path, "m1").is_empty(), "a cut file is not trusted");
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn closeness_is_the_cosine() {
        let a = unit(vec![3.0, 4.0]);
        assert!((dot(&a, &a) - 1.0).abs() < 1e-6);
        assert_eq!(dot(&a, &[1.0]), 0.0, "vectors of two lengths are nothing alike");
    }
}
