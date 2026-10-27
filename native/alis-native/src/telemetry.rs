use std::ffi::CString;
use std::fs;
use std::io::{self, Write};
use std::path::PathBuf;
use std::thread;
use std::time::Duration;

use anyhow::Result;
use clap::Args;
use serde_json::{Value, json};

#[derive(Debug, Args)]
pub struct TelemetryArgs {
    /// Emit a single JSON snapshot and exit.
    #[arg(long)]
    pub once: bool,

    /// Emit periodic JSON snapshots on stdout at this interval in milliseconds.
    #[arg(long, default_value_t = 3000)]
    pub interval_ms: u64,
}

#[derive(Default, Clone, Copy)]
struct CpuTotals {
    total: u64,
    idle: u64,
}

fn read_cpu_totals() -> Option<CpuTotals> {
    let text = fs::read_to_string("/proc/stat").ok()?;
    let first_line = text.lines().next()?;
    let mut parts = first_line.split_whitespace();
    if parts.next()? != "cpu" {
        return None;
    }
    let user: u64 = parts.next()?.parse().ok()?;
    let nice: u64 = parts.next()?.parse().ok()?;
    let system: u64 = parts.next()?.parse().ok()?;
    let idle_raw: u64 = parts.next()?.parse().ok()?;
    let iowait: u64 = parts.next().and_then(|s| s.parse().ok()).unwrap_or(0);
    let irq: u64 = parts.next().and_then(|s| s.parse().ok()).unwrap_or(0);
    let softirq: u64 = parts.next().and_then(|s| s.parse().ok()).unwrap_or(0);
    let total = user + nice + system + idle_raw + iowait + irq + softirq;
    let idle = idle_raw + iowait;
    Some(CpuTotals { total, idle })
}

fn read_meminfo() -> (u64, u64, u64, u64) {
    let Ok(text) = fs::read_to_string("/proc/meminfo") else {
        return (0, 0, 0, 0);
    };
    let mut mem_total = 0;
    let mut mem_avail = 0;
    let mut swap_total = 0;
    let mut swap_free = 0;
    for line in text.lines() {
        if let Some(rest) = line.strip_prefix("MemTotal:") {
            mem_total = rest
                .split_whitespace()
                .next()
                .and_then(|s| s.parse().ok())
                .unwrap_or(0);
        } else if let Some(rest) = line.strip_prefix("MemAvailable:") {
            mem_avail = rest
                .split_whitespace()
                .next()
                .and_then(|s| s.parse().ok())
                .unwrap_or(0);
        } else if let Some(rest) = line.strip_prefix("SwapTotal:") {
            swap_total = rest
                .split_whitespace()
                .next()
                .and_then(|s| s.parse().ok())
                .unwrap_or(0);
        } else if let Some(rest) = line.strip_prefix("SwapFree:") {
            swap_free = rest
                .split_whitespace()
                .next()
                .and_then(|s| s.parse().ok())
                .unwrap_or(0);
        }
    }
    (mem_total, mem_avail, swap_total, swap_free)
}

fn read_netdev() -> (u64, u64) {
    let Ok(text) = fs::read_to_string("/proc/net/dev") else {
        return (0, 0);
    };
    let mut rx_total = 0u64;
    let mut tx_total = 0u64;
    for line in text.lines().skip(2) {
        let Some((iface, rest)) = line.split_once(':') else {
            continue;
        };
        if iface.trim() == "lo" {
            continue;
        }
        let mut cols = rest.split_whitespace();
        let rx: u64 = cols.next().and_then(|s| s.parse().ok()).unwrap_or(0);
        let tx: u64 = cols.nth(7).and_then(|s| s.parse().ok()).unwrap_or(0);
        rx_total = rx_total.saturating_add(rx);
        tx_total = tx_total.saturating_add(tx);
    }
    (rx_total, tx_total)
}

fn discover_hwmon_paths() -> (Option<PathBuf>, Option<PathBuf>) {
    let mut cpu_temp: Option<PathBuf> = None;
    let mut gpu_temp: Option<PathBuf> = None;
    let Ok(entries) = fs::read_dir("/sys/class/hwmon") else {
        return (None, None);
    };
    for entry in entries.flatten() {
        let dir = entry.path();
        let name = fs::read_to_string(dir.join("name"))
            .unwrap_or_default()
            .trim()
            .to_owned();
        let temp1 = dir.join("temp1_input");
        if !temp1.is_file() {
            continue;
        }
        match name.as_str() {
            "k10temp" | "coretemp" | "zenpower" | "cpu_thermal" | "acpitz" => {
                if cpu_temp.is_none() || name == "k10temp" || name == "coretemp" {
                    cpu_temp = Some(temp1);
                }
            }
            "amdgpu" | "nouveau" | "i915" | "xe" => {
                if gpu_temp.is_none() {
                    gpu_temp = Some(temp1);
                }
            }
            _ => {}
        }
    }
    (cpu_temp, gpu_temp)
}

fn discover_gpu_busy_path() -> Option<PathBuf> {
    let entries = fs::read_dir("/sys/class/drm").ok()?;
    for entry in entries.flatten() {
        let name = entry.file_name();
        let Some(name_str) = name.to_str() else {
            continue;
        };
        if !name_str.starts_with("card") || name_str.contains('-') {
            continue;
        }
        let busy = entry.path().join("device/gpu_busy_percent");
        if busy.is_file() {
            return Some(busy);
        }
    }
    None
}

fn read_temp_celsius(path: Option<&PathBuf>) -> i64 {
    let Some(p) = path else {
        return 0;
    };
    let raw: i64 = fs::read_to_string(p)
        .ok()
        .and_then(|s| s.trim().parse().ok())
        .unwrap_or(0);
    (raw + 500) / 1000
}

fn read_root_disk_kb() -> (u64, u64) {
    let Ok(c_path) = CString::new("/") else {
        return (1, 0);
    };
    unsafe {
        let mut stat: libc::statvfs = std::mem::zeroed();
        if libc::statvfs(c_path.as_ptr(), &mut stat) == 0 {
            let block_kb = (stat.f_frsize as u64) / 1024;
            let total_kb = (stat.f_blocks as u64).saturating_mul(block_kb).max(1);
            let avail_kb = (stat.f_bavail as u64).saturating_mul(block_kb);
            let used_kb = total_kb.saturating_sub(avail_kb);
            return (total_kb, used_kb);
        }
    }
    (1, 0)
}

pub fn run(args: TelemetryArgs) -> Result<Value> {
    let (cpu_temp_path, gpu_temp_path) = discover_hwmon_paths();
    let gpu_busy_path = discover_gpu_busy_path();
    let mut prev_cpu = read_cpu_totals();

    if args.once {
        thread::sleep(Duration::from_millis(40));
        let cur_cpu = read_cpu_totals();
        let cpu_usage = match (prev_cpu, cur_cpu) {
            (Some(p), Some(c)) if c.total > p.total => {
                let total_diff = (c.total - p.total) as f64;
                let idle_diff = c.idle.saturating_sub(p.idle) as f64;
                (1.0 - idle_diff / total_diff).clamp(0.0, 1.0)
            }
            _ => 0.0,
        };
        let (mem_total, mem_avail, swap_total, swap_free) = read_meminfo();
        let (rx_bytes, tx_bytes) = read_netdev();
        let (disk_total_kb, disk_used_kb) = read_root_disk_kb();
        let gpu_usage = gpu_busy_path
            .as_ref()
            .and_then(|p| fs::read_to_string(p).ok())
            .and_then(|s| s.trim().parse::<f64>().ok())
            .map(|v| (v / 100.0).clamp(0.0, 1.0))
            .unwrap_or(0.0);

        return Ok(json!({
            "memory_total_kb": mem_total,
            "memory_available_kb": mem_avail,
            "swap_total_kb": swap_total,
            "swap_free_kb": swap_free,
            "cpu_usage": cpu_usage,
            "network_rx_bytes": rx_bytes,
            "network_tx_bytes": tx_bytes,
            "cpu_temp_c": read_temp_celsius(cpu_temp_path.as_ref()),
            "gpu_temp_c": read_temp_celsius(gpu_temp_path.as_ref()),
            "gpu_usage": gpu_usage,
            "disk_total_kb": disk_total_kb,
            "disk_used_kb": disk_used_kb,
        }));
    }

    let sleep_dur = Duration::from_millis(args.interval_ms.max(100));
    let mut stdout = io::stdout().lock();
    loop {
        let cur_cpu = read_cpu_totals();
        let cpu_usage = match (prev_cpu, cur_cpu) {
            (Some(p), Some(c)) if c.total > p.total => {
                let total_diff = (c.total - p.total) as f64;
                let idle_diff = c.idle.saturating_sub(p.idle) as f64;
                (1.0 - idle_diff / total_diff).clamp(0.0, 1.0)
            }
            _ => 0.0,
        };
        prev_cpu = cur_cpu;

        let (mem_total, mem_avail, swap_total, swap_free) = read_meminfo();
        let (rx_bytes, tx_bytes) = read_netdev();
        let (disk_total_kb, disk_used_kb) = read_root_disk_kb();
        let gpu_usage = gpu_busy_path
            .as_ref()
            .and_then(|p| fs::read_to_string(p).ok())
            .and_then(|s| s.trim().parse::<f64>().ok())
            .map(|v| (v / 100.0).clamp(0.0, 1.0))
            .unwrap_or(0.0);

        let payload = json!({
            "memory_total_kb": mem_total,
            "memory_available_kb": mem_avail,
            "swap_total_kb": swap_total,
            "swap_free_kb": swap_free,
            "cpu_usage": cpu_usage,
            "network_rx_bytes": rx_bytes,
            "network_tx_bytes": tx_bytes,
            "cpu_temp_c": read_temp_celsius(cpu_temp_path.as_ref()),
            "gpu_temp_c": read_temp_celsius(gpu_temp_path.as_ref()),
            "gpu_usage": gpu_usage,
            "disk_total_kb": disk_total_kb,
            "disk_used_kb": disk_used_kb,
        });
        writeln!(stdout, "{}", serde_json::to_string(&payload)?)?;
        stdout.flush()?;
        thread::sleep(sleep_dur);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_once_telemetry_snapshot_with_expected_keys() {
        let val = run(TelemetryArgs {
            once: true,
            interval_ms: 1000,
        })
        .expect("telemetry snapshot");
        assert!(val.get("memory_total_kb").and_then(Value::as_u64).unwrap_or(0) > 0);
        assert!(val.get("cpu_usage").is_some());
        assert!(val.get("disk_total_kb").is_some());
    }
}
