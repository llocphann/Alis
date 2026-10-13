use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result};
use clap::Subcommand;
use serde_json::{Value, json};

#[derive(Debug, Subcommand)]
pub enum DesktopCommand {
    SyncIconTheme { theme: String },
}

pub fn run(command: DesktopCommand) -> Result<Value> {
    match command {
        DesktopCommand::SyncIconTheme { theme } => sync_icon_theme(&theme),
    }
}

fn home_dir() -> PathBuf {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/"))
}

fn config_home() -> PathBuf {
    std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| home_dir().join(".config"))
}

fn atomic_write(path: &Path, content: &str) -> Result<()> {
    let parent = path.parent().unwrap_or_else(|| Path::new("."));
    fs::create_dir_all(parent)?;
    let temporary = parent.join(format!(
        ".{}.inir-native-{}.tmp",
        path.file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("config"),
        std::process::id()
    ));
    {
        let mut file = fs::File::create(&temporary)
            .with_context(|| format!("create {}", temporary.display()))?;
        file.write_all(content.as_bytes())?;
        let _ = file.sync_all();
    }
    fs::rename(&temporary, path).with_context(|| format!("replace {}", path.display()))?;
    Ok(())
}

fn section_bounds(lines: &[String], section: &str) -> Option<(usize, usize)> {
    let header = format!("[{section}]");
    let start = lines.iter().position(|line| line.trim() == header)?;
    let end = lines
        .iter()
        .enumerate()
        .skip(start + 1)
        .find(|(_, line)| {
            let line = line.trim();
            line.starts_with('[') && line.ends_with(']')
        })
        .map(|(index, _)| index)
        .unwrap_or(lines.len());
    Some((start, end))
}

fn set_ini_key(content: &str, section: &str, key: &str, value: &str) -> String {
    let mut lines = content.lines().map(str::to_owned).collect::<Vec<_>>();
    let trailing_newline = content.ends_with('\n');
    let (start, mut end) = match section_bounds(&lines, section) {
        Some(bounds) => bounds,
        None => {
            if !lines.is_empty() && !lines.last().is_some_and(|line| line.trim().is_empty()) {
                lines.push(String::new());
            }
            lines.push(format!("[{section}]"));
            let start = lines.len() - 1;
            (start, lines.len())
        }
    };

    let mut replaced = false;
    for line in &mut lines[start + 1..end] {
        let trimmed = line.trim_start();
        if trimmed.starts_with('#') || trimmed.starts_with(';') {
            continue;
        }
        let Some((candidate, _)) = trimmed.split_once('=') else {
            continue;
        };
        if candidate.trim() == key {
            let prefix = " ".repeat(line.len() - trimmed.len());
            *line = format!("{prefix}{key}={value}");
            replaced = true;
            break;
        }
    }
    if !replaced {
        end = end.min(lines.len());
        lines.insert(end, format!("{key}={value}"));
    }

    let mut output = lines.join("\n");
    if trailing_newline || !output.is_empty() {
        output.push('\n');
    }
    output
}

fn backup_corrupt(path: &Path) -> Result<Option<PathBuf>> {
    if !path.is_file() || fs::metadata(path).map(|meta| meta.len()).unwrap_or(0) == 0 {
        return Ok(None);
    }
    let seconds = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    let backup = PathBuf::from(format!("{}.corrupt-{seconds}.bak", path.display()));
    fs::copy(path, &backup)?;
    Ok(Some(backup))
}

fn sync_one(
    path: &Path,
    section: &str,
    key: &str,
    value: &str,
    reset_if_missing_section: bool,
) -> Result<Value> {
    let existing = fs::read_to_string(path).unwrap_or_default();
    let has_section = section_bounds(
        &existing.lines().map(str::to_owned).collect::<Vec<_>>(),
        section,
    )
    .is_some();
    let (base, backup) = if reset_if_missing_section && !has_section && !existing.is_empty() {
        (String::new(), backup_corrupt(path)?)
    } else {
        (existing, None)
    };
    let updated = set_ini_key(&base, section, key, value);
    if updated != base {
        atomic_write(path, &updated)?;
    }
    Ok(json!({
        "path": path.to_string_lossy(),
        "updated": true,
        "backup": backup.map(|path| path.to_string_lossy().into_owned())
    }))
}

fn sync_icon_theme(theme: &str) -> Result<Value> {
    if theme.trim().is_empty() || theme.contains('\n') || theme.contains('\r') {
        anyhow::bail!("invalid_icon_theme");
    }
    let config = config_home();
    let results = vec![
        sync_one(&config.join("kdeglobals"), "Icons", "Theme", theme, false)?,
        sync_one(
            &config.join("qt5ct/qt5ct.conf"),
            "Appearance",
            "icon_theme",
            theme,
            false,
        )?,
        sync_one(
            &config.join("qt6ct/qt6ct.conf"),
            "Appearance",
            "icon_theme",
            theme,
            false,
        )?,
        sync_one(
            &config.join("gtk-3.0/settings.ini"),
            "Settings",
            "gtk-icon-theme-name",
            theme,
            true,
        )?,
        sync_one(
            &config.join("gtk-4.0/settings.ini"),
            "Settings",
            "gtk-icon-theme-name",
            theme,
            true,
        )?,
    ];
    Ok(json!({"ok": true, "theme": theme, "files": results}))
}

#[cfg(test)]
mod tests {
    use super::set_ini_key;

    #[test]
    fn updates_existing_key_without_destroying_other_sections() {
        let output = set_ini_key(
            "[Icons]\nTheme=old\nFoo=bar\n\n[Other]\nX=1\n",
            "Icons",
            "Theme",
            "new",
        );
        assert!(output.contains("[Icons]\nTheme=new\nFoo=bar"));
        assert!(output.contains("[Other]\nX=1"));
    }

    #[test]
    fn creates_missing_section() {
        assert!(
            set_ini_key("[Other]\nX=1\n", "Icons", "Theme", "WhiteSur-dark")
                .contains("[Icons]\nTheme=WhiteSur-dark")
        );
    }

    #[test]
    fn preserves_comments_and_inserts_missing_key() {
        let output = set_ini_key(
            "[Appearance]\n# keep me\nstyle=Fusion\n",
            "Appearance",
            "icon_theme",
            "Papirus",
        );
        assert!(output.contains("# keep me"));
        assert!(output.contains("icon_theme=Papirus"));
    }
}
