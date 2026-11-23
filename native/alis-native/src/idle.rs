use std::collections::HashMap;
use std::os::fd::OwnedFd;
use std::process::Command;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use alis_dbus::{DBusConnection, DBusValue, MSG_SIGNAL};
use alis_wayland::{WlConnection, WlWriter};
use anyhow::{Result, anyhow, bail};

const EXT_IDLE_GET_NOTIFICATION: u16 = 1;
const EXT_IDLE_NOTIF_DESTROY: u16 = 0;
const EXT_IDLE_NOTIF_EV_IDLED: u16 = 0;
const EXT_IDLE_NOTIF_EV_RESUMED: u16 = 1;

static STOP_REQUESTED: AtomicBool = AtomicBool::new(false);

extern "C" fn handle_signal(_sig: libc::c_int) {
    STOP_REQUESTED.store(true, Ordering::SeqCst);
}

#[derive(Debug, Clone)]
pub struct TimeoutRule {
    pub seconds: u32,
    pub timeout_cmd: String,
    pub resume_cmd: Option<String>,
}

#[derive(Debug, Default, Clone)]
pub struct IdleConfig {
    pub wait_for_commands: bool,
    pub timeouts: Vec<TimeoutRule>,
    pub before_sleep: Vec<String>,
    pub after_resume: Vec<String>,
    pub lock_cmds: Vec<String>,
    pub unlock_cmds: Vec<String>,
}

pub fn parse_swayidle_args(raw: &[String]) -> Result<IdleConfig> {
    let mut cfg = IdleConfig::default();
    let mut i = 0;
    while i < raw.len() {
        match raw[i].as_str() {
            "-w" => {
                cfg.wait_for_commands = true;
                i += 1;
            }
            "timeout" => {
                if i + 2 >= raw.len() {
                    bail!("idle timeout requires <seconds> <command>");
                }
                let seconds: u32 = raw[i + 1].parse()?;
                let timeout_cmd = raw[i + 2].clone();
                i += 3;
                let resume_cmd = if raw.get(i).map(String::as_str) == Some("resume") {
                    let cmd = raw
                        .get(i + 1)
                        .ok_or_else(|| anyhow!("idle resume requires <command>"))?
                        .clone();
                    i += 2;
                    Some(cmd)
                } else {
                    None
                };
                cfg.timeouts.push(TimeoutRule {
                    seconds,
                    timeout_cmd,
                    resume_cmd,
                });
            }
            "before-sleep" => {
                let cmd = raw
                    .get(i + 1)
                    .ok_or_else(|| anyhow!("before-sleep requires <command>"))?
                    .clone();
                cfg.before_sleep.push(cmd);
                i += 2;
            }
            "after-resume" => {
                let cmd = raw
                    .get(i + 1)
                    .ok_or_else(|| anyhow!("after-resume requires <command>"))?
                    .clone();
                cfg.after_resume.push(cmd);
                i += 2;
            }
            "lock" => {
                let cmd = raw
                    .get(i + 1)
                    .ok_or_else(|| anyhow!("lock requires <command>"))?
                    .clone();
                cfg.lock_cmds.push(cmd);
                i += 2;
            }
            "unlock" => {
                let cmd = raw
                    .get(i + 1)
                    .ok_or_else(|| anyhow!("unlock requires <command>"))?
                    .clone();
                cfg.unlock_cmds.push(cmd);
                i += 2;
            }
            other => bail!("unknown idle argument: {other}"),
        }
    }
    Ok(cfg)
}

fn run_shell_command(cmd: &str, wait: bool, children: &mut Vec<std::process::Child>) {
    if cmd.trim().is_empty() {
        return;
    }
    let mut proc = Command::new("/bin/sh");
    proc.arg("-c").arg(cmd);
    if wait {
        let _ = proc.status();
    } else if let Ok(child) = proc.spawn() {
        children.push(child);
    }
}

fn acquire_sleep_inhibitor(conn: &mut DBusConnection) -> Option<Arc<OwnedFd>> {
    let reply = conn
        .call(
            "org.freedesktop.login1",
            "/org/freedesktop/login1",
            "org.freedesktop.login1.Manager",
            "Inhibit",
            "ssss",
            &[
                DBusValue::String("sleep".to_string()),
                DBusValue::String("alis-native".to_string()),
                DBusValue::String("Run before-sleep hooks".to_string()),
                DBusValue::String("delay".to_string()),
            ],
        )
        .ok()?;
    let idx = reply.body.first().and_then(DBusValue::as_u32).unwrap_or(0) as usize;
    reply
        .fds
        .get(idx)
        .cloned()
        .or_else(|| reply.fds.first().cloned())
}

fn reap_children(children: &mut Vec<std::process::Child>) {
    children.retain_mut(|child| matches!(child.try_wait(), Ok(None)));
}

pub fn run(raw_args: &[String]) -> Result<i32> {
    let cfg = parse_swayidle_args(raw_args)?;
    STOP_REQUESTED.store(false, Ordering::SeqCst);
    unsafe {
        libc::signal(libc::SIGTERM, handle_signal as *const () as libc::sighandler_t);
        libc::signal(libc::SIGINT, handle_signal as *const () as libc::sighandler_t);
    }

    let mut wl = WlConnection::connect()?;
    let (registry, globals) = wl.get_globals()?;
    let seat_g = globals
        .iter()
        .find(|g| g.interface == "wl_seat")
        .ok_or_else(|| anyhow!("compositor did not advertise wl_seat"))?
        .clone();
    let notifier_g = globals
        .iter()
        .find(|g| g.interface == "ext_idle_notifier_v1")
        .ok_or_else(|| anyhow!("compositor does not advertise ext_idle_notifier_v1"))?
        .clone();

    let seat_id = wl.bind_global(registry, seat_g.name, "wl_seat", seat_g.version.min(5))?;
    let notifier_id = wl.bind_global(
        registry,
        notifier_g.name,
        "ext_idle_notifier_v1",
        notifier_g.version.min(2),
    )?;

    let mut notif_map: HashMap<u32, TimeoutRule> = HashMap::new();
    for rule in &cfg.timeouts {
        let notif_id = wl.next_id();
        let timeout_ms = rule.seconds.saturating_mul(1000);
        let mut w = WlWriter::new();
        w.u32(notif_id).u32(timeout_ms).u32(seat_id);
        wl.send(notifier_id, EXT_IDLE_GET_NOTIFICATION, w)?;
        notif_map.insert(notif_id, rule.clone());
    }
    let _ = wl.roundtrip()?;

    let mut dbus = match DBusConnection::connect_system() {
        Ok(mut conn) => {
            let _ = conn.add_match(
                "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'",
            );
            let _ = conn.add_match(
                "type='signal',interface='org.freedesktop.login1.Session',member='Lock'",
            );
            let _ = conn.add_match(
                "type='signal',interface='org.freedesktop.login1.Session',member='Unlock'",
            );
            Some(conn)
        }
        Err(_) => None,
    };

    let mut sleep_inhibit_fd = if !cfg.before_sleep.is_empty() {
        dbus.as_mut().and_then(acquire_sleep_inhibitor)
    } else {
        None
    };

    let mut children: Vec<std::process::Child> = Vec::new();
    let mut wl_disconnected = false;

    while !STOP_REQUESTED.load(Ordering::SeqCst) {
        reap_children(&mut children);

        let mut pfds = vec![libc::pollfd {
            fd: wl.as_raw_fd(),
            events: libc::POLLIN,
            revents: 0,
        }];
        if let Some(ref d) = dbus {
            pfds.push(libc::pollfd {
                fd: d.as_raw_fd(),
                events: libc::POLLIN,
                revents: 0,
            });
        }

        let rc = unsafe { libc::poll(pfds.as_mut_ptr(), pfds.len() as libc::nfds_t, 500) };
        if rc < 0 {
            let err = std::io::Error::last_os_error();
            if err.kind() == std::io::ErrorKind::Interrupted {
                continue;
            }
            return Err(err.into());
        }
        if rc == 0 {
            continue;
        }

        if (pfds[0].revents & (libc::POLLERR | libc::POLLNVAL)) != 0 {
            wl_disconnected = true;
            break;
        }
        if (pfds[0].revents & libc::POLLIN) != 0 {
            loop {
                match wl.recv_message_timeout(0) {
                    Ok(Some(ev)) => {
                        WlConnection::check_display_error(&ev)?;
                        if let Some(rule) = notif_map.get(&ev.object_id) {
                            if ev.opcode == EXT_IDLE_NOTIF_EV_IDLED {
                                run_shell_command(
                                    &rule.timeout_cmd,
                                    cfg.wait_for_commands,
                                    &mut children,
                                );
                            } else if ev.opcode == EXT_IDLE_NOTIF_EV_RESUMED
                                && let Some(ref resume) = rule.resume_cmd
                            {
                                run_shell_command(resume, cfg.wait_for_commands, &mut children);
                            }
                        }
                    }
                    Ok(None) => break,
                    Err(_) => {
                        wl_disconnected = true;
                        break;
                    }
                }
            }
            if wl_disconnected {
                break;
            }
        } else if (pfds[0].revents & libc::POLLHUP) != 0 {
            wl_disconnected = true;
            break;
        }

        if pfds.len() > 1 {
            let drev = pfds[1].revents;
            let mut drop_dbus = (drev & (libc::POLLERR | libc::POLLNVAL)) != 0
                || ((drev & libc::POLLHUP) != 0 && (drev & libc::POLLIN) == 0);
            if !drop_dbus && (drev & libc::POLLIN) != 0
                && let Some(ref mut d) = dbus
            {
                let mut reacquire_inhibit = false;
                loop {
                    match d.read_message_timeout(0) {
                        Ok(Some(msg)) => {
                            if msg.msg_type != MSG_SIGNAL {
                                continue;
                            }
                            match msg.member.as_deref() {
                                Some("PrepareForSleep") => {
                                    let sleeping = msg
                                        .body
                                        .first()
                                        .and_then(DBusValue::as_bool)
                                        .unwrap_or(false);
                                    if sleeping {
                                        for cmd in &cfg.before_sleep {
                                            run_shell_command(cmd, true, &mut children);
                                        }
                                        sleep_inhibit_fd = None;
                                    } else {
                                        for cmd in &cfg.after_resume {
                                            run_shell_command(
                                                cmd,
                                                cfg.wait_for_commands,
                                                &mut children,
                                            );
                                        }
                                        if !cfg.before_sleep.is_empty() {
                                            reacquire_inhibit = true;
                                        }
                                    }
                                }
                                Some("Lock") => {
                                    for cmd in &cfg.lock_cmds {
                                        run_shell_command(cmd, cfg.wait_for_commands, &mut children);
                                    }
                                }
                                Some("Unlock") => {
                                    for cmd in &cfg.unlock_cmds {
                                        run_shell_command(cmd, cfg.wait_for_commands, &mut children);
                                    }
                                }
                                _ => {}
                            }
                        }
                        Ok(None) => break,
                        Err(_) => {
                            drop_dbus = true;
                            break;
                        }
                    }
                }
                if !drop_dbus && reacquire_inhibit && sleep_inhibit_fd.is_none() {
                    sleep_inhibit_fd = acquire_sleep_inhibitor(d);
                }
            }
            if drop_dbus {
                dbus = None;
            }
        }
    }

    reap_children(&mut children);
    if !wl_disconnected {
        for &notif_id in notif_map.keys() {
            let _ = wl.send(notif_id, EXT_IDLE_NOTIF_DESTROY, WlWriter::new());
        }
        let _ = wl.roundtrip();
    }
    Ok(0)
}

#[cfg(test)]
mod tests {
    use super::parse_swayidle_args;

    #[test]
    fn parses_full_idle_qml_invocation() {
        let args: Vec<String> = vec![
            "-w",
            "timeout",
            "300",
            "niri msg action power-off-monitors",
            "resume",
            "niri msg action power-on-monitors",
            "timeout",
            "600",
            "alis lock activate",
            "before-sleep",
            "alis lock activate",
            "after-resume",
            "alis lock focus",
        ]
        .into_iter()
        .map(String::from)
        .collect();
        let cfg = parse_swayidle_args(&args).unwrap();
        assert!(cfg.wait_for_commands);
        assert_eq!(cfg.timeouts.len(), 2);
        assert_eq!(cfg.timeouts[0].seconds, 300);
        assert!(cfg.timeouts[0].resume_cmd.is_some());
        assert_eq!(cfg.timeouts[1].seconds, 600);
        assert_eq!(cfg.before_sleep.len(), 1);
        assert_eq!(cfg.after_resume.len(), 1);
    }
}
