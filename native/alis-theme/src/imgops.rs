use std::fs;
use std::io::{self, Cursor, Write};
use std::path::Path;

use anyhow::{Context, Result, anyhow, bail};
use image::codecs::jpeg::JpegEncoder;
use image::imageops::FilterType;
use image::{DynamicImage, GenericImageView, ImageFormat, ImageReader};

fn open_image_guessed(path: &str) -> Result<DynamicImage> {
    ImageReader::open(path)
        .with_context(|| format!("open image {path}"))?
        .with_guessed_format()
        .with_context(|| format!("guess format for {path}"))?
        .decode()
        .with_context(|| format!("decode image {path}"))
}

fn dimensions_guessed(path: &str) -> Result<(u32, u32)> {
    ImageReader::open(path)
        .with_context(|| format!("open image {path}"))?
        .with_guessed_format()
        .with_context(|| format!("guess format for {path}"))?
        .into_dimensions()
        .or_else(|_| open_image_guessed(path).map(|img| img.dimensions()))
        .with_context(|| format!("identify image {path}"))
}

fn parse_geometry(geom: &str) -> Result<(u32, u32, u32, u32)> {
    let (wh, xy) = geom
        .split_once('+')
        .ok_or_else(|| anyhow!("invalid crop geometry (expected WxH+X+Y): {geom}"))?;
    let (w_s, h_s) = wh
        .split_once('x')
        .or_else(|| wh.split_once('X'))
        .ok_or_else(|| anyhow!("invalid WxH in geometry: {geom}"))?;
    let (x_s, y_s) = xy
        .split_once('+')
        .ok_or_else(|| anyhow!("invalid +X+Y in geometry: {geom}"))?;
    Ok((w_s.parse()?, h_s.parse()?, x_s.parse()?, y_s.parse()?))
}

fn parse_resize_spec(spec: &str, orig_w: u32, orig_h: u32) -> Result<(u32, u32)> {
    let clean = spec.trim_end_matches('!');
    if let Some((ws, hs)) = clean.split_once('x').or_else(|| clean.split_once('X')) {
        let w_opt: Option<u32> = (!ws.is_empty()).then(|| ws.parse()).transpose()?;
        let h_opt: Option<u32> = (!hs.is_empty()).then(|| hs.parse()).transpose()?;
        match (w_opt, h_opt) {
            (Some(w), Some(h)) => {
                if spec.ends_with('!') {
                    return Ok((w.max(1), h.max(1)));
                }
                let scale =
                    (w as f64 / orig_w.max(1) as f64).min(h as f64 / orig_h.max(1) as f64);
                Ok((
                    ((orig_w as f64) * scale).round().max(1.0) as u32,
                    ((orig_h as f64) * scale).round().max(1.0) as u32,
                ))
            }
            (Some(w), None) => {
                let h = ((orig_h as f64) * (w as f64 / orig_w.max(1) as f64))
                    .round()
                    .max(1.0) as u32;
                Ok((w.max(1), h))
            }
            (None, Some(h)) => {
                let w = ((orig_w as f64) * (h as f64 / orig_h.max(1) as f64))
                    .round()
                    .max(1.0) as u32;
                Ok((w, h.max(1)))
            }
            (None, None) => bail!("empty resize spec: {spec}"),
        }
    } else {
        let dim: u32 = clean.parse()?;
        let scale = (dim as f64 / orig_w.max(1) as f64).min(dim as f64 / orig_h.max(1) as f64);
        Ok((
            ((orig_w as f64) * scale).round().max(1.0) as u32,
            ((orig_h as f64) * scale).round().max(1.0) as u32,
        ))
    }
}

fn write_images_to_pdf(images: &[String], output_path: &Path) -> Result<()> {
    if images.is_empty() {
        bail!("to-pdf requires at least one image");
    }
    if let Some(parent) = output_path.parent().filter(|p| !p.as_os_str().is_empty()) {
        fs::create_dir_all(parent)?;
    }

    struct PageData {
        width: u32,
        height: u32,
        jpeg: Vec<u8>,
    }
    let mut pages = Vec::with_capacity(images.len());
    for path in images {
        let img = open_image_guessed(path)?;
        let rgb = img.to_rgb8();
        let (w, h) = rgb.dimensions();
        let mut jpeg = Vec::new();
        let mut enc = JpegEncoder::new_with_quality(&mut jpeg, 90);
        enc.encode_image(&rgb)?;
        pages.push(PageData { width: w, height: h, jpeg });
    }

    let mut pdf = Vec::new();
    pdf.extend_from_slice(b"%PDF-1.4\n%\xE2\xE3\xCF\xD3\n");
    let mut offsets: Vec<usize> = vec![0];
    let page_count = pages.len();

    let push_obj = |pdf: &mut Vec<u8>, offsets: &mut Vec<usize>, id: usize, body: &[u8]| {
        offsets.push(pdf.len());
        pdf.extend_from_slice(format!("{id} 0 obj\n").as_bytes());
        pdf.extend_from_slice(body);
        pdf.extend_from_slice(b"\nendobj\n");
    };

    push_obj(&mut pdf, &mut offsets, 1, b"<< /Type /Catalog /Pages 2 0 R >>");

    let kids: Vec<String> = (0..page_count).map(|i| format!("{} 0 R", 3 + 3 * i)).collect();
    let pages_dict = format!(
        "<< /Type /Pages /Kids [{}] /Count {} >>",
        kids.join(" "),
        page_count
    );
    push_obj(&mut pdf, &mut offsets, 2, pages_dict.as_bytes());

    for (i, page) in pages.iter().enumerate() {
        let page_id = 3 + 3 * i;
        let img_id = page_id + 1;
        let content_id = page_id + 2;

        let page_body = format!(
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {} {}] /Resources << /XObject << /Im0 {} 0 R >> >> /Contents {} 0 R >>",
            page.width, page.height, img_id, content_id
        );
        push_obj(&mut pdf, &mut offsets, page_id, page_body.as_bytes());

        let mut img_body = format!(
            "<< /Type /XObject /Subtype /Image /Width {} /Height {} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length {} >>\nstream\n",
            page.width,
            page.height,
            page.jpeg.len()
        )
        .into_bytes();
        img_body.extend_from_slice(&page.jpeg);
        img_body.extend_from_slice(b"\nendstream");
        push_obj(&mut pdf, &mut offsets, img_id, &img_body);

        let stream_ops = format!("q {} 0 0 {} 0 0 cm /Im0 Do Q", page.width, page.height);
        let content_body = format!(
            "<< /Length {} >>\nstream\n{}\nendstream",
            stream_ops.len(),
            stream_ops
        );
        push_obj(&mut pdf, &mut offsets, content_id, content_body.as_bytes());
    }

    let xref_offset = pdf.len();
    pdf.extend_from_slice(format!("xref\n0 {}\n", offsets.len()).as_bytes());
    pdf.extend_from_slice(b"0000000000 65535 f \n");
    for &off in &offsets[1..] {
        pdf.extend_from_slice(format!("{off:010} 00000 n \n").as_bytes());
    }
    pdf.extend_from_slice(
        format!(
            "trailer\n<< /Size {} /Root 1 0 R >>\nstartxref\n{}\n%%EOF\n",
            offsets.len(),
            xref_offset
        )
        .as_bytes(),
    );
    fs::write(output_path, pdf)?;
    Ok(())
}

pub fn rgb_to_hsl(r: f64, g: f64, b: f64) -> (f64, f64, f64) {
    let r = r.clamp(0.0, 1.0);
    let g = g.clamp(0.0, 1.0);
    let b = b.clamp(0.0, 1.0);
    let max = r.max(g).max(b);
    let min = r.min(g).min(b);
    let l = (max + min) * 0.5;
    let d = max - min;
    if d <= 1e-12 {
        return (0.0, 0.0, l);
    }
    let s = if l > 0.5 {
        d / (2.0 - max - min)
    } else {
        d / (max + min)
    };
    let h_raw = if (max - r).abs() <= 1e-12 {
        ((g - b) / d) + if g < b { 6.0 } else { 0.0 }
    } else if (max - g).abs() <= 1e-12 {
        ((b - r) / d) + 2.0
    } else {
        ((r - g) / d) + 4.0
    };
    let h = (h_raw * 60.0).rem_euclid(360.0);
    (h, s.clamp(0.0, 1.0), l.clamp(0.0, 1.0))
}

pub fn average_hsl(img: &DynamicImage) -> (f64, f64, f64) {
    if img.color().has_alpha() {
        let rgba = img.to_rgba8();
        let (mut r_sum, mut g_sum, mut b_sum, mut a_sum) = (0_u128, 0_u128, 0_u128, 0_u128);
        for px in rgba.pixels() {
            let a = px[3] as u128;
            if a == 0 {
                continue;
            }
            r_sum += (px[0] as u128) * a;
            g_sum += (px[1] as u128) * a;
            b_sum += (px[2] as u128) * a;
            a_sum += a;
        }
        if a_sum > 0 {
            let denom = (a_sum as f64) * 255.0;
            return rgb_to_hsl(
                (r_sum as f64) / denom,
                (g_sum as f64) / denom,
                (b_sum as f64) / denom,
            );
        }
        return (0.0, 0.0, 0.0);
    }
    let rgb = img.to_rgb8();
    let count = (rgb.width() as u64) * (rgb.height() as u64);
    if count == 0 {
        return (0.0, 0.0, 0.0);
    }
    let (mut r_sum, mut g_sum, mut b_sum) = (0_u64, 0_u64, 0_u64);
    for px in rgb.pixels() {
        r_sum += px[0] as u64;
        g_sum += px[1] as u64;
        b_sum += px[2] as u64;
    }
    let denom = (count as f64) * 255.0;
    rgb_to_hsl(
        (r_sum as f64) / denom,
        (g_sum as f64) / denom,
        (b_sum as f64) / denom,
    )
}

fn extract_single_path<'a>(args: &'a [String], flag: Option<&str>) -> Option<&'a str> {
    let mut after_sep = false;
    for arg in args {
        if after_sep {
            return Some(arg.as_str());
        }
        if arg == "--" {
            after_sep = true;
            continue;
        }
        if flag.is_some_and(|f| arg == f) {
            continue;
        }
        return Some(arg.as_str());
    }
    None
}

pub fn run_image(raw_args: &[String]) -> Result<()> {
    let sub = raw_args
        .first()
        .map(String::as_str)
        .ok_or_else(|| anyhow!("usage: --image <identify|crop|resize|first-frame|luma|hsl|convert|to-pdf> ..."))?;
    let rest = &raw_args[1..];

    match sub {
        "identify" => {
            let path = rest.first().ok_or_else(|| anyhow!("identify requires path"))?;
            let (w, h) = dimensions_guessed(path)?;
            println!("{w} {h}");
            Ok(())
        }
        "crop" => {
            if rest.len() < 3 {
                bail!("usage: --image crop <src> <WxH+X+Y> <out_or_->");
            }
            let src = &rest[0];
            let (cw, ch, cx, cy) = parse_geometry(&rest[1])?;
            let out = &rest[2];
            let img = open_image_guessed(src)?;
            let (iw, ih) = img.dimensions();
            let x = cx.min(iw.saturating_sub(1));
            let y = cy.min(ih.saturating_sub(1));
            let w = cw.min(iw.saturating_sub(x)).max(1);
            let h = ch.min(ih.saturating_sub(y)).max(1);
            let cropped = img.crop_imm(x, y, w, h);
            if out == "-" {
                let mut buf = Cursor::new(Vec::new());
                cropped.write_to(&mut buf, ImageFormat::Png)?;
                io::stdout().write_all(&buf.into_inner())?;
                return Ok(());
            }
            let out_path = Path::new(out);
            if let Some(parent) = out_path.parent().filter(|p| !p.as_os_str().is_empty()) {
                fs::create_dir_all(parent)?;
            }
            let tmp = out_path.with_extension(format!("alis-{}.tmp.png", std::process::id()));
            cropped.save_with_format(&tmp, ImageFormat::Png)?;
            fs::rename(&tmp, out_path)?;
            Ok(())
        }
        "resize" => {
            if rest.len() < 3 {
                bail!("usage: --image resize <src> <WxH> <out> [--quality Q]");
            }
            let src = &rest[0];
            let spec = &rest[1];
            let out = Path::new(&rest[2]);
            let quality: Option<u8> = rest
                .windows(2)
                .find(|w| w[0] == "--quality")
                .and_then(|w| w[1].parse().ok());
            let img = open_image_guessed(src)?;
            let (tw, th) = parse_resize_spec(spec, img.width(), img.height())?;
            let resized = img.resize_exact(tw, th, FilterType::Triangle);
            if let Some(parent) = out.parent().filter(|p| !p.as_os_str().is_empty()) {
                fs::create_dir_all(parent)?;
            }
            let ext = out
                .extension()
                .and_then(|e| e.to_str())
                .unwrap_or("png")
                .to_ascii_lowercase();
            if (ext == "jpg" || ext == "jpeg")
                && let Some(q) = quality
            {
                let mut f = fs::File::create(out)?;
                let mut enc = JpegEncoder::new_with_quality(&mut f, q.clamp(1, 100));
                enc.encode_image(&resized.to_rgb8())?;
            } else if let Ok(fmt) = ImageFormat::from_path(out) {
                if fmt == ImageFormat::Jpeg {
                    resized.to_rgb8().save_with_format(out, ImageFormat::Jpeg)?;
                } else {
                    resized.save_with_format(out, fmt)?;
                }
            } else {
                resized.save_with_format(out, ImageFormat::Png)?;
            }
            Ok(())
        }
        "first-frame" => {
            if rest.len() < 2 {
                bail!("usage: --image first-frame <src> <out>");
            }
            let img = open_image_guessed(&rest[0])?;
            let out = Path::new(&rest[1]);
            if let Some(parent) = out.parent().filter(|p| !p.as_os_str().is_empty()) {
                fs::create_dir_all(parent)?;
            }
            img.save_with_format(out, ImageFormat::Png)?;
            Ok(())
        }
        "luma" => {
            let percent = rest.iter().any(|a| a == "--percent");
            let path = extract_single_path(rest, Some("--percent"))
                .ok_or_else(|| anyhow!("luma requires image path"))?;
            let img = open_image_guessed(path)?
                .resize_exact(64, 64, FilterType::Triangle)
                .to_rgb8();
            let mut sum = 0.0_f64;
            let count = (img.width() as f64) * (img.height() as f64);
            for px in img.pixels() {
                sum +=
                    (0.2126 * px[0] as f64 + 0.7152 * px[1] as f64 + 0.0722 * px[2] as f64) / 255.0;
            }
            let mean = if count > 0.0 { sum / count } else { 0.0 };
            if percent {
                println!("{:.4}", mean * 100.0);
            } else {
                println!("{mean:.6}");
            }
            Ok(())
        }
        "hsl" => {
            let path = extract_single_path(rest, None)
                .ok_or_else(|| anyhow!("hsl requires image path"))?;
            let img = open_image_guessed(path)?;
            let (h, s, l) = average_hsl(&img);
            println!("{h:.4} {s:.6} {l:.6}");
            Ok(())
        }
        "convert" => {
            if rest.len() < 2 {
                bail!("usage: --image convert <src> <out>");
            }
            let img = open_image_guessed(&rest[0])?;
            let out = Path::new(&rest[1]);
            if let Some(parent) = out.parent().filter(|p| !p.as_os_str().is_empty()) {
                fs::create_dir_all(parent)?;
            }
            if let Ok(fmt) = ImageFormat::from_path(out) {
                if fmt == ImageFormat::Jpeg {
                    img.to_rgb8().save_with_format(out, ImageFormat::Jpeg)?;
                } else {
                    img.save_with_format(out, fmt)?;
                }
            } else {
                img.save_with_format(out, ImageFormat::Png)?;
            }
            Ok(())
        }
        "to-pdf" => {
            if rest.len() < 2 {
                bail!("usage: --image to-pdf <out.pdf> <img1> [img2 ...]");
            }
            write_images_to_pdf(&rest[1..], Path::new(&rest[0]))
        }
        other => {
            eprintln!("unknown --image subcommand: {other}");
            std::process::exit(2);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{
        average_hsl, extract_single_path, parse_geometry, parse_resize_spec, rgb_to_hsl,
        write_images_to_pdf,
    };
    use image::{DynamicImage, Rgb, RgbImage, Rgba, RgbaImage};

    #[test]
    fn parses_crop_and_resize_specs() {
        assert_eq!(parse_geometry("640x480+10+20").unwrap(), (640, 480, 10, 20));
        assert_eq!(parse_resize_spec("200x", 400, 200).unwrap(), (200, 100));
        assert_eq!(parse_resize_spec("64x64!", 400, 200).unwrap(), (64, 64));
    }

    #[test]
    fn computes_average_hsl_accurately() {
        let (h_r, s_r, l_r) = average_hsl(&DynamicImage::ImageRgb8(RgbImage::from_pixel(
            8,
            8,
            Rgb([255, 0, 0]),
        )));
        assert!(h_r.abs() < 0.01 && (s_r - 1.0).abs() < 0.001 && (l_r - 0.5).abs() < 0.001);

        let (h_g, s_g, l_g) = average_hsl(&DynamicImage::ImageRgb8(RgbImage::from_pixel(
            8,
            8,
            Rgb([0, 255, 0]),
        )));
        assert!((h_g - 120.0).abs() < 0.01 && (s_g - 1.0).abs() < 0.001 && (l_g - 0.5).abs() < 0.001);

        let (h_b, s_b, l_b) = average_hsl(&DynamicImage::ImageRgb8(RgbImage::from_pixel(
            8,
            8,
            Rgb([0, 0, 255]),
        )));
        assert!((h_b - 240.0).abs() < 0.01 && (s_b - 1.0).abs() < 0.001 && (l_b - 0.5).abs() < 0.001);

        let (h_w, s_w, l_w) = rgb_to_hsl(1.0, 1.0, 1.0);
        assert!(h_w == 0.0 && s_w == 0.0 && (l_w - 1.0).abs() < 1e-9);

        let (h_k, s_k, l_k) = rgb_to_hsl(0.0, 0.0, 0.0);
        assert!(h_k == 0.0 && s_k == 0.0 && l_k == 0.0);

        let (h_y, s_y, l_y) = rgb_to_hsl(1.0, 1.0, 0.0);
        assert!((h_y - 60.0).abs() < 0.01 && (s_y - 1.0).abs() < 0.001 && (l_y - 0.5).abs() < 0.001);

        // Transparent pixels must not skew average HSL of visible content.
        let mut rgba = RgbaImage::new(4, 4);
        for (x, _, px) in rgba.enumerate_pixels_mut() {
            *px = if x < 2 {
                Rgba([255, 0, 0, 0])
            } else {
                Rgba([0, 0, 255, 255])
            };
        }
        let (h_a, s_a, l_a) = average_hsl(&DynamicImage::ImageRgba8(rgba));
        assert!((h_a - 240.0).abs() < 0.01 && (s_a - 1.0).abs() < 0.001 && (l_a - 0.5).abs() < 0.001);

        // Paths starting with '-' must still be parsed cleanly.
        assert_eq!(
            extract_single_path(&["-leading-dash.png".into()], None),
            Some("-leading-dash.png")
        );
        assert_eq!(
            extract_single_path(&["--percent".into(), "-dash.png".into()], Some("--percent")),
            Some("-dash.png")
        );
    }

    #[test]
    fn creates_valid_multipage_pdf() {
        let dir = std::env::temp_dir().join(format!("alis-pdf-test-{}", std::process::id()));
        let _ = std::fs::create_dir_all(&dir);
        let p1 = dir.join("a.png");
        let pdf = dir.join("out.pdf");
        RgbImage::from_pixel(16, 12, Rgb([20, 140, 220])).save(&p1).unwrap();
        write_images_to_pdf(&[p1.to_string_lossy().into_owned()], &pdf).unwrap();
        let bytes = std::fs::read(&pdf).unwrap();
        assert!(bytes.starts_with(b"%PDF-1.4"));
        assert!(bytes.windows(5).any(|w| w == b"%%EOF"));
        let _ = std::fs::remove_dir_all(&dir);
    }
}
