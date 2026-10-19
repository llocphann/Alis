//! Versioned, content-addressed cache for image-derived seed + auto scheme.
//! Best-effort only: a cache problem must never change or block color generation.
use std::fs::{self, File, OpenOptions};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use material_color_utils::utils::color_utils::Argb;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::source::color_seed;

const CACHE_VERSION: &str = "seed-v1-image-0.25.9-catmul-128color-scheme-auto-v1";
const MAX_ENTRIES: usize = 64;

#[derive(Serialize, Deserialize)]
struct Entry {
    version: String,
    image_sha256: String,
    bitmap_size: u32,
    seed_color: String,
    auto_scheme: String,
}

pub struct SeedCache {
    directory: PathBuf,
    entry_path: PathBuf,
    image_path: PathBuf,
    image_sha256: String,
    bitmap_size: u32,
}

fn cache_directory() -> Option<PathBuf> {
    if std::env::var("ALIS_THEME_SEED_CACHE").as_deref() == Ok("0") {
        return None;
    }
    let root = std::env::var_os("XDG_CACHE_HOME")
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .or_else(|| {
            std::env::var_os("HOME")
                .filter(|value| !value.is_empty())
                .map(|home| PathBuf::from(home).join(".cache"))
        })?;
    Some(root.join("alis").join("theme-seeds"))
}

/// Hash the actual image bytes, not a path/mtime shortcut. Replacing an image
/// in-place invalidates this key even when timestamps or file sizes are reused.
fn digest_file(path: &Path) -> std::io::Result<String> {
    let mut file = File::open(path)?;
    let mut digest = Sha256::new();
    let mut buffer = [0_u8; 64 * 1024];
    loop {
        let count = file.read(&mut buffer)?;
        if count == 0 {
            break;
        }
        digest.update(&buffer[..count]);
    }
    Ok(format!("{:x}", digest.finalize()))
}

fn is_auto_scheme(value: &str) -> bool {
    matches!(
        value,
        "scheme-content"
            | "scheme-expressive"
            | "scheme-fidelity"
            | "scheme-fruit-salad"
            | "scheme-monochrome"
            | "scheme-neutral"
            | "scheme-rainbow"
            | "scheme-tonal-spot"
            | "scheme-vibrant"
    )
}

impl SeedCache {
    pub fn prepare(image: &Path, bitmap_size: u32) -> Option<Self> {
        let directory = cache_directory()?;
        let image_sha256 = digest_file(image).ok()?;
        let mut key = Sha256::new();
        key.update(CACHE_VERSION.as_bytes());
        key.update(bitmap_size.to_le_bytes());
        key.update(image_sha256.as_bytes());
        let entry_path = directory.join(format!("v1-{:x}.json", key.finalize()));
        Some(Self {
            directory,
            entry_path,
            image_path: image.to_path_buf(),
            image_sha256,
            bitmap_size,
        })
    }

    pub fn image_unchanged(&self) -> bool {
        digest_file(&self.image_path).ok().as_deref() == Some(&self.image_sha256)
    }

    pub fn lookup(&self) -> Option<(Argb, String)> {
        let bytes = fs::read(&self.entry_path).ok()?;
        // Reject unexpected large or corrupt entries without panicking.
        if bytes.len() > 4096 {
            return None;
        }
        let entry: Entry = serde_json::from_slice(&bytes).ok()?;
        if entry.version != CACHE_VERSION
            || entry.image_sha256 != self.image_sha256
            || entry.bitmap_size != self.bitmap_size
            || !is_auto_scheme(&entry.auto_scheme)
        {
            return None;
        }
        let seed = color_seed(&entry.seed_color).ok()?;
        Some((seed, entry.auto_scheme))
    }

    pub fn store(&self, seed: Argb, scheme: &str) {
        if !is_auto_scheme(scheme) {
            return;
        }
        // Another process may have replaced this wallpaper while we were
        // decoding it. Never cache a seed against the previous file contents.
        if !self.image_unchanged() {
            return;
        }
        if fs::create_dir_all(&self.directory).is_err() {
            return;
        }
        let entry = Entry {
            version: CACHE_VERSION.to_owned(),
            image_sha256: self.image_sha256.clone(),
            bitmap_size: self.bitmap_size,
            seed_color: seed.to_hex(),
            auto_scheme: scheme.to_owned(),
        };
        let Ok(content) = serde_json::to_vec(&entry) else {
            return;
        };
        let serial = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_or(0, |duration| duration.as_nanos());
        let staged = self.directory.join(format!(
            ".seed-{}-{serial}.tmp",
            std::process::id()
        ));
        let stored = (|| -> std::io::Result<()> {
            let mut file = OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&staged)?;
            file.write_all(&content)?;
            drop(file);
            fs::rename(&staged, &self.entry_path)?;
            Ok(())
        })();
        if stored.is_err() {
            let _ = fs::remove_file(&staged);
            return;
        }
        prune(&self.directory);
    }
}

fn prune(directory: &Path) {
    let Ok(reader) = fs::read_dir(directory) else {
        return;
    };
    let mut entries = reader
        .flatten()
        .filter_map(|entry| {
            let name = entry.file_name();
            let name = name.to_str()?;
            if !name.starts_with("v1-") || !name.ends_with(".json") {
                return None;
            }
            let metadata = entry.metadata().ok()?;
            if !metadata.is_file() {
                return None;
            }
            Some((
                metadata.modified().unwrap_or(UNIX_EPOCH),
                entry.path(),
            ))
        })
        .collect::<Vec<_>>();
    if entries.len() <= MAX_ENTRIES {
        return;
    }
    entries.sort_by(|left, right| left.cmp(right));
    let remove_count = entries.len() - MAX_ENTRIES;
    for (_, path) in entries.into_iter().take(remove_count) {
        let _ = fs::remove_file(path);
    }
}

#[cfg(test)]
mod tests {
    use super::{SeedCache, cache_directory, digest_file, is_auto_scheme};
    use crate::source::color_seed;
    use std::fs;
    use std::path::PathBuf;

    fn fixture(name: &str) -> PathBuf {
        let mut dir = std::env::temp_dir();
        dir.push(format!(
            "alis-theme-seed-cache-test-{}-{}-{name}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .expect("clock").as_nanos()
        ));
        fs::create_dir_all(&dir).expect("fixture directory");
        dir
    }

    #[test]
    fn sha256_key_tracks_actual_bytes() {
        let dir = fixture("hash");
        let image = dir.join("wallpaper.dat");
        fs::write(&image, b"image version A").expect("write A");
        let first = digest_file(&image).expect("hash A");
        fs::write(&image, b"image version B").expect("write B");
        assert_ne!(first, digest_file(&image).expect("hash B"));
        fs::remove_dir_all(dir).expect("cleanup");
    }

    #[test]
    fn cached_schemes_are_known_and_reject_auto_placeholder() {
        assert!(is_auto_scheme("scheme-tonal-spot"));
        assert!(!is_auto_scheme("auto"));
        assert!(!is_auto_scheme("scheme-unknown"));
    }

    #[test]
    fn cache_directory_never_uses_wallpaper_path_as_namespace() {
        if let Some(dir) = cache_directory() {
            assert!(dir.ends_with("alis/theme-seeds"));
        }
        assert!(color_seed("#123456").is_ok());
    }

    #[test]
    fn version_and_size_change_cache_key() {
        let dir = fixture("key");
        let image = dir.join("wallpaper.dat");
        fs::write(&image, b"seed fixture").expect("write fixture");
        let first = SeedCache::prepare(&image, 128).expect("cache");
        let different_size = SeedCache::prepare(&image, 96).expect("cache");
        assert_ne!(first.entry_path, different_size.entry_path);
        fs::remove_dir_all(dir).expect("cleanup");
    }
}
