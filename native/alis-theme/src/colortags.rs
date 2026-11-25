use std::collections::HashSet;
use std::fs;
use std::io::{self, IsTerminal, Read};
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use anyhow::Result;
use image::imageops::FilterType;
use material_color_utils::hct::Hct;
use material_color_utils::utils::color_utils::Argb;
use serde_json::{Map, Value, json};

const CACHE_VERSION: i64 = 3;

const BUCKET_ORDER: &[&str] = &[
    "red",
    "orange",
    "yellow",
    "green",
    "cyan",
    "blue",
    "purple",
    "pink",
    "monochrome",
];

const IMAGE_EXTS: &[&str] = &["jpg", "jpeg", "png", "webp", "avif", "bmp", "gif"];

fn xdg_cache_dir() -> PathBuf {
    if let Some(xdg) = std::env::var_os("XDG_CACHE_HOME")
        && !xdg.is_empty()
    {
        return PathBuf::from(xdg);
    }
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/tmp"))
        .join(".cache")
}

fn cache_path() -> PathBuf {
    xdg_cache_dir().join("alis/wallpaper-color-tags.json")
}

fn thumb_root() -> PathBuf {
    xdg_cache_dir().join("thumbnails")
}

fn md5_hex(input: &[u8]) -> String {
    const S: [u32; 64] = [
        7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 5, 9, 14, 20, 5, 9, 14, 20, 5,
        9, 14, 20, 5, 9, 14, 20, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 6, 10,
        15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
    ];
    const K: [u32; 64] = [
        0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, 0xf57c0faf, 0x4787c62a, 0xa8304613,
        0xfd469501, 0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be, 0x6b901122, 0xfd987193,
        0xa679438e, 0x49b40821, 0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa, 0xd62f105d,
        0x02441453, 0xd8a1e681, 0xe7d3fbc8, 0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
        0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a, 0xfffa3942, 0x8771f681, 0x6d9d6122,
        0xfde5380c, 0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70, 0x289b7ec6, 0xeaa127fa,
        0xd4ef3085, 0x04881d05, 0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665, 0xf4292244,
        0x432aff97, 0xab9423a7, 0xfc93a039, 0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
        0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1, 0xf7537e82, 0xbd3af235, 0x2ad7d2bb,
        0xeb86d391,
    ];

    let mut msg = input.to_vec();
    let bit_len = (input.len() as u64).wrapping_mul(8);
    msg.push(0x80);
    while msg.len() % 64 != 56 {
        msg.push(0);
    }
    msg.extend_from_slice(&bit_len.to_le_bytes());

    let mut a0: u32 = 0x67452301;
    let mut b0: u32 = 0xefcdab89;
    let mut c0: u32 = 0x98badcfe;
    let mut d0: u32 = 0x10325476;

    for chunk in msg.chunks_exact(64) {
        let mut m = [0u32; 16];
        for (i, word) in chunk.chunks_exact(4).enumerate() {
            m[i] = u32::from_le_bytes([word[0], word[1], word[2], word[3]]);
        }
        let (mut a, mut b, mut c, mut d) = (a0, b0, c0, d0);
        for i in 0..64 {
            let (f, g) = match i {
                0..=15 => ((b & c) | (!b & d), i),
                16..=31 => ((d & b) | (!d & c), (5 * i + 1) % 16),
                32..=47 => (b ^ c ^ d, (3 * i + 5) % 16),
                _ => (c ^ (b | !d), (7 * i) % 16),
            };
            let temp = d;
            d = c;
            c = b;
            b = b.wrapping_add(
                a.wrapping_add(f)
                    .wrapping_add(K[i])
                    .wrapping_add(m[g])
                    .rotate_left(S[i]),
            );
            a = temp;
        }
        a0 = a0.wrapping_add(a);
        b0 = b0.wrapping_add(b);
        c0 = c0.wrapping_add(c);
        d0 = d0.wrapping_add(d);
    }

    let mut out = String::with_capacity(32);
    for word in [a0, b0, c0, d0] {
        for byte in word.to_le_bytes() {
            out.push_str(&format!("{byte:02x}"));
        }
    }
    out
}

fn percent_encode_part(part: &str) -> String {
    let mut out = String::with_capacity(part.len());
    for &b in part.as_bytes() {
        if b.is_ascii_alphanumeric() || matches!(b, b'-' | b'_' | b'.' | b'~') {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

fn find_existing_thumbnail(path: &str, root: &Path) -> PathBuf {
    let encoded = path
        .split('/')
        .map(percent_encode_part)
        .collect::<Vec<_>>()
        .join("/");
    let uri = format!("file://{encoded}");
    let md5_file = format!("{}.png", md5_hex(uri.as_bytes()));
    for size_dir in ["normal", "large", "x-large", "xx-large"] {
        let candidate = root.join(size_dir).join(&md5_file);
        if candidate.is_file() {
            return candidate;
        }
    }
    PathBuf::from(path)
}

fn rgb_to_hsv(r: f64, g: f64, b: f64) -> (f64, f64, f64) {
    let maxc = r.max(g).max(b);
    let minc = r.min(g).min(b);
    let v = maxc;
    if (minc - maxc).abs() < f64::EPSILON {
        return (0.0, 0.0, v);
    }
    let span = maxc - minc;
    let s = span / maxc;
    let rc = (maxc - r) / span;
    let gc = (maxc - g) / span;
    let bc = (maxc - b) / span;
    let mut h = if (r - maxc).abs() < f64::EPSILON {
        bc - gc
    } else if (g - maxc).abs() < f64::EPSILON {
        2.0 + rc - bc
    } else {
        4.0 + gc - rc
    };
    h = (h / 6.0).rem_euclid(1.0);
    (h, s, v)
}

fn hue_deg_to_chromatic_bucket(h_deg: f64) -> &'static str {
    let h = h_deg.rem_euclid(360.0);
    if !(14.0..345.0).contains(&h) {
        return "red";
    }
    if h < 40.0 {
        return "orange";
    }
    if h < 68.0 {
        return "yellow";
    }
    if h < 162.0 {
        return "green";
    }
    if h < 200.0 {
        return "cyan";
    }
    if h < 255.0 {
        return "blue";
    }
    if h < 295.0 {
        return "purple";
    }
    "pink"
}

#[cfg(test)]
fn hue_to_bucket(h_deg: f64, s: f64, v: f64) -> &'static str {
    if v < 0.10 || s < 0.14 {
        return "monochrome";
    }
    hue_deg_to_chromatic_bucket(h_deg)
}

fn hue_distance_deg(a: f64, b: f64) -> f64 {
    let d = (a - b).rem_euclid(360.0);
    d.min(360.0 - d)
}

fn argb_to_hsv_deg(argb: Argb) -> (f64, f64, f64) {
    let rf = f64::from(argb.red()) / 255.0;
    let gf = f64::from(argb.green()) / 255.0;
    let bf = f64::from(argb.blue()) / 255.0;
    let (h, s, v) = rgb_to_hsv(rf, gf, bf);
    (h * 360.0, s, v)
}

fn configured_scheme_option() -> String {
    let raw = std::env::var("ALIS_COLOR_TAGS_SCHEME").unwrap_or_default();
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        "auto".to_owned()
    } else {
        trimmed.to_owned()
    }
}

fn configured_invert_hue() -> bool {
    let raw = std::env::var("ALIS_COLOR_TAGS_INVERT_HUE").unwrap_or_default();
    matches!(
        raw.trim().to_ascii_lowercase().as_str(),
        "1" | "true" | "yes" | "on"
    )
}

fn classify_filename_fallback(path: &str) -> Vec<String> {
    let lower = Path::new(path)
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or_default()
        .to_ascii_lowercase();
    BUCKET_ORDER
        .iter()
        .filter(|&&b| lower.contains(b))
        .map(|&b| b.to_owned())
        .collect()
}

#[derive(Clone)]
struct ImageColorFeatures {
    seed: Option<u32>,
    auto_scheme: String,
    mono_ratio: f64,
    chromatic_weight: f64,
    total_weight: f64,
    bucket_weights: [f64; 8],
    hue_weights: [f64; 36],
    hue_pixels: [u16; 36],
}

fn round4(v: f64) -> f64 {
    (v * 10000.0).round() / 10000.0
}

fn argb_to_rgb_u32(argb: Argb) -> u32 {
    (0xFFu32 << 24)
        | (u32::from(argb.red()) << 16)
        | (u32::from(argb.green()) << 8)
        | u32::from(argb.blue())
}

fn rgb_u32_to_argb(raw: u32) -> Argb {
    Argb::from_rgb(
        ((raw >> 16) & 0xFF) as u8,
        ((raw >> 8) & 0xFF) as u8,
        (raw & 0xFF) as u8,
    )
}

impl ImageColorFeatures {
    fn to_json_value(&self) -> Value {
        json!({
            "seed": self.seed,
            "auto": self.auto_scheme,
            "mono": round4(self.mono_ratio),
            "cw": round4(self.chromatic_weight),
            "tw": round4(self.total_weight),
            "bw": self.bucket_weights.iter().map(|&v| round4(v)).collect::<Vec<f64>>(),
            "hw": self.hue_weights.iter().map(|&v| round4(v)).collect::<Vec<f64>>(),
            "hp": self.hue_pixels.iter().copied().collect::<Vec<u16>>(),
        })
    }

    fn from_cache_entry(cached: &Map<String, Value>) -> Option<Self> {
        let feat = cached.get("feat")?.as_object()?;
        let seed = match feat.get("seed") {
            Some(Value::Null) | None => None,
            Some(v) => Some(u32::try_from(v.as_u64()?).ok()?),
        };
        let auto_scheme = feat.get("auto")?.as_str()?.to_owned();
        let mono_ratio = feat.get("mono")?.as_f64()?;
        let chromatic_weight = feat.get("cw")?.as_f64()?;
        let total_weight = feat.get("tw")?.as_f64()?;
        let bw_arr = feat.get("bw")?.as_array()?;
        let hw_arr = feat.get("hw")?.as_array()?;
        let hp_arr = feat.get("hp")?.as_array()?;
        if bw_arr.len() != 8 || hw_arr.len() != 36 || hp_arr.len() != 36 {
            return None;
        }
        let mut bucket_weights = [0.0f64; 8];
        for (i, item) in bw_arr.iter().enumerate() {
            bucket_weights[i] = item.as_f64()?;
        }
        let mut hue_weights = [0.0f64; 36];
        for (i, item) in hw_arr.iter().enumerate() {
            hue_weights[i] = item.as_f64()?;
        }
        let mut hue_pixels = [0u16; 36];
        for (i, item) in hp_arr.iter().enumerate() {
            hue_pixels[i] = u16::try_from(item.as_u64()?).ok()?;
        }
        Some(Self {
            seed,
            auto_scheme,
            mono_ratio,
            chromatic_weight,
            total_weight,
            bucket_weights,
            hue_weights,
            hue_pixels,
        })
    }
}

fn bucket_index(bucket: &str) -> Option<usize> {
    BUCKET_ORDER[..8].iter().position(|&b| b == bucket)
}

fn extract_image_features(path: &str, thumbs: &Path) -> Option<ImageColorFeatures> {
    let source_path = find_existing_thumbnail(path, thumbs);
    let mut img = image::open(&source_path).ok()?;

    let (orig_w, orig_h) = (img.width(), img.height());
    let (opt_w, opt_h) = crate::source::calculate_optimal_size(orig_w, orig_h, 128);
    if opt_w < orig_w || opt_h < orig_h {
        img = img.resize_exact(opt_w, opt_h, FilterType::Triangle);
    }

    let sample_small = img.to_rgb8();
    let sample_resized = image::imageops::resize(&sample_small, 32, 32, FilterType::Triangle);
    let raw = sample_resized.as_raw();
    if raw.is_empty() {
        return None;
    }

    let mut mono_count = 0.0;
    let mut chromatic_weight = 0.0;
    let mut total_weight = 0.0;
    let mut bucket_weights = [0.0f64; 8];
    let mut hue_weights = [0.0f64; 36];
    let mut hue_pixels = [0u16; 36];

    for pixel in raw.chunks_exact(3) {
        let rf = pixel[0] as f64 / 255.0;
        let gf = pixel[1] as f64 / 255.0;
        let bf = pixel[2] as f64 / 255.0;
        let (h, s, v) = rgb_to_hsv(rf, gf, bf);
        let h_deg = h * 360.0;
        total_weight += 1.0;
        if v < 0.10 || s < 0.14 {
            mono_count += 1.0;
            continue;
        }
        let bucket = hue_deg_to_chromatic_bucket(h_deg);
        let weight = (0.5 + 0.5 * s) * (0.4 + 0.6 * (v * 1.25).min(1.0));
        if let Some(b_idx) = bucket_index(bucket) {
            bucket_weights[b_idx] += weight;
        }
        chromatic_weight += weight;
        let bin = ((h_deg.rem_euclid(360.0) / 10.0).floor() as usize).min(35);
        hue_weights[bin] += weight;
        hue_pixels[bin] = hue_pixels[bin].saturating_add(1);
    }

    if total_weight <= 0.0 {
        return None;
    }

    let mono_ratio = mono_count / total_weight;
    let auto_scheme = crate::source::auto_detect_scheme(&img).to_owned();
    let seed = crate::source::image_seed(&img).ok().map(argb_to_rgb_u32);

    Some(ImageColorFeatures {
        seed,
        auto_scheme,
        mono_ratio,
        chromatic_weight,
        total_weight,
        bucket_weights,
        hue_weights,
        hue_pixels,
    })
}

fn classify_from_features(
    features: &ImageColorFeatures,
    scheme_opt: &str,
    invert_hue_opt: bool,
) -> Vec<String> {
    if features.total_weight <= 0.0 {
        return Vec::new();
    }

    let eff_scheme = if scheme_opt == "auto" {
        features.auto_scheme.as_str()
    } else {
        scheme_opt
    };

    if eff_scheme == "scheme-monochrome" || features.chromatic_weight <= 0.01 {
        return vec!["monochrome".to_owned()];
    }

    let Some(seed_raw) = features.seed else {
        let mut best_idx = None;
        let mut best_val = 0.0f64;
        for (i, &w) in features.bucket_weights.iter().enumerate() {
            if w > best_val {
                best_val = w;
                best_idx = Some(i);
            }
        }
        return best_idx
            .map(|i| vec![BUCKET_ORDER[i].to_owned()])
            .unwrap_or_default();
    };

    let mut seed = rgb_u32_to_argb(seed_raw);
    let raw_seed_hct = Hct::from_argb(seed);
    if !invert_hue_opt && features.mono_ratio >= 0.85 && raw_seed_hct.chroma() < 15.0 {
        return vec!["monochrome".to_owned()];
    }

    if invert_hue_opt {
        seed = crate::source::invert_hue(seed);
    }

    let primary_argb = crate::palette::primary_theme_color(seed, eff_scheme, true);
    let primary_hct = Hct::from_argb(primary_argb);
    if primary_hct.chroma() < 8.0 || (raw_seed_hct.chroma() < 12.0 && features.mono_ratio >= 0.65) {
        return vec!["monochrome".to_owned()];
    }

    let (theme_hue_deg, _, _) = argb_to_hsv_deg(primary_argb);
    let theme_bucket = hue_deg_to_chromatic_bucket(theme_hue_deg);

    // Ensure the auto-themed bucket is genuinely present in the wallpaper as well
    // (excludes rotated palettes such as expressive/invert-hue when absent from image,
    // and blocks Score.score's #4285F4 blue fallback from polluting monochrome images).
    let mut matched_weight = 0.0;
    let mut matched_pixels = 0.0;
    for bin in 0..36 {
        let px_count = f64::from(features.hue_pixels[bin]);
        if px_count <= 0.0 {
            continue;
        }
        let bin_center = (bin as f64) * 10.0 + 5.0;
        let bin_bucket = hue_deg_to_chromatic_bucket(bin_center);
        if bin_bucket == theme_bucket || hue_distance_deg(bin_center, theme_hue_deg) <= 28.0 {
            matched_weight += features.hue_weights[bin];
            matched_pixels += px_count;
        }
    }

    let visual_support = matched_weight / features.chromatic_weight.max(1e-6);
    let matched_pixel_ratio = matched_pixels / features.total_weight;
    if visual_support >= 0.08 && matched_pixel_ratio >= 0.005 {
        return vec![theme_bucket.to_owned()];
    }

    if features.mono_ratio >= 0.78 {
        return vec!["monochrome".to_owned()];
    }
    Vec::new()
}

#[cfg(test)]
fn analyze_image(
    path: &str,
    thumbs: &Path,
    scheme_opt: &str,
    invert_hue_opt: bool,
) -> Vec<String> {
    match extract_image_features(path, thumbs) {
        Some(features) => classify_from_features(&features, scheme_opt, invert_hue_opt),
        None => classify_filename_fallback(path),
    }
}

fn expand_tilde(raw: &str) -> PathBuf {
    if let Some(rest) = raw.strip_prefix("~/")
        && let Some(home) = std::env::var_os("HOME")
    {
        return PathBuf::from(home).join(rest);
    }
    PathBuf::from(raw)
}

fn walk_dir_images(
    dir: &Path,
    visited_dirs: &mut HashSet<PathBuf>,
    seen: &mut HashSet<String>,
    found: &mut Vec<String>,
) {
    let canonical = fs::canonicalize(dir).unwrap_or_else(|_| dir.to_path_buf());
    if !visited_dirs.insert(canonical) {
        return;
    }
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    let mut subdirs = Vec::new();
    for entry in entries.flatten() {
        let path = entry.path();
        let Ok(meta) = fs::metadata(&path) else {
            continue;
        };
        if meta.is_dir() {
            subdirs.push(path);
        } else if meta.is_file()
            && let Some(ext) = path.extension().and_then(|e| e.to_str())
            && IMAGE_EXTS.contains(&ext.to_ascii_lowercase().as_str())
        {
            let full = path.to_string_lossy().into_owned();
            if seen.insert(full.clone()) {
                found.push(full);
            }
        }
    }
    for sub in subdirs {
        walk_dir_images(&sub, visited_dirs, seen, found);
    }
}

fn collect_from_roots(roots: &[String]) -> Vec<String> {
    let mut found = Vec::new();
    let mut seen = HashSet::new();
    let mut visited_dirs = HashSet::new();
    for root in roots {
        let trimmed = root.trim_end_matches('/');
        let normalized = if trimmed.is_empty() && !root.is_empty() {
            "/"
        } else {
            trimmed
        };
        let root_path = expand_tilde(normalized);
        if fs::metadata(&root_path).map(|m| m.is_dir()).unwrap_or(false) {
            walk_dir_images(&root_path, &mut visited_dirs, &mut seen, &mut found);
        }
    }
    found
}

fn load_cache(path: &Path) -> Map<String, Value> {
    if let Ok(text) = fs::read_to_string(path)
        && let Ok(Value::Object(map)) = serde_json::from_str::<Value>(&text)
    {
        return map;
    }
    Map::new()
}

fn save_cache(path: &Path, cache: &Map<String, Value>) {
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    let tmp = path.with_extension("tmp");
    if let Ok(bytes) = serde_json::to_vec(cache)
        && fs::write(&tmp, bytes).is_ok()
    {
        let _ = fs::rename(&tmp, path);
    }
}

fn cache_entry_matches(
    cached: &Map<String, Value>,
    mtime: i64,
    scheme_opt: &str,
    invert_hue_opt: bool,
) -> Option<Vec<Value>> {
    let ver = cached.get("v").and_then(Value::as_i64)?;
    if ver != 2 && ver != CACHE_VERSION {
        return None;
    }
    if cached.get("mtime").and_then(Value::as_i64) != Some(mtime) {
        return None;
    }
    if cached.get("scheme").and_then(Value::as_str) != Some(scheme_opt) {
        return None;
    }
    if cached
        .get("invert")
        .and_then(Value::as_bool)
        .unwrap_or(false)
        != invert_hue_opt
    {
        return None;
    }
    cached.get("colors").and_then(Value::as_array).cloned()
}

fn compute_color_tags_with_paths(
    paths: Vec<String>,
    thumbs: &Path,
    cpath: &Path,
    scheme_opt: &str,
    invert_hue_opt: bool,
) -> Map<String, Value> {
    let mut cache = load_cache(cpath);
    let mut result = Map::new();
    let mut to_compute: Vec<(String, i64)> = Vec::new();
    let mut cache_dirty = false;

    for path in paths {
        let mtime = fs::metadata(&path).map(|m| m.mtime()).unwrap_or(0);
        if let Some(Value::Object(cached)) = cache.get_mut(&path) {
            if let Some(colors) = cache_entry_matches(cached, mtime, scheme_opt, invert_hue_opt) {
                result.insert(path, Value::Array(colors));
                continue;
            }
            if mtime > 0
                && cached.get("v").and_then(Value::as_i64) == Some(CACHE_VERSION)
                && cached.get("mtime").and_then(Value::as_i64) == Some(mtime)
                && let Some(features) = ImageColorFeatures::from_cache_entry(cached)
            {
                let colors = classify_from_features(&features, scheme_opt, invert_hue_opt);
                let arr: Vec<Value> = colors.into_iter().map(Value::String).collect();
                cached.insert("scheme".to_owned(), Value::String(scheme_opt.to_owned()));
                cached.insert("invert".to_owned(), Value::Bool(invert_hue_opt));
                cached.insert("colors".to_owned(), Value::Array(arr.clone()));
                result.insert(path, Value::Array(arr));
                cache_dirty = true;
                continue;
            }
        }
        to_compute.push((path, mtime));
    }

    if !to_compute.is_empty() {
        let workers = to_compute.len().clamp(1, 8);
        let chunk_size = to_compute.len().div_ceil(workers);
        let computed: Mutex<Vec<(String, i64, Option<ImageColorFeatures>, Vec<String>)>> =
            Mutex::new(Vec::with_capacity(to_compute.len()));

        std::thread::scope(|scope| {
            for chunk in to_compute.chunks(chunk_size) {
                let computed = &computed;
                scope.spawn(move || {
                    let mut local = Vec::with_capacity(chunk.len());
                    for (path, mtime) in chunk {
                        let features = extract_image_features(path, thumbs);
                        let tags = match features.as_ref() {
                            Some(feat) => classify_from_features(feat, scheme_opt, invert_hue_opt),
                            None => classify_filename_fallback(path),
                        };
                        local.push((path.clone(), *mtime, features, tags));
                    }
                    if let Ok(mut guard) = computed.lock() {
                        guard.extend(local);
                    }
                });
            }
        });

        for (path, mtime, features, colors) in computed.into_inner().unwrap_or_default() {
            let arr = Value::Array(colors.into_iter().map(Value::String).collect());
            result.insert(path.clone(), arr.clone());
            if mtime > 0 {
                let mut entry = Map::new();
                entry.insert("v".to_owned(), json!(CACHE_VERSION));
                entry.insert("mtime".to_owned(), json!(mtime));
                entry.insert("scheme".to_owned(), json!(scheme_opt));
                entry.insert("invert".to_owned(), json!(invert_hue_opt));
                entry.insert("colors".to_owned(), arr);
                if let Some(feat) = features {
                    entry.insert("feat".to_owned(), feat.to_json_value());
                }
                cache.insert(path, Value::Object(entry));
                cache_dirty = true;
            }
        }
    }

    if cache_dirty {
        save_cache(cpath, &cache);
    }

    result
}

pub fn run_color_tags(raw_args: &[String]) -> Result<()> {
    let args: Vec<String> = raw_args
        .iter()
        .map(|s| s.trim().to_owned())
        .filter(|s| !s.is_empty())
        .collect();

    let paths = if args.first().map(String::as_str) == Some("--roots") {
        collect_from_roots(&args[1..])
    } else if !args.is_empty() {
        args
    } else if !io::stdin().is_terminal() {
        let mut input = String::new();
        let _ = io::stdin().read_to_string(&mut input);
        input
            .lines()
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(str::to_owned)
            .collect()
    } else {
        Vec::new()
    };

    let cpath = cache_path();
    let thumbs = thumb_root();
    let scheme_opt = configured_scheme_option();
    let invert_hue_opt = configured_invert_hue();
    let result = compute_color_tags_with_paths(paths, &thumbs, &cpath, &scheme_opt, invert_hue_opt);

    println!("{}", serde_json::to_string(&Value::Object(result))?);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::{ImageBuffer, Rgb};
    use std::time::{SystemTime, UNIX_EPOCH};

    fn write_solid_png(path: &Path, rgb: [u8; 3]) {
        let img: ImageBuffer<Rgb<u8>, Vec<u8>> = ImageBuffer::from_pixel(64, 64, Rgb(rgb));
        img.save(path).expect("write solid test png");
    }

    fn temp_dir(label: &str) -> PathBuf {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        let dir = std::env::temp_dir().join(format!(
            "alis-colortags-{label}-{}-{nonce}",
            std::process::id()
        ));
        fs::create_dir_all(&dir).expect("create temp test dir");
        dir
    }

    #[test]
    fn md5_matches_rfc1321_vectors() {
        assert_eq!(md5_hex(b""), "d41d8cd98f00b204e9800998ecf8427e");
        assert_eq!(md5_hex(b"abc"), "900150983cd24fb0d6963f7d28e17f72");
        assert_eq!(
            md5_hex(b"message digest"),
            "f96b697d7cb7938d525a2f31aaf161d0"
        );
        assert_eq!(
            md5_hex(b"file:///home/user/Wallpapers/test%20image.png"),
            "870fce2678647e575ccc3577edf83989"
        );
    }

    #[test]
    fn bucket_classification_matches_python_contract() {
        assert_eq!(hue_to_bucket(0.0, 0.8, 0.8), "red");
        assert_eq!(hue_to_bucket(350.0, 0.8, 0.8), "red");
        assert_eq!(hue_to_bucket(25.0, 0.8, 0.8), "orange");
        assert_eq!(hue_to_bucket(55.0, 0.8, 0.8), "yellow");
        assert_eq!(hue_to_bucket(120.0, 0.8, 0.8), "green");
        assert_eq!(hue_to_bucket(180.0, 0.8, 0.8), "cyan");
        assert_eq!(hue_to_bucket(220.0, 0.8, 0.8), "blue");
        assert_eq!(hue_to_bucket(275.0, 0.8, 0.8), "purple");
        assert_eq!(hue_to_bucket(320.0, 0.8, 0.8), "pink");
        assert_eq!(hue_to_bucket(120.0, 0.05, 0.8), "monochrome");
    }

    #[test]
    fn solid_swatches_and_grayscale_match_auto_theming() {
        let dir = temp_dir("swatches");
        let thumbs = dir.join("thumbs");
        fs::create_dir_all(&thumbs).unwrap();

        let swatches = [
            ("red", [0xef, 0x44, 0x44]),
            ("orange", [0xf9, 0x73, 0x16]),
            ("yellow", [0xea, 0xb3, 0x08]),
            ("green", [0x22, 0xc5, 0x5e]),
            ("cyan", [0x06, 0xb6, 0xd4]),
            ("blue", [0x3b, 0x82, 0xf6]),
            ("purple", [0xa8, 0x55, 0xf7]),
            ("pink", [0xec, 0x48, 0x99]),
            ("monochrome", [0x7a, 0x7a, 0x7a]),
        ];

        for scheme in ["auto", "scheme-tonal-spot"] {
            for (expected, rgb) in swatches {
                let file = dir.join(format!("{expected}.png"));
                write_solid_png(&file, rgb);
                let tags = analyze_image(&file.to_string_lossy(), &thumbs, scheme, false);
                assert_eq!(
                    tags,
                    vec![expected.to_owned()],
                    "swatch {expected} mismatched under {scheme}: {tags:?}"
                );
            }
        }

        // Pure grayscale / faint sepia must never leak Material Score's #4285F4 blue fallback
        let bw = dir.join("bw.png");
        let mut bw_img: ImageBuffer<Rgb<u8>, Vec<u8>> = ImageBuffer::new(64, 64);
        for (x, y, px) in bw_img.enumerate_pixels_mut() {
            let luma = if (x + y) % 2 == 0 { 28 } else { 224 };
            *px = Rgb([luma, luma, luma]);
        }
        bw_img.save(&bw).unwrap();
        for scheme in ["auto", "scheme-tonal-spot"] {
            assert_eq!(
                analyze_image(&bw.to_string_lossy(), &thumbs, scheme, false),
                vec!["monochrome".to_owned()]
            );
        }

        // Mixed 56% muted slate-blue sky + 44% vivid orange sun ->
        // area majority is blue, while Material Score picks vivid orange;
        // only "orange" (the Auto-Theming color) may be emitted!
        let mixed = dir.join("mixed_navy_orange.png");
        let mut mixed_img: ImageBuffer<Rgb<u8>, Vec<u8>> = ImageBuffer::new(64, 64);
        for (_, y, px) in mixed_img.enumerate_pixels_mut() {
            *px = if y < 18 {
                Rgb([46, 56, 76])
            } else if y < 36 {
                Rgb([34, 48, 72])
            } else {
                Rgb([255, 118, 12])
            };
        }
        mixed_img.save(&mixed).unwrap();
        let mixed_tags =
            analyze_image(&mixed.to_string_lossy(), &thumbs, "scheme-tonal-spot", false);
        assert_eq!(mixed_tags, vec!["orange".to_owned()]);

        // Inverted hue on solid red yields cyan theme; since cyan is absent from
        // the solid red image, neither red nor cyan passes BOTH criteria.
        let red_path = dir.join("red.png");
        let inverted_tags =
            analyze_image(&red_path.to_string_lossy(), &thumbs, "scheme-tonal-spot", true);
        assert!(
            inverted_tags.is_empty(),
            "absent rotated theme hue must not tag image: {inverted_tags:?}"
        );

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn v1_cache_entries_auto_migrate_to_v2() {
        let dir = temp_dir("cache-v2");
        let thumbs = dir.join("thumbs");
        let cache_file = dir.join("wallpaper-color-tags.json");
        let img_path = dir.join("sample.png");
        let unrelated_path = dir.join("unrelated.png");
        write_solid_png(&img_path, [0x22, 0xc5, 0x5e]);
        let mtime = fs::metadata(&img_path).unwrap().mtime();

        // Pre-populate legacy v1 entry lacking `v: 2` plus an unrelated entry
        let initial_cache = json!({
            img_path.to_string_lossy().to_string(): {
                "mtime": mtime,
                "colors": ["blue", "red"]
            },
            unrelated_path.to_string_lossy().to_string(): {
                "mtime": 123456,
                "colors": ["purple"]
            }
        });
        fs::write(&cache_file, serde_json::to_vec(&initial_cache).unwrap()).unwrap();

        let first = compute_color_tags_with_paths(
            vec![img_path.to_string_lossy().into_owned()],
            &thumbs,
            &cache_file,
            "scheme-tonal-spot",
            false,
        );
        assert_eq!(
            first.get(&*img_path.to_string_lossy()),
            Some(&json!(["green"]))
        );

        let saved = load_cache(&cache_file);
        assert_eq!(
            saved
                .get(&*img_path.to_string_lossy())
                .and_then(|v| v.get("v"))
                .and_then(Value::as_i64),
            Some(CACHE_VERSION)
        );
        assert_eq!(
            saved
                .get(&*unrelated_path.to_string_lossy())
                .and_then(|v| v.get("colors")),
            Some(&json!(["purple"]))
        );

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn v2_cache_entry_remains_instant_hit_for_matching_scheme() {
        let dir = temp_dir("cache-v2-compat");
        let thumbs = dir.join("thumbs");
        let cache_file = dir.join("wallpaper-color-tags.json");
        let img_path = dir.join("sample.png");
        write_solid_png(&img_path, [0x3b, 0x82, 0xf6]);
        let mtime = fs::metadata(&img_path).unwrap().mtime();

        let initial_cache = json!({
            img_path.to_string_lossy().to_string(): {
                "v": 2,
                "mtime": mtime,
                "scheme": "scheme-tonal-spot",
                "invert": false,
                "colors": ["blue"]
            }
        });
        fs::write(&cache_file, serde_json::to_vec(&initial_cache).unwrap()).unwrap();

        let out = compute_color_tags_with_paths(
            vec![img_path.to_string_lossy().into_owned()],
            &thumbs,
            &cache_file,
            "scheme-tonal-spot",
            false,
        );
        assert_eq!(out.get(&*img_path.to_string_lossy()), Some(&json!(["blue"])));

        let saved = load_cache(&cache_file);
        assert_eq!(
            saved.get(&*img_path.to_string_lossy()).and_then(|v| v.get("v")).and_then(Value::as_i64),
            Some(2)
        );
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn v3_cache_switches_scheme_without_redecoding() {
        let dir = temp_dir("cache-v3-switch");
        let thumbs = dir.join("thumbs");
        let cache_file = dir.join("wallpaper-color-tags.json");
        let img_path = dir.join("sample.png");
        write_solid_png(&img_path, [0x22, 0xc5, 0x5e]);

        let first = compute_color_tags_with_paths(
            vec![img_path.to_string_lossy().into_owned()],
            &thumbs,
            &cache_file,
            "scheme-tonal-spot",
            false,
        );
        assert_eq!(first.get(&*img_path.to_string_lossy()), Some(&json!(["green"])));

        // Corrupt image bytes on disk while preserving mtime: v3 scheme switch
        // must succeed from cached visual features without decoding the file.
        let orig_meta = fs::metadata(&img_path).unwrap();
        let mtime_val = orig_meta.mtime();
        fs::write(&img_path, b"not-a-valid-image").unwrap();
        let mut cache = load_cache(&cache_file);
        let new_mtime = fs::metadata(&img_path).unwrap().mtime();
        if new_mtime != mtime_val {
            cache
                .get_mut(&*img_path.to_string_lossy())
                .and_then(Value::as_object_mut)
                .unwrap()
                .insert("mtime".to_owned(), json!(new_mtime));
            save_cache(&cache_file, &cache);
        }

        let mono = compute_color_tags_with_paths(
            vec![img_path.to_string_lossy().into_owned()],
            &thumbs,
            &cache_file,
            "scheme-monochrome",
            false,
        );
        assert_eq!(
            mono.get(&*img_path.to_string_lossy()),
            Some(&json!(["monochrome"]))
        );

        let expr = compute_color_tags_with_paths(
            vec![img_path.to_string_lossy().into_owned()],
            &thumbs,
            &cache_file,
            "scheme-expressive",
            false,
        );
        assert_eq!(
            expr.get(&*img_path.to_string_lossy()),
            Some(&json!(["green"]))
        );

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn collect_from_roots_follows_symlinks_without_looping() {
        let dir = temp_dir("symlinks");
        let real_dir = dir.join("real");
        let sub_dir = real_dir.join("sub");
        let root_dir = dir.join("root");
        fs::create_dir_all(&sub_dir).unwrap();
        fs::create_dir_all(&root_dir).unwrap();

        let target_img = sub_dir.join("linked.png");
        write_solid_png(&target_img, [0xef, 0x44, 0x44]);

        #[cfg(unix)]
        {
            std::os::unix::fs::symlink(&target_img, root_dir.join("img_link.png")).unwrap();
            std::os::unix::fs::symlink(&sub_dir, root_dir.join("dir_link")).unwrap();
            std::os::unix::fs::symlink(&root_dir, sub_dir.join("loop_back")).unwrap();
        }

        let files = collect_from_roots(&[format!("{}/", root_dir.to_string_lossy())]);
        assert!(files.iter().any(|p| p.ends_with("/img_link.png")));
        assert!(files.iter().any(|p| p.ends_with("/dir_link/linked.png")));
        assert!(!files.iter().any(|p| p.contains("//")));

        let _ = fs::remove_dir_all(&dir);
    }
}
