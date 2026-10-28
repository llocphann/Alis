use std::collections::{HashMap, HashSet};
use std::fs;
use std::io::{self, IsTerminal, Read};
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use anyhow::Result;
use image::imageops::FilterType;
use serde_json::{Map, Value, json};

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
    for size_dir in ["normal", "large", "x-large"] {
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

fn hue_to_bucket(h_deg: f64, s: f64, v: f64) -> &'static str {
    if v < 0.10 || s < 0.14 {
        return "monochrome";
    }
    if !(14.0..345.0).contains(&h_deg) {
        return "red";
    }
    if h_deg < 42.0 {
        return "orange";
    }
    if h_deg < 68.0 {
        return "yellow";
    }
    if h_deg < 162.0 {
        return "green";
    }
    if h_deg < 200.0 {
        return "cyan";
    }
    if h_deg < 255.0 {
        return "blue";
    }
    if h_deg < 295.0 {
        return "purple";
    }
    "pink"
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

fn analyze_image(path: &str, thumbs: &Path) -> Vec<String> {
    let source_path = find_existing_thumbnail(path, thumbs);
    let Ok(img) = image::open(&source_path) else {
        return classify_filename_fallback(path);
    };
    let small = img.to_rgb8();
    let resized = image::imageops::resize(&small, 16, 16, FilterType::Triangle);
    let raw = resized.as_raw();
    if raw.is_empty() {
        return Vec::new();
    }

    let mut counts: HashMap<&'static str, f64> =
        BUCKET_ORDER.iter().map(|&b| (b, 0.0)).collect();
    let mut chromatic_weight = 0.0;
    let mut total_weight = 0.0;

    for pixel in raw.chunks_exact(3) {
        let rf = pixel[0] as f64 / 255.0;
        let gf = pixel[1] as f64 / 255.0;
        let bf = pixel[2] as f64 / 255.0;
        let (h, s, v) = rgb_to_hsv(rf, gf, bf);
        let h_deg = h * 360.0;
        total_weight += 1.0;
        if v < 0.10 || s < 0.14 {
            *counts.get_mut("monochrome").unwrap() += 1.0;
            continue;
        }
        let bucket = hue_to_bucket(h_deg, s, v);
        let weight = (0.5 + 0.5 * s) * (0.4 + 0.6 * (v * 1.25).min(1.0));
        *counts.get_mut(bucket).unwrap() += weight;
        chromatic_weight += weight;
    }

    if total_weight <= 0.0 {
        return Vec::new();
    }

    let mono_ratio = counts["monochrome"] / total_weight;
    if chromatic_weight <= 0.01 || mono_ratio >= 0.78 {
        return vec!["monochrome".to_owned()];
    }

    let mut chromatic_buckets: Vec<(&'static str, f64)> = BUCKET_ORDER
        .iter()
        .copied()
        .filter(|&b| b != "monochrome" && counts[b] > 0.0)
        .map(|b| (b, counts[b] / chromatic_weight))
        .collect();
    chromatic_buckets.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));

    let mut tags: Vec<String> = Vec::new();
    if let Some(&(first, _)) = chromatic_buckets.first() {
        tags.push(first.to_owned());
        for &(bucket, share) in chromatic_buckets.iter().skip(1).take(2) {
            if share >= 0.22 {
                tags.push(bucket.to_owned());
            }
        }
    }
    if mono_ratio >= 0.58 && !tags.iter().any(|t| t == "monochrome") {
        tags.push("monochrome".to_owned());
    }
    tags
}

fn expand_tilde(raw: &str) -> PathBuf {
    if let Some(rest) = raw.strip_prefix("~/")
        && let Some(home) = std::env::var_os("HOME")
    {
        return PathBuf::from(home).join(rest);
    }
    PathBuf::from(raw)
}

fn walk_dir_images(dir: &Path, seen: &mut HashSet<String>, found: &mut Vec<String>) {
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    let mut subdirs = Vec::new();
    for entry in entries.flatten() {
        let path = entry.path();
        let Ok(ft) = entry.file_type() else {
            continue;
        };
        if ft.is_dir() {
            subdirs.push(path);
        } else if ft.is_file()
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
        walk_dir_images(&sub, seen, found);
    }
}

fn collect_from_roots(roots: &[String]) -> Vec<String> {
    let mut found = Vec::new();
    let mut seen = HashSet::new();
    for root in roots {
        let root_path = expand_tilde(root);
        if root_path.is_dir() {
            walk_dir_images(&root_path, &mut seen, &mut found);
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
    let mut cache = load_cache(&cpath);
    let mut result = Map::new();
    let mut to_compute: Vec<(String, i64)> = Vec::new();

    for path in paths {
        let mtime = fs::metadata(&path).map(|m| m.mtime()).unwrap_or(0);
        if let Some(Value::Object(cached)) = cache.get(&path)
            && cached.get("mtime").and_then(Value::as_i64) == Some(mtime)
            && let Some(Value::Array(colors)) = cached.get("colors")
        {
            result.insert(path, Value::Array(colors.clone()));
        } else {
            to_compute.push((path, mtime));
        }
    }

    if !to_compute.is_empty() {
        let thumbs = thumb_root();
        let workers = to_compute.len().clamp(1, 8);
        let chunk_size = to_compute.len().div_ceil(workers);
        let computed: Mutex<Vec<(String, i64, Vec<String>)>> =
            Mutex::new(Vec::with_capacity(to_compute.len()));

        std::thread::scope(|scope| {
            for chunk in to_compute.chunks(chunk_size) {
                let thumbs = &thumbs;
                let computed = &computed;
                scope.spawn(move || {
                    let mut local = Vec::with_capacity(chunk.len());
                    for (path, mtime) in chunk {
                        let tags = analyze_image(path, thumbs);
                        local.push((path.clone(), *mtime, tags));
                    }
                    if let Ok(mut guard) = computed.lock() {
                        guard.extend(local);
                    }
                });
            }
        });

        for (path, mtime, colors) in computed.into_inner().unwrap_or_default() {
            let arr = Value::Array(colors.into_iter().map(Value::String).collect());
            result.insert(path.clone(), arr.clone());
            if mtime > 0 {
                cache.insert(path, json!({"mtime": mtime, "colors": arr}));
            }
        }
        save_cache(&cpath, &cache);
    }

    println!("{}", serde_json::to_string(&Value::Object(result))?);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

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
}
