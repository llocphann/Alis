use std::fs;
use std::io::Write;
use std::os::unix::fs::symlink;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

use alis_dbus::{DBusConnection, DBusValue, MSG_SIGNAL};
use anyhow::{Context, Result, anyhow, bail};
use clap::{Args, Subcommand};
use serde_json::{Value, json};

#[derive(Debug, Subcommand)]
pub enum DesktopCommand {
    /// Sync icon theme to kdeglobals, qt5ct, qt6ct, and GTK settings.ini.
    SyncIconTheme { theme: String },

    /// Sync UI/monospace fonts to kdeglobals, GTK settings.ini, and xsettingsd.conf (replaces kwriteconfig6).
    SyncFonts {
        main_font: String,
        mono_font: String,
        size: u32,
    },

    /// Direct INI key writer replacing kwriteconfig6 --file <file> --group <group> --key <key> <value>.
    SetKdeConfig {
        #[arg(long)]
        file: String,
        #[arg(long)]
        group: String,
        #[arg(long)]
        key: String,
        value: String,
    },

    /// Native file chooser via XDG Desktop Portal FileChooser D-Bus (replaces kdialog).
    FileDialog(FileDialogArgs),

    /// Native package update checker (replaces pacman-contrib checkupdates).
    CheckUpdates,
}

#[derive(Debug, Args)]
pub struct FileDialogArgs {
    /// Dialog title.
    #[arg(long, default_value = "Select file")]
    pub title: String,

    /// Dialog mode: open or save.
    #[arg(long, default_value = "open")]
    pub mode: String,

    /// Allow selecting multiple files.
    #[arg(long)]
    pub multiple: bool,

    /// Allow selecting directories instead of files.
    #[arg(long)]
    pub directory: bool,

    /// Initial folder path.
    #[arg(long)]
    pub current_folder: Option<String>,

    /// Space-separated glob filters (e.g. "*.png *.jpg").
    #[arg(long)]
    pub filter: Option<String>,
}

pub enum DesktopOutcome {
    Json(Value),
    RawLines { lines: Vec<String>, code: i32 },
}

pub fn run(command: DesktopCommand) -> Result<DesktopOutcome> {
    match command {
        DesktopCommand::SyncIconTheme { theme } => Ok(DesktopOutcome::Json(sync_icon_theme(&theme)?)),
        DesktopCommand::SyncFonts {
            main_font,
            mono_font,
            size,
        } => Ok(DesktopOutcome::Json(sync_fonts(&main_font, &mono_font, size)?)),
        DesktopCommand::SetKdeConfig {
            file,
            group,
            key,
            value,
        } => Ok(DesktopOutcome::Json(set_kde_config(&file, &group, &key, &value)?)),
        DesktopCommand::FileDialog(args) => run_file_dialog(args),
        DesktopCommand::CheckUpdates => run_check_updates(),
    }
}

fn home_dir() -> PathBuf {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/"))
}

fn config_home() -> PathBuf {
    std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| home_dir().join(".config"))
}

fn atomic_write(path: &Path, content: &str) -> Result<()> {
    let parent = path.parent().unwrap_or_else(|| Path::new("."));
    fs::create_dir_all(parent)?;
    let temporary = parent.join(format!(
        ".{}.alis-native-{}.tmp",
        path.file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("config"),
        std::process::id()
    ));
    {
        let mut file = fs::File::create(&temporary)
            .with_context(|| format!("create {}", temporary.display()))?;
        file.write_all(content.as_bytes())?;
        let _ = file.sync_all();
    }
    fs::rename(&temporary, path).with_context(|| format!("replace {}", path.display()))?;
    Ok(())
}

fn section_bounds(lines: &[String], section: &str) -> Option<(usize, usize)> {
    let header = format!("[{section}]");
    let start = lines.iter().position(|line| line.trim() == header)?;
    let end = lines
        .iter()
        .enumerate()
        .skip(start + 1)
        .find(|(_, line)| {
            let line = line.trim();
            line.starts_with('[') && line.ends_with(']')
        })
        .map(|(index, _)| index)
        .unwrap_or(lines.len());
    Some((start, end))
}

fn set_ini_key(content: &str, section: &str, key: &str, value: &str) -> String {
    let mut lines = content.lines().map(str::to_owned).collect::<Vec<_>>();
    let trailing_newline = content.ends_with('\n');
    let (start, mut end) = match section_bounds(&lines, section) {
        Some(bounds) => bounds,
        None => {
            if !lines.is_empty() && !lines.last().is_some_and(|line| line.trim().is_empty()) {
                lines.push(String::new());
            }
            lines.push(format!("[{section}]"));
            let start = lines.len() - 1;
            (start, lines.len())
        }
    };

    let mut replaced = false;
    for line in &mut lines[start + 1..end] {
        let trimmed = line.trim_start();
        if trimmed.starts_with('#') || trimmed.starts_with(';') {
            continue;
        }
        let Some((candidate, _)) = trimmed.split_once('=') else {
            continue;
        };
        if candidate.trim() == key {
            let prefix = " ".repeat(line.len() - trimmed.len());
            *line = format!("{prefix}{key}={value}");
            replaced = true;
            break;
        }
    }
    if !replaced {
        end = end.min(lines.len());
        lines.insert(end, format!("{key}={value}"));
    }

    let mut output = lines.join("\n");
    if trailing_newline || !output.is_empty() {
        output.push('\n');
    }
    output
}

fn backup_corrupt(path: &Path) -> Result<Option<PathBuf>> {
    if !path.is_file() || fs::metadata(path).map(|meta| meta.len()).unwrap_or(0) == 0 {
        return Ok(None);
    }
    let seconds = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    let backup = PathBuf::from(format!("{}.corrupt-{seconds}.bak", path.display()));
    fs::copy(path, &backup)?;
    Ok(Some(backup))
}

fn sync_one(
    path: &Path,
    section: &str,
    key: &str,
    value: &str,
    reset_if_missing_section: bool,
) -> Result<Value> {
    let existing = fs::read_to_string(path).unwrap_or_default();
    let has_section = section_bounds(
        &existing.lines().map(str::to_owned).collect::<Vec<_>>(),
        section,
    )
    .is_some();
    let (base, backup) = if reset_if_missing_section && !has_section && !existing.is_empty() {
        (String::new(), backup_corrupt(path)?)
    } else {
        (existing, None)
    };
    let updated = set_ini_key(&base, section, key, value);
    if updated != base {
        atomic_write(path, &updated)?;
    }
    Ok(json!({
        "path": path.to_string_lossy(),
        "updated": true,
        "backup": backup.map(|path| path.to_string_lossy().into_owned())
    }))
}

fn set_kde_config(file: &str, group: &str, key: &str, value: &str) -> Result<Value> {
    let target = if Path::new(file).is_absolute() {
        PathBuf::from(file)
    } else {
        config_home().join(file)
    };
    sync_one(&target, group, key, value, false)
}

fn sync_icon_theme(theme: &str) -> Result<Value> {
    if theme.trim().is_empty() || theme.contains('\n') || theme.contains('\r') {
        bail!("invalid_icon_theme");
    }
    let config = config_home();
    let results = vec![
        sync_one(&config.join("kdeglobals"), "Icons", "Theme", theme, false)?,
        sync_one(
            &config.join("qt5ct/qt5ct.conf"),
            "Appearance",
            "icon_theme",
            theme,
            false,
        )?,
        sync_one(
            &config.join("qt6ct/qt6ct.conf"),
            "Appearance",
            "icon_theme",
            theme,
            false,
        )?,
        sync_one(
            &config.join("gtk-3.0/settings.ini"),
            "Settings",
            "gtk-icon-theme-name",
            theme,
            true,
        )?,
        sync_one(
            &config.join("gtk-4.0/settings.ini"),
            "Settings",
            "gtk-icon-theme-name",
            theme,
            true,
        )?,
    ];
    Ok(json!({"ok": true, "theme": theme, "files": results}))
}

fn sync_fonts(main_font: &str, mono_font: &str, size: u32) -> Result<Value> {
    if main_font.trim().is_empty() || mono_font.trim().is_empty() || size == 0 {
        bail!("invalid_font_parameters");
    }
    let config = config_home();
    let kdeglobals = config.join("kdeglobals");
    let main_kde = format!("{main_font},{size},-1,5,50,0,0,0,0,0,0,0,0,0,0,1");
    let mono_kde = format!("{mono_font},{size},-1,5,50,0,0,0,0,0,0,0,0,0,0,1");

    let mut existing = fs::read_to_string(&kdeglobals).unwrap_or_default();
    let original = existing.clone();
    for key in ["font", "menuFont", "toolBarFont"] {
        existing = set_ini_key(&existing, "General", key, &main_kde);
    }
    existing = set_ini_key(&existing, "General", "fixed", &mono_kde);
    if existing != original {
        atomic_write(&kdeglobals, &existing)?;
    }

    let gtk_font = format!("{main_font} {size}");
    for subdir in ["gtk-3.0", "gtk-4.0"] {
        let p = config.join(subdir).join("settings.ini");
        if p.is_file() {
            let _ = sync_one(&p, "Settings", "gtk-font-name", &gtk_font, false);
        }
    }

    let xsettings = config.join("xsettingsd/xsettingsd.conf");
    if xsettings.is_file() {
        let content = fs::read_to_string(&xsettings).unwrap_or_default();
        let replacement = format!("Gtk/FontName \"{main_font},  {size}\"");
        let mut found = false;
        let mut lines: Vec<String> = content
            .lines()
            .map(|l| {
                if l.starts_with("Gtk/FontName ") {
                    found = true;
                    replacement.clone()
                } else {
                    l.to_string()
                }
            })
            .collect();
        if !found {
            lines.push(replacement);
        }
        let next = lines.join("\n") + "\n";
        if next != content {
            atomic_write(&xsettings, &next)?;
        }
    }

    Ok(json!({
        "ok": true,
        "mainFont": main_font,
        "monoFont": mono_font,
        "size": size,
        "kdeglobals": kdeglobals.to_string_lossy()
    }))
}

// ---------------------------------------------------------------------------
// XDG Desktop Portal FileChooser (replaces kdialog)
// ---------------------------------------------------------------------------

fn percent_decode_uri(uri: &str) -> String {
    let raw = uri.strip_prefix("file://").unwrap_or(uri);
    let bytes = raw.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%'
            && i + 2 < bytes.len()
            && let Ok(hex) = std::str::from_utf8(&bytes[i + 1..i + 3])
            && let Ok(val) = u8::from_str_radix(hex, 16)
        {
            out.push(val);
            i += 3;
            continue;
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

fn run_file_dialog(args: FileDialogArgs) -> Result<DesktopOutcome> {
    if std::env::var_os("WAYLAND_DISPLAY").is_none() && std::env::var_os("DISPLAY").is_none() {
        bail!("no graphical display available for file dialog");
    }
    let mut conn = DBusConnection::connect_session()?;
    let token = format!(
        "alis_file_dialog_{}_{}",
        std::process::id(),
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis()
    );
    let sender_slug = conn
        .unique_name()
        .trim_start_matches(':')
        .replace('.', "_");
    let expected_path = format!("/org/freedesktop/portal/desktop/request/{sender_slug}/{token}");

    conn.add_match(&format!(
        "type='signal',interface='org.freedesktop.portal.Request',member='Response',path='{expected_path}'"
    ))?;

    let is_save = args.mode.eq_ignore_ascii_case("save");
    let mut opts: Vec<(DBusValue, DBusValue)> = vec![(
        DBusValue::String("handle_token".into()),
        DBusValue::Variant("s".into(), Box::new(DBusValue::String(token))),
    )];
    if !is_save {
        opts.push((
            DBusValue::String("multiple".into()),
            DBusValue::Variant("b".into(), Box::new(DBusValue::Bool(args.multiple))),
        ));
        opts.push((
            DBusValue::String("directory".into()),
            DBusValue::Variant("b".into(), Box::new(DBusValue::Bool(args.directory))),
        ));
    }

    if let Some(folder) = args.current_folder.as_deref().filter(|s| !s.is_empty()) {
        let mut bytes: Vec<DBusValue> = folder.as_bytes().iter().copied().map(DBusValue::Byte).collect();
        bytes.push(DBusValue::Byte(0));
        opts.push((
            DBusValue::String("current_folder".into()),
            DBusValue::Variant("ay".into(), Box::new(DBusValue::Array("y".into(), bytes))),
        ));
    }

    if let Some(filter_str) = args.filter.as_deref().filter(|s| !s.is_empty()) {
        let mut patterns = Vec::new();
        for tok in filter_str.split_whitespace() {
            patterns.push(DBusValue::Struct(vec![
                DBusValue::Uint32(0), // glob pattern
                DBusValue::String(tok.to_string()),
            ]));
        }
        if !patterns.is_empty() {
            let filter_entry = DBusValue::Struct(vec![
                DBusValue::String("Supported Files".into()),
                DBusValue::Array("(us)".into(), patterns),
            ]);
            opts.push((
                DBusValue::String("filters".into()),
                DBusValue::Variant(
                    "a(sa(us))".into(),
                    Box::new(DBusValue::Array("(sa(us))".into(), vec![filter_entry])),
                ),
            ));
        }
    }

    let member = if args.mode.eq_ignore_ascii_case("save") {
        "SaveFile"
    } else {
        "OpenFile"
    };
    let reply = conn.call(
        "org.freedesktop.portal.Desktop",
        "/org/freedesktop/portal/desktop",
        "org.freedesktop.portal.FileChooser",
        member,
        "ssa{sv}",
        &[
            DBusValue::String(String::new()),
            DBusValue::String(args.title),
            DBusValue::Dict("s".into(), "v".into(), opts),
        ],
    )?;

    let request_path = reply
        .body
        .first()
        .and_then(DBusValue::as_str)
        .unwrap_or(&expected_path)
        .to_string();

    loop {
        let msg = conn.read_message()?;
        if msg.msg_type == MSG_SIGNAL
            && msg.interface.as_deref() == Some("org.freedesktop.portal.Request")
            && msg.member.as_deref() == Some("Response")
            && msg.path.as_deref() == Some(request_path.as_str())
        {
            let response_code = msg.body.first().and_then(DBusValue::as_u32).unwrap_or(2);
            if response_code != 0 {
                return Ok(DesktopOutcome::RawLines {
                    lines: Vec::new(),
                    code: 1,
                });
            }
            let mut paths = Vec::new();
            if let Some(DBusValue::Dict(_, _, entries)) = msg.body.get(1) {
                for (k, v) in entries {
                    if k.as_str() == Some("uris")
                        && let DBusValue::Variant(_, inner) = v
                        && let DBusValue::Array(_, uris) = inner.as_ref()
                    {
                        for u in uris {
                            if let Some(s) = u.as_str() {
                                paths.push(percent_decode_uri(s));
                            }
                        }
                    }
                }
            }
            return Ok(DesktopOutcome::RawLines {
                lines: paths,
                code: 0,
            });
        }
    }
}

// ---------------------------------------------------------------------------
// Native Package Update Checker (replaces pacman-contrib checkupdates)
// ---------------------------------------------------------------------------

fn parse_pacman_repos(conf_path: &Path) -> Vec<(String, Vec<String>)> {
    let Ok(content) = fs::read_to_string(conf_path) else {
        return Vec::new();
    };
    let arch = std::env::consts::ARCH;
    let mut repos: Vec<(String, Vec<String>)> = Vec::new();
    let mut current: Option<(String, Vec<String>)> = None;

    for raw in content.lines() {
        let line = raw.split('#').next().unwrap_or("").trim();
        if line.is_empty() {
            continue;
        }
        if line.starts_with('[') && line.ends_with(']') {
            if let Some(prev) = current.take()
                && prev.0 != "options"
                && !prev.1.is_empty()
            {
                repos.push(prev);
            }
            let name = line[1..line.len() - 1].trim().to_string();
            current = Some((name, Vec::new()));
            continue;
        }
        let Some((ref repo_name, ref mut servers)) = current else {
            continue;
        };
        if repo_name == "options" {
            continue;
        }
        if let Some((k, v)) = line.split_once('=') {
            let key = k.trim();
            let val = v.trim();
            if key == "Server" {
                servers.push(val.replace("$repo", repo_name).replace("$arch", arch));
            } else if key == "Include"
                && let Ok(inc) = fs::read_to_string(val)
            {
                for iline in inc.lines() {
                    let t = iline.split('#').next().unwrap_or("").trim();
                    if let Some((ik, iv)) = t.split_once('=')
                        && ik.trim() == "Server"
                    {
                        servers.push(
                            iv.trim()
                                .replace("$repo", repo_name)
                                .replace("$arch", arch),
                        );
                        if servers.len() >= 3 {
                            break;
                        }
                    }
                }
            }
        }
    }
    if let Some(prev) = current
        && prev.0 != "options"
        && !prev.1.is_empty()
    {
        repos.push(prev);
    }
    repos
}

fn check_arch_updates_native() -> Result<DesktopOutcome> {
    let repos = parse_pacman_repos(Path::new("/etc/pacman.conf"));
    if repos.is_empty() {
        bail!("no pacman repositories parsed from /etc/pacman.conf");
    }

    let tmp_root = std::env::temp_dir().join(format!("alis-checkupdates-{}", std::process::id()));
    let sync_dir = tmp_root.join("sync");
    fs::create_dir_all(&sync_dir)?;
    let _ = symlink("/var/lib/pacman/local", tmp_root.join("local"));

    let mut synced_any = false;
    for (repo, servers) in &repos {
        let dest = sync_dir.join(format!("{repo}.db"));
        let sig_dest = sync_dir.join(format!("{repo}.db.sig"));
        let mut repo_ok = false;
        for base in servers.iter().take(4) {
            let trimmed_base = base.trim_end_matches('/');
            let url = format!("{trimmed_base}/{repo}.db");
            let ok = Command::new("curl")
                .args(["-fsSL", "--connect-timeout", "8", "--max-time", "25", "-o"])
                .arg(&dest)
                .arg(&url)
                .status()
                .is_ok_and(|s| s.success());
            if ok && dest.is_file() {
                // Best-effort fetch of optional signature for DatabaseRequired repos
                let sig_url = format!("{trimmed_base}/{repo}.db.sig");
                let _ = Command::new("curl")
                    .args(["-fsSL", "--connect-timeout", "4", "--max-time", "10", "-o"])
                    .arg(&sig_dest)
                    .arg(&sig_url)
                    .status();
                repo_ok = true;
                synced_any = true;
                break;
            }
        }
        if !repo_ok {
            // Fall back to the system sync DB so one unavailable third-party repo does not
            // make pacman -Qu reject the entire check.
            let existing_db = PathBuf::from(format!("/var/lib/pacman/sync/{repo}.db"));
            if existing_db.is_file() {
                let _ = fs::copy(&existing_db, &dest);
                let existing_sig = PathBuf::from(format!("/var/lib/pacman/sync/{repo}.db.sig"));
                if existing_sig.is_file() {
                    let _ = fs::copy(&existing_sig, &sig_dest);
                }
            }
        }
    }

    if !synced_any {
        let _ = fs::remove_dir_all(&tmp_root);
        bail!("failed to fetch pacman sync databases");
    }

    let out = Command::new("pacman")
        .args(["-Qu", "--dbpath"])
        .arg(&tmp_root)
        .output();
    let _ = fs::remove_dir_all(&tmp_root);

    let out = out.context("run pacman -Qu")?;
    let stdout = String::from_utf8_lossy(&out.stdout);
    let stderr = String::from_utf8_lossy(&out.stderr);
    let lines: Vec<String> = stdout
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty())
        .map(str::to_owned)
        .collect();
    if lines.is_empty() {
        if !out.status.success() && stderr.contains("error:") {
            bail!("pacman -Qu failed: {}", stderr.trim());
        }
        // Match checkupdates contract: exit 2 means 0 updates available
        Ok(DesktopOutcome::RawLines { lines, code: 2 })
    } else {
        Ok(DesktopOutcome::RawLines { lines, code: 0 })
    }
}

fn run_check_updates() -> Result<DesktopOutcome> {
    if Path::new("/etc/pacman.conf").is_file() {
        return check_arch_updates_native();
    }
    // Non-Arch fallback: dnf or apt
    if let Ok(out) = Command::new("dnf").args(["check-update", "-q"]).output() {
        let code = out.status.code().unwrap_or(1);
        if code == 100 || code == 0 {
            let lines: Vec<String> = String::from_utf8_lossy(&out.stdout)
                .lines()
                .map(str::trim)
                .filter(|l| !l.is_empty() && !l.starts_with("Last metadata"))
                .map(str::to_owned)
                .collect();
            return Ok(DesktopOutcome::RawLines {
                code: if lines.is_empty() { 2 } else { 0 },
                lines,
            });
        }
    }
    if let Ok(out) = Command::new("apt").args(["list", "--upgradable"]).output()
        && out.status.success()
    {
        let lines: Vec<String> = String::from_utf8_lossy(&out.stdout)
            .lines()
            .skip(1)
            .map(str::trim)
            .filter(|l| !l.is_empty())
            .map(str::to_owned)
            .collect();
        return Ok(DesktopOutcome::RawLines {
            code: if lines.is_empty() { 2 } else { 0 },
            lines,
        });
    }
    Err(anyhow!("no supported package manager found for update check"))
}

#[cfg(test)]
mod tests {
    use super::{percent_decode_uri, set_ini_key};

    #[test]
    fn updates_existing_key_without_destroying_other_sections() {
        let output = set_ini_key(
            "[Icons]\nTheme=old\nFoo=bar\n\n[Other]\nX=1\n",
            "Icons",
            "Theme",
            "new",
        );
        assert!(output.contains("[Icons]\nTheme=new\nFoo=bar"));
        assert!(output.contains("[Other]\nX=1"));
    }

    #[test]
    fn creates_missing_section() {
        assert!(
            set_ini_key("[Other]\nX=1\n", "Icons", "Theme", "WhiteSur-dark")
                .contains("[Icons]\nTheme=WhiteSur-dark")
        );
    }

    #[test]
    fn preserves_comments_and_inserts_missing_key() {
        let output = set_ini_key(
            "[Appearance]\n# keep me\nstyle=Fusion\n",
            "Appearance",
            "icon_theme",
            "Papirus",
        );
        assert!(output.contains("# keep me"));
        assert!(output.contains("icon_theme=Papirus"));
    }

    #[test]
    fn decodes_portal_file_uri() {
        assert_eq!(
            percent_decode_uri("file:///home/user/My%20Pictures/wall%231.png"),
            "/home/user/My Pictures/wall#1.png"
        );
    }
}
