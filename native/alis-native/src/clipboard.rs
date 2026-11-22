use std::collections::{HashMap, HashSet, VecDeque};
use std::fs;
use std::io::{self, BufRead, BufReader, Read, Write};
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd};
use std::path::{Path, PathBuf};
use std::process::{Command as ProcessCommand, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, LazyLock};
use std::time::{Duration, Instant};

use alis_wayland::{WlConnection, WlReader, WlWriter};
use anyhow::{Context, Result, anyhow, bail};
use clap::{Args, Subcommand};
use regex::Regex;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

const HTML_PAYLOAD_PREFIX: &[u8] = b"<meta http-equiv=\"content-type\" content=\"text/html";
const HTML_FRAGMENT_MARKER: &[u8] = b"<!--StartFragment-->";

// ext_data_control_v1 and zwlr_data_control_v1 share identical opcodes:
const DC_MGR_CREATE_SOURCE: u16 = 0;
const DC_MGR_GET_DEVICE: u16 = 1;
const DC_DEV_SET_SELECTION: u16 = 0;
const DC_DEV_SET_PRIMARY_SELECTION: u16 = 2;
const DC_DEV_EV_DATA_OFFER: u16 = 0;
const DC_DEV_EV_SELECTION: u16 = 1;
const DC_DEV_EV_FINISHED: u16 = 2;
const DC_DEV_EV_PRIMARY_SELECTION: u16 = 3;
const DC_SRC_OFFER: u16 = 0;
const DC_SRC_DESTROY: u16 = 1;
const DC_SRC_EV_SEND: u16 = 0;
const DC_SRC_EV_CANCELLED: u16 = 1;
const DC_OFFER_RECEIVE: u16 = 0;
const DC_OFFER_DESTROY: u16 = 1;
const DC_OFFER_EV_OFFER: u16 = 0;

static STOP_REQUESTED: AtomicBool = AtomicBool::new(false);

extern "C" fn handle_signal(_sig: libc::c_int) {
    STOP_REQUESTED.store(true, Ordering::SeqCst);
}

#[derive(Debug, Subcommand)]
pub enum ClipboardCommand {
    /// Copy text or stdin bytes to Wayland clipboard (replaces wl-copy).
    Copy(CopyArgs),
    /// Internal foreground selection server used by copy.
    #[command(hide = true)]
    Serve {
        #[arg(long)]
        mime: String,
        #[arg(long)]
        primary: bool,
        #[arg(long)]
        data_file: PathBuf,
        #[arg(long)]
        signal_ready: bool,
    },
    /// Read current Wayland clipboard selection (replaces wl-paste).
    Paste(PasteArgs),
    /// Watch Wayland clipboard selections and store deduplicated history (replaces wl-paste --watch + cliphist).
    Watch {
        #[arg(long, default_value_t = 400)]
        max_entries: usize,
    },
    /// Store stdin payload directly into Alis clipboard history.
    Store {
        #[arg(long)]
        mime: Option<String>,
        #[arg(long, default_value_t = 400)]
        max_entries: usize,
    },
    /// List stored clipboard history entries as "ID\tPREVIEW".
    List {
        #[arg(long, default_value_t = 400)]
        limit: usize,
    },
    /// Decode entry ID (or line read from stdin) to stdout.
    Decode {
        id: Option<String>,
    },
    /// Delete entry ID (or line read from stdin) from clipboard history.
    Delete {
        id: Option<String>,
    },
    /// Wipe all stored clipboard history entries.
    Wipe,
}

#[derive(Debug, Args)]
pub struct CopyArgs {
    /// MIME type to advertise (default: text/plain;charset=utf-8).
    #[arg(short = 't', long = "type")]
    pub mime: Option<String>,

    /// Set primary selection instead of regular clipboard.
    #[arg(short = 'p', long = "primary")]
    pub primary: bool,

    /// Clear clipboard selection instead of setting content.
    #[arg(short = 'c', long = "clear")]
    pub clear: bool,

    /// Stay in foreground instead of detaching a background selection holder.
    #[arg(short = 'f', long = "foreground")]
    pub foreground: bool,

    /// Optional text arguments to copy (reads stdin if omitted).
    #[arg(trailing_var_arg = true)]
    pub text: Vec<String>,
}

#[derive(Debug, Args)]
pub struct PasteArgs {
    /// Preferred MIME type.
    #[arg(short = 't', long = "type")]
    pub mime: Option<String>,

    /// Read primary selection.
    #[arg(short = 'p', long = "primary")]
    pub primary: bool,

    /// Strip trailing newline (for compatibility with wl-paste -n/--no-newline).
    #[arg(short = 'n', long = "no-newline")]
    pub no_newline: bool,

    /// Print offered MIME types one per line.
    #[arg(short = 'l', long = "list-types")]
    pub list_types: bool,
}

fn is_browser_markup(payload: &[u8]) -> bool {
    payload.starts_with(HTML_PAYLOAD_PREFIX)
        || payload
            .windows(HTML_FRAGMENT_MARKER.len())
            .any(|window| window == HTML_FRAGMENT_MARKER)
}

static META_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^<meta[^>]*>").expect("clipboard meta regex"));
static SCRIPT_STYLE_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?is)<(script|style)\b.*?</(?:script|style)>")
        .expect("clipboard script/style regex")
});
static COMMENT_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?s)<!--.*?-->").expect("clipboard comment regex"));
static BR_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?i)<br\s*/?>").expect("clipboard br regex"));
static BLOCK_END_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)</(?:p|div|li|tr|h[1-6]|blockquote|pre)>").expect("clipboard block-end regex")
});
static IMG_SRC_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r#"(?i)<img[^>]*\bsrc=["']([^"']+)["'][^>]*>"#).expect("clipboard image regex")
});
static TAG_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"<[^>]+>").expect("clipboard tag regex"));
static TRAILING_SPACE_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"[ \t]+\n").expect("clipboard whitespace regex"));
static EXTRA_NEWLINE_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"\n{3,}").expect("clipboard newline regex"));

fn replace(regex: &Regex, input: &str, replacement: &str) -> String {
    regex.replace_all(input, replacement).into_owned()
}

pub fn strip_browser_markup(markup: &str) -> String {
    let text = replace(&META_RE, markup, "");
    let text = replace(&SCRIPT_STYLE_RE, &text, "");
    let text = replace(&COMMENT_RE, &text, "");
    let text = replace(&BR_RE, &text, "\n");
    let text = replace(&BLOCK_END_RE, &text, "\n");
    let text = replace(&IMG_SRC_RE, &text, "$1");
    let text = replace(&TAG_RE, &text, "");
    let text = html_escape::decode_html_entities(&text).into_owned();
    let text = replace(&TRAILING_SPACE_RE, &text, "\n");
    replace(&EXTRA_NEWLINE_RE, &text, "\n\n").trim().to_owned()
}

pub fn sanitize_payload(payload: Vec<u8>) -> Vec<u8> {
    if !is_browser_markup(&payload) {
        return payload;
    }
    strip_browser_markup(&String::from_utf8_lossy(&payload)).into_bytes()
}

// ---------------------------------------------------------------------------
// Native Clipboard History Store ($XDG_CACHE_HOME/alis/clipboard/)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
struct StoreIndex {
    next_id: u64,
    entries: Vec<StoreEntry>,
}

impl Default for StoreIndex {
    fn default() -> Self {
        Self {
            next_id: 1,
            entries: Vec::new(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct StoreEntry {
    id: u64,
    sha256: String,
    mime: String,
    size: usize,
    preview: String,
}

fn store_dir() -> PathBuf {
    if let Some(override_dir) = std::env::var_os("ALIS_CLIPBOARD_STORE_DIR") {
        return PathBuf::from(override_dir);
    }
    let cache = std::env::var_os("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            std::env::var_os("HOME")
                .map(PathBuf::from)
                .unwrap_or_else(|| PathBuf::from("/"))
                .join(".cache")
        });
    cache.join("alis").join("clipboard")
}

fn index_path(dir: &Path) -> PathBuf {
    dir.join("index.json")
}

fn entry_blob_path(dir: &Path, id: u64) -> PathBuf {
    dir.join(format!("{id}.bin"))
}

fn load_index(dir: &Path) -> StoreIndex {
    fs::read_to_string(index_path(dir))
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}

fn save_index(dir: &Path, index: &StoreIndex) -> Result<()> {
    fs::create_dir_all(dir)?;
    let tmp = dir.join(format!(".index-{}.tmp", std::process::id()));
    let json = serde_json::to_string_pretty(index)?;
    fs::write(&tmp, json)?;
    fs::rename(&tmp, index_path(dir))?;
    Ok(())
}

type DetectedImageMeta = (&'static str, &'static str, Option<(u32, u32)>);

fn detect_image_meta(payload: &[u8]) -> Option<DetectedImageMeta> {
    if payload.len() >= 24 && payload.starts_with(&[0x89, b'P', b'N', b'G', 0x0d, 0x0a, 0x1a, 0x0a]) {
        let w = u32::from_be_bytes(payload[16..20].try_into().ok()?);
        let h = u32::from_be_bytes(payload[20..24].try_into().ok()?);
        return Some(("image/png", "png", Some((w, h))));
    }
    if payload.len() >= 3 && payload[0] == 0xff && payload[1] == 0xd8 && payload[2] == 0xff {
        let dims = image::load_from_memory(payload).ok().map(|i| (i.width(), i.height()));
        return Some(("image/jpeg", "jpeg", dims));
    }
    if payload.len() >= 12 && &payload[0..4] == b"RIFF" && &payload[8..12] == b"WEBP" {
        let dims = image::load_from_memory(payload).ok().map(|i| (i.width(), i.height()));
        return Some(("image/webp", "webp", dims));
    }
    if payload.len() >= 10 && (payload.starts_with(b"GIF87a") || payload.starts_with(b"GIF89a")) {
        let w = u16::from_le_bytes(payload[6..8].try_into().ok()?) as u32;
        let h = u16::from_le_bytes(payload[8..10].try_into().ok()?) as u32;
        return Some(("image/gif", "gif", Some((w, h))));
    }
    if payload.len() >= 26 && payload.starts_with(b"BM") {
        let w = i32::from_le_bytes(payload[18..22].try_into().ok()?).unsigned_abs();
        let h = i32::from_le_bytes(payload[22..26].try_into().ok()?).unsigned_abs();
        return Some(("image/bmp", "bmp", Some((w, h))));
    }
    None
}

fn format_size(bytes: usize) -> String {
    if bytes >= 1024 * 1024 {
        format!("{:.1} MiB", bytes as f64 / (1024.0 * 1024.0))
    } else if bytes >= 1024 {
        format!("{} KiB", bytes / 1024)
    } else {
        format!("{bytes} B")
    }
}

fn build_preview(payload: &[u8], mime_hint: Option<&str>) -> (String, String) {
    if let Some((mime, ext, dims)) = detect_image_meta(payload) {
        let dim_str = dims
            .map(|(w, h)| format!(" {w}x{h}"))
            .unwrap_or_default();
        return (
            mime.to_string(),
            format!("[[ binary data {} {ext}{dim_str} ]]", format_size(payload.len())),
        );
    }
    if let Some(m) = mime_hint
        && m.starts_with("image/")
    {
        let ext = m.trim_start_matches("image/");
        return (
            m.to_string(),
            format!("[[ binary data {} {ext} ]]", format_size(payload.len())),
        );
    }
    let text = String::from_utf8_lossy(payload);
    let collapsed = text.split_whitespace().collect::<Vec<_>>().join(" ");
    let preview: String = collapsed.chars().take(100).collect();
    (
        mime_hint
            .unwrap_or("text/plain;charset=utf-8")
            .to_string(),
        preview,
    )
}

fn sha256_hex(data: &[u8]) -> String {
    let digest = Sha256::digest(data);
    let mut out = String::with_capacity(64);
    for b in digest {
        out.push_str(&format!("{b:02x}"));
    }
    out
}

pub fn store_native_entry(payload: Vec<u8>, mime_hint: Option<&str>, max_entries: usize) -> Result<()> {
    let payload = if mime_hint.is_some_and(|m| m.starts_with("image/")) {
        payload
    } else {
        sanitize_payload(payload)
    };
    if payload.is_empty() {
        return Ok(());
    }
    // Skip whitespace-only text entries
    if detect_image_meta(&payload).is_none()
        && !mime_hint.is_some_and(|m| m.starts_with("image/"))
        && String::from_utf8_lossy(&payload).trim().is_empty()
    {
        return Ok(());
    }

    let dir = store_dir();
    fs::create_dir_all(&dir)?;
    let mut index = load_index(&dir);
    let hash = sha256_hex(&payload);

    // Move duplicate to top instead of creating duplicate history rows
    if let Some(pos) = index.entries.iter().position(|e| e.sha256 == hash) {
        let existing = index.entries.remove(pos);
        index.entries.insert(0, existing);
        save_index(&dir, &index)?;
        return Ok(());
    }

    let id = index.next_id;
    index.next_id += 1;
    let (mime, preview) = build_preview(&payload, mime_hint);
    fs::write(entry_blob_path(&dir, id), &payload)?;
    index.entries.insert(
        0,
        StoreEntry {
            id,
            sha256: hash,
            mime,
            size: payload.len(),
            preview,
        },
    );

    let cap = max_entries.clamp(10, 5000);
    while index.entries.len() > cap {
        if let Some(removed) = index.entries.pop() {
            let _ = fs::remove_file(entry_blob_path(&dir, removed.id));
        }
    }
    save_index(&dir, &index)?;
    Ok(())
}

fn parse_entry_id(raw: &str) -> Result<u64> {
    let trimmed = raw.trim();
    let digits: String = trimmed.chars().take_while(|c| c.is_ascii_digit()).collect();
    if digits.is_empty() {
        bail!("invalid clipboard entry id: {raw}");
    }
    Ok(digits.parse()?)
}

fn read_id_or_stdin(id_opt: Option<String>) -> Result<u64> {
    if let Some(id_str) = id_opt {
        return parse_entry_id(&id_str);
    }
    let mut buf = String::new();
    io::stdin().read_to_string(&mut buf)?;
    parse_entry_id(&buf)
}

fn run_list(limit: usize) -> Result<i32> {
    let dir = store_dir();
    let index = load_index(&dir);
    let stdout = io::stdout();
    let mut out = io::BufWriter::new(stdout.lock());
    let mut seen_hashes = HashSet::new();
    let mut count = 0usize;
    for entry in &index.entries {
        if count >= limit {
            break;
        }
        if !seen_hashes.insert(entry.sha256.clone()) {
            continue;
        }
        writeln!(out, "{}\t{}", entry.id, entry.preview)?;
        count += 1;
    }
    out.flush()?;
    Ok(0)
}

fn run_decode(id_opt: Option<String>) -> Result<i32> {
    let id = read_id_or_stdin(id_opt)?;
    let dir = store_dir();
    let blob = fs::read(entry_blob_path(&dir, id))
        .with_context(|| format!("clipboard entry {id} not found"))?;
    let filtered = if detect_image_meta(&blob).is_some() {
        blob
    } else {
        sanitize_payload(blob)
    };
    io::stdout().write_all(&filtered)?;
    Ok(0)
}

fn run_delete(id_opt: Option<String>) -> Result<i32> {
    let id = read_id_or_stdin(id_opt)?;
    let dir = store_dir();
    let mut index = load_index(&dir);
    index.entries.retain(|e| e.id != id);
    let _ = fs::remove_file(entry_blob_path(&dir, id));
    save_index(&dir, &index)?;
    Ok(0)
}

fn run_wipe() -> Result<i32> {
    let dir = store_dir();
    if dir.is_dir() {
        for entry in fs::read_dir(&dir)?.flatten() {
            let _ = fs::remove_file(entry.path());
        }
    }
    save_index(&dir, &StoreIndex::default())?;
    Ok(0)
}

// ---------------------------------------------------------------------------
// Wayland Data Control Client (ext_data_control_v1 / zwlr_data_control_v1)
// ---------------------------------------------------------------------------

fn bind_data_control(conn: &mut WlConnection) -> Result<(u32, u32)> {
    let (registry, globals) = conn.get_globals()?;
    let seat_g = globals
        .iter()
        .find(|g| g.interface == "wl_seat")
        .ok_or_else(|| anyhow!("compositor missing wl_seat"))?
        .clone();
    let seat_id = conn.bind_global(registry, seat_g.name, "wl_seat", seat_g.version.min(5))?;

    let mgr_g = globals
        .iter()
        .find(|g| g.interface == "ext_data_control_manager_v1")
        .or_else(|| globals.iter().find(|g| g.interface == "zwlr_data_control_manager_v1"))
        .ok_or_else(|| anyhow!("compositor advertises neither ext_data_control_manager_v1 nor zwlr_data_control_manager_v1"))?
        .clone();
    let mgr_id = conn.bind_global(
        registry,
        mgr_g.name,
        &mgr_g.interface,
        mgr_g.version.min(2),
    )?;
    let dev_id = conn.next_id();
    let mut w = WlWriter::new();
    w.u32(dev_id).u32(seat_id);
    conn.send(mgr_id, DC_MGR_GET_DEVICE, w)?;
    Ok((mgr_id, dev_id))
}

fn read_pipe_bounded(read_fd: OwnedFd, max_bytes: usize, timeout: Duration) -> Result<Vec<u8>> {
    unsafe {
        let flags = libc::fcntl(read_fd.as_raw_fd(), libc::F_GETFL);
        if flags >= 0 {
            libc::fcntl(read_fd.as_raw_fd(), libc::F_SETFL, flags | libc::O_NONBLOCK);
        }
    }
    let deadline = Instant::now() + timeout;
    let mut data = Vec::new();
    let mut chunk = [0u8; 8192];
    loop {
        if data.len() >= max_bytes {
            break;
        }
        let now = Instant::now();
        if now >= deadline {
            bail!("timed out reading Wayland clipboard offer");
        }
        let rem_ms = (deadline - now).as_millis().min(500) as i32;
        let mut pfd = libc::pollfd {
            fd: read_fd.as_raw_fd(),
            events: libc::POLLIN,
            revents: 0,
        };
        let rc = unsafe { libc::poll(&mut pfd, 1, rem_ms) };
        if rc < 0 {
            let err = io::Error::last_os_error();
            if err.kind() == io::ErrorKind::Interrupted {
                continue;
            }
            return Err(err).context("poll clipboard pipe");
        }
        if rc == 0 {
            continue;
        }
        let to_read = chunk.len().min(max_bytes - data.len());
        let n = unsafe {
            libc::read(
                read_fd.as_raw_fd(),
                chunk.as_mut_ptr() as *mut libc::c_void,
                to_read,
            )
        };
        if n > 0 {
            data.extend_from_slice(&chunk[..n as usize]);
        } else if n == 0 {
            break;
        } else {
            let err = io::Error::last_os_error();
            if err.kind() == io::ErrorKind::WouldBlock || err.kind() == io::ErrorKind::Interrupted {
                continue;
            }
            return Err(err).context("read clipboard pipe");
        }
    }
    Ok(data)
}

fn receive_offer_bytes(
    conn: &mut WlConnection,
    offer_id: u32,
    mime: &str,
) -> Result<(Vec<u8>, Vec<alis_wayland::WlMessage>)> {
    let mut pipe_fds = [0 as libc::c_int; 2];
    if unsafe { libc::pipe2(pipe_fds.as_mut_ptr(), libc::O_CLOEXEC) } != 0 {
        return Err(io::Error::last_os_error()).context("pipe2");
    }
    let read_fd = unsafe { OwnedFd::from_raw_fd(pipe_fds[0]) };
    let write_fd = unsafe { OwnedFd::from_raw_fd(pipe_fds[1]) };

    let mut w = WlWriter::new();
    w.string(mime).fd(write_fd.as_raw_fd());
    conn.send(offer_id, DC_OFFER_RECEIVE, w)?;
    drop(write_fd);
    let extra_events = conn.roundtrip()?;

    // Cap at 32 MiB and 3s timeout so a stalled clipboard owner cannot hang or OOM the watcher
    let data = read_pipe_bounded(read_fd, 32 * 1024 * 1024, Duration::from_secs(3))?;
    Ok((data, extra_events))
}

fn pick_best_mime<'a>(offered: &'a [String], requested: Option<&str>) -> Option<&'a str> {
    if let Some(req) = requested {
        if let Some(exact) = offered.iter().find(|m| m.as_str() == req) {
            return Some(exact.as_str());
        }
        if req == "text" {
            for pref in ["text/plain;charset=utf-8", "text/plain", "UTF8_STRING", "STRING", "text/html"] {
                if let Some(found) = offered.iter().find(|m| m.as_str() == pref) {
                    return Some(found.as_str());
                }
            }
            return offered.iter().find(|m| m.starts_with("text/")).map(String::as_str);
        }
        if req == "image" {
            for pref in ["image/png", "image/jpeg", "image/webp", "image/gif", "image/bmp"] {
                if let Some(found) = offered.iter().find(|m| m.as_str() == pref) {
                    return Some(found.as_str());
                }
            }
            return offered.iter().find(|m| m.starts_with("image/")).map(String::as_str);
        }
        return None;
    }

    // Watch/default priority: prefer image MIME if clipboard holds an image, else UTF-8 text, else HTML
    for pref in [
        "image/png",
        "image/jpeg",
        "image/webp",
        "image/gif",
        "text/plain;charset=utf-8",
        "text/plain",
        "UTF8_STRING",
        "STRING",
        "TEXT",
        "text/html",
    ] {
        if let Some(found) = offered.iter().find(|m| m.as_str() == pref) {
            return Some(found.as_str());
        }
    }
    offered
        .iter()
        .find(|m| m.starts_with("image/") || m.starts_with("text/"))
        .map(String::as_str)
}

fn run_paste(args: PasteArgs) -> Result<i32> {
    let mut conn = WlConnection::connect()?;
    let (_mgr_id, dev_id) = bind_data_control(&mut conn)?;
    let events = conn.roundtrip()?;

    let mut offers: HashMap<u32, Vec<String>> = HashMap::new();
    let mut active_offer: u32 = 0;

    for ev in events {
        if ev.object_id == dev_id {
            match ev.opcode {
                DC_DEV_EV_DATA_OFFER => {
                    let mut r = WlReader::new(&ev.payload);
                    if let Ok(offer_id) = r.u32() {
                        offers.insert(offer_id, Vec::new());
                    }
                }
                DC_DEV_EV_SELECTION if !args.primary => {
                    let mut r = WlReader::new(&ev.payload);
                    active_offer = r.u32().unwrap_or(0);
                }
                DC_DEV_EV_PRIMARY_SELECTION if args.primary => {
                    let mut r = WlReader::new(&ev.payload);
                    active_offer = r.u32().unwrap_or(0);
                }
                _ => {}
            }
        } else if ev.opcode == DC_OFFER_EV_OFFER
            && let Some(list) = offers.get_mut(&ev.object_id)
        {
            let mut r = WlReader::new(&ev.payload);
            if let Ok(mime) = r.string() {
                list.push(mime);
            }
        }
    }

    if active_offer == 0 {
        return Ok(1);
    }
    let offered = offers.get(&active_offer).cloned().unwrap_or_default();
    if args.list_types {
        for m in &offered {
            println!("{m}");
        }
        return Ok(0);
    }

    let Some(chosen) = pick_best_mime(&offered, args.mime.as_deref()) else {
        return Ok(1);
    };
    let (bytes, _) = receive_offer_bytes(&mut conn, active_offer, chosen)?;
    io::stdout().write_all(&bytes)?;
    if !args.no_newline && chosen.starts_with("text/") && !bytes.ends_with(b"\n") {
        io::stdout().write_all(b"\n")?;
    }
    Ok(0)
}

fn serve_selection(data: Vec<u8>, mime: &str, primary: bool, signal_ready: bool) -> Result<i32> {
    let mut conn = WlConnection::connect()?;
    let (mgr_id, dev_id) = bind_data_control(&mut conn)?;
    let src_id = conn.next_id();
    let mut cw = WlWriter::new();
    cw.u32(src_id);
    conn.send(mgr_id, DC_MGR_CREATE_SOURCE, cw)?;

    let mut offered_mimes: Vec<String> = vec![mime.to_string()];
    if mime.starts_with("text/plain") {
        for alias in ["text/plain;charset=utf-8", "text/plain", "UTF8_STRING", "STRING", "TEXT"] {
            if !offered_mimes.iter().any(|m| m == alias) {
                offered_mimes.push(alias.to_string());
            }
        }
    }
    for m in &offered_mimes {
        let mut ow = WlWriter::new();
        ow.string(m);
        conn.send(src_id, DC_SRC_OFFER, ow)?;
    }

    let mut sw = WlWriter::new();
    sw.u32(src_id);
    conn.send(
        dev_id,
        if primary {
            DC_DEV_SET_PRIMARY_SELECTION
        } else {
            DC_DEV_SET_SELECTION
        },
        sw,
    )?;
    let _ = conn.roundtrip()?;

    if signal_ready {
        let _ = writeln!(io::stdout(), "READY");
        let _ = io::stdout().flush();
        // Detach stdout from parent pipe so command substitutions never wait on this daemon.
        if let Ok(devnull) = fs::OpenOptions::new().write(true).open("/dev/null") {
            unsafe {
                libc::dup2(devnull.as_raw_fd(), libc::STDOUT_FILENO);
            }
        }
    }

    let shared_data = Arc::new(data);
    while !STOP_REQUESTED.load(Ordering::SeqCst) {
        let ev = match conn.recv_message_timeout(1000) {
            Ok(Some(ev)) => ev,
            Ok(None) => continue,
            Err(_) => break,
        };
        WlConnection::check_display_error(&ev)?;
        if ev.object_id == src_id {
            match ev.opcode {
                DC_SRC_EV_SEND => {
                    if let Some(fd) = conn.take_fd() {
                        let bytes = Arc::clone(&shared_data);
                        std::thread::spawn(move || {
                            let mut f = std::fs::File::from(fd);
                            let _ = f.write_all(&bytes);
                        });
                    }
                }
                DC_SRC_EV_CANCELLED => break,
                _ => {}
            }
        } else if ev.object_id == dev_id && ev.opcode == DC_DEV_EV_FINISHED {
            break;
        }
    }
    let _ = conn.send(src_id, DC_SRC_DESTROY, WlWriter::new());
    Ok(0)
}

fn run_copy(args: CopyArgs) -> Result<i32> {
    if args.clear {
        let mut conn = WlConnection::connect()?;
        let (_mgr_id, dev_id) = bind_data_control(&mut conn)?;
        let mut sw = WlWriter::new();
        sw.u32(0);
        conn.send(
            dev_id,
            if args.primary {
                DC_DEV_SET_PRIMARY_SELECTION
            } else {
                DC_DEV_SET_SELECTION
            },
            sw,
        )?;
        let _ = conn.roundtrip()?;
        return Ok(0);
    }

    let data = if !args.text.is_empty() {
        args.text.join(" ").into_bytes()
    } else {
        let mut buf = Vec::new();
        io::stdin().read_to_end(&mut buf)?;
        buf
    };
    let mime = args.mime.unwrap_or_else(|| {
        detect_image_meta(&data)
            .map(|(m, _, _)| m.to_string())
            .unwrap_or_else(|| "text/plain;charset=utf-8".to_string())
    });

    if args.foreground {
        return serve_selection(data, &mime, args.primary, false);
    }

    // Write payload to a private temp file and spawn a detached self-process to serve Wayland selection.
    // Wait for the child's READY handshake (after Wayland set_selection + roundtrip) so an immediate
    // clipboard paste or Ctrl+V never races against server startup.
    let runtime = std::env::var_os("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(std::env::temp_dir);
    let tmp_dir = runtime.join("alis");
    let _ = fs::create_dir_all(&tmp_dir);
    let tmp_file = tmp_dir.join(format!("clip-copy-{}.bin", std::process::id()));
    fs::write(&tmp_file, &data)?;

    let exe = std::env::current_exe().context("resolve current alis-native exe")?;
    let mut cmd = ProcessCommand::new(exe);
    cmd.args(["clipboard", "serve", "--mime", &mime, "--signal-ready"]);
    if args.primary {
        cmd.arg("--primary");
    }
    cmd.arg("--data-file").arg(&tmp_file);
    cmd.stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null());
    let mut child = cmd.spawn().context("spawn background clipboard selection server")?;
    if let Some(stdout) = child.stdout.take() {
        let mut reader = BufReader::new(stdout);
        let mut line = String::new();
        let _ = reader.read_line(&mut line);
    }
    Ok(0)
}

fn run_watch(max_entries: usize) -> Result<i32> {
    STOP_REQUESTED.store(false, Ordering::SeqCst);
    unsafe {
        libc::signal(libc::SIGTERM, handle_signal as *const () as libc::sighandler_t);
        libc::signal(libc::SIGINT, handle_signal as *const () as libc::sighandler_t);
    }

    let mut conn = WlConnection::connect()?;
    let (_mgr_id, dev_id) = bind_data_control(&mut conn)?;

    let mut offers: HashMap<u32, Vec<String>> = HashMap::new();
    let mut pending: VecDeque<alis_wayland::WlMessage> = VecDeque::new();
    for ev in conn.roundtrip()? {
        pending.push_back(ev);
    }

    while !STOP_REQUESTED.load(Ordering::SeqCst) {
        let ev = if let Some(queued) = pending.pop_front() {
            queued
        } else {
            match conn.recv_message_timeout(500) {
                Ok(Some(ev)) => ev,
                Ok(None) => continue,
                Err(_) => break,
            }
        };
        WlConnection::check_display_error(&ev)?;
        if ev.object_id == dev_id {
            match ev.opcode {
                DC_DEV_EV_DATA_OFFER => {
                    let mut r = WlReader::new(&ev.payload);
                    if let Ok(offer_id) = r.u32() {
                        offers.insert(offer_id, Vec::new());
                    }
                }
                DC_DEV_EV_SELECTION => {
                    let mut r = WlReader::new(&ev.payload);
                    let offer_id = r.u32().unwrap_or(0);
                    if offer_id != 0 {
                        let mimes = offers.remove(&offer_id).unwrap_or_default();
                        if !mimes.iter().any(|m| m == "x-kde-passwordManagerHint")
                            && let Some(chosen) = pick_best_mime(&mimes, None)
                        {
                            let chosen_owned = chosen.to_string();
                            if let Ok((bytes, extra_events)) =
                                receive_offer_bytes(&mut conn, offer_id, &chosen_owned)
                            {
                                for extra in extra_events {
                                    pending.push_back(extra);
                                }
                                let _ = store_native_entry(bytes, Some(&chosen_owned), max_entries);
                            }
                        }
                        let _ = conn.send(offer_id, DC_OFFER_DESTROY, WlWriter::new());
                    }
                }
                DC_DEV_EV_PRIMARY_SELECTION => {
                    let mut r = WlReader::new(&ev.payload);
                    let offer_id = r.u32().unwrap_or(0);
                    if offer_id != 0 && offers.remove(&offer_id).is_some() {
                        let _ = conn.send(offer_id, DC_OFFER_DESTROY, WlWriter::new());
                    }
                }
                DC_DEV_EV_FINISHED => break,
                _ => {}
            }
        } else if ev.opcode == DC_OFFER_EV_OFFER
            && let Some(list) = offers.get_mut(&ev.object_id)
        {
            let mut r = WlReader::new(&ev.payload);
            if let Ok(mime) = r.string() {
                list.push(mime);
            }
        }
    }
    Ok(0)
}

pub fn run_command(command: ClipboardCommand) -> Result<i32> {
    match command {
        ClipboardCommand::Copy(args) => run_copy(args),
        ClipboardCommand::Serve {
            mime,
            primary,
            data_file,
            signal_ready,
        } => {
            STOP_REQUESTED.store(false, Ordering::SeqCst);
            unsafe {
                libc::signal(libc::SIGTERM, handle_signal as *const () as libc::sighandler_t);
                libc::signal(libc::SIGINT, handle_signal as *const () as libc::sighandler_t);
            }
            let data = fs::read(&data_file).unwrap_or_default();
            let _ = fs::remove_file(&data_file);
            serve_selection(data, &mime, primary, signal_ready)
        }
        ClipboardCommand::Paste(args) => run_paste(args),
        ClipboardCommand::Watch { max_entries } => run_watch(max_entries),
        ClipboardCommand::Store { mime, max_entries } => {
            let mut payload = Vec::new();
            io::stdin().read_to_end(&mut payload)?;
            store_native_entry(payload, mime.as_deref(), max_entries)?;
            Ok(0)
        }
        ClipboardCommand::List { limit } => run_list(limit),
        ClipboardCommand::Decode { id } => run_decode(id),
        ClipboardCommand::Delete { id } => run_delete(id),
        ClipboardCommand::Wipe => run_wipe(),
    }
}

// Legacy parity helper (`alis-native clipboard-filter [--filter]`)
fn store_with_cliphist(payload: &[u8]) -> Result<i32> {
    let child_res = ProcessCommand::new("cliphist")
        .arg("store")
        .stdin(Stdio::piped())
        .spawn();
    if let Ok(mut child) = child_res {
        if let Some(mut stdin) = child.stdin.take() {
            stdin
                .write_all(payload)
                .context("failed to write clipboard payload to cliphist")?;
        }
        let status = child.wait().context("failed to wait for cliphist store")?;
        return Ok(status.code().unwrap_or(1));
    }
    // If cliphist is not installed, store natively in Alis clipboard store!
    store_native_entry(payload.to_vec(), None, 400)?;
    Ok(0)
}

pub fn run(filter: bool) -> Result<i32> {
    let mut payload = Vec::new();
    io::stdin()
        .read_to_end(&mut payload)
        .context("failed to read clipboard payload")?;
    let payload = sanitize_payload(payload);

    if payload.is_empty() {
        return Ok(0);
    }

    if filter {
        io::stdout()
            .write_all(&payload)
            .context("failed to write filtered clipboard payload")?;
        return Ok(0);
    }

    store_with_cliphist(&payload)
}

#[cfg(test)]
mod tests {
    use super::{
        build_preview, is_browser_markup, pick_best_mime, sanitize_payload, strip_browser_markup,
    };

    #[test]
    fn plain_text_is_byte_for_byte_passthrough() {
        let input = b"alpha <div>literal source</div>\n".to_vec();
        assert!(!is_browser_markup(&input));
        assert_eq!(sanitize_payload(input.clone()), input);
    }

    #[test]
    fn firefox_html_payload_is_sanitized() {
        let input = r#"<meta http-equiv="content-type" content="text/html; charset=utf-8"><div>Hello&nbsp;world</div><div>Next</div>"#;
        assert_eq!(strip_browser_markup(input), "Hello\u{00a0}world\nNext");
    }

    #[test]
    fn chromium_fragment_removes_wrapper_and_preserves_lines() {
        let input =
            r#"<!--StartFragment--><p>One<br>Two</p><script>bad()</script><!--EndFragment-->"#;
        assert_eq!(strip_browser_markup(input), "One\nTwo");
    }

    #[test]
    fn image_only_markup_keeps_source() {
        let input = r#"<!--StartFragment--><img alt="x" src="https://example.test/a.png"><!--EndFragment-->"#;
        assert_eq!(strip_browser_markup(input), "https://example.test/a.png");
    }

    #[test]
    fn detects_png_dimensions_in_preview_and_selects_mime() {
        let mut png = vec![0x89, b'P', b'N', b'G', 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13, b'I', b'H', b'D', b'R'];
        png.extend_from_slice(&1920u32.to_be_bytes());
        png.extend_from_slice(&1080u32.to_be_bytes());
        let (mime, preview) = build_preview(&png, None);
        assert_eq!(mime, "image/png");
        assert!(preview.contains("[[ binary data"));
        assert!(preview.contains("png 1920x1080"));
        let offers = vec!["text/html".into(), "text/plain;charset=utf-8".into()];
        assert_eq!(pick_best_mime(&offers, None), Some("text/plain;charset=utf-8"));
    }
}
