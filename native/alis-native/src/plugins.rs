use std::fs;
use std::path::{Path, PathBuf};

use anyhow::Result;
use clap::Subcommand;
use serde_json::{Value, json};

#[derive(Debug, Subcommand)]
pub enum PluginsCommand {
    /// Scan plugin directory for valid manifest.json files and output JSON array.
    Scan {
        /// Optional override for the Alis shell root directory (containing defaults/plugins).
        #[arg(long)]
        shell_root: Option<PathBuf>,
    },
}

fn resolve_shell_config_dir() -> PathBuf {
    let xdg_config = std::env::var_os("XDG_CONFIG_HOME")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            let home = std::env::var_os("HOME")
                .map(PathBuf::from)
                .unwrap_or_else(|| PathBuf::from("/tmp"));
            home.join(".config")
        });
    let new_dir = xdg_config.join("alis");
    let legacy_dir = xdg_config.join("illogical-impulse");

    let is_symlink = fs::symlink_metadata(&legacy_dir)
        .map(|m| m.file_type().is_symlink())
        .unwrap_or(false);
    if is_symlink && new_dir.is_dir() {
        return new_dir;
    }
    if legacy_dir.is_dir() {
        return legacy_dir;
    }
    if new_dir.is_dir() {
        return new_dir;
    }
    new_dir
}

fn resolve_defaults_dir(explicit_root: Option<&Path>) -> Option<PathBuf> {
    if let Some(root) = explicit_root {
        let candidate = root.join("defaults/plugins");
        if candidate.is_dir() {
            return Some(candidate);
        }
    }
    if let Some(env_root) = std::env::var_os("ALIS_SHELL_ROOT") {
        let candidate = PathBuf::from(env_root).join("defaults/plugins");
        if candidate.is_dir() {
            return Some(candidate);
        }
    }
    if let Ok(exe) = std::env::current_exe() {
        for ancestor in exe.ancestors().skip(1).take(5) {
            let candidate = ancestor.join("defaults/plugins");
            if candidate.is_dir() {
                return Some(candidate);
            }
        }
    }
    None
}

fn copy_dir_recursive(src: &Path, dst: &Path) -> Result<()> {
    fs::create_dir_all(dst)?;
    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let src_path = entry.path();
        let dst_path = dst.join(entry.file_name());
        if src_path.is_dir() {
            copy_dir_recursive(&src_path, &dst_path)?;
        } else if src_path.is_file() {
            fs::copy(&src_path, &dst_path)?;
        }
    }
    Ok(())
}

fn bootstrap_defaults(plugins_dir: &Path, defaults_dir: &Path) {
    if !defaults_dir.is_dir() {
        return;
    }
    let _ = fs::create_dir_all(plugins_dir);
    let Ok(entries) = fs::read_dir(defaults_dir) else {
        return;
    };
    for entry in entries.flatten() {
        let src = entry.path();
        if !src.is_dir() {
            continue;
        }
        let dest = plugins_dir.join(entry.file_name());
        if !dest.is_dir() {
            if copy_dir_recursive(&src, &dest).is_ok() {
                eprintln!(
                    "[Plugins] Installed default plugin: {}",
                    entry.file_name().to_string_lossy()
                );
            }
        } else {
            let src_scripts = src.join("scripts");
            if src_scripts.is_dir() {
                let dest_scripts = dest.join("scripts");
                let _ = fs::create_dir_all(&dest_scripts);
                if let Ok(script_entries) = fs::read_dir(&src_scripts) {
                    for sf in script_entries.flatten() {
                        let sf_path = sf.path();
                        if sf_path.is_file() {
                            let _ = fs::copy(&sf_path, dest_scripts.join(sf.file_name()));
                        }
                    }
                }
            }
        }
    }
}

pub fn run(command: PluginsCommand) -> Result<Value> {
    match command {
        PluginsCommand::Scan { shell_root } => {
            let plugins_dir = resolve_shell_config_dir().join("plugins");
            let is_empty = !plugins_dir.is_dir()
                || fs::read_dir(&plugins_dir)
                    .map(|mut it| it.next().is_none())
                    .unwrap_or(true);
            if is_empty
                && let Some(defaults_dir) = resolve_defaults_dir(shell_root.as_deref())
            {
                bootstrap_defaults(&plugins_dir, &defaults_dir);
            }

            if !plugins_dir.is_dir() {
                return Ok(json!([]));
            }

            let mut dir_names: Vec<String> = fs::read_dir(&plugins_dir)
                .ok()
                .into_iter()
                .flatten()
                .flatten()
                .filter_map(|e| e.file_name().into_string().ok())
                .collect();
            dir_names.sort();

            let mut plugins: Vec<Value> = Vec::new();
            for entry in dir_names {
                let plugin_dir = plugins_dir.join(&entry);
                let manifest_path = plugin_dir.join("manifest.json");
                if !manifest_path.is_file() {
                    continue;
                }
                let Ok(raw) = fs::read_to_string(&manifest_path) else {
                    continue;
                };
                let Ok(Value::Object(mut data)) = serde_json::from_str::<Value>(&raw) else {
                    continue;
                };
                let Some(id_val) = data.get("id").and_then(Value::as_str).map(str::to_owned) else {
                    continue;
                };
                if !data.get("url").is_some_and(Value::is_string) {
                    continue;
                }

                data.entry("name".to_owned())
                    .or_insert_with(|| Value::String(id_val));
                data.entry("icon".to_owned())
                    .or_insert_with(|| Value::String("language".to_owned()));
                data.entry("display".to_owned())
                    .or_insert_with(|| Value::String("tab".to_owned()));
                data.entry("version".to_owned())
                    .or_insert_with(|| Value::String("1.0".to_owned()));

                if let Some(icon_rel) = data.get("iconPath").and_then(Value::as_str) {
                    let full_icon = plugin_dir.join(icon_rel);
                    if full_icon.is_file() {
                        data.insert(
                            "faviconPath".to_owned(),
                            Value::String(full_icon.to_string_lossy().into_owned()),
                        );
                    }
                }

                if let Some(scripts) = data
                    .get("userscripts")
                    .and_then(Value::as_array)
                    .cloned()
                    && !scripts.is_empty()
                {
                    let mut resolved: Vec<Value> = Vec::new();
                    let mut sources: Vec<Value> = Vec::new();
                    for s in scripts {
                        let Some(rel_script) = s.as_str() else {
                            continue;
                        };
                        let full_script = plugin_dir.join(rel_script);
                        if full_script.is_file() {
                            resolved.push(Value::String(
                                full_script.to_string_lossy().into_owned(),
                            ));
                            let src_text = fs::read_to_string(&full_script).unwrap_or_default();
                            sources.push(Value::String(src_text));
                        }
                    }
                    data.insert("userscriptPaths".to_owned(), Value::Array(resolved));
                    data.insert("userscriptSources".to_owned(), Value::Array(sources));
                }

                plugins.push(Value::Object(data));
            }

            Ok(Value::Array(plugins))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scans_defaults_plugins_when_given_shell_root() {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
        let val = run(PluginsCommand::Scan {
            shell_root: Some(root),
        })
        .expect("plugins scan succeeds");
        assert!(val.is_array());
    }
}
