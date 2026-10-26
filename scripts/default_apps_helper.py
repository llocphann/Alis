#!/usr/bin/env python3
"""SET-F01 helper: Native + Flatpak/Flathub app discovery, XDG/MIME sync, and safe launcher."""
import configparser
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
from pathlib import Path

SLOT_FALLBACKS = {
    "terminal": ["kitty", "foot", "ghostty", "alacritty", "wezterm", "konsole", "xterm"],
    "browser": ["firefox", "zen-browser", "librewolf", "chromium", "google-chrome-stable", "brave-browser", "xdg-open"],
    "editor": ["code", "codium", "zeditor", "zed", "kate", "gnome-text-editor", "gedit", "mousepad", "nvim"],
    "fileManager": ["nautilus", "dolphin", "thunar", "nemo", "pcmanfm-qt", "pcmanfm", "caja", "xdg-open"],
    "manageUser": ["kcmshell6 kcm_users", "gnome-control-center user-accounts", "mate-user-admin"],
    "network": ["nm-connection-editor", "kcmshell6 kcm_networkmanagement", "gnome-control-center network"],
    "networkEthernet": ["nm-connection-editor", "kcmshell6 kcm_networkmanagement", "gnome-control-center network"],
    "bluetooth": ["blueman-manager", "kcmshell6 kcm_bluetooth", "gnome-control-center bluetooth"],
    "volumeMixer": ["pavucontrol", "pavucontrol-qt", "helvum"],
    "taskManager": ["missioncenter", "resources", "plasma-systemmonitor", "gnome-system-monitor"],
}

KNOWN_SLOT_KEYWORDS = {
    "terminal": {
        "categories": {"TerminalEmulator"},
        "mimes": set(),
        "bins": {
            "kitty", "foot", "ghostty", "alacritty", "wezterm", "konsole",
            "xterm", "tilix", "terminator", "kgx", "ptyxis", "blackbox",
            "rio", "tabby", "warp", "zutty", "footclient",
        },
        "ids": {
            "kitty", "foot", "com.mitchellh.ghostty", "org.wezfurlong.wezterm",
            "org.kde.konsole", "org.gnome.console", "org.gnome.ptyxis",
            "com.raggesilver.blackbox", "Alacritty",
        },
    },
    "browser": {
        "categories": {"WebBrowser"},
        "mimes": {"x-scheme-handler/http", "x-scheme-handler/https", "text/html"},
        "bins": {
            "firefox", "zen-browser", "zen", "librewolf", "chromium",
            "google-chrome", "google-chrome-stable", "brave", "brave-browser",
            "vivaldi", "vivaldi-stable", "opera", "epiphany", "falkon",
            "floorp", "waterfox", "thorium-browser",
        },
        "ids": {
            "firefox", "org.mozilla.firefox", "app.zen_browser.zen", "zen",
            "io.gitlab.librewolf-community", "librewolf", "org.chromium.Chromium",
            "chromium", "com.google.Chrome", "google-chrome", "com.brave.Browser",
            "brave-browser", "com.vivaldi.Vivaldi", "one.ablaze.floorp",
        },
    },
    "editor": {
        "categories": {"TextEditor", "IDE"},
        "mimes": {"text/plain"},
        "bins": {
            "code", "code-oss", "codium", "vscodium", "zed", "zeditor",
            "nvim", "neovide", "gvim", "emacs", "gedit", "gnome-text-editor",
            "kate", "kwrite", "mousepad", "featherpad", "lapce", "hx",
            "helix", "subl", "sublime_text", "geany", "lite-xl",
        },
        "ids": {
            "code", "com.visualstudio.code", "com.vscodium.codium", "codium",
            "dev.zed.Zed", "zed", "org.kde.kate", "org.kde.kwrite",
            "org.gnome.TextEditor", "org.gnome.gedit", "org.xfce.mousepad",
            "io.lapce.lapce", "com.sublimetext.three",
        },
    },
    "fileManager": {
        "categories": {"FileManager"},
        "mimes": {"inode/directory"},
        "bins": {
            "nautilus", "dolphin", "thunar", "nemo", "pcmanfm", "pcmanfm-qt",
            "caja", "krusader", "doublecmd", "cosmic-files", "yazi", "ranger", "lf",
        },
        "ids": {
            "org.gnome.Nautilus", "nautilus", "org.kde.dolphin", "dolphin",
            "thunar", "org.xfce.Thunar", "nemo", "pcmanfm-qt", "org.kde.krusader",
            "com.system76.CosmicFiles",
        },
    },
    "manageUser": {
        "categories": {"UserSettings"},
        "mimes": set(),
        "bins": {"mate-user-admin", "gnome-control-center", "kcmshell6"},
        "ids": {"kcm_users", "gnome-user-accounts-panel"},
    },
    "network": {
        "categories": set(),
        "mimes": set(),
        "bins": {"nm-connection-editor", "nmtui", "iwgtk"},
        "ids": {"nm-connection-editor", "kcm_networkmanagement", "gnome-network-panel"},
    },
    "networkEthernet": {
        "categories": set(),
        "mimes": set(),
        "bins": {"nm-connection-editor", "iwgtk"},
        "ids": {"nm-connection-editor", "kcm_networkmanagement", "gnome-network-panel"},
    },
    "bluetooth": {
        "categories": {"Bluetooth"},
        "mimes": set(),
        "bins": {"blueman-manager", "blueberry", "overskride"},
        "ids": {"blueman-manager", "io.github.kaii_lb.Overskride", "kcm_bluetooth", "gnome-bluetooth-panel"},
    },
    "volumeMixer": {
        "categories": {"Mixer"},
        "mimes": set(),
        "bins": {"pavucontrol", "pavucontrol-qt", "helvum", "qpwgraph", "pwvucontrol"},
        "ids": {
            "org.pulseaudio.pavucontrol", "pavucontrol", "pavucontrol-qt",
            "org.pipewire.Helvum", "org.rncbc.qpwgraph", "com.saivert.pwvucontrol",
        },
    },
    "taskManager": {
        "categories": set(),
        "mimes": set(),
        "bins": {"missioncenter", "resources", "plasma-systemmonitor", "gnome-system-monitor", "ksysguard", "btop", "htop"},
        "ids": {
            "io.missioncenter.MissionCenter", "missioncenter",
            "net.nokyan.Resources", "org.kde.plasma-systemmonitor",
            "org.gnome.SystemMonitor", "btop", "htop",
        },
    },
}

FIELD_CODE_RE = re.compile(r"^%[fFuUdDnNickvm]$")


def _search_path() -> str:
    return os.environ.get("ALIS_DEFAULT_APPS_PATH") or os.environ.get("PATH") or "/usr/local/bin:/usr/bin:/bin"


def _which(cmd: str) -> str | None:
    if not cmd:
        return None
    if "/" in cmd:
        p = Path(cmd)
        return str(p) if p.is_file() and os.access(p, os.X_OK) else None
    return shutil.which(cmd, path=_search_path())


def _clean_exec_tokens(exec_line: str) -> list[str]:
    if not exec_line:
        return []
    try:
        tokens = shlex.split(exec_line)
    except ValueError:
        tokens = exec_line.split()
    cleaned = []
    skip_next = False
    for idx, tok in enumerate(tokens):
        if skip_next:
            skip_next = False
            continue
        if idx == 0 and tok == "env":
            continue
        if idx > 0 and "=" in tok and not tok.startswith("-") and not cleaned:
            continue
        if FIELD_CODE_RE.match(tok):
            continue
        # Strip embedded field codes like --uri=%U
        tok = re.sub(r"%[fFuUdDnNickvm]", "", tok).strip()
        if tok:
            cleaned.append(tok)
    return cleaned


def _parse_flatpak_exec(tokens: list[str], desktop_id: str, x_flatpak: str) -> tuple[str, str]:
    """Return (app_id, installation_hint) from a Flatpak Exec line or metadata."""
    app_id = (x_flatpak or "").strip()
    inst_hint = ""
    if tokens and os.path.basename(tokens[0]) == "flatpak" and len(tokens) >= 2 and tokens[1] == "run":
        for tok in tokens[2:]:
            if tok == "--user":
                inst_hint = "user"
            elif tok == "--system":
                inst_hint = "system"
            elif tok.startswith("-"):
                continue
            else:
                if not app_id:
                    app_id = tok
                break
    if not app_id and desktop_id.endswith(".desktop"):
        stem = desktop_id[:-8]
        if stem.count(".") >= 2:
            app_id = stem
    return app_id, inst_hint


def _query_flatpak_inventory() -> tuple[dict[tuple[str, str], dict], bool]:
    """Return ({(installation, app_id): info}, flatpak_cli_available)."""
    if os.environ.get("ALIS_DEFAULT_APPS_DISABLE_FLATPAK_CLI") == "1":
        return {}, False
    override_json = os.environ.get("ALIS_DEFAULT_APPS_FLATPAK_LIST_JSON")
    if override_json:
        try:
            items = json.loads(Path(override_json).read_text(encoding="utf-8"))
            inv = {}
            for item in items:
                app_id = str(item.get("appId") or item.get("application") or "").strip()
                inst = str(item.get("installation") or "system").strip().lower()
                if inst not in ("user", "system"):
                    inst = "user" if "user" in inst else "system"
                if app_id:
                    inv[(inst, app_id)] = {
                        "appId": app_id,
                        "installation": inst,
                        "origin": str(item.get("origin") or "").strip(),
                        "branch": str(item.get("branch") or "stable").strip(),
                        "name": str(item.get("name") or "").strip(),
                    }
            return inv, True
        except Exception:
            return {}, False

    flatpak_bin = _which("flatpak")
    if not flatpak_bin:
        return {}, False
    try:
        proc = subprocess.run(
            [flatpak_bin, "list", "--app", "--columns=application,installation,origin,branch,name"],
            text=True,
            capture_output=True,
            timeout=3,
            check=False,
        )
        if proc.returncode != 0:
            return {}, True
        inv: dict[tuple[str, str], dict] = {}
        for raw_line in proc.stdout.splitlines():
            line = raw_line.strip()
            if not line:
                continue
            parts = raw_line.split("\t")
            if len(parts) < 2:
                parts = line.split(None, 4)
            if not parts:
                continue
            app_id = parts[0].strip()
            inst_raw = (parts[1].strip().lower() if len(parts) > 1 else "system")
            inst = "user" if "user" in inst_raw else "system"
            origin = parts[2].strip() if len(parts) > 2 else ""
            branch = parts[3].strip() if len(parts) > 3 else "stable"
            name = parts[4].strip() if len(parts) > 4 else ""
            inv[(inst, app_id)] = {
                "appId": app_id,
                "installation": inst,
                "origin": origin,
                "branch": branch,
                "name": name,
            }
        return inv, True
    except Exception:
        return {}, True


def _read_flatpak_origin_from_disk(flatpak_root: Path, app_id: str) -> tuple[bool, str]:
    """Check if <flatpak_root> has <app_id> installed and read its origin remote if available."""
    if not flatpak_root or not app_id:
        return False, ""
    export_bin = flatpak_root / "exports" / "bin" / app_id
    app_dir = flatpak_root / "app" / app_id
    installed = export_bin.exists() or app_dir.exists()
    origin = ""
    for candidate in [
        app_dir / "current" / "active" / "origin",
        app_dir / "x86_64" / "stable" / "active" / "origin",
    ]:
        if candidate.is_file():
            try:
                origin = candidate.read_text(encoding="utf-8", errors="ignore").strip()
                if origin:
                    installed = True
                    break
            except Exception:
                pass
    if not origin and (app_dir / "current" / "active" / "deploy").is_file():
        installed = True
        try:
            raw = (app_dir / "current" / "active" / "deploy").read_bytes()
            text = raw.decode("utf-8", errors="ignore")
            for candidate_remote in ("flathub", "fedora", "gnome-nightly", "kdeapps"):
                if candidate_remote in text.lower():
                    origin = candidate_remote
                    break
        except Exception:
            pass
    return installed, origin


def _candidate_application_dirs() -> list[tuple[Path, str, str, Path | None]]:
    """Return list of (applications_dir, source_kind, installation, flatpak_root)."""
    override = os.environ.get("ALIS_DEFAULT_APPS_XDG_DIRS")
    user_fp_override = os.environ.get("ALIS_DEFAULT_APPS_USER_FLATPAK_DIR")
    sys_fp_override = os.environ.get("ALIS_DEFAULT_APPS_SYSTEM_FLATPAK_DIR")

    result: list[tuple[Path, str, str, Path | None]] = []
    if override is not None:
        for idx, raw in enumerate(override.split(":")):
            raw = raw.strip()
            if not raw:
                continue
            p = Path(raw)
            apps_dir = p / "applications" if (p / "applications").is_dir() else p
            inst = "user" if idx == 0 else "system"
            result.append((apps_dir, "native", inst, None))
        if user_fp_override:
            ufp = Path(user_fp_override)
            apps_dir = ufp / "exports" / "share" / "applications" if (ufp / "exports" / "share" / "applications").is_dir() else ufp
            result.append((apps_dir, "flatpak", "user", ufp))
        if sys_fp_override:
            sfp = Path(sys_fp_override)
            apps_dir = sfp / "exports" / "share" / "applications" if (sfp / "exports" / "share" / "applications").is_dir() else sfp
            result.append((apps_dir, "flatpak", "system", sfp))
        return result

    xdg_data_home = Path(os.environ.get("XDG_DATA_HOME") or (Path.home() / ".local" / "share"))
    user_fp_root = Path(user_fp_override) if user_fp_override else (xdg_data_home / "flatpak")
    sys_fp_root = Path(sys_fp_override) if sys_fp_override else Path("/var/lib/flatpak")

    result.append((xdg_data_home / "applications", "native", "user", None))
    result.append((user_fp_root / "exports" / "share" / "applications", "flatpak", "user", user_fp_root))
    result.append((sys_fp_root / "exports" / "share" / "applications", "flatpak", "system", sys_fp_root))

    xdg_data_dirs = os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"
    seen_dirs = {str(d[0]) for d in result}
    for raw in xdg_data_dirs.split(":"):
        raw = raw.strip()
        if not raw:
            continue
        base = Path(raw)
        apps_dir = base / "applications"
        if str(apps_dir) in seen_dirs:
            continue
        seen_dirs.add(str(apps_dir))
        if "flatpak/exports" in str(apps_dir):
            inst = "user" if str(Path.home()) in str(apps_dir) else "system"
            fp_root = user_fp_root if inst == "user" else sys_fp_root
            result.append((apps_dir, "flatpak", inst, fp_root))
        else:
            result.append((apps_dir, "native", "system", None))
    return result


def _classify_slots(desktop_id: str, app_id: str, exec_bin: str, categories: set[str], mimes: set[str], exec_str: str) -> list[str]:
    slots = []
    stem = desktop_id[:-8] if desktop_id.endswith(".desktop") else desktop_id
    base_bin = os.path.basename(exec_bin).lower()
    for slot_id, rules in KNOWN_SLOT_KEYWORDS.items():
        matched = False
        if rules["categories"] and (categories & rules["categories"]):
            matched = True
        elif rules["mimes"] and (mimes & rules["mimes"]):
            # Do not classify browsers or file managers as text editors solely via text/plain
            if slot_id == "editor" and (("WebBrowser" in categories) or ("FileManager" in categories)):
                matched = False
            else:
                matched = True
        elif base_bin in {b.lower() for b in rules["bins"]}:
            matched = True
        elif stem.lower() in {i.lower() for i in rules["ids"]} or (app_id and app_id.lower() in {i.lower() for i in rules["ids"]}):
            matched = True
        elif slot_id in ("network", "networkEthernet") and "nmtui" in exec_str:
            matched = True
        elif slot_id == "manageUser" and ("kcm_users" in exec_str or "user-accounts" in exec_str):
            matched = True
        elif slot_id == "bluetooth" and ("kcm_bluetooth" in exec_str or "bluetooth" in exec_str.lower() and base_bin in ("kcmshell6", "gnome-control-center")):
            matched = True
        if matched:
            slots.append(slot_id)
    return slots


def _format_source_badge(is_flatpak: bool, origin: str, installation: str, duplicate_flatpak_installs: bool) -> str:
    if not is_flatpak:
        return "Native"
    orig_clean = (origin or "").strip()
    if orig_clean.lower() == "flathub":
        base = "Flatpak · Flathub"
    elif orig_clean:
        base = f"Flatpak · {orig_clean}"
    else:
        base = "Flatpak"
    if duplicate_flatpak_installs:
        inst_label = "User" if installation == "user" else "System"
        return f"{base} ({inst_label})"
    return base


def discover_applications() -> tuple[list[dict], bool]:
    fixture_path = os.environ.get("ALIS_DEFAULT_APPS_FIXTURE_JSON")
    if fixture_path and Path(fixture_path).is_file():
        data = json.loads(Path(fixture_path).read_text(encoding="utf-8"))
        if isinstance(data, dict) and "apps" in data:
            return data["apps"], bool(data.get("flatpakAvailable", True))

    flatpak_inv, flatpak_cli_ok = _query_flatpak_inventory()
    app_dirs = _candidate_application_dirs()

    raw_entries: dict[str, dict] = {}
    for apps_dir, dir_kind, dir_inst, fp_root in app_dirs:
        if not apps_dir.is_dir():
            continue
        for entry_path in sorted(apps_dir.glob("*.desktop")):
            if not entry_path.is_file():
                continue
            desktop_id = entry_path.name
            cp = configparser.ConfigParser(interpolation=None, strict=False)
            try:
                cp.read(entry_path, encoding="utf-8")
            except Exception:
                continue
            if "Desktop Entry" not in cp:
                continue
            sec = cp["Desktop Entry"]
            if sec.get("Type", "Application").strip() != "Application":
                continue
            if sec.get("Hidden", "false").strip().lower() == "true":
                continue
            if sec.get("NoDisplay", "false").strip().lower() == "true":
                continue

            name = sec.get("Name", "").strip()
            exec_raw = sec.get("Exec", "").strip()
            if not name or not exec_raw:
                continue

            try_exec = sec.get("TryExec", "").strip()
            x_flatpak = sec.get("X-Flatpak", "").strip()
            tokens = _clean_exec_tokens(exec_raw)
            if not tokens:
                continue

            is_flatpak = (
                dir_kind == "flatpak"
                or bool(x_flatpak)
                or (os.path.basename(tokens[0]) == "flatpak" and len(tokens) >= 2 and tokens[1] == "run")
            )

            if is_flatpak:
                app_id, inst_hint = _parse_flatpak_exec(tokens, desktop_id, x_flatpak)
                installation = inst_hint or (dir_inst if dir_kind == "flatpak" else "system")
                if not app_id:
                    continue
                fp_meta = flatpak_inv.get((installation, app_id)) or flatpak_inv.get(("user", app_id)) or flatpak_inv.get(("system", app_id))
                disk_ok, disk_origin = _read_flatpak_origin_from_disk(fp_root, app_id) if fp_root else (False, "")
                if fp_meta is None and not disk_ok:
                    # Stale or uninstalled Flatpak desktop file
                    continue
                if fp_meta is not None and not inst_hint and dir_kind != "flatpak":
                    installation = fp_meta["installation"]
                origin = (fp_meta.get("origin") if fp_meta else "") or disk_origin
                identity_key = f"flatpak:{installation}:{app_id}"
                if identity_key in raw_entries:
                    continue
                launch_cmd = f"flatpak run --user {app_id}" if installation == "user" else f"flatpak run {app_id}"
                exec_bin = app_id
            else:
                check_bin = try_exec or tokens[0]
                resolved_bin = _which(check_bin)
                if not resolved_bin:
                    # Stale native desktop file whose binary is not installed
                    continue
                app_id = ""
                installation = "native"
                origin = ""
                identity_key = f"native:{desktop_id}"
                if identity_key in raw_entries:
                    continue
                launch_cmd = " ".join(shlex.quote(t) if " " in t else t for t in tokens)
                exec_bin = tokens[0]

            categories = {c.strip() for c in sec.get("Categories", "").split(";") if c.strip()}
            mimes = {m.strip() for m in sec.get("MimeType", "").split(";") if m.strip()}
            slots = _classify_slots(desktop_id, app_id, exec_bin, categories, mimes, launch_cmd)
            is_terminal_app = sec.get("Terminal", "false").strip().lower() == "true"

            raw_entries[identity_key] = {
                "identityKey": identity_key,
                "desktopId": desktop_id,
                "appId": app_id,
                "name": name,
                "genericName": sec.get("GenericName", "").strip(),
                "comment": sec.get("Comment", "").strip(),
                "icon": sec.get("Icon", "").strip() or "application-x-executable",
                "exec": launch_cmd,
                "execBin": os.path.basename(tokens[0]),
                "isFlatpak": is_flatpak,
                "terminal": is_terminal_app,
                "installation": installation,
                "origin": origin,
                "categories": sorted(categories),
                "mimeTypes": sorted(mimes),
                "slots": slots,
                "installed": True,
            }

    # Count Flatpak appIds across user/system installations to disambiguate badges if needed
    fp_counts: dict[str, int] = {}
    for item in raw_entries.values():
        if item["isFlatpak"] and item["appId"]:
            fp_counts[item["appId"]] = fp_counts.get(item["appId"], 0) + 1

    apps = []
    for item in raw_entries.values():
        dup_fp = item["isFlatpak"] and fp_counts.get(item["appId"], 0) > 1
        item["sourceBadge"] = _format_source_badge(
            item["isFlatpak"], item["origin"], item["installation"], dup_fp
        )
        apps.append(item)

    apps.sort(key=lambda a: (a["name"].lower(), 1 if a["isFlatpak"] else 0, a["installation"], a["desktopId"]))
    return apps, flatpak_cli_ok


def _run_query(cmd: list[str]) -> tuple[int, str]:
    bin_path = _which(cmd[0])
    if not bin_path:
        return 127, ""
    try:
        proc = subprocess.run([bin_path] + cmd[1:], text=True, capture_output=True, timeout=3, check=False)
        return proc.returncode, proc.stdout.strip()
    except Exception as exc:
        return 1, str(exc)


def query_xdg_defaults() -> dict:
    xdg_settings_ok = _which("xdg-settings") is not None
    xdg_mime_ok = _which("xdg-mime") is not None

    _, web_browser = _run_query(["xdg-settings", "get", "default-web-browser"]) if xdg_settings_ok else (127, "")
    _, http_handler = _run_query(["xdg-mime", "query", "default", "x-scheme-handler/http"]) if xdg_mime_ok else (127, "")
    _, https_handler = _run_query(["xdg-mime", "query", "default", "x-scheme-handler/https"]) if xdg_mime_ok else (127, "")
    _, html_handler = _run_query(["xdg-mime", "query", "default", "text/html"]) if xdg_mime_ok else (127, "")
    _, dir_handler = _run_query(["xdg-mime", "query", "default", "inode/directory"]) if xdg_mime_ok else (127, "")
    _, text_handler = _run_query(["xdg-mime", "query", "default", "text/plain"]) if xdg_mime_ok else (127, "")

    browser_vals = [v for v in (web_browser, http_handler, https_handler, html_handler) if v]
    browser_effective = web_browser or http_handler or https_handler or html_handler
    browser_consistent = len(set(browser_vals)) <= 1 if browser_vals else False

    return {
        "toolsAvailable": {
            "xdgSettings": xdg_settings_ok,
            "xdgMime": xdg_mime_ok,
        },
        "browser": {
            "defaultWebBrowser": web_browser,
            "http": http_handler,
            "https": https_handler,
            "html": html_handler,
            "effectiveDesktopId": browser_effective,
            "consistent": browser_consistent,
        },
        "fileManager": {
            "inodeDirectory": dir_handler,
            "effectiveDesktopId": dir_handler,
            "consistent": bool(dir_handler),
        },
        "editor": {
            "textPlain": text_handler,
            "effectiveDesktopId": text_handler,
            "consistent": bool(text_handler),
        },
    }


def apply_xdg_default(slot_id: str, desktop_id: str) -> dict:
    desktop_id = (desktop_id or "").strip()
    if not desktop_id or "/" in desktop_id or not desktop_id.endswith(".desktop") or not re.match(r"^[A-Za-z0-9_.\-]+\.desktop$", desktop_id):
        return {
            "ok": False,
            "slotId": slot_id,
            "desktopId": desktop_id,
            "error": f"Invalid desktop entry ID: {desktop_id!r}",
        }

    apps, _ = discover_applications()
    matched = [a for a in apps if a.get("desktopId") == desktop_id and a.get("installed", True)]
    if not matched:
        return {
            "ok": False,
            "slotId": slot_id,
            "desktopId": desktop_id,
            "error": f"Desktop entry {desktop_id!r} is not installed",
        }

    xdg_settings_bin = _which("xdg-settings")
    xdg_mime_bin = _which("xdg-mime")
    errors = []

    if slot_id == "browser":
        if not xdg_settings_bin and not xdg_mime_bin:
            return {"ok": False, "slotId": slot_id, "desktopId": desktop_id, "error": "Neither xdg-settings nor xdg-mime is available"}
        if xdg_settings_bin:
            rc, out = _run_query(["xdg-settings", "set", "default-web-browser", desktop_id])
            if rc != 0:
                errors.append(f"xdg-settings set default-web-browser failed (exit {rc})")
        if xdg_mime_bin:
            for mime in ("x-scheme-handler/http", "x-scheme-handler/https", "text/html"):
                rc, out = _run_query(["xdg-mime", "default", desktop_id, mime])
                if rc != 0:
                    errors.append(f"xdg-mime default {mime} failed (exit {rc})")
    elif slot_id == "fileManager":
        if not xdg_mime_bin:
            return {"ok": False, "slotId": slot_id, "desktopId": desktop_id, "error": "xdg-mime is not available"}
        rc, _ = _run_query(["xdg-mime", "default", desktop_id, "inode/directory"])
        if rc != 0:
            errors.append(f"xdg-mime default inode/directory failed (exit {rc})")
    elif slot_id == "editor":
        if not xdg_mime_bin:
            return {"ok": False, "slotId": slot_id, "desktopId": desktop_id, "error": "xdg-mime is not available"}
        rc, _ = _run_query(["xdg-mime", "default", desktop_id, "text/plain"])
        if rc != 0:
            errors.append(f"xdg-mime default text/plain failed (exit {rc})")
    else:
        return {"ok": False, "slotId": slot_id, "desktopId": desktop_id, "error": f"Slot {slot_id!r} does not have a system XDG MIME association"}

    readback = query_xdg_defaults().get(slot_id, {})
    effective = readback.get("effectiveDesktopId", "")
    if slot_id == "browser":
        expected_checks = []
        if xdg_settings_bin:
            expected_checks.append(readback.get("defaultWebBrowser") == desktop_id)
        if xdg_mime_bin:
            expected_checks.extend([
                readback.get("http") == desktop_id,
                readback.get("https") == desktop_id,
                readback.get("html") == desktop_id,
            ])
        verified = bool(expected_checks) and all(expected_checks)
    else:
        verified = effective == desktop_id

    if errors or not verified:
        reason = "; ".join(errors) if errors else f"Readback mismatch (got {effective!r}, expected {desktop_id!r})"
        return {
            "ok": False,
            "slotId": slot_id,
            "desktopId": desktop_id,
            "readback": readback,
            "error": reason,
        }

    return {
        "ok": True,
        "slotId": slot_id,
        "desktopId": desktop_id,
        "readback": readback,
        "message": f"Synced system default to {desktop_id}",
    }


def check_command_availability(command_str: str, apps: list[dict] | None = None) -> dict:
    command_str = (command_str or "").strip()
    if not command_str:
        return {"valid": False, "executable": "", "reason": "Empty command"}
    try:
        tokens = shlex.split(command_str)
    except ValueError as exc:
        return {"valid": False, "executable": "", "reason": f"Invalid quoting: {exc}"}
    if not tokens:
        return {"valid": False, "executable": "", "reason": "Empty command"}

    if apps is None:
        apps, _ = discover_applications()

    if os.path.basename(tokens[0]) == "flatpak" and len(tokens) >= 3 and tokens[1] == "run":
        app_id = ""
        inst = ""
        for tok in tokens[2:]:
            if tok == "--user":
                inst = "user"
            elif tok == "--system":
                inst = "system"
            elif not tok.startswith("-"):
                app_id = tok
                break
        if app_id:
            for app in apps:
                if app.get("isFlatpak") and app.get("appId") == app_id and (not inst or app.get("installation") == inst):
                    return {"valid": True, "executable": f"flatpak:{app_id}", "reason": "Installed Flatpak app"}
        return {"valid": False, "executable": app_id or "flatpak", "reason": f"Flatpak app {app_id!r} is not installed"}

    resolved = _which(tokens[0])
    if resolved:
        return {"valid": True, "executable": resolved, "reason": "Executable found"}

    for app in apps:
        if app.get("desktopId") == command_str or app.get("appId") == command_str or app.get("execBin") == tokens[0]:
            return {"valid": True, "executable": app.get("exec", ""), "reason": "Matched discovered desktop entry"}

    return {"valid": False, "executable": tokens[0], "reason": f"Executable {tokens[0]!r} not found"}


TUI_APP_BINS = {
    "yazi", "ranger", "lf", "nnn", "vifm", "mc",
    "nvim", "vim", "vi", "nano", "hx", "helix", "micro", "kak",
    "btop", "htop", "top", "nvtop", "nmtui", "pulsemixer", "alsamixer",
}

APP_ID_ALIASES = {
    "zen": {"app.zen_browser.zen", "zen", "zen-browser", "zen-alpha", "zen-beta"},
    "app.zen_browser.zen": {"app.zen_browser.zen", "zen", "zen-browser", "zen-alpha", "zen-beta"},
    "zen-browser": {"app.zen_browser.zen", "zen", "zen-browser", "zen-alpha", "zen-beta"},
    "firefox": {"firefox", "org.mozilla.firefox", "firefox-esr", "firefox-developer-edition"},
    "org.mozilla.firefox": {"firefox", "org.mozilla.firefox", "firefox-esr", "firefox-developer-edition"},
    "librewolf": {"librewolf", "io.gitlab.librewolf-community"},
    "chromium": {"chromium", "org.chromium.chromium", "chromium-browser"},
    "google-chrome": {"google-chrome", "google-chrome-stable", "com.google.chrome"},
    "google-chrome-stable": {"google-chrome", "google-chrome-stable", "com.google.chrome"},
    "brave": {"brave", "brave-browser", "com.brave.browser"},
    "brave-browser": {"brave", "brave-browser", "com.brave.browser"},
    "code": {"code", "code-oss", "com.visualstudio.code"},
    "codium": {"codium", "vscodium", "com.vscodium.codium"},
    "zed": {"zed", "zeditor", "dev.zed.zed"},
    "zeditor": {"zed", "zeditor", "dev.zed.zed"},
    "nautilus": {"nautilus", "org.gnome.nautilus"},
    "dolphin": {"dolphin", "org.kde.dolphin"},
    "thunar": {"thunar", "org.xfce.thunar"},
    "kitty": {"kitty"},
    "foot": {"foot", "footclient"},
    "ghostty": {"ghostty", "com.mitchellh.ghostty"},
    "alacritty": {"alacritty"},
    "wezterm": {"wezterm", "org.wezfurlong.wezterm"},
    "konsole": {"konsole", "org.kde.konsole"},
}


def _strip_new_flag(extra_args: list[str]) -> tuple[bool, list[str]]:
    if extra_args and extra_args[0] == "--new":
        return True, list(extra_args[1:])
    return False, list(extra_args)


def _apply_force_new_flags(slot_id: str, base_argv: list[str], target_app: dict | None, is_tui: bool) -> list[str]:
    if not base_argv or is_tui:
        return list(base_argv)
    argv = list(base_argv)
    exec_bin = os.path.basename(argv[0]).lower()
    if exec_bin == "flatpak" and len(argv) >= 3:
        for tok in argv[2:]:
            if not tok.startswith("-"):
                exec_bin = tok.lower()
                break
    app_id = str((target_app or {}).get("appId") or "").strip().lower()
    ident = app_id or exec_bin

    if slot_id == "browser":
        if exec_bin != "xdg-open" and "--new-window" not in argv:
            argv.append("--new-window")
    elif slot_id == "fileManager":
        if any(k in ident for k in ("nautilus", "dolphin", "cosmic")) and "--new-window" not in argv:
            argv.append("--new-window")
    elif slot_id == "editor":
        if any(k in ident for k in ("code", "codium", "zed", "subl")):
            if not any(f in argv for f in ("-n", "--new-window", "--new")):
                argv.append("-n")
        elif any(k in ident for k in ("text-editor", "texteditor", "gedit", "kate")):
            if "--new-window" not in argv:
                argv.append("--new-window")
    return argv


def _resolve_slot_details(slot_id: str, config_path: str, extra_args: list[str]) -> tuple[list[str], dict | None, bool, str]:
    """Return (argv, target_app, is_tui, tui_bin)."""
    force_new, clean_extra = _strip_new_flag(extra_args)

    cfg = {}
    if config_path and Path(config_path).is_file():
        try:
            cfg = json.loads(Path(config_path).read_text(encoding="utf-8"))
        except Exception:
            cfg = {}

    apps_cfg = cfg.get("apps") if isinstance(cfg.get("apps"), dict) else {}
    desktop_ids = apps_cfg.get("desktopIds") if isinstance(apps_cfg.get("desktopIds"), dict) else {}

    configured_desktop_id = str(desktop_ids.get(slot_id) or "").strip()
    configured_cmd = str(apps_cfg.get(slot_id) or "").strip()
    if slot_id == "fileManager" and not configured_cmd:
        configured_cmd = str(apps_cfg.get("fileExplorer") or "").strip()

    discovered, _ = discover_applications()

    # 1. Try explicit identityKey or desktopId match
    target_app = None
    if configured_desktop_id:
        for app in discovered:
            if app["identityKey"] == configured_desktop_id or app["desktopId"] == configured_desktop_id:
                target_app = app
                break

    # 2. Try matching configured_cmd against discovered apps if it's a flatpak run or single token
    if target_app is None and configured_cmd:
        for app in discovered:
            if app["exec"] == configured_cmd or app["desktopId"] == configured_cmd or (app["appId"] and app["appId"] == configured_cmd):
                target_app = app
                break

    base_argv: list[str] = []
    if target_app is not None:
        base_argv = shlex.split(target_app["exec"])
    elif configured_cmd:
        chk = check_command_availability(configured_cmd, discovered)
        if chk.get("valid"):
            base_argv = shlex.split(configured_cmd)
    else:
        for fb in SLOT_FALLBACKS.get(slot_id, []):
            chk = check_command_availability(fb, discovered)
            if chk.get("valid"):
                base_argv = shlex.split(fb)
                if fb == "xdg-open" and slot_id == "browser" and not clean_extra:
                    return base_argv + ["https://"], None, False, ""
                if fb == "xdg-open" and slot_id == "fileManager" and not clean_extra:
                    return base_argv + [str(Path.home())], None, False, ""
                break

    if not base_argv:
        # Final fallback chain if configured_cmd was invalid
        for fb in SLOT_FALLBACKS.get(slot_id, []):
            chk = check_command_availability(fb, discovered)
            if chk.get("valid"):
                base_argv = shlex.split(fb)
                if fb == "xdg-open" and slot_id == "browser" and not clean_extra:
                    return base_argv + ["https://"], None, False, ""
                if fb == "xdg-open" and slot_id == "fileManager" and not clean_extra:
                    return base_argv + [str(Path.home())], None, False, ""
                break

    if not base_argv:
        return [], None, False, ""

    first_bin = os.path.basename(base_argv[0]).lower()
    is_tui = False
    tui_bin = ""
    if slot_id != "terminal":
        if (target_app and target_app.get("terminal")) or first_bin in TUI_APP_BINS:
            is_tui = True
            tui_bin = first_bin
            term_argv, _, _, _ = _resolve_slot_details("terminal", config_path, [])
            if not term_argv:
                term_argv = ["kitty"]
            return term_argv + ["-e"] + base_argv + clean_extra, target_app, True, tui_bin
    else:
        # Check if terminal is being invoked with a TUI app argument (e.g. `alis terminal yazi` or `alis terminal -e yazi`)
        if clean_extra:
            if len(clean_extra) >= 2 and clean_extra[0] == "-e":
                cand = os.path.basename(clean_extra[1]).lower()
                if cand:
                    is_tui = True
                    tui_bin = cand
            elif len(clean_extra) == 1 and not clean_extra[0].startswith("-"):
                cand = os.path.basename(clean_extra[0]).lower()
                if cand:
                    is_tui = True
                    tui_bin = cand

    if force_new:
        base_argv = _apply_force_new_flags(slot_id, base_argv, target_app, is_tui)

    return base_argv + clean_extra, target_app, is_tui, tui_bin


def resolve_launch_argv(slot_id: str, config_path: str, extra_args: list[str]) -> list[str]:
    argv, _, _, _ = _resolve_slot_details(slot_id, config_path, extra_args)
    return argv


def _pid_has_descendant_comm(root_pid: int | None, target_comm: str, window_obj: dict | None = None) -> bool:
    target = (target_comm or "").strip().lower()
    if not target:
        return False
    if isinstance(window_obj, dict) and isinstance(window_obj.get("mock_children_comms"), list):
        return target in {str(c).strip().lower() for c in window_obj["mock_children_comms"]}
    if not root_pid or int(root_pid) <= 0:
        return False
    queue = [int(root_pid)]
    visited: set[int] = set()
    while queue and len(visited) < 64:
        pid = queue.pop(0)
        if pid in visited:
            continue
        visited.add(pid)
        proc_dir = Path(f"/proc/{pid}")
        if not proc_dir.is_dir():
            continue
        if pid != int(root_pid):
            try:
                comm = (proc_dir / "comm").read_text(encoding="utf-8", errors="ignore").strip().lower()
                if comm == target:
                    return True
            except Exception:
                pass
            try:
                cmdline_raw = (proc_dir / "cmdline").read_bytes()
                parts = [p.decode("utf-8", errors="ignore") for p in cmdline_raw.split(b"\0") if p]
                if parts and os.path.basename(parts[0]).lower() == target:
                    return True
            except Exception:
                pass
        try:
            for children_file in (proc_dir / "task").glob("*/children"):
                for tok in children_file.read_text(encoding="utf-8", errors="ignore").split():
                    if tok.isdigit():
                        cpid = int(tok)
                        if cpid not in visited:
                            queue.append(cpid)
        except Exception:
            pass
    return False


def _query_niri_windows() -> list[dict]:
    override = os.environ.get("ALIS_DEFAULT_APPS_WINDOWS_JSON")
    if override:
        try:
            p = Path(override)
            raw = p.read_text(encoding="utf-8") if p.is_file() else override
            data = json.loads(raw)
            return data if isinstance(data, list) else []
        except Exception:
            return []
    if os.environ.get("ALIS_LAUNCH_DRY_RUN") == "1":
        return []
    niri_bin = _which("niri") or shutil.which("niri")
    if not niri_bin:
        return []
    try:
        proc = subprocess.run(
            [niri_bin, "msg", "-j", "windows"],
            text=True,
            capture_output=True,
            timeout=1.5,
            check=False,
        )
        if proc.returncode != 0 or not proc.stdout.strip():
            return []
        data = json.loads(proc.stdout)
        return data if isinstance(data, list) else []
    except Exception:
        return []


def _focus_niri_window(window_id: int) -> bool:
    focus_log = os.environ.get("ALIS_DEFAULT_APPS_FOCUS_LOG")
    if focus_log:
        try:
            Path(focus_log).write_text(str(window_id), encoding="utf-8")
            return True
        except Exception:
            return False
    if os.environ.get("ALIS_LAUNCH_DRY_RUN") == "1":
        return True
    niri_bin = _which("niri") or shutil.which("niri")
    if not niri_bin:
        return False
    try:
        proc = subprocess.run(
            [niri_bin, "msg", "action", "focus-window", "--id", str(window_id)],
            text=True,
            capture_output=True,
            timeout=1.5,
            check=False,
        )
        return proc.returncode == 0
    except Exception:
        return False


def _candidate_window_app_ids(base_argv: list[str], target_app: dict | None) -> set[str]:
    cands: set[str] = set()
    if target_app:
        app_id = str(target_app.get("appId") or "").strip().lower()
        desktop_id = str(target_app.get("desktopId") or "").strip()
        stem = (desktop_id[:-8] if desktop_id.endswith(".desktop") else desktop_id).strip().lower()
        exec_bin = str(target_app.get("execBin") or "").strip().lower()
        for k in (app_id, stem, exec_bin):
            if k:
                cands.add(k)
                cands.update(APP_ID_ALIASES.get(k, set()))
    if base_argv:
        first_bin = os.path.basename(base_argv[0]).lower()
        if first_bin == "flatpak":
            for tok in base_argv[2:]:
                if not tok.startswith("-"):
                    first_bin = tok.lower()
                    break
        if first_bin and first_bin != "xdg-open":
            cands.add(first_bin)
            cands.update(APP_ID_ALIASES.get(first_bin, set()))
    return cands


def focus_or_launch(slot_id: str, config_path: str, extra_args: list[str]) -> dict:
    force_new, clean_extra = _strip_new_flag(extra_args)
    argv, target_app, is_tui, tui_bin = _resolve_slot_details(slot_id, config_path, extra_args)
    if not argv:
        return {"ok": False, "action": "none", "argv": []}

    # Determine if we should attempt to focus an existing open window
    can_focus = not force_new
    if slot_id == "terminal":
        if clean_extra and not is_tui:
            can_focus = False
    else:
        if clean_extra:
            can_focus = False

    if can_focus:
        windows = _query_niri_windows()
        if windows:
            matches = []
            if is_tui and tui_bin:
                for w in windows:
                    w_app = str(w.get("app_id") or "").strip().lower()
                    w_title = str(w.get("title") or "").strip().lower()
                    w_pid = w.get("pid")
                    if (
                        w_app == tui_bin
                        or _pid_has_descendant_comm(w_pid, tui_bin, w)
                        or w_title == tui_bin
                        or w_title.startswith(f"{tui_bin} ")
                        or w_title.endswith(f" - {tui_bin}")
                    ):
                        matches.append(w)
            else:
                cand_ids = _candidate_window_app_ids(argv, target_app)
                for w in windows:
                    w_app = str(w.get("app_id") or "").strip().lower()
                    if not w_app:
                        continue
                    matched_app = (
                        w_app in cand_ids
                        or any(w_app.endswith("." + cid) or cid.endswith("." + w_app) for cid in cand_ids if len(cid) > 2)
                    )
                    if not matched_app:
                        continue
                    # For plain terminal shortcut (Mod+T), ignore terminal windows dedicated to a TUI file manager (e.g. yazi)
                    if slot_id == "terminal":
                        w_pid = w.get("pid")
                        w_title = str(w.get("title") or "").strip().lower()
                        if any(
                            _pid_has_descendant_comm(w_pid, fm_tui, w)
                            or w_title == fm_tui
                            or w_title.startswith(f"{fm_tui} ")
                            for fm_tui in ("yazi", "ranger", "lf")
                        ):
                            continue
                    matches.append(w)

            if matches:
                matches.sort(key=lambda w: int(w.get("id") or 0))
                focused_indices = [i for i, w in enumerate(matches) if w.get("is_focused") is True]
                if focused_indices and len(matches) > 1:
                    chosen = matches[(focused_indices[0] + 1) % len(matches)]
                elif focused_indices:
                    chosen = matches[focused_indices[0]]
                else:
                    def _ts_key(w: dict) -> tuple[int, int, int]:
                        ts = w.get("focus_timestamp") if isinstance(w.get("focus_timestamp"), dict) else {}
                        return (
                            int(ts.get("secs") or 0),
                            int(ts.get("nanos") or 0),
                            int(w.get("id") or 0),
                        )
                    chosen = max(matches, key=_ts_key)
                wid = int(chosen.get("id") or 0)
                if wid > 0 and _focus_niri_window(wid):
                    return {
                        "ok": True,
                        "action": "focused",
                        "windowId": wid,
                        "argv": argv,
                    }

    return {
        "ok": True,
        "action": "launch",
        "argv": argv,
    }


def main() -> int:
    cmd = sys.argv[1] if len(sys.argv) > 1 else "discover"
    if cmd == "discover":
        apps, fp_cli = discover_applications()
        xdg = query_xdg_defaults()
        out = {
            "apps": apps,
            "xdgDefaults": xdg,
            "toolsAvailable": {
                "flatpak": fp_cli,
                "xdgSettings": xdg["toolsAvailable"]["xdgSettings"],
                "xdgMime": xdg["toolsAvailable"]["xdgMime"],
            },
        }
        print(json.dumps(out))
        return 0
    if cmd == "status":
        print(json.dumps(query_xdg_defaults()))
        return 0
    if cmd == "check-command":
        target = sys.argv[2] if len(sys.argv) > 2 else ""
        print(json.dumps(check_command_availability(target)))
        return 0
    if cmd == "apply-xdg":
        slot_id = sys.argv[2] if len(sys.argv) > 2 else ""
        desktop_id = sys.argv[3] if len(sys.argv) > 3 else ""
        res = apply_xdg_default(slot_id, desktop_id)
        print(json.dumps(res))
        return 0 if res.get("ok") else 1
    if cmd == "resolve-launch":
        slot_id = sys.argv[2] if len(sys.argv) > 2 else "terminal"
        config_path = sys.argv[3] if len(sys.argv) > 3 else ""
        extra = sys.argv[4:]
        if extra and extra[0] == "--":
            extra = extra[1:]
        argv = resolve_launch_argv(slot_id, config_path, extra)
        print(json.dumps({"ok": bool(argv), "argv": argv}))
        return 0 if argv else 1
    if cmd == "focus-or-launch":
        slot_id = sys.argv[2] if len(sys.argv) > 2 else "terminal"
        config_path = sys.argv[3] if len(sys.argv) > 3 else ""
        extra = sys.argv[4:]
        if extra and extra[0] == "--":
            extra = extra[1:]
        res = focus_or_launch(slot_id, config_path, extra)
        print(json.dumps(res))
        return 0 if res.get("ok") else 1
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
