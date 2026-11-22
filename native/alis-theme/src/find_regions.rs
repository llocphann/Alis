use std::collections::HashMap;
use std::path::PathBuf;

use anyhow::{Context, Result, anyhow};
use image::imageops::FilterType;
use image::{ImageReader, Rgb, RgbImage};
use serde_json::json;

#[derive(Debug, Clone)]
struct Rect {
    x: i32,
    y: i32,
    width: i32,
    height: i32,
}

impl Rect {
    fn area(&self) -> i64 {
        (self.width.max(0) as i64) * (self.height.max(0) as i64)
    }
}

fn iou(a: &Rect, b: &Rect) -> f64 {
    let x1 = a.x.max(b.x);
    let y1 = a.y.max(b.y);
    let x2 = (a.x + a.width).min(b.x + b.width);
    let y2 = (a.y + a.height).min(b.y + b.height);
    let iw = (x2 - x1).max(0) as f64;
    let ih = (y2 - y1).max(0) as f64;
    let inter = iw * ih;
    let union = (a.area() + b.area()) as f64 - inter;
    if union > 0.0 { inter / union } else { 0.0 }
}

fn non_max_suppression(mut regions: Vec<Rect>, iou_threshold: f64) -> Vec<Rect> {
    regions.sort_by_key(|b| std::cmp::Reverse(b.area()));
    let mut keep: Vec<Rect> = Vec::new();
    for cand in regions {
        if keep.iter().all(|k| iou(k, &cand) < iou_threshold) {
            keep.push(cand);
        }
    }
    keep
}

struct UnionFind {
    parent: Vec<usize>,
    size: Vec<u32>,
    int_diff: Vec<f32>,
}

impl UnionFind {
    fn new(n: usize) -> Self {
        Self {
            parent: (0..n).collect(),
            size: vec![1; n],
            int_diff: vec![0.0; n],
        }
    }

    fn find(&mut self, mut x: usize) -> usize {
        while self.parent[x] != x {
            self.parent[x] = self.parent[self.parent[x]];
            x = self.parent[x];
        }
        x
    }

    fn union(&mut self, a: usize, b: usize, weight: f32) -> usize {
        let ra = self.find(a);
        let rb = self.find(b);
        if ra == rb {
            return ra;
        }
        let (big, small) = if self.size[ra] >= self.size[rb] {
            (ra, rb)
        } else {
            (rb, ra)
        };
        self.parent[small] = big;
        self.size[big] += self.size[small];
        self.int_diff[big] = weight.max(self.int_diff[big]).max(self.int_diff[small]);
        big
    }
}

fn color_dist(p1: Rgb<u8>, p2: Rgb<u8>) -> f32 {
    let dr = p1[0] as f32 - p2[0] as f32;
    let dg = p1[1] as f32 - p2[1] as f32;
    let db = p1[2] as f32 - p2[2] as f32;
    (dr * dr + dg * dg + db * db).sqrt()
}

/// Graph-based Felzenszwalb-Huttenlocher segmentation producing UI/object bounding boxes
/// matching scripts/images/find_regions.py without OpenCV.
fn segment_regions(img: &RgbImage, k: f32, min_size: u32) -> Vec<Rect> {
    let w = img.width() as usize;
    let h = img.height() as usize;
    if w == 0 || h == 0 {
        return Vec::new();
    }
    let n = w * h;
    let mut edges: Vec<(f32, usize, usize)> = Vec::with_capacity(n * 2);
    for y in 0..h {
        for x in 0..w {
            let idx = y * w + x;
            let p = *img.get_pixel(x as u32, y as u32);
            if x + 1 < w {
                let q = *img.get_pixel((x + 1) as u32, y as u32);
                edges.push((color_dist(p, q), idx, idx + 1));
            }
            if y + 1 < h {
                let q = *img.get_pixel(x as u32, (y + 1) as u32);
                edges.push((color_dist(p, q), idx, idx + w));
            }
        }
    }
    edges.sort_by(|a, b| a.0.total_cmp(&b.0));

    let mut uf = UnionFind::new(n);
    for &(weight, u, v) in &edges {
        let ru = uf.find(u);
        let rv = uf.find(v);
        if ru == rv {
            continue;
        }
        let tau_u = uf.int_diff[ru] + k / (uf.size[ru] as f32);
        let tau_v = uf.int_diff[rv] + k / (uf.size[rv] as f32);
        if weight <= tau_u.min(tau_v) {
            uf.union(ru, rv, weight);
        }
    }
    for &(weight, u, v) in &edges {
        let ru = uf.find(u);
        let rv = uf.find(v);
        if ru != rv && (uf.size[ru] < min_size || uf.size[rv] < min_size) {
            uf.union(ru, rv, weight);
        }
    }

    let mut boxes: HashMap<usize, (i32, i32, i32, i32)> = HashMap::new();
    for y in 0..h {
        for x in 0..w {
            let root = uf.find(y * w + x);
            let entry = boxes
                .entry(root)
                .or_insert((x as i32, y as i32, x as i32, y as i32));
            entry.0 = entry.0.min(x as i32);
            entry.1 = entry.1.min(y as i32);
            entry.2 = entry.2.max(x as i32);
            entry.3 = entry.3.max(y as i32);
        }
    }

    boxes
        .into_values()
        .map(|(x0, y0, x1, y1)| Rect {
            x: x0,
            y: y0,
            width: x1 - x0 + 1,
            height: y1 - y0 + 1,
        })
        .collect()
}

pub fn run_find_regions(raw_args: &[String]) -> Result<()> {
    let mut image_path = PathBuf::from("/tmp/quickshell/media/screenshot/image");
    let mut min_width: i32 = 200;
    let mut min_height: i32 = 100;
    let mut max_width: Option<i32> = None;
    let mut max_height: Option<i32> = None;
    let mut single = false;
    let mut quality = false;
    let mut k: f32 = 3000.0;
    let mut min_size: u32 = 50;
    let mut resize_factor: f64 = 0.1;
    let mut hyprctl = false;
    let mut debug_output: Option<PathBuf> = None;

    let mut i = 0;
    while i < raw_args.len() {
        match raw_args[i].as_str() {
            "-i" | "--image" => {
                i += 1;
                image_path = PathBuf::from(raw_args.get(i).ok_or_else(|| anyhow!("missing --image"))?);
            }
            "-do" | "--debug-output" => {
                i += 1;
                debug_output = Some(PathBuf::from(
                    raw_args.get(i).ok_or_else(|| anyhow!("missing --debug-output"))?,
                ));
            }
            "--min-width" => {
                i += 1;
                min_width = raw_args.get(i).ok_or_else(|| anyhow!("missing --min-width"))?.parse()?;
            }
            "--min-height" => {
                i += 1;
                min_height = raw_args.get(i).ok_or_else(|| anyhow!("missing --min-height"))?.parse()?;
            }
            "--max-width" => {
                i += 1;
                max_width = Some(raw_args.get(i).ok_or_else(|| anyhow!("missing --max-width"))?.parse()?);
            }
            "--max-height" => {
                i += 1;
                max_height = Some(raw_args.get(i).ok_or_else(|| anyhow!("missing --max-height"))?.parse()?);
            }
            "--single" => single = true,
            "--quality" => quality = true,
            "--k" => {
                i += 1;
                k = raw_args.get(i).ok_or_else(|| anyhow!("missing --k"))?.parse()?;
            }
            "--min-size" => {
                i += 1;
                min_size = raw_args.get(i).ok_or_else(|| anyhow!("missing --min-size"))?.parse()?;
            }
            "--sigma" => {
                i += 1; // parsed for CLI compatibility
            }
            "--resize-factor" => {
                i += 1;
                resize_factor = raw_args.get(i).ok_or_else(|| anyhow!("missing --resize-factor"))?.parse()?;
            }
            "--hyprctl" => hyprctl = true,
            _ => {}
        }
        i += 1;
    }

    let dyn_img = ImageReader::open(&image_path)
        .with_context(|| format!("could not open image {}", image_path.display()))?
        .with_guessed_format()
        .with_context(|| format!("could not guess image format {}", image_path.display()))?
        .decode()
        .with_context(|| format!("could not decode image {}", image_path.display()))?;
    let orig_w = dyn_img.width() as i32;
    let orig_h = dyn_img.height() as i32;
    let factor = resize_factor.clamp(0.02, 1.0);
    let sw = ((orig_w as f64) * factor).round().max(16.0) as u32;
    let sh = ((orig_h as f64) * factor).round().max(16.0) as u32;
    let scaled = dyn_img.resize_exact(sw, sh, FilterType::Triangle).to_rgb8();

    let scales: &[f32] = if quality {
        &[k * 0.25, k * 0.5, k, k * 2.0]
    } else {
        &[k * 0.35, k]
    };
    let mut raw_rects = Vec::new();
    for &scale_k in scales {
        raw_rects.extend(segment_regions(&scaled, scale_k.max(20.0), min_size.max(8)));
    }

    let inv_x = orig_w as f64 / sw as f64;
    let inv_y = orig_h as f64 / sh as f64;
    let mut regions: Vec<Rect> = Vec::new();
    for r in raw_rects {
        let x = ((r.x as f64) * inv_x).round() as i32;
        let y = ((r.y as f64) * inv_y).round() as i32;
        let w = ((r.width as f64) * inv_x).round().min((orig_w - x) as f64) as i32;
        let h = ((r.height as f64) * inv_y).round().min((orig_h - y) as f64) as i32;
        if x == 0 && y == 0 && w >= orig_w - 2 && h >= orig_h - 2 {
            continue;
        }
        if w > min_width
            && h > min_height
            && max_width.is_none_or(|mw| w < mw)
            && max_height.is_none_or(|mh| h < mh)
        {
            regions.push(Rect { x, y, width: w, height: h });
        }
    }

    let mut regions = non_max_suppression(regions, 0.7);
    if single && !regions.is_empty() {
        regions.truncate(1);
    }

    if let Some(debug_path) = debug_output {
        let mut out = dyn_img.to_rgb8();
        for r in &regions {
            let x0 = r.x.clamp(0, orig_w - 1) as u32;
            let y0 = r.y.clamp(0, orig_h - 1) as u32;
            let x1 = (r.x + r.width - 1).clamp(0, orig_w - 1) as u32;
            let y1 = (r.y + r.height - 1).clamp(0, orig_h - 1) as u32;
            for x in x0..=x1 {
                out.put_pixel(x, y0, Rgb([255, 0, 0]));
                out.put_pixel(x, y1, Rgb([255, 0, 0]));
            }
            for y in y0..=y1 {
                out.put_pixel(x0, y, Rgb([255, 0, 0]));
                out.put_pixel(x1, y, Rgb([255, 0, 0]));
            }
        }
        let _ = out.save(debug_path);
    }

    let payload: Vec<_> = if hyprctl {
        regions
            .iter()
            .map(|r| json!({ "at": [r.x, r.y], "size": [r.width, r.height] }))
            .collect()
    } else {
        regions
            .iter()
            .map(|r| json!({ "x": r.x, "y": r.y, "width": r.width, "height": r.height }))
            .collect()
    };
    println!("{}", serde_json::to_string(&payload)?);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{Rect, non_max_suppression, segment_regions};
    use image::{Rgb, RgbImage};

    #[test]
    fn segments_distinct_colored_rectangles() {
        let mut img = RgbImage::from_pixel(64, 64, Rgb([20, 20, 20]));
        for y in 8..32 {
            for x in 10..44 {
                img.put_pixel(x, y, Rgb([240, 240, 240]));
            }
        }
        let rects = segment_regions(&img, 100.0, 20);
        assert!(rects.iter().any(|r| r.x >= 8 && r.x <= 12 && r.width >= 30 && r.height >= 20));
    }

    #[test]
    fn nms_drops_duplicate_overlapping_boxes() {
        let kept = non_max_suppression(
            vec![
                Rect { x: 0, y: 0, width: 100, height: 100 },
                Rect { x: 2, y: 2, width: 98, height: 98 },
                Rect { x: 200, y: 200, width: 50, height: 50 },
            ],
            0.7,
        );
        assert_eq!(kept.len(), 2);
    }
}
