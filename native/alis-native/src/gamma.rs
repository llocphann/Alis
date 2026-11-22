use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use alis_wayland::{ShmBuffer, WlConnection, WlReader, WlWriter};
use anyhow::{Result, anyhow};
use clap::Args;

const ZWLR_GAMMA_MGR_GET: u16 = 0;
const ZWLR_GAMMA_MGR_DESTROY: u16 = 1;
const ZWLR_GAMMA_CTRL_SET_GAMMA: u16 = 0;
const ZWLR_GAMMA_CTRL_DESTROY: u16 = 1;
const ZWLR_GAMMA_CTRL_EV_SIZE: u16 = 0;
const ZWLR_GAMMA_CTRL_EV_FAILED: u16 = 1;

static STOP_REQUESTED: AtomicBool = AtomicBool::new(false);

extern "C" fn handle_signal(_sig: libc::c_int) {
    STOP_REQUESTED.store(true, Ordering::SeqCst);
}

#[derive(Debug, Args)]
pub struct GammaArgs {
    /// Night / low color temperature in Kelvin.
    #[arg(short = 't', long = "low-temp", default_value_t = 4000)]
    pub low_temp: u32,

    /// Day / high color temperature in Kelvin.
    #[arg(short = 'T', long = "high-temp", default_value_t = 6500)]
    pub high_temp: u32,

    /// Sunset time HH:MM (manual schedule).
    #[arg(short = 's', long = "sunset")]
    pub sunset: Option<String>,

    /// Sunrise time HH:MM (manual schedule).
    #[arg(short = 'S', long = "sunrise")]
    pub sunrise: Option<String>,

    /// Gamma exponent.
    #[arg(short = 'g', long = "gamma", default_value_t = 1.0)]
    pub gamma: f64,

    /// Transition duration in seconds (accepted for CLI compatibility).
    #[arg(short = 'd', long = "duration", default_value_t = 0)]
    pub _duration: u32,
}

/// Tanner Helland Planckian color temperature approximation normalized to 6500K.
pub fn kelvin_to_rgb_multipliers(kelvin: u32) -> (f64, f64, f64) {
    let temp = (kelvin.clamp(1000, 10000) as f64) / 100.0;
    let r = if temp <= 66.0 {
        255.0
    } else {
        (329.698727446 * (temp - 60.0).powf(-0.1332047592)).clamp(0.0, 255.0)
    };
    let g = if temp <= 66.0 {
        (99.4708025861 * temp.ln() - 161.1195681661).clamp(0.0, 255.0)
    } else {
        (288.1221695283 * (temp - 60.0).powf(-0.0755148492)).clamp(0.0, 255.0)
    };
    let b = if temp >= 66.0 {
        255.0
    } else if temp <= 19.0 {
        0.0
    } else {
        (138.5177312231 * (temp - 10.0).ln() - 305.0447927307).clamp(0.0, 255.0)
    };
    (r / 255.0, g / 255.0, b / 255.0)
}

pub fn build_gamma_ramp(size: usize, kelvin: u32, gamma: f64) -> Vec<u8> {
    let (mr, mg, mb) = kelvin_to_rgb_multipliers(kelvin);
    let inv_gamma = 1.0 / gamma.clamp(0.2, 5.0);
    let mut out = vec![0u8; size * 3 * 2];
    let denom = (size.saturating_sub(1)).max(1) as f64;
    for i in 0..size {
        let base = (i as f64 / denom).powf(inv_gamma);
        let rv = (base * mr * 65535.0).round().clamp(0.0, 65535.0) as u16;
        let gv = (base * mg * 65535.0).round().clamp(0.0, 65535.0) as u16;
        let bv = (base * mb * 65535.0).round().clamp(0.0, 65535.0) as u16;
        let ro = i * 2;
        let go = (size + i) * 2;
        let bo = (2 * size + i) * 2;
        out[ro..ro + 2].copy_from_slice(&rv.to_ne_bytes());
        out[go..go + 2].copy_from_slice(&gv.to_ne_bytes());
        out[bo..bo + 2].copy_from_slice(&bv.to_ne_bytes());
    }
    out
}

fn parse_hhmm(raw: &str) -> Option<u32> {
    let (h, m) = raw.trim().split_once(':')?;
    let hh: u32 = h.parse().ok()?;
    let mm: u32 = m.parse().ok()?;
    if hh < 24 && mm < 60 {
        Some(hh * 60 + mm)
    } else {
        None
    }
}

fn current_local_minute() -> u32 {
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as libc::time_t;
    let mut tm: libc::tm = unsafe { std::mem::zeroed() };
    unsafe {
        libc::localtime_r(&secs, &mut tm);
    }
    (tm.tm_hour.max(0) as u32) * 60 + (tm.tm_min.max(0) as u32)
}

fn desired_temperature(args: &GammaArgs) -> u32 {
    let Some(sunset) = args.sunset.as_deref().and_then(parse_hhmm) else {
        return args.low_temp;
    };
    let Some(sunrise) = args.sunrise.as_deref().and_then(parse_hhmm) else {
        return args.low_temp;
    };
    let now = current_local_minute();
    let is_night = if sunset == 0 && sunrise >= 23 * 60 + 58 {
        true
    } else if sunset < sunrise {
        now >= sunset && now < sunrise
    } else {
        now >= sunset || now < sunrise
    };
    if is_night {
        args.low_temp
    } else {
        args.high_temp
    }
}

fn apply_all_ramps(
    conn: &WlConnection,
    controls: &HashMap<u32, usize>,
    kelvin: u32,
    gamma: f64,
) -> Result<()> {
    for (&ctrl_id, &size) in controls {
        if size == 0 {
            continue;
        }
        let ramp = build_gamma_ramp(size, kelvin, gamma);
        let mut shm = ShmBuffer::new("alis-gamma", ramp.len())?;
        shm.as_mut_slice()[..ramp.len()].copy_from_slice(&ramp);
        let mut w = WlWriter::new();
        w.fd(shm.raw_fd());
        conn.send(ctrl_id, ZWLR_GAMMA_CTRL_SET_GAMMA, w)?;
    }
    Ok(())
}

pub fn run(args: GammaArgs) -> Result<i32> {
    STOP_REQUESTED.store(false, Ordering::SeqCst);
    unsafe {
        libc::signal(libc::SIGTERM, handle_signal as *const () as libc::sighandler_t);
        libc::signal(libc::SIGINT, handle_signal as *const () as libc::sighandler_t);
    }

    let mut conn = WlConnection::connect()?;
    let (registry, globals) = conn.get_globals()?;
    let gamma_mgr_g = globals
        .iter()
        .find(|g| g.interface == "zwlr_gamma_control_manager_v1")
        .ok_or_else(|| anyhow!("compositor does not advertise zwlr_gamma_control_manager_v1"))?
        .clone();
    let gamma_mgr = conn.bind_global(registry, gamma_mgr_g.name, "zwlr_gamma_control_manager_v1", 1)?;

    let mut controls: HashMap<u32, usize> = HashMap::new();
    for g in globals.iter().filter(|g| g.interface == "wl_output") {
        let out_id = conn.bind_global(registry, g.name, "wl_output", g.version.min(4))?;
        let ctrl_id = conn.next_id();
        let mut w = WlWriter::new();
        w.u32(ctrl_id).u32(out_id);
        conn.send(gamma_mgr, ZWLR_GAMMA_MGR_GET, w)?;
        controls.insert(ctrl_id, 0);
    }

    let events = conn.roundtrip()?;
    for ev in events {
        if let std::collections::hash_map::Entry::Occupied(mut e) = controls.entry(ev.object_id) {
            if ev.opcode == ZWLR_GAMMA_CTRL_EV_SIZE {
                let mut r = WlReader::new(&ev.payload);
                if let Ok(sz) = r.u32() {
                    e.insert(sz as usize);
                }
            } else if ev.opcode == ZWLR_GAMMA_CTRL_EV_FAILED {
                e.remove();
            }
        }
    }

    let mut current_temp = desired_temperature(&args);
    apply_all_ramps(&conn, &controls, current_temp, args.gamma)?;
    let _ = conn.roundtrip()?;

    let mut last_check = std::time::Instant::now();
    let mut disconnected = false;
    while !STOP_REQUESTED.load(Ordering::SeqCst) {
        match conn.recv_message_timeout(500) {
            Ok(Some(ev)) => {
                if WlConnection::check_display_error(&ev).is_err() {
                    disconnected = true;
                    break;
                }
                if ev.object_id == registry && ev.opcode == alis_wayland::WL_REGISTRY_EVENT_GLOBAL {
                    let mut r = WlReader::new(&ev.payload);
                    if let (Ok(name), Ok(iface), Ok(ver)) = (r.u32(), r.string(), r.u32())
                        && iface == "wl_output"
                        && let Ok(out_id) = conn.bind_global(registry, name, "wl_output", ver.min(4))
                    {
                        let ctrl_id = conn.next_id();
                        let mut w = WlWriter::new();
                        w.u32(ctrl_id).u32(out_id);
                        if conn.send(gamma_mgr, ZWLR_GAMMA_MGR_GET, w).is_ok() {
                            controls.insert(ctrl_id, 0);
                        }
                    }
                } else if let std::collections::hash_map::Entry::Occupied(mut e) =
                    controls.entry(ev.object_id)
                {
                    if ev.opcode == ZWLR_GAMMA_CTRL_EV_SIZE {
                        let mut r = WlReader::new(&ev.payload);
                        if let Ok(sz) = r.u32() {
                            e.insert(sz as usize);
                            let mut one = HashMap::new();
                            one.insert(ev.object_id, sz as usize);
                            let _ = apply_all_ramps(&conn, &one, current_temp, args.gamma);
                        }
                    } else if ev.opcode == ZWLR_GAMMA_CTRL_EV_FAILED {
                        e.remove();
                    }
                }
            }
            Ok(None) => {}
            Err(_) => {
                disconnected = true;
                break;
            }
        }
        if last_check.elapsed() >= Duration::from_secs(15) {
            last_check = std::time::Instant::now();
            let next_temp = desired_temperature(&args);
            if next_temp != current_temp {
                current_temp = next_temp;
                if apply_all_ramps(&conn, &controls, current_temp, args.gamma).is_err()
                    || conn.roundtrip().is_err()
                {
                    disconnected = true;
                    break;
                }
            }
        }
    }

    if !disconnected {
        for &ctrl_id in controls.keys() {
            let _ = conn.send(ctrl_id, ZWLR_GAMMA_CTRL_DESTROY, WlWriter::new());
        }
        let _ = conn.send(gamma_mgr, ZWLR_GAMMA_MGR_DESTROY, WlWriter::new());
        let _ = conn.roundtrip();
    }
    Ok(0)
}

#[cfg(test)]
mod tests {
    use super::{build_gamma_ramp, kelvin_to_rgb_multipliers};

    #[test]
    fn kelvin_6500_is_near_neutral_and_warm_reduces_blue() {
        let (r65, g65, b65) = kelvin_to_rgb_multipliers(6500);
        assert!(r65 > 0.99 && g65 > 0.95 && b65 > 0.95);
        let (r35, g35, b35) = kelvin_to_rgb_multipliers(3500);
        assert!(r35 > 0.99);
        assert!(b35 < g35 && g35 < r35);
    }

    #[test]
    fn gamma_ramp_has_exact_expected_byte_layout() {
        let ramp = build_gamma_ramp(256, 4500, 1.0);
        assert_eq!(ramp.len(), 256 * 3 * 2);
        assert_eq!(u16::from_ne_bytes([ramp[0], ramp[1]]), 0);
        assert_eq!(u16::from_ne_bytes([ramp[510], ramp[511]]), 65535);
    }
}
