use std::collections::{HashMap, HashSet};
use std::ffi::CString;
use std::fs;
use std::io::{self, Write};
use std::os::fd::RawFd;
use std::path::{Path, PathBuf};
use std::sync::mpsc::{self, Receiver, Sender};
use std::thread;

use anyhow::{Context, Result};
use clap::{Parser, ValueEnum};
use evdev::{Device, EventSummary, KeyCode, LedCode};
use alis_protocol::{Envelope, InputMessage};

const INPUT_DIR: &str = "/dev/input";
const IGNORED_NAME_PARTS: &[&str] = &["ydotool", "virtual"];

#[derive(Debug, Clone, Copy, ValueEnum)]
enum StreamMode {
    Locks,
    Keys,
    All,
}

impl StreamMode {
    fn wants_locks(self) -> bool {
        matches!(self, Self::Locks | Self::All)
    }

    fn wants_keys(self) -> bool {
        matches!(self, Self::Keys | Self::All)
    }
}

#[derive(Debug, Parser)]
#[command(about = "Dormant native keyboard input backend for Alis")]
struct Args {
    /// Match the current Python lock-state probe: print one snapshot and exit.
    #[arg(long)]
    once: bool,

    /// Select the streaming messages to emit.
    #[arg(long, value_enum, default_value_t = StreamMode::All)]
    mode: StreamMode,
}

#[derive(Debug)]
struct DeviceRuntime {
    token: u64,
    lock_candidate: bool,
    key_candidate: bool,
    caps: bool,
    num: bool,
    pressed: HashSet<u16>,
}

#[derive(Debug)]
enum InternalEvent {
    Hotplug,
    DeviceGone {
        path: PathBuf,
        token: u64,
    },
    LockSnapshot {
        path: PathBuf,
        token: u64,
        caps: bool,
        num: bool,
    },
    KeyChanged {
        path: PathBuf,
        token: u64,
        code: u16,
        pressed: bool,
    },
}

#[derive(Debug, Default)]
struct MonitorState {
    devices: HashMap<PathBuf, DeviceRuntime>,
    next_token: u64,
    last_lock: Option<(bool, bool)>,
    last_key_device_count: Option<usize>,
}

fn event_paths() -> Vec<PathBuf> {
    let mut paths = fs::read_dir(INPUT_DIR)
        .into_iter()
        .flatten()
        .flatten()
        .map(|entry| entry.path())
        .filter(|path| {
            path.file_name()
                .and_then(|name| name.to_str())
                .is_some_and(|name| name.starts_with("event"))
        })
        .collect::<Vec<_>>();
    paths.sort();
    paths
}

fn ignored_device(device: &Device) -> bool {
    let name = device.name().unwrap_or_default().to_ascii_lowercase();
    IGNORED_NAME_PARTS.iter().any(|part| name.contains(part))
}

fn is_lock_candidate(device: &Device) -> bool {
    if ignored_device(device) {
        return false;
    }

    let Some(keys) = device.supported_keys() else {
        return false;
    };
    let Some(leds) = device.supported_leds() else {
        return false;
    };

    let has_relevant_key =
        keys.contains(KeyCode::KEY_CAPSLOCK) || keys.contains(KeyCode::KEY_NUMLOCK);
    let has_relevant_led = leds.contains(LedCode::LED_CAPSL) || leds.contains(LedCode::LED_NUML);
    has_relevant_key && has_relevant_led
}

fn is_key_candidate(device: &Device) -> bool {
    if ignored_device(device) {
        return false;
    }

    let Some(keys) = device.supported_keys() else {
        return false;
    };

    [
        KeyCode::KEY_A,
        KeyCode::KEY_Z,
        KeyCode::KEY_ENTER,
        KeyCode::KEY_SPACE,
    ]
    .into_iter()
    .all(|key| keys.contains(key))
}

fn initial_lock_state(device: &Device) -> (bool, bool) {
    match device.get_led_state() {
        Ok(leds) => (
            leds.contains(LedCode::LED_CAPSL),
            leds.contains(LedCode::LED_NUML),
        ),
        Err(_) => (false, false),
    }
}

fn initial_pressed(device: &Device) -> HashSet<u16> {
    device
        .get_key_state()
        .map(|keys| keys.iter().map(|key| key.0).collect())
        .unwrap_or_default()
}

fn aggregate(values: impl Iterator<Item = bool>, previous: Option<bool>) -> Option<bool> {
    let mut true_count = 0usize;
    let mut false_count = 0usize;

    for value in values {
        if value {
            true_count += 1;
        } else {
            false_count += 1;
        }
    }

    if true_count == 0 && false_count == 0 {
        return None;
    }
    if true_count == false_count {
        return Some(previous.unwrap_or(false));
    }
    Some(true_count > false_count)
}

fn aggregate_lock(
    devices: &HashMap<PathBuf, DeviceRuntime>,
    previous: Option<(bool, bool)>,
) -> Option<(bool, bool, usize)> {
    let lock_devices = devices.values().filter(|device| device.lock_candidate);
    let count = lock_devices.clone().count();
    if count == 0 {
        return None;
    }

    let previous_caps = previous.map(|state| state.0);
    let previous_num = previous.map(|state| state.1);
    let caps = aggregate(
        lock_devices.clone().map(|device| device.caps),
        previous_caps,
    )?;
    let num = aggregate(lock_devices.map(|device| device.num), previous_num)?;
    Some((caps, num, count))
}

fn key_device_count(devices: &HashMap<PathBuf, DeviceRuntime>) -> usize {
    devices
        .values()
        .filter(|device| device.key_candidate)
        .count()
}

fn key_pressed(devices: &HashMap<PathBuf, DeviceRuntime>, code: u16) -> bool {
    devices
        .values()
        .filter(|device| device.key_candidate)
        .any(|device| device.pressed.contains(&code))
}

fn emit(message: InputMessage) -> bool {
    let stdout = io::stdout();
    let mut out = stdout.lock();
    if serde_json::to_writer(&mut out, &Envelope::new(message)).is_err() {
        return false;
    }
    out.write_all(b"\n").and_then(|_| out.flush()).is_ok()
}

fn emit_lock_if_changed(
    state: &mut MonitorState,
    force: bool,
    emit_message: &mut impl FnMut(InputMessage) -> bool,
) -> bool {
    let Some((caps, num, count)) = aggregate_lock(&state.devices, state.last_lock) else {
        return true;
    };

    let next = (caps, num);
    if (force || state.last_lock != Some(next))
        && !emit_message(InputMessage::State {
            caps,
            num,
            devices: count,
        })
    {
        return false;
    }
    state.last_lock = Some(next);
    true
}

fn emit_ready_if_changed(
    state: &mut MonitorState,
    force: bool,
    emit_message: &mut impl FnMut(InputMessage) -> bool,
) -> bool {
    let count = key_device_count(&state.devices);
    if (force || state.last_key_device_count != Some(count))
        && !emit_message(InputMessage::Ready { devices: count })
    {
        return false;
    }
    state.last_key_device_count = Some(count);
    true
}

fn spawn_device_thread(
    path: PathBuf,
    token: u64,
    mut device: Device,
    lock_candidate: bool,
    key_candidate: bool,
    tx: Sender<InternalEvent>,
) {
    thread::spawn(move || {
        loop {
            let mut resync_locks = false;
            let events = match device.fetch_events() {
                Ok(events) => events,
                Err(_) => break,
            };

            for event in events {
                match event.destructure() {
                    EventSummary::Key(_, code, value) => {
                        if key_candidate && (value == 0 || value == 1) {
                            let _ = tx.send(InternalEvent::KeyChanged {
                                path: path.clone(),
                                token,
                                code: code.0,
                                pressed: value == 1,
                            });
                        }

                        if lock_candidate
                            && value == 0
                            && (code == KeyCode::KEY_CAPSLOCK || code == KeyCode::KEY_NUMLOCK)
                        {
                            resync_locks = true;
                        }
                    }
                    EventSummary::Led(_, code, _)
                        if lock_candidate
                            && (code == LedCode::LED_CAPSL || code == LedCode::LED_NUML) =>
                    {
                        resync_locks = true;
                    }
                    _ => {}
                }
            }

            if lock_candidate
                && resync_locks
                && let Ok(leds) = device.get_led_state()
            {
                let _ = tx.send(InternalEvent::LockSnapshot {
                    path: path.clone(),
                    token,
                    caps: leds.contains(LedCode::LED_CAPSL),
                    num: leds.contains(LedCode::LED_NUML),
                });
            }
        }

        let _ = tx.send(InternalEvent::DeviceGone { path, token });
    });
}

fn add_device(path: &Path, state: &mut MonitorState, tx: &Sender<InternalEvent>, mode: StreamMode) {
    let Ok(device) = Device::open(path) else {
        return;
    };

    let lock_candidate = mode.wants_locks() && is_lock_candidate(&device);
    let key_candidate = mode.wants_keys() && is_key_candidate(&device);
    if !lock_candidate && !key_candidate {
        return;
    }

    state.next_token = state.next_token.wrapping_add(1).max(1);
    let token = state.next_token;
    let (caps, num) = if lock_candidate {
        initial_lock_state(&device)
    } else {
        (false, false)
    };
    let pressed = if key_candidate {
        initial_pressed(&device)
    } else {
        HashSet::new()
    };

    state.devices.insert(
        path.to_path_buf(),
        DeviceRuntime {
            token,
            lock_candidate,
            key_candidate,
            caps,
            num,
            pressed,
        },
    );

    spawn_device_thread(
        path.to_path_buf(),
        token,
        device,
        lock_candidate,
        key_candidate,
        tx.clone(),
    );
}

fn refresh_devices(state: &mut MonitorState, tx: &Sender<InternalEvent>, mode: StreamMode) {
    let paths = event_paths();
    let discovered = paths.iter().cloned().collect::<HashSet<_>>();

    state.devices.retain(|path, _| discovered.contains(path));

    for path in paths {
        if !state.devices.contains_key(&path) {
            add_device(&path, state, tx, mode);
        }
    }
}

fn spawn_hotplug_watcher(tx: Sender<InternalEvent>) {
    thread::spawn(move || {
        if let Err(error) = hotplug_loop(tx.clone()) {
            let _ = tx.send(InternalEvent::Hotplug);
            eprintln!("alis-inputd: inotify watcher stopped: {error:#}");
        }
    });
}

fn hotplug_loop(tx: Sender<InternalEvent>) -> Result<()> {
    let fd = unsafe { libc::inotify_init1(libc::IN_CLOEXEC) };
    if fd < 0 {
        return Err(io::Error::last_os_error()).context("inotify_init1");
    }
    let _fd = FdGuard(fd);

    let path = CString::new(INPUT_DIR).expect("static input path contains no NUL");
    let mask = libc::IN_CREATE
        | libc::IN_DELETE
        | libc::IN_MOVED_FROM
        | libc::IN_MOVED_TO
        | libc::IN_ATTRIB;
    let watch = unsafe { libc::inotify_add_watch(fd, path.as_ptr(), mask) };
    if watch < 0 {
        return Err(io::Error::last_os_error()).context("inotify_add_watch /dev/input");
    }

    let mut buffer = [0u8; 4096];
    loop {
        let read = unsafe { libc::read(fd, buffer.as_mut_ptr().cast(), buffer.len()) };
        if read < 0 {
            let error = io::Error::last_os_error();
            if error.kind() == io::ErrorKind::Interrupted {
                continue;
            }
            return Err(error).context("read inotify event");
        }
        if read == 0 {
            continue;
        }
        if tx.send(InternalEvent::Hotplug).is_err() {
            return Ok(());
        }
    }
}

struct FdGuard(RawFd);

impl Drop for FdGuard {
    fn drop(&mut self) {
        unsafe {
            libc::close(self.0);
        }
    }
}

fn snapshot_lock_state() -> Option<(bool, bool, usize)> {
    let mut lock_states = Vec::new();

    for path in event_paths() {
        let Ok(device) = Device::open(&path) else {
            continue;
        };
        if !is_lock_candidate(&device) {
            continue;
        }
        lock_states.push(initial_lock_state(&device));
    }

    let count = lock_states.len();
    if count == 0 {
        return None;
    }

    let caps = aggregate(lock_states.iter().map(|state| state.0), None)?;
    let num = aggregate(lock_states.iter().map(|state| state.1), None)?;
    Some((caps, num, count))
}

fn run_once() -> i32 {
    let Some((caps, num, count)) = snapshot_lock_state() else {
        return 1;
    };

    if emit(InputMessage::State {
        caps,
        num,
        devices: count,
    }) {
        0
    } else {
        1
    }
}

fn process_event(
    event: InternalEvent,
    state: &mut MonitorState,
    tx: &Sender<InternalEvent>,
    mode: StreamMode,
    emit_message: &mut impl FnMut(InputMessage) -> bool,
) -> bool {
    match event {
        InternalEvent::Hotplug => {
            refresh_devices(state, tx, mode);
            if mode.wants_locks() && !emit_lock_if_changed(state, false, emit_message) {
                return false;
            }
            if mode.wants_keys() && !emit_ready_if_changed(state, false, emit_message) {
                return false;
            }
        }
        InternalEvent::DeviceGone { path, token } => {
            if state
                .devices
                .get(&path)
                .is_some_and(|device| device.token == token)
            {
                let removed = state.devices.remove(&path);
                if let Some(removed) = removed
                    && mode.wants_keys()
                    && removed.key_candidate
                {
                    for code in removed.pressed {
                        if !key_pressed(&state.devices, code)
                            && !emit_message(InputMessage::Key {
                                code,
                                pressed: false,
                            })
                        {
                            return false;
                        }
                    }
                }
                if mode.wants_locks() && !emit_lock_if_changed(state, false, emit_message) {
                    return false;
                }
                if mode.wants_keys() && !emit_ready_if_changed(state, false, emit_message) {
                    return false;
                }
            }
        }
        InternalEvent::LockSnapshot {
            path,
            token,
            caps,
            num,
        } => {
            if let Some(device) = state.devices.get_mut(&path)
                && device.token == token
                && device.lock_candidate
            {
                device.caps = caps;
                device.num = num;
                if mode.wants_locks() && !emit_lock_if_changed(state, false, emit_message) {
                    return false;
                }
            }
        }
        InternalEvent::KeyChanged {
            path,
            token,
            code,
            pressed,
        } => {
            let was_pressed = key_pressed(&state.devices, code);
            if let Some(device) = state.devices.get_mut(&path) {
                if device.token == token && device.key_candidate {
                    if pressed {
                        device.pressed.insert(code);
                    } else {
                        device.pressed.remove(&code);
                    }
                } else {
                    return true;
                }
            } else {
                return true;
            }

            let is_pressed = key_pressed(&state.devices, code);
            if mode.wants_keys()
                && was_pressed != is_pressed
                && !emit_message(InputMessage::Key {
                    code,
                    pressed: is_pressed,
                })
            {
                return false;
            }
        }
    }
    true
}

fn run_stream(mode: StreamMode) -> i32 {
    let (tx, rx): (Sender<InternalEvent>, Receiver<InternalEvent>) = mpsc::channel();
    let mut state = MonitorState::default();
    let mut emit_message = emit;

    refresh_devices(&mut state, &tx, mode);
    if mode.wants_locks() && !emit_lock_if_changed(&mut state, true, &mut emit_message) {
        return 0;
    }
    if mode.wants_keys() && !emit_ready_if_changed(&mut state, true, &mut emit_message) {
        return 0;
    }

    spawn_hotplug_watcher(tx.clone());

    while let Ok(event) = rx.recv() {
        if !process_event(event, &mut state, &tx, mode, &mut emit_message) {
            break;
        }
    }
    0
}

fn main() {
    let args = Args::parse();
    let code = if args.once {
        run_once()
    } else {
        run_stream(args.mode)
    };
    std::process::exit(code);
}

#[cfg(test)]
mod tests {
    use std::collections::HashSet;
    use std::path::PathBuf;
    use std::sync::mpsc;

    use alis_protocol::InputMessage;

    use super::{DeviceRuntime, InternalEvent, MonitorState, StreamMode, aggregate, process_event};

    #[test]
    fn aggregate_matches_python_majority_rule() {
        assert_eq!(aggregate([true, true, false].into_iter(), None), Some(true));
        assert_eq!(
            aggregate([false, false, true].into_iter(), None),
            Some(false)
        );
    }

    #[test]
    fn aggregate_keeps_previous_on_tie() {
        assert_eq!(aggregate([true, false].into_iter(), Some(true)), Some(true));
        assert_eq!(
            aggregate([true, false].into_iter(), Some(false)),
            Some(false)
        );
        assert_eq!(aggregate([true, false].into_iter(), None), Some(false));
    }

    #[test]
    fn aggregate_empty_has_no_state() {
        assert_eq!(aggregate(std::iter::empty(), None), None);
    }

    #[test]
    fn synthetic_key_stream_preserves_aggregate_press_and_hot_unplug_release() {
        let first = PathBuf::from("/fixture/event1");
        let second = PathBuf::from("/fixture/event2");
        let mut state = MonitorState::default();
        for (path, token) in [(&first, 1), (&second, 2)] {
            state.devices.insert(
                path.clone(),
                DeviceRuntime {
                    token,
                    lock_candidate: false,
                    key_candidate: true,
                    caps: false,
                    num: false,
                    pressed: HashSet::new(),
                },
            );
        }
        state.last_key_device_count = Some(2);

        let (tx, _rx) = mpsc::channel();
        let mut messages = Vec::new();
        let mut capture = |message| {
            messages.push(message);
            true
        };

        assert!(process_event(
            InternalEvent::KeyChanged {
                path: first.clone(),
                token: 1,
                code: 30,
                pressed: true,
            },
            &mut state,
            &tx,
            StreamMode::Keys,
            &mut capture,
        ));
        assert!(process_event(
            InternalEvent::KeyChanged {
                path: second.clone(),
                token: 2,
                code: 30,
                pressed: true,
            },
            &mut state,
            &tx,
            StreamMode::Keys,
            &mut capture,
        ));
        assert!(process_event(
            InternalEvent::KeyChanged {
                path: first.clone(),
                token: 1,
                code: 30,
                pressed: false,
            },
            &mut state,
            &tx,
            StreamMode::Keys,
            &mut capture,
        ));
        assert!(process_event(
            InternalEvent::DeviceGone {
                path: second,
                token: 2,
            },
            &mut state,
            &tx,
            StreamMode::Keys,
            &mut capture,
        ));

        assert_eq!(
            messages,
            vec![
                InputMessage::Key {
                    code: 30,
                    pressed: true,
                },
                InputMessage::Key {
                    code: 30,
                    pressed: false,
                },
                InputMessage::Ready { devices: 1 },
            ]
        );
    }

    #[test]
    fn stream_modes_only_enable_requested_work() {
        assert!(StreamMode::Locks.wants_locks());
        assert!(!StreamMode::Locks.wants_keys());

        assert!(!StreamMode::Keys.wants_locks());
        assert!(StreamMode::Keys.wants_keys());

        assert!(StreamMode::All.wants_locks());
        assert!(StreamMode::All.wants_keys());
    }
}
