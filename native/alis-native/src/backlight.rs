use anyhow::{Context, Result, anyhow, bail};
use clap::{Args, Subcommand};
use serde_json::json;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

#[derive(Debug, Subcommand)]
pub enum BacklightCommand {
    /// List backlight devices in machine-readable format (`name,backlight,cur,pct%,max`) or JSON.
    List {
        #[arg(long)]
        json: bool,
    },
    /// Read `<current> <max>` for a backlight device (auto-selects highest-range device if omitted).
    Get {
        device: Option<String>,
    },
    /// Set backlight brightness (`32768`, `50%`, `+5%`, `-5%`, `5%+`, `5%-`).
    Set(SetArgs),
}

#[derive(Debug, Args)]
pub struct SetArgs {
    /// Target value: raw integer (`32768`), percent (`50%`), or delta (`+5%`, `-5%`, `5%+`, `5%-`).
    pub target: String,
    /// Specific sysfs backlight device name (defaults to highest-range device).
    #[arg(short = 'd', long)]
    pub device: Option<String>,
    /// Minimum raw hardware value to clamp to (default: 1 when max > 0).
    #[arg(long, default_value_t = 1)]
    pub min_value: u64,
}

#[derive(Debug, Clone)]
struct BacklightDevice {
    name: String,
    path: PathBuf,
    current: u64,
    max: u64,
}

fn sysfs_root() -> PathBuf {
    env::var_os("ALIS_BACKLIGHT_SYSFS_DIR")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/sys/class/backlight"))
}

fn read_u64_trimmed(path: &Path) -> Result<u64> {
    let raw = fs::read_to_string(path)
        .with_context(|| format!("failed to read {}", path.display()))?;
    raw.trim()
        .parse::<u64>()
        .with_context(|| format!("invalid integer in {}", path.display()))
}

fn enumerate_devices(root: &Path) -> Vec<BacklightDevice> {
    let Ok(entries) = fs::read_dir(root) else {
        return Vec::new();
    };
    let mut out = Vec::new();
    for entry in entries.flatten() {
        let name = entry.file_name().to_string_lossy().into_owned();
        if name.starts_with('.') {
            continue;
        }
        let path = entry.path();
        let Ok(max) = read_u64_trimmed(&path.join("max_brightness")) else {
            continue;
        };
        if max == 0 {
            continue;
        }
        let current = read_u64_trimmed(&path.join("brightness"))
            .or_else(|_| read_u64_trimmed(&path.join("actual_brightness")))
            .unwrap_or(max);
        out.push(BacklightDevice {
            name,
            path,
            current: current.min(max),
            max,
        });
    }
    out.sort_by(|a, b| a.max.cmp(&b.max).then_with(|| a.name.cmp(&b.name)));
    out
}

fn resolve_device(root: &Path, requested: Option<&str>) -> Result<BacklightDevice> {
    let devices = enumerate_devices(root);
    if devices.is_empty() {
        bail!("no backlight devices found in {}", root.display());
    }
    if let Some(req) = requested.filter(|s| !s.trim().is_empty()) {
        if let Some(found) = devices.iter().find(|d| d.name == req) {
            return Ok(found.clone());
        }
        bail!("backlight device '{}' not found", req);
    }
    devices
        .last()
        .cloned()
        .ok_or_else(|| anyhow!("no usable backlight device"))
}

fn compute_target_raw(target: &str, current: u64, max: u64, min_value: u64) -> Result<u64> {
    let s = target.trim();
    if s.is_empty() {
        bail!("empty brightness target");
    }
    let floor = min_value.min(max);
    let raw_i128: i128 = if let Some(rest) = s.strip_suffix("%+") {
        let pct: f64 = rest.trim().parse().context("invalid percent delta")?;
        let step = ((pct / 100.0) * (max as f64)).round().max(1.0) as i128;
        (current as i128) + step
    } else if let Some(rest) = s.strip_suffix("%-") {
        let pct: f64 = rest.trim().parse().context("invalid percent delta")?;
        let step = ((pct / 100.0) * (max as f64)).round().max(1.0) as i128;
        (current as i128) - step
    } else if let Some(rest) = s.strip_suffix('%') {
        let trimmed = rest.trim();
        if let Some(pos) = trimmed.strip_prefix('+') {
            let pct: f64 = pos.trim().parse().context("invalid +percent delta")?;
            let step = ((pct / 100.0) * (max as f64)).round().max(1.0) as i128;
            (current as i128) + step
        } else if let Some(neg) = trimmed.strip_prefix('-') {
            let pct: f64 = neg.trim().parse().context("invalid -percent delta")?;
            let step = ((pct / 100.0) * (max as f64)).round().max(1.0) as i128;
            (current as i128) - step
        } else {
            let pct: f64 = trimmed.parse().context("invalid percent value")?;
            (((pct.clamp(0.0, 100.0)) / 100.0) * (max as f64)).round() as i128
        }
    } else if let Some(pos) = s.strip_prefix('+') {
        let delta: i128 = pos.trim().parse().context("invalid +raw delta")?;
        (current as i128) + delta
    } else if let Some(neg) = s.strip_prefix('-') {
        let delta: i128 = neg.trim().parse().context("invalid -raw delta")?;
        (current as i128) - delta
    } else {
        s.parse::<i128>().context("invalid raw brightness value")?
    };

    Ok(raw_i128.clamp(floor as i128, max as i128) as u64)
}

fn logind_set_brightness(device_name: &str, raw: u32) -> bool {
    let raw_str = raw.to_string();
    let mut session_paths = vec![
        "/org/freedesktop/login1/session/auto".to_string(),
        "/org/freedesktop/login1/session/self".to_string(),
    ];
    if let Ok(sid) = env::var("XDG_SESSION_ID") {
        let trimmed = sid.trim();
        if !trimmed.is_empty() && trimmed.chars().all(|c| c.is_ascii_alphanumeric()) {
            session_paths.push(format!("/org/freedesktop/login1/session/_{trimmed}"));
            session_paths.push(format!("/org/freedesktop/login1/session/{trimmed}"));
        }
    }

    for obj_path in &session_paths {
        if let Ok(status) = Command::new("/usr/bin/busctl")
            .args([
                "--system",
                "--quiet",
                "call",
                "org.freedesktop.login1",
                obj_path.as_str(),
                "org.freedesktop.login1.Session",
                "SetBrightness",
                "ssu",
                "backlight",
                device_name,
                raw_str.as_str(),
            ])
            .status()
            && status.success()
        {
            return true;
        }
    }
    false
}

fn write_brightness(dev: &BacklightDevice, raw: u64) -> Result<()> {
    let brightness_file = dev.path.join("brightness");

    if let Some(log_path) = env::var_os("ALIS_BACKLIGHT_WRITE_LOG").filter(|v| !v.is_empty()) {
        let _ = fs::write(&brightness_file, format!("{raw}\n"));
        let mut prev = fs::read_to_string(&log_path).unwrap_or_default();
        prev.push_str(&format!("{raw}\n"));
        fs::write(&log_path, prev)
            .with_context(|| format!("failed writing ALIS_BACKLIGHT_WRITE_LOG"))?;
        return Ok(());
    }

    if fs::write(&brightness_file, format!("{raw}\n")).is_ok() {
        return Ok(());
    }

    if let Ok(raw_u32) = u32::try_from(raw)
        && logind_set_brightness(&dev.name, raw_u32)
    {
        return Ok(());
    }

    if let Ok(status) = Command::new("brightnessctl")
        .args(["-d", &dev.name, "s", &raw.to_string(), "--quiet"])
        .status()
        && status.success()
    {
        return Ok(());
    }

    bail!(
        "unable to set brightness on {} (sysfs write and logind SetBrightness both failed)",
        dev.name
    )
}

pub fn run(cmd: BacklightCommand) -> Result<i32> {
    let root = sysfs_root();
    match cmd {
        BacklightCommand::List { json: want_json } => {
            let devices = enumerate_devices(&root);
            if want_json {
                let items: Vec<_> = devices
                    .iter()
                    .map(|d| {
                        let pct = ((d.current as f64 / d.max as f64) * 100.0).round() as u64;
                        json!({
                            "device": d.name,
                            "class": "backlight",
                            "current": d.current,
                            "percent": pct,
                            "max": d.max,
                        })
                    })
                    .collect();
                println!("{}", serde_json::to_string(&items)?);
            } else {
                for d in &devices {
                    let pct = ((d.current as f64 / d.max as f64) * 100.0).round() as u64;
                    println!("{},backlight,{},{}%,{}", d.name, d.current, pct, d.max);
                }
            }
            Ok(0)
        }
        BacklightCommand::Get { device } => {
            let dev = resolve_device(&root, device.as_deref())?;
            println!("{} {}", dev.current, dev.max);
            Ok(0)
        }
        BacklightCommand::Set(args) => {
            let dev = resolve_device(&root, args.device.as_deref())?;
            let raw = compute_target_raw(&args.target, dev.current, dev.max, args.min_value)?;
            write_brightness(&dev, raw)?;
            Ok(0)
        }
    }
}
