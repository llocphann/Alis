use std::thread;
use std::time::{Duration, Instant};

use alis_wayland::{WlConnection, WlWriter};
use anyhow::{Result, anyhow, bail};

const ZWLR_VPM_CREATE_VIRTUAL_POINTER: u16 = 0;
const ZWLR_VPM_DESTROY: u16 = 1;

const ZWLR_VP_MOTION: u16 = 0;
const ZWLR_VP_MOTION_ABSOLUTE: u16 = 1;
const ZWLR_VP_BUTTON: u16 = 2;
const ZWLR_VP_FRAME: u16 = 4;
const ZWLR_VP_AXIS_SOURCE: u16 = 5;
const ZWLR_VP_AXIS_STOP: u16 = 6;
const ZWLR_VP_AXIS_DISCRETE: u16 = 7;
const ZWLR_VP_DESTROY: u16 = 8;

const BTN_LEFT: u32 = 0x110;
const BTN_RIGHT: u32 = 0x111;
const BTN_MIDDLE: u32 = 0x112;

const BUTTON_RELEASED: u32 = 0;
const BUTTON_PRESSED: u32 = 1;

const AXIS_VERTICAL: u32 = 0;
const AXIS_HORIZONTAL: u32 = 1;
const AXIS_SOURCE_WHEEL: u32 = 0;

#[derive(Debug, Clone, PartialEq)]
pub enum PointerCommand {
    Help,
    Probe,
    MoveAbs {
        x: u32,
        y: u32,
        width: u32,
        height: u32,
    },
    MoveRel {
        dx: f64,
        dy: f64,
    },
    Click {
        button_code: u32,
        double: bool,
        pos: Option<(u32, u32, u32, u32)>,
    },
    Scroll {
        delta: i32,
        axis: u32,
        pos: Option<(u32, u32, u32, u32)>,
    },
    Drag {
        x1: u32,
        y1: u32,
        x2: u32,
        y2: u32,
        width: u32,
        height: u32,
        button_code: u32,
        steps: usize,
    },
}

pub fn map_button_name(name: &str) -> Result<u32> {
    match name.trim().to_ascii_lowercase().as_str() {
        "" | "left" | "primary" => Ok(BTN_LEFT),
        "right" | "secondary" => Ok(BTN_RIGHT),
        "middle" | "aux" => Ok(BTN_MIDDLE),
        other => bail!("unknown pointer button: {other}"),
    }
}

pub fn interpolate_drag_points(
    x1: u32,
    y1: u32,
    x2: u32,
    y2: u32,
    steps: usize,
) -> Vec<(u32, u32)> {
    let clamped_steps = steps.clamp(2, 24);
    let mut pts = Vec::with_capacity(clamped_steps);
    for i in 1..=clamped_steps {
        let t = (i as f64) / (clamped_steps as f64);
        let px = ((x1 as f64) + ((x2 as f64) - (x1 as f64)) * t).round().max(0.0) as u32;
        let py = ((y1 as f64) + ((y2 as f64) - (y1 as f64)) * t).round().max(0.0) as u32;
        pts.push((px, py));
    }
    pts
}

fn validate_extent(width: Option<u32>, height: Option<u32>) -> Result<(u32, u32)> {
    let w = width.ok_or_else(|| anyhow!("--width is required for absolute coordinates"))?;
    let h = height.ok_or_else(|| anyhow!("--height is required for absolute coordinates"))?;
    if w == 0 || h == 0 {
        bail!("--width and --height must be >= 1");
    }
    Ok((w, h))
}

fn next_flag_value<'a>(args: &'a [String], i: &mut usize, flag: &str) -> Result<&'a str> {
    *i += 1;
    args.get(*i)
        .map(String::as_str)
        .ok_or_else(|| anyhow!("missing value for {flag}"))
}

pub fn parse_pointer_args(args: &[String]) -> Result<PointerCommand> {
    let Some(sub) = args.first().map(String::as_str) else {
        return Ok(PointerCommand::Help);
    };
    if matches!(sub, "--help" | "-h" | "help") {
        return Ok(PointerCommand::Help);
    }
    if sub == "probe" {
        return Ok(PointerCommand::Probe);
    }

    let mut x: Option<u32> = None;
    let mut y: Option<u32> = None;
    let mut dx: Option<f64> = None;
    let mut dy: Option<f64> = None;
    let mut x1: Option<u32> = None;
    let mut y1: Option<u32> = None;
    let mut x2: Option<u32> = None;
    let mut y2: Option<u32> = None;
    let mut width: Option<u32> = None;
    let mut height: Option<u32> = None;
    let mut button_str = "left".to_string();
    let mut double_click = false;
    let mut delta: Option<i32> = None;
    let mut axis = AXIS_VERTICAL;
    let mut steps: usize = 10;

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--x" => x = Some(next_flag_value(args, &mut i, "--x")?.parse()?),
            "--y" => y = Some(next_flag_value(args, &mut i, "--y")?.parse()?),
            "--dx" => dx = Some(next_flag_value(args, &mut i, "--dx")?.parse()?),
            "--dy" => dy = Some(next_flag_value(args, &mut i, "--dy")?.parse()?),
            "--x1" => x1 = Some(next_flag_value(args, &mut i, "--x1")?.parse()?),
            "--y1" => y1 = Some(next_flag_value(args, &mut i, "--y1")?.parse()?),
            "--x2" => x2 = Some(next_flag_value(args, &mut i, "--x2")?.parse()?),
            "--y2" => y2 = Some(next_flag_value(args, &mut i, "--y2")?.parse()?),
            "--width" => width = Some(next_flag_value(args, &mut i, "--width")?.parse()?),
            "--height" => height = Some(next_flag_value(args, &mut i, "--height")?.parse()?),
            "--button" => button_str = next_flag_value(args, &mut i, "--button")?.to_string(),
            "--double" => double_click = true,
            "--delta" => delta = Some(next_flag_value(args, &mut i, "--delta")?.parse()?),
            "--axis" => {
                let raw_axis = next_flag_value(args, &mut i, "--axis")?.trim().to_ascii_lowercase();
                axis = match raw_axis.as_str() {
                    "vertical" | "v" => AXIS_VERTICAL,
                    "horizontal" | "h" => AXIS_HORIZONTAL,
                    other => bail!("unknown axis: {other}"),
                };
            }
            "--steps" => steps = next_flag_value(args, &mut i, "--steps")?.parse()?,
            "--help" | "-h" => return Ok(PointerCommand::Help),
            other => bail!("unknown pointer argument: {other}"),
        }
        i += 1;
    }

    match sub {
        "move" => {
            if dx.is_some() || dy.is_some() {
                return Ok(PointerCommand::MoveRel {
                    dx: dx.unwrap_or(0.0),
                    dy: dy.unwrap_or(0.0),
                });
            }
            let px = x.ok_or_else(|| anyhow!("--x (or --dx) is required for move"))?;
            let py = y.ok_or_else(|| anyhow!("--y (or --dy) is required for move"))?;
            let (w, h) = validate_extent(width, height)?;
            Ok(PointerCommand::MoveAbs {
                x: px.min(w),
                y: py.min(h),
                width: w,
                height: h,
            })
        }
        "click" => {
            let button_code = map_button_name(&button_str)?;
            let pos = if let (Some(px), Some(py)) = (x, y) {
                let (w, h) = validate_extent(width, height)?;
                Some((px.min(w), py.min(h), w, h))
            } else {
                None
            };
            Ok(PointerCommand::Click {
                button_code,
                double: double_click,
                pos,
            })
        }
        "scroll" => {
            let d = delta.ok_or_else(|| anyhow!("--delta is required for scroll"))?;
            if d == 0 {
                bail!("--delta must be non-zero");
            }
            let pos = if let (Some(px), Some(py)) = (x, y) {
                let (w, h) = validate_extent(width, height)?;
                Some((px.min(w), py.min(h), w, h))
            } else {
                None
            };
            Ok(PointerCommand::Scroll {
                delta: d.clamp(-30, 30),
                axis,
                pos,
            })
        }
        "drag" => {
            let sx = x1.ok_or_else(|| anyhow!("--x1 is required for drag"))?;
            let sy = y1.ok_or_else(|| anyhow!("--y1 is required for drag"))?;
            let ex = x2.ok_or_else(|| anyhow!("--x2 is required for drag"))?;
            let ey = y2.ok_or_else(|| anyhow!("--y2 is required for drag"))?;
            let (w, h) = validate_extent(width, height)?;
            let button_code = map_button_name(&button_str)?;
            Ok(PointerCommand::Drag {
                x1: sx.min(w),
                y1: sy.min(h),
                x2: ex.min(w),
                y2: ey.min(h),
                width: w,
                height: h,
                button_code,
                steps: steps.clamp(2, 24),
            })
        }
        other => bail!("unknown pointer subcommand: {other}"),
    }
}

struct VirtualPointer {
    conn: WlConnection,
    mgr_id: u32,
    vp_id: u32,
    started: Instant,
}

impl VirtualPointer {
    fn connect() -> Result<Self> {
        let mut conn = WlConnection::connect()?;
        let (registry, globals) = conn.get_globals()?;
        let seat_g = globals
            .iter()
            .find(|g| g.interface == "wl_seat")
            .ok_or_else(|| anyhow!("compositor did not advertise wl_seat"))?
            .clone();
        let mgr_g = globals
            .iter()
            .find(|g| g.interface == "zwlr_virtual_pointer_manager_v1")
            .ok_or_else(|| anyhow!("compositor does not advertise zwlr_virtual_pointer_manager_v1"))?
            .clone();

        let seat_id = conn.bind_global(registry, seat_g.name, "wl_seat", seat_g.version.min(5))?;
        let mgr_id = conn.bind_global(
            registry,
            mgr_g.name,
            "zwlr_virtual_pointer_manager_v1",
            mgr_g.version.min(2),
        )?;
        let vp_id = conn.next_id();
        let mut w = WlWriter::new();
        w.u32(seat_id).u32(vp_id);
        conn.send(mgr_id, ZWLR_VPM_CREATE_VIRTUAL_POINTER, w)?;
        let _ = conn.roundtrip()?;
        Ok(Self {
            conn,
            mgr_id,
            vp_id,
            started: Instant::now(),
        })
    }

    fn ts_ms(&self) -> u32 {
        self.started.elapsed().as_millis() as u32
    }

    fn frame(&self) -> Result<()> {
        self.conn.send(self.vp_id, ZWLR_VP_FRAME, WlWriter::new())
    }

    fn motion_abs(&self, x: u32, y: u32, width: u32, height: u32) -> Result<()> {
        let mut w = WlWriter::new();
        w.u32(self.ts_ms())
            .u32(x.min(width))
            .u32(y.min(height))
            .u32(width)
            .u32(height);
        self.conn.send(self.vp_id, ZWLR_VP_MOTION_ABSOLUTE, w)?;
        self.frame()
    }

    fn motion_rel(&self, dx: f64, dy: f64) -> Result<()> {
        let mut w = WlWriter::new();
        w.u32(self.ts_ms()).fixed(dx).fixed(dy);
        self.conn.send(self.vp_id, ZWLR_VP_MOTION, w)?;
        self.frame()
    }

    fn button(&self, button_code: u32, pressed: bool) -> Result<()> {
        let mut w = WlWriter::new();
        w.u32(self.ts_ms())
            .u32(button_code)
            .u32(if pressed { BUTTON_PRESSED } else { BUTTON_RELEASED });
        self.conn.send(self.vp_id, ZWLR_VP_BUTTON, w)?;
        self.frame()
    }

    fn scroll(&self, axis: u32, discrete: i32) -> Result<()> {
        let mut w_src = WlWriter::new();
        w_src.u32(AXIS_SOURCE_WHEEL);
        self.conn.send(self.vp_id, ZWLR_VP_AXIS_SOURCE, w_src)?;

        let value = 15.0 * (discrete as f64);
        let mut w_disc = WlWriter::new();
        w_disc
            .u32(self.ts_ms())
            .u32(axis)
            .fixed(value)
            .i32(discrete);
        self.conn.send(self.vp_id, ZWLR_VP_AXIS_DISCRETE, w_disc)?;
        self.frame()?;

        let mut w_stop = WlWriter::new();
        w_stop.u32(self.ts_ms()).u32(axis);
        self.conn.send(self.vp_id, ZWLR_VP_AXIS_STOP, w_stop)?;
        self.frame()
    }

    fn sync(&mut self) -> Result<()> {
        let _ = self.conn.roundtrip()?;
        Ok(())
    }
}

impl Drop for VirtualPointer {
    fn drop(&mut self) {
        let _ = self.conn.send(self.vp_id, ZWLR_VP_DESTROY, WlWriter::new());
        let _ = self.conn.send(self.mgr_id, ZWLR_VPM_DESTROY, WlWriter::new());
    }
}

fn print_usage() {
    println!(
        "Usage: alis-inputd --pointer <probe|move|click|scroll|drag> [options]\n\
         Commands:\n\
         \tprobe\n\
         \tmove   (--x X --y Y --width W --height H | --dx DX --dy DY)\n\
         \tclick  [--button left|right|middle] [--double] [--x X --y Y --width W --height H]\n\
         \tscroll --delta N [--axis vertical|horizontal] [--x X --y Y --width W --height H]\n\
         \tdrag   --x1 X1 --y1 Y1 --x2 X2 --y2 Y2 --width W --height H [--button left|right|middle] [--steps N]"
    );
}

pub fn run_pointer_command(args: &[String]) -> Result<()> {
    let cmd = parse_pointer_args(args)?;
    match cmd {
        PointerCommand::Help => {
            print_usage();
            Ok(())
        }
        PointerCommand::Probe => {
            let mut conn = WlConnection::connect()?;
            let (_reg, globals) = conn.get_globals()?;
            let supported = globals
                .iter()
                .any(|g| g.interface == "zwlr_virtual_pointer_manager_v1");
            if !supported {
                bail!("compositor does not advertise zwlr_virtual_pointer_manager_v1");
            }
            println!("ok");
            Ok(())
        }
        PointerCommand::MoveAbs {
            x,
            y,
            width,
            height,
        } => {
            let mut vp = VirtualPointer::connect()?;
            vp.motion_abs(x, y, width, height)?;
            vp.sync()
        }
        PointerCommand::MoveRel { dx, dy } => {
            let mut vp = VirtualPointer::connect()?;
            vp.motion_rel(dx, dy)?;
            vp.sync()
        }
        PointerCommand::Click {
            button_code,
            double,
            pos,
        } => {
            let mut vp = VirtualPointer::connect()?;
            if let Some((x, y, w, h)) = pos {
                vp.motion_abs(x, y, w, h)?;
                vp.sync()?;
                thread::sleep(Duration::from_millis(6));
            }
            let clicks = if double { 2 } else { 1 };
            for idx in 0..clicks {
                vp.button(button_code, true)?;
                vp.sync()?;
                thread::sleep(Duration::from_millis(8));
                vp.button(button_code, false)?;
                vp.sync()?;
                if idx + 1 < clicks {
                    thread::sleep(Duration::from_millis(25));
                }
            }
            Ok(())
        }
        PointerCommand::Scroll { delta, axis, pos } => {
            let mut vp = VirtualPointer::connect()?;
            if let Some((x, y, w, h)) = pos {
                vp.motion_abs(x, y, w, h)?;
                vp.sync()?;
                thread::sleep(Duration::from_millis(6));
            }
            vp.scroll(axis, delta)?;
            vp.sync()
        }
        PointerCommand::Drag {
            x1,
            y1,
            x2,
            y2,
            width,
            height,
            button_code,
            steps,
        } => {
            let mut vp = VirtualPointer::connect()?;
            vp.motion_abs(x1, y1, width, height)?;
            vp.sync()?;
            thread::sleep(Duration::from_millis(8));
            vp.button(button_code, true)?;
            vp.sync()?;
            thread::sleep(Duration::from_millis(10));
            for (px, py) in interpolate_drag_points(x1, y1, x2, y2, steps) {
                vp.motion_abs(px, py, width, height)?;
                vp.sync()?;
                thread::sleep(Duration::from_millis(8));
            }
            vp.button(button_code, false)?;
            vp.sync()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{
        AXIS_HORIZONTAL, AXIS_VERTICAL, BTN_LEFT, BTN_MIDDLE, BTN_RIGHT, PointerCommand,
        interpolate_drag_points, map_button_name, parse_pointer_args,
    };

    fn s(items: &[&str]) -> Vec<String> {
        items.iter().map(|v| (*v).to_string()).collect()
    }

    #[test]
    fn button_mapping_accepts_standard_names() {
        assert_eq!(map_button_name("left").unwrap(), BTN_LEFT);
        assert_eq!(map_button_name("RIGHT").unwrap(), BTN_RIGHT);
        assert_eq!(map_button_name("middle").unwrap(), BTN_MIDDLE);
        assert!(map_button_name("invalid").is_err());
    }

    #[test]
    fn parse_pointer_subcommands_validates_extents_and_flags() {
        assert_eq!(
            parse_pointer_args(&s(&["probe"])).unwrap(),
            PointerCommand::Probe
        );
        assert_eq!(
            parse_pointer_args(&s(&[
                "click", "--button", "right", "--double", "--x", "120", "--y", "240", "--width",
                "1920", "--height", "1080"
            ]))
            .unwrap(),
            PointerCommand::Click {
                button_code: BTN_RIGHT,
                double: true,
                pos: Some((120, 240, 1920, 1080)),
            }
        );
        assert_eq!(
            parse_pointer_args(&s(&["scroll", "--delta", "-3", "--axis", "horizontal"])).unwrap(),
            PointerCommand::Scroll {
                delta: -3,
                axis: AXIS_HORIZONTAL,
                pos: None,
            }
        );
        assert_eq!(
            parse_pointer_args(&s(&["scroll", "--delta", "5"])).unwrap(),
            PointerCommand::Scroll {
                delta: 5,
                axis: AXIS_VERTICAL,
                pos: None,
            }
        );
        assert!(parse_pointer_args(&s(&["move", "--x", "10", "--y", "10"])).is_err());
        assert!(parse_pointer_args(&s(&[
            "move", "--x", "10", "--y", "10", "--width", "0", "--height", "1080"
        ]))
        .is_err());
    }

    #[test]
    fn drag_interpolation_reaches_target_with_clamped_steps() {
        let pts = interpolate_drag_points(0, 0, 100, 50, 1);
        assert_eq!(pts.len(), 2);
        assert_eq!(pts.last(), Some(&(100, 50)));

        let pts_hi = interpolate_drag_points(10, 20, 110, 120, 999);
        assert_eq!(pts_hi.len(), 24);
        assert_eq!(pts_hi.last(), Some(&(110, 120)));
    }
}
