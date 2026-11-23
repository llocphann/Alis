use std::collections::VecDeque;
use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result, anyhow, bail};
use image::codecs::jpeg::JpegEncoder;
use image::imageops::FilterType;
use image::{DynamicImage, GenericImageView, ImageFormat, ImageReader, Rgba, RgbaImage};
use serde_json::Value;

use crate::cover_colors::extract_cover_colors;

fn open_image_guessed(path: &str) -> Result<DynamicImage> {
    ImageReader::open(path)
        .with_context(|| format!("open {path}"))?
        .with_guessed_format()
        .with_context(|| format!("guess image format {path}"))?
        .decode()
        .with_context(|| format!("decode {path}"))
}

const BUILTIN_THEMES: &[(&str, &[&str])] = &[
    ("catppuccin", &["#1e1e2e", "#181825", "#313244", "#45475a", "#cdd6f4", "#f5e0dc", "#f38ba8", "#fab387", "#f9e2af", "#a6e3a1", "#94e2d5", "#89b4fa", "#cba6f7"]),
    ("catppuccin-latte", &["#eff1f5", "#e6e9ef", "#ccd0da", "#4c4f69", "#dc8a78", "#d20f39", "#fe640b", "#df8e1d", "#40a02b", "#179299", "#1e66f5", "#8839ef"]),
    ("catppuccin-frappe", &["#303446", "#292c3c", "#414559", "#c6d0f5", "#e78284", "#ef9f76", "#e5c890", "#a6d189", "#81c8be", "#8caaee", "#ca9ee6"]),
    ("catppuccin-macchiato", &["#24273a", "#1e2030", "#363a4f", "#cad3f5", "#ed8796", "#f5a97f", "#eed49f", "#a6da95", "#8bd5ca", "#8aadf4", "#c6a0f6"]),
    ("dracula", &["#282a36", "#44475a", "#f8f8f2", "#6272a4", "#8be9fd", "#50fa7b", "#ffb86c", "#ff79c6", "#bd93f9", "#ff5555", "#f1fa8c"]),
    ("everforest", &["#2d353b", "#343f44", "#3d484d", "#d3c6aa", "#e67e80", "#e69875", "#dbbc7f", "#a7c080", "#83c092", "#7fbbb3", "#d699b6"]),
    ("gruvbox", &["#282828", "#3c3836", "#504945", "#ebdbb2", "#cc241d", "#98971a", "#d79921", "#458588", "#b16286", "#689d6a", "#d65d0e", "#fb4934", "#b8bb26", "#fabd2f", "#83a598", "#d3869b", "#8ec07c"]),
    ("nord", &["#2e3440", "#3b4252", "#434c5e", "#4c566a", "#d8dee9", "#e5e9f0", "#eceff4", "#8fbcbb", "#88c0d0", "#81a1c1", "#5e81ac", "#bf616a", "#d08770", "#ebcb8b", "#a3be8c", "#b48ead"]),
    ("onedark", &["#282c34", "#353b45", "#3e4451", "#abb2bf", "#e06c75", "#98c379", "#e5c07b", "#61afef", "#c678dd", "#56b6c2", "#d19a66"]),
    ("rose-pine", &["#191724", "#1f1d2e", "#26233a", "#6e6a86", "#908caa", "#e0def4", "#eb6f92", "#f6c177", "#ebbcba", "#31748f", "#9ccfd8", "#c4a7e7"]),
    ("solarized", &["#002b36", "#073642", "#586e75", "#657b83", "#839496", "#93a1a1", "#eee8d5", "#fdf6e3", "#b58900", "#cb4b16", "#dc322f", "#d33682", "#6c71c4", "#268bd2", "#2aa198", "#859900"]),
    ("tokyo-night", &["#1a1b26", "#24283b", "#414868", "#a9b1d6", "#c0caf5", "#f7768e", "#ff9e64", "#e0af68", "#9ece6a", "#73daca", "#7dcfff", "#7aa2f7", "#bb9af7"]),
    ("kanagawa", &["#1f1f28", "#2a2a37", "#363646", "#dcd7ba", "#c34043", "#76946a", "#c0a36e", "#7e9cd8", "#957fb8", "#6a9589", "#ffa066", "#d27e99"]),
    ("monokai", &["#272822", "#3e3d32", "#75715e", "#f8f8f2", "#f92672", "#a6e22e", "#fd971f", "#66d9ef", "#ae81ff", "#e6db74"]),
    ("synthwave84", &["#262335", "#241b2f", "#34294f", "#f92aad", "#fe4450", "#ff7edb", "#fede5d", "#72f1b8", "#36f9f6", "#ffffff"]),
    ("ayu-dark", &["#0b0e14", "#131721", "#202229", "#bfbdb6", "#ff8f40", "#ffb454", "#aad94c", "#39bae6", "#59c2ff", "#d2a6ff", "#f07178"]),
    ("material", &["#212121", "#303030", "#424242", "#eeffff", "#f07178", "#f78c6c", "#ffcb6b", "#c3e88d", "#89ddff", "#82aaff", "#c792ea"]),
    ("cyberpunk", &["#0d0221", "#190041", "#2b0f54", "#ff007f", "#00f0ff", "#ffee00", "#8a2be2", "#00ff9f", "#ffffff"]),
    ("vaporwave", &["#1b0b3b", "#2d1457", "#ff71ce", "#01cdfe", "#05ffa1", "#b967ff", "#fffb96", "#f4f1de"]),
    ("monochrome", &["#0b0b0b", "#1c1c1c", "#333333", "#555555", "#7a7a7a", "#a3a3a3", "#cccccc", "#ededed", "#ffffff"]),
    ("sunset", &["#1a1423", "#3d314a", "#684756", "#96705b", "#ab8476", "#ff6b6b", "#ffa06b", "#ffd166", "#fff1d0"]),
    ("ocean", &["#03045e", "#023e8a", "#0077b6", "#0096c7", "#00b4d8", "#48cae4", "#90e0ef", "#ade8f4", "#caf0f8"]),
    ("forest", &["#081c15", "#1b4332", "#2d6a4f", "#40916c", "#52b788", "#74c69d", "#95d5b2", "#b7e4c7", "#d8f3dc"]),
];

fn parse_hex_rgb(raw: &str) -> Result<[u8; 3]> {
    let s = raw.trim().trim_start_matches('#');
    if !s.is_ascii() {
        bail!("invalid hex color: {raw}");
    }
    if s.len() == 6 {
        let r = u8::from_str_radix(&s[0..2], 16)?;
        let g = u8::from_str_radix(&s[2..4], 16)?;
        let b = u8::from_str_radix(&s[4..6], 16)?;
        return Ok([r, g, b]);
    }
    if s.len() == 3 {
        let r = u8::from_str_radix(&s[0..1], 16)? * 17;
        let g = u8::from_str_radix(&s[1..2], 16)? * 17;
        let b = u8::from_str_radix(&s[2..3], 16)? * 17;
        return Ok([r, g, b]);
    }
    bail!("invalid hex color: {raw}");
}

fn load_palette(theme_arg: &str) -> Result<Vec<[u8; 3]>> {
    let p = Path::new(theme_arg);
    if p.is_file() {
        let text = fs::read_to_string(p)
            .with_context(|| format!("read custom theme {}", p.display()))?;
        let val: Value = serde_json::from_str(&text)?;
        let arr = val
            .get("colors")
            .and_then(|v| v.as_array())
            .ok_or_else(|| anyhow!("custom theme JSON missing colors array"))?;
        let mut out = Vec::new();
        for item in arr {
            if let Some(hex) = item.as_str()
                && let Ok(rgb) = parse_hex_rgb(hex)
            {
                out.push(rgb);
            }
        }
        if out.is_empty() {
            bail!("custom theme palette is empty");
        }
        return Ok(out);
    }
    let needle = theme_arg.trim().to_ascii_lowercase();
    for &(name, colors) in BUILTIN_THEMES {
        if name == needle {
            return colors.iter().map(|c| parse_hex_rgb(c)).collect();
        }
    }
    bail!("unknown gowall theme: {theme_arg}");
}

fn color_dist_sq(a: [u8; 3], b: [u8; 3]) -> f32 {
    let rmean = (a[0] as f32 + b[0] as f32) * 0.5;
    let dr = a[0] as f32 - b[0] as f32;
    let dg = a[1] as f32 - b[1] as f32;
    let db = a[2] as f32 - b[2] as f32;
    (2.0 + rmean / 256.0) * dr * dr + 4.0 * dg * dg + (2.0 + (255.0 - rmean) / 256.0) * db * db
}

fn save_with_format(img: &DynamicImage, output: &Path, fmt_opt: Option<&str>) -> Result<()> {
    if let Some(parent) = output.parent().filter(|p| !p.as_os_str().is_empty()) {
        fs::create_dir_all(parent)?;
    }
    let fmt_str = fmt_opt
        .map(|s| s.to_ascii_lowercase())
        .or_else(|| {
            output
                .extension()
                .and_then(|e| e.to_str())
                .map(|s| s.to_ascii_lowercase())
        })
        .unwrap_or_else(|| "png".to_string());
    let format = match fmt_str.as_str() {
        "jpg" | "jpeg" => ImageFormat::Jpeg,
        "webp" => ImageFormat::WebP,
        "bmp" => ImageFormat::Bmp,
        "gif" => ImageFormat::Gif,
        _ => ImageFormat::Png,
    };
    if format == ImageFormat::Jpeg {
        let rgb = img.to_rgb8();
        rgb.save_with_format(output, ImageFormat::Jpeg)?;
    } else {
        img.save_with_format(output, format)?;
    }
    Ok(())
}

fn recolor_to_palette(img: &DynamicImage, palette: &[[u8; 3]]) -> DynamicImage {
    let mut rgba = img.to_rgba8();
    for px in rgba.pixels_mut() {
        let src = [px[0], px[1], px[2]];
        let mut best_i = 0usize;
        let mut second_i = 0usize;
        let mut best_d = f32::MAX;
        let mut second_d = f32::MAX;
        for (i, &c) in palette.iter().enumerate() {
            let d = color_dist_sq(src, c);
            if d < best_d {
                second_d = best_d;
                second_i = best_i;
                best_d = d;
                best_i = i;
            } else if d < second_d {
                second_d = d;
                second_i = i;
            }
        }
        let c1 = palette[best_i];
        let c2 = palette[second_i];
        let mapped = if palette.len() > 1 && best_d > 1.0 && second_d < best_d * 4.0 {
            let w1 = 1.0 / best_d.sqrt();
            let w2 = 1.0 / second_d.sqrt();
            let sum = w1 + w2;
            [
                ((c1[0] as f32 * w1 + c2[0] as f32 * w2) / sum).round() as u8,
                ((c1[1] as f32 * w1 + c2[1] as f32 * w2) / sum).round() as u8,
                ((c1[2] as f32 * w1 + c2[2] as f32 * w2) / sum).round() as u8,
            ]
        } else {
            c1
        };
        px[0] = mapped[0];
        px[1] = mapped[1];
        px[2] = mapped[2];
    }
    DynamicImage::ImageRgba8(rgba)
}

fn replace_color(img: &DynamicImage, from: [u8; 3], to: [u8; 3]) -> DynamicImage {
    let mut rgba = img.to_rgba8();
    let threshold = 110.0_f32;
    for px in rgba.pixels_mut() {
        let dist = color_dist_sq([px[0], px[1], px[2]], from).sqrt() / 2.2;
        if dist < threshold {
            let t = (1.0 - dist / threshold).powf(1.3);
            px[0] = (px[0] as f32 * (1.0 - t) + to[0] as f32 * t).round().clamp(0.0, 255.0) as u8;
            px[1] = (px[1] as f32 * (1.0 - t) + to[1] as f32 * t).round().clamp(0.0, 255.0) as u8;
            px[2] = (px[2] as f32 * (1.0 - t) + to[2] as f32 * t).round().clamp(0.0, 255.0) as u8;
        }
    }
    DynamicImage::ImageRgba8(rgba)
}

fn remove_background(img: &DynamicImage) -> DynamicImage {
    let mut rgba = img.to_rgba8();
    let (w, h) = rgba.dimensions();
    if w == 0 || h == 0 {
        return DynamicImage::ImageRgba8(rgba);
    }
    let corners = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)];
    let mut visited = vec![false; (w * h) as usize];
    let mut queue: VecDeque<(u32, u32, [u8; 3])> = VecDeque::new();
    for (cx, cy) in corners {
        let p = *rgba.get_pixel(cx, cy);
        visited[(cy * w + cx) as usize] = true;
        queue.push_back((cx, cy, [p[0], p[1], p[2]]));
    }
    let tol_sq = 58.0_f32 * 58.0 * 4.5;
    while let Some((x, y, seed)) = queue.pop_front() {
        rgba.get_pixel_mut(x, y)[3] = 0;
        let neighbors = [
            x.checked_sub(1).map(|nx| (nx, y)),
            (x + 1 < w).then_some((x + 1, y)),
            y.checked_sub(1).map(|ny| (x, ny)),
            (y + 1 < h).then_some((x, y + 1)),
        ];
        for (nx, ny) in neighbors.into_iter().flatten() {
            let idx = (ny * w + nx) as usize;
            if visited[idx] {
                continue;
            }
            let np = *rgba.get_pixel(nx, ny);
            if color_dist_sq([np[0], np[1], np[2]], seed) <= tol_sq {
                visited[idx] = true;
                queue.push_back((nx, ny, seed));
            }
        }
    }
    DynamicImage::ImageRgba8(rgba)
}

fn parse_flag_value(args: &[String], flag: &str) -> Option<String> {
    args.windows(2).find(|w| w[0] == flag).map(|w| w[1].clone())
}

fn first_positional(args: &[String], flags_with_value: &[&str]) -> Option<String> {
    let mut i = 0;
    while i < args.len() {
        if flags_with_value.contains(&args[i].as_str()) {
            i += 2;
            continue;
        }
        if !args[i].starts_with('-') {
            return Some(args[i].clone());
        }
        i += 1;
    }
    None
}

pub fn run_gowall(raw_args: &[String]) -> Result<()> {
    let sub = raw_args
        .first()
        .map(String::as_str)
        .ok_or_else(|| anyhow!("usage: --gowall <list|convert|effects|invert|pixelate|extract|draw|compress|bg|upscale> ..."))?;
    let rest = &raw_args[1..];

    match sub {
        "list" => {
            for &(name, _) in BUILTIN_THEMES {
                println!("{name}");
            }
            Ok(())
        }
        "convert" => {
            let src = first_positional(rest, &["--theme", "-t", "--replace", "--output", "-o", "--format"])
                .ok_or_else(|| anyhow!("convert requires source image"))?;
            let out = parse_flag_value(rest, "--output")
                .or_else(|| parse_flag_value(rest, "-o"))
                .ok_or_else(|| anyhow!("convert requires --output"))?;
            let fmt = parse_flag_value(rest, "--format");
            let img = open_image_guessed(&src)?;
            let result = if let Some(rep) = parse_flag_value(rest, "--replace") {
                let (from_s, to_s) = rep
                    .split_once(',')
                    .ok_or_else(|| anyhow!("--replace expects #from,#to"))?;
                replace_color(&img, parse_hex_rgb(from_s)?, parse_hex_rgb(to_s)?)
            } else if let Some(theme) = parse_flag_value(rest, "--theme").or_else(|| parse_flag_value(rest, "-t")) {
                let pal = load_palette(&theme)?;
                recolor_to_palette(&img, &pal)
            } else {
                bail!("convert requires --theme or --replace");
            };
            save_with_format(&result, Path::new(&out), fmt.as_deref())
        }
        "effects" => {
            let effect = rest
                .first()
                .map(String::as_str)
                .ok_or_else(|| anyhow!("effects requires effect name"))?;
            let eff_args = &rest[1..];
            let src = first_positional(eff_args, &["--factor", "--output", "-o", "--format"])
                .ok_or_else(|| anyhow!("effects requires source image"))?;
            let out = parse_flag_value(eff_args, "--output")
                .or_else(|| parse_flag_value(eff_args, "-o"))
                .ok_or_else(|| anyhow!("effects requires --output"))?;
            let fmt = parse_flag_value(eff_args, "--format");
            let img = open_image_guessed(&src)?;
            let result = match effect {
                "grayscale" => img.grayscale(),
                "flip" => img.flipv(),
                "mirror" => img.fliph(),
                "br" => {
                    let factor: f32 = parse_flag_value(eff_args, "--factor")
                        .and_then(|v| v.parse().ok())
                        .unwrap_or(1.0);
                    let mut rgba = img.to_rgba8();
                    for px in rgba.pixels_mut() {
                        px[0] = (px[0] as f32 * factor).round().clamp(0.0, 255.0) as u8;
                        px[1] = (px[1] as f32 * factor).round().clamp(0.0, 255.0) as u8;
                        px[2] = (px[2] as f32 * factor).round().clamp(0.0, 255.0) as u8;
                    }
                    DynamicImage::ImageRgba8(rgba)
                }
                other => bail!("unsupported gowall effect: {other}"),
            };
            save_with_format(&result, Path::new(&out), fmt.as_deref())
        }
        "invert" => {
            let src = first_positional(rest, &["--output", "-o", "--format"])
                .ok_or_else(|| anyhow!("invert requires source image"))?;
            let out = parse_flag_value(rest, "--output")
                .or_else(|| parse_flag_value(rest, "-o"))
                .ok_or_else(|| anyhow!("invert requires --output"))?;
            let fmt = parse_flag_value(rest, "--format");
            let mut img = open_image_guessed(&src)?;
            img.invert();
            save_with_format(&img, Path::new(&out), fmt.as_deref())
        }
        "pixelate" => {
            let src = first_positional(rest, &["--scale", "-s", "--output", "-o", "--format"])
                .ok_or_else(|| anyhow!("pixelate requires source image"))?;
            let out = parse_flag_value(rest, "--output")
                .or_else(|| parse_flag_value(rest, "-o"))
                .ok_or_else(|| anyhow!("pixelate requires --output"))?;
            let fmt = parse_flag_value(rest, "--format");
            let scale: f32 = parse_flag_value(rest, "--scale")
                .or_else(|| parse_flag_value(rest, "-s"))
                .and_then(|v| v.parse::<f32>().ok())
                .filter(|v| v.is_finite() && *v > 0.0)
                .unwrap_or(10.0_f32);
            let img = open_image_guessed(&src)?;
            let result = pixelate_image(&img, scale);
            save_with_format(&result, Path::new(&out), fmt.as_deref())
        }
        "extract" => {
            let src = first_positional(rest, &["-c", "--colors"])
                .ok_or_else(|| anyhow!("extract requires source image"))?;
            let count: usize = parse_flag_value(rest, "-c")
                .or_else(|| parse_flag_value(rest, "--colors"))
                .and_then(|v| v.parse().ok())
                .unwrap_or(6)
                .clamp(1, 16);
            let colors = extract_cover_colors(Path::new(&src), count)?;
            for c in colors {
                println!("{c}");
            }
            Ok(())
        }
        "draw" => {
            let kind = rest
                .first()
                .map(String::as_str)
                .ok_or_else(|| anyhow!("draw requires border|grid"))?;
            let draw_args = &rest[1..];
            let src = first_positional(
                draw_args,
                &["--color", "--borderThickness", "--size", "--thickness", "--output", "-o", "--format"],
            )
            .ok_or_else(|| anyhow!("draw requires source image"))?;
            let out = parse_flag_value(draw_args, "--output")
                .or_else(|| parse_flag_value(draw_args, "-o"))
                .ok_or_else(|| anyhow!("draw requires --output"))?;
            let fmt = parse_flag_value(draw_args, "--format");
            let col = parse_hex_rgb(
                &parse_flag_value(draw_args, "--color").unwrap_or_else(|| "#ffffff".to_string()),
            )?;
            let rgba_col = Rgba([col[0], col[1], col[2], 255]);
            let img = open_image_guessed(&src)?;
            let result = match kind {
                "border" => {
                    let thickness: u32 = parse_flag_value(draw_args, "--borderThickness")
                        .or_else(|| parse_flag_value(draw_args, "--thickness"))
                        .and_then(|v| v.parse().ok())
                        .unwrap_or(16)
                        .min(512);
                    let (w, h) = img.dimensions();
                    let mut canvas = RgbaImage::from_pixel(w + thickness * 2, h + thickness * 2, rgba_col);
                    image::imageops::overlay(&mut canvas, &img.to_rgba8(), thickness as i64, thickness as i64);
                    DynamicImage::ImageRgba8(canvas)
                }
                "grid" => {
                    let grid_size: u32 = parse_flag_value(draw_args, "--size")
                        .and_then(|v| v.parse().ok())
                        .unwrap_or(64)
                        .max(4);
                    let thickness: u32 = parse_flag_value(draw_args, "--thickness")
                        .and_then(|v| v.parse().ok())
                        .unwrap_or(2)
                        .max(1);
                    let mut canvas = img.to_rgba8();
                    let (w, h) = canvas.dimensions();
                    let mut x = 0;
                    while x < w {
                        for dx in 0..thickness {
                            if x + dx < w {
                                for y in 0..h {
                                    canvas.put_pixel(x + dx, y, rgba_col);
                                }
                            }
                        }
                        x += grid_size;
                    }
                    let mut y = 0;
                    while y < h {
                        for dy in 0..thickness {
                            if y + dy < h {
                                for x in 0..w {
                                    canvas.put_pixel(x, y + dy, rgba_col);
                                }
                            }
                        }
                        y += grid_size;
                    }
                    DynamicImage::ImageRgba8(canvas)
                }
                other => bail!("unsupported draw kind: {other}"),
            };
            save_with_format(&result, Path::new(&out), fmt.as_deref())
        }
        "compress" => {
            let src = first_positional(rest, &["--quality", "--method", "--output", "-o"])
                .ok_or_else(|| anyhow!("compress requires source image"))?;
            let out = parse_flag_value(rest, "--output")
                .or_else(|| parse_flag_value(rest, "-o"))
                .ok_or_else(|| anyhow!("compress requires --output"))?;
            let quality: u8 = parse_flag_value(rest, "--quality")
                .and_then(|v| v.parse().ok())
                .unwrap_or(80)
                .clamp(1, 100);
            let orig_size = fs::metadata(&src).map(|m| m.len()).unwrap_or(0);
            let img = open_image_guessed(&src)?;
            let out_path = PathBuf::from(&out);
            if let Some(parent) = out_path.parent().filter(|p| !p.as_os_str().is_empty()) {
                fs::create_dir_all(parent)?;
            }
            let ext = out_path
                .extension()
                .and_then(|e| e.to_str())
                .unwrap_or("jpg")
                .to_ascii_lowercase();
            if ext == "jpg" || ext == "jpeg" {
                let mut file = fs::File::create(&out_path)?;
                let mut enc = JpegEncoder::new_with_quality(&mut file, quality);
                enc.encode_image(&img.to_rgb8())?;
            } else {
                save_with_format(&img, &out_path, Some(&ext))?;
            }
            let new_size = fs::metadata(&out_path).map(|m| m.len()).unwrap_or(0);
            let saved_pct = if orig_size > 0 && new_size < orig_size {
                ((orig_size - new_size) as f64 * 100.0) / orig_size as f64
            } else {
                0.0
            };
            println!(
                "Compressed: {:.1} KB -> {:.1} KB ({:.1}% saved)",
                orig_size as f64 / 1024.0,
                new_size as f64 / 1024.0,
                saved_pct
            );
            Ok(())
        }
        "bg" => {
            let src = first_positional(rest, &["--output", "-o", "--format"])
                .ok_or_else(|| anyhow!("bg requires source image"))?;
            let out = parse_flag_value(rest, "--output")
                .or_else(|| parse_flag_value(rest, "-o"))
                .ok_or_else(|| anyhow!("bg requires --output"))?;
            let img = open_image_guessed(&src)?;
            let result = remove_background(&img);
            save_with_format(&result, Path::new(&out), Some("png"))
        }
        "upscale" => {
            let src = first_positional(rest, &["--scale", "--model", "--output", "-o", "--format"])
                .ok_or_else(|| anyhow!("upscale requires source image"))?;
            let out = parse_flag_value(rest, "--output")
                .or_else(|| parse_flag_value(rest, "-o"))
                .ok_or_else(|| anyhow!("upscale requires --output"))?;
            let fmt = parse_flag_value(rest, "--format");
            let scale: u32 = parse_flag_value(rest, "--scale")
                .and_then(|v| v.parse().ok())
                .unwrap_or(2)
                .clamp(1, 4);
            let img = open_image_guessed(&src)?;
            let (w, h) = img.dimensions();
            let upscaled = img.resize_exact(w * scale, h * scale, FilterType::Lanczos3);
            let sharpened = upscaled.unsharpen(1.0, 4);
            save_with_format(&sharpened, Path::new(&out), fmt.as_deref())
        }
        other => bail!("unknown gowall subcommand: {other}"),
    }
}

fn pixelate_image(img: &DynamicImage, scale: f32) -> DynamicImage {
    let (w, h) = img.dimensions();
    let factor = if scale >= 1.0 {
        (scale / 100.0).clamp(0.01, 1.0)
    } else {
        scale.clamp(0.01, 1.0)
    };
    let sw = ((w as f32) * factor).round().max(4.0) as u32;
    let sh = ((h as f32) * factor).round().max(4.0) as u32;
    let small = img.resize_exact(sw, sh, FilterType::Nearest);
    small.resize_exact(w, h, FilterType::Nearest)
}

#[cfg(test)]
mod tests {
    use super::{
        BUILTIN_THEMES, load_palette, parse_hex_rgb, pixelate_image, recolor_to_palette,
    };
    use image::{DynamicImage, GenericImageView, Rgb, RgbImage};
    use std::collections::HashSet;

    #[test]
    fn builtin_themes_parse_and_recolor() {
        assert!(BUILTIN_THEMES.len() >= 20);
        let pal = load_palette("catppuccin").unwrap();
        assert!(pal.len() >= 8);
        assert_eq!(parse_hex_rgb("#ff8800").unwrap(), [255, 136, 0]);
        let img = DynamicImage::ImageRgb8(RgbImage::from_pixel(8, 8, Rgb([200, 100, 50])));
        let out = recolor_to_palette(&img, &pal);
        assert_eq!(out.width(), 8);
    }

    #[test]
    fn parse_hex_rgb_rejects_non_ascii_without_panic() {
        assert!(parse_hex_rgb("éa").is_err());
        assert!(parse_hex_rgb("#éa").is_err());
        assert!(parse_hex_rgb("éaéa").is_err());
        assert!(parse_hex_rgb("#ééé").is_err());
    }

    #[test]
    fn pixelate_smaller_scale_is_blockier() {
        let mut raw = RgbImage::new(100, 100);
        for (x, y, px) in raw.enumerate_pixels_mut() {
            *px = Rgb([((x * 7) % 256) as u8, ((y * 11) % 256) as u8, (((x + y) * 5) % 256) as u8]);
        }
        let img = DynamicImage::ImageRgb8(raw);
        let strong = pixelate_image(&img, 1.0);
        let finer = pixelate_image(&img, 25.0);

        let orig_bytes = img.to_rgb8().into_raw();
        let strong_bytes = strong.to_rgb8().into_raw();
        let finer_bytes = finer.to_rgb8().into_raw();
        assert_ne!(strong_bytes, orig_bytes);
        assert_ne!(finer_bytes, orig_bytes);
        assert_ne!(strong_bytes, finer_bytes);

        let unique_colors = |buf: &DynamicImage| -> usize {
            buf.pixels().map(|(_, _, p)| p.0).collect::<HashSet<_>>().len()
        };
        assert!(unique_colors(&strong) < unique_colors(&finer));
    }
}
