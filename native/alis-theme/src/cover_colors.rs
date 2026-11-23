use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result, anyhow, bail};
use image::ImageReader;
use image::imageops::FilterType;

fn rgb_to_hsv(r: f64, g: f64, b: f64) -> (f64, f64, f64) {
    let max = r.max(g).max(b);
    let min = r.min(g).min(b);
    let delta = max - min;
    let h = if delta <= 1e-9 {
        0.0
    } else if (max - r).abs() <= 1e-9 {
        ((g - b) / delta).rem_euclid(6.0) / 6.0
    } else if (max - g).abs() <= 1e-9 {
        ((b - r) / delta + 2.0) / 6.0
    } else {
        ((r - g) / delta + 4.0) / 6.0
    };
    let s = if max <= 1e-9 { 0.0 } else { delta / max };
    (h, s, max)
}

fn hsv_to_rgb(h: f64, s: f64, v: f64) -> (u8, u8, u8) {
    if s <= 1e-9 {
        let c = (v.clamp(0.0, 1.0) * 255.0) as u8;
        return (c, c, c);
    }
    let hh = (h.rem_euclid(1.0)) * 6.0;
    let i = hh.floor() as i32;
    let f = hh - (i as f64);
    let p = v * (1.0 - s);
    let q = v * (1.0 - s * f);
    let t = v * (1.0 - s * (1.0 - f));
    let (r, g, b) = match i % 6 {
        0 => (v, t, p),
        1 => (q, v, p),
        2 => (p, v, t),
        3 => (p, q, v),
        4 => (t, p, v),
        _ => (v, p, q),
    };
    (
        (r.clamp(0.0, 1.0) * 255.0) as u8,
        (g.clamp(0.0, 1.0) * 255.0) as u8,
        (b.clamp(0.0, 1.0) * 255.0) as u8,
    )
}

fn saturate(rgb: (u8, u8, u8), factor: f64) -> (u8, u8, u8) {
    let (h, s, v) = rgb_to_hsv(rgb.0 as f64 / 255.0, rgb.1 as f64 / 255.0, rgb.2 as f64 / 255.0);
    hsv_to_rgb(h, (s * factor).min(1.0), (v * 1.08).min(1.0))
}

fn brightness(rgb: (u8, u8, u8)) -> f64 {
    (rgb.0 as f64 * 299.0 + rgb.1 as f64 * 587.0 + rgb.2 as f64 * 114.0) / 1000.0
}

fn hex(rgb: (u8, u8, u8)) -> String {
    format!("#{:02x}{:02x}{:02x}", rgb.0, rgb.1, rgb.2)
}

pub fn extract_cover_colors(image_path: &Path, count: usize) -> Result<Vec<String>> {
    let img = ImageReader::open(image_path)
        .with_context(|| format!("open cover image {}", image_path.display()))?
        .with_guessed_format()
        .with_context(|| format!("guess cover image format {}", image_path.display()))?
        .decode()
        .with_context(|| format!("decode cover image {}", image_path.display()))?
        .resize_exact(150, 150, FilterType::Triangle)
        .to_rgb8();

    // 5-bit per channel color histogram quantization + bucket averaging.
    type QuantKey = (u8, u8, u8);
    type BucketAccum = (u64, u64, u64, u64);
    let mut buckets: HashMap<QuantKey, BucketAccum> = HashMap::new();
    for px in img.pixels() {
        let key = (px[0] >> 3, px[1] >> 3, px[2] >> 3);
        let entry = buckets.entry(key).or_insert((0, 0, 0, 0));
        entry.0 += px[0] as u64;
        entry.1 += px[1] as u64;
        entry.2 += px[2] as u64;
        entry.3 += 1;
    }

    let mut ranked: Vec<((u8, u8, u8), u64)> = buckets
        .into_values()
        .map(|(sr, sg, sb, n)| (((sr / n) as u8, (sg / n) as u8, (sb / n) as u8), n))
        .collect();
    ranked.sort_by_key(|b| std::cmp::Reverse(b.1));

    for (min_b, max_b) in [(20.0, 240.0), (10.0, 250.0), (0.0, 255.0)] {
        let mut selected: Vec<(u8, u8, u8)> = Vec::new();
        let mut seen = HashSet::new();
        let mut out = Vec::new();
        for &(rgb, _) in &ranked {
            let bness = brightness(rgb);
            if bness < min_b || bness > max_b {
                continue;
            }
            let too_close = selected.iter().any(|&(pr, pg, pb)| {
                let dr = pr as i32 - rgb.0 as i32;
                let dg = pg as i32 - rgb.1 as i32;
                let db = pb as i32 - rgb.2 as i32;
                dr * dr + dg * dg + db * db < 32 * 32
            });
            if too_close && selected.len() < count {
                continue;
            }
            let sat = saturate(rgb, 1.35);
            let h = hex(sat);
            if seen.insert(h.clone()) {
                selected.push(rgb);
                out.push(h);
                if out.len() >= count {
                    break;
                }
            }
        }
        if out.len() >= count.min(2) {
            return Ok(out);
        }
    }
    Ok(ranked
        .into_iter()
        .take(count)
        .map(|(rgb, _)| hex(saturate(rgb, 1.35)))
        .collect())
}

pub fn run_cover_colors(raw_args: &[String]) -> Result<()> {
    let image_path = PathBuf::from(
        raw_args
            .first()
            .ok_or_else(|| anyhow!("usage: --cover-colors <image_path> [count] [output_path]"))?,
    );
    let count = raw_args
        .get(1)
        .and_then(|v| v.parse::<usize>().ok())
        .unwrap_or(8)
        .clamp(1, 8);
    let output_path = raw_args.get(2).map(PathBuf::from).unwrap_or_else(|| {
        let state = std::env::var_os("XDG_STATE_HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| {
                std::env::var_os("HOME")
                    .map(PathBuf::from)
                    .unwrap_or_else(|| PathBuf::from("/"))
                    .join(".local/state")
            });
        state.join("quickshell/user/generated/cover-colors.json")
    });

    if !image_path.is_file() {
        bail!("Image not found: {}", image_path.display());
    }
    let colors = extract_cover_colors(&image_path, count)?;
    if colors.is_empty() {
        bail!("Not enough distinct colors found");
    }
    if let Some(parent) = output_path.parent().filter(|p| !p.as_os_str().is_empty()) {
        fs::create_dir_all(parent)?;
    }
    let serialized = serde_json::to_string(&colors)?;
    fs::write(&output_path, &serialized)?;
    println!("{serialized}");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::extract_cover_colors;
    use image::{Rgb, RgbImage};

    #[test]
    fn extracts_dominant_cover_colors() {
        let mut img = RgbImage::new(64, 64);
        for y in 0..64 {
            for x in 0..64 {
                img.put_pixel(x, y, if x < 32 { Rgb([210, 60, 40]) } else { Rgb([40, 120, 210]) });
            }
        }
        let path = std::env::temp_dir().join(format!("alis-cover-test-{}.png", std::process::id()));
        img.save(&path).unwrap();
        let colors = extract_cover_colors(&path, 4).unwrap();
        let _ = std::fs::remove_file(&path);
        assert!(colors.len() >= 2);
        assert!(colors.iter().all(|c| c.starts_with('#') && c.len() == 7));
    }
}
