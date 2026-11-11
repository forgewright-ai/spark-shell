//! User-owned launcher preferences, independent of installed entry contents.
use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::io::Write;
use std::os::unix::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};

pub const OTHER: &str = "Other";

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Preference {
    pub category: Option<String>,
    pub hidden: bool,
    pub launch: String,
}

impl Preference {
    pub fn mode(&self) -> &str {
        if self.launch.is_empty() {
            "default"
        } else {
            &self.launch
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct Preferences {
    pub categories: Vec<String>,
    pub mappings: BTreeMap<String, String>,
    pub apps: BTreeMap<String, Preference>,
}

impl Default for Preferences {
    fn default() -> Self {
        let mappings = [
            ("Development", "Development"),
            ("System", "System"),
            ("Settings", "System"),
            ("Network", "Web"),
            ("Office", "Office"),
            ("Graphics", "Graphics"),
            ("AudioVideo", "Media"),
            ("Audio", "Media"),
            ("Video", "Media"),
            ("Education", "Education"),
            ("Science", "Education"),
            ("Game", "Games"),
            ("Utility", "Utilities"),
        ];
        Self {
            categories: [
                "Development",
                "System",
                "Web",
                "Office",
                "Graphics",
                "Media",
                "Education",
                "Games",
                "Utilities",
                OTHER,
            ]
            .into_iter()
            .map(String::from)
            .collect(),
            mappings: mappings.into_iter().map(|(a, b)| (a.into(), b.into())).collect(),
            apps: BTreeMap::new(),
        }
    }
}

impl Preferences {
    pub fn path() -> PathBuf {
        std::env::var_os("XDG_CONFIG_HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".config"))
            .join("spark-shell/apps.json")
    }

    pub fn load(path: &Path) -> Result<Self, String> {
        match std::fs::read_to_string(path) {
            Ok(text) => Self::parse(&text),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(Self::default()),
            Err(e) => Err(format!("Cannot read Apps preferences: {e}")),
        }
    }

    pub fn parse(text: &str) -> Result<Self, String> {
        let v: Value = serde_json::from_str(text).map_err(|e| format!("Cannot read Apps preferences: {e}"))?;
        if v["version"] != 1 {
            return Err("Apps preferences need version 1".into());
        }
        let categories = v["categories"]
            .as_array()
            .ok_or("Apps categories must be a list")?
            .iter()
            .map(|x| x.as_str().ok_or("Invalid category").and_then(valid_name))
            .collect::<Result<Vec<_>, _>>()?;
        if !categories.iter().any(|x| x == OTHER) {
            return Err("Apps categories must include Other".into());
        }
        for (i, name) in categories.iter().enumerate() {
            if categories[..i].iter().any(|x| x.eq_ignore_ascii_case(name)) {
                return Err("Duplicate Apps category".into());
            }
        }
        let mut mappings = BTreeMap::new();
        for (source, target) in v["mappings"].as_object().ok_or("Apps mappings must be an object")? {
            let target = target
                .as_str()
                .filter(|t| categories.iter().any(|c| c == t))
                .ok_or("Mapping names an unknown category")?;
            if source.is_empty() || !source.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-') {
                return Err("Invalid desktop category".into());
            }
            mappings.insert(source.clone(), target.into());
        }
        let mut apps = BTreeMap::new();
        for (id, p) in v["apps"].as_object().ok_or("Apps preferences must be an object")? {
            let category = p
                .get("category")
                .filter(|v| !v.is_null())
                .map(|v| v.as_str().filter(|t| categories.iter().any(|c| c == t)).ok_or("App names an unknown category"))
                .transpose()?
                .map(String::from);
            let launch = p.get("launch").and_then(Value::as_str).unwrap_or("default");
            if !["default", "focus", "new"].contains(&launch) {
                return Err("Invalid launch preference".into());
            }
            let hidden = p
                .get("hidden")
                .map(|v| v.as_bool().ok_or("Visibility must be true or false"))
                .transpose()?
                .unwrap_or(false);
            apps.insert(
                id.clone(),
                Preference {
                    category,
                    hidden,
                    launch: launch.into(),
                },
            );
        }
        Ok(Self { categories, mappings, apps })
    }

    pub fn save(&self, path: &Path) -> Result<(), String> {
        let apps: BTreeMap<_, _> = self
            .apps
            .iter()
            .map(|(id, p)| (id, json!({"category":p.category,"hidden":p.hidden,"launch":p.mode()})))
            .collect();
        let body = json!({"version":1,"categories":self.categories,"mappings":self.mappings,"apps":apps});
        let write = || -> std::io::Result<()> {
            let parent = path.parent().ok_or_else(|| std::io::Error::other("missing preference directory"))?;
            std::fs::create_dir_all(parent)?;
            let nonce = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_nanos();
            let tmp = parent.join(format!(".apps-{}-{nonce}", std::process::id()));
            let result = (|| {
                let mut f = std::fs::OpenOptions::new().write(true).create_new(true).mode(0o600).open(&tmp)?;
                writeln!(f, "{}", serde_json::to_string_pretty(&body)?)?;
                f.sync_all()?;
                std::fs::rename(&tmp, path)
            })();
            if result.is_err() {
                let _ = std::fs::remove_file(tmp);
            }
            result
        };
        write().map_err(|e| format!("Apps preferences were not saved: {e}"))
    }

    pub fn category(&self, id: &str, system: &[String]) -> String {
        self.apps
            .get(id)
            .and_then(|p| p.category.clone())
            .or_else(|| system.iter().find_map(|c| self.mappings.get(c).cloned()))
            .unwrap_or_else(|| OTHER.into())
    }

    pub fn add(&mut self, name: &str) -> Result<(), String> {
        let name = valid_name(name)?;
        if self.categories.iter().any(|c| c.eq_ignore_ascii_case(&name)) {
            return Err("That category already exists".into());
        }
        self.categories.insert(self.categories.len().saturating_sub(1), name);
        Ok(())
    }

    pub fn rename(&mut self, from: &str, to: &str) -> Result<(), String> {
        if from == OTHER {
            return Err("Other is the fallback category".into());
        }
        let to = valid_name(to)?;
        if self.categories.iter().any(|c| c != from && c.eq_ignore_ascii_case(&to)) {
            return Err("That category already exists".into());
        }
        let old = self.categories.iter_mut().find(|c| *c == from).ok_or("Category no longer exists")?;
        *old = to.clone();
        for target in self.mappings.values_mut() {
            if target == from {
                *target = to.clone();
            }
        }
        for p in self.apps.values_mut() {
            if p.category.as_deref() == Some(from) {
                p.category = Some(to.clone());
            }
        }
        Ok(())
    }

    /// A category one place up or down the list (#233): the apps list and every list of categories follow its order.
    pub fn shift(&mut self, name: &str, up: bool) -> Result<(), String> {
        let at = self.categories.iter().position(|c| c == name).ok_or("Category no longer exists")?;
        let to = if up {
            at.checked_sub(1)
        } else {
            Some(at + 1).filter(|&t| t < self.categories.len())
        };
        let to = to.ok_or(if up {
            "That category is first already"
        } else {
            "That category is last already"
        })?;
        self.categories.swap(at, to);
        Ok(())
    }

    pub fn delete(&mut self, name: &str) -> Result<(), String> {
        if name == OTHER {
            return Err("Other is the fallback category".into());
        }
        if !self.categories.iter().any(|c| c == name) {
            return Err("Category no longer exists".into());
        }
        self.categories.retain(|c| c != name);
        self.mappings.retain(|_, c| c != name);
        for p in self.apps.values_mut() {
            if p.category.as_deref() == Some(name) {
                p.category = None;
            }
        }
        Ok(())
    }
}

fn valid_name(name: &str) -> Result<String, &'static str> {
    let name = name.trim();
    if name.is_empty() || name.chars().count() > 40 || name.chars().any(char::is_control) || name.eq_ignore_ascii_case("All apps") {
        return Err("Use a category name of 1 to 40 characters; All apps is reserved");
    }
    Ok(name.into())
}
