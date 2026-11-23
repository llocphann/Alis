use std::ffi::{CString, c_char, c_int, c_void};
use std::fs;
use std::io::{self, BufRead, BufReader, Read, Write};
use std::os::unix::process::CommandExt;
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

use anyhow::{Context, Result, anyhow, bail};
use clap::{Args, Subcommand};

static STOP_REQUESTED: AtomicBool = AtomicBool::new(false);

extern "C" fn handle_signal(_sig: libc::c_int) {
    STOP_REQUESTED.store(true, Ordering::SeqCst);
}

#[derive(Debug, Subcommand)]
pub enum AudioCommand {
    /// Real-time FFT audio spectrum analyzer (drop-in replacement for cava raw ASCII output).
    Spectrum(SpectrumArgs),
    /// Live microphone RMS + peak-hold level meter (replaces scripts/audio/mic-level-meter.py).
    MicMeter(MicMeterArgs),
}

#[derive(Debug, Args)]
pub struct SpectrumArgs {
    /// Optional CAVA INI config file (-p <path>).
    #[arg(short = 'p', long = "config")]
    pub config: Option<String>,

    /// Number of output bars.
    #[arg(long, default_value_t = 64)]
    pub bars: usize,

    /// Output frames per second.
    #[arg(long, default_value_t = 30)]
    pub framerate: u32,

    /// Sensitivity percentage (100 = default).
    #[arg(long, default_value_t = 100)]
    pub sensitivity: u32,

    /// Stereo split output (left reversed + right).
    #[arg(long)]
    pub stereo: bool,

    /// Audio source name (default: @DEFAULT_MONITOR@).
    #[arg(long)]
    pub source: Option<String>,

    /// Maximum integer value per bar (cava ascii_max_range).
    #[arg(long, default_value_t = 1000)]
    pub max_range: u32,
}

#[derive(Debug, Args)]
pub struct MicMeterArgs {
    /// Target frames per second.
    #[arg(long, default_value_t = 30)]
    pub fps: u32,

    /// Audio source (default: @DEFAULT_SOURCE@).
    #[arg(long)]
    pub source: Option<String>,
}

// PulseAudio Simple C ABI loaded dynamically via libc::dlopen("libpulse-simple.so.0")
// so native builds require zero C headers or link-time dependencies.
#[repr(C)]
struct PaSampleSpec {
    format: c_int,
    rate: u32,
    channels: u8,
}

#[repr(C)]
struct PaBufferAttr {
    maxlength: u32,
    tlength: u32,
    prebuf: u32,
    minreq: u32,
    fragsize: u32,
}

const PA_STREAM_RECORD: c_int = 2;
const PA_SAMPLE_S16LE: c_int = 3;

type PaSimpleNewFn = unsafe extern "C" fn(
    server: *const c_char,
    name: *const c_char,
    dir: c_int,
    dev: *const c_char,
    stream_name: *const c_char,
    ss: *const PaSampleSpec,
    map: *const c_void,
    attr: *const PaBufferAttr,
    error: *mut c_int,
) -> *mut c_void;
type PaSimpleReadFn =
    unsafe extern "C" fn(s: *mut c_void, data: *mut c_void, bytes: usize, error: *mut c_int) -> c_int;
type PaSimpleFreeFn = unsafe extern "C" fn(s: *mut c_void);

enum AudioCapture {
    PulseSimple {
        lib: *mut c_void,
        handle: *mut c_void,
        read_fn: PaSimpleReadFn,
        free_fn: PaSimpleFreeFn,
    },
    Subprocess {
        child: std::process::Child,
        stdout: BufReader<std::process::ChildStdout>,
    },
}

#[derive(Clone, Copy)]
struct StreamIdentity {
    app_name: &'static str,
    stream_name: &'static str,
}

const SPECTRUM_IDENTITY: StreamIdentity = StreamIdentity {
    app_name: "alis-audio-spectrum",
    stream_name: "Alis Audio Analyzer",
};

const MIC_METER_IDENTITY: StreamIdentity = StreamIdentity {
    app_name: "alis-mic-meter",
    stream_name: "Alis Mic Meter",
};

impl AudioCapture {
    fn open(
        source: Option<&str>,
        rate: u32,
        channels: u8,
        frag_bytes: u32,
        capture_sink: bool,
        identity: StreamIdentity,
    ) -> Result<Self> {
        if let Ok(cap) = Self::open_pulse_simple(source, rate, channels, frag_bytes, identity) {
            return Ok(cap);
        }
        Self::open_subprocess(source, rate, channels, capture_sink, identity)
    }

    fn open_pulse_simple(
        source: Option<&str>,
        rate: u32,
        channels: u8,
        frag_bytes: u32,
        identity: StreamIdentity,
    ) -> Result<Self> {
        unsafe {
            let lib_name = CString::new("libpulse-simple.so.0").unwrap();
            let lib = libc::dlopen(lib_name.as_ptr(), libc::RTLD_LAZY | libc::RTLD_LOCAL);
            if lib.is_null() {
                bail!("libpulse-simple.so.0 not available");
            }
            let sym_new = libc::dlsym(lib, c"pa_simple_new".as_ptr());
            let sym_read = libc::dlsym(lib, c"pa_simple_read".as_ptr());
            let sym_free = libc::dlsym(lib, c"pa_simple_free".as_ptr());
            if sym_new.is_null() || sym_read.is_null() || sym_free.is_null() {
                libc::dlclose(lib);
                bail!("missing pa_simple symbols");
            }
            let new_fn: PaSimpleNewFn = std::mem::transmute(sym_new);
            let read_fn: PaSimpleReadFn = std::mem::transmute(sym_read);
            let free_fn: PaSimpleFreeFn = std::mem::transmute(sym_free);

            let app_name = CString::new(identity.app_name).unwrap();
            let stream_name = CString::new(identity.stream_name).unwrap();
            let dev_cstr = source
                .filter(|s| !s.is_empty() && *s != "auto")
                .and_then(|s| CString::new(s).ok());
            let ss = PaSampleSpec {
                format: PA_SAMPLE_S16LE,
                rate,
                channels,
            };
            let attr = PaBufferAttr {
                maxlength: u32::MAX,
                tlength: u32::MAX,
                prebuf: u32::MAX,
                minreq: u32::MAX,
                fragsize: frag_bytes.max(256),
            };
            let mut err: c_int = 0;
            let handle = new_fn(
                std::ptr::null(),
                app_name.as_ptr(),
                PA_STREAM_RECORD,
                dev_cstr
                    .as_ref()
                    .map(|c| c.as_ptr())
                    .unwrap_or(std::ptr::null()),
                stream_name.as_ptr(),
                &ss,
                std::ptr::null(),
                &attr,
                &mut err,
            );
            if handle.is_null() {
                libc::dlclose(lib);
                bail!("pa_simple_new failed (err={err})");
            }
            Ok(Self::PulseSimple {
                lib,
                handle,
                read_fn,
                free_fn,
            })
        }
    }

    fn build_pw_cat_record_args(
        target: Option<&str>,
        rate: u32,
        channels: u8,
        capture_sink: bool,
    ) -> Vec<String> {
        let mut args = vec![
            "--record".to_string(),
            "--raw".to_string(),
            "--format".to_string(),
            "s16".to_string(),
            "--rate".to_string(),
            rate.to_string(),
            "--channels".to_string(),
            channels.to_string(),
        ];
        if let Some(dev) = target.filter(|s| !s.is_empty() && *s != "auto" && !s.starts_with('@')) {
            args.push("--target".to_string());
            args.push(dev.to_string());
        }
        if capture_sink {
            args.push("-P".to_string());
            args.push("stream.capture.sink=true".to_string());
        }
        args.push("-".to_string());
        args
    }

    fn spawn_pw_cat_record(
        target: Option<&str>,
        rate: u32,
        channels: u8,
        capture_sink: bool,
    ) -> std::io::Result<std::process::Child> {
        let mut pw = Command::new("pw-cat");
        pw.args(Self::build_pw_cat_record_args(target, rate, channels, capture_sink));
        pw.stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::null());
        unsafe {
            pw.pre_exec(|| {
                libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM);
                Ok(())
            });
        }
        pw.spawn()
    }

    fn open_pw_stream_target(target: &str, rate: u32, channels: u8, capture_sink: bool) -> Result<Self> {
        let mut child = Self::spawn_pw_cat_record(Some(target), rate, channels, capture_sink)
            .context("spawn pw-cat")?;
        let stdout = child
            .stdout
            .take()
            .ok_or_else(|| anyhow!("pw-cat stdout missing"))?;
        Ok(Self::Subprocess {
            child,
            stdout: BufReader::new(stdout),
        })
    }

    fn open_subprocess(
        source: Option<&str>,
        rate: u32,
        channels: u8,
        capture_sink: bool,
        identity: StreamIdentity,
    ) -> Result<Self> {
        let client_arg = format!("--client-name={}", identity.app_name);
        let stream_arg = format!("--stream-name={}", identity.app_name);
        let mut cmd = Command::new("parec");
        cmd.args([
            "--format=s16le",
            &format!("--rate={rate}"),
            &format!("--channels={channels}"),
            "--latency-msec=25",
            &client_arg,
            &stream_arg,
        ]);
        if let Some(dev) = source.filter(|s| !s.is_empty() && *s != "auto") {
            cmd.args(["--device", dev]);
        }
        cmd.stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::null());
        unsafe {
            cmd.pre_exec(|| {
                libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM);
                Ok(())
            });
        }
        let mut child = cmd
            .spawn()
            .or_else(|_| Self::spawn_pw_cat_record(source, rate, channels, capture_sink))?;
        let stdout = child
            .stdout
            .take()
            .ok_or_else(|| anyhow!("audio subprocess stdout missing"))?;
        Ok(Self::Subprocess {
            child,
            stdout: BufReader::new(stdout),
        })
    }

    fn read_exact(&mut self, buf: &mut [u8]) -> Result<()> {
        match self {
            Self::PulseSimple {
                handle, read_fn, ..
            } => {
                let mut err: c_int = 0;
                let rc = unsafe { read_fn(*handle, buf.as_mut_ptr() as *mut c_void, buf.len(), &mut err) };
                if rc < 0 {
                    bail!("pa_simple_read error {err}");
                }
                Ok(())
            }
            Self::Subprocess { stdout, .. } => {
                stdout.read_exact(buf).context("read audio subprocess PCM")
            }
        }
    }
}

impl Drop for AudioCapture {
    fn drop(&mut self) {
        match self {
            Self::PulseSimple {
                lib,
                handle,
                free_fn,
                ..
            } => unsafe {
                if !handle.is_null() {
                    free_fn(*handle);
                }
                if !lib.is_null() {
                    libc::dlclose(*lib);
                }
            },
            Self::Subprocess { child, .. } => {
                let _ = child.kill();
                let _ = child.wait();
            }
        }
    }
}

/// Pure-Rust in-place iterative Radix-2 Cooley-Tukey FFT.
pub fn fft_radix2(re: &mut [f64], im: &mut [f64]) {
    let n = re.len();
    debug_assert!(n.is_power_of_two() && im.len() == n);

    let mut j = 0usize;
    for i in 1..n {
        let mut bit = n >> 1;
        while (j & bit) != 0 {
            j ^= bit;
            bit >>= 1;
        }
        j ^= bit;
        if i < j {
            re.swap(i, j);
            im.swap(i, j);
        }
    }

    let mut len = 2usize;
    while len <= n {
        let ang = -2.0 * std::f64::consts::PI / (len as f64);
        let wlen_re = ang.cos();
        let wlen_im = ang.sin();
        let half = len >> 1;
        let mut i = 0;
        while i < n {
            let mut w_re = 1.0;
            let mut w_im = 0.0;
            for k in 0..half {
                let u_re = re[i + k];
                let u_im = im[i + k];
                let v_re = re[i + k + half] * w_re - im[i + k + half] * w_im;
                let v_im = re[i + k + half] * w_im + im[i + k + half] * w_re;
                re[i + k] = u_re + v_re;
                im[i + k] = u_im + v_im;
                re[i + k + half] = u_re - v_re;
                im[i + k + half] = u_im - v_im;
                let next_re = w_re * wlen_re - w_im * wlen_im;
                w_im = w_re * wlen_im + w_im * wlen_re;
                w_re = next_re;
            }
            i += len;
        }
        len <<= 1;
    }
}

fn compute_bands(samples: &[f64], sample_rate: f64, num_bars: usize, fft_size: usize) -> Vec<f64> {
    let mut re = vec![0.0_f64; fft_size];
    let mut im = vec![0.0_f64; fft_size];
    let copy_len = samples.len().min(fft_size);
    let offset = samples.len().saturating_sub(copy_len);
    for i in 0..copy_len {
        let hann = 0.5 * (1.0 - (2.0 * std::f64::consts::PI * i as f64 / (fft_size - 1) as f64).cos());
        re[i] = samples[offset + i] * hann;
    }
    fft_radix2(&mut re, &mut im);

    let half = fft_size / 2;
    let mut mag = vec![0.0_f64; half];
    let norm = 2.0 / (fft_size as f64);
    for i in 0..half {
        mag[i] = (re[i] * re[i] + im[i] * im[i]).sqrt() * norm;
    }

    let low_hz = 50.0_f64;
    let high_hz = (sample_rate * 0.45).min(10_000.0_f64);
    let hz_per_bin = sample_rate / (fft_size as f64);
    let mut bands = vec![0.0_f64; num_bars];

    for (b, slot) in bands.iter_mut().enumerate().take(num_bars) {
        let f0 = low_hz * (high_hz / low_hz).powf(b as f64 / num_bars.max(1) as f64);
        let f1 = low_hz * (high_hz / low_hz).powf((b + 1) as f64 / num_bars.max(1) as f64);
        let bin0 = ((f0 / hz_per_bin).floor() as usize).clamp(1, half.saturating_sub(1));
        let bin1 = ((f1 / hz_per_bin).ceil() as usize).clamp(bin0 + 1, half);
        let mut peak = 0.0_f64;
        for &m in &mag[bin0..bin1] {
            if m > peak {
                peak = m;
            }
        }
        // Gentle frequency compensation so highs remain visible alongside bass
        let eq = 1.0 + 1.8 * (b as f64 / num_bars.max(1) as f64);
        *slot = peak * eq;
    }
    bands
}

fn parse_cava_config(path: &str, args: &mut SpectrumArgs) {
    let Ok(file) = fs::File::open(path) else {
        return;
    };
    let mut section = String::new();
    for line in BufReader::new(file).lines().map_while(Result::ok) {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') || trimmed.starts_with(';') {
            continue;
        }
        if trimmed.starts_with('[') && trimmed.ends_with(']') {
            section = trimmed[1..trimmed.len() - 1].trim().to_ascii_lowercase();
            continue;
        }
        let Some((k, v)) = trimmed.split_once('=') else {
            continue;
        };
        let key = k.trim().to_ascii_lowercase();
        let val = v.trim().trim_matches('\'').trim_matches('"');
        match (section.as_str(), key.as_str()) {
            ("general", "bars") => {
                if let Ok(n) = val.parse::<usize>() {
                    args.bars = n.clamp(2, 512);
                }
            }
            ("general", "framerate") => {
                if let Ok(n) = val.parse::<u32>() {
                    args.framerate = n.clamp(5, 240);
                }
            }
            ("general", "sensitivity") => {
                if let Ok(n) = val.parse::<u32>() {
                    args.sensitivity = n.clamp(1, 2000);
                }
            }
            ("input", "source") if !val.is_empty() => {
                args.source = Some(val.to_string());
            }
            ("output", "channels") => {
                args.stereo = val.eq_ignore_ascii_case("stereo");
            }
            ("output", "ascii_max_range") => {
                if let Ok(n) = val.parse::<u32>() {
                    args.max_range = n.clamp(10, 10000);
                }
            }
            _ => {}
        }
    }
}

fn parse_pw_stream_serial(raw: &str) -> Option<&str> {
    let trimmed = raw.trim();
    let base = trimmed.strip_suffix(".monitor").unwrap_or(trimmed);
    if !base.is_empty() && base.bytes().all(|b| b.is_ascii_digit()) {
        Some(base)
    } else {
        None
    }
}

fn parse_sink_id_for_stream_serial(pactl_sink_inputs: &str, serial: &str) -> Option<String> {
    let needle = format!("object.serial = \"{serial}\"");
    let mut current_index: Option<&str> = None;
    let mut current_sink: Option<String> = None;
    let mut current_matches = false;

    for raw_line in pactl_sink_inputs.lines() {
        let trimmed = raw_line.trim();
        if let Some(rest) = trimmed.strip_prefix("Sink Input #") {
            if (current_matches || current_index == Some(serial)) && current_sink.is_some() {
                return current_sink;
            }
            current_index = rest.split_whitespace().next();
            current_sink = None;
            current_matches = current_index == Some(serial);
            continue;
        }
        if let Some(rest) = trimmed.strip_prefix("Sink:") {
            current_sink = rest.split_whitespace().next().map(str::to_string);
        } else if trimmed == needle {
            current_matches = true;
        }
    }

    if current_matches || current_index == Some(serial) {
        current_sink
    } else {
        None
    }
}

fn pw_stream_serial_exists(serial: &str) -> bool {
    let Ok(out) = Command::new("pactl").args(["list", "sink-inputs"]).output() else {
        return false;
    };
    if !out.status.success() {
        return false;
    }
    let needle = format!("object.serial = \"{serial}\"");
    String::from_utf8_lossy(&out.stdout).contains(&needle)
}

fn pulse_source_exists(name: &str) -> Option<bool> {
    let out = Command::new("pactl").args(["list", "short", "sources"]).output().ok()?;
    if !out.status.success() {
        return None;
    }
    let found = String::from_utf8_lossy(&out.stdout)
        .lines()
        .any(|line| line.split_whitespace().nth(1) == Some(name));
    Some(found)
}

fn pw_stream_sink_monitor(serial: &str) -> Option<String> {
    let sink_inputs = Command::new("pactl").args(["list", "sink-inputs"]).output().ok()?;
    if !sink_inputs.status.success() {
        return None;
    }
    let sink_id =
        parse_sink_id_for_stream_serial(&String::from_utf8_lossy(&sink_inputs.stdout), serial)?;
    let sinks = Command::new("pactl").args(["list", "short", "sinks"]).output().ok()?;
    if !sinks.status.success() {
        return None;
    }
    let sinks_text = String::from_utf8_lossy(&sinks.stdout);
    let sink_name = sinks_text.lines().find_map(|line| {
        let mut cols = line.split_whitespace();
        let id = cols.next()?;
        let name = cols.next()?;
        (id == sink_id).then(|| name.to_string())
    })?;
    let monitor = format!("{sink_name}.monitor");
    if pulse_source_exists(&monitor) == Some(false) {
        None
    } else {
        Some(monitor)
    }
}

fn resolve_default_monitor() -> String {
    if let Ok(out) = Command::new("pactl").arg("get-default-sink").output()
        && out.status.success()
    {
        let sink = String::from_utf8_lossy(&out.stdout).trim().to_string();
        if !sink.is_empty() {
            return format!("{sink}.monitor");
        }
    }
    if let Ok(out) = Command::new("pactl").args(["list", "short", "sources"]).output()
        && out.status.success()
    {
        for line in String::from_utf8_lossy(&out.stdout).lines() {
            if let Some(src) = line.split_whitespace().nth(1)
                && src.ends_with(".monitor")
            {
                return src.to_string();
            }
        }
    }
    "@DEFAULT_MONITOR@".to_string()
}

fn run_spectrum(mut args: SpectrumArgs) -> Result<i32> {
    if let Some(cfg_path) = args.config.clone() {
        parse_cava_config(&cfg_path, &mut args);
    }

    let rate = 44_100u32;
    let channels: u8 = if args.stereo { 2 } else { 1 };
    let fps = args.framerate.clamp(10, 165);
    let bars = args.bars.clamp(2, 512);
    let max_range = args.max_range as f64;
    let sensitivity = (args.sensitivity as f64 / 100.0).max(0.05);

    let raw_source = args.source.as_deref().map(str::trim);

    let stdout = io::stdout();
    let mut out = io::BufWriter::new(stdout.lock());

    // Silent placeholder mode when config explicitly requests __alis_no_music__
    if raw_source == Some("__alis_no_music__") {
        let zero_line = format!("{};\n", vec!["0"; bars].join(";"));
        let frame_dur = Duration::from_secs_f64(1.0 / fps as f64);
        while !STOP_REQUESTED.load(Ordering::SeqCst) {
            if out.write_all(zero_line.as_bytes()).is_err() || out.flush().is_err() {
                break;
            }
            std::thread::sleep(frame_dur);
        }
        return Ok(0);
    }

    let frames_per_read = ((rate / fps) as usize).max(256);
    let bytes_per_read = frames_per_read * (channels as usize) * 2;

    // PipeWire stream serials (e.g. "691.monitor" from `accel cava-config`) are
    // not valid PulseAudio source names — passing them to `pa_simple_new` makes
    // pipewire-pulse silently fall back to the default microphone. Prefer the
    // owning sink's `.monitor` source via libpulse-simple, then `pw-cat`, and
    // finally the default output monitor source.
    let (mut capture, mut tried_default_fallback) =
        if let Some(serial) = raw_source.and_then(parse_pw_stream_serial) {
            if let Some(sink_monitor) = pw_stream_sink_monitor(serial)
                && let Ok(cap) = AudioCapture::open(
                    Some(&sink_monitor),
                    rate,
                    channels,
                    bytes_per_read as u32,
                    true,
                    SPECTRUM_IDENTITY,
                )
            {
                (cap, false)
            } else if pw_stream_serial_exists(serial)
                && let Ok(cap) = AudioCapture::open_pw_stream_target(serial, rate, channels, true)
            {
                (cap, false)
            } else {
                let monitor = resolve_default_monitor();
                (
                    AudioCapture::open(
                        Some(&monitor),
                        rate,
                        channels,
                        bytes_per_read as u32,
                        true,
                        SPECTRUM_IDENTITY,
                    )?,
                    true,
                )
            }
        } else {
            let (resolved, is_default) = match raw_source {
                None | Some("") | Some("auto") | Some("@DEFAULT_MONITOR@") => {
                    (resolve_default_monitor(), true)
                }
                Some(other) => {
                    // Guard against passing an unknown node name to pa_simple_new (which
                    // would silently attach to the microphone on pipewire-pulse).
                    if pulse_source_exists(other) == Some(false) {
                        (resolve_default_monitor(), true)
                    } else {
                        (other.to_string(), false)
                    }
                }
            };
            match AudioCapture::open(
                Some(&resolved),
                rate,
                channels,
                bytes_per_read as u32,
                true,
                SPECTRUM_IDENTITY,
            ) {
                Ok(cap) => (cap, is_default),
                Err(_) if !is_default => {
                    let monitor = resolve_default_monitor();
                    (
                        AudioCapture::open(
                            Some(&monitor),
                            rate,
                            channels,
                            bytes_per_read as u32,
                            true,
                            SPECTRUM_IDENTITY,
                        )?,
                        true,
                    )
                }
                Err(err) => return Err(err),
            }
        };

    let fft_size = 2048usize;
    let mut ring_l = vec![0.0_f64; fft_size];
    let mut ring_r = vec![0.0_f64; fft_size];
    let mut pcm = vec![0u8; bytes_per_read];
    let mut smoothed = vec![0.0_f64; bars];
    let mut agc_gain = 18.0_f64 * sensitivity;
    let mut line_buf = String::with_capacity(bars * 5);
    let mut got_frame = false;

    while !STOP_REQUESTED.load(Ordering::SeqCst) {
        if capture.read_exact(&mut pcm).is_err() {
            if !got_frame && !tried_default_fallback {
                tried_default_fallback = true;
                let monitor = resolve_default_monitor();
                if let Ok(fallback) = AudioCapture::open(
                    Some(&monitor),
                    rate,
                    channels,
                    bytes_per_read as u32,
                    true,
                    SPECTRUM_IDENTITY,
                ) {
                    capture = fallback;
                    continue;
                }
            }
            break;
        }
        got_frame = true;
        let sample_frames = pcm.len() / (2 * channels as usize);
        let shift = sample_frames.min(fft_size);
        ring_l.copy_within(shift.., 0);
        if args.stereo {
            ring_r.copy_within(shift.., 0);
            for i in 0..shift {
                let off = (sample_frames - shift + i) * 4;
                let sl = i16::from_le_bytes([pcm[off], pcm[off + 1]]) as f64 / 32768.0;
                let sr = i16::from_le_bytes([pcm[off + 2], pcm[off + 3]]) as f64 / 32768.0;
                ring_l[fft_size - shift + i] = sl;
                ring_r[fft_size - shift + i] = sr;
            }
        } else {
            for i in 0..shift {
                let off = (sample_frames - shift + i) * 2;
                let s = i16::from_le_bytes([pcm[off], pcm[off + 1]]) as f64 / 32768.0;
                ring_l[fft_size - shift + i] = s;
            }
        }

        let raw_bars = if args.stereo {
            let half = bars / 2;
            let mut left = compute_bands(&ring_l, rate as f64, half, fft_size);
            left.reverse();
            let right = compute_bands(&ring_r, rate as f64, bars - half, fft_size);
            left.extend(right);
            left
        } else {
            compute_bands(&ring_l, rate as f64, bars, fft_size)
        };

        let frame_peak = raw_bars.iter().copied().fold(0.0_f64, f64::max);
        if frame_peak * agc_gain > 0.95 {
            agc_gain = (0.95 / frame_peak).max(1.0);
        } else if frame_peak > 0.0005 {
            agc_gain = (agc_gain * 1.008).min(80.0 * sensitivity);
        }

        line_buf.clear();
        for i in 0..bars {
            let scaled = (raw_bars[i] * agc_gain).clamp(0.0, 1.0);
            // Fast attack, smooth gravity decay
            let prev = smoothed[i];
            let next = if scaled >= prev {
                prev + (scaled - prev) * 0.65
            } else {
                prev * 0.78 + scaled * 0.22
            };
            smoothed[i] = if next < 0.002 { 0.0 } else { next };
            let int_val = (smoothed[i] * max_range).round().clamp(0.0, max_range) as u32;
            use std::fmt::Write as _;
            let _ = write!(&mut line_buf, "{int_val};");
        }
        line_buf.push('\n');
        if out.write_all(line_buf.as_bytes()).is_err() || out.flush().is_err() {
            break;
        }
    }

    Ok(0)
}

fn run_mic_meter(args: MicMeterArgs) -> Result<i32> {
    let rate = 16_000u32;
    let fps = args.fps.clamp(5, 60);
    let source = args
        .source
        .as_deref()
        .unwrap_or("@DEFAULT_SOURCE@");
    let frames_per_read = ((rate / fps) as usize).max(160);
    let bytes_per_read = frames_per_read * 2;
    let mut capture = AudioCapture::open(
        Some(source),
        rate,
        1,
        bytes_per_read as u32,
        false,
        MIC_METER_IDENTITY,
    )?;

    let mut pcm = vec![0u8; bytes_per_read];
    let mut smooth_level = 0.0_f64;
    let mut peak = 0.0_f64;
    let mut peak_time = Instant::now();
    let stdout = io::stdout();
    let mut out = io::BufWriter::new(stdout.lock());

    while !STOP_REQUESTED.load(Ordering::SeqCst) {
        if capture.read_exact(&mut pcm).is_err() {
            break;
        }
        let mut sum_sq = 0.0_f64;
        let samples = pcm.len() / 2;
        for chunk in pcm.chunks_exact(2) {
            let s = i16::from_le_bytes([chunk[0], chunk[1]]) as f64 / 32768.0;
            sum_sq += s * s;
        }
        let rms = (sum_sq / samples.max(1) as f64).sqrt();
        // Perceptual dB mapping (-55 dBFS .. -4 dBFS -> 0..1)
        let db = 20.0 * rms.max(1e-7).log10();
        let normalized = ((db + 55.0) / 51.0).clamp(0.0, 1.0);
        smooth_level = if normalized > smooth_level {
            smooth_level * 0.35 + normalized * 0.65
        } else {
            smooth_level * 0.72 + normalized * 0.28
        };
        if smooth_level >= peak {
            peak = smooth_level;
            peak_time = Instant::now();
        } else if peak_time.elapsed() >= Duration::from_millis(650) {
            peak = (peak - 0.04).max(smooth_level);
        }
        if writeln!(out, "{smooth_level:.4} {peak:.4}").is_err() || out.flush().is_err() {
            break;
        }
    }
    Ok(0)
}

pub fn run(command: AudioCommand) -> Result<i32> {
    STOP_REQUESTED.store(false, Ordering::SeqCst);
    unsafe {
        libc::signal(libc::SIGTERM, handle_signal as *const () as libc::sighandler_t);
        libc::signal(libc::SIGINT, handle_signal as *const () as libc::sighandler_t);
    }
    match command {
        AudioCommand::Spectrum(args) => run_spectrum(args),
        AudioCommand::MicMeter(args) => run_mic_meter(args),
    }
}

#[cfg(test)]
mod tests {
    use super::{
        AudioCapture, compute_bands, fft_radix2, parse_pw_stream_serial,
        parse_sink_id_for_stream_serial,
    };

    #[test]
    fn fft_detects_pure_sine_wave_bin() {
        let n = 1024usize;
        let sr = 44100.0;
        let freq = 1000.0;
        let mut samples = vec![0.0_f64; n];
        for (i, s) in samples.iter_mut().enumerate() {
            *s = (2.0 * std::f64::consts::PI * freq * i as f64 / sr).sin();
        }
        let mut re = samples.clone();
        let mut im = vec![0.0_f64; n];
        fft_radix2(&mut re, &mut im);
        let peak_bin = (1..n / 2)
            .max_by(|&a, &b| {
                let ma = re[a] * re[a] + im[a] * im[a];
                let mb = re[b] * re[b] + im[b] * im[b];
                ma.total_cmp(&mb)
            })
            .unwrap();
        let expected_bin = (freq * n as f64 / sr).round() as usize;
        assert!((peak_bin as i32 - expected_bin as i32).abs() <= 1);

        let bands = compute_bands(&samples, sr, 32, n);
        assert_eq!(bands.len(), 32);
        assert!(bands.iter().copied().fold(0.0_f64, f64::max) > 0.2);
    }

    #[test]
    fn pw_cat_record_args_use_short_properties_flag() {
        let with_sink = AudioCapture::build_pw_cat_record_args(Some("691"), 44100, 2, true);
        assert!(!with_sink.iter().any(|arg| arg == "--stream-properties"));
        let prop_idx = with_sink.iter().position(|arg| arg == "-P").unwrap();
        assert_eq!(with_sink[prop_idx + 1], "stream.capture.sink=true");
        let target_idx = with_sink.iter().position(|arg| arg == "--target").unwrap();
        assert_eq!(with_sink[target_idx + 1], "691");
        assert_eq!(with_sink.last().map(String::as_str), Some("-"));

        let without_sink =
            AudioCapture::build_pw_cat_record_args(Some("@DEFAULT_MONITOR@"), 16000, 1, false);
        assert!(!without_sink.iter().any(|arg| arg == "-P" || arg == "--target"));
        assert_eq!(without_sink.last().map(String::as_str), Some("-"));
    }

    #[test]
    fn parse_sink_id_for_stream_serial_extracts_sink() {
        let fixture = "\
Sink Input #691
\tDriver: PipeWire
\tSink: 33
\tProperties:
\t\tapplication.name = \"Zen\"
\t\tobject.serial = \"691\"

Sink Input #1799
\tDriver: PipeWire
\tSink: 84
\tProperties:
\t\tobject.serial = \"1799\"
";
        assert_eq!(
            parse_sink_id_for_stream_serial(fixture, "691").as_deref(),
            Some("33")
        );
        assert_eq!(
            parse_sink_id_for_stream_serial(fixture, "1799").as_deref(),
            Some("84")
        );
        assert_eq!(parse_sink_id_for_stream_serial(fixture, "9999"), None);
        assert_eq!(parse_pw_stream_serial("691.monitor"), Some("691"));
        assert_eq!(parse_pw_stream_serial("easyeffects_sink.monitor"), None);
    }
}
