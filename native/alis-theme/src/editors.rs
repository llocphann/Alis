use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{Result, anyhow};
use regex::Regex;
use serde_json::{Map, Value, json};

pub fn read_string_map_json(path: &Path) -> Result<HashMap<String, String>> {
    let data = fs::read_to_string(path)?;
    let raw: Value = serde_json::from_str(&data)?;
    let mut out = HashMap::new();
    if let Some(obj) = raw.as_object() {
        for (k, v) in obj {
            if let Some(s) = v.as_str() {
                out.insert(k.clone(), s.to_owned());
            }
        }
    }
    Ok(out)
}

pub fn parse_scss(path: &Path) -> Result<HashMap<String, String>> {
    let data = fs::read_to_string(path)?;
    let re = Regex::new(r"\$(\w+):\s*(#[A-Fa-f0-9]{6}|True|False);")?;
    let mut out = HashMap::new();
    for line in data.lines() {
        if let Some(caps) = re.captures(line.trim())
            && let (Some(k), Some(v)) = (caps.get(1), caps.get(2))
        {
            out.insert(k.as_str().to_owned(), v.as_str().to_owned());
        }
    }
    Ok(out)
}

fn pick<'a>(m: &'a HashMap<String, String>, key: &str, fallback: &'a str) -> &'a str {
    m.get(key)
        .map(String::as_str)
        .filter(|s| !s.is_empty())
        .unwrap_or(fallback)
}

fn hex_byte(s: &str) -> i32 {
    i32::from_str_radix(s, 16).unwrap_or(0)
}

fn hex_to_rgb(color: &str) -> (i32, i32, i32) {
    let c = color.strip_prefix('#').unwrap_or(color);
    if c.len() < 6 {
        return (0, 0, 0);
    }
    (hex_byte(&c[0..2]), hex_byte(&c[2..4]), hex_byte(&c[4..6]))
}

fn rgb_to_hex(r: i32, g: i32, b: i32) -> String {
    format!(
        "#{:02x}{:02x}{:02x}",
        r.clamp(0, 255),
        g.clamp(0, 255),
        b.clamp(0, 255)
    )
}

fn blend(color1: &str, color2: &str, factor: f64) -> String {
    let (r1, g1, b1) = hex_to_rgb(color1);
    let (r2, g2, b2) = hex_to_rgb(color2);
    let r = (r1 as f64 + (r2 - r1) as f64 * factor) as i32;
    let g = (g1 as f64 + (g2 - g1) as f64 * factor) as i32;
    let b = (b1 as f64 + (b2 - b1) as f64 * factor) as i32;
    rgb_to_hex(r, g, b)
}

fn user_home() -> PathBuf {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/tmp"))
}

pub fn run_opencode_theme(args: &[String]) -> Result<()> {
    let home = user_home();
    let scss_path = args
        .first()
        .map(PathBuf::from)
        .unwrap_or_else(|| home.join(".local/state/quickshell/user/generated/material_colors.scss"));
    let palette_path = args
        .get(1)
        .map(PathBuf::from)
        .unwrap_or_else(|| home.join(".local/state/quickshell/user/generated/palette.json"));
    let terminal_path = args
        .get(2)
        .map(PathBuf::from)
        .unwrap_or_else(|| home.join(".local/state/quickshell/user/generated/terminal.json"));
    let output_dir = args
        .get(3)
        .map(PathBuf::from)
        .unwrap_or_else(|| home.join(".config/opencode/themes"));

    let mut colors = parse_scss(&scss_path)
        .map_err(|_| anyhow!("Error: {} not found", scss_path.display()))?;
    if let Ok(pal) = read_string_map_json(&palette_path) {
        colors.extend(pal);
    }
    if let Ok(term) = read_string_map_json(&terminal_path) {
        colors.extend(term);
    }

    let primary = pick(&colors, "primary", "#7aa2f7");
    let on_primary = pick(&colors, "onPrimary", pick(&colors, "on_primary", "#1a1b26"));
    let primary_container = pick(
        &colors,
        "primaryContainer",
        pick(&colors, "primary_container", "#004c6b"),
    );
    let on_primary_container = pick(
        &colors,
        "onPrimaryContainer",
        pick(&colors, "on_primary_container", "#c6e7ff"),
    );
    let secondary = pick(&colors, "secondary", "#bb9af7");
    let secondary_container = pick(
        &colors,
        "secondaryContainer",
        pick(&colors, "secondary_container", "#394b58"),
    );
    let tertiary = pick(&colors, "tertiary", "#9ece6a");
    let tertiary_container = pick(
        &colors,
        "tertiaryContainer",
        pick(&colors, "tertiary_container", "#958bb1"),
    );
    let surface = pick(&colors, "surface", "#0f1417");
    let surface_dim = pick(&colors, "surfaceDim", pick(&colors, "surface_dim", "#0f1417"));
    let surface_bright = pick(
        &colors,
        "surfaceBright",
        pick(&colors, "surface_bright", "#353a3d"),
    );
    let surface_container = pick(
        &colors,
        "surfaceContainer",
        pick(&colors, "surface_container", "#1c2024"),
    );
    let surface_container_low = pick(
        &colors,
        "surfaceContainerLow",
        pick(&colors, "surface_container_low", "#181c1f"),
    );
    let surface_container_high = pick(
        &colors,
        "surfaceContainerHigh",
        pick(&colors, "surface_container_high", "#262b2e"),
    );
    let surface_container_highest = pick(
        &colors,
        "surfaceContainerHighest",
        pick(&colors, "surface_container_highest", "#313539"),
    );
    let on_surface = pick(&colors, "onSurface", pick(&colors, "on_surface", "#dfe3e7"));
    let on_surface_variant = pick(
        &colors,
        "onSurfaceVariant",
        pick(&colors, "on_surface_variant", "#c1c7ce"),
    );
    let outline = pick(&colors, "outline", "#8b9298");
    let outline_variant = pick(
        &colors,
        "outlineVariant",
        pick(&colors, "outline_variant", "#41484d"),
    );
    let shadow = pick(&colors, "shadow", "#000000");
    let error_col = pick(&colors, "error", "#ffb4ab");
    let error_container = pick(
        &colors,
        "errorContainer",
        pick(&colors, "error_container", "#93000a"),
    );
    let success = pick(&colors, "success", "#b5ccba");
    let success_container = pick(
        &colors,
        "successContainer",
        pick(&colors, "success_container", "#374b3e"),
    );
    let inverse_surface = pick(
        &colors,
        "inverseSurface",
        pick(&colors, "inverse_surface", "#dfe3e7"),
    );
    let inverse_on_surface = pick(
        &colors,
        "inverseOnSurface",
        pick(&colors, "inverse_on_surface", "#2c3135"),
    );
    let inverse_primary = pick(
        &colors,
        "inversePrimary",
        pick(&colors, "inverse_primary", primary),
    );

    let term: Vec<String> = (0..16)
        .map(|i| pick(&colors, &format!("term{i}"), "#888888").to_owned())
        .collect();

    let diff_added_bg = blend(surface_container, success, 0.15);
    let diff_removed_bg = blend(surface_container, error_col, 0.15);
    let diff_added_line_bg = blend(surface_container, success, 0.10);
    let diff_removed_line_bg = blend(surface_container, error_col, 0.10);
    let warning = pick(&colors, "term3", &term[3]);

    let light_primary = inverse_primary;
    let light_secondary = blend(secondary, inverse_surface, 0.25);
    let light_accent = blend(tertiary, inverse_surface, 0.25);
    let light_error = blend(error_col, inverse_surface, 0.35);
    let light_warning = blend(warning, inverse_surface, 0.40);
    let light_success = blend(success, inverse_surface, 0.35);
    let light_text_muted = blend(inverse_on_surface, inverse_surface, 0.35);
    let light_bg_panel = blend(inverse_surface, "#ffffff", 0.06);
    let light_bg_element = blend(inverse_surface, "#ffffff", 0.12);
    let light_bg_menu = blend(inverse_surface, "#ffffff", 0.08);
    let light_border = blend(inverse_on_surface, inverse_surface, 0.55);
    let light_border_subtle = blend(inverse_on_surface, inverse_surface, 0.70);
    let light_diff_added_bg = blend(inverse_surface, &light_success, 0.18);
    let light_diff_removed_bg = blend(inverse_surface, &light_error, 0.18);
    let light_diff_added_line_bg = blend(inverse_surface, &light_success, 0.12);
    let light_diff_removed_line_bg = blend(inverse_surface, &light_error, 0.12);
    let light_md_link = blend(tertiary, inverse_surface, 0.20);
    let light_md_code = blend(&term[2], inverse_surface, 0.20);
    let light_syn_keyword = blend(&term[5], inverse_surface, 0.25);
    let light_syn_func = blend(&term[4], inverse_surface, 0.25);
    let light_syn_var = blend(&term[6], inverse_surface, 0.20);
    let light_syn_str = blend(&term[2], inverse_surface, 0.25);
    let light_syn_num = blend(&term[13], inverse_surface, 0.25);
    let light_syn_type = blend(&term[3], inverse_surface, 0.25);

    let tv = |dark: &str, light: &str| json!({"dark": dark, "light": light});

    let payload = json!({
        "$schema": "https://opencode.ai/theme.json",
        "defs": {
            "m3Primary": primary,
            "m3OnPrimary": on_primary,
            "m3PrimaryContainer": primary_container,
            "m3OnPrimaryContainer": on_primary_container,
            "m3Secondary": secondary,
            "m3SecondaryContainer": secondary_container,
            "m3Tertiary": tertiary,
            "m3TertiaryContainer": tertiary_container,
            "m3Surface": surface,
            "m3SurfaceDim": surface_dim,
            "m3SurfaceBright": surface_bright,
            "m3SurfaceContainer": surface_container,
            "m3SurfaceContainerLow": surface_container_low,
            "m3SurfaceContainerHigh": surface_container_high,
            "m3SurfaceContainerHighest": surface_container_highest,
            "m3OnSurface": on_surface,
            "m3OnSurfaceVariant": on_surface_variant,
            "m3Outline": outline,
            "m3OutlineVariant": outline_variant,
            "m3Error": error_col,
            "m3ErrorContainer": error_container,
            "m3Success": success,
            "m3SuccessContainer": success_container,
            "m3Shadow": shadow,
            "m3InverseSurface": inverse_surface,
            "m3InverseOnSurface": inverse_on_surface,
            "m3InversePrimary": inverse_primary,
            "ansiRed": term[1],
            "ansiGreen": term[2],
            "ansiYellow": term[3],
            "ansiBlue": term[4],
            "ansiMagenta": term[5],
            "ansiCyan": term[6],
            "ansiBrightRed": term[9],
            "ansiBrightGreen": term[10],
            "ansiBrightYellow": term[11],
            "ansiBrightBlue": term[12],
            "ansiBrightMagenta": term[13],
            "ansiBrightCyan": term[14],
        },
        "theme": {
            "primary": tv("m3Primary", "m3InversePrimary"),
            "secondary": tv("m3Secondary", &light_secondary),
            "accent": tv("m3Tertiary", &light_accent),
            "error": tv("m3Error", &light_error),
            "warning": tv(warning, &light_warning),
            "success": tv("m3Success", &light_success),
            "info": tv("m3Primary", light_primary),
            "text": tv("m3OnSurface", "m3InverseOnSurface"),
            "textMuted": tv("m3OnSurfaceVariant", &light_text_muted),
            "selectedListItemText": tv("m3Surface", inverse_surface),
            "background": tv("m3Surface", "m3InverseSurface"),
            "backgroundPanel": tv("m3SurfaceContainer", &light_bg_panel),
            "backgroundElement": tv("m3SurfaceContainerHigh", &light_bg_element),
            "backgroundMenu": tv("m3SurfaceContainerHigh", &light_bg_menu),
            "border": tv("m3OutlineVariant", &light_border),
            "borderActive": tv("m3Primary", "m3InversePrimary"),
            "borderSubtle": tv(&blend(outline_variant, surface, 0.3), &light_border_subtle),
            "diffAdded": tv("m3Success", &light_success),
            "diffRemoved": tv("m3Error", &light_error),
            "diffContext": tv("m3OnSurfaceVariant", &light_text_muted),
            "diffHunkHeader": tv("m3Outline", &light_border),
            "diffHighlightAdded": tv("ansiBrightGreen", "ansiGreen"),
            "diffHighlightRemoved": tv("ansiBrightRed", "ansiRed"),
            "diffAddedBg": tv(&diff_added_bg, &light_diff_added_bg),
            "diffRemovedBg": tv(&diff_removed_bg, &light_diff_removed_bg),
            "diffContextBg": tv("m3SurfaceContainer", &light_bg_panel),
            "diffLineNumber": tv("m3Outline", &light_border),
            "diffAddedLineNumberBg": tv(&diff_added_line_bg, &light_diff_added_line_bg),
            "diffRemovedLineNumberBg": tv(&diff_removed_line_bg, &light_diff_removed_line_bg),
            "markdownText": tv("m3OnSurface", "m3InverseOnSurface"),
            "markdownHeading": tv("m3Primary", "m3InversePrimary"),
            "markdownLink": tv("m3Tertiary", &light_md_link),
            "markdownLinkText": tv("ansiCyan", "ansiBlue"),
            "markdownCode": tv("ansiGreen", &light_md_code),
            "markdownBlockQuote": tv("m3OnSurfaceVariant", &light_text_muted),
            "markdownEmph": tv("ansiYellow", &light_warning),
            "markdownStrong": tv("ansiBrightYellow", warning),
            "markdownHorizontalRule": tv("m3OutlineVariant", &light_border),
            "markdownListItem": tv("m3Primary", "m3InversePrimary"),
            "markdownListEnumeration": tv("m3Secondary", &light_secondary),
            "markdownImage": tv("ansiMagenta", &light_accent),
            "markdownImageText": tv("ansiBrightMagenta", "ansiMagenta"),
            "markdownCodeBlock": tv("m3OnSurface", "m3InverseOnSurface"),
            "syntaxComment": tv("m3Outline", &light_text_muted),
            "syntaxKeyword": tv("ansiMagenta", &light_syn_keyword),
            "syntaxFunction": tv("ansiBlue", &light_syn_func),
            "syntaxVariable": tv("ansiCyan", &light_syn_var),
            "syntaxString": tv("ansiGreen", &light_syn_str),
            "syntaxNumber": tv("ansiBrightMagenta", &light_syn_num),
            "syntaxType": tv("ansiYellow", &light_syn_type),
            "syntaxOperator": tv("m3OnSurfaceVariant", &light_text_muted),
            "syntaxPunctuation": tv("m3OnSurfaceVariant", &light_text_muted),
            "thinkingOpacity": 0.6
        }
    });

    fs::create_dir_all(&output_dir)?;
    let output_path = output_dir.join("alis.json");
    let mut data = serde_json::to_vec_pretty(&payload)?;
    data.push(b'\n');
    fs::write(&output_path, data)?;
    println!("[opencode] Theme generated: {}", output_path.display());
    Ok(())
}

// ── VSCode & Forks Theme Generator ─────────────────────────────────────

const VSCODE_THEME_NAME: &str = "Alis Material";
const VSCODE_THEME_NAME_LIGHT: &str = "Alis Material Light";
const VSCODE_EXTENSION_ID: &str = "alis-material-theme";
const VSCODE_FILE_DARK: &str = "alis-material-color-theme.json";
const VSCODE_FILE_LIGHT: &str = "alis-material-light-color-theme.json";
const VSCODE_PREV_KEY: &str = "alis.previousColorTheme";

const VSCODE_FORKS: &[(&str, &str, &str)] = &[
    ("code", "Code", ".vscode/extensions"),
    ("codium", "VSCodium", ".vscode-oss/extensions"),
    ("code-oss", "Code - OSS", ".vscode-oss/extensions"),
    ("code-insiders", "Code - Insiders", ".vscode-insiders/extensions"),
    ("cursor", "Cursor", ".cursor/extensions"),
    ("windsurf", "Windsurf", ".windsurf/extensions"),
    ("windsurf-next", "Windsurf - Next", ".windsurf-next/extensions"),
    ("qoder", "Qoder", ".qoder/extensions"),
    ("antigravity", "Antigravity", ".antigravity/extensions"),
    ("positron", "Positron", ".positron/extensions"),
    ("void", "Void", ".void/extensions"),
    ("melty", "Melty", ".melty/extensions"),
    ("pearai", "PearAI", ".pearai/extensions"),
    ("aide", "Aide", ".aide/extensions"),
];

#[derive(Clone, Copy)]
struct Hsl {
    h: f64,
    s: f64,
    l: f64,
}

fn hex_to_hsl_deg(hex: &str) -> Hsl {
    let hex = hex.strip_prefix('#').unwrap_or(hex);
    if hex.len() < 6 {
        return Hsl { h: 0.0, s: 0.0, l: 0.0 };
    }
    let r = hex_byte(&hex[0..2]) as f64 / 255.0;
    let g = hex_byte(&hex[2..4]) as f64 / 255.0;
    let b = hex_byte(&hex[4..6]) as f64 / 255.0;
    let max_c = r.max(g).max(b);
    let min_c = r.min(g).min(b);
    let l = (max_c + min_c) / 2.0;
    if (max_c - min_c).abs() < f64::EPSILON {
        return Hsl { h: 0.0, s: 0.0, l };
    }
    let d = max_c - min_c;
    let s = if l > 0.5 {
        d / (2.0 - max_c - min_c)
    } else {
        d / (max_c + min_c)
    };
    let mut h = if (max_c - r).abs() < f64::EPSILON {
        let mut v = (g - b) / d;
        if g < b {
            v += 6.0;
        }
        v
    } else if (max_c - g).abs() < f64::EPSILON {
        (b - r) / d + 2.0
    } else {
        (r - g) / d + 4.0
    };
    h *= 60.0;
    Hsl { h, s, l }
}

fn hsl_deg_to_hex(c: Hsl) -> String {
    let s = c.s.clamp(0.0, 1.0);
    let l = c.l.clamp(0.0, 1.0);
    let h = c.h.rem_euclid(360.0);
    let ch = (1.0 - (2.0 * l - 1.0).abs()) * s;
    let x = ch * (1.0 - ((h / 60.0).rem_euclid(2.0) - 1.0).abs());
    let m = l - ch / 2.0;
    let (r, g, b) = if h < 60.0 {
        (ch, x, 0.0)
    } else if h < 120.0 {
        (x, ch, 0.0)
    } else if h < 180.0 {
        (0.0, ch, x)
    } else if h < 240.0 {
        (0.0, x, ch)
    } else if h < 300.0 {
        (x, 0.0, ch)
    } else {
        (ch, 0.0, x)
    };
    let to_u8 = |v: f64| ((v + m) * 255.0) as i32;
    rgb_to_hex(to_u8(r), to_u8(g), to_u8(b))
}

fn saturate_color(hex: &str, factor: f64, min_sat: f64) -> String {
    let mut c = hex_to_hsl_deg(hex);
    if c.s < 0.01 {
        return hex.to_owned();
    }
    c.s = (c.s * factor).min(1.0).max(min_sat);
    hsl_deg_to_hex(c)
}

fn adjust_lightness_bounds(hex: &str, min_l: f64, max_l: f64) -> String {
    let mut c = hex_to_hsl_deg(hex);
    c.l = c.l.clamp(min_l, max_l);
    hsl_deg_to_hex(c)
}

fn rel_luminance(hex: &str) -> f64 {
    let h = hex.strip_prefix('#').unwrap_or(hex);
    if h.len() < 6 {
        return 0.0;
    }
    let lin = |v: i32| {
        let c = v as f64 / 255.0;
        if c <= 0.03928 {
            c / 12.92
        } else {
            ((c + 0.055) / 1.055).powf(2.4)
        }
    };
    0.2126 * lin(hex_byte(&h[0..2]))
        + 0.7152 * lin(hex_byte(&h[2..4]))
        + 0.0722 * lin(hex_byte(&h[4..6]))
}

fn contrast_hex(a: &str, b: &str) -> f64 {
    let mut la = rel_luminance(a);
    let mut lb = rel_luminance(b);
    if la < lb {
        std::mem::swap(&mut la, &mut lb);
    }
    (la + 0.05) / (lb + 0.05)
}

fn with_contrast(hex: &str, bg: &str, ratio: f64, dark: bool) -> String {
    let mut c = hex_to_hsl_deg(hex);
    for _ in 0..60 {
        if contrast_hex(&hsl_deg_to_hex(c), bg) >= ratio {
            break;
        }
        if dark {
            c.l = (c.l + 0.01).min(0.96);
        } else {
            c.l = (c.l - 0.01).max(0.04);
        }
    }
    hsl_deg_to_hex(c)
}

fn muted_ink(fg: &str, bg: &str, alpha: u8, dark: bool) -> String {
    let fg_clean = format!("#{}", fg.strip_prefix('#').unwrap_or(fg));
    let bg_clean = format!("#{}", bg.strip_prefix('#').unwrap_or(bg));
    let a = alpha as f64 / 255.0;
    let mix = |i: usize| -> i32 {
        let fv = hex_byte(&fg_clean[i..i + 2]) as f64;
        let bv = hex_byte(&bg_clean[i..i + 2]) as f64;
        (fv * a + bv * (1.0 - a) + 0.5) as i32
    };
    let over = rgb_to_hex(mix(1), mix(3), mix(5));
    if contrast_hex(&over, &bg_clean) >= 4.5 {
        format!("{fg_clean}{alpha:02x}")
    } else {
        with_contrast(&fg_clean, &bg_clean, 4.5, dark)
    }
}

fn syntax_color(
    term_colors: &HashMap<String, String>,
    primary: &str,
    bg: &str,
    term_idx: usize,
) -> String {
    let raw = pick(term_colors, &format!("term{term_idx}"), "#888888");
    let dark = hex_to_hsl_deg(bg).l < 0.5;
    if dark {
        let boosted = saturate_color(raw, 2.1, 0.50);
        let blended = blend(&boosted, primary, 0.28);
        with_contrast(&adjust_lightness_bounds(&blended, 0.50, 0.88), bg, 4.5, true)
    } else {
        let boosted = saturate_color(raw, 1.2, 0.45);
        let blended = blend(&boosted, primary, 0.20);
        with_contrast(&adjust_lightness_bounds(&blended, 0.22, 0.46), bg, 4.5, false)
    }
}

pub fn strip_jsonc_comments(data: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(data.len());
    let mut in_string = false;
    let mut escaped = false;
    let mut i = 0;
    let n = data.len();

    while i < n {
        let c = data[i];
        if in_string {
            out.push(c);
            if escaped {
                escaped = false;
            } else if c == b'\\' {
                escaped = true;
            } else if c == b'"' {
                in_string = false;
            }
            i += 1;
            continue;
        }
        if c == b'"' {
            in_string = true;
            out.push(c);
            i += 1;
        } else if c == b'/' && i + 1 < n && data[i + 1] == b'/' {
            while i < n && data[i] != b'\n' {
                i += 1;
            }
        } else if c == b'/' && i + 1 < n && data[i + 1] == b'*' {
            i += 2;
            while i + 1 < n && !(data[i] == b'*' && data[i + 1] == b'/') {
                i += 1;
            }
            if i + 1 < n {
                i += 2;
            } else {
                i = n;
            }
        } else if c == b',' && i + 1 < n {
            let mut j = i + 1;
            while j < n && matches!(data[j], b' ' | b'\t' | b'\n' | b'\r') {
                j += 1;
            }
            if j < n && matches!(data[j], b']' | b'}') {
                i += 1;
            } else {
                out.push(c);
                i += 1;
            }
        } else {
            out.push(c);
            i += 1;
        }
    }
    out
}

fn xdg_config_dir() -> PathBuf {
    if let Some(xdg) = std::env::var_os("XDG_CONFIG_HOME")
        && !xdg.is_empty()
    {
        return PathBuf::from(xdg);
    }
    user_home().join(".config")
}

fn vscode_ext_base(fork_key: &str) -> PathBuf {
    let rel = VSCODE_FORKS
        .iter()
        .find(|&&(k, _, _)| k == fork_key)
        .map(|&(_, _, ext)| ext.to_owned())
        .unwrap_or_else(|| format!(".{fork_key}/extensions"));
    user_home().join(rel)
}

fn vscode_settings_path(fork_name: &str) -> PathBuf {
    xdg_config_dir().join(fork_name).join("User/settings.json")
}

fn ensure_vscode_registered(fork_key: &str, ext_dir: &Path) -> Result<()> {
    let ext_base = vscode_ext_base(fork_key);
    let registry_path = ext_base.join("extensions.json");
    let mut entries: Vec<Value> = fs::read_to_string(&registry_path)
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default();

    let ext_id = format!("alis.{VSCODE_EXTENSION_ID}");
    if entries.iter().any(|e| {
        e.get("identifier")
            .and_then(|id| id.get("id"))
            .and_then(Value::as_str)
            == Some(ext_id.as_str())
    }) {
        return Ok(());
    }

    entries.push(json!({
        "identifier": {"id": ext_id},
        "version": "1.0.0",
        "location": {"$mid": 1.0, "path": ext_dir.to_string_lossy(), "scheme": "file"},
        "relativeLocation": VSCODE_EXTENSION_ID
    }));
    let tmp = registry_path.with_extension("json.tmp");
    fs::write(&tmp, serde_json::to_vec(&entries)?)?;
    fs::rename(&tmp, &registry_path)?;
    Ok(())
}

fn unregister_vscode_extension(fork_key: &str) {
    let registry_path = vscode_ext_base(fork_key).join("extensions.json");
    let Ok(text) = fs::read_to_string(&registry_path) else {
        return;
    };
    let Ok(entries) = serde_json::from_str::<Vec<Value>>(&text) else {
        return;
    };
    let ext_id = format!("alis.{VSCODE_EXTENSION_ID}");
    let orig_len = entries.len();
    let filtered: Vec<Value> = entries
        .into_iter()
        .filter(|e| {
            e.get("identifier")
                .and_then(|id| id.get("id"))
                .and_then(Value::as_str)
                != Some(ext_id.as_str())
        })
        .collect();
    if filtered.len() == orig_len {
        return;
    }
    let tmp = registry_path.with_extension("json.tmp");
    if let Ok(bytes) = serde_json::to_vec(&filtered)
        && fs::write(&tmp, bytes).is_ok()
    {
        let _ = fs::rename(&tmp, &registry_path);
    }
}

fn write_vscode_manifest(ext_dir: &Path) -> Result<()> {
    let manifest = json!({
        "name": VSCODE_EXTENSION_ID,
        "displayName": VSCODE_THEME_NAME,
        "description": "Dynamic Material You theme — auto-generated by Alis from wallpaper colors",
        "version": "1.0.0",
        "publisher": "alis",
        "engines": {"vscode": "^1.34.0"},
        "categories": ["Themes"],
        "contributes": {
            "themes": [
                {"label": VSCODE_THEME_NAME, "uiTheme": "vs-dark", "path": format!("./themes/{VSCODE_FILE_DARK}"), "_watch": true},
                {"label": VSCODE_THEME_NAME_LIGHT, "uiTheme": "vs", "path": format!("./themes/{VSCODE_FILE_LIGHT}"), "_watch": true}
            ]
        }
    });
    let mut data = serde_json::to_vec_pretty(&manifest)?;
    data.push(b'\n');
    fs::write(ext_dir.join("package.json"), data)?;
    Ok(())
}

fn build_vscode_colors(
    colors: &HashMap<String, String>,
    term_colors: &HashMap<String, String>,
) -> Map<String, Value> {
    let bg = pick(colors, "background", pick(colors, "surface", "#080809"));
    let fg = pick(
        colors,
        "on_background",
        pick(colors, "on_surface", "#e3dfd9"),
    );
    let surface = pick(colors, "surface", "#080809");
    let surface_lowest = pick(colors, "surface_container_lowest", surface);
    let surface_low = pick(colors, "surface_container_low", "#0c0c0e");
    let surface_std = pick(colors, "surface_container", "#121115");
    let surface_high = pick(colors, "surface_container_high", "#1a191d");
    let surface_highest = pick(colors, "surface_container_highest", "#232126");
    let on_surface = pick(colors, "on_surface", "#e3dfd9");
    let on_surface_variant = pick(colors, "on_surface_variant", "#c4bfb8");
    let outline = pick(colors, "outline", "#5c5862");
    let outline_variant = pick(colors, "outline_variant", "#3a363e");
    let primary = pick(colors, "primary", "#d4b796");
    let on_primary = pick(colors, "on_primary", "#241c14");
    let primary_container = pick(colors, "primary_container", "#33281d");
    let on_primary_container = pick(colors, "on_primary_container", "#eddccb");
    let secondary = pick(colors, "secondary", "#ccc2b2");
    let tertiary = pick(colors, "tertiary", "#b8cbb8");
    let error_col = pick(colors, "error", "#ffb4ab");

    let term_defaults = [
        ("term0", surface_lowest),
        ("term1", error_col),
        ("term2", tertiary),
        ("term3", secondary),
        ("term4", primary),
        ("term5", secondary),
        ("term6", tertiary),
        ("term7", on_surface),
        ("term8", outline_variant),
        ("term9", error_col),
        ("term10", tertiary),
        ("term11", secondary),
        ("term12", primary),
        ("term13", secondary),
        ("term14", tertiary),
        ("term15", fg),
    ];
    let term = |name: &str| -> String {
        let fb = term_defaults
            .iter()
            .find(|&&(k, _)| k == name)
            .map(|&(_, v)| v)
            .unwrap_or("#888888");
        pick(term_colors, name, fb).to_owned()
    };
    let term_bg = term("term0");
    let term_fg = term("term15");
    let transparent = "#00000000";

    let mut m = Map::new();
    let mut set = |k: &str, v: &str| {
        m.insert(k.to_owned(), Value::String(v.to_owned()));
    };
    set("focusBorder", primary);
    set("foreground", fg);
    set("disabledForeground", &format!("{on_surface_variant}80"));
    set("widget.shadow", "#00000060");
    set("selection.background", &format!("{primary}60"));
    set("descriptionForeground", on_surface_variant);
    set("errorForeground", error_col);
    set("icon.foreground", on_surface);
    set("window.activeBorder", transparent);
    set("window.inactiveBorder", transparent);
    set("textBlockQuote.background", surface_low);
    set("textBlockQuote.border", transparent);
    set("textCodeBlock.background", surface_low);
    set("textLink.activeForeground", primary);
    set("textLink.foreground", primary);
    set("textPreformat.foreground", tertiary);
    set("textSeparator.foreground", transparent);
    set("button.background", primary_container);
    set("button.foreground", on_primary_container);
    set("button.hoverBackground", &format!("{primary_container}dd"));
    set("button.secondaryBackground", surface_high);
    set("button.secondaryForeground", on_surface);
    set("button.secondaryHoverBackground", surface_highest);
    set("checkbox.background", surface_std);
    set("checkbox.border", transparent);
    set("checkbox.foreground", on_surface);
    set("dropdown.background", surface_low);
    set("dropdown.border", transparent);
    set("dropdown.foreground", on_surface);
    set("dropdown.listBackground", surface_std);
    set("input.background", surface_low);
    set("input.border", transparent);
    set("input.foreground", on_surface);
    set("input.placeholderForeground", &format!("{on_surface_variant}80"));
    set("inputOption.activeBackground", &format!("{primary}40"));
    set("inputOption.activeBorder", primary);
    set("inputOption.activeForeground", on_surface);
    set("inputValidation.errorBackground", &format!("{error_col}20"));
    set("inputValidation.errorBorder", error_col);
    set("scrollbar.shadow", "#00000040");
    set("scrollbarSlider.activeBackground", &format!("{on_surface_variant}80"));
    set("scrollbarSlider.background", &format!("{on_surface_variant}40"));
    set("scrollbarSlider.hoverBackground", &format!("{on_surface_variant}60"));
    set("badge.background", primary_container);
    set("badge.foreground", on_primary_container);
    set("progressBar.background", primary);
    set("list.activeSelectionBackground", surface_high);
    set("list.activeSelectionForeground", on_surface);
    set("list.dropBackground", &format!("{primary}40"));
    set("list.focusBackground", surface_high);
    set("list.focusForeground", on_surface);
    set("list.highlightForeground", primary);
    set("list.hoverBackground", surface_std);
    set("list.hoverForeground", on_surface);
    set("list.inactiveSelectionBackground", surface_std);
    set("list.inactiveSelectionForeground", on_surface);
    set("list.invalidItemForeground", error_col);
    set("list.errorForeground", error_col);
    set("list.warningForeground", tertiary);
    set("listFilterWidget.background", surface_high);
    set("listFilterWidget.outline", primary);
    set("listFilterWidget.noMatchesOutline", error_col);
    set("list.filterMatchBackground", &format!("{primary}40"));
    set("tree.indentGuidesStroke", &format!("{outline_variant}40"));
    set("activityBar.background", surface_lowest);
    set("activityBar.foreground", on_surface);
    set("activityBar.inactiveForeground", on_surface_variant);
    set("activityBar.border", transparent);
    set("activityBarBadge.background", primary);
    set("activityBarBadge.foreground", on_primary);
    set("activityBar.activeBorder", primary);
    set("activityBar.activeBackground", surface_std);
    set("sideBar.background", surface_lowest);
    set("sideBar.foreground", on_surface);
    set("sideBar.border", transparent);
    set("sideBarTitle.foreground", on_surface);
    set("sideBarSectionHeader.background", surface_low);
    set("sideBarSectionHeader.foreground", on_surface);
    set("sideBarSectionHeader.border", transparent);
    set("editorGroup.border", transparent);
    set("editorGroup.dropBackground", &format!("{primary}20"));
    set("editorGroupHeader.noTabsBackground", surface_lowest);
    set("editorGroupHeader.tabsBackground", surface_lowest);
    set("editorGroupHeader.tabsBorder", transparent);
    set("editorGroupHeader.border", transparent);
    set("tab.activeBackground", surface_low);
    set("tab.activeForeground", on_surface);
    set("tab.border", transparent);
    set("tab.activeBorder", primary);
    set("tab.unfocusedActiveBorder", outline);
    set("tab.inactiveBackground", surface_lowest);
    set("tab.inactiveForeground", on_surface_variant);
    set("tab.unfocusedActiveForeground", on_surface_variant);
    set("tab.unfocusedInactiveForeground", &format!("{on_surface_variant}80"));
    set("tab.hoverBackground", surface_low);
    set("tab.unfocusedHoverBackground", surface_low);
    set("tab.hoverForeground", on_surface);
    set("tab.hoverBorder", outline);
    set("tab.lastPinnedBorder", outline);
    set("editor.background", bg);
    set("editor.foreground", fg);
    set("editorPane.background", bg);
    set("editorGutter.background", bg);
    set("editorOverviewRuler.background", bg);
    set("editorStickyScroll.background", bg);
    set("editorStickyScrollHover.background", surface_low);
    set("editorLineNumber.foreground", on_surface_variant);
    set("editorLineNumber.activeForeground", on_surface);
    set("editorCursor.foreground", primary);
    set("editor.selectionBackground", &format!("{primary_container}66"));
    set("editor.inactiveSelectionBackground", &format!("{primary_container}33"));
    set("editor.selectionHighlightBackground", &format!("{primary_container}4d"));
    set("editor.wordHighlightBackground", &format!("{secondary}30"));
    set("editor.wordHighlightStrongBackground", &format!("{secondary}50"));
    set("editor.findMatchBackground", &format!("{tertiary}40"));
    set("editor.findMatchHighlightBackground", &format!("{tertiary}30"));
    set("editor.findRangeHighlightBackground", &format!("{primary}20"));
    set("editor.hoverHighlightBackground", &format!("{primary}20"));
    set("editor.lineHighlightBackground", &format!("{surface_low}80"));
    set("editor.lineHighlightBorder", &format!("{outline_variant}00"));
    set("editorLink.activeForeground", primary);
    set("editor.rangeHighlightBackground", &format!("{surface_std}40"));
    set("editorWhitespace.foreground", &format!("{on_surface_variant}40"));
    set("editorIndentGuide.background", outline_variant);
    set("editorIndentGuide.activeBackground", outline);
    set("editorRuler.foreground", outline_variant);
    set("editorCodeLens.foreground", on_surface_variant);
    set("editorBracketMatch.background", &format!("{primary}20"));
    set("editorBracketMatch.border", primary);
    set("diffEditor.insertedTextBackground", &format!("{tertiary}20"));
    set("diffEditor.removedTextBackground", &format!("{error_col}20"));
    set("diffEditor.insertedLineBackground", &format!("{tertiary}15"));
    set("diffEditor.removedLineBackground", &format!("{error_col}15"));
    set("diffEditor.diagonalFill", &format!("{outline_variant}80"));
    set("diffEditor.border", transparent);
    set("editorWidget.background", surface_high);
    set("editorWidget.border", outline);
    set("editorWidget.foreground", on_surface);
    set("editorSuggestWidget.background", surface_high);
    set("editorSuggestWidget.border", outline);
    set("editorSuggestWidget.foreground", on_surface);
    set("editorSuggestWidget.highlightForeground", primary);
    set("editorSuggestWidget.selectedBackground", surface_highest);
    set("editorHoverWidget.background", surface_high);
    set("editorHoverWidget.border", outline);
    set("peekView.border", primary);
    set("peekViewEditor.background", surface_low);
    set("peekViewEditorGutter.background", surface_low);
    set("peekViewEditor.matchHighlightBackground", &format!("{primary}40"));
    set("peekViewResult.background", surface_std);
    set("peekViewResult.fileForeground", on_surface);
    set("peekViewResult.lineForeground", on_surface_variant);
    set("peekViewResult.matchHighlightBackground", &format!("{primary}40"));
    set("peekViewResult.selectionBackground", surface_high);
    set("peekViewResult.selectionForeground", on_surface);
    set("peekViewTitle.background", surface_std);
    set("peekViewTitleDescription.foreground", on_surface_variant);
    set("peekViewTitleLabel.foreground", on_surface);
    set("merge.currentHeaderBackground", &format!("{primary}80"));
    set("merge.currentContentBackground", &format!("{primary}20"));
    set("merge.incomingHeaderBackground", &format!("{secondary}80"));
    set("merge.incomingContentBackground", &format!("{secondary}20"));
    set("merge.border", outline);
    set("mergeEditor.background", bg);
    set("editorOverviewRuler.currentContentForeground", primary);
    set("editorOverviewRuler.incomingContentForeground", secondary);
    set("panel.background", surface_lowest);
    set("panel.border", transparent);
    set("panelTitle.activeBorder", primary);
    set("panelTitle.activeForeground", on_surface);
    set("panelTitle.inactiveForeground", on_surface_variant);
    set("panelInput.border", outline);
    set("statusBar.background", surface_lowest);
    set("statusBar.foreground", on_surface);
    set("statusBar.border", transparent);
    set("statusBar.debuggingBackground", error_col);
    set("statusBar.debuggingForeground", on_primary);
    set("statusBar.noFolderBackground", surface_lowest);
    set("statusBar.noFolderForeground", on_surface);
    set("statusBarItem.activeBackground", surface_high);
    set("statusBarItem.hoverBackground", surface_std);
    set("statusBarItem.prominentBackground", primary_container);
    set("statusBarItem.prominentForeground", on_primary_container);
    set("statusBarItem.prominentHoverBackground", &format!("{primary_container}dd"));
    set("titleBar.activeBackground", surface_lowest);
    set("titleBar.activeForeground", on_surface);
    set("titleBar.inactiveBackground", surface_lowest);
    set("titleBar.inactiveForeground", on_surface_variant);
    set("titleBar.border", transparent);
    set("menubar.selectionForeground", on_surface);
    set("menubar.selectionBackground", surface_std);
    set("menu.foreground", on_surface);
    set("menu.background", surface_high);
    set("menu.selectionForeground", on_surface);
    set("menu.selectionBackground", surface_highest);
    set("menu.separatorBackground", transparent);
    set("menu.border", transparent);
    set("notificationCenter.border", transparent);
    set("notificationCenterHeader.foreground", on_surface);
    set("notificationCenterHeader.background", surface_std);
    set("notificationToast.border", transparent);
    set("notifications.foreground", on_surface);
    set("notifications.background", surface_high);
    set("notifications.border", transparent);
    set("notificationLink.foreground", primary);
    set("extensionButton.prominentForeground", on_primary);
    set("extensionButton.prominentBackground", primary);
    set("extensionButton.prominentHoverBackground", &format!("{primary}dd"));
    set("pickerGroup.border", outline);
    set("pickerGroup.foreground", primary);
    set("quickInput.background", surface_high);
    set("quickInput.foreground", on_surface);
    set("terminal.background", &term_bg);
    set("terminal.foreground", &term_fg);
    set("terminal.ansiBlack", &term("term0"));
    set("terminal.ansiRed", &term("term1"));
    set("terminal.ansiGreen", &term("term2"));
    set("terminal.ansiYellow", &term("term3"));
    set("terminal.ansiBlue", &term("term4"));
    set("terminal.ansiMagenta", &term("term5"));
    set("terminal.ansiCyan", &term("term6"));
    set("terminal.ansiWhite", &term("term7"));
    set("terminal.ansiBrightBlack", &term("term8"));
    set("terminal.ansiBrightRed", &term("term9"));
    set("terminal.ansiBrightGreen", &term("term10"));
    set("terminal.ansiBrightYellow", &term("term11"));
    set("terminal.ansiBrightBlue", &term("term12"));
    set("terminal.ansiBrightMagenta", &term("term13"));
    set("terminal.ansiBrightCyan", &term("term14"));
    set("terminal.ansiBrightWhite", &term("term15"));
    set("terminal.selectionBackground", &format!("{primary}40"));
    set("terminalCursor.background", bg);
    set("terminalCursor.foreground", primary);
    set("debugToolBar.background", surface_high);
    set("debugToolBar.border", outline);
    set("editor.stackFrameHighlightBackground", &format!("{tertiary}30"));
    set("editor.focusedStackFrameHighlightBackground", &format!("{tertiary}50"));
    set("gitDecoration.addedResourceForeground", tertiary);
    set("gitDecoration.modifiedResourceForeground", secondary);
    set("gitDecoration.deletedResourceForeground", error_col);
    set("gitDecoration.untrackedResourceForeground", &format!("{tertiary}cc"));
    set("gitDecoration.ignoredResourceForeground", &format!("{on_surface_variant}80"));
    set("gitDecoration.conflictingResourceForeground", error_col);
    set("gitDecoration.submoduleResourceForeground", secondary);
    set("settings.headerForeground", on_surface);
    set("settings.modifiedItemIndicator", primary);
    set("settings.dropdownBackground", surface_low);
    set("settings.dropdownForeground", on_surface);
    set("settings.dropdownBorder", outline);
    set("settings.checkboxBackground", surface_std);
    set("settings.checkboxForeground", on_surface);
    set("settings.checkboxBorder", outline);
    set("settings.textInputBackground", surface_low);
    set("settings.textInputForeground", on_surface);
    set("settings.textInputBorder", outline);
    set("settings.numberInputBackground", surface_low);
    set("settings.numberInputForeground", on_surface);
    set("settings.numberInputBorder", outline);
    set("breadcrumb.foreground", on_surface_variant);
    set("breadcrumb.background", bg);
    set("breadcrumb.focusForeground", on_surface);
    set("breadcrumb.activeSelectionForeground", primary);
    set("breadcrumbPicker.background", surface_high);
    set("editor.snippetTabstopHighlightBackground", &format!("{primary}30"));
    set("editor.snippetTabstopHighlightBorder", primary);
    set("editor.snippetFinalTabstopHighlightBackground", &format!("{tertiary}30"));
    set("editor.snippetFinalTabstopHighlightBorder", tertiary);
    set("symbolIcon.arrayForeground", secondary);
    set("symbolIcon.booleanForeground", tertiary);
    set("symbolIcon.classForeground", primary);
    set("symbolIcon.colorForeground", secondary);
    set("symbolIcon.constantForeground", tertiary);
    set("symbolIcon.constructorForeground", primary);
    set("symbolIcon.enumeratorForeground", secondary);
    set("symbolIcon.enumeratorMemberForeground", tertiary);
    set("symbolIcon.eventForeground", error_col);
    set("symbolIcon.fieldForeground", secondary);
    set("symbolIcon.fileForeground", on_surface);
    set("symbolIcon.folderForeground", on_surface);
    set("symbolIcon.functionForeground", primary);
    set("symbolIcon.interfaceForeground", secondary);
    set("symbolIcon.keyForeground", tertiary);
    set("symbolIcon.keywordForeground", secondary);
    set("symbolIcon.methodForeground", primary);
    set("symbolIcon.moduleForeground", on_surface);
    set("symbolIcon.namespaceForeground", on_surface);
    set("symbolIcon.nullForeground", on_surface_variant);
    set("symbolIcon.numberForeground", tertiary);
    set("symbolIcon.objectForeground", secondary);
    set("symbolIcon.operatorForeground", secondary);
    set("symbolIcon.packageForeground", on_surface);
    set("symbolIcon.propertyForeground", secondary);
    set("symbolIcon.referenceForeground", secondary);
    set("symbolIcon.snippetForeground", tertiary);
    set("symbolIcon.stringForeground", tertiary);
    set("symbolIcon.structForeground", primary);
    set("symbolIcon.textForeground", on_surface);
    set("symbolIcon.typeParameterForeground", secondary);
    set("symbolIcon.unitForeground", tertiary);
    set("symbolIcon.variableForeground", on_surface);
    set("notebook.editorBackground", bg);
    set("notebook.cellEditorBackground", bg);
    set("notebook.cellBorderColor", transparent);
    set("notebook.cellToolbarSeparator", transparent);
    set("notebook.focusedCellBackground", bg);
    set("notebookStatusRunningIcon.foreground", primary);

    if hex_to_hsl_deg(bg).l >= 0.5 {
        for k in [
            "panel.border",
            "sideBar.border",
            "editorGroup.border",
            "editorGroupHeader.tabsBorder",
            "tab.border",
            "activityBar.border",
            "statusBar.border",
            "titleBar.border",
        ] {
            m.insert(k.to_owned(), Value::String(outline_variant.to_owned()));
        }
        m.insert("input.border".into(), Value::String(outline.to_owned()));
        m.insert("dropdown.border".into(), Value::String(outline.to_owned()));
        m.insert("checkbox.border".into(), Value::String(outline.to_owned()));
        m.insert(
            "input.placeholderForeground".into(),
            Value::String(with_contrast(on_surface_variant, bg, 4.5, false)),
        );
        m.insert(
            "editor.selectionBackground".into(),
            Value::String(format!("{primary}40")),
        );
        m.insert(
            "editor.inactiveSelectionBackground".into(),
            Value::String(format!("{primary}22")),
        );
    }
    if contrast_hex(&term("term0"), &term_bg) < 3.0 {
        m.insert(
            "terminal.ansiBlack".into(),
            Value::String(outline.to_owned()),
        );
    }
    m
}

fn build_vscode_syntax_and_semantic(
    colors: &HashMap<String, String>,
    term_colors: &HashMap<String, String>,
) -> (Value, Value) {
    let primary = pick(colors, "primary", "#d4b796");
    let on_surface = pick(colors, "on_surface", "#e3dfd9");
    let on_surface_variant = pick(colors, "on_surface_variant", "#c4bfb8");
    let error_col = saturate_color(pick(colors, "error", "#ffb4ab"), 1.4, 0.50);
    let editor_bg = pick(colors, "background", pick(colors, "surface", "#080809"));
    let dark = hex_to_hsl_deg(editor_bg).l < 0.5;

    let col_keyword = syntax_color(term_colors, primary, editor_bg, 5);
    let col_string = syntax_color(term_colors, primary, editor_bg, 2);
    let col_function = syntax_color(term_colors, primary, editor_bg, 4);
    let col_type = syntax_color(term_colors, primary, editor_bg, 6);
    let col_constant = syntax_color(term_colors, primary, editor_bg, 3);
    let col_tag = syntax_color(term_colors, primary, editor_bg, 1);
    let col_property = with_contrast(
        &blend(&col_function, &col_type, 0.5),
        editor_bg,
        4.5,
        dark,
    );
    let comment_aa = muted_ink(on_surface_variant, editor_bg, 0xaa, dark);
    let comment_cc = muted_ink(on_surface_variant, editor_bg, 0xcc, dark);

    let tokens = json!([
        {"scope": ["comment", "punctuation.definition.comment"], "settings": {"foreground": comment_aa, "fontStyle": "italic"}},
        {"scope": ["comment.block.documentation", "comment.block.javadoc"], "settings": {"foreground": comment_cc, "fontStyle": "italic"}},
        {"scope": ["keyword", "storage.type", "storage.modifier"], "settings": {"foreground": col_keyword}},
        {"scope": ["keyword.control", "keyword.control.flow"], "settings": {"foreground": col_keyword}},
        {"scope": ["keyword.operator", "keyword.operator.assignment"], "settings": {"foreground": col_keyword}},
        {"scope": ["keyword.other.unit"], "settings": {"foreground": col_constant}},
        {"scope": ["constant", "constant.language", "constant.character"], "settings": {"foreground": col_constant}},
        {"scope": ["constant.numeric", "constant.numeric.integer", "constant.numeric.float"], "settings": {"foreground": col_constant}},
        {"scope": ["constant.other.color", "constant.other.symbol"], "settings": {"foreground": col_constant}},
        {"scope": ["string", "string.quoted"], "settings": {"foreground": col_string}},
        {"scope": ["string.regexp"], "settings": {"foreground": col_tag}},
        {"scope": ["string.template", "string.interpolated"], "settings": {"foreground": col_string}},
        {"scope": ["string.other.link"], "settings": {"foreground": col_function}},
        {"scope": ["punctuation.definition.string"], "settings": {"foreground": col_string}},
        {"scope": ["constant.character.escape", "string.escape"], "settings": {"foreground": col_tag}},
        {"scope": ["entity.name.function", "support.function"], "settings": {"foreground": col_function}},
        {"scope": ["meta.function-call", "entity.name.function.call"], "settings": {"foreground": col_function}},
        {"scope": ["support.function.builtin"], "settings": {"foreground": col_function}},
        {"scope": ["entity.name.function.decorator", "meta.decorator"], "settings": {"foreground": col_tag, "fontStyle": "italic"}},
        {"scope": ["entity.name.type", "entity.name.class", "support.type", "support.class"], "settings": {"foreground": col_type}},
        {"scope": ["entity.other.inherited-class"], "settings": {"foreground": col_type, "fontStyle": "italic"}},
        {"scope": ["entity.name.type.interface"], "settings": {"foreground": col_type}},
        {"scope": ["entity.name.type.enum"], "settings": {"foreground": col_type}},
        {"scope": ["support.type.builtin", "support.type.primitive"], "settings": {"foreground": col_type}},
        {"scope": ["variable", "variable.other"], "settings": {"foreground": on_surface}},
        {"scope": ["variable.language"], "settings": {"foreground": col_tag, "fontStyle": "italic"}},
        {"scope": ["variable.parameter", "variable.parameter.function"], "settings": {"foreground": on_surface}},
        {"scope": ["variable.other.property", "support.variable.property", "variable.other.object.property"], "settings": {"foreground": col_property}},
        {"scope": ["entity.other.attribute-name"], "settings": {"foreground": col_property}},
        {"scope": ["meta.object-literal.key"], "settings": {"foreground": col_property}},
        {"scope": ["entity.name.tag"], "settings": {"foreground": col_tag}},
        {"scope": ["punctuation.definition.tag"], "settings": {"foreground": col_tag}},
        {"scope": ["entity.name.tag.css"], "settings": {"foreground": col_type}},
        {"scope": ["support.type.property-name.css"], "settings": {"foreground": col_property}},
        {"scope": ["support.constant.property-value.css"], "settings": {"foreground": col_constant}},
        {"scope": ["punctuation"], "settings": {"foreground": on_surface}},
        {"scope": ["punctuation.separator", "punctuation.terminator"], "settings": {"foreground": on_surface_variant}},
        {"scope": ["punctuation.section.embedded"], "settings": {"foreground": col_tag}},
        {"scope": ["markup.heading"], "settings": {"foreground": col_function, "fontStyle": "bold"}},
        {"scope": ["markup.bold"], "settings": {"foreground": on_surface, "fontStyle": "bold"}},
        {"scope": ["markup.italic"], "settings": {"foreground": on_surface, "fontStyle": "italic"}},
        {"scope": ["markup.underline.link"], "settings": {"foreground": col_function, "fontStyle": "underline"}},
        {"scope": ["markup.inline.raw", "markup.fenced_code"], "settings": {"foreground": col_string}},
        {"scope": ["markup.list"], "settings": {"foreground": col_keyword}},
        {"scope": ["markup.deleted"], "settings": {"foreground": error_col}},
        {"scope": ["markup.inserted"], "settings": {"foreground": col_string}},
        {"scope": ["markup.changed"], "settings": {"foreground": col_constant}},
        {"scope": ["invalid"], "settings": {"foreground": error_col}},
        {"scope": ["invalid.deprecated"], "settings": {"foreground": error_col, "fontStyle": "italic strikethrough"}}
    ]);

    let semantic = json!({
        "class": col_type,
        "enum": col_type,
        "enumMember": col_constant,
        "function": col_function,
        "method": col_function,
        "interface": col_type,
        "namespace": col_type,
        "parameter": on_surface,
        "property": col_property,
        "struct": col_type,
        "type": col_type,
        "typeParameter": col_constant,
        "variable": on_surface,
        "variable.constant": col_constant,
        "variable.defaultLibrary": col_tag,
        "comment": comment_aa,
        "keyword": col_keyword,
        "keyword.control": col_keyword,
        "number": col_constant,
        "string": col_string,
        "regexp": col_tag,
        "operator": col_keyword,
        "decorator": col_tag
    });

    (tokens, semantic)
}

fn load_vscode_settings(path: &Path) -> Result<Map<String, Value>> {
    match fs::read(path) {
        Ok(data) => {
            let stripped = strip_jsonc_comments(&data);
            let Value::Object(map) = serde_json::from_slice(&stripped)? else {
                return Err(anyhow!("settings.json is not an object"));
            };
            Ok(map)
        }
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(Map::new()),
        Err(e) => Err(e.into()),
    }
}

fn write_vscode_settings(path: &Path, settings: &Map<String, Value>) -> Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let mut data = serde_json::to_vec_pretty(settings)?;
    data.push(b'\n');
    fs::write(path, data)?;
    Ok(())
}

pub fn run_vscode_theme(raw_args: &[String]) -> Result<()> {
    let home = user_home();
    let mut colors_path = home.join(".local/state/quickshell/user/generated/palette.json");
    let mut terminal_path = home.join(".local/state/quickshell/user/generated/terminal.json");
    let mut scss_path = home.join(".local/state/quickshell/user/generated/material_colors.scss");
    let mut strip_mode = false;
    let mut forks: Vec<String> = Vec::new();

    let mut i = 0;
    while i < raw_args.len() {
        match raw_args[i].as_str() {
            "--colors" if i + 1 < raw_args.len() => {
                colors_path = PathBuf::from(&raw_args[i + 1]);
                i += 2;
            }
            "--terminal-json" if i + 1 < raw_args.len() => {
                terminal_path = PathBuf::from(&raw_args[i + 1]);
                i += 2;
            }
            "--scss" if i + 1 < raw_args.len() => {
                scss_path = PathBuf::from(&raw_args[i + 1]);
                i += 2;
            }
            "--strip" => {
                strip_mode = true;
                i += 1;
            }
            "--forks" if i + 1 < raw_args.len() => {
                forks.push(raw_args[i + 1].clone());
                i += 2;
            }
            _ => i += 1,
        }
    }

    if strip_mode {
        let selected: Vec<(&str, &str)> = if forks.is_empty() {
            VSCODE_FORKS
                .iter()
                .filter(|&&(key, name, _)| {
                    vscode_settings_path(name).is_file()
                        || vscode_ext_base(key).join(VSCODE_EXTENSION_ID).is_dir()
                })
                .map(|&(k, n, _)| (k, n))
                .collect()
        } else {
            forks
                .iter()
                .filter_map(|fk| {
                    VSCODE_FORKS
                        .iter()
                        .find(|&&(k, _, _)| k == fk.as_str())
                        .map(|&(k, n, _)| (k, n))
                })
                .collect()
        };

        let mut success = 0;
        for (fork_key, fork_name) in &selected {
            let ext_dir = vscode_ext_base(fork_key).join(VSCODE_EXTENSION_ID);
            if ext_dir.is_dir() {
                let _ = fs::remove_dir_all(&ext_dir);
            }
            unregister_vscode_extension(fork_key);
            let legacy_dir = vscode_ext_base(fork_key).join("alis.alis-theme-1.0.0");
            if legacy_dir.is_dir() {
                let _ = fs::remove_dir_all(&legacy_dir);
            }
            let settings_path = vscode_settings_path(fork_name);
            let mut ok = true;
            if settings_path.is_file() {
                if let Ok(mut settings) = load_vscode_settings(&settings_path) {
                    let mut changed = false;
                    if let Some(curr) = settings.get("workbench.colorTheme").and_then(Value::as_str)
                        && (curr == VSCODE_THEME_NAME || curr == VSCODE_THEME_NAME_LIGHT)
                    {
                        if let Some(prev) = settings
                            .get(VSCODE_PREV_KEY)
                            .and_then(Value::as_str)
                            .filter(|s| !s.is_empty())
                            .map(str::to_owned)
                        {
                            settings.insert("workbench.colorTheme".into(), Value::String(prev));
                        } else {
                            settings.remove("workbench.colorTheme");
                        }
                        changed = true;
                    }
                    if settings.remove(VSCODE_PREV_KEY).is_some() {
                        changed = true;
                    }
                    for key in [
                        "workbench.colorCustomizations",
                        "editor.tokenColorCustomizations",
                        "editor.semanticTokenColorCustomizations",
                    ] {
                        if settings.remove(key).is_some() {
                            changed = true;
                        }
                    }
                    if changed && write_vscode_settings(&settings_path, &settings).is_err() {
                        ok = false;
                    }
                } else {
                    ok = false;
                }
            }
            if ok {
                success += 1;
                println!("  ✓ {fork_name}");
            } else {
                eprintln!("  ✗ {fork_name}");
            }
        }
        println!("Stripped themes from {success}/{} forks", selected.len());
        return Ok(());
    }

    let colors = read_string_map_json(&colors_path)?;
    let mut term_colors = parse_scss(&scss_path).unwrap_or_default();
    if let Ok(explicit) = read_string_map_json(&terminal_path) {
        term_colors.extend(explicit);
    }

    let bg = pick(&colors, "background", pick(&colors, "surface", "#080809"));
    let is_dark = hex_to_hsl_deg(bg).l < 0.5;
    let (active_name, active_file, theme_type) = if is_dark {
        (VSCODE_THEME_NAME, VSCODE_FILE_DARK, "dark")
    } else {
        (VSCODE_THEME_NAME_LIGHT, VSCODE_FILE_LIGHT, "light")
    };

    let ui_colors = build_vscode_colors(&colors, &term_colors);
    let (token_colors, semantic_colors) = build_vscode_syntax_and_semantic(&colors, &term_colors);
    let theme_json = json!({
        "$schema": "vscode://schemas/color-theme",
        "name": active_name,
        "type": theme_type,
        "colors": ui_colors,
        "tokenColors": token_colors,
        "semanticHighlighting": true,
        "semanticTokenColors": semantic_colors
    });
    let mut theme_bytes = serde_json::to_vec_pretty(&theme_json)?;
    theme_bytes.push(b'\n');

    let selected: Vec<(&str, &str)> = if forks.is_empty() {
        VSCODE_FORKS
            .iter()
            .filter(|&&(_, name, _)| {
                vscode_settings_path(name)
                    .parent()
                    .is_some_and(Path::is_dir)
            })
            .map(|&(k, n, _)| (k, n))
            .collect()
    } else {
        forks
            .iter()
            .filter_map(|fk| {
                VSCODE_FORKS
                    .iter()
                    .find(|&&(k, _, _)| k == fk.as_str())
                    .map(|&(k, n, _)| (k, n))
            })
            .collect()
    };

    let mut success = 0;
    for (fork_key, fork_name) in &selected {
        let settings_path = vscode_settings_path(fork_name);
        if !settings_path.parent().is_some_and(Path::is_dir) {
            continue;
        }
        let legacy_dir = vscode_ext_base(fork_key).join("alis.alis-theme-1.0.0");
        if legacy_dir.is_dir() {
            let _ = fs::remove_dir_all(&legacy_dir);
        }
        let ext_dir = vscode_ext_base(fork_key).join(VSCODE_EXTENSION_ID);
        if fs::create_dir_all(ext_dir.join("themes")).is_err() {
            continue;
        }
        let pkg_path = ext_dir.join("package.json");
        let has_light = fs::read_to_string(&pkg_path)
            .map(|s| s.contains(VSCODE_FILE_LIGHT))
            .unwrap_or(false);
        if !has_light && write_vscode_manifest(&ext_dir).is_err() {
            continue;
        }
        let _ = ensure_vscode_registered(fork_key, &ext_dir);

        let theme_path = ext_dir.join("themes").join(active_file);
        let tmp_path = theme_path.with_extension("json.tmp");
        if fs::write(&tmp_path, &theme_bytes).is_err()
            || fs::rename(&tmp_path, &theme_path).is_err()
        {
            continue;
        }

        if let Ok(mut settings) = load_vscode_settings(&settings_path) {
            let current_theme = settings
                .get("workbench.colorTheme")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_owned();
            let mut changed = false;
            if !current_theme.is_empty()
                && current_theme != VSCODE_THEME_NAME
                && current_theme != VSCODE_THEME_NAME_LIGHT
            {
                settings.insert(VSCODE_PREV_KEY.into(), Value::String(current_theme.clone()));
                changed = true;
            }
            for key in [
                "workbench.colorCustomizations",
                "editor.tokenColorCustomizations",
                "editor.semanticTokenColorCustomizations",
            ] {
                if settings.remove(key).is_some() {
                    changed = true;
                }
            }
            if current_theme != active_name {
                settings.insert(
                    "workbench.colorTheme".into(),
                    Value::String(active_name.to_owned()),
                );
                changed = true;
            }
            if changed && write_vscode_settings(&settings_path, &settings).is_err() {
                continue;
            }
            success += 1;
            println!("  ✓ {fork_name}");
        }
    }
    println!("Generated themes for {success}/{} forks", selected.len());
    Ok(())
}

// ── Zed Theme Generator ────────────────────────────────────────────────

fn is_hex_color(v: &str) -> bool {
    let s = v.trim();
    if let Some(rest) = s.strip_prefix('#') {
        (rest.len() == 6 || rest.len() == 8) && rest.bytes().all(|b| b.is_ascii_hexdigit())
    } else {
        false
    }
}

fn normalize_hex6(v: &str) -> String {
    let s = v.trim().to_ascii_lowercase();
    let rest = s.strip_prefix('#').unwrap_or(&s);
    if rest.len() < 6 {
        return "#000000".to_owned();
    }
    format!("#{}", &rest[0..6])
}

fn hex_with_alpha(hex_color: &str, alpha: &str) -> String {
    format!("{}{}", normalize_hex6(hex_color), alpha.to_ascii_lowercase())
}

fn zed_adjust_lightness(hex_color: &str, factor: f64) -> String {
    let mut c = hex_to_hsl_deg(hex_color);
    c.l = (c.l * factor).clamp(0.0, 1.0);
    hsl_deg_to_hex(c)
}

fn zed_saturate(hex_color: &str, factor: f64, min_sat: f64, additive_floor: f64) -> String {
    let mut c = hex_to_hsl_deg(hex_color);
    if c.s < 0.001 {
        c.h = 0.0;
    }
    let mut boosted = (c.s * factor + additive_floor * (1.0 - c.s)).min(1.0);
    if boosted < min_sat {
        boosted = (boosted + min_sat).min(1.0);
    }
    c.s = boosted;
    hsl_deg_to_hex(c)
}

fn zed_blend(base_hex: &str, mix_hex: &str, mix_ratio: f64) -> String {
    let b = normalize_hex6(base_hex);
    let m = normalize_hex6(mix_hex);
    let ratio = mix_ratio.clamp(0.0, 1.0);
    let (br, bg, bb) = hex_to_rgb(&b);
    let (mr, mg, mb) = hex_to_rgb(&m);
    let r = (br as f64 * (1.0 - ratio) + mr as f64 * ratio).round() as i32;
    let g = (bg as f64 * (1.0 - ratio) + mg as f64 * ratio).round() as i32;
    let bl = (bb as f64 * (1.0 - ratio) + mb as f64 * ratio).round() as i32;
    rgb_to_hex(r, g, bl)
}

fn zed_luminance(hex_color: &str) -> f64 {
    let (r, g, b) = hex_to_rgb(&normalize_hex6(hex_color));
    r as f64 * 0.299 + g as f64 * 0.587 + b as f64 * 0.114
}

fn zed_term_color(term_colors: &HashMap<String, String>, idx: usize) -> String {
    let key = format!("term{idx}");
    if let Some(v) = term_colors.get(&key)
        && is_hex_color(v)
    {
        return normalize_hex6(v);
    }
    const DEFAULTS: [&str; 16] = [
        "#1d1f21", "#cc6666", "#b5bd68", "#f0c674", "#81a2be", "#b294bb", "#8abeb7", "#c5c8c6",
        "#666666", "#d54e53", "#b9ca4a", "#e7c547", "#7aa6da", "#c397d8", "#70c0ba", "#ffffff",
    ];
    DEFAULTS.get(idx).copied().unwrap_or("#ffffff").to_owned()
}

fn zed_pick(m: &HashMap<String, String>, key: &str, fallback: &str) -> String {
    if let Some(v) = m.get(key)
        && !v.is_empty()
    {
        return normalize_hex6(v);
    }
    normalize_hex6(fallback)
}

fn build_zed_syntax_map(primary: &str, appearance: &str) -> Value {
    let defaults: &[(&str, &str, Option<&str>, Option<i64>)] = if appearance == "light" {
        &[
            ("attribute", "#5c78e2", None, None),
            ("boolean", "#ad6e25", None, None),
            ("comment", "#a2a3a7", None, None),
            ("comment.doc", "#7c7e86", None, None),
            ("constant", "#c18401", None, None),
            ("constructor", "#5c78e2", None, None),
            ("embedded", "#242529", None, None),
            ("emphasis", "#5c78e2", None, None),
            ("emphasis.strong", "#ad6e25", None, Some(700)),
            ("enum", "#3882b7", None, None),
            ("function", "#5b79e3", None, None),
            ("hint", "#7274a7", None, None),
            ("keyword", "#a449ab", None, None),
            ("label", "#5c78e2", None, None),
            ("link_text", "#5b79e3", Some("italic"), None),
            ("link_uri", "#3882b7", None, None),
            ("namespace", "#242529", None, None),
            ("number", "#ad6e25", None, None),
            ("operator", "#3882b7", None, None),
            ("predictive", "#9b9ec6", Some("italic"), None),
            ("preproc", "#242529", None, None),
            ("primary", "#242529", None, None),
            ("property", "#d3604f", None, None),
            ("punctuation", "#242529", None, None),
            ("punctuation.bracket", "#4d4f52", None, None),
            ("punctuation.delimiter", "#4d4f52", None, None),
            ("punctuation.list_marker", "#d3604f", None, None),
            ("punctuation.markup", "#d3604f", None, None),
            ("punctuation.special", "#b92b46", None, None),
            ("selector", "#669f59", None, None),
            ("selector.pseudo", "#5c78e2", None, None),
            ("string", "#649f57", None, None),
            ("string.escape", "#7c7e86", None, None),
            ("string.regex", "#ad6e26", None, None),
            ("string.special", "#ad6e26", None, None),
            ("string.special.symbol", "#ad6e26", None, None),
            ("tag", "#5c78e2", None, None),
            ("text.literal", "#649f57", None, None),
            ("title", "#d3604f", None, Some(400)),
            ("type", "#3882b7", None, None),
            ("variable", "#242529", None, None),
            ("variable.special", "#ad6e25", None, None),
            ("variant", "#5b79e3", None, None),
        ]
    } else {
        &[
            ("attribute", "#74ade8", None, None),
            ("boolean", "#bf956a", None, None),
            ("comment", "#5d636f", None, None),
            ("comment.doc", "#878e98", None, None),
            ("constant", "#dfc184", None, None),
            ("constructor", "#73ade9", None, None),
            ("embedded", "#dce0e5", None, None),
            ("emphasis", "#74ade8", None, None),
            ("emphasis.strong", "#bf956a", None, Some(700)),
            ("enum", "#6eb4bf", None, None),
            ("function", "#73ade9", None, None),
            ("hint", "#788ca6", None, None),
            ("keyword", "#b477cf", None, None),
            ("label", "#74ade8", None, None),
            ("link_text", "#73ade9", Some("normal"), None),
            ("link_uri", "#6eb4bf", None, None),
            ("namespace", "#dce0e5", None, None),
            ("number", "#bf956a", None, None),
            ("operator", "#6eb4bf", None, None),
            ("predictive", "#5a6a87", Some("italic"), None),
            ("preproc", "#dce0e5", None, None),
            ("primary", "#acb2be", None, None),
            ("property", "#d07277", None, None),
            ("punctuation", "#acb2be", None, None),
            ("punctuation.bracket", "#b2b9c6", None, None),
            ("punctuation.delimiter", "#b2b9c6", None, None),
            ("punctuation.list_marker", "#d07277", None, None),
            ("punctuation.markup", "#d07277", None, None),
            ("punctuation.special", "#b1574b", None, None),
            ("selector", "#dfc184", None, None),
            ("selector.pseudo", "#74ade8", None, None),
            ("string", "#a1c181", None, None),
            ("string.escape", "#878e98", None, None),
            ("string.regex", "#bf956a", None, None),
            ("string.special", "#bf956a", None, None),
            ("string.special.symbol", "#bf956a", None, None),
            ("tag", "#74ade8", None, None),
            ("text.literal", "#a1c181", None, None),
            ("title", "#d07277", None, Some(400)),
            ("type", "#6eb4bf", None, None),
            ("variable", "#acb2be", None, None),
            ("variable.special", "#bf956a", None, None),
            ("variant", "#73ade9", None, None),
        ]
    };

    let mut syntax = Map::new();
    for &(token, color, font_style, font_weight) in defaults {
        let blended = zed_blend(color, primary, 0.50);
        syntax.insert(
            token.to_owned(),
            json!({
                "color": hex_with_alpha(&blended, "ff"),
                "font_style": font_style,
                "font_weight": font_weight
            }),
        );
    }
    Value::Object(syntax)
}

fn make_zed_borderless(style: &Map<String, Value>) -> Map<String, Value> {
    let mut out = style.clone();
    for key in [
        "border",
        "border.variant",
        "border.focused",
        "border.selected",
        "border.transparent",
        "border.disabled",
        "scrollbar.thumb.border",
        "scrollbar.track.border",
    ] {
        if out.contains_key(key) {
            out.insert(key.into(), Value::String("#00000000".into()));
        }
    }
    out.insert("panel.focused_border".into(), Value::Null);
    out.insert("pane.focused_border".into(), Value::Null);
    out
}

pub fn run_zed_theme(raw_args: &[String]) -> Result<()> {
    let home = user_home();
    let mut scss_path = home.join(".local/state/quickshell/user/generated/material_colors.scss");
    let mut colors_path = home.join(".local/state/quickshell/user/generated/palette.json");
    let mut terminal_path = home.join(".local/state/quickshell/user/generated/terminal.json");
    let mut output_path = home.join(".config/zed/themes/ii-theme.json");
    let mut positional: Vec<String> = Vec::new();

    let mut i = 0;
    while i < raw_args.len() {
        match raw_args[i].as_str() {
            "--scss" if i + 1 < raw_args.len() => {
                scss_path = PathBuf::from(&raw_args[i + 1]);
                i += 2;
            }
            "--colors" if i + 1 < raw_args.len() => {
                colors_path = PathBuf::from(&raw_args[i + 1]);
                i += 2;
            }
            "--terminal-json" if i + 1 < raw_args.len() => {
                terminal_path = PathBuf::from(&raw_args[i + 1]);
                i += 2;
            }
            "--output" if i + 1 < raw_args.len() => {
                output_path = PathBuf::from(&raw_args[i + 1]);
                i += 2;
            }
            "--template" if i + 1 < raw_args.len() => {
                i += 2;
            }
            arg if !arg.starts_with("--") => {
                positional.push(arg.to_owned());
                i += 1;
            }
            _ => i += 1,
        }
    }
    if let Some(p0) = positional.first() {
        scss_path = PathBuf::from(p0);
    }
    if let Some(p1) = positional.get(1) {
        colors_path = PathBuf::from(p1);
    }
    if let Some(p2) = positional.get(2) {
        terminal_path = PathBuf::from(p2);
    }

    let raw_colors = read_string_map_json(&colors_path).unwrap_or_default();
    let mut my_colors: HashMap<String, String> = raw_colors
        .iter()
        .filter(|(_, v)| is_hex_color(v))
        .map(|(k, v)| (k.clone(), v.to_ascii_lowercase()))
        .collect();
    if my_colors.is_empty() {
        for (k, v) in [
            ("primary", "#7aa2f7"),
            ("secondary", "#bb9af7"),
            ("tertiary", "#9ece6a"),
            ("error", "#f7768e"),
            ("surface", "#1a1b26"),
            ("surface_container_low", "#24283b"),
            ("surface_container", "#414868"),
            ("surface_container_high", "#565f89"),
            ("outline", "#565f89"),
            ("on_surface", "#c0caf5"),
            ("on_surface_variant", "#9aa5ce"),
            ("on_primary", "#1a1b26"),
        ] {
            my_colors.insert(k.to_owned(), v.to_owned());
        }
    }

    let mut term_colors = HashMap::new();
    for map in [
        raw_colors,
        parse_scss(&scss_path).unwrap_or_default(),
        read_string_map_json(&terminal_path).unwrap_or_default(),
    ] {
        for (k, v) in map {
            if k.starts_with("term") && is_hex_color(&v) {
                term_colors.insert(k, v.to_ascii_lowercase());
            }
        }
    }

    let is_dark = zed_luminance(&zed_pick(&my_colors, "surface", "#000000")) < 128.0;
    let (
        dk_surface,
        dk_surface_low,
        dk_surface_std,
        dk_surface_high,
        _dk_surface_highest,
        dk_on_surface,
        dk_on_surface_variant,
        dk_outline,
        dk_outline_variant,
        lt_surface,
        lt_surface_low,
        lt_surface_std,
        lt_surface_high,
        lt_surface_highest,
        lt_on_surface,
        lt_on_surface_variant,
        _lt_outline,
        lt_outline_variant,
    ) = if is_dark {
        let lts = zed_pick(&my_colors, "inverse_surface", "#f1dedc");
        (
            zed_pick(&my_colors, "surface", "#1a1b26"),
            zed_pick(&my_colors, "surface_container_low", "#24283b"),
            zed_pick(&my_colors, "surface_container", "#414868"),
            zed_pick(&my_colors, "surface_container_high", "#565f89"),
            zed_pick(&my_colors, "surface_container_highest", "#3d3231"),
            zed_pick(&my_colors, "on_surface", "#c0caf5"),
            zed_pick(&my_colors, "on_surface_variant", "#9aa5ce"),
            zed_pick(&my_colors, "outline", "#565f89"),
            zed_pick(&my_colors, "outline_variant", "#534341"),
            lts.clone(),
            zed_adjust_lightness(&lts, 0.97),
            zed_adjust_lightness(&lts, 0.94),
            zed_adjust_lightness(&lts, 0.91),
            zed_adjust_lightness(&lts, 0.88),
            zed_pick(&my_colors, "inverse_on_surface", "#392e2c"),
            zed_pick(&my_colors, "outline_variant", "#534341"),
            zed_pick(&my_colors, "outline", "#565f89"),
            zed_pick(&my_colors, "outline_variant", "#534341"),
        )
    } else {
        let dks = zed_pick(&my_colors, "inverse_surface", "#382e30");
        (
            dks.clone(),
            zed_adjust_lightness(&dks, 1.15),
            zed_adjust_lightness(&dks, 1.35),
            zed_adjust_lightness(&dks, 1.55),
            zed_adjust_lightness(&dks, 1.75),
            zed_pick(&my_colors, "inverse_on_surface", "#feedef"),
            zed_pick(&my_colors, "outline_variant", "#d6c2c4"),
            zed_pick(&my_colors, "outline", "#847376"),
            zed_pick(&my_colors, "outline_variant", "#d6c2c4"),
            zed_pick(&my_colors, "surface", "#fff8f7"),
            zed_pick(&my_colors, "surface_container_low", "#fff0f2"),
            zed_pick(&my_colors, "surface_container", "#fbeaec"),
            zed_pick(&my_colors, "surface_container_high", "#f5e4e6"),
            zed_pick(&my_colors, "surface_container_highest", "#efdee0"),
            zed_pick(&my_colors, "on_surface", "#22191b"),
            zed_pick(&my_colors, "on_surface_variant", "#514346"),
            zed_pick(&my_colors, "outline", "#847376"),
            zed_pick(&my_colors, "outline_variant", "#d6c2c4"),
        )
    };

    let primary = zed_pick(&my_colors, "primary", "#7aa2f7");
    let secondary = zed_pick(&my_colors, "secondary", "#bb9af7");
    let tertiary = zed_pick(&my_colors, "tertiary", "#9ece6a");
    let error_col = zed_pick(&my_colors, "error", "#f7768e");

    let mut dark_style = Map::new();
    let mut ds = |k: &str, v: &str| {
        dark_style.insert(k.to_owned(), Value::String(v.to_owned()));
    };
    ds("border", &hex_with_alpha(&dk_on_surface, "20"));
    ds("border.variant", &hex_with_alpha(&dk_surface, "20"));
    ds("border.focused", &hex_with_alpha(&dk_surface, "40"));
    ds("border.selected", &hex_with_alpha(&dk_surface, "ff"));
    ds("border.transparent", &hex_with_alpha(&dk_surface, "20"));
    ds("border.disabled", &hex_with_alpha(&dk_outline_variant, "60"));
    ds("elevated_surface.background", &hex_with_alpha(&dk_surface_low, "ff"));
    ds("surface.background", &hex_with_alpha(&dk_surface_low, "ff"));
    ds("background", &hex_with_alpha(&dk_surface, "ff"));
    ds("element.background", &hex_with_alpha(&dk_surface_low, "ff"));
    ds("element.hover", &hex_with_alpha(&dk_surface_std, "ff"));
    ds("element.active", &hex_with_alpha(&dk_surface_high, "ff"));
    ds("element.selected", &hex_with_alpha(&dk_surface_high, "ff"));
    ds("element.disabled", &hex_with_alpha(&dk_surface_low, "ff"));
    ds("drop_target.background", &hex_with_alpha(&primary, "80"));
    ds("ghost_element.background", "#00000000");
    ds("ghost_element.hover", &hex_with_alpha(&dk_surface_std, "ff"));
    ds("ghost_element.active", &hex_with_alpha(&dk_surface_high, "ff"));
    ds("ghost_element.selected", &hex_with_alpha(&dk_surface_high, "ff"));
    ds("ghost_element.disabled", &hex_with_alpha(&dk_surface_low, "ff"));
    ds("text", &hex_with_alpha(&dk_on_surface, "ff"));
    ds("text.muted", &hex_with_alpha(&dk_on_surface_variant, "ff"));
    ds("text.placeholder", &hex_with_alpha(&zed_adjust_lightness(&dk_on_surface_variant, 0.7), "ff"));
    ds("text.disabled", &hex_with_alpha(&zed_adjust_lightness(&dk_on_surface_variant, 0.6), "ff"));
    ds("text.accent", &hex_with_alpha(&primary, "ff"));
    ds("icon", &hex_with_alpha(&dk_on_surface, "ff"));
    ds("icon.muted", &hex_with_alpha(&dk_on_surface_variant, "ff"));
    ds("icon.disabled", &hex_with_alpha(&zed_adjust_lightness(&dk_on_surface_variant, 0.6), "ff"));
    ds("icon.placeholder", &hex_with_alpha(&dk_on_surface_variant, "ff"));
    ds("icon.accent", &hex_with_alpha(&primary, "ff"));
    ds("status_bar.background", &hex_with_alpha(&dk_surface, "ff"));
    ds("title_bar.background", &hex_with_alpha(&dk_surface, "ff"));
    ds("title_bar.inactive_background", &hex_with_alpha(&dk_surface_low, "ff"));
    ds("toolbar.background", &hex_with_alpha(&dk_surface_low, "ff"));
    ds("tab_bar.background", &hex_with_alpha(&dk_surface_low, "ff"));
    ds("tab.inactive_background", &hex_with_alpha(&dk_surface_low, "ff"));
    ds("tab.active_background", &hex_with_alpha(&zed_adjust_lightness(&dk_surface, 0.9), "ff"));
    ds("search.match_background", &hex_with_alpha(&primary, "66"));
    ds("search.active_match_background", &hex_with_alpha(&tertiary, "66"));
    ds("panel.background", &hex_with_alpha(&dk_surface_low, "ff"));
    ds("scrollbar.thumb.background", &hex_with_alpha(&dk_on_surface_variant, "4c"));
    ds("scrollbar.thumb.hover_background", &hex_with_alpha(&dk_surface_high, "ff"));
    ds("scrollbar.thumb.border", &hex_with_alpha(&dk_surface_std, "ff"));
    ds("scrollbar.track.background", "#00000000");
    ds("scrollbar.track.border", &hex_with_alpha(&dk_surface_std, "ff"));
    ds("editor.foreground", &hex_with_alpha(&dk_on_surface, "ff"));
    ds("editor.background", &hex_with_alpha(&dk_surface, "ff"));
    ds("editor.gutter.background", &hex_with_alpha(&dk_surface, "ff"));
    ds("editor.subheader.background", &hex_with_alpha(&dk_surface_low, "ff"));
    ds("editor.active_line.background", &hex_with_alpha(&dk_surface_low, "bf"));
    ds("editor.highlighted_line.background", &hex_with_alpha(&dk_surface_std, "ff"));
    ds("editor.line_number", &hex_with_alpha(&dk_on_surface_variant, "ff"));
    ds("editor.active_line_number", &hex_with_alpha(&dk_on_surface, "ff"));
    ds("editor.hover_line_number", &hex_with_alpha(&zed_adjust_lightness(&dk_on_surface, 1.1), "ff"));
    ds("editor.invisible", &hex_with_alpha(&dk_on_surface_variant, "ff"));
    ds("editor.wrap_guide", &hex_with_alpha(&dk_on_surface_variant, "0d"));
    ds("editor.active_wrap_guide", &hex_with_alpha(&dk_on_surface_variant, "1a"));
    ds("editor.document_highlight.read_background", &hex_with_alpha(&primary, "1a"));
    ds("editor.document_highlight.write_background", &hex_with_alpha(&dk_surface_std, "66"));
    ds("terminal.background", &hex_with_alpha(&dk_surface, "ff"));
    ds("terminal.foreground", &hex_with_alpha(&dk_on_surface, "ff"));
    ds("terminal.bright_foreground", &hex_with_alpha(&dk_on_surface, "ff"));
    ds("terminal.dim_foreground", &hex_with_alpha(&zed_adjust_lightness(&dk_on_surface, 0.6), "ff"));
    ds("link_text.hover", &hex_with_alpha(&primary, "ff"));
    ds("version_control.added", &hex_with_alpha(&tertiary, "ff"));
    ds("version_control.modified", &hex_with_alpha(&zed_adjust_lightness(&primary, 0.8), "ff"));
    ds("version_control.word_added", &hex_with_alpha(&tertiary, "59"));
    ds("version_control.word_deleted", &hex_with_alpha(&error_col, "cc"));
    ds("version_control.deleted", &hex_with_alpha(&error_col, "ff"));
    ds("version_control.conflict_marker.ours", &hex_with_alpha(&tertiary, "1a"));
    ds("version_control.conflict_marker.theirs", &hex_with_alpha(&primary, "1a"));
    ds("conflict", &hex_with_alpha(&zed_adjust_lightness(&tertiary, 0.8), "ff"));
    ds("conflict.background", &hex_with_alpha(&zed_adjust_lightness(&tertiary, 0.8), "1a"));
    ds("conflict.border", &hex_with_alpha(&zed_adjust_lightness(&tertiary, 0.6), "ff"));
    ds("created", &hex_with_alpha(&tertiary, "ff"));
    ds("created.background", &hex_with_alpha(&tertiary, "1a"));
    ds("created.border", &hex_with_alpha(&zed_adjust_lightness(&tertiary, 0.6), "ff"));
    ds("deleted", &hex_with_alpha(&error_col, "ff"));
    ds("deleted.background", &hex_with_alpha(&error_col, "1a"));
    ds("deleted.border", &hex_with_alpha(&zed_adjust_lightness(&error_col, 0.6), "ff"));
    ds("error", &hex_with_alpha(&error_col, "ff"));
    ds("error.background", &hex_with_alpha(&error_col, "1a"));
    ds("error.border", &hex_with_alpha(&zed_adjust_lightness(&error_col, 0.6), "ff"));
    ds("hidden", &hex_with_alpha(&dk_on_surface_variant, "ff"));
    ds("hidden.background", &hex_with_alpha(&zed_adjust_lightness(&dk_on_surface_variant, 0.3), "1a"));
    ds("hidden.border", &hex_with_alpha(&dk_outline, "ff"));
    ds("hint", &hex_with_alpha(&zed_adjust_lightness(&primary, 0.7), "ff"));
    ds("hint.background", &hex_with_alpha(&zed_adjust_lightness(&primary, 0.7), "1a"));
    ds("hint.border", &hex_with_alpha(&zed_adjust_lightness(&primary, 0.6), "ff"));
    ds("ignored", &hex_with_alpha(&dk_on_surface_variant, "ff"));
    ds("ignored.background", &hex_with_alpha(&zed_adjust_lightness(&dk_on_surface_variant, 0.3), "1a"));
    ds("ignored.border", &hex_with_alpha(&dk_outline, "ff"));
    ds("info", &hex_with_alpha(&primary, "ff"));
    ds("info.background", &hex_with_alpha(&primary, "1a"));
    ds("info.border", &hex_with_alpha(&zed_adjust_lightness(&primary, 0.6), "ff"));
    ds("modified.background", &hex_with_alpha(&zed_adjust_lightness(&primary, 0.8), "1a"));
    ds("modified.border", &hex_with_alpha(&primary, "ff"));
    ds("predictive", &hex_with_alpha(&zed_adjust_lightness(&secondary, 0.8), "ff"));
    ds("predictive.background", &hex_with_alpha(&zed_adjust_lightness(&secondary, 0.8), "1a"));
    ds("predictive.border", &hex_with_alpha(&secondary, "ff"));
    ds("renamed", &hex_with_alpha(&primary, "ff"));
    ds("renamed.background", &hex_with_alpha(&primary, "1a"));
    ds("renamed.border", &hex_with_alpha(&zed_adjust_lightness(&primary, 0.6), "ff"));
    ds("success", &hex_with_alpha(&tertiary, "ff"));
    ds("success.background", &hex_with_alpha(&tertiary, "1a"));
    ds("success.border", &hex_with_alpha(&zed_adjust_lightness(&tertiary, 0.6), "ff"));
    ds("unreachable", &hex_with_alpha(&dk_on_surface_variant, "ff"));
    ds("unreachable.background", &hex_with_alpha(&zed_adjust_lightness(&dk_on_surface_variant, 0.3), "1a"));
    ds("unreachable.border", &hex_with_alpha(&dk_outline, "ff"));
    ds("warning", &hex_with_alpha(&zed_adjust_lightness(&tertiary, 0.9), "ff"));
    ds("warning.background", &hex_with_alpha(&zed_adjust_lightness(&tertiary, 0.9), "1a"));
    ds("warning.border", &hex_with_alpha(&zed_adjust_lightness(&tertiary, 0.9), "ff"));
    ds("terminal.ansi.black", &hex_with_alpha(&zed_term_color(&term_colors, 0), "ff"));
    ds("terminal.ansi.bright_black", &hex_with_alpha(&zed_term_color(&term_colors, 8), "ff"));
    ds("terminal.ansi.dim_black", &hex_with_alpha(&zed_adjust_lightness(&zed_term_color(&term_colors, 0), 0.6), "ff"));
    dark_style.insert("panel.focused_border".into(), Value::Null);
    dark_style.insert("pane.focused_border".into(), Value::Null);

    for (name, idx) in [
        ("red", 1), ("bright_red", 9), ("dim_red", 1),
        ("green", 2), ("bright_green", 10), ("dim_green", 2),
        ("yellow", 3), ("bright_yellow", 11), ("dim_yellow", 3),
        ("blue", 4), ("bright_blue", 12), ("dim_blue", 4),
        ("magenta", 5), ("bright_magenta", 13), ("dim_magenta", 5),
        ("cyan", 6), ("bright_cyan", 14), ("dim_cyan", 6),
        ("white", 7), ("bright_white", 15), ("dim_white", 7),
    ] {
        let base = zed_term_color(&term_colors, idx);
        let c = if name.contains("bright") {
            zed_adjust_lightness(&base, 1.2)
        } else if name.contains("dim") {
            zed_adjust_lightness(&base, 0.7)
        } else {
            base
        };
        dark_style.insert(
            format!("terminal.ansi.{name}"),
            Value::String(hex_with_alpha(&c, "ff")),
        );
    }
    let dark_players: Vec<Value> = [
        primary.clone(),
        error_col.clone(),
        zed_adjust_lightness(&tertiary, 0.8),
        secondary.clone(),
        zed_adjust_lightness(&secondary, 1.2),
        zed_adjust_lightness(&error_col, 0.8),
        zed_adjust_lightness(&tertiary, 0.9),
        zed_adjust_lightness(&primary, 0.8),
    ]
    .into_iter()
    .map(|c| {
        json!({
            "cursor": hex_with_alpha(&c, "ff"),
            "background": hex_with_alpha(&c, "ff"),
            "selection": hex_with_alpha(&c, "3d")
        })
    })
    .collect();
    dark_style.insert("players".into(), Value::Array(dark_players));
    dark_style.insert("syntax".into(), build_zed_syntax_map(&primary, "dark"));

    let sat = |c: &str, f: f64| zed_saturate(c, f, 0.38, 0.22);
    let mut light_style = Map::new();
    let mut ls = |k: &str, v: &str| {
        light_style.insert(k.to_owned(), Value::String(v.to_owned()));
    };
    ls("border", &hex_with_alpha(&lt_on_surface, "20"));
    ls("border.variant", &hex_with_alpha(&lt_surface, "20"));
    ls("border.focused", &hex_with_alpha(&lt_surface, "40"));
    ls("border.selected", &hex_with_alpha(&lt_surface, "ff"));
    ls("border.transparent", &hex_with_alpha(&lt_surface, "20"));
    ls("border.disabled", &hex_with_alpha(&lt_outline_variant, "60"));
    ls("elevated_surface.background", &hex_with_alpha(&lt_surface_low, "ff"));
    ls("surface.background", &hex_with_alpha(&lt_surface_low, "ff"));
    ls("background", &hex_with_alpha(&lt_surface, "ff"));
    ls("element.background", &hex_with_alpha(&lt_surface_std, "ff"));
    ls("element.hover", &hex_with_alpha(&lt_surface_high, "ff"));
    ls("element.active", &hex_with_alpha(&lt_surface_highest, "ff"));
    ls("element.selected", &hex_with_alpha(&lt_surface_highest, "ff"));
    ls("element.disabled", &hex_with_alpha(&lt_surface_low, "ff"));
    ls("drop_target.background", &hex_with_alpha(&primary, "30"));
    ls("ghost_element.background", "#00000000");
    ls("ghost_element.hover", &hex_with_alpha(&lt_surface_high, "ff"));
    ls("ghost_element.active", &hex_with_alpha(&lt_surface_highest, "ff"));
    ls("ghost_element.selected", &hex_with_alpha(&lt_surface_highest, "ff"));
    ls("ghost_element.disabled", &hex_with_alpha(&lt_surface_low, "ff"));
    ls("text", &hex_with_alpha(&lt_on_surface, "ff"));
    ls("text.muted", &hex_with_alpha(&lt_on_surface_variant, "ff"));
    ls("text.placeholder", &hex_with_alpha(&zed_adjust_lightness(&lt_on_surface_variant, 1.3), "ff"));
    ls("text.disabled", &hex_with_alpha(&zed_adjust_lightness(&lt_on_surface_variant, 1.5), "ff"));
    ls("text.accent", &hex_with_alpha(&primary, "ff"));
    ls("icon", &hex_with_alpha(&lt_on_surface, "ff"));
    ls("icon.muted", &hex_with_alpha(&lt_on_surface_variant, "ff"));
    ls("icon.disabled", &hex_with_alpha(&zed_adjust_lightness(&lt_on_surface_variant, 1.5), "ff"));
    ls("icon.placeholder", &hex_with_alpha(&lt_on_surface_variant, "ff"));
    ls("icon.accent", &hex_with_alpha(&primary, "ff"));
    ls("status_bar.background", &hex_with_alpha(&lt_surface, "ff"));
    ls("title_bar.background", &hex_with_alpha(&lt_surface, "ff"));
    ls("title_bar.inactive_background", &hex_with_alpha(&lt_surface_low, "ff"));
    ls("toolbar.background", &hex_with_alpha(&lt_surface_low, "ff"));
    ls("tab_bar.background", &hex_with_alpha(&lt_surface_low, "ff"));
    ls("tab.inactive_background", &hex_with_alpha(&lt_surface_low, "ff"));
    ls("tab.active_background", &hex_with_alpha(&lt_surface, "ff"));
    ls("search.match_background", &hex_with_alpha(&primary, "40"));
    ls("search.active_match_background", &hex_with_alpha(&tertiary, "40"));
    ls("panel.background", &hex_with_alpha(&lt_surface_low, "ff"));
    ls("scrollbar.thumb.background", &hex_with_alpha(&lt_on_surface_variant, "4c"));
    ls("scrollbar.thumb.hover_background", &hex_with_alpha(&lt_on_surface_variant, "80"));
    ls("scrollbar.thumb.border", &hex_with_alpha(&lt_on_surface_variant, "60"));
    ls("scrollbar.track.background", "#00000000");
    ls("scrollbar.track.border", &hex_with_alpha(&lt_outline_variant, "ff"));
    ls("editor.foreground", &hex_with_alpha(&lt_on_surface, "ff"));
    ls("editor.background", &hex_with_alpha(&lt_surface, "ff"));
    ls("editor.gutter.background", &hex_with_alpha(&lt_surface, "ff"));
    ls("editor.subheader.background", &hex_with_alpha(&lt_surface_low, "ff"));
    ls("editor.active_line.background", &hex_with_alpha(&lt_surface_std, "bf"));
    ls("editor.highlighted_line.background", &hex_with_alpha(&lt_surface_high, "ff"));
    ls("editor.line_number", &hex_with_alpha(&lt_on_surface_variant, "ff"));
    ls("editor.active_line_number", &hex_with_alpha(&lt_on_surface, "ff"));
    ls("editor.hover_line_number", &hex_with_alpha(&zed_adjust_lightness(&lt_on_surface, 0.8), "ff"));
    ls("editor.invisible", &hex_with_alpha(&zed_adjust_lightness(&lt_on_surface_variant, 1.3), "ff"));
    ls("editor.wrap_guide", &hex_with_alpha(&lt_on_surface_variant, "0d"));
    ls("editor.active_wrap_guide", &hex_with_alpha(&lt_on_surface_variant, "1a"));
    ls("editor.document_highlight.read_background", &hex_with_alpha(&primary, "20"));
    ls("editor.document_highlight.write_background", &hex_with_alpha(&lt_on_surface_variant, "66"));
    ls("terminal.background", &hex_with_alpha(&lt_surface, "ff"));
    ls("terminal.foreground", &hex_with_alpha(&lt_on_surface, "ff"));
    ls("terminal.bright_foreground", &hex_with_alpha(&lt_on_surface, "ff"));
    ls("terminal.dim_foreground", &hex_with_alpha(&lt_on_surface_variant, "ff"));
    ls("link_text.hover", &hex_with_alpha(&primary, "ff"));
    ls("version_control.added", &hex_with_alpha(&sat(&tertiary, 1.3), "ff"));
    ls("version_control.modified", &hex_with_alpha(&sat(&primary, 1.3), "ff"));
    ls("version_control.word_added", &hex_with_alpha(&tertiary, "40"));
    ls("version_control.word_deleted", &hex_with_alpha(&error_col, "40"));
    ls("version_control.deleted", &hex_with_alpha(&sat(&error_col, 1.3), "ff"));
    ls("version_control.conflict_marker.ours", &hex_with_alpha(&tertiary, "25"));
    ls("version_control.conflict_marker.theirs", &hex_with_alpha(&primary, "25"));
    ls("conflict", &hex_with_alpha(&sat(&tertiary, 1.3), "ff"));
    ls("conflict.background", &hex_with_alpha(&tertiary, "18"));
    ls("conflict.border", &hex_with_alpha(&sat(&tertiary, 1.5), "ff"));
    ls("created", &hex_with_alpha(&sat(&tertiary, 1.3), "ff"));
    ls("created.background", &hex_with_alpha(&tertiary, "18"));
    ls("created.border", &hex_with_alpha(&sat(&tertiary, 1.5), "ff"));
    ls("deleted", &hex_with_alpha(&sat(&error_col, 1.3), "ff"));
    ls("deleted.background", &hex_with_alpha(&error_col, "18"));
    ls("deleted.border", &hex_with_alpha(&sat(&error_col, 1.5), "ff"));
    ls("error", &hex_with_alpha(&sat(&error_col, 1.3), "ff"));
    ls("error.background", &hex_with_alpha(&error_col, "18"));
    ls("error.border", &hex_with_alpha(&sat(&error_col, 1.5), "ff"));
    ls("hidden", &hex_with_alpha(&lt_on_surface_variant, "ff"));
    ls("hidden.background", &hex_with_alpha(&lt_on_surface_variant, "18"));
    ls("hidden.border", &hex_with_alpha(&lt_outline_variant, "ff"));
    ls("hint", &hex_with_alpha(&sat(&primary, 1.3), "ff"));
    ls("hint.background", &hex_with_alpha(&primary, "18"));
    ls("hint.border", &hex_with_alpha(&sat(&primary, 1.5), "ff"));
    ls("ignored", &hex_with_alpha(&lt_on_surface_variant, "ff"));
    ls("ignored.background", &hex_with_alpha(&lt_on_surface_variant, "18"));
    ls("ignored.border", &hex_with_alpha(&lt_outline_variant, "ff"));
    ls("info", &hex_with_alpha(&sat(&primary, 1.3), "ff"));
    ls("info.background", &hex_with_alpha(&primary, "18"));
    ls("info.border", &hex_with_alpha(&sat(&primary, 1.5), "ff"));
    ls("modified", &hex_with_alpha(&sat(&primary, 1.3), "ff"));
    ls("modified.background", &hex_with_alpha(&primary, "18"));
    ls("modified.border", &hex_with_alpha(&sat(&primary, 1.5), "ff"));
    ls("predictive", &hex_with_alpha(&sat(&secondary, 1.3), "ff"));
    ls("predictive.background", &hex_with_alpha(&secondary, "18"));
    ls("predictive.border", &hex_with_alpha(&sat(&secondary, 1.5), "ff"));
    ls("renamed", &hex_with_alpha(&sat(&primary, 1.3), "ff"));
    ls("renamed.background", &hex_with_alpha(&primary, "18"));
    ls("renamed.border", &hex_with_alpha(&sat(&primary, 1.5), "ff"));
    ls("success", &hex_with_alpha(&sat(&tertiary, 1.3), "ff"));
    ls("success.background", &hex_with_alpha(&tertiary, "18"));
    ls("success.border", &hex_with_alpha(&sat(&tertiary, 1.5), "ff"));
    ls("unreachable", &hex_with_alpha(&lt_on_surface_variant, "ff"));
    ls("unreachable.background", &hex_with_alpha(&lt_on_surface_variant, "18"));
    ls("unreachable.border", &hex_with_alpha(&lt_outline_variant, "ff"));
    ls("warning", &hex_with_alpha(&sat(&tertiary, 1.3), "ff"));
    ls("warning.background", &hex_with_alpha(&tertiary, "18"));
    ls("warning.border", &hex_with_alpha(&sat(&tertiary, 1.5), "ff"));
    ls("terminal.ansi.black", &hex_with_alpha(&zed_term_color(&term_colors, 0), "ff"));
    ls("terminal.ansi.white", &hex_with_alpha(&zed_adjust_lightness(&zed_term_color(&term_colors, 7), 0.5), "ff"));
    ls("terminal.ansi.bright_black", &hex_with_alpha(&zed_adjust_lightness(&zed_term_color(&term_colors, 8), 0.6), "ff"));
    ls("terminal.ansi.bright_white", &hex_with_alpha(&zed_adjust_lightness(&zed_term_color(&term_colors, 15), 0.3), "ff"));
    light_style.insert("panel.focused_border".into(), Value::Null);
    light_style.insert("pane.focused_border".into(), Value::Null);

    for (name, idx) in [
        ("red", 1), ("bright_red", 9), ("dim_red", 1),
        ("green", 2), ("bright_green", 10), ("dim_green", 2),
        ("yellow", 3), ("bright_yellow", 11), ("dim_yellow", 3),
        ("blue", 4), ("bright_blue", 12), ("dim_blue", 4),
        ("magenta", 5), ("bright_magenta", 13), ("dim_magenta", 5),
        ("cyan", 6), ("bright_cyan", 14), ("dim_cyan", 6),
    ] {
        let base = zed_term_color(&term_colors, idx);
        let c = if name.contains("bright") {
            zed_adjust_lightness(&base, 0.75)
        } else if name.contains("dim") {
            zed_adjust_lightness(&base, 0.5)
        } else {
            zed_adjust_lightness(&base, 0.85)
        };
        light_style.insert(
            format!("terminal.ansi.{name}"),
            Value::String(hex_with_alpha(&c, "ff")),
        );
    }
    let light_players: Vec<Value> = [
        sat(&primary, 1.3),
        sat(&error_col, 1.3),
        sat(&tertiary, 1.3),
        sat(&secondary, 1.3),
    ]
    .into_iter()
    .map(|c| {
        json!({
            "cursor": hex_with_alpha(&c, "ff"),
            "background": hex_with_alpha(&c, "ff"),
            "selection": hex_with_alpha(&zed_adjust_lightness(&c, 1.2), "3d")
        })
    })
    .collect();
    light_style.insert("players".into(), Value::Array(light_players));
    light_style.insert("syntax".into(), build_zed_syntax_map(&primary, "light"));

    let borderless_dark = make_zed_borderless(&dark_style);
    let borderless_light = make_zed_borderless(&light_style);
    let alt_dark = dark_style.clone();
    let alt_light = light_style.clone();

    let theme_data = json!({
        "$schema": "https://zed.dev/schema/themes/v0.2.0.json",
        "name": "Alis Material",
        "author": "Alis Theme System",
        "themes": [
            {"name": "Alis Dark", "appearance": "dark", "style": dark_style},
            {"name": "Alis Light", "appearance": "light", "style": light_style},
            {"name": "Alis Borderless Dark", "appearance": "dark", "style": borderless_dark},
            {"name": "Alis Borderless Light", "appearance": "light", "style": borderless_light},
            {"name": "Alis-alt Dark", "appearance": "dark", "style": alt_dark},
            {"name": "Alis-alt Light", "appearance": "light", "style": alt_light}
        ]
    });

    if let Some(parent) = output_path.parent() {
        fs::create_dir_all(parent)?;
    }
    let mut data = serde_json::to_vec_pretty(&theme_data)?;
    data.push(b'\n');
    fs::write(&output_path, data)?;
    println!("✓ Generated Zed theme");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strips_jsonc_comments_and_trailing_commas() {
        let input = br#"{
            // line comment
            "workbench.colorTheme": "Alis Material", /* block */
            "arr": [1, 2, ],
        }"#;
        let stripped = strip_jsonc_comments(input);
        let parsed: Value = serde_json::from_slice(&stripped).expect("valid JSON after strip");
        assert_eq!(parsed["workbench.colorTheme"], "Alis Material");
        assert_eq!(parsed["arr"], json!([1, 2]));
    }
}
