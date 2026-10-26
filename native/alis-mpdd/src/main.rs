use std::collections::{BTreeMap, HashMap, HashSet};
use std::fs;
use std::io::{self, BufRead, BufReader, Read, Write};
use std::net::TcpStream;
use std::os::unix::ffi::OsStrExt;
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use anyhow::{Context, Result, anyhow, bail};
use clap::Parser;
use serde::Deserialize;
use serde_json::{Map, Value, json};
use sha2::{Digest, Sha256};

const ART_NAMES: &[&str] = &["cover", "folder", "front", "album", "artwork"];
const ART_EXTENSIONS: &[&str] = &[".jpg", ".jpeg", ".png", ".webp", ".avif"];
const CACHE_ART_EXTENSIONS: &[&str] = &[".jpg", ".jpeg", ".png", ".webp", ".gif", ".avif"];
const IDLE_SUBSYSTEMS: &[&str] = &[
    "player",
    "playlist",
    "mixer",
    "options",
    "database",
    "stored_playlist",
];

trait ReadWrite: Read + Write {}
impl<T: Read + Write> ReadWrite for T {}

#[derive(Debug, Parser)]
#[command(about = "Dormant persistent MPD backend for Alis")]
struct Args {
    #[arg(long, default_value = "127.0.0.1")]
    host: String,

    #[arg(long, default_value_t = 6600)]
    port: u16,

    #[arg(long)]
    music_root: Option<String>,

    #[arg(long)]
    socket: Option<PathBuf>,

    /// Run one operation using the legacy local_music_mpd.py CLI contract.
    #[arg(long)]
    compat: bool,

    /// Forward the legacy CLI contract to a running alis-mpdd Unix socket.
    #[arg(long)]
    client_compat: bool,

    /// Subscribe to MPD idle events through a running alis-mpdd Unix socket.
    #[arg(long)]
    subscribe: bool,

    /// Read a local .lrc/.txt sidecar using the LocalMusic lyrics contract.
    #[arg(long)]
    lyrics: Option<String>,

    /// Arguments consumed by --compat/--client-compat: MODE HOST PORT [MODE_ARGS...].
    #[arg(trailing_var_arg = true)]
    compat_args: Vec<String>,
}

struct MpdClient {
    stream: BufReader<Box<dyn ReadWrite + Send>>,
}

impl MpdClient {
    fn connect(host: &str, port: u16) -> Result<Self> {
        Self::connect_with_timeout(host, port, Some(Duration::from_secs(5)))
    }

    fn connect_idle(host: &str, port: u16) -> Result<Self> {
        Self::connect_with_timeout(host, port, None)
    }

    fn connect_with_timeout(host: &str, port: u16, read_timeout: Option<Duration>) -> Result<Self> {
        let stream: Box<dyn ReadWrite + Send> = if host.starts_with('/') {
            let stream = UnixStream::connect(host)
                .with_context(|| format!("connect MPD unix socket {host}"))?;
            stream.set_read_timeout(read_timeout)?;
            stream.set_write_timeout(Some(Duration::from_secs(5)))?;
            Box::new(stream)
        } else {
            let stream = TcpStream::connect((host, port))
                .with_context(|| format!("connect MPD {host}:{port}"))?;
            stream.set_read_timeout(read_timeout)?;
            stream.set_write_timeout(Some(Duration::from_secs(5)))?;
            let _ = stream.set_nodelay(true);
            Box::new(stream)
        };

        let mut client = Self {
            stream: BufReader::new(stream),
        };
        let greeting = client.read_line()?;
        if !greeting.starts_with("OK MPD ") {
            bail!("invalid_greeting");
        }
        Ok(client)
    }

    fn read_line(&mut self) -> Result<String> {
        let mut line = String::new();
        let bytes = self.stream.read_line(&mut line)?;
        if bytes == 0 {
            bail!("connection_closed");
        }
        Ok(line.trim_end_matches(['\r', '\n']).to_owned())
    }

    fn send_line(&mut self, line: &str) -> Result<()> {
        let inner = self.stream.get_mut();
        inner.write_all(line.as_bytes())?;
        inner.write_all(b"\n")?;
        inner.flush()?;
        Ok(())
    }

    fn command<I, S>(&mut self, name: &str, args: I) -> Result<Vec<String>>
    where
        I: IntoIterator<Item = S>,
        S: AsRef<str>,
    {
        let line = command_line(name, args);
        self.send_line(&line)?;

        let mut result = Vec::new();
        loop {
            let text = self.read_line()?;
            if text == "OK" {
                return Ok(result);
            }
            if text.starts_with("ACK ") {
                bail!("{text}");
            }
            result.push(text);
        }
    }

    fn command_batch(&mut self, commands: &[String]) -> Result<()> {
        if commands.is_empty() {
            return Ok(());
        }

        let mut payload = String::from("command_list_begin\n");
        for command in commands {
            payload.push_str(command);
            payload.push('\n');
        }
        payload.push_str("command_list_end\n");

        let inner = self.stream.get_mut();
        inner.write_all(payload.as_bytes())?;
        inner.flush()?;

        loop {
            let text = self.read_line()?;
            if text == "OK" {
                return Ok(());
            }
            if text.starts_with("ACK ") {
                bail!("{text}");
            }
        }
    }

    fn binary(&mut self, name: &str, uri: &str) -> Result<Option<(Vec<u8>, String)>> {
        let mut data = Vec::new();
        let mut mime = String::new();
        let mut offset = 0usize;

        loop {
            self.send_line(&format!(
                "{name} {} {}",
                quote(uri),
                quote(&offset.to_string())
            ))?;
            let mut total_size = None;
            let mut chunk_size = 0usize;

            loop {
                let text = self.read_line()?;
                if text.starts_with("ACK ") {
                    if offset == 0 {
                        return Ok(None);
                    }
                    bail!("{text}");
                }
                if text == "OK" {
                    break;
                }
                let Some((key, value)) = text.split_once(": ") else {
                    continue;
                };
                match key.to_ascii_lowercase().as_str() {
                    "size" => total_size = value.parse::<usize>().ok(),
                    "type" => mime = value.trim().to_owned(),
                    "binary" => {
                        chunk_size = value.parse::<usize>().context("invalid_binary_size")?;
                        if chunk_size > 0 {
                            let start = data.len();
                            data.resize(start + chunk_size, 0);
                            self.stream.read_exact(&mut data[start..])?;
                            let mut newline = [0u8; 1];
                            self.stream.read_exact(&mut newline)?;
                            if newline != [b'\n'] {
                                bail!("invalid_binary_terminator");
                            }
                        }
                    }
                    _ => {}
                }
            }

            if chunk_size == 0 || total_size.is_none_or(|size| data.len() >= size) {
                break;
            }
            offset = data.len();
        }

        if data.is_empty() {
            Ok(None)
        } else {
            Ok(Some((data, mime)))
        }
    }
}

struct MpdManager {
    host: String,
    port: u16,
    music_root_override: String,
    resolved_music_root: Mutex<Option<String>>,
    art_lookup: Mutex<ArtLookup>,
    client: Mutex<Option<MpdClient>>,
}

impl MpdManager {
    fn new(host: String, port: u16, music_root_override: String) -> Self {
        Self {
            host,
            port,
            music_root_override,
            resolved_music_root: Mutex::new(None),
            art_lookup: Mutex::new(ArtLookup::default()),
            client: Mutex::new(None),
        }
    }

    fn with_client<T>(
        &self,
        operation: impl FnOnce(&mut MpdClient, &str, &mut ArtLookup) -> Result<T>,
    ) -> Result<T> {
        let mut guard = self
            .client
            .lock()
            .map_err(|_| anyhow!("mpd_mutex_poisoned"))?;
        if guard.is_none() {
            *guard = Some(MpdClient::connect(&self.host, self.port)?);
        }

        let client = guard.as_mut().expect("client initialized");
        let root = if self.music_root_override.trim().is_empty() {
            let mut resolved = self
                .resolved_music_root
                .lock()
                .map_err(|_| anyhow!("mpd_root_mutex_poisoned"))?;
            if resolved.is_none() {
                *resolved = Some(music_root(client, ""));
            }
            resolved.clone().unwrap_or_default()
        } else {
            expand_home(&self.music_root_override)
                .to_string_lossy()
                .into_owned()
        };

        let mut art_lookup = self
            .art_lookup
            .lock()
            .map_err(|_| anyhow!("mpd_art_mutex_poisoned"))?;
        let result = operation(client, &root, &mut art_lookup);
        if result.is_err() {
            *guard = None;
        }
        result
    }
}

#[derive(Debug, Deserialize)]
struct Request {
    #[serde(default)]
    id: Value,
    op: String,
    #[serde(default)]
    params: Value,
    #[serde(default)]
    host: Option<String>,
    #[serde(default)]
    port: Option<u16>,
}

type Record = BTreeMap<String, Vec<String>>;

fn quote(value: &str) -> String {
    format!("\"{}\"", value.replace('\\', "\\\\").replace('"', "\\\""))
}

fn command_line<I, S>(name: &str, args: I) -> String
where
    I: IntoIterator<Item = S>,
    S: AsRef<str>,
{
    let mut line = name.to_owned();
    for arg in args {
        line.push(' ');
        line.push_str(&quote(arg.as_ref()));
    }
    line
}

fn pairs(lines: &[String]) -> BTreeMap<String, String> {
    let mut result = BTreeMap::new();
    for line in lines {
        if let Some((key, value)) = line.split_once(": ") {
            result.insert(key.to_ascii_lowercase(), value.to_owned());
        }
    }
    result
}

fn records(lines: &[String], marker: &str) -> Vec<Record> {
    let marker = marker.to_ascii_lowercase();
    let mut result = Vec::new();
    let mut current: Option<Record> = None;

    for line in lines {
        let Some((key, value)) = line.split_once(": ") else {
            continue;
        };
        let key = key.to_ascii_lowercase();
        if key == marker {
            if let Some(previous) = current.take() {
                result.push(previous);
            }
            let mut record = Record::new();
            record.insert(marker.clone(), vec![value.to_owned()]);
            current = Some(record);
        } else if let Some(record) = current.as_mut() {
            record.entry(key).or_default().push(value.to_owned());
        }
    }

    if let Some(record) = current {
        result.push(record);
    }
    result
}

fn first(record: &Record, keys: &[&str]) -> String {
    for key in keys {
        if let Some(value) = record.get(*key).and_then(|values| values.first()) {
            let value = value.trim();
            if !value.is_empty() {
                return value.to_owned();
            }
        }
    }
    String::new()
}

fn number(value: &str) -> f64 {
    value
        .split(':')
        .next()
        .and_then(|part| part.parse().ok())
        .unwrap_or(0.0)
}

fn int_prefix(value: &str) -> i64 {
    value
        .split('/')
        .next()
        .and_then(|part| part.parse().ok())
        .unwrap_or(0)
}

fn home_dir() -> PathBuf {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/"))
}

fn expand_home(value: &str) -> PathBuf {
    if value == "~" {
        return home_dir();
    }
    if let Some(rest) = value.strip_prefix("~/") {
        return home_dir().join(rest);
    }
    PathBuf::from(value)
}

fn lyrics_candidates(track: &Path) -> Vec<PathBuf> {
    let mut candidates = vec![
        track.with_extension("lrc"),
        PathBuf::from(format!("{}.lrc", track.to_string_lossy())),
        track.with_extension("txt"),
        PathBuf::from(format!("{}.txt", track.to_string_lossy())),
    ];
    let mut unique = Vec::with_capacity(candidates.len());
    for path in candidates.drain(..) {
        if !unique.contains(&path) {
            unique.push(path);
        }
    }
    unique
}

fn lrc_stamp_seconds(token: &str) -> Option<f64> {
    let (minutes, seconds_part) = token.split_once(':')?;
    if minutes.is_empty() || minutes.len() > 3 || !minutes.bytes().all(|byte| byte.is_ascii_digit())
    {
        return None;
    }

    let fraction_at = seconds_part.find('.').or_else(|| seconds_part.find(':'));
    let (seconds, fraction) = match fraction_at {
        Some(index) => (&seconds_part[..index], Some(&seconds_part[index + 1..])),
        None => (seconds_part, None),
    };
    if seconds.len() != 2 || !seconds.bytes().all(|byte| byte.is_ascii_digit()) {
        return None;
    }
    if fraction.is_some_and(|value| {
        value.is_empty() || value.len() > 3 || !value.bytes().all(|byte| byte.is_ascii_digit())
    }) {
        return None;
    }

    let minutes = minutes.parse::<u64>().ok()?;
    let seconds = seconds.parse::<u64>().ok()?;
    let mut value = (minutes * 60 + seconds) as f64;
    if let Some(fraction) = fraction {
        let numerator = fraction.parse::<u64>().ok()? as f64;
        value += numerator / 10_f64.powi(fraction.len() as i32);
    }
    Some(value)
}

fn lrc_inline_words(raw_lyric: &str) -> (String, Vec<(f64, String)>) {
    let mut clean = String::with_capacity(raw_lyric.len());
    let mut inline_stamps: Vec<(f64, usize, usize)> = Vec::new();
    let mut copied_until = 0usize;
    let mut search_from = 0usize;

    while let Some(relative_start) = raw_lyric[search_from..].find('<') {
        let start = search_from + relative_start;
        let Some(relative_end) = raw_lyric[start + 1..].find('>') else {
            break;
        };
        let end = start + 1 + relative_end;
        if let Some(seconds) = lrc_stamp_seconds(&raw_lyric[start + 1..end]) {
            let chunk = &raw_lyric[copied_until..start];
            if !clean.ends_with(' ') && !clean.is_empty() && !chunk.starts_with(' ') && !chunk.is_empty() {
                clean.push(' ');
            }
            clean.push_str(chunk);
            copied_until = end + 1;
            inline_stamps.push((seconds, start, end + 1));
        }
        search_from = end + 1;
    }
    let tail = &raw_lyric[copied_until..];
    if !clean.ends_with(' ') && !clean.is_empty() && !tail.starts_with(' ') && !tail.is_empty() {
        clean.push(' ');
    }
    clean.push_str(tail);
    let normalized = clean.split_whitespace().collect::<Vec<_>>().join(" ");

    let mut segments = Vec::new();
    if !inline_stamps.is_empty() {
        let prefix = raw_lyric[..inline_stamps[0].1].trim();
        if !prefix.is_empty() {
            segments.push((-1.0, prefix.to_owned()));
        }
        for (idx, (sec, _start, after)) in inline_stamps.iter().enumerate() {
            let seg_end = inline_stamps
                .get(idx + 1)
                .map(|item| item.1)
                .unwrap_or(raw_lyric.len());
            let seg_text = raw_lyric[*after..seg_end].trim();
            segments.push((*sec, seg_text.to_owned()));
        }
    }
    (normalized, segments)
}

fn lrc_line(line: &str) -> (Vec<f64>, String, Vec<(f64, String)>) {
    let mut stamps = Vec::new();
    let mut lyric = String::with_capacity(line.len());
    let mut copied_until = 0usize;
    let mut search_from = 0usize;

    while let Some(relative_start) = line[search_from..].find('[') {
        let start = search_from + relative_start;
        let Some(relative_end) = line[start + 1..].find(']') else {
            break;
        };
        let end = start + 1 + relative_end;
        if let Some(seconds) = lrc_stamp_seconds(&line[start + 1..end]) {
            lyric.push_str(&line[copied_until..start]);
            copied_until = end + 1;
            stamps.push(seconds);
        }
        search_from = end + 1;
    }
    lyric.push_str(&line[copied_until..]);
    let raw_trimmed = lyric.trim();
    let (clean_lyric, inline_segments) = lrc_inline_words(raw_trimmed);
    (stamps, clean_lyric, inline_segments)
}

fn parse_lrc(text: &str) -> (Vec<Value>, bool) {
    let mut offset_ms = 0i64;
    let mut timed: Vec<(f64, String, Vec<(f64, String)>)> = Vec::new();
    let mut plain = Vec::new();

    for raw in text.lines() {
        let line = raw.trim_matches(|ch| matches!(ch, '\u{feff}' | '\r' | '\n'));
        if line.trim().is_empty() {
            continue;
        }

        let trimmed = line.trim();
        let lowered = trimmed.to_ascii_lowercase();
        if lowered.starts_with("[offset:") && lowered.ends_with(']') {
            if let Ok(value) = trimmed[8..trimmed.len() - 1].parse::<i64>() {
                offset_ms = value;
            }
            continue;
        }
        if ["[ar:", "[al:", "[ti:", "[by:", "[re:", "[ve:", "[length:"]
            .iter()
            .any(|prefix| lowered.starts_with(prefix))
        {
            continue;
        }

        let (stamps, lyric, inline_segments) = lrc_line(line);
        if stamps.is_empty() {
            if !lyric.is_empty() {
                plain.push(json!({"time": -1.0, "text": lyric}));
            }
            continue;
        }

        let lyric = if lyric.is_empty() {
            "♪".to_owned()
        } else {
            lyric
        };
        for stamp in stamps {
            timed.push((stamp, lyric.clone(), inline_segments.clone()));
        }
    }

    if timed.is_empty() {
        return (plain, false);
    }

    let offset = offset_ms as f64 / 1000.0;
    timed.sort_by(|left, right| left.0.total_cmp(&right.0));
    let n_lines = timed.len();
    let mut result = Vec::with_capacity(n_lines);
    for idx in 0..n_lines {
        let line_start = (timed[idx].0 + offset).max(0.0);
        let text = timed[idx].1.clone();
        let inline_segments = &timed[idx].2;
        let mut next_start = line_start + 4.2;
        for next_item in timed.iter().skip(idx + 1) {
            let cand = (next_item.0 + offset).max(0.0);
            if cand > line_start + 0.05 {
                next_start = cand;
                break;
            }
        }
        let gap = (next_start - line_start).max(0.35);
        let vocal_window = (gap - 0.06).max(0.35).min((gap * 0.92).clamp(1.4, 8.5));
        let mut line_end = line_start + vocal_window;

        if inline_segments.is_empty() {
            result.push(json!({
                "time": line_start,
                "endTime": (line_end * 1000.0).round() / 1000.0,
                "text": text
            }));
        } else {
            let mut words = Vec::new();
            for (seg_idx, (raw_t, seg_text)) in inline_segments.iter().enumerate() {
                if seg_text.is_empty() {
                    continue;
                }
                let w_start = if *raw_t < 0.0 {
                    line_start
                } else {
                    (*raw_t + offset).max(0.0)
                };
                let w_end = inline_segments
                    .get(seg_idx + 1)
                    .map(|(nt, _)| (*nt + offset).max(w_start + 0.08))
                    .unwrap_or_else(|| line_end.max(w_start + 0.2));
                if w_end > line_end {
                    line_end = w_end;
                }
                for sub in seg_text.split_whitespace() {
                    words.push(json!({
                        "text": sub,
                        "start": (w_start * 1000.0).round() / 1000.0,
                        "end": (w_end * 1000.0).round() / 1000.0,
                        "duration": ((w_end - w_start).max(0.04) * 1000.0).round() / 1000.0
                    }));
                }
            }
            result.push(json!({
                "time": line_start,
                "endTime": (line_end * 1000.0).round() / 1000.0,
                "text": text,
                "words": words
            }));
        }
    }
    (result, true)
}

fn local_lyrics(track_text: &str) -> Value {
    if track_text.contains("://") {
        return json!({"status": "not_found", "path": "", "synced": false, "lines": []});
    }

    let track = expand_home(track_text);
    for path in lyrics_candidates(&track) {
        if !path.is_file() {
            continue;
        }
        let bytes = match fs::read(&path) {
            Ok(bytes) => bytes,
            Err(error) => {
                return json!({
                    "status": "error",
                    "path": path.to_string_lossy(),
                    "synced": false,
                    "lines": [],
                    "error": error.to_string()
                });
            }
        };
        let text = String::from_utf8_lossy(&bytes);
        let (lines, synced) = parse_lrc(&text);
        if !lines.is_empty() {
            let resolved = fs::canonicalize(&path).unwrap_or(path);
            return json!({
                "status": "ok",
                "path": resolved.to_string_lossy(),
                "synced": synced,
                "lines": lines
            });
        }
    }

    json!({"status": "not_found", "path": "", "synced": false, "lines": []})
}

fn cache_dir() -> PathBuf {
    std::env::var_os("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| home_dir().join(".cache"))
        .join("hadalis")
        .join("music-covers")
}

fn local_path(uri: &str, music_root: &str) -> String {
    if uri.contains("://") {
        return uri.to_owned();
    }
    let candidate = expand_home(uri);
    if candidate.is_absolute() {
        return candidate.to_string_lossy().into_owned();
    }
    if !music_root.is_empty() {
        return expand_home(music_root)
            .join(candidate)
            .to_string_lossy()
            .into_owned();
    }
    uri.to_owned()
}

fn file_url(path: &Path) -> String {
    let path = if path.is_absolute() {
        path.to_path_buf()
    } else {
        std::env::current_dir()
            .unwrap_or_else(|_| PathBuf::from("/"))
            .join(path)
    };

    let mut output = String::from("file://");
    for byte in path.as_os_str().as_bytes() {
        match *byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'/' | b'-' | b'.' | b'_' | b'~' => {
                output.push(*byte as char)
            }
            value => output.push_str(&format!("%{value:02X}")),
        }
    }
    output
}

struct ArtLookup {
    cache: PathBuf,
    folders: HashMap<PathBuf, String>,
    cached: HashMap<String, String>,
}

impl Default for ArtLookup {
    fn default() -> Self {
        Self {
            cache: cache_dir(),
            folders: HashMap::new(),
            cached: HashMap::new(),
        }
    }
}

fn art_filename_rank(name: &str) -> Option<usize> {
    let lower = name.to_ascii_lowercase();
    for (base_index, base) in ART_NAMES.iter().enumerate() {
        let Some(extension) = lower.strip_prefix(base) else {
            continue;
        };
        if let Some(extension_index) = ART_EXTENSIONS
            .iter()
            .position(|candidate| extension == *candidate)
        {
            return Some(base_index * ART_EXTENSIONS.len() + extension_index);
        }
    }
    None
}

impl ArtLookup {
    fn folder_art(&mut self, path_text: &str) -> String {
        if path_text.is_empty() || path_text.contains("://") {
            return String::new();
        }

        let directory = Path::new(path_text)
            .parent()
            .unwrap_or_else(|| Path::new("."))
            .to_path_buf();
        if let Some(art) = self.folders.get(&directory) {
            return art.clone();
        }

        let art = fs::read_dir(&directory)
            .ok()
            .and_then(|entries| {
                let mut best: Option<(usize, PathBuf)> = None;
                for entry in entries.flatten() {
                    let path = entry.path();
                    if !path.is_file() {
                        continue;
                    }
                    let Some(name) = path.file_name().and_then(|name| name.to_str()) else {
                        continue;
                    };
                    let Some(rank) = art_filename_rank(name) else {
                        continue;
                    };
                    if best
                        .as_ref()
                        .is_none_or(|(best_rank, _)| rank <= *best_rank)
                    {
                        best = Some((rank, path));
                    }
                }
                best.map(|(_, path)| file_url(&path))
            })
            .unwrap_or_default();

        self.folders.insert(directory, art.clone());
        art
    }

    fn cached_art(&mut self, track: &Map<String, Value>) -> String {
        let key = art_cache_key(track);
        if let Some(art) = self.cached.get(&key) {
            return art.clone();
        }

        let art = CACHE_ART_EXTENSIONS
            .iter()
            .map(|extension| self.cache.join(format!("{key}{extension}")))
            .find(|path| fs::metadata(path).is_ok_and(|meta| meta.len() > 0))
            .map(|path| file_url(&path))
            .unwrap_or_default();

        self.cached.insert(key, art.clone());
        art
    }
}

fn track_str<'a>(track: &'a Map<String, Value>, key: &str) -> &'a str {
    track
        .get(key)
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
}

fn casefold_key(value: &str) -> String {
    oxixml_unicode::case::fold_str(value)
}

fn track_value(track: &Map<String, Value>, key: &str) -> String {
    track_str(track, key).to_owned()
}

fn art_cache_key(track: &Map<String, Value>) -> String {
    let album_artist = {
        let value = track_str(track, "albumArtist");
        if value.is_empty() {
            track_str(track, "artist")
        } else {
            value
        }
    };
    let album = track_str(track, "album");
    let folder = track_str(track, "folder");
    let uri = track_str(track, "uri");

    let mut digest = Sha256::new();
    if album.is_empty() {
        let identity_folder = if folder.is_empty() {
            Path::new(uri)
                .parent()
                .and_then(Path::to_str)
                .unwrap_or_default()
        } else {
            folder
        };
        digest.update(b"folder\x1f");
        digest.update(identity_folder.as_bytes());
    } else {
        digest.update(b"album\x1f");
        digest.update(album_artist.as_bytes());
        digest.update(b"\x1f");
        digest.update(album.as_bytes());
        digest.update(b"\x1f");
        digest.update(folder.as_bytes());
    }
    format!("{:x}", digest.finalize())
}

fn art_extension(data: &[u8], mime: &str) -> &'static str {
    let mime = mime.to_ascii_lowercase();
    if mime.contains("png") || data.starts_with(b"\x89PNG\r\n\x1a\n") {
        ".png"
    } else if mime.contains("webp")
        || (data.len() >= 12 && &data[..4] == b"RIFF" && &data[8..12] == b"WEBP")
    {
        ".webp"
    } else if mime.contains("gif") || data.starts_with(b"GIF87a") || data.starts_with(b"GIF89a") {
        ".gif"
    } else {
        ".jpg"
    }
}

fn write_cached_art(
    cache: &Path,
    track: &Map<String, Value>,
    data: &[u8],
    mime: &str,
) -> Result<String> {
    if data.is_empty() {
        return Ok(String::new());
    }
    fs::create_dir_all(cache)?;
    let target = cache.join(format!(
        "{}{}",
        art_cache_key(track),
        art_extension(data, mime)
    ));
    let temporary = target.with_extension(format!(
        "{}.tmp",
        target
            .extension()
            .and_then(|value| value.to_str())
            .unwrap_or("img")
    ));
    fs::write(&temporary, data)?;
    fs::rename(&temporary, &target)?;
    Ok(file_url(&target))
}

fn build_track(
    record: &Record,
    music_root: &str,
    art_lookup: &mut ArtLookup,
) -> Map<String, Value> {
    let uri = first(record, &["file"]);
    let path = local_path(&uri, music_root);
    let title = {
        let title = first(record, &["title"]);
        if title.is_empty() {
            Path::new(&uri)
                .file_stem()
                .and_then(|value| value.to_str())
                .unwrap_or_default()
                .replace('_', " ")
                .trim()
                .to_owned()
        } else {
            title
        }
    };
    let folder = Path::new(&uri)
        .parent()
        .filter(|path| *path != Path::new("."))
        .map(|path| path.to_string_lossy().into_owned())
        .unwrap_or_default();

    let mut track = Map::new();
    track.insert("uri".into(), json!(uri));
    track.insert("path".into(), json!(path));
    track.insert("title".into(), json!(title));
    track.insert(
        "artist".into(),
        json!(first(record, &["artist", "albumartist"])),
    );
    track.insert("album".into(), json!(first(record, &["album"])));
    track.insert("albumArtist".into(), json!(first(record, &["albumartist"])));
    track.insert(
        "duration".into(),
        json!((number(&first(record, &["duration", "time"])) * 1000.0).round() / 1000.0),
    );
    track.insert(
        "track".into(),
        json!(int_prefix(&first(record, &["track"]))),
    );
    track.insert("disc".into(), json!(int_prefix(&first(record, &["disc"]))));
    track.insert("genre".into(), json!(first(record, &["genre"])));
    track.insert("date".into(), json!(first(record, &["date"])));
    track.insert("folder".into(), json!(folder));
    track.insert("queueId".into(), json!(int_prefix(&first(record, &["id"]))));
    track.insert(
        "queuePos".into(),
        json!(int_prefix(&first(record, &["pos"]))),
    );

    let art = art_lookup.folder_art(&track_value(&track, "path"));
    let art = if art.is_empty() {
        art_lookup.cached_art(&track)
    } else {
        art
    };
    track.insert("art".into(), json!(art));
    track
}

fn music_root(client: &mut MpdClient, override_root: &str) -> String {
    if !override_root.trim().is_empty() {
        return expand_home(override_root).to_string_lossy().into_owned();
    }
    client
        .command("config", std::iter::empty::<&str>())
        .ok()
        .map(|lines| pairs(&lines))
        .and_then(|values| values.get("music_directory").cloned())
        .map(|root| expand_home(&root).to_string_lossy().into_owned())
        .unwrap_or_default()
}

fn status_payload_mode_with_art(
    client: &mut MpdClient,
    root: &str,
    include_queue: bool,
    art_lookup: &mut ArtLookup,
) -> Result<Value> {
    let mut status = pairs(&client.command("status", std::iter::empty::<&str>())?);
    if status.get("consume").map(String::as_str) == Some("1") {
        let _ = client.command("consume", ["0"]);
        status.insert("consume".into(), "0".into());
    }
    let current_records = records(
        &client.command("currentsong", std::iter::empty::<&str>())?,
        "file",
    );
    let current = current_records
        .first()
        .map(|record| Value::Object(build_track(record, root, art_lookup)))
        .unwrap_or(Value::Null);

    let mut payload = Map::new();
    payload.insert("connected".into(), json!(true));
    payload.insert("status".into(), json!(status));
    payload.insert("current".into(), current);

    if include_queue {
        let queue_records = records(
            &client.command("playlistinfo", std::iter::empty::<&str>())?,
            "file",
        );
        let mut queue = Vec::with_capacity(queue_records.len());
        for record in &queue_records {
            queue.push(Value::Object(build_track(record, root, art_lookup)));
        }
        payload.insert("queue".into(), Value::Array(queue));
    }

    Ok(Value::Object(payload))
}

fn status_payload_mode(client: &mut MpdClient, root: &str, include_queue: bool) -> Result<Value> {
    let mut art_lookup = ArtLookup::default();
    status_payload_mode_with_art(client, root, include_queue, &mut art_lookup)
}

fn status_payload(client: &mut MpdClient, root: &str) -> Result<Value> {
    status_payload_mode(client, root, true)
}

fn fetch_mpd_art(client: &mut MpdClient, uri: &str) -> Option<(Vec<u8>, String)> {
    for command in ["albumart", "readpicture"] {
        if let Ok(Some(payload)) = client.binary(command, uri)
            && !payload.0.is_empty()
        {
            return Some(payload);
        }
    }
    None
}

fn populate_library_art(
    client: &mut MpdClient,
    tracks: &mut [Map<String, Value>],
    art_lookup: &mut ArtLookup,
) {
    let mut groups: BTreeMap<String, Vec<usize>> = BTreeMap::new();

    for (index, track) in tracks.iter_mut().enumerate() {
        if !track_str(track, "art").is_empty() {
            continue;
        }
        let cached = art_lookup.cached_art(track);
        if !cached.is_empty() {
            track.insert("art".into(), json!(cached));
            continue;
        }
        groups.entry(art_cache_key(track)).or_default().push(index);
    }

    for indexes in groups.values() {
        let Some(&first_index) = indexes.first() else {
            continue;
        };
        let Some((data, mime)) = fetch_mpd_art(client, track_str(&tracks[first_index], "uri"))
        else {
            continue;
        };
        let Ok(art) = write_cached_art(&art_lookup.cache, &tracks[first_index], &data, &mime)
        else {
            continue;
        };
        if art.is_empty() {
            continue;
        }
        art_lookup
            .cached
            .insert(art_cache_key(&tracks[first_index]), art.clone());
        for index in indexes {
            tracks[*index].insert("art".into(), json!(art));
        }
    }
}

fn snapshot(client: &mut MpdClient, root: &str, include_folders: bool) -> Result<Value> {
    let library_records = records(
        &client.command("listallinfo", std::iter::empty::<&str>())?,
        "file",
    );
    let mut art_lookup = ArtLookup::default();
    let mut tracks = Vec::with_capacity(library_records.len());
    for record in &library_records {
        tracks.push(build_track(record, root, &mut art_lookup));
    }

    tracks.sort_by_cached_key(|track| {
        (
            casefold_key(track_str(track, "artist")),
            casefold_key(track_str(track, "album")),
            track.get("disc").and_then(Value::as_i64).unwrap_or(0),
            track.get("track").and_then(Value::as_i64).unwrap_or(0),
            casefold_key(track_str(track, "title")),
            casefold_key(track_str(track, "uri")),
        )
    });
    populate_library_art(client, &mut tracks, &mut art_lookup);

    let playlist_lines = client.command("listplaylists", std::iter::empty::<&str>())?;
    let mut playlist_names = playlist_lines
        .iter()
        .filter_map(|line| {
            let (key, value) = line.split_once(": ")?;
            key.eq_ignore_ascii_case("playlist")
                .then(|| value.to_owned())
        })
        .collect::<Vec<_>>();
    playlist_names.sort_by_cached_key(|name| casefold_key(name));

    let mut playlists = Vec::new();
    for name in playlist_names {
        let Ok(lines) = client.command("listplaylistinfo", [&name]) else {
            continue;
        };
        let playlist_records = records(&lines, "file");
        let mut items = Vec::with_capacity(playlist_records.len());
        for record in &playlist_records {
            items.push(Value::Object(build_track(record, root, &mut art_lookup)));
        }
        playlists.push(json!({
            "id": format!("mpd:{name}"),
            "name": name,
            "kind": "playlist",
            "tracks": items,
        }));
    }

    let folder_values = if include_folders {
        let mut folders: BTreeMap<String, Vec<Value>> = BTreeMap::new();
        for track in &tracks {
            let folder = track_value(track, "folder");
            if !folder.is_empty() {
                folders
                    .entry(folder)
                    .or_default()
                    .push(Value::Object(track.clone()));
            }
        }
        let mut folder_entries = folders.into_iter().collect::<Vec<_>>();
        folder_entries.sort_by_cached_key(|(folder, _)| casefold_key(folder));
        folder_entries
            .into_iter()
            .filter(|(_, tracks)| tracks.len() >= 2)
            .map(|(folder, tracks)| {
                let name = Path::new(&folder)
                    .file_name()
                    .and_then(|value| value.to_str())
                    .unwrap_or(&folder)
                    .to_owned();
                json!({
                    "id": format!("folder:{folder}"),
                    "name": name,
                    "subtitle": folder,
                    "kind": "folder",
                    "tracks": tracks,
                })
            })
            .collect::<Vec<_>>()
    } else {
        Vec::new()
    };

    let mut payload = status_payload_mode_with_art(client, root, true, &mut art_lookup)?;
    let object = payload
        .as_object_mut()
        .ok_or_else(|| anyhow!("invalid_status_payload"))?;
    object.insert("musicRoot".into(), json!(root));
    object.insert(
        "tracks".into(),
        Value::Array(tracks.into_iter().map(Value::Object).collect()),
    );
    object.insert("playlists".into(), Value::Array(playlists));
    if include_folders {
        object.insert("folders".into(), Value::Array(folder_values));
    }
    Ok(payload)
}

fn param_string(params: &Value, key: &str) -> Result<String> {
    params
        .get(key)
        .and_then(Value::as_str)
        .map(str::to_owned)
        .ok_or_else(|| anyhow!("missing_{key}"))
}

fn param_strings(params: &Value, key: &str) -> Result<Vec<String>> {
    params
        .get(key)
        .and_then(Value::as_array)
        .ok_or_else(|| anyhow!("missing_{key}"))?
        .iter()
        .map(|value| {
            value
                .as_str()
                .map(str::to_owned)
                .ok_or_else(|| anyhow!("invalid_{key}"))
        })
        .collect()
}

fn playlist_names(client: &mut MpdClient) -> Result<Vec<String>> {
    Ok(client
        .command("listplaylists", std::iter::empty::<&str>())?
        .iter()
        .filter_map(|line| {
            let (key, value) = line.split_once(": ")?;
            key.eq_ignore_ascii_case("playlist")
                .then(|| value.trim().to_owned())
        })
        .filter(|name| !name.is_empty())
        .collect())
}

fn handle_operation(
    client: &mut MpdClient,
    override_root: &str,
    art_lookup: &mut ArtLookup,
    op: &str,
    params: &Value,
) -> Result<Value> {
    match op {
        "status" => {
            let mut payload =
                status_payload_mode_with_art(client, override_root, true, art_lookup)?;
            payload
                .as_object_mut()
                .expect("status payload is object")
                .insert("musicRoot".into(), json!(override_root));
            Ok(payload)
        }
        "snapshot" => {
            let include_folders = params
                .get("includeFolders")
                .and_then(Value::as_bool)
                .unwrap_or(true);
            let result = snapshot(client, override_root, include_folders);
            if result.is_ok() {
                *art_lookup = ArtLookup::default();
            }
            result
        }
        "queue" => {
            let uris = param_strings(params, "uris")?;
            if uris.is_empty() {
                bail!("empty_queue");
            }
            let index = params.get("index").and_then(Value::as_i64).unwrap_or(0);
            let clamped = index.clamp(0, uris.len().saturating_sub(1) as i64);
            let mut commands = Vec::with_capacity(uris.len() + 2);
            commands.push(command_line("clear", std::iter::empty::<&str>()));
            commands.extend(uris.iter().map(|uri| command_line("add", [uri])));
            commands.push(command_line("play", [clamped.to_string()]));
            client.command_batch(&commands)?;
            Ok(json!({"ok": true}))
        }
        "enqueue" => {
            let uri = param_string(params, "uri")?;
            if uri.is_empty() {
                bail!("empty_uri");
            }
            let play_now = params
                .get("playNow")
                .and_then(Value::as_bool)
                .unwrap_or(false);
            let response = pairs(&client.command("addid", [&uri])?);
            if play_now {
                if let Some(song_id) = response.get("id") {
                    client.command("playid", [song_id])?;
                } else {
                    let status = pairs(&client.command("status", std::iter::empty::<&str>())?);
                    let queue_len = status
                        .get("playlistlength")
                        .and_then(|value| value.parse::<i64>().ok())
                        .unwrap_or(1);
                    client.command("play", [(queue_len - 1).max(0).to_string()])?;
                }
            }
            let mut payload =
                status_payload_mode_with_art(client, override_root, true, art_lookup)?;
            payload
                .as_object_mut()
                .expect("status payload is object")
                .insert("musicRoot".into(), json!(override_root));
            Ok(payload)
        }
        "enqueue-many" => {
            let commands = trimmed_nonempty_uris(param_strings(params, "uris")?)
                .into_iter()
                .map(|uri| command_line("add", [uri]))
                .collect::<Vec<_>>();
            client.command_batch(&commands)?;
            let mut payload =
                status_payload_mode_with_art(client, override_root, true, art_lookup)?;
            payload
                .as_object_mut()
                .expect("status payload is object")
                .insert("musicRoot".into(), json!(override_root));
            Ok(payload)
        }
        "playlist-create" | "playlist-add" => {
            let name = param_string(params, "name")?.trim().to_owned();
            if name.is_empty() || name.contains('\n') || name.contains('\r') {
                bail!("invalid_playlist_name");
            }
            let uris = unique_trimmed_uris(param_strings(params, "uris")?);
            if uris.is_empty() {
                bail!("empty_playlist_selection");
            }

            if op == "playlist-create" {
                let folded = casefold_key(&name);
                if playlist_names(client)?
                    .iter()
                    .any(|existing| casefold_key(existing) == folded)
                {
                    bail!("playlist_exists");
                }
            }

            let commands = uris
                .into_iter()
                .map(|uri| command_line("playlistadd", [&name, &uri]))
                .collect::<Vec<_>>();
            client.command_batch(&commands)?;
            Ok(json!({"ok": true}))
        }
        "command" => {
            const ALLOWED: &[&str] = &[
                "next", "previous", "stop", "play", "pause", "seekcur", "setvol", "random",
                "repeat", "single", "consume", "update", "delete", "deleteid", "clear",
            ];
            let name = param_string(params, "name")?;
            if !ALLOWED.contains(&name.as_str()) {
                bail!("command_not_allowed");
            }
            let args = params
                .get("args")
                .and_then(Value::as_array)
                .cloned()
                .unwrap_or_default()
                .into_iter()
                .map(|value| match value {
                    Value::String(value) => value,
                    other => other.to_string(),
                })
                .collect::<Vec<_>>();
            if name == "repeat" && args.len() >= 2 {
                client.command_batch(&[
                    command_line("repeat", [&args[0]]),
                    command_line("single", [&args[1]]),
                ])?;
                return Ok(json!({"ok": true, "lines": []}));
            }
            let lines = client.command(&name, &args)?;
            Ok(json!({"ok": true, "lines": lines}))
        }
        _ => bail!("unknown_operation"),
    }
}

fn response(id: Value, result: Result<Value>) -> Value {
    match result {
        Ok(result) => json!({"v": 1, "id": id, "ok": true, "result": result}),
        Err(error) => json!({
            "v": 1,
            "id": id,
            "ok": false,
            "error": error.to_string(),
        }),
    }
}

fn write_json_line(stream: &mut UnixStream, value: &Value) -> Result<()> {
    serde_json::to_writer(&mut *stream, value)?;
    stream.write_all(b"\n")?;
    stream.flush()?;
    Ok(())
}

fn handle_client(
    stream: UnixStream,
    manager: Arc<MpdManager>,
    subscribers: Arc<Mutex<Vec<UnixStream>>>,
) -> Result<()> {
    let mut reader = BufReader::new(stream);
    let mut line = String::new();

    while reader.read_line(&mut line)? > 0 {
        let current = std::mem::take(&mut line);
        let request: Request = match serde_json::from_str(current.trim()) {
            Ok(request) => request,
            Err(error) => {
                write_json_line(
                    reader.get_mut(),
                    &json!({
                        "v": 1,
                        "ok": false,
                        "error": format!("invalid_request: {error}")
                    }),
                )?;
                continue;
            }
        };

        if request.op == "subscribe" {
            let subscriber = reader.get_ref().try_clone()?;
            subscriber.set_write_timeout(Some(Duration::from_millis(250)))?;
            subscribers
                .lock()
                .map_err(|_| anyhow!("subscriber_mutex_poisoned"))?
                .push(subscriber);
            write_json_line(
                reader.get_mut(),
                &json!({
                    "v": 1,
                    "id": request.id,
                    "ok": true,
                    "result": {"subscribed": true}
                }),
            )?;
            return Ok(());
        }

        if request
            .host
            .as_deref()
            .is_some_and(|host| host != manager.host.as_str())
            || request.port.is_some_and(|port| port != manager.port)
        {
            write_json_line(
                reader.get_mut(),
                &json!({
                    "v": 1,
                    "id": request.id,
                    "ok": false,
                    "error": "endpoint_mismatch"
                }),
            )?;
            continue;
        }

        let id = request.id;
        let result = manager.with_client(|client, root, art_lookup| {
            handle_operation(client, root, art_lookup, &request.op, &request.params)
        });
        write_json_line(reader.get_mut(), &response(id, result))?;
    }
    Ok(())
}

fn broadcast(subscribers: &Arc<Mutex<Vec<UnixStream>>>, value: &Value) {
    let mut current = {
        let Ok(mut subscribers) = subscribers.lock() else {
            return;
        };
        std::mem::take(&mut *subscribers)
    };

    current.retain_mut(|stream| write_json_line(stream, value).is_ok());
    if current.is_empty() {
        return;
    }

    if let Ok(mut subscribers) = subscribers.lock() {
        subscribers.extend(current);
    }
}

fn idle_loop(
    host: String,
    port: u16,
    manager: Arc<MpdManager>,
    subscribers: Arc<Mutex<Vec<UnixStream>>>,
) {
    loop {
        let mut client = match MpdClient::connect_idle(&host, port) {
            Ok(client) => client,
            Err(error) => {
                broadcast(
                    &subscribers,
                    &json!({
                        "v": 1,
                        "type": "connection",
                        "connected": false,
                        "error": error.to_string()
                    }),
                );
                thread::sleep(Duration::from_secs(2));
                continue;
            }
        };

        broadcast(
            &subscribers,
            &json!({"v": 1, "type": "connection", "connected": true}),
        );

        loop {
            match client.command("idle", IDLE_SUBSYSTEMS) {
                Ok(lines) => {
                    let changed = lines
                        .iter()
                        .filter_map(|line| {
                            let (key, value) = line.split_once(": ")?;
                            key.eq_ignore_ascii_case("changed")
                                .then(|| value.to_owned())
                        })
                        .collect::<Vec<_>>();
                    if !changed.is_empty() {
                        let requires_rescan = changed.iter().any(|subsystem| {
                            matches!(subsystem.as_str(), "database" | "stored_playlist")
                        });
                        let include_queue = changed.iter().any(|subsystem| subsystem == "playlist");
                        let payload = if requires_rescan {
                            None
                        } else {
                            manager
                                .with_client(|client, root, art_lookup| {
                                    status_payload_mode_with_art(
                                        client,
                                        root,
                                        include_queue,
                                        art_lookup,
                                    )
                                })
                                .ok()
                        };

                        broadcast(
                            &subscribers,
                            &json!({
                                "v": 1,
                                "type": "changed",
                                "subsystems": changed,
                                "payload": payload
                            }),
                        );
                    }
                }
                Err(error) => {
                    broadcast(
                        &subscribers,
                        &json!({
                            "v": 1,
                            "type": "connection",
                            "connected": false,
                            "error": error.to_string()
                        }),
                    );
                    break;
                }
            }
        }
        thread::sleep(Duration::from_millis(500));
    }
}

fn trimmed_nonempty_uris(uris: Vec<String>) -> Vec<String> {
    uris.into_iter()
        .map(|uri| uri.trim().to_owned())
        .filter(|uri| !uri.is_empty())
        .collect()
}

fn unique_trimmed_uris(uris: Vec<String>) -> Vec<String> {
    let mut seen = HashSet::new();
    trimmed_nonempty_uris(uris)
        .into_iter()
        .filter(|uri| seen.insert(uri.clone()))
        .collect()
}

fn load_json_list_argument(raw: &str) -> Result<Vec<String>> {
    let text = if let Some(path) = raw.strip_prefix('@') {
        fs::read_to_string(path).with_context(|| format!("read payload {path}"))?
    } else {
        raw.to_owned()
    };
    let value: Value = serde_json::from_str(&text)?;
    value
        .as_array()
        .ok_or_else(|| anyhow!("expected_json_array"))?
        .iter()
        .map(|value| {
            value
                .as_str()
                .map(str::to_owned)
                .ok_or_else(|| anyhow!("expected_string_array"))
        })
        .collect()
}

fn compat_error(error: &anyhow::Error) -> i32 {
    let payload = json!({"connected": false, "error": error.to_string()});
    println!(
        "{}",
        serde_json::to_string(&payload).unwrap_or_else(|_| "{\"connected\":false}".into())
    );
    1
}

fn run_compat(args: &[String]) -> i32 {
    let result = (|| -> Result<Value> {
        if args.len() < 3 {
            bail!("usage: --compat MODE HOST PORT [MODE_ARGS...]");
        }
        let mode = args[0].as_str();
        let host = &args[1];
        let port = args[2].parse::<u16>().context("invalid_port")?;
        let rest = &args[3..];
        let mut client = MpdClient::connect(host, port)?;

        match mode {
            "snapshot" => {
                let override_root = rest.first().map(String::as_str).unwrap_or("");
                let root = music_root(&mut client, override_root);
                snapshot(
                    &mut client,
                    &root,
                    rest.get(1).map(String::as_str) != Some("--lean"),
                )
            }
            "status" => {
                let root = rest.first().map(String::as_str).unwrap_or("");
                let music_root = music_root(&mut client, root);
                let mut payload = status_payload(&mut client, &music_root)?;
                payload
                    .as_object_mut()
                    .expect("status payload is object")
                    .insert("musicRoot".into(), json!(music_root));
                Ok(payload)
            }
            "queue" => {
                if rest.len() < 2 {
                    bail!("queue_requires_index_and_payload");
                }
                let index = rest[0].parse::<i64>().context("invalid_queue_index")?;
                let uris = load_json_list_argument(&rest[1])?;
                if uris.is_empty() {
                    bail!("empty_queue");
                }
                let clamped = index.clamp(0, uris.len().saturating_sub(1) as i64);
                let mut commands = Vec::with_capacity(uris.len() + 2);
                commands.push(command_line("clear", std::iter::empty::<&str>()));
                commands.extend(uris.iter().map(|uri| command_line("add", [uri])));
                commands.push(command_line("play", [clamped.to_string()]));
                client.command_batch(&commands)?;
                Ok(json!({"ok": true}))
            }
            "enqueue" => {
                if rest.len() < 3 {
                    bail!("enqueue_requires_root_play_now_uri");
                }
                let override_root = &rest[0];
                let play_now = rest[1] == "1";
                let uri = &rest[2];
                if uri.is_empty() {
                    bail!("empty_uri");
                }
                let response = pairs(&client.command("addid", [uri])?);
                if play_now {
                    match response.get("id") {
                        Some(song_id) => {
                            client.command("playid", [song_id])?;
                        }
                        None => {
                            let status =
                                pairs(&client.command("status", std::iter::empty::<&str>())?);
                            let queue_len = status
                                .get("playlistlength")
                                .and_then(|value| value.parse::<i64>().ok())
                                .unwrap_or(1);
                            client.command("play", [(queue_len - 1).max(0).to_string()])?;
                        }
                    }
                }
                let root = music_root(&mut client, override_root);
                let mut payload = status_payload(&mut client, &root)?;
                payload
                    .as_object_mut()
                    .expect("status payload is object")
                    .insert("musicRoot".into(), json!(root));
                Ok(payload)
            }
            "enqueue-many" => {
                if rest.len() < 2 {
                    bail!("enqueue_many_requires_root_and_payload");
                }
                let override_root = &rest[0];
                let commands = trimmed_nonempty_uris(load_json_list_argument(&rest[1])?)
                    .into_iter()
                    .map(|uri| command_line("add", [uri]))
                    .collect::<Vec<_>>();
                client.command_batch(&commands)?;
                let root = music_root(&mut client, override_root);
                let mut payload = status_payload(&mut client, &root)?;
                payload
                    .as_object_mut()
                    .expect("status payload is object")
                    .insert("musicRoot".into(), json!(root));
                Ok(payload)
            }
            "playlist-create" | "playlist-add" => {
                if rest.len() < 2 {
                    bail!("playlist_requires_name_and_payload");
                }
                let name = rest[0].trim().to_owned();
                if name.is_empty() || name.contains('\n') || name.contains('\r') {
                    bail!("invalid_playlist_name");
                }
                let uris = unique_trimmed_uris(load_json_list_argument(&rest[1])?);
                if uris.is_empty() {
                    bail!("empty_playlist_selection");
                }
                if mode == "playlist-create" {
                    let folded = casefold_key(&name);
                    if playlist_names(&mut client)?
                        .iter()
                        .any(|existing| casefold_key(existing) == folded)
                    {
                        bail!("playlist_exists");
                    }
                }
                let commands = uris
                    .into_iter()
                    .map(|uri| command_line("playlistadd", [&name, &uri]))
                    .collect::<Vec<_>>();
                client.command_batch(&commands)?;
                Ok(json!({"ok": true}))
            }
            "command" => {
                if rest.len() < 2 {
                    bail!("command_requires_name_and_args");
                }
                const ALLOWED: &[&str] = &[
                    "next", "previous", "stop", "play", "pause", "seekcur", "setvol", "random",
                    "repeat", "single", "consume", "update", "delete", "deleteid", "clear",
                ];
                let name = &rest[0];
                if !ALLOWED.contains(&name.as_str()) {
                    bail!("command_not_allowed");
                }
                let raw_args: Value = serde_json::from_str(&rest[1])?;
                let command_args = raw_args
                    .as_array()
                    .ok_or_else(|| anyhow!("command_args_must_be_array"))?
                    .iter()
                    .map(|value| match value {
                        Value::String(value) => value.clone(),
                        other => other.to_string(),
                    })
                    .collect::<Vec<_>>();
                if name == "repeat" && command_args.len() >= 2 {
                    client.command_batch(&[
                        command_line("repeat", [&command_args[0]]),
                        command_line("single", [&command_args[1]]),
                    ])?;
                    return Ok(json!({"ok": true, "lines": []}));
                }
                let lines = client.command(name, &command_args)?;
                Ok(json!({"ok": true, "lines": lines}))
            }
            _ => bail!("unknown_mode:{mode}"),
        }
    })();

    match result {
        Ok(payload) => {
            match serde_json::to_string(&payload) {
                Ok(text) => println!("{text}"),
                Err(error) => return compat_error(&error.into()),
            }
            0
        }
        Err(error) => compat_error(&error),
    }
}

fn legacy_request(args: &[String]) -> Result<Value> {
    if args.len() < 3 {
        bail!("usage: --client-compat MODE HOST PORT [MODE_ARGS...]");
    }

    let mode = args[0].as_str();
    let host = &args[1];
    let port = args[2].parse::<u16>().context("invalid_port")?;
    let rest = &args[3..];

    let (op, params) = match mode {
        "snapshot" if rest.get(1).map(String::as_str) == Some("--lean") => {
            (mode, json!({"includeFolders": false}))
        }
        "snapshot" | "status" => (mode, json!({})),
        "queue" => {
            if rest.len() < 2 {
                bail!("queue_requires_index_and_payload");
            }
            let index = rest[0].parse::<i64>().context("invalid_queue_index")?;
            let uris = load_json_list_argument(&rest[1])?;
            ("queue", json!({"index": index, "uris": uris}))
        }
        "enqueue" => {
            if rest.len() < 3 {
                bail!("enqueue_requires_root_play_now_uri");
            }
            let uri = rest[2].clone();
            if uri.is_empty() {
                bail!("empty_uri");
            }
            ("enqueue", json!({"playNow": rest[1] == "1", "uri": uri}))
        }
        "enqueue-many" => {
            if rest.len() < 2 {
                bail!("enqueue_many_requires_root_and_payload");
            }
            (
                "enqueue-many",
                json!({"uris": load_json_list_argument(&rest[1])?}),
            )
        }
        "playlist-create" | "playlist-add" => {
            if rest.len() < 2 {
                bail!("playlist_requires_name_and_payload");
            }
            (
                mode,
                json!({
                    "name": rest[0],
                    "uris": load_json_list_argument(&rest[1])?
                }),
            )
        }
        "command" => {
            if rest.len() < 2 {
                bail!("command_requires_name_and_args");
            }
            let args: Value = serde_json::from_str(&rest[1])?;
            if !args.is_array() {
                bail!("command_args_must_be_array");
            }
            ("command", json!({"name": rest[0], "args": args}))
        }
        _ => bail!("unknown_mode:{mode}"),
    };

    Ok(json!({
        "v": 1,
        "id": 1,
        "op": op,
        "params": params,
        "host": host,
        "port": port
    }))
}

fn run_client_compat(args: &[String], socket: &Path) -> i32 {
    let request = match legacy_request(args) {
        Ok(request) => request,
        Err(error) => return compat_error(&error),
    };

    let mut stream = match UnixStream::connect(socket) {
        Ok(stream) => stream,
        Err(error) => {
            eprintln!(
                "alis-mpdd: daemon socket unavailable at {}: {error}",
                socket.display()
            );
            return 75;
        }
    };

    if let Err(error) = write_json_line(&mut stream, &request) {
        eprintln!("alis-mpdd: daemon request write failed: {error:#}");
        return 75;
    }

    let mut reader = BufReader::new(stream);
    let mut line = String::new();
    if let Err(error) = reader.read_line(&mut line) {
        eprintln!("alis-mpdd: daemon response read failed: {error}");
        return 75;
    }
    if line.is_empty() {
        eprintln!("alis-mpdd: daemon closed before replying");
        return 75;
    }

    let response: Value = match serde_json::from_str(line.trim()) {
        Ok(response) => response,
        Err(error) => {
            eprintln!("alis-mpdd: invalid daemon response: {error}");
            return 75;
        }
    };

    if response.get("ok").and_then(Value::as_bool) != Some(true) {
        let error = response
            .get("error")
            .and_then(Value::as_str)
            .unwrap_or("mpd_daemon_operation_failed");
        if error == "endpoint_mismatch" {
            eprintln!("alis-mpdd: daemon endpoint does not match requested MPD endpoint");
            return 75;
        }
        let payload = json!({"connected": false, "error": error});
        println!(
            "{}",
            serde_json::to_string(&payload).unwrap_or_else(|_| "{\"connected\":false}".into())
        );
        return 1;
    }

    let payload = response.get("result");
    let serialized = match payload {
        Some(payload) => serde_json::to_string(payload),
        None => serde_json::to_string(&Value::Null),
    };
    match serialized {
        Ok(text) => {
            println!("{text}");
            0
        }
        Err(error) => {
            eprintln!("alis-mpdd: daemon result serialization failed: {error}");
            75
        }
    }
}

fn run_subscribe(socket: &Path) -> Result<()> {
    let mut stream = UnixStream::connect(socket)
        .with_context(|| format!("connect daemon socket {}", socket.display()))?;
    write_json_line(
        &mut stream,
        &json!({"v": 1, "id": 1, "op": "subscribe", "params": {}}),
    )?;

    let mut reader = BufReader::new(stream);
    let mut line = String::new();
    reader.read_line(&mut line)?;
    if line.is_empty() {
        bail!("daemon_closed_before_subscribe_ack");
    }

    let ack: Value = serde_json::from_str(line.trim())?;
    if ack.get("ok").and_then(Value::as_bool) != Some(true) {
        bail!(
            "{}",
            ack.get("error")
                .and_then(Value::as_str)
                .unwrap_or("subscribe_failed")
        );
    }

    let stdout = io::stdout();
    let mut out = stdout.lock();
    serde_json::to_writer(&mut out, &json!({"v": 1, "type": "subscribed"}))?;
    out.write_all(b"\n")?;
    out.flush()?;

    loop {
        line.clear();
        if reader.read_line(&mut line)? == 0 {
            return Ok(());
        }
        out.write_all(line.as_bytes())?;
        out.flush()?;
    }
}

fn default_socket_path() -> PathBuf {
    std::env::var_os("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/tmp"))
        .join("alis")
        .join("mpd.sock")
}

fn arm_parent_death_signal() -> Result<()> {
    let parent = unsafe { libc::getppid() };
    if parent <= 1 {
        bail!("parent_process_unavailable");
    }

    let result = unsafe { libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM) };
    if result != 0 {
        return Err(io::Error::last_os_error()).context("arm parent-death signal");
    }

    if unsafe { libc::getppid() } != parent {
        bail!("parent_process_changed");
    }
    Ok(())
}

fn prepare_socket(path: &Path) -> Result<UnixListener> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }

    if path.exists() {
        match UnixStream::connect(path) {
            Ok(_) => bail!("daemon_socket_in_use:{}", path.display()),
            Err(error) if error.kind() == io::ErrorKind::ConnectionRefused => {
                fs::remove_file(path)
                    .with_context(|| format!("remove stale socket {}", path.display()))?;
            }
            Err(error) if error.kind() == io::ErrorKind::NotFound => {}
            Err(error) => {
                return Err(error)
                    .with_context(|| format!("probe existing socket {}", path.display()));
            }
        }
    }

    UnixListener::bind(path).with_context(|| format!("bind {}", path.display()))
}

fn main() -> Result<()> {
    let args = Args::parse();
    if let Some(track) = args.lyrics.as_deref() {
        println!("{}", serde_json::to_string(&local_lyrics(track))?);
        return Ok(());
    }
    if args.compat {
        std::process::exit(run_compat(&args.compat_args));
    }

    let socket = args.socket.clone().unwrap_or_else(default_socket_path);
    if args.client_compat {
        std::process::exit(run_client_compat(&args.compat_args, &socket));
    }

    // These are Quickshell-owned long-lived helpers. Linux does not terminate
    // children automatically when their parent exits, so bind their lifetime
    // to the shell and avoid leaving native helpers behind after reloads.
    arm_parent_death_signal()?;

    if args.subscribe {
        return run_subscribe(&socket);
    }

    let root = args.music_root.unwrap_or_default();
    let manager = Arc::new(MpdManager::new(args.host.clone(), args.port, root));
    let subscribers = Arc::new(Mutex::new(Vec::new()));

    {
        let host = args.host.clone();
        let manager = manager.clone();
        let subscribers = subscribers.clone();
        let port = args.port;
        thread::spawn(move || idle_loop(host, port, manager, subscribers));
    }

    let listener = prepare_socket(&socket)?;
    for connection in listener.incoming() {
        let stream = match connection {
            Ok(stream) => stream,
            Err(error) => {
                eprintln!("alis-mpdd: accept failed: {error}");
                continue;
            }
        };
        let manager = manager.clone();
        let subscribers = subscribers.clone();
        thread::spawn(move || {
            if let Err(error) = handle_client(stream, manager, subscribers) {
                eprintln!("alis-mpdd: client error: {error:#}");
            }
        });
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::io::{BufRead, BufReader, Write};
    use std::net::TcpListener;
    use std::os::unix::net::{UnixListener, UnixStream};
    use std::path::PathBuf;
    use std::sync::mpsc::{self, Receiver};
    use std::sync::{Arc, Mutex};
    use std::thread::{self, JoinHandle};
    use std::time::{Duration, SystemTime, UNIX_EPOCH};

    use super::{
        ART_EXTENSIONS, MpdClient, MpdManager, art_cache_key, art_filename_rank, broadcast,
        casefold_key, legacy_request, lrc_stamp_seconds, pairs, parse_lrc, prepare_socket, quote,
        records, status_payload_mode, status_payload_mode_with_art, unique_trimmed_uris,
    };
    use serde_json::{Value, json};

    fn test_socket_path(label: &str) -> PathBuf {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock")
            .as_nanos();
        std::env::temp_dir().join(format!(
            "alis-mpdd-{label}-{}-{nonce}.sock",
            std::process::id()
        ))
    }

    #[test]
    fn prepare_socket_preserves_live_daemon() {
        let path = test_socket_path("live");
        let listener = UnixListener::bind(&path).expect("bind live socket");

        let error = prepare_socket(&path).expect_err("live daemon must not be replaced");
        assert!(error.to_string().contains("daemon_socket_in_use"));
        assert!(path.exists(), "live socket path must remain intact");

        drop(listener);
        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn prepare_socket_reclaims_stale_socket() {
        let path = test_socket_path("stale");
        let listener = UnixListener::bind(&path).expect("bind stale socket");
        drop(listener);

        let replacement = prepare_socket(&path).expect("reclaim stale socket");
        assert!(path.exists(), "replacement socket must be bound");

        drop(replacement);
        let _ = std::fs::remove_file(path);
    }

    fn spawn_fake_mpd() -> (u16, Receiver<Vec<String>>, JoinHandle<()>) {
        let listener = TcpListener::bind(("127.0.0.1", 0)).expect("bind fake MPD");
        let port = listener.local_addr().expect("fake MPD address").port();
        let (tx, rx) = mpsc::channel();

        let handle = thread::spawn(move || {
            let (stream, _) = listener.accept().expect("accept fake MPD client");
            let mut reader = BufReader::new(stream);
            reader
                .get_mut()
                .write_all(b"OK MPD 0.23.15\n")
                .expect("write MPD greeting");
            reader.get_mut().flush().expect("flush MPD greeting");

            let mut commands = Vec::new();
            loop {
                let mut line = String::new();
                let read = reader.read_line(&mut line).expect("read MPD command");
                if read == 0 {
                    break;
                }

                let command = line.trim_end_matches(['\r', '\n']).to_owned();
                let name = command
                    .split_whitespace()
                    .next()
                    .unwrap_or_default()
                    .to_owned();
                commands.push(command);

                let response = match name.as_str() {
                    "config" => "music_directory: /music\nOK\n",
                    "status" => concat!(
                        "volume: 50\n",
                        "repeat: 0\n",
                        "random: 0\n",
                        "single: 0\n",
                        "state: play\n",
                        "song: 0\n",
                        "elapsed: 1.5\n",
                        "duration: 180.0\n",
                        "OK\n"
                    ),
                    "currentsong" => concat!(
                        "file: https://example.invalid/a.flac\n",
                        "Artist: Alpha\n",
                        "Title: One\n",
                        "duration: 180\n",
                        "OK\n"
                    ),
                    "playlistinfo" => concat!(
                        "file: https://example.invalid/a.flac\n",
                        "Artist: Alpha\n",
                        "Title: One\n",
                        "duration: 180\n",
                        "Pos: 0\n",
                        "Id: 10\n",
                        "file: https://example.invalid/b.flac\n",
                        "Artist: Beta\n",
                        "Title: Two\n",
                        "duration: 200\n",
                        "Pos: 1\n",
                        "Id: 11\n",
                        "OK\n"
                    ),
                    other => panic!("unexpected fake MPD command: {other}"),
                };

                reader
                    .get_mut()
                    .write_all(response.as_bytes())
                    .expect("write fake MPD response");
                reader.get_mut().flush().expect("flush fake MPD response");
            }

            tx.send(commands).expect("return fake MPD commands");
        });

        (port, rx, handle)
    }

    fn finish_fake_mpd(rx: Receiver<Vec<String>>, handle: JoinHandle<()>) -> Vec<String> {
        let commands = rx
            .recv_timeout(Duration::from_secs(2))
            .expect("fake MPD command log");
        handle.join().expect("join fake MPD");
        commands
    }

    #[test]
    fn parses_legacy_compat_cli_shape() {
        use clap::Parser as _;

        let args = super::Args::try_parse_from([
            "alis-mpdd",
            "--compat",
            "status",
            "127.0.0.1",
            "6600",
            "",
        ])
        .expect("compat CLI should parse");

        assert!(args.compat);
        assert_eq!(args.compat_args, vec!["status", "127.0.0.1", "6600", ""]);
    }

    #[test]
    fn maps_legacy_status_to_daemon_request() {
        let request = legacy_request(&[
            "status".into(),
            "127.0.0.1".into(),
            "6600".into(),
            "/music".into(),
        ])
        .expect("legacy status should map to an RPC request");

        assert_eq!(request["op"], "status");
        assert_eq!(request["params"], json!({}));
    }

    #[test]
    fn parses_and_maps_opt_in_lean_snapshot() {
        use clap::Parser as _;

        for flag in ["--compat", "--client-compat"] {
            let args = super::Args::try_parse_from([
                "alis-mpdd",
                flag,
                "snapshot",
                "127.0.0.1",
                "6600",
                "/music",
                "--lean",
            ])
            .expect("trailing lean option should parse");
            let request = legacy_request(&args.compat_args).expect("lean snapshot RPC");
            assert_eq!(request["op"], "snapshot");
            assert_eq!(request["params"], json!({"includeFolders": false}));
        }
        let full = legacy_request(&[
            "snapshot".into(),
            "127.0.0.1".into(),
            "6600".into(),
            "/music".into(),
        ])
        .expect("default full snapshot RPC");
        assert_eq!(full["params"], json!({}));
    }

    #[test]
    fn maps_legacy_queue_payload_to_daemon_request() {
        let request = legacy_request(&[
            "queue".into(),
            "127.0.0.1".into(),
            "6600".into(),
            "2".into(),
            "[\"a.flac\",\"b.flac\"]".into(),
        ])
        .expect("legacy queue should map to an RPC request");

        assert_eq!(request["op"], "queue");
        assert_eq!(request["params"]["index"], 2);
        assert_eq!(request["params"]["uris"], json!(["a.flac", "b.flac"]));
    }

    #[test]
    fn lightweight_status_skips_queue_snapshot() {
        let (port, rx, handle) = spawn_fake_mpd();
        {
            let mut client =
                MpdClient::connect("127.0.0.1", port).expect("connect lightweight fake MPD");
            let payload =
                status_payload_mode(&mut client, "", false).expect("read lightweight status");
            assert!(payload.get("queue").is_none());
            assert_eq!(payload["status"]["state"], "play");
            assert_eq!(payload["current"]["title"], "One");
        }

        let commands = finish_fake_mpd(rx, handle);
        assert_eq!(commands, vec!["status", "currentsong"]);
    }

    #[test]
    fn playlist_status_includes_queue_snapshot() {
        let (port, rx, handle) = spawn_fake_mpd();
        {
            let mut client =
                MpdClient::connect("127.0.0.1", port).expect("connect playlist fake MPD");
            let payload = status_payload_mode(&mut client, "", true).expect("read playlist status");
            let queue = payload["queue"].as_array().expect("queue array");
            assert_eq!(queue.len(), 2);
            assert_eq!(queue[0]["queueId"], 10);
            assert_eq!(queue[1]["title"], "Two");
        }

        let commands = finish_fake_mpd(rx, handle);
        assert_eq!(commands, vec!["status", "currentsong", "playlistinfo"]);
    }

    #[test]
    fn casefold_matches_python_edge_cases_used_for_library_ordering() {
        let cases = [
            ("Straße", "strasse"),
            ("ẞ", "ss"),
            ("Σ", "σ"),
            ("ς", "σ"),
            ("K", "k"),
            ("ſ", "s"),
            ("İ", "i\u{307}"),
            ("ǰ", "j\u{30c}"),
            ("ﬃ", "ffi"),
            ("Maße", "masse"),
        ];
        for (input, expected) in cases {
            assert_eq!(
                casefold_key(input),
                expected,
                "casefold mismatch for {input:?}"
            );
        }

        let mut names = vec!["Zeta", "Straße", "strasse", "ς", "Σ"];
        names.sort_by_cached_key(|name| casefold_key(name));
        assert_eq!(names, vec!["Straße", "strasse", "Zeta", "ς", "Σ"]);
    }

    #[test]
    fn playlist_uri_normalization_preserves_first_seen_order() {
        let uris = unique_trimmed_uris(vec![
            " z.flac ".into(),
            "a.flac".into(),
            "z.flac".into(),
            "".into(),
            " b.flac ".into(),
        ]);
        assert_eq!(uris, vec!["z.flac", "a.flac", "b.flac"]);
    }

    #[test]
    fn daemon_rpc_forwards_mutations_errors_and_reconnects_without_replay() {
        let listener = TcpListener::bind(("127.0.0.1", 0)).expect("bind daemon fake MPD");
        let port = listener
            .local_addr()
            .expect("daemon fake MPD address")
            .port();
        let (tx, rx) = mpsc::channel();

        let mpd_handle = thread::spawn(move || {
            let mut commands = Vec::new();

            let (first_stream, _) = listener.accept().expect("accept first daemon MPD client");
            let mut first = BufReader::new(first_stream);
            first
                .get_mut()
                .write_all(b"OK MPD 0.23.15\n")
                .expect("write first daemon greeting");
            first
                .get_mut()
                .flush()
                .expect("flush first daemon greeting");

            for (expected, reply) in [
                ("pause \"1\"", "OK\n"),
                ("seekcur \"bad\"", "ACK [2@0] {seekcur} bad time\n"),
            ] {
                let mut line = String::new();
                first
                    .read_line(&mut line)
                    .expect("read first daemon MPD command");
                let command = line.trim_end_matches(['\r', '\n']).to_owned();
                assert_eq!(command, expected);
                commands.push(command);
                first
                    .get_mut()
                    .write_all(reply.as_bytes())
                    .expect("write first daemon MPD reply");
                first
                    .get_mut()
                    .flush()
                    .expect("flush first daemon MPD reply");
            }
            drop(first);

            let (second_stream, _) = listener
                .accept()
                .expect("accept reconnected daemon MPD client");
            let mut second = BufReader::new(second_stream);
            second
                .get_mut()
                .write_all(b"OK MPD 0.23.15\n")
                .expect("write second daemon greeting");
            second
                .get_mut()
                .flush()
                .expect("flush second daemon greeting");
            let mut line = String::new();
            second
                .read_line(&mut line)
                .expect("read reconnected daemon MPD command");
            commands.push(line.trim_end_matches(['\r', '\n']).to_owned());
            second
                .get_mut()
                .write_all(b"OK\n")
                .expect("write reconnected daemon MPD reply");
            second
                .get_mut()
                .flush()
                .expect("flush reconnected daemon MPD reply");

            tx.send(commands).expect("return daemon MPD command log");
        });

        let manager = Arc::new(MpdManager::new("127.0.0.1".into(), port, "/music".into()));
        let subscribers = Arc::new(Mutex::new(Vec::new()));
        let (server_stream, mut client_stream) =
            UnixStream::pair().expect("create daemon RPC socket pair");
        client_stream
            .set_read_timeout(Some(Duration::from_secs(2)))
            .expect("set daemon RPC timeout");

        let handler = thread::spawn(move || {
            super::handle_client(server_stream, manager, subscribers)
                .expect("handle daemon RPC fixture")
        });

        let rpc = |stream: &mut UnixStream, request: Value| -> Value {
            super::write_json_line(stream, &request).expect("write daemon RPC request");
            let mut reader = BufReader::new(stream);
            let mut line = String::new();
            reader
                .read_line(&mut line)
                .expect("read daemon RPC response");
            serde_json::from_str(line.trim()).expect("parse daemon RPC response")
        };

        let pause = rpc(
            &mut client_stream,
            json!({
                "v": 1,
                "id": 1,
                "op": "command",
                "params": {"name": "pause", "args": ["1"]},
                "host": "127.0.0.1",
                "port": port
            }),
        );
        assert_eq!(pause["ok"], true);
        assert_eq!(pause["result"]["ok"], true);

        let failed_seek = rpc(
            &mut client_stream,
            json!({
                "v": 1,
                "id": 2,
                "op": "command",
                "params": {"name": "seekcur", "args": ["bad"]},
                "host": "127.0.0.1",
                "port": port
            }),
        );
        assert_eq!(failed_seek["ok"], false);
        assert!(
            failed_seek["error"]
                .as_str()
                .is_some_and(|error| error.contains("ACK [2@0] {seekcur} bad time"))
        );

        let play = rpc(
            &mut client_stream,
            json!({
                "v": 1,
                "id": 3,
                "op": "command",
                "params": {"name": "play", "args": []},
                "host": "127.0.0.1",
                "port": port
            }),
        );
        assert_eq!(play["ok"], true);
        assert_eq!(play["result"]["ok"], true);

        drop(client_stream);
        handler.join().expect("join daemon RPC handler");
        let commands = rx
            .recv_timeout(Duration::from_secs(2))
            .expect("daemon MPD command log");
        mpd_handle.join().expect("join daemon fake MPD");
        assert_eq!(commands, vec!["pause \"1\"", "seekcur \"bad\"", "play"]);
    }

    #[test]
    fn manager_reconnects_after_failed_request_without_replaying_mutation() {
        let listener = TcpListener::bind(("127.0.0.1", 0)).expect("bind reconnect fake MPD");
        let port = listener
            .local_addr()
            .expect("reconnect fake MPD address")
            .port();
        let (tx, rx) = mpsc::channel();

        let handle = thread::spawn(move || {
            let mut commands = Vec::new();
            for attempt in 0..2 {
                let (stream, _) = listener.accept().expect("accept reconnect fake MPD");
                let mut reader = BufReader::new(stream);
                reader
                    .get_mut()
                    .write_all(b"OK MPD 0.23.15\n")
                    .expect("write reconnect greeting");
                reader.get_mut().flush().expect("flush reconnect greeting");

                let mut line = String::new();
                reader.read_line(&mut line).expect("read reconnect command");
                commands.push(line.trim_end_matches(['\r', '\n']).to_owned());

                if attempt == 0 {
                    continue;
                }
                reader
                    .get_mut()
                    .write_all(b"OK\n")
                    .expect("write reconnect success");
                reader.get_mut().flush().expect("flush reconnect success");
            }
            tx.send(commands).expect("return reconnect command log");
        });

        let manager = MpdManager::new("127.0.0.1".into(), port, "/music".into());
        let first = manager.with_client(|client, _, _| client.command("pause", ["1"]));
        assert!(
            first.is_err(),
            "first request should observe the dropped socket"
        );

        let second =
            manager.with_client(|client, _, _| client.command("play", std::iter::empty::<&str>()));
        assert!(second.is_ok(), "next request should reconnect cleanly");

        let commands = rx
            .recv_timeout(Duration::from_secs(2))
            .expect("reconnect fake MPD command log");
        handle.join().expect("join reconnect fake MPD");
        assert_eq!(commands, vec!["pause \"1\"", "play"]);
    }

    #[test]
    fn manager_reuses_connection_and_cached_music_root() {
        let (port, rx, handle) = spawn_fake_mpd();
        {
            let manager = MpdManager::new("127.0.0.1".into(), port, String::new());
            for _ in 0..2 {
                let payload = manager
                    .with_client(|client, root, art_lookup| {
                        status_payload_mode_with_art(client, root, false, art_lookup)
                    })
                    .expect("persistent manager status");
                assert_eq!(payload["status"]["state"], "play");
            }
        }

        let commands = finish_fake_mpd(rx, handle);
        assert_eq!(
            commands,
            vec!["config", "status", "currentsong", "status", "currentsong"]
        );
    }

    #[test]
    fn broadcast_prunes_closed_subscribers_and_keeps_live_ones() {
        let (closed_server, closed_client) = UnixStream::pair().expect("closed subscriber pair");
        drop(closed_client);
        let (live_server, mut live_client) = UnixStream::pair().expect("live subscriber pair");
        live_client
            .set_read_timeout(Some(Duration::from_secs(1)))
            .expect("live subscriber timeout");

        let subscribers = Arc::new(Mutex::new(vec![closed_server, live_server]));
        broadcast(&subscribers, &json!({"type": "changed"}));

        assert_eq!(subscribers.lock().expect("subscriber lock").len(), 1);
        let mut line = String::new();
        BufReader::new(&mut live_client)
            .read_line(&mut line)
            .expect("read live broadcast");
        assert_eq!(line.trim(), r#"{"type":"changed"}"#);
    }

    #[test]
    fn artwork_filename_priority_matches_legacy_lookup_order() {
        assert_eq!(art_filename_rank("cover.jpg"), Some(0));
        assert_eq!(art_filename_rank("COVER.PNG"), Some(2));
        assert_eq!(art_filename_rank("folder.jpg"), Some(ART_EXTENSIONS.len()));
        assert_eq!(
            art_filename_rank("front.avif"),
            Some(2 * ART_EXTENSIONS.len() + 4)
        );
        assert_eq!(art_filename_rank("cover.txt"), None);
        assert_eq!(art_filename_rank("my-cover.jpg"), None);
    }

    #[test]
    fn artwork_cache_keys_preserve_existing_hash_contract() {
        let album_track = json!({
            "albumArtist": "Alpha",
            "artist": "Fallback",
            "album": "Record",
            "folder": "Jazz/Record",
            "uri": "Jazz/Record/one.flac"
        });
        assert_eq!(
            art_cache_key(album_track.as_object().expect("album track object")),
            "2026b06cfd606695ce6971ed00fd52e507dafe003130275530888a1ee569e7d8"
        );

        let folder_track = json!({
            "albumArtist": "",
            "artist": "Alpha",
            "album": "",
            "folder": "Jazz/Record",
            "uri": "Jazz/Record/one.flac"
        });
        assert_eq!(
            art_cache_key(folder_track.as_object().expect("folder track object")),
            "d3467bfa85b116e89030170c8b45c975b15ed3587eedf4aaf3eb5223c4e6da8a"
        );
    }

    #[test]
    fn parses_synced_lyrics_with_offset_and_multiple_stamps() {
        let (lines, synced) = parse_lrc("[offset:+250]\n[00:01.50][00:03]Hello\n[ar:Ignored]\n");
        assert!(synced);
        assert_eq!(lines.len(), 2);
        assert_eq!(lines[0]["time"], json!(1.75));
        assert_eq!(lines[0]["text"], "Hello");
        assert_eq!(lines[1]["time"], json!(3.25));
    }

    #[test]
    fn parses_plain_lyrics_when_no_timestamps_exist() {
        let (lines, synced) = parse_lrc("Line one\nLine two\n");
        assert!(!synced);
        assert_eq!(lines.len(), 2);
        assert_eq!(lines[0]["time"], json!(-1.0));
    }

    #[test]
    fn timestamp_parser_matches_lrc_fraction_precision() {
        assert_eq!(lrc_stamp_seconds("1:02.5"), Some(62.5));
        assert_eq!(lrc_stamp_seconds("001:02:050"), Some(62.05));
        assert_eq!(lrc_stamp_seconds("1:2"), None);
    }

    #[test]
    fn quotes_mpd_arguments() {
        assert_eq!(quote("a\\b\"c"), "\"a\\\\b\\\"c\"");
    }

    #[test]
    fn parses_pairs_case_insensitively() {
        let values = pairs(&["State: play".into(), "volume: 50".into()]);
        assert_eq!(values.get("state").map(String::as_str), Some("play"));
        assert_eq!(values.get("volume").map(String::as_str), Some("50"));
    }

    #[test]
    fn splits_record_stream_on_file_marker() {
        let parsed = records(
            &[
                "file: a.flac".into(),
                "Artist: Alpha".into(),
                "file: b.flac".into(),
                "Artist: Beta".into(),
                "Artist: Guest".into(),
            ],
            "file",
        );
        assert_eq!(parsed.len(), 2);
        assert_eq!(parsed[0]["artist"], vec!["Alpha"]);
        assert_eq!(parsed[1]["artist"], vec!["Beta", "Guest"]);
    }
    #[test]
    fn daemon_result_borrow_serialization_matches_owned_clone() {
        let mut large_tracks = Vec::new();
        for index in 0..256 {
            large_tracks.push(json!({
                "uri": format!("Artist/Album/{index:03}.flac"),
                "title": format!("Track {index}"),
                "artist": "Fixture Artist",
                "duration": 180.25 + index as f64,
                "tags": ["alpha", "beta", index]
            }));
        }

        let fixtures = vec![
            json!({"ok": true}),
            json!({"ok": true, "result": null}),
            json!({"ok": true, "result": true}),
            json!({"ok": true, "result": 42}),
            json!({"ok": true, "result": "text"}),
            json!({"ok": true, "result": [1, "two", null, false]}),
            json!({
                "ok": true,
                "result": {
                    "connected": true,
                    "status": {"state": "play", "volume": "72"},
                    "queue": large_tracks
                }
            }),
        ];

        for response in fixtures {
            let owned = response.get("result").cloned().unwrap_or(Value::Null);
            let borrowed = match response.get("result") {
                Some(payload) => serde_json::to_string(payload),
                None => serde_json::to_string(&Value::Null),
            };
            assert_eq!(
                serde_json::to_string(&owned).expect("serialize owned daemon result"),
                borrowed.expect("serialize borrowed daemon result")
            );
        }
    }
}
