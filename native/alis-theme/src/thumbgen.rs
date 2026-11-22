use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Mutex;
use std::time::UNIX_EPOCH;

use anyhow::{Context, Result, anyhow, bail};
use image::ImageReader;
use image::imageops::FilterType;

const IMAGE_EXTS: &[&str] = &[
    "jpg", "jpeg", "png", "gif", "webp", "bmp", "tif", "tiff", "avif", "qoi", "ico",
];
const VIDEO_EXTS: &[&str] = &["mp4", "webm", "mkv", "avi", "mov"];

fn size_pixels(size_name: &str) -> Result<u32> {
    match size_name {
        "normal" => Ok(128),
        "large" => Ok(256),
        "x-large" => Ok(512),
        "xx-large" => Ok(1024),
        other => bail!("invalid thumbnail size: {other}"),
    }
}

fn percent_encode_component(comp: &str) -> String {
    let mut out = String::with_capacity(comp.len());
    for &b in comp.as_bytes() {
        let safe = b.is_ascii_alphanumeric() || matches!(b, b'-' | b'_' | b'.' | b'~');
        if safe {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

pub fn file_uri(path: &Path) -> String {
    let s = path.to_string_lossy();
    let encoded = s
        .split('/')
        .map(percent_encode_component)
        .collect::<Vec<_>>()
        .join("/");
    format!("file://{encoded}")
}

fn md5_hex(data: &[u8]) -> String {
    // Standard RFC 1321 MD5 for Freedesktop thumbnail spec filenames.
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
    const S: [u32; 64] = [
        7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 5, 9, 14, 20, 5, 9, 14, 20, 5,
        9, 14, 20, 5, 9, 14, 20, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 6, 10,
        15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
    ];
    let mut a0: u32 = 0x67452301;
    let mut b0: u32 = 0xefcdab89;
    let mut c0: u32 = 0x98badcfe;
    let mut d0: u32 = 0x10325476;

    let orig_bits = (data.len() as u64).wrapping_mul(8);
    let mut msg = data.to_vec();
    msg.push(0x80);
    while msg.len() % 64 != 56 {
        msg.push(0);
    }
    msg.extend_from_slice(&orig_bits.to_le_bytes());

    for chunk in msg.chunks_exact(64) {
        let mut m = [0u32; 16];
        for i in 0..16 {
            m[i] = u32::from_le_bytes(chunk[i * 4..i * 4 + 4].try_into().unwrap());
        }
        let (mut a, mut b, mut c, mut d) = (a0, b0, c0, d0);
        for i in 0..64 {
            let (f, g) = match i {
                0..=15 => ((b & c) | ((!b) & d), i),
                16..=31 => ((d & b) | ((!d) & c), (5 * i + 1) % 16),
                32..=47 => (b ^ c ^ d, (3 * i + 5) % 16),
                _ => (c ^ (b | (!d)), (7 * i) % 16),
            };
            let temp = d;
            d = c;
            c = b;
            let sum = a.wrapping_add(f).wrapping_add(K[i]).wrapping_add(m[g]);
            b = b.wrapping_add(sum.rotate_left(S[i]));
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

pub fn thumbnail_path(abs_path: &Path, size_name: &str) -> PathBuf {
    let uri = file_uri(abs_path);
    let hash = md5_hex(uri.as_bytes());
    let cache = std::env::var_os("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            std::env::var_os("HOME")
                .map(PathBuf::from)
                .unwrap_or_else(|| PathBuf::from("/"))
                .join(".cache")
        });
    cache.join("thumbnails").join(size_name).join(format!("{hash}.png"))
}

fn is_media_ext(path: &Path) -> bool {
    let Some(ext) = path.extension().and_then(|e| e.to_str()) else {
        return false;
    };
    let lower = ext.to_ascii_lowercase();
    IMAGE_EXTS.contains(&lower.as_str()) || VIDEO_EXTS.contains(&lower.as_str())
}

fn is_video(path: &Path) -> bool {
    let Some(ext) = path.extension().and_then(|e| e.to_str()) else {
        return false;
    };
    VIDEO_EXTS.contains(&ext.to_ascii_lowercase().as_str())
}

fn is_fresh(src: &Path, dst: &Path) -> bool {
    let Ok(src_meta) = fs::metadata(src) else {
        return false;
    };
    let Ok(dst_meta) = fs::metadata(dst) else {
        return false;
    };
    if dst_meta.len() == 0 {
        return false;
    }
    match (src_meta.modified(), dst_meta.modified()) {
        (Ok(sm), Ok(dm)) => dm >= sm,
        _ => true,
    }
}

pub fn generate_one(path: &Path, size_name: &str) -> Result<bool> {
    let abs = fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf());
    let out = thumbnail_path(&abs, size_name);
    if is_fresh(&abs, &out) {
        return Ok(false);
    }
    if let Some(parent) = out.parent() {
        fs::create_dir_all(parent)?;
    }
    let max_dim = size_pixels(size_name)?;
    let tmp = out.with_extension(format!("alis-{}.tmp.png", std::process::id()));

    if is_video(&abs) {
        let filter = format!(
            "thumbnail,scale={max_dim}:{max_dim}:force_original_aspect_ratio=decrease"
        );
        let status = Command::new("ffmpeg")
            .args([
                "-v",
                "error",
                "-y",
                "-ss",
                "00:00:01",
                "-i",
            ])
            .arg(&abs)
            .args(["-frames:v", "1", "-vf", &filter])
            .arg(&tmp)
            .status();
        if status.is_ok_and(|s| s.success()) && tmp.is_file() {
            fs::rename(&tmp, &out)?;
            return Ok(true);
        }
        let _ = fs::remove_file(&tmp);
        return Ok(false);
    }

    let img = match ImageReader::open(&abs)
        .ok()
        .and_then(|r| r.with_guessed_format().ok())
        .and_then(|r| r.decode().ok())
    {
        Some(i) => i,
        None => return Ok(false),
    };
    let resized = if img.width() <= max_dim && img.height() <= max_dim {
        img
    } else {
        img.resize(max_dim, max_dim, FilterType::Triangle)
    };
    resized
        .save_with_format(&tmp, image::ImageFormat::Png)
        .with_context(|| format!("save thumbnail {}", out.display()))?;
    fs::rename(&tmp, &out)?;
    Ok(true)
}

fn collect_files(dir: &Path, recursive: bool, only_images: bool, out: &mut Vec<PathBuf>) -> Result<()> {
    let entries = fs::read_dir(dir).with_context(|| format!("read_dir {}", dir.display()))?;
    for entry in entries.flatten() {
        let p = entry.path();
        if p.is_dir() {
            if recursive {
                let _ = collect_files(&p, true, only_images, out);
            }
        } else if p.is_file() && (!only_images || is_media_ext(&p)) {
            out.push(p);
        }
    }
    Ok(())
}

pub fn run_thumbgen(raw_args: &[String]) -> Result<()> {
    let mut dirs: Vec<PathBuf> = Vec::new();
    let mut single_files: Vec<PathBuf> = Vec::new();
    let mut size = "normal".to_string();
    let mut workers: usize = 2;
    let mut only_images = false;
    let mut recursive = false;
    let mut machine_progress = false;

    let mut i = 0;
    while i < raw_args.len() {
        match raw_args[i].as_str() {
            "-d" | "--img_dirs" | "--directory" => {
                i += 1;
                let val = raw_args.get(i).ok_or_else(|| anyhow!("missing directory argument"))?;
                let direct = PathBuf::from(val);
                if direct.exists() {
                    dirs.push(direct);
                } else {
                    for part in val.split_whitespace() {
                        dirs.push(PathBuf::from(part));
                    }
                }
            }
            "-f" | "--file" => {
                i += 1;
                let val = raw_args.get(i).ok_or_else(|| anyhow!("missing --file argument"))?;
                single_files.push(PathBuf::from(val));
            }
            "-s" | "--size" => {
                i += 1;
                size = raw_args
                    .get(i)
                    .ok_or_else(|| anyhow!("missing --size argument"))?
                    .clone();
            }
            "-w" | "--workers" => {
                i += 1;
                workers = raw_args
                    .get(i)
                    .ok_or_else(|| anyhow!("missing --workers argument"))?
                    .parse::<usize>()
                    .unwrap_or(2)
                    .clamp(1, 16);
            }
            "-i" | "--only_images" => only_images = true,
            "-r" | "--recursive" => recursive = true,
            "--machine_progress" => machine_progress = true,
            other if !other.starts_with('-') => {
                let p = PathBuf::from(other);
                if p.is_dir() {
                    dirs.push(p);
                } else {
                    single_files.push(p);
                }
            }
            _ => {}
        }
        i += 1;
    }

    let _ = size_pixels(&size)?;

    let mut all_files = single_files;
    for dir in &dirs {
        if dir.is_dir() {
            let before = all_files.len();
            collect_files(dir, recursive, only_images, &mut all_files)?;
            if !machine_progress {
                println!(
                    "Found {} files in the directory: {}",
                    all_files.len() - before,
                    dir.display()
                );
            }
        }
    }
    all_files.sort();
    all_files.dedup();
    let total = all_files.len();
    if total == 0 {
        println!("Thumbnail Generation Completed!");
        return Ok(());
    }

    let next_idx = AtomicUsize::new(0);
    let completed = AtomicUsize::new(0);
    let out_lock = Mutex::new(());
    let actual_workers = workers.min(total).max(1);

    std::thread::scope(|scope| {
        for _ in 0..actual_workers {
            scope.spawn(|| loop {
                let idx = next_idx.fetch_add(1, Ordering::Relaxed);
                if idx >= total {
                    break;
                }
                let path = &all_files[idx];
                let _ = generate_one(path, &size);
                let done = completed.fetch_add(1, Ordering::SeqCst) + 1;
                if machine_progress {
                    let _g = out_lock.lock().unwrap();
                    println!("PROGRESS {done}/{total} FILE {}", path.display());
                    let _ = std::io::stdout().flush();
                }
            });
        }
    });

    // Touch mtime marker check not needed; print completion line matching thumbgen.py
    let _ = UNIX_EPOCH;
    println!("Thumbnail Generation Completed!");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{file_uri, md5_hex};
    use std::path::Path;

    #[test]
    fn freedesktop_uri_and_md5_match_spec() {
        assert_eq!(file_uri(Path::new("/tmp/a b.png")), "file:///tmp/a%20b.png");
        assert_eq!(md5_hex(b"hello"), "5d41402abc4b2a76b9719d911017c592");
    }
}
