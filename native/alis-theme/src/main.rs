mod palette;
mod sddm;
mod source;
mod template;

use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result, anyhow};
use clap::{Parser, ValueEnum};
use material_color_utils::utils::color_utils::Argb;
use serde_json::{Value, json};

use crate::palette::{
    Palette, TerminalSettings, build_app_palette, colors_contract, material_palette,
    palette_contract, palette_to_value, scss_output, terminal_palette,
};
use crate::sddm::sync_if_installed;
use crate::source::{
    auto_detect_scheme, color_seed, image_seed, invert_hue, load_resized_image, low_chroma,
};
use crate::template::{RenderRequest, render_templates};

#[derive(Debug, Clone, Copy, ValueEnum)]
enum Mode {
    Dark,
    Light,
}

#[derive(Debug, Clone, Copy, ValueEnum)]
enum Transparency {
    Opaque,
    Transparent,
}

#[derive(Debug, Parser)]
#[command(about = "Dormant Rust parity implementation of generate_colors_material.py")]
struct Args {
    #[arg(long)]
    path: Option<PathBuf>,

    #[arg(long, default_value_t = 128)]
    size: u32,

    #[arg(long)]
    color: Option<String>,

    #[arg(long, value_enum, default_value_t = Mode::Dark)]
    mode: Mode,

    #[arg(long, default_value = "vibrant")]
    scheme: String,

    #[arg(long)]
    smart: bool,

    #[arg(long, value_enum, default_value_t = Transparency::Opaque)]
    transparency: Transparency,

    #[arg(long)]
    termscheme: Option<PathBuf>,

    #[arg(long, default_value_t = 0.4)]
    harmony: f64,

    #[arg(long = "harmonize_threshold", default_value_t = 100.0)]
    harmonize_threshold: f64,

    #[arg(long = "term_fg_boost", default_value_t = 0.35)]
    term_fg_boost: f64,

    #[arg(long = "term_saturation", default_value_t = 0.65)]
    term_saturation: f64,

    #[arg(long = "term_brightness", default_value_t = 0.60)]
    term_brightness: f64,

    #[arg(long = "term_bg_brightness", default_value_t = 0.50)]
    term_bg_brightness: f64,

    #[arg(long = "blend_bg_fg")]
    blend_bg_fg: bool,

    #[arg(long)]
    cache: Option<PathBuf>,

    #[arg(long)]
    soften: bool,

    #[arg(long)]
    debug: bool,

    #[arg(long = "json-output")]
    json_output: Option<PathBuf>,

    #[arg(long = "palette-output")]
    palette_output: Option<PathBuf>,

    #[arg(long = "app-palette-output")]
    app_palette_output: Option<PathBuf>,

    #[arg(long = "terminal-output")]
    terminal_output: Option<PathBuf>,

    #[arg(long = "meta-output")]
    meta_output: Option<PathBuf>,

    #[arg(long = "scss-output")]
    scss_output: Option<PathBuf>,

    #[arg(long = "render-templates")]
    render_templates: Option<PathBuf>,

    #[arg(long = "color-strength", default_value_t = 1.0)]
    color_strength: f64,

    #[arg(long = "invert-hue")]
    invert_hue: bool,
}

fn write_text(path: &Path, content: &str) -> Result<()> {
    if fs::read(path)
        .ok()
        .is_some_and(|existing| existing == content.as_bytes())
    {
        return Ok(());
    }
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(path, content).with_context(|| format!("write {}", path.display()))
}

fn write_json(path: &Path, value: &Value) -> Result<()> {
    write_text(path, &(serde_json::to_string_pretty(value)? + "\n"))
}

fn terminal_source(path: Option<&Path>, dark: bool) -> Result<Option<Palette>> {
    let Some(path) = path else {
        return Ok(None);
    };
    let value: Value = serde_json::from_str(&fs::read_to_string(path)?)?;
    let key = if dark { "dark" } else { "light" };
    let object = value
        .get(key)
        .and_then(Value::as_object)
        .ok_or_else(|| anyhow!("termscheme_missing_{key}"))?;
    Ok(Some(
        object
            .iter()
            .filter_map(|(key, value)| value.as_str().map(|value| (key.clone(), value.to_owned())))
            .collect(),
    ))
}

fn resolve_seed(args: &Args) -> Result<(Argb, String, Option<PathBuf>, String)> {
    if let Some(path) = &args.path {
        let image = load_resized_image(path, args.size)?;
        let mut scheme = args.scheme.clone();
        if scheme == "auto" {
            scheme = auto_detect_scheme(&image).to_owned();
        }
        let seed = image_seed(&image)?;
        return Ok((seed, scheme, Some(path.clone()), "image".into()));
    }
    if let Some(color) = &args.color {
        return Ok((
            color_seed(color)?,
            args.scheme.clone(),
            None,
            "color".into(),
        ));
    }
    Err(anyhow!("one_of_path_or_color_is_required"))
}

fn main() -> Result<()> {
    let args = Args::parse();
    let dark = matches!(args.mode, Mode::Dark);
    let transparent = matches!(args.transparency, Transparency::Transparent);

    let (source_seed, mut scheme, source_path, source_kind) = resolve_seed(&args)?;
    if source_kind == "image" && args.smart && low_chroma(source_seed) {
        scheme = "neutral".into();
    }
    let scheme_seed = if args.invert_hue {
        invert_hue(source_seed)
    } else {
        source_seed
    };

    if source_kind == "image"
        && let Some(cache) = &args.cache
    {
        write_text(cache, &source_seed.to_hex())?;
    }

    let material = material_palette(scheme_seed, &scheme, dark, args.soften, args.color_strength);
    let palette = palette_contract(&material);
    let app_palette = build_app_palette(&palette);
    let source_terminal = terminal_source(args.termscheme.as_deref(), dark)?;
    let terminal = terminal_palette(
        &material,
        source_terminal.as_ref(),
        dark,
        &TerminalSettings {
            harmony: args.harmony,
            harmonize_threshold: args.harmonize_threshold,
            fg_boost: args.term_fg_boost,
            saturation: args.term_saturation,
            brightness: args.term_brightness,
            bg_brightness: args.term_bg_brightness,
            soften: args.soften,
            scheme_name: scheme.clone(),
        },
    );
    let colors = colors_contract(&palette, &terminal);
    let scss = scss_output(&material, &terminal, dark, transparent);

    if let Some(path) = &args.scss_output {
        write_text(path, &scss)?;
    }
    if let Some(path) = &args.json_output {
        write_json(path, &palette_to_value(&colors))?;
    }
    if let Some(path) = &args.palette_output {
        write_json(path, &palette_to_value(&palette))?;
    }
    if let Some(path) = &args.app_palette_output {
        write_json(path, &palette_to_value(&app_palette))?;
    }
    if let Some(path) = &args.terminal_output {
        write_json(path, &palette_to_value(&terminal))?;
    }
    if let Some(path) = &args.meta_output {
        let meta = json!({
            "source": source_kind,
            "source_path": source_path.as_ref().map(|path| path.to_string_lossy().into_owned()),
            "seed_color": source_seed.to_hex(),
            "mode": if dark { "dark" } else { "light" },
            "scheme": scheme,
            "transparent": transparent,
            "soften": args.soften,
            "term_harmony": args.harmony,
            "term_saturation": args.term_saturation,
            "term_brightness": args.term_brightness,
            "term_bg_brightness": args.term_bg_brightness,
            "term_fg_boost": args.term_fg_boost,
            "harmonize_threshold": args.harmonize_threshold,
            "color_strength": args.color_strength,
            "blend_bg_fg": args.blend_bg_fg,
            "generated_by": "inir-theme"
        });
        write_json(path, &meta)?;
    }

    if let Some(template_dir) = args.render_templates.as_deref() {
        let managed_outputs = [
            args.json_output.clone(),
            args.palette_output.clone(),
            args.app_palette_output.clone(),
            args.terminal_output.clone(),
            args.meta_output.clone(),
            args.scss_output.clone(),
        ];
        let rendered = render_templates(RenderRequest {
            template_dir,
            managed_outputs: &managed_outputs,
            scheme_seed,
            source_seed,
            scheme: &scheme,
            dark_mode: dark,
            soften: args.soften,
            current_material: &material,
            current_app_palette: &app_palette,
            image: source_path.as_deref(),
        })?;
        if rendered > 0
            && std::env::var_os("INIR_THEME_SKIP_SDDM_SYNC").is_none()
            && let Err(error) = sync_if_installed(&app_palette)
        {
            eprintln!("[sddm-pixel] Native sync failed: {error:#}");
        }
    }

    if args.debug {
        eprintln!(
            "inir-theme: seed={} mode={} scheme={} material_roles={} terminal_roles={}",
            source_seed.to_hex(),
            if dark { "dark" } else { "light" },
            scheme,
            material.len(),
            terminal.len()
        );
    } else {
        print!("{scss}");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn metadata_source_selection_requires_input() {
        let parsed = Args::try_parse_from(["inir-theme", "--color", "#4181EE"]);
        assert!(parsed.is_ok());
    }

    #[test]
    fn underscore_terminal_flags_match_python_cli() {
        let parsed = Args::try_parse_from([
            "inir-theme",
            "--color",
            "#4181EE",
            "--term_saturation",
            "0.7",
            "--term_brightness",
            "0.6",
            "--term_bg_brightness",
            "0.5",
            "--term_fg_boost",
            "0.3",
            "--harmonize_threshold",
            "90",
        ])
        .unwrap();
        assert_eq!(parsed.term_saturation, 0.7);
        assert_eq!(parsed.harmonize_threshold, 90.0);
    }
}
