use std::collections::{HashMap, HashSet};
use std::io::{self, BufRead};
use std::os::fd::AsRawFd;
use std::thread;
use std::time::{Duration, Instant};

use alis_wayland::{ShmBuffer, WlConnection, WlWriter};
use anyhow::{Result, anyhow, bail};

const ZWP_VK_MANAGER_CREATE: u16 = 0;
const ZWP_VK_KEYMAP: u16 = 0;
const ZWP_VK_KEY: u16 = 1;
const ZWP_VK_MODIFIERS: u16 = 2;
const ZWP_VK_DESTROY: u16 = 3;
const XKB_KEYMAP_FORMAT_TEXT_V1: u32 = 1;

const MOD_SHIFT: u32 = 1 << 0;
const MOD_CTRL: u32 = 1 << 2;
const MOD_ALT: u32 = 1 << 3;
const MOD_SUPER: u32 = 1 << 6;

fn build_unicode_keymap(chars: &[char]) -> (String, HashMap<char, u32>) {
    let mut map = HashMap::new();
    let mut keycodes = String::new();
    let mut symbols = String::new();
    let mut next_evdev: u32 = 1;

    for &ch in chars {
        if map.contains_key(&ch) {
            continue;
        }
        // Wayland keycodes sent to xkb are evdev + 8 in xkb_keycodes
        let evdev = next_evdev;
        next_evdev += 1;
        if evdev > 240 {
            break;
        }
        map.insert(ch, evdev);
        let xkb_code = evdev + 8;
        let sym = match ch {
            '\n' | '\r' => "Return".to_string(),
            '\t' => "Tab".to_string(),
            ' ' => "space".to_string(),
            c => format!("U{:04X}", c as u32),
        };
        keycodes.push_str(&format!("\t<K{evdev}> = {xkb_code};\n"));
        symbols.push_str(&format!("\tkey <K{evdev}> {{ [ {sym} ] }};\n"));
    }

    let keymap = format!(
        "xkb_keymap {{\n\
xkb_keycodes \"alis_unicode\" {{\n\
\tminimum = 8;\n\
\tmaximum = 255;\n\
{keycodes}}};\n\
xkb_types \"minimal\" {{\n\
\tvirtual_modifiers Alt,Meta,Super;\n\
\ttype \"ONE_LEVEL\" {{ modifiers = none; level_name[Level1] = \"Any\"; }};\n\
}};\n\
xkb_compatibility \"minimal\" {{\n\
\tinterpret Any+AnyOf(all) {{ action = SetMods(modifiers=modMapMods,clearLocks); }};\n\
}};\n\
xkb_symbols \"alis_unicode\" {{\n\
{symbols}}};\n\
}};\0"
    );
    (keymap, map)
}

fn build_standard_evdev_keymap() -> String {
    // Standard evdev keycodes (xkb = evdev + 8) for virtual keyboard injection & OSK.
    const PAIRS: &[(u32, &str, &str)] = &[
        (1, "Escape", "Escape"),
        (2, "1", "exclam"),
        (3, "2", "at"),
        (4, "3", "numbersign"),
        (5, "4", "dollar"),
        (6, "5", "percent"),
        (7, "6", "asciicircum"),
        (8, "7", "ampersand"),
        (9, "8", "asterisk"),
        (10, "9", "parenleft"),
        (11, "0", "parenright"),
        (12, "minus", "underscore"),
        (13, "equal", "plus"),
        (14, "BackSpace", "BackSpace"),
        (15, "Tab", "ISO_Left_Tab"),
        (16, "q", "Q"),
        (17, "w", "W"),
        (18, "e", "E"),
        (19, "r", "R"),
        (20, "t", "T"),
        (21, "y", "Y"),
        (22, "u", "U"),
        (23, "i", "I"),
        (24, "o", "O"),
        (25, "p", "P"),
        (26, "bracketleft", "braceleft"),
        (27, "bracketright", "braceright"),
        (28, "Return", "Return"),
        (29, "Control_L", "Control_L"),
        (30, "a", "A"),
        (31, "s", "S"),
        (32, "d", "D"),
        (33, "f", "F"),
        (34, "g", "G"),
        (35, "h", "H"),
        (36, "j", "J"),
        (37, "k", "K"),
        (38, "l", "L"),
        (39, "semicolon", "colon"),
        (40, "apostrophe", "quotedbl"),
        (41, "grave", "asciitilde"),
        (42, "Shift_L", "Shift_L"),
        (43, "backslash", "bar"),
        (44, "z", "Z"),
        (45, "x", "X"),
        (46, "c", "C"),
        (47, "v", "V"),
        (48, "b", "B"),
        (49, "n", "N"),
        (50, "m", "M"),
        (51, "comma", "less"),
        (52, "period", "greater"),
        (53, "slash", "question"),
        (54, "Shift_R", "Shift_R"),
        (56, "Alt_L", "Alt_L"),
        (57, "space", "space"),
        (58, "Caps_Lock", "Caps_Lock"),
        (59, "F1", "F1"),
        (60, "F2", "F2"),
        (61, "F3", "F3"),
        (62, "F4", "F4"),
        (63, "F5", "F5"),
        (64, "F6", "F6"),
        (65, "F7", "F7"),
        (66, "F8", "F8"),
        (67, "F9", "F9"),
        (68, "F10", "F10"),
        (87, "F11", "F11"),
        (88, "F12", "F12"),
        (97, "Control_R", "Control_R"),
        (100, "Alt_R", "Alt_R"),
        (102, "Home", "Home"),
        (103, "Up", "Up"),
        (104, "Prior", "Prior"),
        (105, "Left", "Left"),
        (106, "Right", "Right"),
        (107, "End", "End"),
        (108, "Down", "Down"),
        (109, "Next", "Next"),
        (110, "Insert", "Insert"),
        (111, "Delete", "Delete"),
        (125, "Super_L", "Super_L"),
        (126, "Super_R", "Super_R"),
    ];

    let mut keycodes = String::new();
    let mut symbols = String::new();
    for &(ev, lower, upper) in PAIRS {
        keycodes.push_str(&format!("\t<K{ev}> = {};\n", ev + 8));
        symbols.push_str(&format!("\tkey <K{ev}> {{ [ {lower}, {upper} ] }};\n"));
    }
    format!(
        "xkb_keymap {{\n\
xkb_keycodes \"alis_evdev\" {{\n\
\tminimum = 8;\n\
\tmaximum = 255;\n\
{keycodes}}};\n\
xkb_types \"complete\" {{\n\
\tvirtual_modifiers Alt,Meta,Super;\n\
\ttype \"TWO_LEVEL\" {{\n\
\t\tmodifiers = Shift;\n\
\t\tmap[Shift] = Level2;\n\
\t\tlevel_name[Level1] = \"Base\";\n\
\t\tlevel_name[Level2] = \"Shift\";\n\
\t}};\n\
}};\n\
xkb_compatibility \"minimal\" {{\n\
\tinterpret Any+AnyOf(all) {{ action = SetMods(modifiers=modMapMods,clearLocks); }};\n\
}};\n\
xkb_symbols \"alis_evdev\" {{\n\
{symbols}\
\tmodifier_map Shift {{ <K42>, <K54> }};\n\
\tmodifier_map Control {{ <K29>, <K97> }};\n\
\tmodifier_map Mod1 {{ <K56>, <K100> }};\n\
\tmodifier_map Mod4 {{ <K125>, <K126> }};\n\
}};\n\
}};\0"
    )
}

fn modifier_bit(evdev_code: u32) -> u32 {
    match evdev_code {
        42 | 54 => MOD_SHIFT,
        29 | 97 => MOD_CTRL,
        56 | 100 => MOD_ALT,
        125 | 126 => MOD_SUPER,
        _ => 0,
    }
}

pub fn named_key_to_evdev(name: &str) -> Option<u32> {
    let lower = name.trim().to_ascii_lowercase();
    if lower.len() == 1 {
        let ch = lower.as_bytes()[0];
        return match ch {
            b'a' => Some(30),
            b'b' => Some(48),
            b'c' => Some(46),
            b'd' => Some(32),
            b'e' => Some(18),
            b'f' => Some(33),
            b'g' => Some(34),
            b'h' => Some(35),
            b'i' => Some(23),
            b'j' => Some(36),
            b'k' => Some(37),
            b'l' => Some(38),
            b'm' => Some(50),
            b'n' => Some(49),
            b'o' => Some(24),
            b'p' => Some(25),
            b'q' => Some(16),
            b'r' => Some(19),
            b's' => Some(31),
            b't' => Some(20),
            b'u' => Some(22),
            b'v' => Some(47),
            b'w' => Some(17),
            b'x' => Some(45),
            b'y' => Some(21),
            b'z' => Some(44),
            b'1' => Some(2),
            b'2' => Some(3),
            b'3' => Some(4),
            b'4' => Some(5),
            b'5' => Some(6),
            b'6' => Some(7),
            b'7' => Some(8),
            b'8' => Some(9),
            b'9' => Some(10),
            b'0' => Some(11),
            _ => None,
        };
    }
    match lower.as_str() {
        "escape" | "esc" => Some(1),
        "backspace" => Some(14),
        "tab" => Some(15),
        "return" | "enter" => Some(28),
        "space" => Some(57),
        "left" => Some(105),
        "right" => Some(106),
        "up" => Some(103),
        "down" => Some(108),
        "home" => Some(102),
        "end" => Some(107),
        "pageup" | "prior" => Some(104),
        "pagedown" | "next" => Some(109),
        "insert" => Some(110),
        "delete" => Some(111),
        "minus" => Some(12),
        "equal" => Some(13),
        "bracketleft" => Some(26),
        "bracketright" => Some(27),
        "semicolon" => Some(39),
        "apostrophe" => Some(40),
        "grave" => Some(41),
        "backslash" => Some(43),
        "comma" => Some(51),
        "period" => Some(52),
        "slash" => Some(53),
        "caps_lock" | "capslock" => Some(58),
        "f1" => Some(59),
        "f2" => Some(60),
        "f3" => Some(61),
        "f4" => Some(62),
        "f5" => Some(63),
        "f6" => Some(64),
        "f7" => Some(65),
        "f8" => Some(66),
        "f9" => Some(67),
        "f10" => Some(68),
        "f11" => Some(87),
        "f12" => Some(88),
        _ => None,
    }
}

struct VirtualKeyboard {
    conn: WlConnection,
    vk_id: u32,
    started: Instant,
}

impl VirtualKeyboard {
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
            .find(|g| g.interface == "zwp_virtual_keyboard_manager_v1")
            .ok_or_else(|| anyhow!("compositor does not advertise zwp_virtual_keyboard_manager_v1"))?
            .clone();

        let seat_id = conn.bind_global(registry, seat_g.name, "wl_seat", seat_g.version.min(5))?;
        let mgr_id = conn.bind_global(
            registry,
            mgr_g.name,
            "zwp_virtual_keyboard_manager_v1",
            1,
        )?;
        let vk_id = conn.next_id();
        // create_virtual_keyboard(seat: object, id: new_id)
        let mut w = WlWriter::new();
        w.u32(seat_id).u32(vk_id);
        conn.send(mgr_id, ZWP_VK_MANAGER_CREATE, w)?;
        let _ = conn.roundtrip()?;
        Ok(Self {
            conn,
            vk_id,
            started: Instant::now(),
        })
    }

    fn upload_keymap(&mut self, keymap: &str) -> Result<()> {
        let bytes = keymap.as_bytes();
        let mut shm = ShmBuffer::new("alis-vk-keymap", bytes.len())?;
        shm.as_mut_slice()[..bytes.len()].copy_from_slice(bytes);
        let mut w = WlWriter::new();
        w.u32(XKB_KEYMAP_FORMAT_TEXT_V1)
            .fd(shm.fd.as_raw_fd())
            .u32(bytes.len() as u32);
        self.conn.send(self.vk_id, ZWP_VK_KEYMAP, w)?;
        let _ = self.conn.roundtrip()?;
        Ok(())
    }

    fn send_key(&self, evdev_code: u32, pressed: bool) -> Result<()> {
        let ts = self.started.elapsed().as_millis() as u32;
        let mut w = WlWriter::new();
        w.u32(ts)
            .u32(evdev_code)
            .u32(if pressed { 1 } else { 0 });
        self.conn.send(self.vk_id, ZWP_VK_KEY, w)
    }

    fn send_modifiers(&self, depressed: u32) -> Result<()> {
        let mut w = WlWriter::new();
        w.u32(depressed).u32(0).u32(0).u32(0);
        self.conn.send(self.vk_id, ZWP_VK_MODIFIERS, w)
    }

    fn sync(&mut self) -> Result<()> {
        let _ = self.conn.roundtrip()?;
        Ok(())
    }
}

impl Drop for VirtualKeyboard {
    fn drop(&mut self) {
        let _ = self.conn.send(self.vk_id, ZWP_VK_DESTROY, WlWriter::new());
    }
}

pub fn type_text(text: &str, delay_ms: u64) -> Result<()> {
    if text.is_empty() {
        return Ok(());
    }
    let chars: Vec<char> = text.chars().collect();
    let mut vk = VirtualKeyboard::connect()?;
    // Process in chunks of <= 200 distinct characters so keymap stays under 240 keys
    let mut idx = 0;
    while idx < chars.len() {
        let end = (idx + 200).min(chars.len());
        let chunk = &chars[idx..end];
        let (keymap, table) = build_unicode_keymap(chunk);
        vk.upload_keymap(&keymap)?;
        for &ch in chunk {
            if let Some(&code) = table.get(&ch) {
                vk.send_key(code, true)?;
                vk.send_key(code, false)?;
                vk.sync()?;
                if delay_ms > 0 {
                    thread::sleep(Duration::from_millis(delay_ms));
                }
            }
        }
        idx = end;
    }
    Ok(())
}

pub fn send_key_sequence(tokens: &[String], delay_ms: u64) -> Result<()> {
    let mut events: Vec<(u32, bool)> = Vec::new();
    let mut mods_to_hold: Vec<u32> = Vec::new();
    let mut i = 0;
    while i < tokens.len() {
        let tok = tokens[i].as_str();
        if tok == "-M" || tok == "--mod" {
            i += 1;
            let m = tokens.get(i).ok_or_else(|| anyhow!("missing modifier after -M"))?;
            let code = match m.to_ascii_lowercase().as_str() {
                "shift" => 42,
                "ctrl" | "control" => 29,
                "alt" => 56,
                "logo" | "win" | "super" => 125,
                other => bail!("unknown modifier: {other}"),
            };
            mods_to_hold.push(code);
        } else if tok == "-k" || tok == "--named" {
            i += 1;
            let k = tokens.get(i).ok_or_else(|| anyhow!("missing key after -k"))?;
            let code = named_key_to_evdev(k).ok_or_else(|| anyhow!("unknown key name: {k}"))?;
            for &mc in &mods_to_hold {
                events.push((mc, true));
            }
            events.push((code, true));
            events.push((code, false));
            for &mc in mods_to_hold.iter().rev() {
                events.push((mc, false));
            }
            mods_to_hold.clear();
        } else if let Some((code_s, state_s)) = tok.split_once(':') {
            let code: u32 = code_s.parse()?;
            let pressed = state_s != "0";
            events.push((code, pressed));
        } else if let Ok(code) = tok.parse::<u32>() {
            events.push((code, true));
            events.push((code, false));
        }
        i += 1;
    }

    if events.is_empty() {
        return Ok(());
    }

    let mut vk = VirtualKeyboard::connect()?;
    let keymap = build_standard_evdev_keymap();
    vk.upload_keymap(&keymap)?;

    let mut depressed_mods: u32 = 0;
    for (code, pressed) in events {
        let bit = modifier_bit(code);
        if bit != 0 {
            if pressed {
                depressed_mods |= bit;
            } else {
                depressed_mods &= !bit;
            }
            vk.send_key(code, pressed)?;
            vk.send_modifiers(depressed_mods)?;
        } else {
            vk.send_key(code, pressed)?;
        }
        vk.sync()?;
        if delay_ms > 0 {
            thread::sleep(Duration::from_millis(delay_ms));
        }
    }
    Ok(())
}

/// Persistent stdin-driven virtual keyboard session for On-Screen Keyboard (OSK)
/// so held modifiers (Shift, Caps, Ctrl, Alt, Super) survive across separate key taps.
/// Protocol (one command per line on stdin):
///   press <evdev>
///   release <evdev>
///   release_all
pub fn run_session() -> Result<()> {
    let mut vk = VirtualKeyboard::connect()?;
    let keymap = build_standard_evdev_keymap();
    vk.upload_keymap(&keymap)?;

    let mut held: HashSet<u32> = HashSet::new();
    let compute_mods = |set: &HashSet<u32>| -> u32 {
        set.iter().fold(0u32, |acc, &code| acc | modifier_bit(code))
    };

    let stdin = io::stdin();
    for line in stdin.lock().lines() {
        let Ok(raw) = line else { break };
        let trimmed = raw.trim();
        if trimmed.is_empty() {
            continue;
        }
        let mut parts = trimmed.split_whitespace();
        match parts.next() {
            Some("press") => {
                if let Some(code) = parts.next().and_then(|s| s.parse::<u32>().ok()) {
                    let was_mod = modifier_bit(code) != 0;
                    held.insert(code);
                    let _ = vk.send_key(code, true);
                    if was_mod {
                        let _ = vk.send_modifiers(compute_mods(&held));
                    }
                    let _ = vk.sync();
                }
            }
            Some("release") => {
                if let Some(code) = parts.next().and_then(|s| s.parse::<u32>().ok()) {
                    let was_mod = modifier_bit(code) != 0;
                    held.remove(&code);
                    let _ = vk.send_key(code, false);
                    if was_mod {
                        let _ = vk.send_modifiers(compute_mods(&held));
                    }
                    let _ = vk.sync();
                }
            }
            Some("release_all") => {
                let codes: Vec<u32> = held.drain().collect();
                for code in codes {
                    let _ = vk.send_key(code, false);
                }
                let _ = vk.send_modifiers(0);
                let _ = vk.sync();
            }
            Some("quit") => break,
            _ => {}
        }
    }

    let remaining: Vec<u32> = held.drain().collect();
    for code in remaining {
        let _ = vk.send_key(code, false);
    }
    let _ = vk.send_modifiers(0);
    let _ = vk.sync();
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{build_standard_evdev_keymap, build_unicode_keymap, named_key_to_evdev};

    #[test]
    fn unicode_keymap_maps_emoji_and_ascii() {
        let (km, map) = build_unicode_keymap(&['A', '😀', '\n']);
        assert!(km.contains("U0041"));
        assert!(km.contains("U1F600"));
        assert!(km.contains("Return"));
        assert_eq!(map.len(), 3);
    }

    #[test]
    fn standard_keymap_and_named_keys_cover_paste_and_media() {
        let km = build_standard_evdev_keymap();
        assert!(km.contains("Control_L"));
        assert!(km.contains("Shift_L"));
        assert_eq!(named_key_to_evdev("n"), Some(49));
        assert_eq!(named_key_to_evdev("p"), Some(25));
        assert_eq!(named_key_to_evdev("v"), Some(47));
    }
}
