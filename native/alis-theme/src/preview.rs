use std::fs::{self, File};
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result, anyhow};
use serde_json::{Map, Value, json};
use sha2::{Digest, Sha256};

use crate:: {
    Args, Mode, Transparency, resolve_seed, terminal_source,
};
use crate::palette::{
    TerminalSettings, colors_contract, material_palette, palette_contract, palette_to_value,
    terminal_palette,
};
use crate::source::{invert_hue, low_chroma};

const MEDIA_EXTS: &[&str] = &["mp4", "webm", "mkv", "avi", "mov"];

fn file_signature(path: &Path) -> Value {
    match fs::metadata(path) {
        Ok(meta) => json!([
            path.to_string_lossy(),
            meta.mtime_nsec() as i128 + (meta.mtime() as i128) * 1_000_000_000,
            meta.len(),
            meta.ino()
        ]),
        Err(_) => json!([path.to_string_lossy(), Value::Null]),
    }
}

fn is_valid_hex_color(value: &str) -> bool {
    let bytes = value.as_bytes();
    if bytes.first() != Some(&b'#') || (bytes.len() != 7 && bytes.len() != 9) {
        return false;
    }
    bytes[1..].iter().all(|b| b.is_ascii_hexdigit())
}

fn valid_palette(value: &Value) -> bool {
    let Some(obj) = value.as_object() else {
        return false;
    };
    ["background", "primary", "on_surface"].iter().all(|key| {
        obj.get(*key)
            .and_then(Value::as_str)
            .is_some_and(is_valid_hex_color)
    })
}

fn is_sha256_json_filename(name: &str) -> bool {
    name.len() == 69
        && name.ends_with(".json")
        && name.as_bytes()[..64]
            .iter()
            .all(|b| matches!(b, b'0'..=b'9' | b'a'..=b'f'))
}

fn touch_file(path: &Path) {
    if let Ok(file) = File::options().write(true).open(path) {
        let _ = file.set_modified(SystemTime::now());
    }
}

fn default_cache_dir() -> PathBuf {
    if let Some(xdg) = std::env::var_os("XDG_CACHE_HOME")
        && !xdg.is_empty()
    {
        return PathBuf::from(xdg).join("quickshell/palette-preview");
    }
    let home = std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/tmp"));
    home.join(".cache/quickshell/palette-preview")
}

fn default_termscheme_path() -> Option<PathBuf> {
    if let Some(root) = std::env::var_os("ALIS_SHELL_ROOT") {
        let candidate = PathBuf::from(root).join("scripts/colors/terminal/scheme-base.json");
        if candidate.is_file() {
            return Some(candidate);
        }
    }
    if let Ok(exe) = std::env::current_exe() {
        for ancestor in exe.ancestors().skip(1).take(5) {
            let candidate = ancestor.join("scripts/colors/terminal/scheme-base.json");
            if candidate.is_file() {
                return Some(candidate);
            }
        }
    }
    None
}

fn option_f64(options: &Map<String, Value>, key: &str, default: f64) -> f64 {
    match options.get(key) {
        Some(Value::Number(n)) => n.as_f64().unwrap_or(default),
        Some(Value::String(s)) => s.parse::<f64>().unwrap_or(default),
        _ => default,
    }
}

fn option_bool(options: &Map<String, Value>, key: &str) -> bool {
    match options.get(key) {
        Some(Value::Bool(b)) => *b,
        Some(Value::String(s)) => s == "true" || s == "1",
        Some(Value::Number(n)) => n.as_i64().unwrap_or(0) != 0,
        _ => false,
    }
}

pub fn run_preview_cache(raw_path: &Path, options_json: &str) -> Result<()> {
    let path = fs::canonicalize(raw_path)
        .with_context(|| format!("resolve preview path {}", raw_path.display()))?;
    let parsed_options: Value =
        serde_json::from_str(options_json).context("invalid preview options JSON")?;
    let mut options = parsed_options
        .as_object()
        .cloned()
        .ok_or_else(|| anyhow!("preview options must be a JSON object"))?;

    let thumbnail = options
        .remove("thumbnail")
        .and_then(|v| v.as_str().map(PathBuf::from))
        .unwrap_or_default();

    let ext = path
        .extension()
        .and_then(|e| e.to_str())
        .map(|s| s.to_ascii_lowercase())
        .unwrap_or_default();

    let is_media = MEDIA_EXTS.contains(&ext.as_str());
    let source = if (is_media || ext == "gif") && thumbnail.is_file() {
        thumbnail
    } else {
        path.clone()
    };

    let exe_sig = std::env::current_exe()
        .ok()
        .map(|p| file_signature(&p))
        .unwrap_or(Value::Null);
    let key_payload = json!([
        1,
        file_signature(&path),
        file_signature(&source),
        Value::Object(options.clone()),
        exe_sig,
        std::env::var("ALIS_NATIVE_BACKEND").unwrap_or_default(),
    ]);
    let mut hasher = Sha256::new();
    hasher.update(serde_json::to_vec(&key_payload)?);
    let key = format!("{:x}", hasher.finalize());

    let cache_dir = default_cache_dir();
    fs::create_dir_all(&cache_dir)?;
    let cached_file = cache_dir.join(format!("{key}.json"));

    if let Ok(existing_text) = fs::read_to_string(&cached_file)
        && let Ok(existing_json) = serde_json::from_str::<Value>(&existing_text)
        && valid_palette(&existing_json)
    {
        touch_file(&cached_file);
        println!("{}", serde_json::to_string(&existing_json)?);
        return Ok(());
    }

    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let temp_dir = cache_dir.join(format!("palette-{}-{nonce}", std::process::id()));
    fs::create_dir_all(&temp_dir)?;

    let generation_result = (|| -> Result<Value> {
        let mut decode_source = source.clone();
        if decode_source == path && is_media {
            let frame_path = temp_dir.join("frame.jpg");
            let status = Command::new("ffmpeg")
                .args([
                    "-nostdin",
                    "-y",
                    "-i",
                    &path.to_string_lossy(),
                    "-vf",
                    "thumbnail=n=100",
                    "-frames:v",
                    "1",
                    "-update",
                    "1",
                    "-q:v",
                    "2",
                    &frame_path.to_string_lossy(),
                ])
                .stdout(std::process::Stdio::null())
                .stderr(std::process::Stdio::null())
                .status()
                .context("spawn ffmpeg for video preview")?;
            if !status.success() {
                return Err(anyhow!("ffmpeg exited with {status}"));
            }
            decode_source = frame_path;
        } else if decode_source == path && ext == "svg" {
            let frame_path = temp_dir.join("frame.png");
            let status = Command::new("magick")
                .arg(format!("{}[0]", path.to_string_lossy()))
                .arg(&frame_path)
                .stdout(std::process::Stdio::null())
                .stderr(std::process::Stdio::null())
                .status()
                .context("spawn magick for svg preview")?;
            if !status.success() {
                return Err(anyhow!("magick exited with {status}"));
            }
            decode_source = frame_path;
        }

        let mode_str = options
            .get("mode")
            .and_then(Value::as_str)
            .unwrap_or("dark");
        let dark = !mode_str.eq_ignore_ascii_case("light");
        let scheme_opt = options
            .get("scheme")
            .and_then(Value::as_str)
            .unwrap_or("auto")
            .to_owned();
        let color_strength = option_f64(&options, "color-strength", 1.0);
        let term_saturation = option_f64(&options, "term_saturation", 0.65);
        let term_brightness = option_f64(&options, "term_brightness", 0.60);
        let harmony = option_f64(&options, "harmony", 0.40);
        let term_bg_brightness = option_f64(&options, "term_bg_brightness", 0.50);
        let harmonize_threshold = option_f64(&options, "harmonize_threshold", 100.0);
        let term_fg_boost = option_f64(&options, "term_fg_boost", 0.35);
        let soften = option_bool(&options, "soften");
        let invert = option_bool(&options, "invert-hue");

        let synth_args = Args {
            path: Some(decode_source),
            size: 128,
            color: None,
            mode: if dark { Mode::Dark } else { Mode::Light },
            scheme: scheme_opt,
            smart: false,
            transparency: Transparency::Opaque,
            termscheme: default_termscheme_path(),
            harmony,
            harmonize_threshold,
            term_fg_boost,
            term_saturation,
            term_brightness,
            term_bg_brightness,
            blend_bg_fg: true,
            cache: None,
            soften,
            debug: false,
            json_output: None,
            palette_output: None,
            app_palette_output: None,
            terminal_output: None,
            meta_output: None,
            scss_output: None,
            render_templates: None,
            color_strength,
            invert_hue: invert,
            preview_options: None,
            least_busy_region: false,
        };

        let (source_seed, mut scheme, _, source_kind) = resolve_seed(&synth_args)?;
        if source_kind == "image" && synth_args.smart && low_chroma(source_seed) {
            scheme = "neutral".into();
        }
        let scheme_seed = if synth_args.invert_hue {
            invert_hue(source_seed)
        } else {
            source_seed
        };

        let material = material_palette(
            scheme_seed,
            &scheme,
            dark,
            synth_args.soften,
            synth_args.color_strength,
        );
        let palette = palette_contract(&material);
        let source_terminal = terminal_source(synth_args.termscheme.as_deref(), dark)?;
        let terminal = terminal_palette(
            &material,
            source_terminal.as_ref(),
            dark,
            &TerminalSettings {
                harmony: synth_args.harmony,
                harmonize_threshold: synth_args.harmonize_threshold,
                fg_boost: synth_args.term_fg_boost,
                saturation: synth_args.term_saturation,
                brightness: synth_args.term_brightness,
                bg_brightness: synth_args.term_bg_brightness,
                soften: synth_args.soften,
                scheme_name: scheme,
            },
        );
        let colors = colors_contract(&palette, &terminal);
        let result = palette_to_value(&colors);
        if !valid_palette(&result) {
            return Err(anyhow!("theme backend returned an invalid preview palette"));
        }

        let temp_output = temp_dir.join("palette.json");
        fs::write(&temp_output, serde_json::to_vec(&result)?)?;
        fs::rename(&temp_output, &cached_file)?;
        Ok(result)
    })();

    let _ = fs::remove_dir_all(&temp_dir);
    let result = generation_result?;

    // Prune older entries beyond 32 while preserving non-matching files (e.g. keep.note).
    let mut entries: Vec<(i128, PathBuf)> = Vec::new();
    if let Ok(read_dir) = fs::read_dir(&cache_dir) {
        for entry in read_dir.flatten() {
            let file_name = entry.file_name();
            let Some(name_str) = file_name.to_str() else {
                continue;
            };
            if !is_sha256_json_filename(name_str) {
                continue;
            }
            if let Ok(meta) = entry.metadata() {
                let mtime_ns =
                    meta.mtime_nsec() as i128 + (meta.mtime() as i128) * 1_000_000_000;
                entries.push((mtime_ns, entry.path()));
            }
        }
    }
    entries.sort_by(|a, b| b.0.cmp(&a.0));
    for (_, stale_path) in entries.into_iter().skip(32) {
        let _ = fs::remove_file(stale_path);
    }

    println!("{}", serde_json::to_string(&result)?);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validates_palette_required_hex_colors() {
        assert!(valid_palette(&json!({
            "background": "#101214",
            "primary": "#80d0ff",
            "on_surface": "#e1e3e5"
        })));
        assert!(!valid_palette(&json!({
            "background": "not-a-color",
            "primary": "#80d0ff",
            "on_surface": "#e1e3e5"
        })));
        assert!(!valid_palette(&json!({"background": "#101214"})));
    }

    #[test]
    fn matches_sha256_json_filenames_only() {
        let valid = format!("{}.json", "a".repeat(64));
        assert!(is_sha256_json_filename(&valid));
        assert!(!is_sha256_json_filename("keep.note"));
        assert!(!is_sha256_json_filename("colors.json"));
    }
}
