//! Event-driven loopback SSE bridge (`127.0.0.1:43821`) for instant zero-restart
//! theme updates in Zen Browser & Firefox (Native & Flatpak).
//!
//! Native Rust replacement for `scripts/colors/alis-browser-theme-bridge.py`:
//! - Binds strictly to loopback (`127.0.0.1`, `::1`, or `localhost`).
//! - Single-instance enforced via non-blocking `flock(LOCK_EX | LOCK_NB)`.
//! - Single-threaded non-blocking `poll(2)` loop (~2 MB RSS vs ~25 MB Python, 0% idle CPU).

use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::net::{TcpListener, TcpStream};
use std::os::fd::AsRawFd;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

use anyhow::{Result, anyhow};
use serde_json::{Value, json};

const DEFAULT_PORT: u16 = 43821;
const REQUEST_TIMEOUT: Duration = Duration::from_secs(5);
const KEEPALIVE_INTERVAL: Duration = Duration::from_secs(45);
const MAX_REQUEST_BYTES: usize = 80 * 1024;
const MAX_BODY_BYTES: usize = 65_536;
const MAX_SSE_BUFFER_BYTES: usize = 256 * 1024;
const MAX_CONNS: usize = 256;

static STOP_FLAG: AtomicBool = AtomicBool::new(false);

extern "C" fn handle_stop_signal(_sig: libc::c_int) {
    STOP_FLAG.store(true, Ordering::SeqCst);
}

fn install_signal_handlers() {
    STOP_FLAG.store(false, Ordering::SeqCst);
    unsafe {
        libc::signal(libc::SIGPIPE, libc::SIG_IGN);
        let mut sa: libc::sigaction = std::mem::zeroed();
        sa.sa_sigaction = handle_stop_signal as *const () as usize;
        libc::sigemptyset(&mut sa.sa_mask);
        // Intentionally omit SA_RESTART so poll(2) wakes immediately with EINTR.
        sa.sa_flags = 0;
        libc::sigaction(libc::SIGINT, &sa, std::ptr::null_mut());
        libc::sigaction(libc::SIGTERM, &sa, std::ptr::null_mut());
    }
}

fn is_loopback_host(host: &str) -> bool {
    matches!(host, "127.0.0.1" | "::1" | "localhost")
}

fn html_escape(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    for ch in input.chars() {
        match ch {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&#x27;"),
            _ => out.push(ch),
        }
    }
    out
}

fn read_payload_compact(theme_file: &Path) -> String {
    if let Ok(raw) = fs::read_to_string(theme_file)
        && let Ok(val) = serde_json::from_str::<Value>(&raw)
        && let Ok(compact) = serde_json::to_string(&val)
    {
        return compact;
    }
    r#"{"enabled":true,"gecko_theme":null}"#.to_owned()
}

fn build_install_html(theme_file: &Path) -> Vec<u8> {
    let raw = read_payload_compact(theme_file);
    let parsed: Value = serde_json::from_str(&raw).unwrap_or_else(|_| json!({}));
    let pal = parsed.get("palette").and_then(Value::as_object);
    let get = |key: &str, default: &str| -> String {
        let val = pal
            .and_then(|map| map.get(key))
            .and_then(Value::as_str)
            .unwrap_or(default);
        html_escape(val)
    };

    let bg = get("bg", "#141318");
    let surface = get("surface_elev", "#211f26");
    let fg = get("fg", "#e6e1e9");
    let sub = get("subtext", "#cac4d0");
    let primary = get("primary", "#82d9df");
    let on_primary = get("on_primary", "#10252a");
    let border = get("border", "#49454f");

    format!(
        r#"<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Alis Live Browser Theme</title>
  <style>
    :root {{
      --bg: {bg};
      --surface: {surface};
      --fg: {fg};
      --sub: {sub};
      --primary: {primary};
      --on-primary: {on_primary};
      --border: {border};
    }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0; min-height: 100vh; display: grid; place-items: center;
      font-family: system-ui, -apple-system, sans-serif;
      background: var(--bg); color: var(--fg); padding: 24px;
      transition: background 180ms ease, color 180ms ease;
    }}
    .card {{
      max-width: 520px; width: 100%; background: var(--surface);
      border: 1px solid var(--border); border-radius: 20px; padding: 28px;
      box-shadow: 0 18px 48px rgba(0,0,0,0.28);
    }}
    h1 {{ margin: 0 0 8px; font-size: 22px; }}
    p {{ margin: 0 0 18px; color: var(--sub); line-height: 1.55; font-size: 14.5px; }}
    .btn {{
      display: inline-flex; align-items: center; gap: 8px;
      background: var(--primary); color: var(--on-primary);
      font-weight: 600; font-size: 15px; text-decoration: none;
      padding: 12px 20px; border-radius: 12px;
    }}
    .meta {{
      margin-top: 20px; padding-top: 16px; border-top: 1px solid var(--border);
      font-size: 13px; color: var(--sub); display: flex; justify-content: space-between;
    }}
    .dot {{
      display: inline-block; width: 9px; height: 9px; border-radius: 50%;
      background: var(--primary); margin-right: 6px;
    }}
  </style>
</head>
<body>
  <div class="card">
    <h1>Alis Live Browser Theme</h1>
    <p>
      Click below once in <strong>Zen Browser</strong> (or Firefox / LibreWolf / Floorp) to install the
      lightweight Alis theme bridge. Wallpaper &amp; Dark/Light color changes will then apply
      <strong>instantly without restarting</strong>.
    </p>
    <a class="btn" href="/alis-browser-theme.xpi">Install Alis Live Theme (.xpi)</a>
    <div class="meta">
      <span><span class="dot"></span>Loopback SSE Bridge Active</span>
      <span id="seed">Accent: {primary}</span>
    </div>
  </div>
  <script>
    const es = new EventSource("/events");
    es.onmessage = (ev) => {{
      try {{
        const d = JSON.parse(ev.data);
        const p = d.palette || {{}};
        if (p.bg) document.documentElement.style.setProperty("--bg", p.bg);
        if (p.surface_elev) document.documentElement.style.setProperty("--surface", p.surface_elev);
        if (p.fg) document.documentElement.style.setProperty("--fg", p.fg);
        if (p.subtext) document.documentElement.style.setProperty("--sub", p.subtext);
        if (p.primary) {{
          document.documentElement.style.setProperty("--primary", p.primary);
          document.getElementById("seed").textContent = "Accent: " + p.primary;
        }}
        if (p.on_primary) document.documentElement.style.setProperty("--on-primary", p.on_primary);
        if (p.border) document.documentElement.style.setProperty("--border", p.border);
      }} catch (_) {{}}
    }};
  </script>
</body>
</html>
"#
    )
    .into_bytes()
}

fn build_http_response(
    status: u16,
    reason: &str,
    content_type: &str,
    body: &[u8],
    extra_headers: &[&str],
) -> Vec<u8> {
    let mut head = format!(
        "HTTP/1.1 {status} {reason}\r\n\
         Content-Type: {content_type}\r\n\
         Content-Length: {}\r\n\
         Cache-Control: no-store\r\n\
         Access-Control-Allow-Origin: *\r\n\
         Connection: close\r\n",
        body.len()
    );
    for hdr in extra_headers {
        head.push_str(hdr);
        head.push_str("\r\n");
    }
    head.push_str("\r\n");
    let mut out = Vec::with_capacity(head.len() + body.len());
    out.extend_from_slice(head.as_bytes());
    out.extend_from_slice(body);
    out
}

enum ConnPhase {
    Reading {
        buf: Vec<u8>,
        deadline: Instant,
    },
    WritingClose {
        buf: Vec<u8>,
        offset: usize,
        deadline: Instant,
    },
    Sse {
        write_buf: Vec<u8>,
        write_offset: usize,
        last_activity: Instant,
    },
}

struct Conn {
    stream: TcpStream,
    phase: ConnPhase,
}

impl Conn {
    fn is_sse(&self) -> bool {
        matches!(self.phase, ConnPhase::Sse { .. })
    }

    fn flush_writes(&mut self, now: Instant) -> Result<bool, ()> {
        match &mut self.phase {
            ConnPhase::WritingClose { buf, offset, .. } => {
                while *offset < buf.len() {
                    match self.stream.write(&buf[*offset..]) {
                        Ok(0) => return Err(()),
                        Ok(n) => *offset += n,
                        Err(err) if err.kind() == io::ErrorKind::WouldBlock => return Ok(false),
                        Err(err) if err.kind() == io::ErrorKind::Interrupted => continue,
                        Err(_) => return Err(()),
                    }
                }
                Ok(true)
            }
            ConnPhase::Sse {
                write_buf,
                write_offset,
                last_activity,
            } => {
                while *write_offset < write_buf.len() {
                    match self.stream.write(&write_buf[*write_offset..]) {
                        Ok(0) => return Err(()),
                        Ok(n) => {
                            *write_offset += n;
                            *last_activity = now;
                        }
                        Err(err) if err.kind() == io::ErrorKind::WouldBlock => return Ok(false),
                        Err(err) if err.kind() == io::ErrorKind::Interrupted => continue,
                        Err(_) => return Err(()),
                    }
                }
                if !write_buf.is_empty() {
                    write_buf.clear();
                    *write_offset = 0;
                    if write_buf.capacity() > 16 * 1024 {
                        write_buf.shrink_to(4096);
                    }
                }
                Ok(false)
            }
            ConnPhase::Reading { .. } => Ok(false),
        }
    }
}

fn find_header_end(buf: &[u8]) -> Option<(usize, usize)> {
    for i in 0..buf.len() {
        if i + 3 < buf.len() && &buf[i..i + 4] == b"\r\n\r\n" {
            return Some((i, i + 4));
        }
        if i + 1 < buf.len() && &buf[i..i + 2] == b"\n\n" {
            return Some((i, i + 2));
        }
    }
    None
}

fn parse_request_ready(buf: &[u8]) -> Option<(String, String)> {
    let (hdr_end, body_start) = find_header_end(buf)?;
    let header_text = String::from_utf8_lossy(&buf[..hdr_end]);
    let mut lines = header_text.lines();
    let req_line = lines.next()?.trim();
    let mut parts = req_line.split_whitespace();
    let method = parts.next()?.to_ascii_uppercase();
    let raw_path = parts.next()?;
    let path = raw_path.split('?').next().unwrap_or(raw_path).to_owned();

    let mut content_length: usize = 0;
    for line in lines {
        if let Some((k, v)) = line.split_once(':')
            && k.trim().eq_ignore_ascii_case("content-length")
            && let Ok(parsed) = v.trim().parse::<usize>()
        {
            content_length = parsed.min(MAX_BODY_BYTES);
        }
    }
    if buf.len() < body_start + content_length {
        return None;
    }
    Some((method, path))
}

fn broadcast_sse(conns: &mut Vec<Conn>, theme_file: &Path, now: Instant) -> usize {
    let payload = read_payload_compact(theme_file);
    let frame = format!("data: {payload}\n\n");
    let frame_bytes = frame.as_bytes();
    let mut delivered = 0usize;
    let mut idx = 0usize;
    while idx < conns.len() {
        if !conns[idx].is_sse() {
            idx += 1;
            continue;
        }
        let mut drop_conn = false;
        if let ConnPhase::Sse {
            write_buf,
            write_offset,
            ..
        } = &mut conns[idx].phase
        {
            if write_buf.len().saturating_sub(*write_offset) + frame_bytes.len()
                > MAX_SSE_BUFFER_BYTES
            {
                drop_conn = true;
            } else {
                write_buf.extend_from_slice(frame_bytes);
            }
        }
        if !drop_conn && conns[idx].flush_writes(now).is_err() {
            drop_conn = true;
        }
        if drop_conn {
            conns.swap_remove(idx);
        } else {
            delivered += 1;
            idx += 1;
        }
    }
    delivered
}

fn acquire_singleton_lock(gen_dir: &Path) -> Result<Option<File>> {
    let lock_path = gen_dir.join("browser-theme-bridge.lock");
    let mut file = OpenOptions::new()
        .create(true)
        .write(true)
        .open(&lock_path)?;
    let rc = unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) };
    if rc != 0 {
        let err = io::Error::last_os_error();
        if err.kind() == io::ErrorKind::WouldBlock
            || err.raw_os_error() == Some(libc::EWOULDBLOCK)
            || err.raw_os_error() == Some(libc::EAGAIN)
        {
            return Ok(None);
        }
        return Err(err.into());
    }
    file.set_len(0)?;
    writeln!(file, "{}", std::process::id())?;
    file.flush()?;
    Ok(Some(file))
}

struct BridgeConfig {
    gen_dir: PathBuf,
    host: String,
    port: u16,
    port_file: Option<PathBuf>,
    no_lock: bool,
}

fn parse_bridge_args(args: &[String]) -> Result<BridgeConfig> {
    let mut state_dir_arg = String::new();
    let mut host = "127.0.0.1".to_owned();
    let mut port: u16 = DEFAULT_PORT;
    let mut port_file_arg = String::new();
    let mut no_lock = false;

    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--state-dir" => {
                i += 1;
                state_dir_arg = args
                    .get(i)
                    .ok_or_else(|| anyhow!("--state-dir requires a value"))?
                    .clone();
            }
            "--host" => {
                i += 1;
                host = args
                    .get(i)
                    .ok_or_else(|| anyhow!("--host requires a value"))?
                    .clone();
            }
            "--port" => {
                i += 1;
                let raw = args
                    .get(i)
                    .ok_or_else(|| anyhow!("--port requires a value"))?;
                port = raw
                    .parse::<u16>()
                    .map_err(|_| anyhow!("invalid --port value: {raw}"))?;
            }
            "--port-file" => {
                i += 1;
                port_file_arg = args
                    .get(i)
                    .ok_or_else(|| anyhow!("--port-file requires a value"))?
                    .clone();
            }
            "--no-lock" => {
                no_lock = true;
            }
            "--help" | "-h" => {
                println!(
                    "Usage: alis-theme --browser-bridge [--state-dir DIR] [--host 127.0.0.1] [--port 43821] [--port-file FILE] [--no-lock]"
                );
                std::process::exit(0);
            }
            other => {
                return Err(anyhow!("unknown --browser-bridge option: {other}"));
            }
        }
        i += 1;
    }

    if !is_loopback_host(&host) {
        eprintln!("Refusing to bind browser theme bridge to non-loopback address");
        std::process::exit(2);
    }

    let state_dir = if !state_dir_arg.is_empty() {
        PathBuf::from(state_dir_arg)
    } else {
        let xdg_state = std::env::var("XDG_STATE_HOME")
            .ok()
            .filter(|v| !v.is_empty())
            .map(PathBuf::from)
            .unwrap_or_else(|| {
                let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_owned());
                PathBuf::from(home).join(".local/state")
            });
        xdg_state.join("quickshell")
    };
    let gen_dir = state_dir.join("user").join("generated");
    fs::create_dir_all(&gen_dir)?;

    let port_file = if port_file_arg.is_empty() {
        None
    } else {
        Some(PathBuf::from(port_file_arg))
    };

    Ok(BridgeConfig {
        gen_dir,
        host,
        port,
        port_file,
        no_lock,
    })
}

fn serve_loop(
    listener: TcpListener,
    gen_dir: &Path,
    stop: &AtomicBool,
) -> Result<()> {
    listener.set_nonblocking(true)?;
    let theme_file = gen_dir.join("browser-live-theme.json");
    let xpi_file = gen_dir.join("alis-browser-theme.xpi");
    let mut conns: Vec<Conn> = Vec::new();
    let mut pollfds: Vec<libc::pollfd> = Vec::new();
    let mut read_tmp = [0u8; 4096];

    while !stop.load(Ordering::Relaxed) {
        let now = Instant::now();

        // Compute minimal poll timeout: -1 (infinite sleep, 0 wakeups) when idle.
        let mut timeout_ms: i32 = -1;
        for conn in &conns {
            let next_wake = match &conn.phase {
                ConnPhase::Reading { deadline, .. } | ConnPhase::WritingClose { deadline, .. } => {
                    *deadline
                }
                ConnPhase::Sse { last_activity, .. } => *last_activity + KEEPALIVE_INTERVAL,
            };
            let rem = next_wake
                .saturating_duration_since(now)
                .as_millis()
                .min(i32::MAX as u128) as i32;
            timeout_ms = if timeout_ms < 0 {
                rem
            } else {
                timeout_ms.min(rem)
            };
        }

        pollfds.clear();
        pollfds.push(libc::pollfd {
            fd: listener.as_raw_fd(),
            events: libc::POLLIN,
            revents: 0,
        });
        for conn in &conns {
            let mut events: libc::c_short = libc::POLLIN;
            match &conn.phase {
                ConnPhase::WritingClose { .. } => {
                    events = libc::POLLOUT;
                }
                ConnPhase::Sse {
                    write_buf,
                    write_offset,
                    ..
                } => {
                    if *write_offset < write_buf.len() {
                        events |= libc::POLLOUT;
                    }
                }
                ConnPhase::Reading { .. } => {}
            }
            pollfds.push(libc::pollfd {
                fd: conn.stream.as_raw_fd(),
                events,
                revents: 0,
            });
        }

        let rc = unsafe {
            libc::poll(
                pollfds.as_mut_ptr(),
                pollfds.len() as libc::nfds_t,
                timeout_ms,
            )
        };
        if rc < 0 {
            let err = io::Error::last_os_error();
            if err.kind() == io::ErrorKind::Interrupted {
                continue;
            }
            return Err(err.into());
        }

        let now = Instant::now();

        // 1. Accept any queued connections.
        if (pollfds[0].revents & libc::POLLIN) != 0 {
            loop {
                match listener.accept() {
                    Ok((stream, _)) => {
                        if conns.len() >= MAX_CONNS {
                            drop(stream);
                            continue;
                        }
                        let _ = stream.set_nonblocking(true);
                        let _ = stream.set_nodelay(true);
                        conns.push(Conn {
                            stream,
                            phase: ConnPhase::Reading {
                                buf: Vec::with_capacity(512),
                                deadline: now + REQUEST_TIMEOUT,
                            },
                        });
                    }
                    Err(err) if err.kind() == io::ErrorKind::WouldBlock => break,
                    Err(err) if err.kind() == io::ErrorKind::Interrupted => continue,
                    Err(_) => break,
                }
            }
        }

        // 2. Service existing connections (walk backwards so swap_remove is safe).
        // Snapshot the count matching pollfds[1..].
        let polled_count = pollfds.len().saturating_sub(1);
        let mut completed_requests: Vec<(usize, String, String)> = Vec::new();
        let mut to_remove: Vec<usize> = Vec::new();

        for idx in 0..polled_count {
            let revents = pollfds[idx + 1].revents;
            let conn = &mut conns[idx];

            if (revents & (libc::POLLERR | libc::POLLNVAL)) != 0 {
                to_remove.push(idx);
                continue;
            }

            let mut remove = false;
            match &mut conn.phase {
                ConnPhase::Reading { buf, deadline } => {
                    if (revents & (libc::POLLIN | libc::POLLHUP)) != 0 {
                        loop {
                            match conn.stream.read(&mut read_tmp) {
                                Ok(0) => {
                                    if let Some((m, p)) = parse_request_ready(buf) {
                                        completed_requests.push((idx, m, p));
                                    } else {
                                        remove = true;
                                    }
                                    break;
                                }
                                Ok(n) => {
                                    if buf.len() + n > MAX_REQUEST_BYTES {
                                        remove = true;
                                        break;
                                    }
                                    buf.extend_from_slice(&read_tmp[..n]);
                                    if let Some((m, p)) = parse_request_ready(buf) {
                                        completed_requests.push((idx, m, p));
                                        break;
                                    }
                                }
                                Err(err) if err.kind() == io::ErrorKind::WouldBlock => break,
                                Err(err) if err.kind() == io::ErrorKind::Interrupted => continue,
                                Err(_) => {
                                    remove = true;
                                    break;
                                }
                            }
                        }
                    } else if now >= *deadline {
                        remove = true;
                    }
                }
                ConnPhase::WritingClose { deadline, .. } => {
                    if (revents & libc::POLLHUP) != 0 {
                        remove = true;
                    } else if (revents & libc::POLLOUT) != 0 {
                        match conn.flush_writes(now) {
                            Ok(true) | Err(()) => remove = true,
                            Ok(false) => {}
                        }
                    } else if now >= *deadline {
                        remove = true;
                    }
                }
                ConnPhase::Sse { last_activity, .. } => {
                    let prev_activity = *last_activity;
                    if (revents & (libc::POLLIN | libc::POLLHUP)) != 0 {
                        loop {
                            match conn.stream.read(&mut read_tmp) {
                                Ok(0) => {
                                    remove = true;
                                    break;
                                }
                                Ok(_) => continue,
                                Err(err) if err.kind() == io::ErrorKind::WouldBlock => break,
                                Err(err) if err.kind() == io::ErrorKind::Interrupted => continue,
                                Err(_) => {
                                    remove = true;
                                    break;
                                }
                            }
                        }
                    }
                    if !remove && (revents & libc::POLLOUT) != 0 && conn.flush_writes(now).is_err()
                    {
                        remove = true;
                    }
                    if !remove && now.saturating_duration_since(prev_activity) >= KEEPALIVE_INTERVAL
                    {
                        if let ConnPhase::Sse {
                            write_buf,
                            last_activity,
                            ..
                        } = &mut conn.phase
                        {
                            if write_buf.is_empty() {
                                write_buf.extend_from_slice(b": keepalive\n\n");
                            }
                            *last_activity = now;
                        }
                        if conn.flush_writes(now).is_err() {
                            remove = true;
                        }
                    }
                }
            }
            if remove {
                to_remove.push(idx);
            }
        }

        // Remove dead connections before dispatching requests (adjusting completed indices).
        // Simpler: dispatch completed requests FIRST (they are guaranteed not in to_remove),
        // unless POST /notify compacts SSE clients — so handle removal cleanly by marking via Option
        // or handling non-broadcast requests inline and removing dead connections in descending order.
        to_remove.sort_unstable();
        to_remove.dedup();
        let mut notify_indices: Vec<usize> = Vec::new();

        for (idx, method, path) in completed_requests {
            if to_remove.binary_search(&idx).is_ok() {
                continue;
            }
            if method == "POST" && path == "/notify" {
                notify_indices.push(idx);
                continue;
            }
            let sse_clients = conns
                .iter()
                .enumerate()
                .filter(|(i, c)| c.is_sse() && to_remove.binary_search(i).is_err())
                .count();

            if method == "GET" && path == "/events" {
                let initial = read_payload_compact(&theme_file);
                let mut init_buf = Vec::with_capacity(256 + initial.len());
                init_buf.extend_from_slice(
                    b"HTTP/1.1 200 OK\r\n\
                      Content-Type: text/event-stream; charset=utf-8\r\n\
                      Cache-Control: no-cache, no-store\r\n\
                      Connection: keep-alive\r\n\
                      Access-Control-Allow-Origin: *\r\n\r\n",
                );
                init_buf.extend_from_slice(b"data: ");
                init_buf.extend_from_slice(initial.as_bytes());
                init_buf.extend_from_slice(b"\n\n");
                conns[idx].phase = ConnPhase::Sse {
                    write_buf: init_buf,
                    write_offset: 0,
                    last_activity: now,
                };
                if conns[idx].flush_writes(now).is_err() {
                    to_remove.push(idx);
                }
                continue;
            }

            let resp = if method == "OPTIONS" {
                build_http_response(204, "No Content", "text/plain", b"", &[])
            } else if method == "GET" && path == "/health" {
                let body = format!(r#"{{"ok":true,"clients":{sse_clients}}}"#);
                build_http_response(
                    200,
                    "OK",
                    "application/json; charset=utf-8",
                    body.as_bytes(),
                    &[],
                )
            } else if method == "GET" && path == "/theme" {
                let body = read_payload_compact(&theme_file);
                build_http_response(
                    200,
                    "OK",
                    "application/json; charset=utf-8",
                    body.as_bytes(),
                    &[],
                )
            } else if method == "GET" && path == "/alis-browser-theme.xpi" {
                match fs::read(&xpi_file) {
                    Ok(bytes) => build_http_response(
                        200,
                        "OK",
                        "application/x-xpinstall",
                        &bytes,
                        &["Content-Disposition: inline; filename=\"alis-browser-theme.xpi\""],
                    ),
                    Err(_) => build_http_response(
                        404,
                        "Not Found",
                        "text/plain; charset=utf-8",
                        b"XPI not built yet",
                        &[],
                    ),
                }
            } else if method == "GET" && (path == "/" || path == "/install") {
                let html = build_install_html(&theme_file);
                build_http_response(200, "OK", "text/html; charset=utf-8", &html, &[])
            } else {
                build_http_response(
                    404,
                    "Not Found",
                    "text/plain; charset=utf-8",
                    b"Not Found",
                    &[],
                )
            };

            conns[idx].phase = ConnPhase::WritingClose {
                buf: resp,
                offset: 0,
                deadline: now + REQUEST_TIMEOUT,
            };
            match conns[idx].flush_writes(now) {
                Ok(true) | Err(()) => to_remove.push(idx),
                Ok(false) => {}
            }
        }

        // Handle POST /notify requests (may drop stale SSE connections cleanly via raw_fd lookup).
        let notify_fds: Vec<libc::c_int> = notify_indices
            .iter()
            .filter(|i| to_remove.binary_search(i).is_err())
            .map(|&i| conns[i].stream.as_raw_fd())
            .collect();

        to_remove.sort_unstable();
        to_remove.dedup();
        for &idx in to_remove.iter().rev() {
            conns.swap_remove(idx);
        }

        for fd in notify_fds {
            let delivered = broadcast_sse(&mut conns, &theme_file, now);
            let body = format!(r#"{{"ok":true,"clients":{delivered}}}"#);
            let resp = build_http_response(
                200,
                "OK",
                "application/json; charset=utf-8",
                body.as_bytes(),
                &[],
            );
            if let Some(pos) = conns.iter().position(|c| c.stream.as_raw_fd() == fd) {
                conns[pos].phase = ConnPhase::WritingClose {
                    buf: resp,
                    offset: 0,
                    deadline: now + REQUEST_TIMEOUT,
                };
                match conns[pos].flush_writes(now) {
                    Ok(true) | Err(()) => {
                        conns.swap_remove(pos);
                    }
                    Ok(false) => {}
                }
            }
        }
    }

    conns.clear();
    Ok(())
}

pub(crate) fn run_browser_bridge(args: &[String]) -> Result<()> {
    let cfg = parse_bridge_args(args)?;
    let _lock_guard = if cfg.no_lock {
        None
    } else {
        match acquire_singleton_lock(&cfg.gen_dir)? {
            Some(file) => Some(file),
            None => return Ok(()),
        }
    };

    install_signal_handlers();

    let bind_host = if cfg.host == "localhost" {
        "127.0.0.1"
    } else {
        cfg.host.as_str()
    };
    let listener = match TcpListener::bind((bind_host, cfg.port)) {
        Ok(l) => l,
        Err(_) => return Ok(()),
    };
    let actual_port = listener.local_addr()?.port();
    if let Some(port_file) = &cfg.port_file {
        fs::write(port_file, format!("{actual_port}\n"))?;
    }

    serve_loop(listener, &cfg.gen_dir, &STOP_FLAG)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{BufRead, BufReader};
    use std::sync::Arc;
    use std::thread;

    fn http_request(port: u16, req: &str) -> String {
        let mut s = TcpStream::connect(("127.0.0.1", port)).unwrap();
        s.set_read_timeout(Some(Duration::from_secs(3))).unwrap();
        s.write_all(req.as_bytes()).unwrap();
        let mut out = String::new();
        let _ = s.read_to_string(&mut out);
        out
    }

    #[test]
    fn test_browser_bridge_http_sse_notify_and_lock() {
        let dir = std::env::temp_dir().join(format!(
            "alis-browser-bridge-test-{}",
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();

        // Singleton flock contention check
        let lock1 = acquire_singleton_lock(&dir).unwrap();
        assert!(lock1.is_some());
        let lock2 = acquire_singleton_lock(&dir).unwrap();
        assert!(lock2.is_none());
        drop(lock1);

        // Seed theme + xpi
        fs::write(
            dir.join("browser-live-theme.json"),
            r##"{"enabled":true,"palette":{"primary":"#ffb4ac"},"gecko_theme":{"colors":{"tab_line":"#ffb4ac"}}}"##,
        )
        .unwrap();
        fs::write(dir.join("alis-browser-theme.xpi"), b"PK\x03\x04fake-xpi-bytes").unwrap();

        let listener = TcpListener::bind(("127.0.0.1", 0)).unwrap();
        let port = listener.local_addr().unwrap().port();
        let stop = Arc::new(AtomicBool::new(false));
        let stop_bg = Arc::clone(&stop);
        let dir_bg = dir.clone();
        let server = thread::spawn(move || {
            serve_loop(listener, &dir_bg, &stop_bg).unwrap();
        });

        // /health
        let health = http_request(port, "GET /health HTTP/1.1\r\nHost: localhost\r\n\r\n");
        assert!(health.starts_with("HTTP/1.1 200 OK"));
        assert!(health.contains(r#""ok":true"#));
        assert!(health.contains(r#""clients":0"#));

        // /install & /alis-browser-theme.xpi
        let install = http_request(port, "GET /install HTTP/1.1\r\nHost: localhost\r\n\r\n");
        assert!(install.contains("alis-browser-theme.xpi"));
        assert!(install.contains("#ffb4ac"));
        let xpi = http_request(
            port,
            "GET /alis-browser-theme.xpi HTTP/1.1\r\nHost: localhost\r\n\r\n",
        );
        assert!(xpi.contains("application/x-xpinstall"));
        assert!(xpi.contains("fake-xpi-bytes"));

        // /events SSE + POST /notify live push
        let mut sse = TcpStream::connect(("127.0.0.1", port)).unwrap();
        sse.set_read_timeout(Some(Duration::from_secs(3))).unwrap();
        sse.write_all(b"GET /events HTTP/1.1\r\nHost: localhost\r\n\r\n")
            .unwrap();
        let mut reader = BufReader::new(sse);
        let mut line = String::new();
        loop {
            line.clear();
            let n = reader.read_line(&mut line).unwrap();
            assert!(n > 0);
            if line.starts_with("data: ") {
                assert!(line.contains("#ffb4ac"));
                break;
            }
        }

        // Update theme file and trigger POST /notify
        fs::write(
            dir.join("browser-live-theme.json"),
            r##"{"enabled":true,"gecko_theme":{"colors":{"tab_line":"#006876"}}}"##,
        )
        .unwrap();
        let notify = http_request(
            port,
            "POST /notify HTTP/1.1\r\nHost: localhost\r\nContent-Length: 0\r\n\r\n",
        );
        assert!(notify.contains(r#""clients":1"#));

        loop {
            line.clear();
            let n = reader.read_line(&mut line).unwrap();
            assert!(n > 0);
            if line.starts_with("data: ") {
                assert!(line.contains("#006876"));
                break;
            }
        }

        // Shut down cleanly
        stop.store(true, Ordering::SeqCst);
        let _ = TcpStream::connect(("127.0.0.1", port));
        server.join().unwrap();
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_loopback_guard() {
        assert!(is_loopback_host("127.0.0.1"));
        assert!(is_loopback_host("::1"));
        assert!(is_loopback_host("localhost"));
        assert!(!is_loopback_host("0.0.0.0"));
        assert!(!is_loopback_host("192.168.1.5"));
    }
}
