use std::fs::File;
use std::io::BufReader;
use std::path::Path;

use anyhow::{Context, Result, anyhow};
use image::codecs::gif::GifDecoder;
use image::imageops::FilterType;
use image::{AnimationDecoder, DynamicImage, GenericImageView};
use material_color_utils::extract_image_colors;
use material_color_utils::hct::Hct;
use material_color_utils::utils::color_utils::Argb;

use crate::palette::parse_hex;

pub fn calculate_optimal_size(width: u32, height: u32, bitmap_size: u32) -> (u32, u32) {
    let image_area = f64::from(width) * f64::from(height);
    let bitmap_area = f64::from(bitmap_size).powi(2);
    let scale = if image_area > bitmap_area {
        (bitmap_area / image_area).sqrt()
    } else {
        1.0
    };
    (
        (f64::from(width) * scale).round_ties_even().max(1.0) as u32,
        (f64::from(height) * scale).round_ties_even().max(1.0) as u32,
    )
}

fn load_gif_second_frame(path: &Path) -> Result<DynamicImage> {
    let file = BufReader::new(File::open(path)?);
    let decoder = GifDecoder::new(file)?;
    let mut frames = decoder.into_frames();
    let first = frames
        .next()
        .transpose()?
        .ok_or_else(|| anyhow!("gif_has_no_frames"))?;
    let frame = frames.next().transpose()?.unwrap_or(first);
    Ok(DynamicImage::ImageRgba8(frame.into_buffer()))
}

pub fn load_resized_image(path: &Path, bitmap_size: u32) -> Result<DynamicImage> {
    let mut image = if path
        .extension()
        .and_then(|value| value.to_str())
        .is_some_and(|value| value.eq_ignore_ascii_case("gif"))
    {
        load_gif_second_frame(path).or_else(|_| image::open(path))?
    } else {
        image::open(path).with_context(|| format!("open image {}", path.display()))?
    };
    let (width, height) = image.dimensions();
    let (target_width, target_height) = calculate_optimal_size(width, height, bitmap_size);
    if target_width < width || target_height < height {
        image = image.resize_exact(target_width, target_height, FilterType::CatmullRom);
    }
    Ok(image)
}

#[derive(Default)]
struct Moments {
    count: u64,
    sum: f64,
    sum_squares: f64,
}

impl Moments {
    fn push(&mut self, value: f64) {
        self.count += 1;
        self.sum += value;
        self.sum_squares += value * value;
    }

    fn mean(&self) -> f64 {
        if self.count == 0 {
            0.0
        } else {
            self.sum / self.count as f64
        }
    }

    fn stddev(&self) -> f64 {
        if self.count == 0 {
            return 0.0;
        }
        let mean = self.mean();
        (self.sum_squares / self.count as f64 - mean * mean)
            .max(0.0)
            .sqrt()
    }
}

pub fn auto_detect_scheme(image: &DynamicImage) -> &'static str {
    let rgb = image.to_rgb8();
    let mut rg = Moments::default();
    let mut yb = Moments::default();
    let mut saturation = Moments::default();
    let mut hue = Moments::default();

    for pixel in rgb.pixels() {
        let [r8, g8, b8] = pixel.0;
        let red = f64::from(r8);
        let green = f64::from(g8);
        let blue = f64::from(b8);
        rg.push((red - green).abs());
        yb.push((0.5 * (red + green) - blue).abs());

        let red = red / 255.0;
        let green = green / 255.0;
        let blue = blue / 255.0;
        let max = red.max(green).max(blue);
        let min = red.min(green).min(blue);
        let delta = max - min;
        saturation.push(if max > 0.0 { delta / max * 255.0 } else { 0.0 });
        let value = if delta <= f64::EPSILON {
            0.0
        } else if (max - red).abs() <= f64::EPSILON {
            30.0 * ((green - blue) / delta).rem_euclid(6.0)
        } else if (max - green).abs() <= f64::EPSILON {
            30.0 * ((blue - red) / delta + 2.0)
        } else {
            30.0 * ((red - green) / delta + 4.0)
        };
        hue.push(value);
    }

    let mean_rg = rg.mean();
    let mean_yb = yb.mean();
    let colorfulness = (rg.stddev().powi(2) + yb.stddev().powi(2)).sqrt()
        + 0.3 * (mean_rg.powi(2) + mean_yb.powi(2)).sqrt();
    let saturation = saturation.mean();
    let hue_spread = hue.stddev();

    if saturation < 20.0 {
        "scheme-monochrome"
    } else if colorfulness < 30.0 {
        if saturation < 55.0 {
            "scheme-neutral"
        } else if hue_spread < 22.0 {
            "scheme-content"
        } else {
            "scheme-tonal-spot"
        }
    } else if colorfulness < 55.0 {
        if hue_spread < 22.0 && saturation < 100.0 {
            "scheme-content"
        } else {
            "scheme-tonal-spot"
        }
    } else if colorfulness < 90.0 {
        if saturation > 140.0 && hue_spread < 35.0 {
            "scheme-fidelity"
        } else if hue_spread < 30.0 {
            "scheme-content"
        } else {
            "scheme-tonal-spot"
        }
    } else if hue_spread > 55.0 && saturation > 150.0 {
        "scheme-rainbow"
    } else if saturation > 160.0 {
        "scheme-fidelity"
    } else if hue_spread > 45.0 {
        "scheme-expressive"
    } else {
        "scheme-tonal-spot"
    }
}

pub fn image_seed(image: &DynamicImage) -> Result<Argb> {
    extract_image_colors(image)
        .quantize_max_colors(128)
        .desired_colors(1)
        .call()
        .first()
        .copied()
        .ok_or_else(|| anyhow!("image_seed_not_found"))
}

pub fn color_seed(value: &str) -> Result<Argb> {
    parse_hex(value)
}

pub fn invert_hue(seed: Argb) -> Argb {
    let hct = Hct::from_argb(seed);
    Hct::new(
        (hct.hue() + 180.0).rem_euclid(360.0),
        hct.chroma(),
        hct.tone(),
    )
    .to_argb()
}

pub fn low_chroma(seed: Argb) -> bool {
    Hct::from_argb(seed).chroma() < 20.0
}

#[cfg(test)]
mod tests {
    use super::calculate_optimal_size;

    #[test]
    fn optimal_size_never_upscales() {
        assert_eq!(calculate_optimal_size(64, 32, 128), (64, 32));
    }

    #[test]
    fn optimal_size_preserves_area_target() {
        let (width, height) = calculate_optimal_size(3840, 2160, 128);
        assert!(width > height);
        assert!((width as u64 * height as u64) <= 128 * 128 + 256);
    }
}
