use std::collections::HashMap;
use std::fs;
use std::io::{self, Cursor, Write};
use std::path::Path;

use alis_wayland::{
    ShmBuffer, WL_BUFFER_DESTROY, WL_SHM_CREATE_POOL, WL_SHM_FORMAT_ABGR8888,
    WL_SHM_FORMAT_ABGR2101010, WL_SHM_FORMAT_ARGB8888, WL_SHM_FORMAT_ARGB2101010,
    WL_SHM_FORMAT_BGR888, WL_SHM_FORMAT_RGB888, WL_SHM_FORMAT_XBGR8888, WL_SHM_FORMAT_XBGR2101010,
    WL_SHM_FORMAT_XRGB8888, WL_SHM_FORMAT_XRGB2101010, WL_SHM_POOL_CREATE_BUFFER,
    WL_SHM_POOL_DESTROY, WlConnection, WlReader, WlWriter,
};
use anyhow::{Context, Result, anyhow, bail};
use clap::Args;
use image::imageops::FilterType;
use image::{DynamicImage, ImageFormat, Rgba, RgbaImage};

// zwlr_screencopy_manager_v1
const WLR_SC_CAPTURE_OUTPUT: u16 = 0;
const WLR_SC_CAPTURE_REGION: u16 = 1;
const WLR_SC_FRAME_COPY: u16 = 0;
const WLR_SC_FRAME_DESTROY: u16 = 1;
const WLR_SC_EV_BUFFER: u16 = 0;
const WLR_SC_EV_FLAGS: u16 = 1;
const WLR_SC_EV_READY: u16 = 2;
const WLR_SC_EV_FAILED: u16 = 3;
const WLR_SC_EV_BUFFER_DONE: u16 = 6;

// ext_image_copy_capture_v1 + ext_output_image_capture_source_manager_v1
const EXT_SRC_CREATE_SOURCE: u16 = 0;
const EXT_CAP_CREATE_SESSION: u16 = 0;
const EXT_SESS_CREATE_FRAME: u16 = 0;
const EXT_SESS_DESTROY: u16 = 1;
const EXT_SESS_EV_BUFFER_SIZE: u16 = 0;
const EXT_SESS_EV_SHM_FORMAT: u16 = 1;
const EXT_SESS_EV_DONE: u16 = 4;
const EXT_FRAME_DESTROY: u16 = 0;
const EXT_FRAME_ATTACH_BUFFER: u16 = 1;
const EXT_FRAME_DAMAGE_BUFFER: u16 = 2;
const EXT_FRAME_CAPTURE: u16 = 3;
const EXT_FRAME_EV_TRANSFORM: u16 = 0;
const EXT_FRAME_EV_READY: u16 = 3;
const EXT_FRAME_EV_FAILED: u16 = 4;

// zxdg_output_manager_v1 / zxdg_output_v1
const ZXDG_OUT_MGR_GET_OUTPUT: u16 = 1;
const ZXDG_OUT_EV_LOGICAL_POS: u16 = 0;
const ZXDG_OUT_EV_LOGICAL_SIZE: u16 = 1;
const ZXDG_OUT_EV_NAME: u16 = 3;

// wl_output events
const WL_OUTPUT_EV_GEOMETRY: u16 = 0;
const WL_OUTPUT_EV_MODE: u16 = 1;
const WL_OUTPUT_EV_SCALE: u16 = 3;
const WL_OUTPUT_EV_NAME: u16 = 4;

#[derive(Debug, Args)]
pub struct ScreencopyArgs {
    /// Capture specific output name (like grim -o).
    #[arg(short = 'o', long = "output")]
    pub output_name: Option<String>,

    /// Capture geometry "X,Y WxH" (like grim -g).
    #[arg(short = 'g', long = "geometry")]
    pub geometry: Option<String>,

    /// Scale factor (like grim -s, e.g. 0.1).
    #[arg(short = 's', long = "scale")]
    pub scale: Option<f64>,

    /// Output format: png, jpeg, ppm.
    #[arg(short = 't', long = "type", default_value = "png")]
    pub format: String,

    /// Compute and print mean grayscale lightness (0..100) directly without encoding an image.
    #[arg(long = "luma")]
    pub luma: bool,

    /// Output path ("-" for stdout). Optional when --luma is passed.
    pub destination: Option<String>,
}

#[derive(Debug, Default, Clone)]
struct OutputInfo {
    id: u32,
    name: String,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    logical_width: i32,
    logical_height: i32,
    scale: i32,
}

impl OutputInfo {
    fn eff_logical_width(&self) -> i32 {
        if self.logical_width > 0 {
            self.logical_width
        } else {
            (self.width / self.scale.max(1)).max(1)
        }
    }

    fn eff_logical_height(&self) -> i32 {
        if self.logical_height > 0 {
            self.logical_height
        } else {
            (self.height / self.scale.max(1)).max(1)
        }
    }
}

fn apply_wl_transform(img: RgbaImage, transform: u32) -> RgbaImage {
    let dyn_img = DynamicImage::ImageRgba8(img);
    let out = match transform {
        1 => dyn_img.rotate270(),
        2 => dyn_img.rotate180(),
        3 => dyn_img.rotate90(),
        4 => dyn_img.fliph(),
        5 => dyn_img.fliph().rotate270(),
        6 => dyn_img.fliph().rotate180(),
        7 => dyn_img.fliph().rotate90(),
        _ => dyn_img,
    };
    out.to_rgba8()
}

fn is_supported_shm_format(fmt: u32) -> bool {
    matches!(
        fmt,
        WL_SHM_FORMAT_ARGB8888
            | WL_SHM_FORMAT_XRGB8888
            | WL_SHM_FORMAT_ABGR8888
            | WL_SHM_FORMAT_XBGR8888
            | WL_SHM_FORMAT_XRGB2101010
            | WL_SHM_FORMAT_ARGB2101010
            | WL_SHM_FORMAT_XBGR2101010
            | WL_SHM_FORMAT_ABGR2101010
            | WL_SHM_FORMAT_RGB888
            | WL_SHM_FORMAT_BGR888
    )
}

fn bytes_per_pixel(fmt: u32) -> u32 {
    match fmt {
        WL_SHM_FORMAT_RGB888 | WL_SHM_FORMAT_BGR888 => 3,
        _ => 4,
    }
}

fn select_output_for_region(outputs: &[OutputInfo], region: Option<(i32, i32, i32, i32)>) -> Option<OutputInfo> {
    if let Some((gx, gy, gw, gh)) = region {
        let mut best: Option<(i64, &OutputInfo)> = None;
        for out in outputs {
            let ox1 = out.x;
            let oy1 = out.y;
            let ox2 = out.x + out.eff_logical_width();
            let oy2 = out.y + out.eff_logical_height();
            let ix = (gx + gw).min(ox2) - gx.max(ox1);
            let iy = (gy + gh).min(oy2) - gy.max(oy1);
            let area = if ix > 0 && iy > 0 { (ix as i64) * (iy as i64) } else { 0 };
            if best.is_none_or(|(b_area, _)| area > b_area) {
                best = Some((area, out));
            }
        }
        if let Some((_, out)) = best {
            return Some(out.clone());
        }
    }
    outputs.first().cloned()
}

fn parse_slurp_geometry(raw: &str) -> Result<(i32, i32, i32, i32)> {
    let (xy, wh) = raw
        .trim()
        .split_once(' ')
        .ok_or_else(|| anyhow!("invalid geometry (expected 'X,Y WxH'): {raw}"))?;
    let (xs, ys) = xy
        .split_once(',')
        .ok_or_else(|| anyhow!("invalid X,Y in geometry: {raw}"))?;
    let (ws, hs) = wh
        .split_once('x')
        .or_else(|| wh.split_once('X'))
        .ok_or_else(|| anyhow!("invalid WxH in geometry: {raw}"))?;
    Ok((xs.parse()?, ys.parse()?, ws.parse()?, hs.parse()?))
}

fn decode_shm_to_rgba(
    data: &[u8],
    width: u32,
    height: u32,
    stride: u32,
    format: u32,
    y_invert: bool,
) -> Result<RgbaImage> {
    let mut img = RgbaImage::new(width, height);
    for y in 0..height {
        let src_y = if y_invert { height - 1 - y } else { y };
        let row_start = (src_y as usize) * (stride as usize);
        for x in 0..width {
            let px = match format {
                WL_SHM_FORMAT_ARGB8888 | WL_SHM_FORMAT_XRGB8888 => {
                    let off = row_start + (x as usize) * 4;
                    if off + 4 > data.len() {
                        Rgba([0, 0, 0, 255])
                    } else {
                        let b = data[off];
                        let g = data[off + 1];
                        let r = data[off + 2];
                        let a = if format == WL_SHM_FORMAT_ARGB8888 {
                            data[off + 3]
                        } else {
                            255
                        };
                        Rgba([r, g, b, a])
                    }
                }
                WL_SHM_FORMAT_ABGR8888 | WL_SHM_FORMAT_XBGR8888 => {
                    let off = row_start + (x as usize) * 4;
                    if off + 4 > data.len() {
                        Rgba([0, 0, 0, 255])
                    } else {
                        let r = data[off];
                        let g = data[off + 1];
                        let b = data[off + 2];
                        let a = if format == WL_SHM_FORMAT_ABGR8888 {
                            data[off + 3]
                        } else {
                            255
                        };
                        Rgba([r, g, b, a])
                    }
                }
                WL_SHM_FORMAT_XRGB2101010 | WL_SHM_FORMAT_ARGB2101010 => {
                    let off = row_start + (x as usize) * 4;
                    if off + 4 > data.len() {
                        Rgba([0, 0, 0, 255])
                    } else {
                        let v = u32::from_le_bytes(data[off..off + 4].try_into().unwrap());
                        let b = ((v & 0x3ff) >> 2) as u8;
                        let g = (((v >> 10) & 0x3ff) >> 2) as u8;
                        let r = (((v >> 20) & 0x3ff) >> 2) as u8;
                        Rgba([r, g, b, 255])
                    }
                }
                WL_SHM_FORMAT_XBGR2101010 | WL_SHM_FORMAT_ABGR2101010 => {
                    let off = row_start + (x as usize) * 4;
                    if off + 4 > data.len() {
                        Rgba([0, 0, 0, 255])
                    } else {
                        let v = u32::from_le_bytes(data[off..off + 4].try_into().unwrap());
                        let r = ((v & 0x3ff) >> 2) as u8;
                        let g = (((v >> 10) & 0x3ff) >> 2) as u8;
                        let b = (((v >> 20) & 0x3ff) >> 2) as u8;
                        Rgba([r, g, b, 255])
                    }
                }
                WL_SHM_FORMAT_RGB888 => {
                    let off = row_start + (x as usize) * 3;
                    if off + 3 > data.len() {
                        Rgba([0, 0, 0, 255])
                    } else {
                        Rgba([data[off + 2], data[off + 1], data[off], 255])
                    }
                }
                WL_SHM_FORMAT_BGR888 => {
                    let off = row_start + (x as usize) * 3;
                    if off + 3 > data.len() {
                        Rgba([0, 0, 0, 255])
                    } else {
                        Rgba([data[off], data[off + 1], data[off + 2], 255])
                    }
                }
                other => bail!("unsupported Wayland SHM pixel format 0x{other:08x}"),
            };
            img.put_pixel(x, y, px);
        }
    }
    Ok(img)
}

fn capture_via_wlr(
    conn: &mut WlConnection,
    shm_id: u32,
    sc_mgr_id: u32,
    sc_mgr_ver: u32,
    output_id: u32,
    region: Option<(i32, i32, i32, i32)>,
) -> Result<RgbaImage> {
    let frame_id = conn.next_id();
    let mut w = WlWriter::new();
    if let Some((x, y, rw, rh)) = region {
        w.u32(frame_id)
            .i32(0)
            .u32(output_id)
            .i32(x)
            .i32(y)
            .i32(rw)
            .i32(rh);
        conn.send(sc_mgr_id, WLR_SC_CAPTURE_REGION, w)?;
    } else {
        w.u32(frame_id).i32(0).u32(output_id);
        conn.send(sc_mgr_id, WLR_SC_CAPTURE_OUTPUT, w)?;
    }

    let mut fmt = 0u32;
    let mut width = 0u32;
    let mut height = 0u32;
    let mut stride = 0u32;
    let mut got_buf = false;
    let wait_buffer_done = sc_mgr_ver >= 3;

    for _ in 0..256 {
        let ev = conn.recv_message()?;
        WlConnection::check_display_error(&ev)?;
        if ev.object_id == frame_id {
            match ev.opcode {
                WLR_SC_EV_BUFFER => {
                    let mut r = WlReader::new(&ev.payload);
                    let cand_fmt = r.u32()?;
                    let cand_w = r.u32()?;
                    let cand_h = r.u32()?;
                    let cand_s = r.u32()?;
                    if !got_buf || (!is_supported_shm_format(fmt) && is_supported_shm_format(cand_fmt)) {
                        fmt = cand_fmt;
                        width = cand_w;
                        height = cand_h;
                        stride = cand_s;
                        got_buf = true;
                    }
                    if !wait_buffer_done {
                        break;
                    }
                }
                WLR_SC_EV_BUFFER_DONE if wait_buffer_done => break,
                WLR_SC_EV_FAILED => bail!("zwlr_screencopy frame failed before buffer"),
                _ => {}
            }
        }
    }
    if !got_buf || width == 0 || height == 0 {
        bail!("zwlr_screencopy did not receive buffer metadata");
    }

    let size = (stride as usize) * (height as usize);
    let shm = ShmBuffer::new("alis-screencopy", size)?;
    let pool_id = conn.next_id();
    let mut pw = WlWriter::new();
    pw.u32(pool_id).fd(shm.raw_fd()).i32(size as i32);
    conn.send(shm_id, WL_SHM_CREATE_POOL, pw)?;

    let buf_id = conn.next_id();
    let mut bw = WlWriter::new();
    bw.u32(buf_id)
        .i32(0)
        .i32(width as i32)
        .i32(height as i32)
        .i32(stride as i32)
        .u32(fmt);
    conn.send(pool_id, WL_SHM_POOL_CREATE_BUFFER, bw)?;

    let mut cw = WlWriter::new();
    cw.u32(buf_id);
    conn.send(frame_id, WLR_SC_FRAME_COPY, cw)?;

    let mut flags = 0u32;
    loop {
        let ev = conn.recv_message()?;
        WlConnection::check_display_error(&ev)?;
        if ev.object_id == frame_id {
            match ev.opcode {
                WLR_SC_EV_FLAGS => {
                    let mut r = WlReader::new(&ev.payload);
                    flags = r.u32().unwrap_or(0);
                }
                WLR_SC_EV_READY => break,
                WLR_SC_EV_FAILED => bail!("zwlr_screencopy copy failed"),
                _ => {}
            }
        }
    }

    let img = decode_shm_to_rgba(shm.as_slice(), width, height, stride, fmt, (flags & 1) != 0)?;
    let _ = conn.send(frame_id, WLR_SC_FRAME_DESTROY, WlWriter::new());
    let _ = conn.send(buf_id, WL_BUFFER_DESTROY, WlWriter::new());
    let _ = conn.send(pool_id, WL_SHM_POOL_DESTROY, WlWriter::new());
    Ok(img)
}

fn capture_via_ext_copy(
    conn: &mut WlConnection,
    shm_id: u32,
    cap_mgr_id: u32,
    src_mgr_id: u32,
    output_id: u32,
) -> Result<RgbaImage> {
    let src_id = conn.next_id();
    let mut sw = WlWriter::new();
    sw.u32(src_id).u32(output_id);
    conn.send(src_mgr_id, EXT_SRC_CREATE_SOURCE, sw)?;

    let sess_id = conn.next_id();
    let mut sew = WlWriter::new();
    sew.u32(sess_id).u32(src_id).u32(0);
    conn.send(cap_mgr_id, EXT_CAP_CREATE_SESSION, sew)?;

    let mut width = 0u32;
    let mut height = 0u32;
    let mut formats = Vec::new();
    loop {
        let ev = conn.recv_message()?;
        WlConnection::check_display_error(&ev)?;
        if ev.object_id == sess_id {
            match ev.opcode {
                EXT_SESS_EV_BUFFER_SIZE => {
                    let mut r = WlReader::new(&ev.payload);
                    width = r.u32()?;
                    height = r.u32()?;
                }
                EXT_SESS_EV_SHM_FORMAT => {
                    let mut r = WlReader::new(&ev.payload);
                    formats.push(r.u32()?);
                }
                EXT_SESS_EV_DONE => break,
                _ => {}
            }
        }
    }

    let preferred = [
        WL_SHM_FORMAT_XRGB8888,
        WL_SHM_FORMAT_ARGB8888,
        WL_SHM_FORMAT_XBGR8888,
        WL_SHM_FORMAT_ABGR8888,
        WL_SHM_FORMAT_XRGB2101010,
        WL_SHM_FORMAT_ARGB2101010,
        WL_SHM_FORMAT_XBGR2101010,
        WL_SHM_FORMAT_ABGR2101010,
        WL_SHM_FORMAT_RGB888,
        WL_SHM_FORMAT_BGR888,
    ];
    let fmt = preferred
        .iter()
        .copied()
        .find(|f| formats.contains(f))
        .or_else(|| formats.first().copied())
        .ok_or_else(|| anyhow!("ext_image_copy_capture offered no supported SHM format"))?;
    let stride = width * bytes_per_pixel(fmt);
    let size = (stride as usize) * (height as usize);
    let shm = ShmBuffer::new("alis-ext-capture", size)?;

    let pool_id = conn.next_id();
    let mut pw = WlWriter::new();
    pw.u32(pool_id).fd(shm.raw_fd()).i32(size as i32);
    conn.send(shm_id, WL_SHM_CREATE_POOL, pw)?;

    let buf_id = conn.next_id();
    let mut bw = WlWriter::new();
    bw.u32(buf_id)
        .i32(0)
        .i32(width as i32)
        .i32(height as i32)
        .i32(stride as i32)
        .u32(fmt);
    conn.send(pool_id, WL_SHM_POOL_CREATE_BUFFER, bw)?;

    let frame_id = conn.next_id();
    let mut fw = WlWriter::new();
    fw.u32(frame_id);
    conn.send(sess_id, EXT_SESS_CREATE_FRAME, fw)?;

    let mut aw = WlWriter::new();
    aw.u32(buf_id);
    conn.send(frame_id, EXT_FRAME_ATTACH_BUFFER, aw)?;

    let mut dw = WlWriter::new();
    dw.i32(0).i32(0).i32(width as i32).i32(height as i32);
    conn.send(frame_id, EXT_FRAME_DAMAGE_BUFFER, dw)?;

    conn.send(frame_id, EXT_FRAME_CAPTURE, WlWriter::new())?;

    let mut transform = 0u32;
    loop {
        let ev = conn.recv_message()?;
        WlConnection::check_display_error(&ev)?;
        if ev.object_id == frame_id {
            match ev.opcode {
                EXT_FRAME_EV_TRANSFORM => {
                    let mut r = WlReader::new(&ev.payload);
                    transform = r.u32().unwrap_or(0);
                }
                EXT_FRAME_EV_READY => break,
                EXT_FRAME_EV_FAILED => bail!("ext_image_copy_capture frame failed"),
                _ => {}
            }
        }
    }

    let raw_img = decode_shm_to_rgba(shm.as_slice(), width, height, stride, fmt, false)?;
    let img = apply_wl_transform(raw_img, transform);
    let _ = conn.send(frame_id, EXT_FRAME_DESTROY, WlWriter::new());
    let _ = conn.send(sess_id, EXT_SESS_DESTROY, WlWriter::new());
    let _ = conn.send(buf_id, WL_BUFFER_DESTROY, WlWriter::new());
    let _ = conn.send(pool_id, WL_SHM_POOL_DESTROY, WlWriter::new());
    Ok(img)
}

pub fn run(args: ScreencopyArgs) -> Result<i32> {
    let mut conn = WlConnection::connect()?;
    let (registry, globals) = conn.get_globals()?;
    let shm_g = globals
        .iter()
        .find(|g| g.interface == "wl_shm")
        .ok_or_else(|| anyhow!("compositor missing wl_shm"))?
        .clone();
    let shm_id = conn.bind_global(registry, shm_g.name, "wl_shm", 1)?;

    let mut outputs: HashMap<u32, OutputInfo> = HashMap::new();
    let mut output_order: Vec<u32> = Vec::new();
    for g in globals.iter().filter(|g| g.interface == "wl_output") {
        let id = conn.bind_global(registry, g.name, "wl_output", g.version.min(4))?;
        outputs.insert(
            id,
            OutputInfo {
                id,
                scale: 1,
                ..Default::default()
            },
        );
        output_order.push(id);
    }

    let mut xdg_to_output: HashMap<u32, u32> = HashMap::new();
    if let Some(xdg_g) = globals
        .iter()
        .find(|g| g.interface == "zxdg_output_manager_v1")
        .cloned()
    {
        let xdg_mgr = conn.bind_global(
            registry,
            xdg_g.name,
            "zxdg_output_manager_v1",
            xdg_g.version.min(3),
        )?;
        for &out_id in &output_order {
            let xdg_out_id = conn.next_id();
            let mut xw = WlWriter::new();
            xw.u32(xdg_out_id).u32(out_id);
            conn.send(xdg_mgr, ZXDG_OUT_MGR_GET_OUTPUT, xw)?;
            xdg_to_output.insert(xdg_out_id, out_id);
        }
    }

    let evs = conn.roundtrip()?;
    for ev in evs {
        if let Some(info) = outputs.get_mut(&ev.object_id) {
            let mut r = WlReader::new(&ev.payload);
            match ev.opcode {
                WL_OUTPUT_EV_GEOMETRY => {
                    if let (Ok(x), Ok(y)) = (r.i32(), r.i32())
                        && info.x == 0
                        && info.y == 0
                    {
                        info.x = x;
                        info.y = y;
                    }
                }
                WL_OUTPUT_EV_MODE => {
                    if let (Ok(flags), Ok(w), Ok(h)) = (r.u32(), r.i32(), r.i32())
                        && (flags & 1) != 0
                    {
                        info.width = w;
                        info.height = h;
                    }
                }
                WL_OUTPUT_EV_SCALE => {
                    if let Ok(s) = r.i32() {
                        info.scale = s.max(1);
                    }
                }
                WL_OUTPUT_EV_NAME => {
                    if let Ok(name) = r.string() {
                        info.name = name;
                    }
                }
                _ => {}
            }
        } else if let Some(&out_id) = xdg_to_output.get(&ev.object_id)
            && let Some(info) = outputs.get_mut(&out_id)
        {
            let mut r = WlReader::new(&ev.payload);
            match ev.opcode {
                ZXDG_OUT_EV_LOGICAL_POS => {
                    if let (Ok(x), Ok(y)) = (r.i32(), r.i32()) {
                        info.x = x;
                        info.y = y;
                    }
                }
                ZXDG_OUT_EV_LOGICAL_SIZE => {
                    if let (Ok(w), Ok(h)) = (r.i32(), r.i32()) {
                        info.logical_width = w;
                        info.logical_height = h;
                    }
                }
                ZXDG_OUT_EV_NAME => {
                    if info.name.is_empty()
                        && let Ok(name) = r.string()
                    {
                        info.name = name;
                    }
                }
                _ => {}
            }
        }
    }

    let region = args
        .geometry
        .as_deref()
        .map(parse_slurp_geometry)
        .transpose()?;

    let ordered_outputs: Vec<OutputInfo> = output_order
        .iter()
        .filter_map(|id| outputs.get(id).cloned())
        .collect();

    let selected = if let Some(ref want_name) = args.output_name {
        ordered_outputs
            .iter()
            .find(|o| o.name == *want_name)
            .cloned()
            .ok_or_else(|| anyhow!("Wayland output not found: {want_name}"))?
    } else {
        select_output_for_region(&ordered_outputs, region)
            .ok_or_else(|| anyhow!("no Wayland outputs available"))?
    };

    let local_region = region.map(|(gx, gy, gw, gh)| {
        let lx = (gx - selected.x).max(0);
        let ly = (gy - selected.y).max(0);
        let lw = gw.max(1).min((selected.eff_logical_width() - lx).max(1));
        let lh = gh.max(1).min((selected.eff_logical_height() - ly).max(1));
        (lx, ly, lw, lh)
    });

    let mut rgba = if let Some(wlr_g) = globals
        .iter()
        .find(|g| g.interface == "zwlr_screencopy_manager_v1")
        .cloned()
    {
        let bound_ver = wlr_g.version.min(3);
        let mgr_id = conn.bind_global(
            registry,
            wlr_g.name,
            "zwlr_screencopy_manager_v1",
            bound_ver,
        )?;
        capture_via_wlr(&mut conn, shm_id, mgr_id, bound_ver, selected.id, local_region)?
    } else if let (Some(cap_g), Some(src_g)) = (
        globals
            .iter()
            .find(|g| g.interface == "ext_image_copy_capture_manager_v1")
            .cloned(),
        globals
            .iter()
            .find(|g| g.interface == "ext_output_image_capture_source_manager_v1")
            .cloned(),
    ) {
        let cap_id = conn.bind_global(registry, cap_g.name, "ext_image_copy_capture_manager_v1", 1)?;
        let src_id = conn.bind_global(
            registry,
            src_g.name,
            "ext_output_image_capture_source_manager_v1",
            1,
        )?;
        let full = capture_via_ext_copy(&mut conn, shm_id, cap_id, src_id, selected.id)?;
        if let Some((lx, ly, lw, lh)) = local_region {
            let sx = full.width() as f64 / selected.eff_logical_width().max(1) as f64;
            let sy = full.height() as f64 / selected.eff_logical_height().max(1) as f64;
            let rx = ((lx as f64) * sx).round().clamp(0.0, full.width().saturating_sub(1) as f64) as u32;
            let ry = ((ly as f64) * sy).round().clamp(0.0, full.height().saturating_sub(1) as f64) as u32;
            let rw = ((lw as f64) * sx).round().max(1.0).min(full.width().saturating_sub(rx).max(1) as f64) as u32;
            let rh = ((lh as f64) * sy).round().max(1.0).min(full.height().saturating_sub(ry).max(1) as f64) as u32;
            DynamicImage::ImageRgba8(full).crop_imm(rx, ry, rw, rh).to_rgba8()
        } else {
            full
        }
    } else {
        bail!("compositor supports neither zwlr_screencopy_manager_v1 nor ext_image_copy_capture_manager_v1");
    };

    if let Some(scale) = args.scale
        && scale > 0.0
        && (scale - 1.0).abs() > 0.001
    {
        let nw = ((rgba.width() as f64) * scale).round().max(1.0) as u32;
        let nh = ((rgba.height() as f64) * scale).round().max(1.0) as u32;
        rgba = DynamicImage::ImageRgba8(rgba)
            .resize_exact(nw, nh, FilterType::Triangle)
            .to_rgba8();
    }

    if args.luma {
        let mut sum = 0.0_f64;
        let count = (rgba.width() as f64) * (rgba.height() as f64);
        for px in rgba.pixels() {
            sum += (0.2126 * px[0] as f64 + 0.7152 * px[1] as f64 + 0.0722 * px[2] as f64) / 255.0;
        }
        let pct = if count > 0.0 { (sum / count) * 100.0 } else { 0.0 };
        println!("{pct:.4}");
        return Ok(0);
    }

    let dest = args.destination.as_deref().unwrap_or("-");
    let dyn_img = DynamicImage::ImageRgba8(rgba);
    let fmt = match args.format.to_ascii_lowercase().as_str() {
        "jpg" | "jpeg" => ImageFormat::Jpeg,
        "ppm" | "pnm" => ImageFormat::Pnm,
        _ => ImageFormat::Png,
    };

    if dest == "-" {
        let mut out = Cursor::new(Vec::new());
        if fmt == ImageFormat::Jpeg {
            DynamicImage::ImageRgb8(dyn_img.to_rgb8()).write_to(&mut out, fmt)?;
        } else {
            dyn_img.write_to(&mut out, fmt)?;
        }
        io::stdout().write_all(&out.into_inner())?;
        return Ok(0);
    }

    let dest_path = Path::new(dest);
    if let Some(parent) = dest_path.parent()
        && !parent.as_os_str().is_empty()
    {
        fs::create_dir_all(parent)?;
    }
    let tmp = dest_path.with_extension(format!("alis-{}.tmp", std::process::id()));
    if fmt == ImageFormat::Jpeg {
        dyn_img
            .to_rgb8()
            .save_with_format(&tmp, ImageFormat::Jpeg)
            .with_context(|| format!("write {}", dest_path.display()))?;
    } else {
        dyn_img
            .save_with_format(&tmp, fmt)
            .with_context(|| format!("write {}", dest_path.display()))?;
    }
    fs::rename(&tmp, dest_path)?;
    Ok(0)
}

#[cfg(test)]
mod tests {
    use super::{decode_shm_to_rgba, parse_slurp_geometry};
    use alis_wayland::WL_SHM_FORMAT_XRGB8888;

    #[test]
    fn parses_slurp_geometry_and_decodes_xrgb() {
        assert_eq!(parse_slurp_geometry("10,20 300x200").unwrap(), (10, 20, 300, 200));
        // XRGB8888 in little-endian memory: B, G, R, X
        let raw = vec![10, 20, 30, 0, 40, 50, 60, 0];
        let img = decode_shm_to_rgba(&raw, 2, 1, 8, WL_SHM_FORMAT_XRGB8888, false).unwrap();
        assert_eq!(img.get_pixel(0, 0).0, [30, 20, 10, 255]);
        assert_eq!(img.get_pixel(1, 0).0, [60, 50, 40, 255]);
    }
}
