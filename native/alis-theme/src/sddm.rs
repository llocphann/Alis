use std::env;
use std::fs;
use std::io::Read;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use anyhow::{Context, Result};
use serde_json::Value;

use crate::palette::Palette;

const THEME_DIR: &str = "/usr/share/sddm/themes/ii-pixel";
const THEME_CONF_TEMPLATE: &str = r#"[SddmTheme]
Name=ii-pixel
Description=Alis SDDM login screen — Material You dynamic colors
Type=sddm-theme
Author=Alis project
Version=1.0
Website=https://github.com/llocphann/Alis
Screenshot=
MainScript=Main.qml
ConfigFile=theme.conf

[General]
background=assets/background.png
defaultBackground=assets/background.png
blurRadius=50

# Alis Material You colors — updated automatically by alis-theme on wallpaper change"#;

fn home_from_getent(user: &str) -> Option<PathBuf> {
    let output = Command::new("getent")
        .args(["passwd", user])
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let text = String::from_utf8(output.stdout).ok()?;
    text.trim()
        .split(':')
        .nth(5)
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
}

fn real_home() -> PathBuf {
    if let Ok(user) = env::var("SUDO_USER")
        && !user.is_empty()
        && let Some(home) = home_from_getent(&user)
    {
        return home;
    }
    env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/"))
}

fn config_path(home: &Path) -> PathBuf {
    env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| home.join(".config"))
        .join("alis/config.json")
}

fn read_config(home: &Path) -> Option<Value> {
    let path = config_path(home);
    let content = fs::read_to_string(path).ok()?;
    serde_json::from_str(&content).ok()
}

fn read_wallpaper(config: Option<&Value>) -> Option<PathBuf> {
    let config = config?;
    let panel_family = config
        .get("panelFamily")
        .and_then(Value::as_str)
        .unwrap_or("ii");
    let background = config.get("background").and_then(Value::as_object);
    let waffles_background = config
        .get("waffles")
        .and_then(Value::as_object)
        .and_then(|waffles| waffles.get("background"))
        .and_then(Value::as_object);

    let main_path = background
        .and_then(|value| value.get("wallpaperPath"))
        .and_then(Value::as_str)
        .unwrap_or("");
    let selected = if panel_family == "waffle" {
        let use_main = waffles_background
            .and_then(|value| value.get("useMainWallpaper"))
            .and_then(Value::as_bool)
            .unwrap_or(true);
        let waffle_path = waffles_background
            .and_then(|value| value.get("wallpaperPath"))
            .and_then(Value::as_str)
            .unwrap_or("");
        if use_main || waffle_path.is_empty() {
            main_path
        } else {
            waffle_path
        }
    } else {
        main_path
    };
    let selected = selected.strip_prefix("file://").unwrap_or(selected);
    let path = PathBuf::from(selected);
    path.is_file().then_some(path)
}

fn material_shape_chars(config: Option<&Value>) -> &'static str {
    if config
        .and_then(|value| value.get("lock"))
        .and_then(Value::as_object)
        .and_then(|lock| lock.get("materialShapeChars"))
        .and_then(Value::as_bool)
        .unwrap_or(false)
    {
        "true"
    } else {
        "false"
    }
}

/// Compare file contents without loading large wallpaper assets into memory.
/// Missing destinations are a normal cache miss; other I/O errors remain visible.
fn files_equal(left: &Path, right: &Path) -> Result<bool> {
    let left_metadata = match fs::metadata(left) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(false),
        Err(error) => return Err(error.into()),
    };
    let right_metadata = match fs::metadata(right) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(false),
        Err(error) => return Err(error.into()),
    };
    if left_metadata.len() != right_metadata.len() {
        return Ok(false);
    }

    let mut left = fs::File::open(left)?;
    let mut right = fs::File::open(right)?;
    let mut left_buffer = [0_u8; 16 * 1024];
    let mut right_buffer = [0_u8; 16 * 1024];
    let mut remaining = left_metadata.len();
    while remaining > 0 {
        let chunk_len = remaining.min(left_buffer.len() as u64) as usize;
        left.read_exact(&mut left_buffer[..chunk_len])?;
        right.read_exact(&mut right_buffer[..chunk_len])?;
        if left_buffer[..chunk_len] != right_buffer[..chunk_len] {
            return Ok(false);
        }
        remaining -= chunk_len as u64;
    }
    Ok(true)
}

fn palette_value<'a>(palette: &'a Palette, keys: &[&str], fallback: &'a str) -> &'a str {
    keys.iter()
        .find_map(|key| palette.get(*key).map(String::as_str))
        .unwrap_or(fallback)
}

fn theme_colors(palette: &Palette) -> Vec<(String, String)> {
    [
        (
            "primaryColor",
            palette_value(palette, &["app_accent", "primary"], "#cba6f7"),
        ),
        (
            "onPrimaryColor",
            palette_value(palette, &["app_on_accent", "on_primary"], "#1e1e2e"),
        ),
        (
            "surfaceColor",
            palette_value(palette, &["app_background", "surface"], "#1e1e2e"),
        ),
        (
            "surfaceContainerColor",
            palette_value(palette, &["app_surface", "surface_container"], "#181825"),
        ),
        (
            "onSurfaceColor",
            palette_value(palette, &["app_foreground", "on_surface"], "#cdd6f4"),
        ),
        (
            "onSurfaceVariantColor",
            palette_value(palette, &["app_subtext", "on_surface_variant"], "#9399b2"),
        ),
        (
            "backgroundColor",
            palette_value(palette, &["app_background", "background"], "#1e1e2e"),
        ),
        ("errorColor", palette_value(palette, &["error"], "#f38ba8")),
    ]
    .into_iter()
    .map(|(key, value)| (key.to_owned(), value.to_owned()))
    .collect()
}

fn update_theme_conf(theme_dir: &Path, palette: &Palette, shape_chars: &str) -> Result<bool> {
    let path = theme_dir.join("theme.conf");
    if !path.is_file() {
        eprintln!("[sddm-pixel] theme.conf not found: {}", path.display());
        return Ok(false);
    }

    let content = fs::read_to_string(&path)?;
    let mut lines: Vec<String> = content.lines().map(str::to_owned).collect();
    let has_general = lines.iter().any(|line| line.contains("[General]"));
    let has_background = lines
        .iter()
        .any(|line| line.trim().starts_with("background="));
    if !has_general || !has_background {
        eprintln!("[sddm-pixel] theme.conf missing structural elements — restoring template");
        lines = THEME_CONF_TEMPLATE.lines().map(str::to_owned).collect();
    }

    let mut remaining = theme_colors(palette);
    remaining.push(("materialShapeChars".into(), shape_chars.into()));
    let mut new_lines = Vec::with_capacity(lines.len() + remaining.len());

    for line in lines {
        let stripped = line.trim();
        if let Some(index) = remaining
            .iter()
            .position(|(key, _)| stripped.starts_with(&format!("{key}=")))
        {
            let (key, value) = remaining.remove(index);
            new_lines.push(format!("{key}={value}"));
        } else {
            new_lines.push(line);
        }
    }
    for (key, value) in remaining {
        new_lines.push(format!("{key}={value}"));
    }
    let updated = new_lines.join("\n");
    let changed = updated != content;
    if changed {
        fs::write(&path, updated)
            .with_context(|| format!("write SDDM theme config {}", path.display()))?;
    }
    Ok(changed)
}

fn current_username() -> Option<String> {
    env::var("SUDO_USER")
        .ok()
        .filter(|value| !value.is_empty())
        .or_else(|| env::var("USER").ok().filter(|value| !value.is_empty()))
}

fn update_avatar(theme_dir: &Path, home: &Path) -> Result<bool> {
    let assets = theme_dir.join("assets");
    fs::create_dir_all(&assets)?;
    let mut candidates = vec![home.join(".face"), home.join(".face.icon")];
    if let Some(user) = current_username() {
        candidates.push(PathBuf::from("/var/lib/AccountsService/icons").join(user));
    }
    let Some(source) = candidates.into_iter().find(|path| path.is_file()) else {
        return Ok(false);
    };

    let destination = assets.join("user-face.png");
    let changed = !files_equal(&source, &destination)?;
    if changed {
        fs::copy(&source, &destination)?;
    }
    // Keep the expected permissions even when the content is already current.
    fs::set_permissions(&destination, fs::Permissions::from_mode(0o644))?;
    if changed {
        eprintln!(
            "[sddm-pixel] Avatar updated: {}",
            source
                .file_name()
                .and_then(|value| value.to_str())
                .unwrap_or("avatar")
        );
    }
    Ok(changed)
}

fn is_video_like(path: &Path) -> bool {
    matches!(
        path.extension()
            .and_then(|value| value.to_str())
            .map(|value| value.to_ascii_lowercase())
            .as_deref(),
        Some("mp4" | "mkv" | "webm" | "avi" | "mov" | "gif" | "webp")
    )
}

fn extract_video_frame(source: &Path) -> Option<PathBuf> {
    let temporary = PathBuf::from("/tmp/sddm-pixel-frame.tmp.png");
    let status = Command::new("ffmpeg")
        .arg("-y")
        .arg("-i")
        .arg(source)
        .args(["-vframes", "1", "-update", "1", "-f", "image2"])
        .arg(&temporary)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .ok()?;
    (status.success() && temporary.is_file()).then_some(temporary)
}

fn update_background(theme_dir: &Path, wallpaper: Option<&Path>) -> Result<bool> {
    let Some(wallpaper) = wallpaper else {
        eprintln!("[sddm-pixel] No wallpaper path found, keeping existing background");
        return Ok(false);
    };
    let assets = theme_dir.join("assets");
    fs::create_dir_all(&assets)?;
    let destination = assets.join("background.png");

    let temporary = if is_video_like(wallpaper) {
        let frame = extract_video_frame(wallpaper);
        if frame.is_none() {
            eprintln!("[sddm-pixel] Keeping existing background (video, no ffmpeg)");
        }
        frame
    } else {
        None
    };
    let source = temporary.as_deref().unwrap_or(wallpaper);
    if is_video_like(wallpaper) && temporary.is_none() {
        return Ok(false);
    }

    let unchanged = match files_equal(source, &destination) {
        Ok(unchanged) => unchanged,
        Err(error) => {
            if let Some(path) = temporary.as_ref() {
                let _ = fs::remove_file(path);
            }
            return Err(error);
        }
    };
    if unchanged {
        if let Some(path) = temporary {
            let _ = fs::remove_file(path);
        }
        return Ok(false);
    }

    let result = fs::copy(source, &destination)
        .with_context(|| format!("copy SDDM background {}", wallpaper.display()));
    if let Some(path) = temporary {
        let _ = fs::remove_file(path);
    }
    result?;
    eprintln!(
        "[sddm-pixel] Background updated: {}",
        wallpaper
            .file_name()
            .and_then(|value| value.to_str())
            .unwrap_or("wallpaper")
    );
    Ok(true)
}

pub fn sync_if_installed(palette: &Palette) -> Result<()> {
    let theme_dir = Path::new(THEME_DIR);
    if !theme_dir.is_dir() {
        return Ok(());
    }

    let home = real_home();
    let config = read_config(&home);
    let shape_chars = material_shape_chars(config.as_ref());
    if update_theme_conf(theme_dir, palette, shape_chars)? {
        eprintln!(
            "[sddm-pixel] Colors synced (primary: {})",
            palette_value(palette, &["app_accent", "primary"], "#cba6f7")
        );
    }

    let wallpaper = read_wallpaper(config.as_ref());
    update_background(theme_dir, wallpaper.as_deref())?;
    update_avatar(theme_dir, &home)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn files_equal_checks_contents_and_handles_missing_destinations() {
        let nonce = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .expect("clock after epoch")
            .as_nanos();
        let directory = std::env::temp_dir().join(format!(
            "alis-sddm-files-equal-{}-{nonce}",
            std::process::id()
        ));
        fs::create_dir_all(&directory).expect("create fixture directory");
        let left = directory.join("left.bin");
        let right = directory.join("right.bin");

        fs::write(&left, b"same wallpaper bytes").expect("write left fixture");
        assert!(!files_equal(&left, &right).expect("missing destination is a cache miss"));
        fs::write(&right, b"same wallpaper bytes").expect("write right fixture");
        assert!(files_equal(&left, &right).expect("compare equal files"));
        fs::write(&right, b"different wallpaper bytes").expect("rewrite right fixture");
        assert!(!files_equal(&left, &right).expect("compare different files"));
        fs::remove_dir_all(&directory).expect("remove fixture directory");
    }

    #[test]
    fn video_extensions_match_python_hook() {
        for name in [
            "a.mp4", "a.mkv", "a.webm", "a.avi", "a.mov", "a.gif", "a.webp",
        ] {
            assert!(is_video_like(Path::new(name)), "{name}");
        }
        assert!(!is_video_like(Path::new("a.png")));
    }

    #[test]
    fn sddm_colors_prefer_app_contract() {
        let palette = [
            ("primary".into(), "#111111".into()),
            ("app_accent".into(), "#222222".into()),
            ("on_surface".into(), "#333333".into()),
            ("app_foreground".into(), "#444444".into()),
        ]
        .into_iter()
        .collect();
        let colors = theme_colors(&palette);
        assert_eq!(colors[0], ("primaryColor".into(), "#222222".into()));
        assert!(colors.contains(&("onSurfaceColor".into(), "#444444".into())));
    }
}
