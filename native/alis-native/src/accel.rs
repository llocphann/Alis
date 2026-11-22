use std::collections::{HashMap, HashSet};
use std::env;
use std::fs::{self, File};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result, bail};
use clap::Subcommand;
use serde::Serialize;
use serde_json::{Value, json};

#[derive(Debug, Subcommand)]
pub enum AccelCommand {
    /// Zero-decode image header dimensions (<width> <height>) for PNG/JPEG/WebP/GIF/BMP.
    ImageSize {
        /// Path (or file:// URI) to the image file.
        path: String,
    },

    /// Resolve active PipeWire/PulseAudio Cava capture source (parity with resolve_audio_source.py).
    CavaSource {
        #[arg(long = "desktop-entry", default_value = "")]
        desktop_entry: String,
        #[arg(long = "track-title", default_value = "")]
        track_title: String,
    },

    /// Resolve Cava capture source and atomically write config only when bytes change.
    CavaConfig {
        output_file: PathBuf,
        #[arg(default_value_t = 30)]
        framerate: u32,
        #[arg(default_value_t = 100)]
        sensitivity: u32,
        #[arg(default_value_t = 50)]
        bars: u32,
        #[arg(default_value = "false")]
        stereo: String,
        #[arg(default_value = "")]
        desktop_entry: String,
        #[arg(long = "print-config")]
        print_config: bool,
    },

    /// Fast XDG .desktop scanner + bitmask/prefix/fuzzy scorer (inspired by inir-accel/qs-rs).
    AppSearch {
        /// Optional search query; empty returns alphabetically sorted entries.
        #[arg(default_value = "")]
        query: String,
        #[arg(long, default_value_t = 30)]
        limit: usize,
        #[arg(long)]
        sloppy: bool,
    },

    /// Freedesktop RFC 1321 MD5 thumbnail cache lookup + zero-decode image header metadata.
    ThumbInfo {
        path: String,
        #[arg(long, default_value = "large")]
        size: String,
    },
}

pub fn run(command: AccelCommand) -> Result<i32> {
    match command {
        AccelCommand::ImageSize { path } => {
            let clean = strip_file_uri(&path);
            let (w, h) = read_image_dimensions(Path::new(clean))?;
            println!("{w} {h}");
            Ok(0)
        }
        AccelCommand::CavaSource {
            desktop_entry,
            track_title,
        } => {
            let (source, _) = resolve_cava_audio_source_and_method(&desktop_entry, &track_title, false);
            println!("{source}");
            Ok(0)
        }
        AccelCommand::CavaConfig {
            output_file,
            framerate,
            sensitivity,
            bars,
            stereo,
            desktop_entry,
            print_config,
        } => {
            let track_title = env::var("CAVA_TRACK_TITLE").unwrap_or_default();
            let (mut monitor, method) =
                resolve_cava_audio_source_and_method(&desktop_entry, &track_title, true);
            if monitor.is_empty() {
                monitor = default_sink_monitor();
            }
            let is_stereo = stereo.eq_ignore_ascii_case("true") || stereo == "1";
            let content = render_cava_config(bars, framerate, sensitivity, is_stereo, &method, &monitor);
            if print_config {
                print!("{content}");
            }
            write_file_if_changed_atomic(&output_file, content.as_bytes())?;
            if !print_config {
                println!("{}", output_file.display());
            }
            Ok(0)
        }
        AccelCommand::AppSearch {
            query,
            limit,
            sloppy,
        } => {
            let apps = scan_desktop_entries();
            let results = query_desktop_entries(&apps, &query, limit, sloppy);
            println!("{}", serde_json::to_string(&results)?);
            Ok(0)
        }
        AccelCommand::ThumbInfo { path, size } => {
            let info = inspect_thumbnail_and_dimensions(&path, &size)?;
            println!("{}", serde_json::to_string(&info)?);
            Ok(0)
        }
    }
}

fn strip_file_uri(raw: &str) -> &str {
    let trimmed = raw.trim();
    trimmed.strip_prefix("file://").unwrap_or(trimmed)
}

// ---------------------------------------------------------------------------
// 1. Zero-Decode Image Header Dimension Reader (<0.2 ms, 64 KB stack/heap cap)
// ---------------------------------------------------------------------------

pub fn read_image_dimensions(path: &Path) -> Result<(u32, u32)> {
    let mut file = File::open(path).with_context(|| format!("open image {}", path.display()))?;
    let mut buf = vec![0u8; 65536];
    let mut total = 0usize;
    while total < buf.len() {
        let n = file.read(&mut buf[total..])?;
        if n == 0 {
            break;
        }
        total += n;
    }
    buf.truncate(total);
    parse_image_dimensions_from_bytes(&buf)
        .or_else(|_| read_jpeg_dimensions_streaming(path))
        .with_context(|| format!("unsupported or truncated image header: {}", path.display()))
}

pub fn parse_image_dimensions_from_bytes(buf: &[u8]) -> Result<(u32, u32)> {
    if buf.len() < 10 {
        bail!("header_too_short");
    }

    // PNG: 89 50 4E 47 0D 0A 1A 0A + length(4) + "IHDR"(4) + width(4 BE) + height(4 BE)
    if buf.len() >= 24 && &buf[0..8] == b"\x89PNG\r\n\x1a\n" && &buf[12..16] == b"IHDR" {
        let w = u32::from_be_bytes([buf[16], buf[17], buf[18], buf[19]]);
        let h = u32::from_be_bytes([buf[20], buf[21], buf[22], buf[23]]);
        if w > 0 && h > 0 {
            return Ok((w, h));
        }
    }

    // GIF87a / GIF89a
    if (&buf[0..6] == b"GIF87a" || &buf[0..6] == b"GIF89a") && buf.len() >= 10 {
        let w = u16::from_le_bytes([buf[6], buf[7]]) as u32;
        let h = u16::from_le_bytes([buf[8], buf[9]]) as u32;
        if w > 0 && h > 0 {
            return Ok((w, h));
        }
    }

    // BMP: "BM" + DIB header at offset 14
    if buf.len() >= 26 && &buf[0..2] == b"BM" {
        let dib_size = u32::from_le_bytes([buf[14], buf[15], buf[16], buf[17]]);
        if dib_size == 12 {
            let w = u16::from_le_bytes([buf[18], buf[19]]) as u32;
            let h = u16::from_le_bytes([buf[20], buf[21]]) as u32;
            if w > 0 && h > 0 {
                return Ok((w, h));
            }
        } else if dib_size >= 40 {
            let w = i32::from_le_bytes([buf[18], buf[19], buf[20], buf[21]]).unsigned_abs();
            let h = i32::from_le_bytes([buf[22], buf[23], buf[24], buf[25]]).unsigned_abs();
            if w > 0 && h > 0 {
                return Ok((w, h));
            }
        }
    }

    // WebP: "RIFF" + size(4) + "WEBP" + chunk_fourcc(4) + chunk_size(4) + payload
    if buf.len() >= 30 && &buf[0..4] == b"RIFF" && &buf[8..12] == b"WEBP" {
        let chunk = &buf[12..16];
        if chunk == b"VP8X" {
            let w = 1 + (buf[24] as u32 | ((buf[25] as u32) << 8) | ((buf[26] as u32) << 16));
            let h = 1 + (buf[27] as u32 | ((buf[28] as u32) << 8) | ((buf[29] as u32) << 16));
            if w > 0 && h > 0 {
                return Ok((w, h));
            }
        } else if chunk == b"VP8 " && buf.len() >= 30 && &buf[23..26] == b"\x9d\x01\x2a" {
            let w = (u16::from_le_bytes([buf[26], buf[27]]) & 0x3fff) as u32;
            let h = (u16::from_le_bytes([buf[28], buf[29]]) & 0x3fff) as u32;
            if w > 0 && h > 0 {
                return Ok((w, h));
            }
        } else if chunk == b"VP8L" && buf.len() >= 25 && buf[20] == 0x2f {
            let b0 = buf[21] as u32;
            let b1 = buf[22] as u32;
            let b2 = buf[23] as u32;
            let b3 = buf[24] as u32;
            let bits = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
            let w = (bits & 0x3fff) + 1;
            let h = ((bits >> 14) & 0x3fff) + 1;
            if w > 0 && h > 0 {
                return Ok((w, h));
            }
        }
    }

    // JPEG: FF D8 ... SOF0..SOF15
    if buf[0] == 0xff
        && buf[1] == 0xd8
        && let Some(dims) = parse_jpeg_sof_slice(buf)
    {
        return Ok(dims);
    }

    bail!("unrecognized_image_header")
}

fn is_jpeg_sof_marker(marker: u8) -> bool {
    matches!(
        marker,
        0xc0..=0xc3 | 0xc5..=0xc7 | 0xc9..=0xcb | 0xcd..=0xcf
    )
}

fn parse_jpeg_sof_slice(buf: &[u8]) -> Option<(u32, u32)> {
    let mut i = 2usize;
    while i + 3 < buf.len() {
        if buf[i] != 0xff {
            i += 1;
            continue;
        }
        while i < buf.len() && buf[i] == 0xff {
            i += 1;
        }
        if i >= buf.len() {
            break;
        }
        let marker = buf[i];
        i += 1;
        if marker == 0x00 || marker == 0x01 || (0xd0..=0xd8).contains(&marker) {
            continue;
        }
        if marker == 0xd9 || marker == 0xda {
            break;
        }
        if i + 2 > buf.len() {
            break;
        }
        let seg_len = u16::from_be_bytes([buf[i], buf[i + 1]]) as usize;
        if seg_len < 2 {
            break;
        }
        if is_jpeg_sof_marker(marker) {
            if i + 7 <= buf.len() {
                let h = u16::from_be_bytes([buf[i + 3], buf[i + 4]]) as u32;
                let w = u16::from_be_bytes([buf[i + 5], buf[i + 6]]) as u32;
                if w > 0 && h > 0 {
                    return Some((w, h));
                }
            }
            break;
        }
        i = i.saturating_add(seg_len);
    }
    None
}

fn read_jpeg_dimensions_streaming(path: &Path) -> Result<(u32, u32)> {
    // Fallback for JPEGs with >64 KB EXIF/ICC APP segments before SOF.
    let bytes = fs::read(path)?;
    if bytes.len() >= 4
        && bytes[0] == 0xff
        && bytes[1] == 0xd8
        && let Some(dims) = parse_jpeg_sof_slice(&bytes)
    {
        return Ok(dims);
    }
    bail!("jpeg_sof_not_found")
}

// ---------------------------------------------------------------------------
// 2. Cava Active Stream Resolver + Atomic Byte-Identical Config Writer
//    (100% parity with scripts/cava/resolve_audio_source.py + generate_config.sh)
// ---------------------------------------------------------------------------

const EXCLUDED_APP_NAMES: &[&str] = &[
    "quickshell",
    "discord",
    "vesktop",
    "webrtc",
    "teams",
    "zoom",
    "slack",
    "telegram-desktop",
    "element",
    "speech-dispatcher",
    "speech-dispatcher-dummy",
    "steam voice",
];

const EXCLUDED_BINARIES: &[&str] = &[
    "quickshell",
    "discord",
    "vesktop",
    "teams",
    "zoom",
    "slack",
    "sd_dummy",
];

const EXCLUDED_MEDIA_ROLES: &[&str] = &[
    "communication",
    "phone",
    "notification",
    "alert",
    "game",
    "production",
];

const PREFERRED_PLAYBACK_TOKENS: &[&str] = &[
    "spotify",
    "chromium",
    "chrome",
    "brave",
    "firefox",
    "zen",
    "mpv",
    "mpd",
    "vlc",
    "strawberry",
    "audacious",
    "rhythmbox",
    "clementine",
    "haruna",
];

const DESKTOP_ENTRY_BINARIES: &[(&str, &[&str])] = &[
    ("spotify", &["spotify"]),
    ("mpv", &["mpv"]),
    ("mpd", &["mpd"]),
    ("mpd-mpris", &["mpd"]),
    ("vlc", &["vlc"]),
    ("firefox", &["firefox", "firefox-bin", "zen", "zen-bin"]),
    ("zen", &["zen", "zen-bin", "firefox", "firefox-bin"]),
    ("app.zen_browser.zen", &["zen", "zen-bin", "firefox", "firefox-bin"]),
    ("chromium", &["chromium", "chrome", "brave", "google-chrome", "google-chrome-stable"]),
    ("chrome", &["chrome", "google-chrome", "google-chrome-stable", "brave"]),
    ("google-chrome", &["chrome", "chromium", "google-chrome", "google-chrome-stable"]),
    ("brave", &["brave"]),
    ("brave-browser", &["brave", "chrome", "chromium"]),
    ("org.chromium.chromium", &["chromium", "chrome"]),
    ("com.google.chrome", &["chrome", "google-chrome", "google-chrome-stable"]),
    ("org.mozilla.firefox", &["firefox", "firefox-bin"]),
    ("strawberry", &["strawberry"]),
    ("audacious", &["audacious"]),
    ("deadbeef", &["deadbeef"]),
    ("rhythmbox", &["rhythmbox"]),
    ("clementine", &["clementine"]),
    ("haruna", &["haruna"]),
    ("com.github.thitzekai.mooz", &["mooz"]),
];

fn run_pactl(args: &[&str]) -> Option<String> {
    let out = Command::new("pactl").args(args).output().ok()?;
    if !out.status.success() {
        return None;
    }
    Some(String::from_utf8_lossy(&out.stdout).into_owned())
}

fn default_sink_monitor() -> String {
    if let Some(sink_raw) = run_pactl(&["get-default-sink"]) {
        let sink = sink_raw.trim();
        if !sink.is_empty() {
            return format!("{sink}.monitor");
        }
    }
    "auto".to_string()
}

fn hint_binaries_for_entry(desktop_entry: &str) -> HashSet<String> {
    let entry = desktop_entry.trim().to_ascii_lowercase();
    let mut hints = HashSet::new();
    if entry.is_empty() || entry == "__alis_music_player__" {
        return hints;
    }
    for &(key, bins) in DESKTOP_ENTRY_BINARIES {
        if key.contains(&entry) || entry.contains(key) {
            for &b in bins {
                hints.insert(b.to_string());
            }
        }
    }
    if let Some(base) = entry.rsplit('.').next()
        && !base.is_empty()
        && base != "desktop"
        && base != "client"
    {
        hints.insert(base.to_string());
    }
    if entry.contains("chrom") || entry.contains("brave") {
        for b in ["chromium", "chrome", "google-chrome", "google-chrome-stable", "brave", "electron"] {
            hints.insert(b.to_string());
        }
    }
    if entry.contains("firefox") || entry.contains("zen") {
        hints.insert("firefox".to_string());
        hints.insert("zen".to_string());
    }
    hints
}

fn title_tokens(text: &str) -> HashSet<String> {
    text.to_ascii_lowercase()
        .split(|c: char| !c.is_alphanumeric() && c != '_')
        .filter(|tok| {
            tok.len() >= 2
                && !matches!(
                    *tok,
                    "the" | "and" | "for" | "with" | "official" | "video" | "audio"
                )
        })
        .map(ToOwned::to_owned)
        .collect()
}

#[derive(Default)]
struct SinkStream {
    index: i64,
    node_name: String,
    object_serial: String,
    media_role: String,
    media_name: String,
    app_name: String,
    app_id: String,
    binary: String,
    corked: bool,
    muted: bool,
}

fn is_excluded_stream(st: &SinkStream) -> bool {
    if EXCLUDED_APP_NAMES.iter().any(|t| st.app_name.contains(t)) {
        return true;
    }
    if EXCLUDED_BINARIES.contains(&st.binary.as_str()) {
        return true;
    }
    if EXCLUDED_MEDIA_ROLES.contains(&st.media_role.as_str()) {
        return true;
    }
    if st.app_name.contains("voice") && st.app_name.contains("steam") {
        return true;
    }
    false
}

fn score_sink_stream(st: &SinkStream, hint_binaries: &HashSet<String>, track_title: &str) -> i64 {
    if is_excluded_stream(st) {
        return -10_000;
    }
    if st.corked {
        return -5_000;
    }
    if st.muted {
        return -4_000;
    }

    let mut score = 180i64;
    if st.media_role == "music" {
        score += 120;
    } else if st.media_role == "video" || st.media_role == "multimedia" {
        score += 50;
    } else if !st.media_role.is_empty() {
        score -= 20;
    }

    let node_low = st.node_name.to_ascii_lowercase();
    let identity = format!(
        "{} {} {} {} {}",
        node_low, st.media_name, st.app_name, st.app_id, st.binary
    );
    if !hint_binaries.is_empty() {
        if hint_binaries.contains(&st.binary) {
            score += 500;
        }
        if hint_binaries.contains(&node_low) || hint_binaries.contains(&st.app_id) {
            score += 420;
        }
        if hint_binaries.iter().any(|h| identity.contains(h.as_str())) {
            score += 260;
        }
    }

    let norm_title = track_title.trim().to_ascii_lowercase();
    let media_name = st.media_name.trim();
    if !norm_title.is_empty() && !media_name.is_empty() {
        if media_name.contains(&norm_title)
            || (media_name.len() >= 4 && norm_title.contains(media_name))
        {
            score += 600;
        } else {
            let t_words = title_tokens(&norm_title);
            let m_words = title_tokens(media_name);
            let overlap = t_words.intersection(&m_words).count();
            if overlap >= 2 || (overlap == 1 && t_words.len() == 1) {
                score += 350 + (overlap.min(5) as i64) * 30;
            }
        }
    }
    if media_name.contains("youtube") || media_name.contains("music") || media_name.contains("spotify") {
        score += 60;
    }
    if PREFERRED_PLAYBACK_TOKENS.iter().any(|t| identity.contains(t)) {
        score += 40;
    }
    score
}

pub fn parse_cava_audio_source_from_pactl(
    clients_out: &str,
    sink_inputs_out: &str,
    info_out: &str,
    desktop_entry: &str,
    track_title: &str,
    fallback_sink_from_info: Option<&str>,
) -> String {
    if info_out.trim().is_empty() {
        return "auto".to_string();
    }
    let is_pipewire = info_out.to_ascii_lowercase().contains("pipewire");

    let mut clients: HashMap<String, (String, String)> = HashMap::new();
    let mut cur_client_id: Option<String> = None;
    let mut cur_app_name = String::new();
    let mut cur_binary = String::new();
    for line in clients_out.lines() {
        let trimmed = line.trim();
        if let Some(rest) = trimmed.strip_prefix("Client #") {
            if let Some(prev_id) = cur_client_id.replace(rest.trim().to_string()) {
                clients.insert(prev_id, (cur_app_name.clone(), cur_binary.clone()));
            }
            cur_app_name.clear();
            cur_binary.clear();
            continue;
        }
        if cur_client_id.is_some()
            && let Some((k, v)) = trimmed.split_once(" = \"")
            && let Some(val) = v.strip_suffix('"')
        {
            match k.trim() {
                "application.name" => cur_app_name = val.to_string(),
                "application.process.binary" => cur_binary = val.to_string(),
                _ => {}
            }
        }
    }
    if let Some(last_id) = cur_client_id {
        clients.insert(last_id, (cur_app_name, cur_binary));
    }

    let mut streams: Vec<SinkStream> = Vec::new();
    let mut cur_idx: Option<i64> = None;
    let mut block: HashMap<String, String> = HashMap::new();
    let flush = |idx_opt: &mut Option<i64>,
                 blk: &mut HashMap<String, String>,
                 clients: &HashMap<String, (String, String)>,
                 out: &mut Vec<SinkStream>| {
        let Some(index) = idx_opt.take() else {
            blk.clear();
            return;
        };
        let node_name = blk.get("node.name").cloned().unwrap_or_default();
        if node_name.is_empty() {
            blk.clear();
            return;
        }
        let client_id = blk
            .get("client.id")
            .or_else(|| blk.get("Client"))
            .cloned()
            .unwrap_or_default();
        let (c_app, c_bin) = clients.get(&client_id).cloned().unwrap_or_default();
        let app_name = blk
            .get("application.name")
            .filter(|s| !s.is_empty())
            .cloned()
            .unwrap_or(c_app)
            .to_ascii_lowercase();
        let binary = blk
            .get("application.process.binary")
            .filter(|s| !s.is_empty())
            .cloned()
            .unwrap_or(c_bin)
            .to_ascii_lowercase();
        let app_id = blk
            .get("application.id")
            .or_else(|| blk.get("pipewire.access.portal.app_id"))
            .cloned()
            .unwrap_or_default()
            .to_ascii_lowercase();
        let corked_raw = blk
            .get("Corked")
            .or_else(|| blk.get("pulse.corked"))
            .map(String::as_str)
            .unwrap_or("false");
        let muted_raw = blk.get("Mute").map(String::as_str).unwrap_or("no");
        out.push(SinkStream {
            index,
            node_name,
            object_serial: blk.get("object.serial").cloned().unwrap_or_default(),
            media_role: blk.get("media.role").cloned().unwrap_or_default().to_ascii_lowercase(),
            media_name: blk.get("media.name").cloned().unwrap_or_default().to_ascii_lowercase(),
            app_name,
            app_id,
            binary,
            corked: matches!(corked_raw.to_ascii_lowercase().as_str(), "yes" | "true" | "1"),
            muted: matches!(muted_raw.to_ascii_lowercase().as_str(), "yes" | "true" | "1"),
        });
        blk.clear();
    };

    for line in sink_inputs_out.lines() {
        let trimmed = line.trim();
        if let Some(rest) = trimmed.strip_prefix("Sink Input #")
            && let Ok(idx) = rest.trim().parse::<i64>()
        {
            flush(&mut cur_idx, &mut block, &clients, &mut streams);
            cur_idx = Some(idx);
            continue;
        }
        if cur_idx.is_none() {
            continue;
        }
        if let Some(rest) = trimmed.strip_prefix("Corked:") {
            block.insert("Corked".to_string(), rest.trim().to_string());
            continue;
        }
        if let Some(rest) = trimmed.strip_prefix("Mute:") {
            block.insert("Mute".to_string(), rest.trim().to_string());
            continue;
        }
        if let Some(rest) = trimmed.strip_prefix("Client:") {
            let v = rest.trim();
            if v.bytes().all(|b| b.is_ascii_digit()) {
                block.insert("Client".to_string(), v.to_string());
                continue;
            }
        }
        if let Some((k, v)) = trimmed.split_once(" = \"")
            && let Some(val) = v.strip_suffix('"')
        {
            block.insert(k.trim().to_string(), val.to_string());
        }
    }
    flush(&mut cur_idx, &mut block, &clients, &mut streams);

    let hint_binaries = hint_binaries_for_entry(desktop_entry);
    let mut ranked: Vec<(i64, usize)> = streams
        .iter()
        .enumerate()
        .map(|(i, st)| (score_sink_stream(st, &hint_binaries, track_title), i))
        .collect();
    ranked.sort_by(|a, b| {
        b.0.cmp(&a.0)
            .then_with(|| streams[b.1].index.cmp(&streams[a.1].index))
    });

    for (score, idx) in ranked {
        let st = &streams[idx];
        if score > 0 && !st.node_name.is_empty() {
            if is_pipewire && !st.object_serial.is_empty() {
                return if st.object_serial.ends_with(".monitor") {
                    st.object_serial.clone()
                } else {
                    format!("{}.monitor", st.object_serial)
                };
            }
            return st.node_name.clone();
        }
    }

    if !streams.is_empty() {
        return String::new();
    }

    if let Some(sink) = fallback_sink_from_info {
        let s = sink.trim();
        if !s.is_empty() {
            return format!("{s}.monitor");
        }
    }
    for line in info_out.lines() {
        if let Some(rest) = line.trim().strip_prefix("Default Sink:") {
            let sink = rest.trim();
            if !sink.is_empty() && sink != "@DEFAULT_SINK@" {
                return format!("{sink}.monitor");
            }
        }
    }
    default_sink_monitor()
}

pub fn resolve_cava_audio_source_and_method(
    desktop_entry: &str,
    track_title: &str,
    need_method: bool,
) -> (String, String) {
    let (info_opt, clients_opt, sink_inputs_opt) = std::thread::scope(|s| {
        let i_handle = s.spawn(|| run_pactl(&["info"]));
        let c_handle = s.spawn(|| run_pactl(&["list", "clients"]));
        let si_handle = s.spawn(|| run_pactl(&["list", "sink-inputs"]));
        (
            i_handle.join().ok().flatten(),
            c_handle.join().ok().flatten(),
            si_handle.join().ok().flatten(),
        )
    });
    let info_str = info_opt.unwrap_or_default();
    let method = if need_method && info_str.to_ascii_lowercase().contains("pipewire") {
        "pipewire".to_string()
    } else {
        "pulse".to_string()
    };
    let eff_title = if !track_title.is_empty() {
        track_title.to_string()
    } else {
        env::var("CAVA_TRACK_TITLE").unwrap_or_default()
    };
    let source = parse_cava_audio_source_from_pactl(
        &clients_opt.unwrap_or_default(),
        &sink_inputs_opt.unwrap_or_default(),
        &info_str,
        desktop_entry,
        &eff_title,
        None,
    );
    (source, method)
}

pub fn render_cava_config(
    bars: u32,
    framerate: u32,
    sensitivity: u32,
    stereo: bool,
    method: &str,
    audio_source: &str,
) -> String {
    let channels = if stereo { "stereo" } else { "mono" };
    format!(
        "[general]\n\
         framerate = {framerate}\n\
         sensitivity = {sensitivity}\n\
         autosens = 1\n\
         bars = {bars}\n\
         \n\
         [input]\n\
         method = {method}\n\
         source = {audio_source}\n\
         active = 0\n\
         \n\
         [output]\n\
         method = raw\n\
         raw_target = /dev/stdout\n\
         data_format = ascii\n\
         ascii_max_range = 1000\n\
         bar_delimiter = 59\n\
         channels = {channels}\n\
         mono_option = average\n\
         \n\
         [smoothing]\n\
         noise_reduction = 65\n"
    )
}

pub fn write_file_if_changed_atomic(path: &Path, content: &[u8]) -> Result<bool> {
    if let Ok(existing) = fs::read(path)
        && existing == content
    {
        return Ok(false);
    }
    if let Some(parent) = path.parent()
        && !parent.as_os_str().is_empty()
    {
        fs::create_dir_all(parent)?;
    }
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let fname = path
        .file_name()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_else(|| "cava.conf".to_string());
    let tmp = path.with_file_name(format!(".{fname}.tmp.{}.{nanos}", std::process::id()));
    {
        let mut f = File::create(&tmp)?;
        f.write_all(content)?;
    }
    fs::rename(&tmp, path).inspect_err(|_| {
        let _ = fs::remove_file(&tmp);
    })?;
    Ok(true)
}

// ---------------------------------------------------------------------------
// 3. Fast XDG .desktop Scanner + Bitmask/Prefix/Fuzzy Scorer (inir-accel+)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NativeAppEntry {
    pub id: String,
    pub name: String,
    pub generic_name: String,
    pub comment: String,
    pub icon: String,
    pub exec: String,
    pub categories: Vec<String>,
    pub keywords: Vec<String>,
    #[serde(skip_serializing)]
    name_lower: String,
    #[serde(skip_serializing)]
    id_lower: String,
    #[serde(skip_serializing)]
    keywords_lower: String,
    #[serde(skip_serializing)]
    generic_lower: String,
    #[serde(skip_serializing)]
    comment_lower: String,
    #[serde(skip_serializing)]
    acronym: String,
    #[serde(skip_serializing)]
    char_mask: u32,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ScoredAppEntry {
    #[serde(flatten)]
    pub entry: NativeAppEntry,
    pub score: f64,
}

#[inline]
pub fn ascii_alpha_mask(s: &str) -> u32 {
    let mut mask = 0u32;
    for b in s.bytes() {
        let lower = b.to_ascii_lowercase();
        if lower.is_ascii_lowercase() {
            mask |= 1u32 << (lower - b'a');
        }
    }
    mask
}

fn build_acronym(name_lower: &str) -> String {
    let mut out = String::new();
    let mut prev_sep = true;
    for ch in name_lower.chars() {
        if ch.is_alphanumeric() {
            if prev_sep {
                out.push(ch);
            }
            prev_sep = false;
        } else {
            prev_sep = true;
        }
    }
    out
}

fn desktop_search_dirs() -> Vec<PathBuf> {
    let mut dirs = Vec::new();
    let mut seen = HashSet::new();
    let mut push_unique = |p: PathBuf| {
        if seen.insert(p.clone()) {
            dirs.push(p);
        }
    };

    if let Ok(data_home) = env::var("XDG_DATA_HOME") {
        if !data_home.trim().is_empty() {
            push_unique(PathBuf::from(data_home).join("applications"));
        }
    } else if let Ok(home) = env::var("HOME") {
        push_unique(PathBuf::from(&home).join(".local/share/applications"));
        push_unique(PathBuf::from(&home).join(".local/share/flatpak/exports/share/applications"));
    }

    if let Ok(data_dirs) = env::var("XDG_DATA_DIRS") {
        for part in data_dirs.split(':').filter(|s| !s.trim().is_empty()) {
            push_unique(PathBuf::from(part).join("applications"));
        }
    } else {
        push_unique(PathBuf::from("/var/lib/flatpak/exports/share/applications"));
        push_unique(PathBuf::from("/usr/local/share/applications"));
        push_unique(PathBuf::from("/usr/share/applications"));
        push_unique(PathBuf::from("/var/lib/snapd/desktop/applications"));
    }
    dirs
}

pub fn parse_desktop_file(path: &Path, desktop_id: &str) -> Option<NativeAppEntry> {
    let raw = fs::read_to_string(path).ok()?;
    let mut in_entry = false;
    let mut entry_type = String::new();
    let mut hidden = false;
    let mut no_display = false;
    let mut name = String::new();
    let mut generic_name = String::new();
    let mut comment = String::new();
    let mut icon = String::new();
    let mut exec = String::new();
    let mut categories = Vec::new();
    let mut keywords = Vec::new();

    for line in raw.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        if trimmed.starts_with('[') && trimmed.ends_with(']') {
            if trimmed == "[Desktop Entry]" {
                in_entry = true;
                continue;
            } else if in_entry {
                break;
            } else {
                continue;
            }
        }
        if !in_entry {
            continue;
        }
        let Some((raw_key, raw_val)) = trimmed.split_once('=') else {
            continue;
        };
        let key = raw_key.trim();
        if key.contains('[') {
            continue;
        }
        let val = raw_val.trim();
        match key {
            "Type" => entry_type = val.to_string(),
            "Hidden" => hidden = val.eq_ignore_ascii_case("true"),
            "NoDisplay" => no_display = val.eq_ignore_ascii_case("true"),
            "Name" => name = val.to_string(),
            "GenericName" => generic_name = val.to_string(),
            "Comment" => comment = val.to_string(),
            "Icon" => icon = val.to_string(),
            "Exec" => exec = val.to_string(),
            "Categories" => {
                categories = val
                    .split(';')
                    .map(str::trim)
                    .filter(|s| !s.is_empty())
                    .map(ToOwned::to_owned)
                    .collect();
            }
            "Keywords" => {
                keywords = val
                    .split(';')
                    .map(str::trim)
                    .filter(|s| !s.is_empty())
                    .map(ToOwned::to_owned)
                    .collect();
            }
            _ => {}
        }
    }

    if hidden || no_display || name.is_empty() {
        return None;
    }
    if !entry_type.is_empty() && entry_type != "Application" {
        return None;
    }

    let name_lower = name.to_ascii_lowercase();
    let id_lower = desktop_id.trim_end_matches(".desktop").to_ascii_lowercase();
    let keywords_lower = keywords.join(" ").to_ascii_lowercase();
    let generic_lower = generic_name.to_ascii_lowercase();
    let comment_lower = comment.to_ascii_lowercase();
    let acronym = build_acronym(&name_lower);
    let char_mask = ascii_alpha_mask(&name_lower)
        | ascii_alpha_mask(&id_lower)
        | ascii_alpha_mask(&keywords_lower)
        | ascii_alpha_mask(&generic_lower)
        | ascii_alpha_mask(&comment_lower);

    Some(NativeAppEntry {
        id: desktop_id.trim_end_matches(".desktop").to_string(),
        name,
        generic_name,
        comment,
        icon,
        exec,
        categories,
        keywords,
        name_lower,
        id_lower,
        keywords_lower,
        generic_lower,
        comment_lower,
        acronym,
        char_mask,
    })
}

pub fn scan_desktop_entries() -> Vec<NativeAppEntry> {
    let mut seen_ids = HashSet::new();
    let mut entries = Vec::new();
    for dir in desktop_search_dirs() {
        let Ok(rd) = fs::read_dir(&dir) else {
            continue;
        };
        let mut paths: Vec<PathBuf> = rd.flatten().map(|e| e.path()).collect();
        paths.sort();
        for p in paths {
            if p.extension().and_then(|s| s.to_str()) != Some("desktop") {
                continue;
            }
            let Some(fname) = p.file_name().and_then(|s| s.to_str()) else {
                continue;
            };
            if !seen_ids.insert(fname.to_string()) {
                // Check if user override explicitly hides a system desktop file
                continue;
            }
            if let Some(parsed) = parse_desktop_file(&p, fname) {
                entries.push(parsed);
            }
        }
    }
    entries.sort_by(|a, b| a.name_lower.cmp(&b.name_lower));
    entries
}

fn subsequence_score(haystack: &str, needle: &str) -> f64 {
    if needle.is_empty() {
        return 1.0;
    }
    let hb = haystack.as_bytes();
    let nb = needle.as_bytes();
    if hb.len() < nb.len() {
        return 0.0;
    }
    let mut hi = 0usize;
    let mut ni = 0usize;
    let mut consecutive = 0usize;
    let mut bonus = 0.0f64;
    while hi < hb.len() && ni < nb.len() {
        if hb[hi] == nb[ni] {
            let at_boundary = hi == 0 || matches!(hb[hi - 1], b' ' | b'-' | b'_' | b'.');
            if at_boundary {
                bonus += 0.18;
            }
            consecutive += 1;
            bonus += (consecutive as f64) * 0.04;
            ni += 1;
        } else {
            consecutive = 0;
        }
        hi += 1;
    }
    if ni < nb.len() {
        return 0.0;
    }
    let density = (nb.len() as f64) / (hb.len() as f64);
    (0.35 + density * 0.35 + bonus).min(0.96)
}

fn bounded_edit_similarity(a: &str, b: &str) -> f64 {
    let ab = a.as_bytes();
    let bb = b.as_bytes();
    if ab.is_empty() || bb.is_empty() {
        return 0.0;
    }
    let m = ab.len().min(48);
    let n = bb.len().min(48);
    let mut prev: Vec<usize> = (0..=n).collect();
    let mut curr = vec![0usize; n + 1];
    for i in 1..=m {
        curr[0] = i;
        for j in 1..=n {
            let cost = usize::from(ab[i - 1] != bb[j - 1]);
            curr[j] = (prev[j] + 1).min(curr[j - 1] + 1).min(prev[j - 1] + cost);
        }
        std::mem::swap(&mut prev, &mut curr);
    }
    let max_len = m.max(n) as f64;
    1.0 - (prev[n] as f64 / max_len)
}

pub fn score_desktop_entry(entry: &NativeAppEntry, q_lower: &str, q_mask: u32, sloppy: bool) -> f64 {
    if !sloppy && (entry.char_mask & q_mask) != q_mask {
        return 0.0;
    }
    if entry.name_lower == q_lower || entry.id_lower == q_lower {
        return 10.0;
    }
    if entry.name_lower.starts_with(q_lower) {
        return 8.5 + (q_lower.len() as f64 / entry.name_lower.len().max(1) as f64);
    }
    if !entry.acronym.is_empty() && entry.acronym.starts_with(q_lower) {
        return 7.8;
    }
    if entry
        .name_lower
        .split(|c: char| !c.is_alphanumeric())
        .any(|w| w.starts_with(q_lower))
    {
        return 7.2;
    }
    if entry.name_lower.contains(q_lower) {
        return 6.0;
    }
    if entry.id_lower.contains(q_lower) || entry.keywords_lower.contains(q_lower) {
        return 4.8;
    }
    if entry.generic_lower.contains(q_lower) || entry.comment_lower.contains(q_lower) {
        return 3.5;
    }

    if sloppy {
        let sim = bounded_edit_similarity(&entry.name_lower, q_lower);
        return if sim >= 0.45 { sim * 4.0 } else { 0.0 };
    }

    let sub = subsequence_score(&entry.name_lower, q_lower)
        .max(subsequence_score(&entry.id_lower, q_lower) * 0.85)
        .max(subsequence_score(&entry.keywords_lower, q_lower) * 0.75);
    if sub > 0.0 {
        sub * 3.0
    } else {
        0.0
    }
}

pub fn query_desktop_entries(
    entries: &[NativeAppEntry],
    query: &str,
    limit: usize,
    sloppy: bool,
) -> Vec<ScoredAppEntry> {
    let q_lower = query.trim().to_ascii_lowercase();
    if q_lower.is_empty() {
        return entries
            .iter()
            .take(limit)
            .cloned()
            .map(|entry| ScoredAppEntry { entry, score: 1.0 })
            .collect();
    }
    let q_mask = ascii_alpha_mask(&q_lower);
    let mut scored: Vec<ScoredAppEntry> = entries
        .iter()
        .filter_map(|e| {
            let s = score_desktop_entry(e, &q_lower, q_mask, sloppy);
            (s > 0.0).then(|| ScoredAppEntry {
                entry: e.clone(),
                score: s,
            })
        })
        .collect();
    scored.sort_by(|a, b| {
        b.score
            .partial_cmp(&a.score)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| a.entry.name_lower.cmp(&b.entry.name_lower))
    });
    scored.truncate(limit);
    scored
}

// ---------------------------------------------------------------------------
// 4. Freedesktop RFC 1321 MD5 Thumbnail Lookup (inir-accel thumbgen parity)
// ---------------------------------------------------------------------------

pub fn md5_hex(data: &[u8]) -> String {
    const S: [u32; 64] = [
        7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
        5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
        4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
        6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
    ];
    const K: [u32; 64] = [
        0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
        0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
        0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
        0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
        0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
        0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
        0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
        0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
        0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
        0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
        0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
        0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
        0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
        0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
        0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
        0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
    ];

    let bit_len = (data.len() as u64).wrapping_mul(8);
    let mut msg = data.to_vec();
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
        for (i, word) in m.iter_mut().enumerate() {
            let base = i * 4;
            *word = u32::from_le_bytes([chunk[base], chunk[base + 1], chunk[base + 2], chunk[base + 3]]);
        }
        let mut a = a0;
        let mut b = b0;
        let mut c = c0;
        let mut d = d0;
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
            b = b.wrapping_add(a.wrapping_add(f).wrapping_add(K[i]).wrapping_add(m[g]).rotate_left(S[i]));
            a = temp;
        }
        a0 = a0.wrapping_add(a);
        b0 = b0.wrapping_add(b);
        c0 = c0.wrapping_add(c);
        d0 = d0.wrapping_add(d);
    }

    let mut digest = [0u8; 16];
    digest[0..4].copy_from_slice(&a0.to_le_bytes());
    digest[4..8].copy_from_slice(&b0.to_le_bytes());
    digest[8..12].copy_from_slice(&c0.to_le_bytes());
    digest[12..16].copy_from_slice(&d0.to_le_bytes());

    let mut out = String::with_capacity(32);
    for byte in digest {
        out.push_str(&format!("{byte:02x}"));
    }
    out
}

pub fn canonical_file_uri(path: &Path) -> String {
    use std::os::unix::ffi::OsStrExt;
    let resolved = fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf());
    let bytes = resolved.as_os_str().as_bytes();
    let mut uri = String::with_capacity(7 + bytes.len());
    uri.push_str("file://");
    for &b in bytes {
        let unreserved = b.is_ascii_alphanumeric()
            || matches!(
                b,
                b'/' | b'-' | b'_' | b'.' | b'~' | b':' | b'@' | b'!' | b'$' | b'&' | b'\'' | b'(' | b')' | b'*' | b'+' | b',' | b';' | b'='
            );
        if unreserved {
            uri.push(b as char);
        } else {
            uri.push_str(&format!("%{b:02X}"));
        }
    }
    uri
}

fn inspect_thumbnail_and_dimensions(raw_path: &str, size_bucket: &str) -> Result<Value> {
    let clean = strip_file_uri(raw_path);
    let path = Path::new(clean);
    let uri = canonical_file_uri(path);
    let md5 = md5_hex(uri.as_bytes());
    let bucket = match size_bucket {
        "normal" | "large" | "x-large" | "xx-large" => size_bucket,
        _ => "large",
    };
    let cache_base = env::var("XDG_CACHE_HOME")
        .ok()
        .filter(|s| !s.trim().is_empty())
        .map(PathBuf::from)
        .or_else(|| env::var("HOME").ok().map(|h| PathBuf::from(h).join(".cache")))
        .unwrap_or_else(|| PathBuf::from("/tmp"));
    let thumb_path = cache_base
        .join("thumbnails")
        .join(bucket)
        .join(format!("{md5}.png"));
    let dims = read_image_dimensions(path).ok();
    Ok(json!({
        "uri": uri,
        "md5": md5,
        "thumbnailPath": thumb_path.to_string_lossy(),
        "thumbnailExists": thumb_path.is_file(),
        "width": dims.map(|d| d.0).unwrap_or(0),
        "height": dims.map(|d| d.1).unwrap_or(0),
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_png_gif_bmp_webp_jpeg_header_dimensions() {
        // PNG 1920x1080
        let mut png = b"\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR".to_vec();
        png.extend_from_slice(&1920u32.to_be_bytes());
        png.extend_from_slice(&1080u32.to_be_bytes());
        png.extend_from_slice(&[8, 6, 0, 0, 0]);
        assert_eq!(parse_image_dimensions_from_bytes(&png).unwrap(), (1920, 1080));

        // GIF 640x480
        let mut gif = b"GIF89a".to_vec();
        gif.extend_from_slice(&640u16.to_le_bytes());
        gif.extend_from_slice(&480u16.to_le_bytes());
        assert_eq!(parse_image_dimensions_from_bytes(&gif).unwrap(), (640, 480));

        // BMP 2560x1440 (top-down negative height)
        let mut bmp = vec![0u8; 30];
        bmp[0..2].copy_from_slice(b"BM");
        bmp[14..18].copy_from_slice(&40u32.to_le_bytes());
        bmp[18..22].copy_from_slice(&2560i32.to_le_bytes());
        bmp[22..26].copy_from_slice(&(-1440i32).to_le_bytes());
        assert_eq!(parse_image_dimensions_from_bytes(&bmp).unwrap(), (2560, 1440));

        // WebP VP8X 3840x2160
        let mut webp = b"RIFF\x24\x00\x00\x00WEBPVP8X\x0a\x00\x00\x00\x00\x00\x00\x00".to_vec();
        let wm1 = 3840u32 - 1;
        let hm1 = 2160u32 - 1;
        webp.extend_from_slice(&[wm1 as u8, (wm1 >> 8) as u8, (wm1 >> 16) as u8]);
        webp.extend_from_slice(&[hm1 as u8, (hm1 >> 8) as u8, (hm1 >> 16) as u8]);
        assert_eq!(parse_image_dimensions_from_bytes(&webp).unwrap(), (3840, 2160));

        // JPEG with APP1 EXIF segment skipped before SOF2 (progressive 3440x1440)
        let mut jpeg = vec![0xff, 0xd8, 0xff, 0xe1, 0x00, 0x08, 1, 2, 3, 4, 5, 6];
        jpeg.extend_from_slice(&[0xff, 0xc2, 0x00, 0x11, 0x08]);
        jpeg.extend_from_slice(&1440u16.to_be_bytes());
        jpeg.extend_from_slice(&3440u16.to_be_bytes());
        jpeg.extend_from_slice(&[0; 10]);
        assert_eq!(parse_image_dimensions_from_bytes(&jpeg).unwrap(), (3440, 1440));
    }

    #[test]
    fn test_rfc1321_md5_vectors() {
        assert_eq!(md5_hex(b""), "d41d8cd98f00b204e9800998ecf8427e");
        assert_eq!(md5_hex(b"abc"), "900150983cd24fb0d6963f7d28e17f72");
        assert_eq!(md5_hex(b"message digest"), "f96b697d7cb7938d525a2f31aaf161d0");
    }

    #[test]
    fn test_cava_audio_source_resolution_parity() {
        let clients = "\
Client #41
\tDriver: PipeWire
\tProperties:
\t\tapplication.name = \"MPD\"
\t\tapplication.process.binary = \"mpd\"
Client #77
\tDriver: PipeWire
\tProperties:
\t\tapplication.name = \"Firefox\"
\t\tapplication.process.binary = \"firefox\"
";
        let sink_inputs = "\
Sink Input #101
\tCorked: no
\tClient: 41
\tProperties:
\t\tnode.name = \"Music Player Daemon\"
\t\tobject.serial = \"912\"
Sink Input #102
\tCorked: no
\tClient: 77
\tProperties:
\t\tmedia.role = \"Music\"
\t\tnode.name = \"Firefox\"
\t\tobject.serial = \"1048\"
Sink Input #103
\tCorked: no
\tProperties:
\t\tmedia.role = \"Notification\"
\t\tnode.name = \"bell\"
";
        let info = "Server Name: PulseAudio (on PipeWire 1.2.7)\nDefault Sink: alsa_output.pci-0000_00_1f.3.analog-stereo\n";
        assert_eq!(
            parse_cava_audio_source_from_pactl(clients, sink_inputs, info, "firefox", "", None),
            "1048.monitor"
        );
        assert_eq!(
            parse_cava_audio_source_from_pactl("", "", info, "", "", Some("alsa_output.pci-0000_00_1f.3.analog-stereo")),
            "alsa_output.pci-0000_00_1f.3.analog-stereo.monitor"
        );
    }

    #[test]
    fn test_app_search_bitmask_and_acronym() {
        let dir = std::env::temp_dir().join(format!("alis-accel-test-{}", std::process::id()));
        let _ = fs::create_dir_all(&dir);
        let desktop_file = dir.join("org.mozilla.firefox.desktop");
        fs::write(
            &desktop_file,
            "[Desktop Entry]\nType=Application\nName=Firefox Web Browser\nKeywords=internet;www;\nExec=firefox %u\nIcon=firefox\n",
        )
        .unwrap();
        let entry = parse_desktop_file(&desktop_file, "org.mozilla.firefox.desktop").unwrap();
        let _ = fs::remove_dir_all(&dir);

        let apps = vec![entry];
        assert_eq!(query_desktop_entries(&apps, "fwb", 10, false).len(), 1);
        assert_eq!(query_desktop_entries(&apps, "fire", 10, false)[0].entry.id, "org.mozilla.firefox");
        assert!(query_desktop_entries(&apps, "zzzzzz", 10, false).is_empty());
    }
}
