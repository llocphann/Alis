use std::path::{Path, PathBuf};

use anyhow::{Context, Result, anyhow};
use image::imageops::FilterType;
use image::{DynamicImage, GenericImageView, GrayImage, RgbImage};
use serde_json::json;

#[derive(Debug, Clone)]
pub struct RegionArgs {
    pub image_path: PathBuf,
    pub width: i32,
    pub height: i32,
    pub visual_output: bool,
    pub screen_width: Option<i32>,
    pub screen_height: Option<i32>,
    pub stride: i32,
    pub screen_mode: String,
    pub verbose: bool,
    pub largest_region: bool,
    pub variance_threshold: f64,
    pub aspect_ratio: f64,
    pub horizontal_padding: i32,
    pub vertical_padding: i32,
    pub busiest: bool,
    pub color_only: bool,
    pub position_x: i32,
    pub position_y: i32,
}

impl Default for RegionArgs {
    fn default() -> Self {
        Self {
            image_path: PathBuf::new(),
            width: 300,
            height: 200,
            visual_output: false,
            screen_width: Some(1920),
            screen_height: Some(1080),
            stride: 10,
            screen_mode: "fill".into(),
            verbose: false,
            largest_region: false,
            variance_threshold: 1000.0,
            aspect_ratio: 1.78,
            horizontal_padding: 50,
            vertical_padding: 50,
            busiest: false,
            color_only: false,
            position_x: 0,
            position_y: 0,
        }
    }
}

pub fn parse_region_args(raw_args: &[String]) -> Result<RegionArgs> {
    let mut args = RegionArgs::default();
    let mut positional: Option<PathBuf> = None;
    let mut i = 0;
    while i < raw_args.len() {
        let arg = &raw_args[i];
        match arg.as_str() {
            "--least-busy-region" => {}
            "--width" => {
                i += 1;
                args.width = raw_args
                    .get(i)
                    .ok_or_else(|| anyhow!("missing --width value"))?
                    .parse()?;
            }
            "--height" => {
                i += 1;
                args.height = raw_args
                    .get(i)
                    .ok_or_else(|| anyhow!("missing --height value"))?
                    .parse()?;
            }
            "-v" | "--visual-output" => args.visual_output = true,
            "--screen-width" => {
                i += 1;
                args.screen_width = Some(
                    raw_args
                        .get(i)
                        .ok_or_else(|| anyhow!("missing --screen-width value"))?
                        .parse()?,
                );
            }
            "--screen-height" => {
                i += 1;
                args.screen_height = Some(
                    raw_args
                        .get(i)
                        .ok_or_else(|| anyhow!("missing --screen-height value"))?
                        .parse()?,
                );
            }
            "--stride" => {
                i += 1;
                args.stride = raw_args
                    .get(i)
                    .ok_or_else(|| anyhow!("missing --stride value"))?
                    .parse()?;
            }
            "--screen-mode" => {
                i += 1;
                args.screen_mode = raw_args
                    .get(i)
                    .ok_or_else(|| anyhow!("missing --screen-mode value"))?
                    .clone();
            }
            "--verbose" => args.verbose = true,
            "-l" | "--largest-region" => args.largest_region = true,
            "-t" | "--variance-threshold" => {
                i += 1;
                args.variance_threshold = raw_args
                    .get(i)
                    .ok_or_else(|| anyhow!("missing --variance-threshold value"))?
                    .parse()?;
            }
            "--aspect-ratio" => {
                i += 1;
                args.aspect_ratio = raw_args
                    .get(i)
                    .ok_or_else(|| anyhow!("missing --aspect-ratio value"))?
                    .parse()?;
            }
            "-hp" | "--horizontal-padding" => {
                i += 1;
                args.horizontal_padding = raw_args
                    .get(i)
                    .ok_or_else(|| anyhow!("missing --horizontal-padding value"))?
                    .parse()?;
            }
            "-vp" | "--vertical-padding" => {
                i += 1;
                args.vertical_padding = raw_args
                    .get(i)
                    .ok_or_else(|| anyhow!("missing --vertical-padding value"))?
                    .parse()?;
            }
            "--busiest" => args.busiest = true,
            "--color-only" => args.color_only = true,
            "--position-x" => {
                i += 1;
                args.position_x = raw_args
                    .get(i)
                    .ok_or_else(|| anyhow!("missing --position-x value"))?
                    .parse()?;
            }
            "--position-y" => {
                i += 1;
                args.position_y = raw_args
                    .get(i)
                    .ok_or_else(|| anyhow!("missing --position-y value"))?
                    .parse()?;
            }
            other if !other.starts_with('-') && positional.is_none() => {
                positional = Some(PathBuf::from(other));
            }
            other => return Err(anyhow!("unknown region argument: {other}")),
        }
        i += 1;
    }
    args.image_path = positional.ok_or_else(|| anyhow!("missing image_path"))?;
    Ok(args)
}

fn load_and_scale(
    path: &Path,
    screen_width: Option<i32>,
    screen_height: Option<i32>,
    screen_mode: &str,
) -> Result<DynamicImage> {
    let mut img =
        image::open(path).with_context(|| format!("Image not found: {}", path.display()))?;
    if let (Some(sw), Some(sh)) = (screen_width, screen_height)
        && sw > 0
        && sh > 0
    {
        let (orig_w, orig_h) = img.dimensions();
        let scale_w = f64::from(sw) / f64::from(orig_w.max(1));
        let scale_h = f64::from(sh) / f64::from(orig_h.max(1));
        let scale = if screen_mode == "fill" {
            scale_w.max(scale_h)
        } else {
            scale_w.min(scale_h)
        };
        let new_w = ((f64::from(orig_w) * scale) as u32).max(1);
        let new_h = ((f64::from(orig_h) * scale) as u32).max(1);
        if new_w != orig_w || new_h != orig_h {
            img = img.resize_exact(new_w, new_h, FilterType::Triangle);
        }
        let target_w = sw as u32;
        let target_h = sh as u32;
        let (cur_w, cur_h) = img.dimensions();
        if cur_w != target_w || cur_h != target_h {
            let x1 = cur_w.saturating_sub(target_w) / 2;
            let y1 = cur_h.saturating_sub(target_h) / 2;
            let crop_w = target_w.min(cur_w.saturating_sub(x1)).max(1);
            let crop_h = target_h.min(cur_h.saturating_sub(y1)).max(1);
            img = img.crop_imm(x1, y1, crop_w, crop_h);
        }
    }
    Ok(img)
}

struct IntegralTables {
    width: usize,
    height: usize,
    sum: Vec<f64>,
    sum_sq: Vec<f64>,
}

impl IntegralTables {
    fn from_gray(gray: &GrayImage) -> Self {
        let width = gray.width() as usize;
        let height = gray.height() as usize;
        let mut sum = vec![0.0_f64; width * height];
        let mut sum_sq = vec![0.0_f64; width * height];
        let raw = gray.as_raw();
        for y in 0..height {
            let mut row_s = 0.0_f64;
            let mut row_s2 = 0.0_f64;
            for x in 0..width {
                let v = f64::from(raw[y * width + x]);
                row_s += v;
                row_s2 += v * v;
                let above_s = if y > 0 { sum[(y - 1) * width + x] } else { 0.0 };
                let above_s2 = if y > 0 {
                    sum_sq[(y - 1) * width + x]
                } else {
                    0.0
                };
                sum[y * width + x] = above_s + row_s;
                sum_sq[y * width + x] = above_s2 + row_s2;
            }
        }
        Self {
            width,
            height,
            sum,
            sum_sq,
        }
    }

    #[inline]
    fn query(table: &[f64], width: usize, x1: usize, y1: usize, x2: usize, y2: usize) -> f64 {
        let mut total = table[y2 * width + x2];
        if x1 > 0 {
            total -= table[y2 * width + (x1 - 1)];
        }
        if y1 > 0 {
            total -= table[(y1 - 1) * width + x2];
        }
        if x1 > 0 && y1 > 0 {
            total += table[(y1 - 1) * width + (x1 - 1)];
        }
        total
    }

    #[inline]
    fn region_variance(&self, x1: usize, y1: usize, x2: usize, y2: usize, area: f64) -> f64 {
        let s = Self::query(&self.sum, self.width, x1, y1, x2, y2);
        let s2 = Self::query(&self.sum_sq, self.width, x1, y1, x2, y2);
        let mean = s / area;
        (s2 / area) - (mean * mean)
    }
}

fn region_brightness(gray: &GrayImage, x: i32, y: i32, w: i32, h: i32) -> (f64, f64) {
    let img_w = gray.width() as i32;
    let img_h = gray.height() as i32;
    if img_w <= 0 || img_h <= 0 {
        return (128.0, 0.0);
    }
    let x0 = x.max(0).min(img_w - 1) as u32;
    let y0 = y.max(0).min(img_h - 1) as u32;
    let rw = w.max(1).min(img_w - x0 as i32) as u32;
    let rh = h.max(1).min(img_h - y0 as i32) as u32;
    if rw == 0 || rh == 0 {
        return (128.0, 0.0);
    }
    let count = f64::from(rw) * f64::from(rh);
    let mut sum = 0.0_f64;
    let mut sum_sq = 0.0_f64;
    for py in y0..(y0 + rh) {
        for px in x0..(x0 + rw) {
            let v = f64::from(gray.get_pixel(px, py).0[0]);
            sum += v;
            sum_sq += v * v;
        }
    }
    let mean = sum / count;
    let var = (sum_sq / count - mean * mean).max(0.0);
    (mean, var.sqrt())
}

fn dominant_color_hex(rgb: &RgbImage, x: i32, y: i32, w: i32, h: i32) -> String {
    let img_w = rgb.width() as i32;
    let img_h = rgb.height() as i32;
    if img_w <= 0 || img_h <= 0 {
        return "#000000".into();
    }
    let x0 = x.max(0).min(img_w - 1) as u32;
    let y0 = y.max(0).min(img_h - 1) as u32;
    let rw = w.max(1).min(img_w - x0 as i32) as u32;
    let rh = h.max(1).min(img_h - y0 as i32) as u32;
    let total_pixels = (rw as usize) * (rh as usize);
    if total_pixels == 0 {
        return "#000000".into();
    }

    // Subsample large regions deterministically for K=3 clustering so even 4K regions finish in <1ms.
    let step = ((total_pixels / 4096) as u32).max(1);
    let mut samples: Vec<[f32; 3]> = Vec::with_capacity(4096);
    let mut idx = 0u32;
    for py in y0..(y0 + rh) {
        for px in x0..(x0 + rw) {
            if idx.is_multiple_of(step) {
                let p = rgb.get_pixel(px, py).0;
                samples.push([f32::from(p[0]), f32::from(p[1]), f32::from(p[2])]);
            }
            idx += 1;
        }
    }

    if samples.len() < 3 {
        let mut r = 0.0_f32;
        let mut g = 0.0_f32;
        let mut b = 0.0_f32;
        let n = samples.len().max(1) as f32;
        for s in &samples {
            r += s[0];
            g += s[1];
            b += s[2];
        }
        return format!(
            "#{:02x}{:02x}{:02x}",
            (r / n) as u8,
            (g / n) as u8,
            (b / n) as u8
        );
    }

    // Deterministic K=3 k-means (10 iterations), seeded at 0%, 50%, and 100% of the sample slice.
    let mut centers = [
        samples[0],
        samples[samples.len() / 2],
        samples[samples.len() - 1],
    ];
    let mut counts = [0usize; 3];

    for _ in 0..10 {
        let mut sums = [[0.0_f32; 3]; 3];
        counts = [0; 3];
        for s in &samples {
            let mut best_k = 0;
            let mut best_dist = f32::MAX;
            for (k, center) in centers.iter().enumerate() {
                let dr = s[0] - center[0];
                let dg = s[1] - center[1];
                let db = s[2] - center[2];
                let dist = dr * dr + dg * dg + db * db;
                if dist < best_dist {
                    best_dist = dist;
                    best_k = k;
                }
            }
            counts[best_k] += 1;
            sums[best_k][0] += s[0];
            sums[best_k][1] += s[1];
            sums[best_k][2] += s[2];
        }
        for k in 0..3 {
            if counts[k] > 0 {
                let c = counts[k] as f32;
                centers[k] = [sums[k][0] / c, sums[k][1] / c, sums[k][2] / c];
            }
        }
    }

    let dominant_idx = (0..3).max_by_key(|&k| counts[k]).unwrap_or(0);
    let dom = centers[dominant_idx];
    format!(
        "#{:02x}{:02x}{:02x}",
        dom[0].clamp(0.0, 255.0) as u8,
        dom[1].clamp(0.0, 255.0) as u8,
        dom[2].clamp(0.0, 255.0) as u8
    )
}

fn round1(value: f64) -> f64 {
    (value * 10.0).round() / 10.0
}

pub fn run_region(args: &RegionArgs) -> Result<()> {
    let img = load_and_scale(
        &args.image_path,
        args.screen_width,
        args.screen_height,
        &args.screen_mode,
    )?;
    let gray = img.to_luma8();
    let rgb = img.to_rgb8();

    if args.color_only {
        let dom = dominant_color_hex(&rgb, args.position_x, args.position_y, args.width, args.height);
        let (brightness, brightness_std) =
            region_brightness(&gray, args.position_x, args.position_y, args.width, args.height);
        let out = json!({
            "center_x": args.position_x + args.width / 2,
            "center_y": args.position_y + args.height / 2,
            "width": args.width,
            "height": args.height,
            "dominant_color": dom,
            "brightness": round1(brightness),
            "brightness_std": round1(brightness_std),
        });
        println!("{}", serde_json::to_string(&out)?);
        return Ok(());
    }

    let w = gray.width() as i32;
    let h = gray.height() as i32;
    let stride = args.stride.max(1) as usize;
    let mut hp = args.horizontal_padding;
    let mut vp = args.vertical_padding;
    if hp * 2 >= w || vp * 2 >= h {
        hp = hp.clamp(0, (w - 1) / 2);
        vp = vp.clamp(0, (h - 1) / 2);
    }
    let max_region_w = w - 2 * hp;
    let max_region_h = h - 2 * vp;
    if max_region_w <= 0 || max_region_h <= 0 {
        return Err(anyhow!("Image too small for the specified padding."));
    }

    let tables = IntegralTables::from_gray(&gray);

    if args.largest_region {
        let ar = if args.aspect_ratio == 0.0 {
            1.0
        } else {
            args.aspect_ratio
        };
        let mut min_size = 10_i32;
        let mut max_size = if ar >= 1.0 {
            max_region_h.min((f64::from(max_region_w) / ar) as i32)
        } else {
            max_region_w.min((f64::from(max_region_h) * ar) as i32)
        };
        let mut best: Option<(i32, i32, i32, i32, f64)> = None;
        while min_size <= max_size {
            let mid = (min_size + max_size) / 2;
            let (region_w, region_h) = if ar >= 1.0 {
                ((f64::from(mid) * ar).round() as i32, mid)
            } else {
                (mid, (f64::from(mid) / ar).round() as i32)
            };
            if region_w <= 0 || region_h <= 0 {
                break;
            }
            if region_w > max_region_w || region_h > max_region_h {
                max_size = mid - 1;
                continue;
            }
            let x_start = hp.max(0) as usize;
            let y_start = vp.max(0) as usize;
            let x_end = (w - region_w - hp).max(hp) as usize;
            let y_end = (h - region_h - vp).max(vp) as usize;
            let area = f64::from(region_w) * f64::from(region_h);
            let mut found = false;
            for y in (y_start..=y_end).step_by(stride) {
                for x in (x_start..=x_end).step_by(stride) {
                    let x2 = x + (region_w as usize) - 1;
                    let y2 = y + (region_h as usize) - 1;
                    if x2 >= tables.width || y2 >= tables.height {
                        continue;
                    }
                    let var = tables.region_variance(x, y, x2, y2, area);
                    if var <= args.variance_threshold {
                        found = true;
                        best = Some((x as i32, y as i32, region_w, region_h, var));
                        break;
                    }
                }
                if found {
                    break;
                }
            }
            if found {
                min_size = mid + 1;
            } else {
                max_size = mid - 1;
            }
        }
        if let Some((bx, by, rw, rh, var)) = best {
            let cx = bx + rw / 2;
            let cy = by + rh / 2;
            let x1 = cx - rw / 2;
            let y1 = cy - rh / 2;
            let dom = dominant_color_hex(&rgb, x1, y1, rw, rh);
            let (brightness, brightness_std) = region_brightness(&gray, x1, y1, rw, rh);
            let out = json!({
                "center_x": cx,
                "center_y": cy,
                "width": rw,
                "height": rh,
                "variance": var,
                "dominant_color": dom,
                "brightness": round1(brightness),
                "brightness_std": round1(brightness_std),
            });
            println!("{}", serde_json::to_string(&out)?);
        } else {
            println!("{}", json!({"error": "No region found under the threshold."}));
        }
        return Ok(());
    }

    let region_w = args.width.min(max_region_w).max(1);
    let region_h = args.height.min(max_region_h).max(1);
    let area = f64::from(region_w) * f64::from(region_h);
    let x_start = hp.max(0) as usize;
    let y_start = vp.max(0) as usize;
    let x_end = (w - region_w - hp + 1).max(hp) as usize;
    let y_end = (h - region_h - vp + 1).max(vp) as usize;

    let mut min_var: Option<f64> = None;
    let mut max_var: Option<f64> = None;
    let mut min_coords = (hp, vp);
    let mut max_coords = (hp, vp);

    for y in (y_start..=y_end).step_by(stride) {
        for x in (x_start..=x_end).step_by(stride) {
            let x2 = x + (region_w as usize) - 1;
            let y2 = y + (region_h as usize) - 1;
            if x2 >= tables.width || y2 >= tables.height {
                continue;
            }
            let var = tables.region_variance(x, y, x2, y2, area);
            if min_var.is_none_or(|cur| var < cur) {
                min_var = Some(var);
                min_coords = (x as i32, y as i32);
            }
            if max_var.is_none_or(|cur| var > cur) {
                max_var = Some(var);
                max_coords = (x as i32, y as i32);
            }
        }
    }

    let (coords, variance) = if args.busiest {
        (max_coords, max_var.unwrap_or(0.0))
    } else {
        (min_coords, min_var.unwrap_or(0.0))
    };

    let center_x = coords.0 + args.width / 2;
    let center_y = coords.1 + args.height / 2;
    let dom = dominant_color_hex(&rgb, coords.0, coords.1, args.width, args.height);
    let (brightness, brightness_std) =
        region_brightness(&gray, coords.0, coords.1, args.width, args.height);

    let out = json!({
        "center_x": center_x,
        "center_y": center_y,
        "width": args.width,
        "height": args.height,
        "variance": variance,
        "dominant_color": dom,
        "brightness": round1(brightness),
        "brightness_std": round1(brightness_std),
    });
    println!("{}", serde_json::to_string(&out)?);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::{GrayImage, Luma, Rgb, RgbImage};

    #[test]
    fn integral_table_computes_zero_variance_for_uniform_region() {
        let gray = GrayImage::from_pixel(16, 16, Luma([128]));
        let tables = IntegralTables::from_gray(&gray);
        let var = tables.region_variance(2, 2, 9, 9, 64.0);
        assert!(var.abs() < 1e-6);
    }

    #[test]
    fn dominant_color_returns_exact_hex_for_solid_image() {
        let mut img = RgbImage::new(8, 8);
        for p in img.pixels_mut() {
            *p = Rgb([0x24, 0x68, 0xac]);
        }
        assert_eq!(dominant_color_hex(&img, 0, 0, 8, 8), "#2468ac");
    }
}
