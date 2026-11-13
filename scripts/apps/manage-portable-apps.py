#!/usr/bin/env python3
"""Manage portable applications (.AppImage, .AppImage.zsync, rsync, .tar.gz, .pkg.tar.zst) for Alis Settings.

Subcommands:
  list                              -> JSON list of managed portable applications
  pick-and-add                      -> Open native file chooser (zenity/kdialog) and install selected files
  add <path> [<path> ...]           -> Move files into managed storage, extract icon, create .desktop entry
  remove <id>                       -> Remove managed files, extracted package, icon, and .desktop entry
  check-updates [<id> ...]          -> Check for updates on supported applications (zsync, rsync, tauri, electron-builder)
  update [<id> ...]                 -> Apply updates for specified applications (or all with available updates)
  set-update-source <id> <source>   -> Configure or override update source (zsync URL, rsync URL, gh-releases-zsync)
"""

from __future__ import annotations

import base64
import concurrent.futures
import configparser
import fnmatch
import hashlib
import http.server
import json
import os
import re
import shutil
import signal
import socketserver
import stat
import struct
import subprocess
import sys
import tarfile
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path
from typing import Any


def _data_home() -> Path:
    env = os.environ.get("ALIS_PORTABLE_APPS_DATA_HOME", "").strip()
    if env:
        return Path(env).expanduser()
    xdg = os.environ.get("XDG_DATA_HOME", "").strip()
    if xdg:
        return Path(xdg).expanduser()
    return Path.home() / ".local" / "share"


def _base_dir() -> Path:
    return _data_home() / "alis" / "applications"


def _appimages_dir() -> Path:
    return _base_dir() / "appimages"


def _archives_dir() -> Path:
    return _base_dir() / "archives"


def _packages_dir() -> Path:
    return _base_dir() / "packages"


def _icons_dir() -> Path:
    return _base_dir() / "icons"


def _desktop_dir() -> Path:
    return _data_home() / "applications"


def _registry_path() -> Path:
    return _base_dir() / "registry.json"


def _operation_status_path() -> Path:
    return _base_dir() / "operation-status.json"


def _ensure_dirs() -> None:
    for d in (_appimages_dir(), _archives_dir(), _packages_dir(), _icons_dir(), _desktop_dir()):
        d.mkdir(parents=True, exist_ok=True)


def _load_registry() -> list[dict[str, Any]]:
    path = _registry_path()
    if not path.is_file():
        return []
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(data, list):
            return [item for item in data if isinstance(item, dict)]
        if isinstance(data, dict) and isinstance(data.get("apps"), list):
            return [item for item in data["apps"] if isinstance(item, dict)]
    except Exception:
        pass
    return []


def _save_registry(apps: list[dict[str, Any]], allow_removal: bool = False) -> None:
    _ensure_dirs()
    path = _registry_path()
    merged_apps = list(apps)
    if not allow_removal and path.is_file():
        try:
            on_disk = _load_registry()
            disk_by_id = {
                str(it.get("id", "")).strip(): it
                for it in on_disk
                if isinstance(it, dict) and str(it.get("id", "")).strip()
            }
            for i, mem_it in enumerate(merged_apps):
                aid = str(mem_it.get("id", "")).strip()
                disk_it = disk_by_id.get(aid)
                if not disk_it:
                    continue
                disk_upd = int(disk_it.get("updatedAt", 0) or 0)
                mem_upd = int(mem_it.get("updatedAt", 0) or 0)
                disk_sp = str(disk_it.get("storedPath", "")).strip()
                mem_sp = str(mem_it.get("storedPath", "")).strip()
                if disk_upd > mem_upd or (
                    disk_sp
                    and mem_sp
                    and disk_sp != mem_sp
                    and Path(disk_sp).exists()
                    and not Path(mem_sp).exists()
                ):
                    merged_apps[i] = disk_it
        except Exception:
            pass
    tmp = path.with_name(f"registry.{os.getpid()}.json.tmp")
    tmp.write_text(json.dumps({"version": 1, "apps": merged_apps}, indent=2, ensure_ascii=False), encoding="utf-8")
    tmp.replace(path)


_CURRENT_OP_ACTIVE = False
_PROGRESS_PIPE_FD = -1
_PROGRESS_PIPE_BROKEN = False
_LAUNCHER_PID = 0


def _format_bytes(n: int) -> str:
    if n < 1024:
        return f"{n} B"
    if n < 1024 * 1024:
        return f"{n / 1024:.1f} KB"
    if n < 1024 * 1024 * 1024:
        return f"{n / (1024 * 1024):.1f} MB"
    return f"{n / (1024 * 1024 * 1024):.2f} GB"


def _write_operation_status(data: dict[str, Any]) -> None:
    try:
        _ensure_dirs()
        path = _operation_status_path()
        tmp = path.with_name(f"operation-status.{os.getpid()}.tmp")
        tmp.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
        tmp.replace(path)
    except Exception:
        pass


def _read_operation_status() -> dict[str, Any]:
    path = _operation_status_path()
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def _is_worker_alive(pid: int) -> bool:
    if pid <= 0 or pid == os.getpid():
        return False
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    stat_path = Path(f"/proc/{pid}/stat")
    if stat_path.is_file():
        try:
            stat_txt = stat_path.read_text(encoding="utf-8", errors="ignore")
            if ") Z " in stat_txt:
                return False
        except Exception:
            pass
    cmdline_path = Path(f"/proc/{pid}/cmdline")
    if cmdline_path.is_file():
        try:
            cmdline = cmdline_path.read_bytes().decode("utf-8", errors="ignore")
            return "manage-portable-apps.py" in cmdline
        except Exception:
            pass
    return True


def _emit_progress(
    action: str,
    percent: float | int = -1,
    detail: str = "",
    app_id: str = "",
    app_name: str = "",
    stage: str = "",
    bytes_done: int = 0,
    bytes_total: int = 0,
    include_apps: list[dict[str, Any]] | None = None,
    write_status_file: bool = True,
) -> None:
    global _CURRENT_OP_ACTIVE, _PROGRESS_PIPE_FD, _PROGRESS_PIPE_BROKEN
    pct_val = max(-1, min(100, int(round(percent)))) if percent >= 0 else -1
    now_ts = time.time()
    payload: dict[str, Any] = {
        "type": "progress",
        "action": action,
        "appId": app_id,
        "appName": app_name,
        "stage": stage,
        "percent": pct_val,
        "detail": detail,
        "bytesDone": int(bytes_done),
        "bytesTotal": int(bytes_total),
        "timestamp": now_ts,
    }
    if include_apps is not None:
        payload["apps"] = include_apps
    line_str = "ALIS_PROGRESS:" + json.dumps(payload, ensure_ascii=False) + "\n"
    if _PROGRESS_PIPE_FD >= 0:
        try:
            os.write(_PROGRESS_PIPE_FD, line_str.encode("utf-8"))
        except OSError:
            _PROGRESS_PIPE_BROKEN = True
            try:
                os.close(_PROGRESS_PIPE_FD)
            except OSError:
                pass
            _PROGRESS_PIPE_FD = -1
    else:
        try:
            sys.stderr.write(line_str)
            sys.stderr.flush()
        except OSError:
            pass
    if write_status_file:
        _CURRENT_OP_ACTIVE = True
        _write_operation_status(
            {
                "running": True,
                "pid": os.getpid(),
                "launcherPid": _LAUNCHER_PID or os.getpid(),
                "action": action,
                "appId": app_id,
                "appName": app_name,
                "stage": stage,
                "percent": pct_val,
                "detail": detail,
                "bytesDone": int(bytes_done),
                "bytesTotal": int(bytes_total),
                "updatedAt": now_ts,
            }
        )


def _complete_operation_status(action: str, result: dict[str, Any]) -> None:
    global _CURRENT_OP_ACTIVE
    _CURRENT_OP_ACTIVE = False
    _write_operation_status(
        {
            "running": False,
            "pid": os.getpid(),
            "launcherPid": _LAUNCHER_PID or os.getpid(),
            "action": action,
            "percent": 100,
            "detail": "",
            "finishedAt": time.time(),
            "unconsumedResult": bool(_PROGRESS_PIPE_BROKEN),
            "result": result,
        }
    )



ARCHIVE_SUFFIXES = (
    ".AppImage.zsync",
    ".appimage.zsync",
    ".AppImage.tar.gz",
    ".appimage.tar.gz",
    ".AppImage",
    ".appimage",
    ".pkg.tar.zst",
    ".pkg.tar.xz",
    ".pkg.tar.gz",
    ".tar.zst",
    ".tzst",
    ".tar.xz",
    ".txz",
    ".tar.bz2",
    ".tbz2",
    ".tar.gz",
    ".tgz",
    ".zip",
)


def _slugify(raw: str) -> str:
    s = raw.strip()
    for suffix in ARCHIVE_SUFFIXES:
        if s.lower().endswith(suffix.lower()):
            s = s[: -len(suffix)]
            break
    # Strip trailing version/arch noise like -1.143.17183-anylinux-x86_64 or -x64
    s = re.sub(
        r"[-_](?:v?\d+(?:\.\d+)+(?:[-._][a-zA-Z0-9]+)*|x86_64|amd64|x64|aarch64|arm64|anylinux|linux|any).*$",
        "",
        s,
        flags=re.IGNORECASE,
    )
    slug = re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")
    return slug or "app"


def _human_title(raw: str) -> str:
    s = raw.strip()
    for suffix in ARCHIVE_SUFFIXES:
        if s.lower().endswith(suffix.lower()):
            s = s[: -len(suffix)]
            break
    s = re.sub(
        r"[-_](?:v?\d+(?:\.\d+)+(?:[-._][a-zA-Z0-9]+)*|x86_64|amd64|x64|aarch64|arm64|anylinux|linux|any).*$",
        "",
        s,
        flags=re.IGNORECASE,
    )
    s = s.replace("_", " ").replace("-", " ").strip()
    return s or "Application"


def _extract_version_from_string(raw: str) -> str:
    s = raw.strip()
    for suffix in ARCHIVE_SUFFIXES + (".jar", ".zsync", ".desktop"):
        if s.lower().endswith(suffix.lower()):
            s = s[: -len(suffix)]
            break
    s = re.sub(
        r"[-_.](?:x86_64|amd64|x64|aarch64|arm64|i686|anylinux|linux|any|desktop|appimage)(?:[-_.].*)?$",
        "",
        s,
        flags=re.IGNORECASE,
    )
    if re.fullmatch(r"[vV]?\d+\.\d+(?:\.\d+)*(?:[-+._][0-9A-Za-z]+)*", s):
        return s.lstrip("vV")
    m = re.search(r"(?:^|[-_vV])(\d+\.\d+(?:\.\d+)*(?:[-+._][0-9A-Za-z]+)*)$", s)
    if m:
        return m.group(1).lstrip("vV")
    m2 = re.search(r"(\d+\.\d+(?:\.\d+)+)", s)
    return m2.group(1) if m2 else ""


def _version_tuple(raw: str) -> tuple[tuple[int, ...], int, tuple[Any, ...]]:
    v = raw.strip().lstrip("vV")
    if not v:
        return ((), 0, ())
    # Normalize +build as post-release component and -prerelease
    plus_part = ""
    if "+" in v:
        v, plus_part = v.split("+", 1)
    pre_part = ""
    if "-" in v:
        head, tail = v.split("-", 1)
        if tail.isdigit():
            # e.g. 0.4.28-2 is build/revision 2, not a pre-release
            plus_part = tail
            v = head
        else:
            v = head
            pre_part = tail
    nums: list[int] = []
    for seg in re.split(r"[^0-9]+", v):
        if seg.isdigit():
            nums.append(int(seg))
    if plus_part and plus_part.isdigit():
        nums.append(int(plus_part))
    # Pre-release sorts before final release (0 vs 1)
    is_final = 0 if pre_part else 1
    pre_tokens: list[Any] = []
    if pre_part:
        for tok in re.split(r"[._-]+", pre_part):
            pre_tokens.append((0, int(tok)) if tok.isdigit() else (1, tok.lower()))
    return (tuple(nums), is_final, tuple(pre_tokens))


def _compare_versions(v_a: str, v_b: str) -> int:
    a = v_a.strip().lstrip("vV")
    b = v_b.strip().lstrip("vV")
    if not a and not b:
        return 0
    if a == b:
        return 0
    ka = _version_tuple(a)
    kb = _version_tuple(b)
    # Pad numeric tuple lengths so 1.2 == 1.2.0 before comparing pre/post tags
    max_len = max(len(ka[0]), len(kb[0]))
    na = ka[0] + (0,) * (max_len - len(ka[0]))
    nb = kb[0] + (0,) * (max_len - len(kb[0]))
    ta = (na, ka[1], ka[2])
    tb = (nb, kb[1], kb[2])
    if ta > tb:
        return 1
    if ta < tb:
        return -1
    return 0


def _parse_zsync_bytes(raw_bytes: bytes) -> dict[str, str]:
    info: dict[str, str] = {}
    try:
        header_bytes = raw_bytes.split(b"\n\n", 1)[0]
        for line in header_bytes.decode("utf-8", errors="ignore").splitlines():
            if ":" in line:
                k, v = line.split(":", 1)
                info[k.strip().lower()] = v.strip()
    except Exception:
        pass
    return info


def _parse_zsync_header(zsync_path: Path) -> dict[str, str]:
    try:
        with zsync_path.open("rb") as f:
            head = f.read(4096)
        return _parse_zsync_bytes(head)
    except Exception:
        return {}


BOGUS_UPD_INFO_PATTERNS = (
    "linuxdeploy-plugin-appimage",
    "appimagetool",
    "appimagekit",
)


def _read_elf_upd_info(binary_path: Path) -> str:
    """Read the embedded .upd_info ELF section from an AppImage binary."""
    if not binary_path.is_file():
        return ""
    raw_info = ""
    try:
        with binary_path.open("rb") as f:
            ident = f.read(64)
            if len(ident) >= 52 and ident[:4] == b"\x7fELF":
                ei_class = ident[4]
                if ei_class == 2 and len(ident) >= 64:
                    (e_shoff,) = struct.unpack_from("<Q", ident, 40)
                    e_shentsize, e_shnum, e_shstrndx = struct.unpack_from("<HHH", ident, 58)
                    if e_shoff > 0 and 0 < e_shnum < 512 and e_shstrndx < e_shnum and e_shentsize >= 64:
                        f.seek(e_shoff + e_shstrndx * e_shentsize)
                        shstr_hdr = f.read(e_shentsize)
                        shstr_off, shstr_size = struct.unpack_from("<QQ", shstr_hdr, 24)
                        if 0 < shstr_size < 1024 * 1024:
                            f.seek(shstr_off)
                            shstrtab = f.read(shstr_size)
                            for i in range(e_shnum):
                                f.seek(e_shoff + i * e_shentsize)
                                sh = f.read(e_shentsize)
                                (sh_name,) = struct.unpack_from("<I", sh, 0)
                                end = shstrtab.find(b"\x00", sh_name)
                                name = shstrtab[sh_name:end].decode("ascii", errors="ignore") if end != -1 else ""
                                if name == ".upd_info":
                                    sh_offset, sh_size = struct.unpack_from("<QQ", sh, 24)
                                    if 0 < sh_size <= 16384:
                                        f.seek(sh_offset)
                                        data = f.read(sh_size)
                                        raw_info = data.split(b"\x00", 1)[0].decode("utf-8", errors="ignore").strip()
                                    break
                elif ei_class == 1:
                    (e_shoff,) = struct.unpack_from("<I", ident, 32)
                    e_shentsize, e_shnum, e_shstrndx = struct.unpack_from("<HHH", ident, 46)
                    if e_shoff > 0 and 0 < e_shnum < 512 and e_shstrndx < e_shnum and e_shentsize >= 40:
                        f.seek(e_shoff + e_shstrndx * e_shentsize)
                        shstr_hdr = f.read(e_shentsize)
                        shstr_off, shstr_size = struct.unpack_from("<II", shstr_hdr, 16)
                        if 0 < shstr_size < 1024 * 1024:
                            f.seek(shstr_off)
                            shstrtab = f.read(shstr_size)
                            for i in range(e_shnum):
                                f.seek(e_shoff + i * e_shentsize)
                                sh = f.read(e_shentsize)
                                (sh_name,) = struct.unpack_from("<I", sh, 0)
                                end = shstrtab.find(b"\x00", sh_name)
                                name = shstrtab[sh_name:end].decode("ascii", errors="ignore") if end != -1 else ""
                                if name == ".upd_info":
                                    sh_offset, sh_size = struct.unpack_from("<II", sh, 16)
                                    if 0 < sh_size <= 16384:
                                        f.seek(sh_offset)
                                        data = f.read(sh_size)
                                        raw_info = data.split(b"\x00", 1)[0].decode("utf-8", errors="ignore").strip()
                                    break
    except Exception:
        pass

    if not raw_info and shutil.which("readelf"):
        try:
            res = subprocess.run(
                ["readelf", "-p", ".upd_info", str(binary_path)],
                capture_output=True,
                text=True,
                timeout=4,
            )
            if res.returncode == 0:
                for line in res.stdout.splitlines():
                    m = re.search(r"\[\s*\d+\]\s+(.+)$", line)
                    if m:
                        raw_info = m.group(1).strip()
                        break
        except Exception:
            pass

    low = raw_info.lower()
    if any(b in low for b in BOGUS_UPD_INFO_PATTERNS):
        return ""
    return raw_info



def _parse_desktop_text(text: str) -> dict[str, str]:
    result: dict[str, str] = {}
    in_entry = False
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            in_entry = line == "[Desktop Entry]"
            continue
        if in_entry and "=" in line:
            k, v = line.split("=", 1)
            key = k.strip()
            if key not in result:
                result[key] = v.strip()
    return result


def _extract_embedded_png(binary_path: Path, dest_icon: Path) -> bool:
    """Fallback: scan first 16 MiB of binary for a well-formed PNG icon."""
    try:
        with binary_path.open("rb") as f:
            chunk = f.read(16 * 1024 * 1024)
        sig = b"\x89PNG\r\n\x1a\n"
        iend = b"IEND\xaeB`\x82"
        best_png = b""
        pos = 0
        while True:
            idx = chunk.find(sig, pos)
            if idx < 0:
                break
            end_idx = chunk.find(iend, idx)
            if end_idx > idx:
                candidate = chunk[idx : end_idx + len(iend)]
                if 256 <= len(candidate) <= 2 * 1024 * 1024 and len(candidate) > len(best_png):
                    best_png = candidate
                pos = end_idx + len(iend)
            else:
                pos = idx + len(sig)
        if best_png:
            dest_icon.write_bytes(best_png)
            return True
    except Exception:
        pass
    return False


def _extract_appimage_metadata(appimage_path: Path, slug: str) -> tuple[dict[str, str], str]:
    """Extract .desktop metadata and icon from an AppImage without unpacking the whole image."""
    meta: dict[str, str] = {}
    saved_icon_path = ""

    with tempfile.TemporaryDirectory(prefix="alis-appimage-") as td:
        tmp_dir = Path(td)
        extracted_root = tmp_dir / "squashfs-root"

        # 1. Try 7z fast selective extraction if SquashFS
        seven_z = shutil.which("7z")
        used_7z = False
        if seven_z:
            try:
                listing = subprocess.run(
                    [seven_z, "l", str(appimage_path)],
                    capture_output=True,
                    text=True,
                    timeout=8,
                ).stdout
                if "Type = SquashFS" in listing:
                    extracted_root.mkdir(parents=True, exist_ok=True)
                    subprocess.run(
                        [
                            seven_z,
                            "x",
                            "-y",
                            f"-o{extracted_root}",
                            str(appimage_path),
                            "*.desktop",
                            "usr/share/applications/*.desktop",
                            ".DirIcon",
                            "*.png",
                            "*.svg",
                            "usr/share/icons/*",
                            "usr/share/pixmaps/*",
                        ],
                        capture_output=True,
                        timeout=15,
                    )
                    used_7z = True
            except Exception:
                pass

        # 2. If 7z did not extract a .desktop file, try --appimage-extract with patterns
        if not used_7z or not list(extracted_root.rglob("*.desktop")):
            for pattern in ("*.desktop", "usr/share/applications/*.desktop", ".DirIcon", "*.png", "*.svg", "usr/share/icons/*"):
                try:
                    subprocess.run(
                        [str(appimage_path), "--appimage-extract", pattern],
                        cwd=str(tmp_dir),
                        capture_output=True,
                        timeout=12,
                    )
                except Exception:
                    break

        if extracted_root.is_dir():
            for dfile in sorted(extracted_root.rglob("*.desktop")):
                if dfile.is_file():
                    parsed = _parse_desktop_text(dfile.read_text(encoding="utf-8", errors="ignore"))
                    if parsed.get("Name") or parsed.get("Exec"):
                        meta = parsed
                        break

            icon_key = meta.get("Icon", "").strip()
            candidates: list[Path] = []
            if icon_key:
                for ext in (".svg", ".png", ""):
                    p = extracted_root / f"{icon_key}{ext}"
                    if p.is_file():
                        candidates.append(p)
                for p in extracted_root.rglob(f"{icon_key}.*"):
                    if p.is_file() and p.suffix.lower() in (".png", ".svg"):
                        candidates.append(p)
            dir_icon = extracted_root / ".DirIcon"
            if dir_icon.is_file():
                candidates.append(dir_icon)
            for p in sorted(extracted_root.rglob("*")):
                if p.is_file() and p.suffix.lower() in (".png", ".svg"):
                    candidates.append(p)

            for cand in candidates:
                try:
                    data = cand.read_bytes()
                    if len(data) < 64:
                        continue
                    ext = cand.suffix.lower()
                    if ext not in (".png", ".svg"):
                        ext = ".svg" if b"<svg" in data[:512] else ".png"
                    dest = _icons_dir() / f"{slug}{ext}"
                    dest.write_bytes(data)
                    saved_icon_path = str(dest)
                    break
                except Exception:
                    continue

    if not saved_icon_path:
        dest = _icons_dir() / f"{slug}.png"
        if _extract_embedded_png(appimage_path, dest):
            saved_icon_path = str(dest)

    return meta, saved_icon_path


def _extract_icon_from_asar(asar_path: Path, slug: str) -> str:
    """Extract top-level icon.png/svg from an Electron resources/app.asar archive."""
    try:
        with asar_path.open("rb") as f:
            hdr = f.read(16)
            if len(hdr) < 16:
                return ""
            _, header_size, _, json_len = struct.unpack("<IIII", hdr)
            data_offset = 8 + header_size
            idx_raw = f.read(json_len).decode("utf-8", errors="ignore")
            idx = json.loads(idx_raw)

            best: tuple[int, str, dict[str, Any]] | None = None

            def walk(node: dict[str, Any], prefix: str = "") -> None:
                nonlocal best
                for k, v in node.get("files", {}).items():
                    rel = f"{prefix}/{k}" if prefix else k
                    if "files" in v:
                        walk(v, rel)
                    elif k.lower().endswith((".png", ".svg")) and "offset" in v and "size" in v:
                        size = int(v["size"])
                        if size < 512 or size > 4 * 1024 * 1024:
                            continue
                        kl = k.lower()
                        score = 0
                        if kl in ("icon.png", "icon.svg", "app.png", "logo.png", "code.png"):
                            score += 100
                        elif "icon" in kl or "logo" in kl:
                            score += 50
                        if "/" not in rel:
                            score += 30
                        if score > 0:
                            cand = (score * 10_000_000 + size, rel, v)
                            if best is None or cand[0] > best[0]:
                                best = cand

            walk(idx)
            if best is not None:
                _, rel, entry = best
                f.seek(data_offset + int(entry["offset"]))
                img_bytes = f.read(int(entry["size"]))
                ext = ".svg" if rel.lower().endswith(".svg") else ".png"
                dest = _icons_dir() / f"{slug}{ext}"
                dest.write_bytes(img_bytes)
                return str(dest)
    except Exception:
        pass
    return ""


def _safe_extract_tar(tar_path: Path, dest_dir: Path) -> None:
    dest_resolved = dest_dir.resolve()
    if tar_path.name.lower().endswith(".zip"):
        with zipfile.ZipFile(tar_path, "r") as zf:
            for info in zf.infolist():
                target = (dest_resolved / info.filename).resolve()
                if not str(target).startswith(str(dest_resolved)):
                    continue
                zf.extract(info, path=dest_resolved)
                unix_mode = (info.external_attr >> 16) & 0o777
                if unix_mode and target.is_file():
                    try:
                        target.chmod(unix_mode)
                    except OSError:
                        pass
        return

    extracted = False
    if not tar_path.name.lower().endswith((".zst", ".tzst")):
        try:
            with tarfile.open(tar_path, "r:*") as tf:
                members = []
                for m in tf.getmembers():
                    target = (dest_resolved / m.name).resolve()
                    if not str(target).startswith(str(dest_resolved)):
                        continue
                    members.append(m)
                try:
                    tf.extractall(path=dest_resolved, members=members, filter="fully_trusted")
                except TypeError:
                    tf.extractall(path=dest_resolved, members=members)
            extracted = True
        except Exception:
            extracted = False

    if not extracted:
        bsdtar = shutil.which("bsdtar")
        gtar = shutil.which("tar")
        if bsdtar:
            subprocess.run(
                [bsdtar, "-xf", str(tar_path), "-C", str(dest_resolved)],
                check=True,
                capture_output=True,
                timeout=120,
            )
        elif gtar:
            cmd = [gtar, "--zstd", "-xf", str(tar_path), "-C", str(dest_resolved)] if tar_path.name.lower().endswith((".zst", ".tzst")) else [gtar, "-xf", str(tar_path), "-C", str(dest_resolved)]
            subprocess.run(
                cmd,
                check=True,
                capture_output=True,
                timeout=120,
            )
        else:
            raise RuntimeError(f"No archive extractor (bsdtar/tar) available for {tar_path.name}")


def _parse_pkginfo(pkginfo_path: Path) -> dict[str, str]:
    info: dict[str, str] = {}
    try:
        for raw_line in pkginfo_path.read_text(encoding="utf-8", errors="ignore").splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            key = k.strip()
            if key not in info:
                info[key] = v.strip()
    except Exception:
        pass
    return info


def _resolve_pkg_exec_target(pkg_dir: Path, raw_exec: str) -> Path | None:
    if not raw_exec:
        return None
    token = raw_exec.strip()
    if token.startswith('"') and '"' in token[1:]:
        token = token[1 : token.index('"', 1)]
    elif token.startswith("'") and "'" in token[1:]:
        token = token[1 : token.index("'", 1)]
    else:
        token = token.split()[0] if token.split() else ""
    if not token or token in ("env", "/usr/bin/env", "sh", "bash"):
        return None

    candidates: list[Path] = []
    if token.startswith("/"):
        candidates.append(pkg_dir / token.lstrip("/"))
    else:
        candidates.extend([
            pkg_dir / "usr" / "bin" / token,
            pkg_dir / "bin" / token,
            pkg_dir / "opt" / token / token,
            pkg_dir / token,
        ])

    for cand in candidates:
        if cand.is_symlink():
            try:
                link_target = os.readlink(cand)
                resolved = (pkg_dir / link_target.lstrip("/")) if link_target.startswith("/") else (cand.parent / link_target)
                if resolved.is_file():
                    return resolved.resolve()
            except OSError:
                pass
        if cand.is_file():
            return cand
    return None


def _find_tar_executable_and_icon(pkg_dir: Path, slug: str) -> tuple[Path | None, dict[str, str], str]:
    meta: dict[str, str] = {}
    desktop_files = sorted(pkg_dir.rglob("*.desktop"))
    for dfile in desktop_files:
        if dfile.is_file():
            parsed = _parse_desktop_text(dfile.read_text(encoding="utf-8", errors="ignore"))
            if parsed.get("Name") or parsed.get("Exec"):
                meta = parsed
                break

    pkginfo_path = pkg_dir / ".PKGINFO"
    if pkginfo_path.is_file():
        pkginfo = _parse_pkginfo(pkginfo_path)
        if not meta.get("Name") and pkginfo.get("pkgname"):
            meta["Name"] = _human_title(pkginfo["pkgname"])
        if not meta.get("Comment") and pkginfo.get("pkgdesc"):
            meta["Comment"] = pkginfo["pkgdesc"]

    # Find top root inside pkg_dir (unwrap single top-level folder if present)
    children = [p for p in pkg_dir.iterdir() if not p.name.startswith(".")]
    search_root = children[0] if (len(children) == 1 and children[0].is_dir() and children[0].name not in ("usr", "opt", "etc", "var")) else pkg_dir

    exec_path: Path | None = _resolve_pkg_exec_target(search_root, meta.get("Exec", ""))

    helper_patterns = (
        "chrome-sandbox",
        "chrome_crashpad_handler",
        "crashpad_handler",
        "xdg-mime",
        "xdg-settings",
        "minidump",
        "lib",
        " ld-",
    )

    if exec_path is None:
        exec_candidates: list[tuple[int, Path]] = []
        for p in search_root.rglob("*"):
            if p.is_symlink():
                try:
                    lt = os.readlink(p)
                    target_p = (search_root / lt.lstrip("/")) if lt.startswith("/") else (p.parent / lt)
                    if target_p.is_file():
                        p = target_p
                    else:
                        continue
                except OSError:
                    continue
            elif not p.is_file():
                continue
            name_l = p.name.lower()
            if name_l.endswith((".so", ".pak", ".dat", ".bin", ".json", ".txt", ".html", ".asar", ".png", ".svg", ".ico", ".desktop", ".zst", ".gz")):
                continue
            if any(name_l.startswith(h) or name_l == h for h in helper_patterns) or ".so." in name_l:
                continue
            try:
                mode = p.stat().st_mode
                size = p.stat().st_size
            except OSError:
                continue
            is_exec = bool(mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH))
            try:
                rel_parts = p.relative_to(search_root).parts
            except ValueError:
                continue
            if len(rel_parts) > 5:
                continue
            if not is_exec and len(rel_parts) > 1:
                continue
            score = 0
            if is_exec:
                score += 50
            if len(rel_parts) == 1:
                score += 40
            elif len(rel_parts) >= 2 and rel_parts[0] in ("bin", "usr", "opt"):
                score += 35
                if len(rel_parts) == 3 and rel_parts[:2] == ("usr", "bin"):
                    score += 25
            if name_l == slug or slug.startswith(name_l) or name_l in slug:
                score += 60
            if size > 1024 * 1024:
                score += 20
            exec_candidates.append((score, p))

        if exec_candidates:
            exec_candidates.sort(key=lambda item: (item[0], item[1].stat().st_size), reverse=True)
            exec_path = exec_candidates[0][1]

    if exec_path is not None:
        try:
            exec_path.chmod(exec_path.stat().st_mode | 0o755)
        except OSError:
            pass

    # Find icon
    saved_icon_path = ""
    icon_candidates: list[tuple[int, Path]] = []
    for p in search_root.rglob("*"):
        if p.is_file() and p.suffix.lower() in (".png", ".svg"):
            nl = p.name.lower()
            if "tray" in nl:
                continue
            try:
                sz = p.stat().st_size
            except OSError:
                continue
            if sz < 256:
                continue
            sc = 10
            if slug in nl or "icon" in nl or "logo" in nl or "app" in nl:
                sc += 50
            if p.suffix.lower() == ".svg":
                sc += 20
            icon_candidates.append((sc * 10_000_000 + sz, p))

    if icon_candidates:
        icon_candidates.sort(key=lambda item: item[0], reverse=True)
        best_icon = icon_candidates[0][1]
        ext = best_icon.suffix.lower()
        dest = _icons_dir() / f"{slug}{ext}"
        shutil.copy2(best_icon, dest)
        saved_icon_path = str(dest)

    if not saved_icon_path:
        for asar in search_root.rglob("app.asar"):
            saved_icon_path = _extract_icon_from_asar(asar, slug)
            if saved_icon_path:
                break

    if not saved_icon_path and exec_path is not None:
        dest = _icons_dir() / f"{slug}.png"
        if _extract_embedded_png(exec_path, dest):
            saved_icon_path = str(dest)

    return exec_path, meta, saved_icon_path


def _is_rsync_source(raw: str) -> bool:
    s = raw.strip()
    if not s:
        return False
    sl = s.lower()
    if sl.startswith(("gh-releases-zsync|", "zsync|")):
        return False
    if sl.endswith((".zsync", "latest.json", ".yml", ".yaml")):
        return False
    if sl.startswith(("http://", "https://")):
        return False
    if sl.startswith(("rsync://", "rsync:")) or "::" in s:
        return True
    if sl.startswith("file://") or s.startswith(("/", "./", "../", "~/")):
        return True
    if re.match(r"^[A-Za-z0-9._-]+@[A-Za-z0-9._-]+:.+", s) or re.match(r"^[A-Za-z0-9._-]+:[^/].*", s):
        return True
    try:
        if Path(s).expanduser().exists():
            return True
    except Exception:
        pass
    return False


def _normalize_rsync_source(raw: str) -> str:
    s = raw.strip()
    if s.startswith("rsync:") and not s.startswith("rsync://"):
        s = s[6:].strip()
    if s.startswith("file://"):
        s = urllib.parse.unquote(urllib.parse.urlparse(s).path)
    return s


def _read_xattr_origin_url(path: Path) -> str:
    if not path.is_file() or not hasattr(os, "getxattr"):
        return ""
    for attr in ("user.xdg.origin.url", "user.origin.url"):
        try:
            val = os.getxattr(str(path), attr)
            if isinstance(val, bytes):
                u = val.decode("utf-8", errors="ignore").strip()
                if u.startswith(("http://", "https://", "rsync://")):
                    return u
        except OSError:
            continue
    return ""


def _write_desktop_entry(
    slug: str,
    name: str,
    exec_path: Path,
    icon_path: str,
    comment: str,
    categories: str,
    wm_class: str,
    zsync_path: str = "",
    mime_type: str = "",
    update_source: str = "",
) -> Path:
    desktop_file = _desktop_dir() / f"alis-app-{slug}.desktop"
    icon_val = icon_path if icon_path else "application-x-executable"
    cat_val = categories.strip() if categories.strip() else "Utility;Application;"
    if not cat_val.endswith(";"):
        cat_val += ";"
    exec_str = str(exec_path)
    exec_quoted = f'"{exec_str}" %U' if " " in exec_str else f"{exec_str} %U"
    lines = [
        "[Desktop Entry]",
        "Type=Application",
        "Version=1.0",
        f"Name={name}",
        f"Comment={comment or f'Managed by Alis Applications ({name})'}",
        f"Exec={exec_quoted}",
        f"TryExec={exec_path}",
        f"Icon={icon_val}",
        "Terminal=false",
        f"Categories={cat_val}",
        f"StartupWMClass={wm_class or slug}",
        "X-Alis-Managed=true",
        f"X-Alis-App-Id={slug}",
    ]
    if not mime_type.strip():
        check_tokens = f"{slug} {name} {comment}".lower()
        if "pdf" in check_tokens:
            mime_type = "application/pdf;"
        elif any(k in check_tokens for k in ("word", "wordcraft", "office", "writer", "docx")):
            mime_type = "application/vnd.openxmlformats-officedocument.wordprocessingml.document;application/msword;application/vnd.oasis.opendocument.text;"
        elif any(k in check_tokens for k in ("codium", "vscodium", "vscode", "antigravity")):
            mime_type = "text/plain;"
    if mime_type.strip():
        mv = mime_type.strip()
        if not mv.endswith(";"):
            mv += ";"
        lines.append(f"MimeType={mv}")
    if zsync_path:
        lines.append(f"X-AppImage-Update-ZSync={zsync_path}")
    upd_src = update_source.strip()
    if upd_src:
        lines.append(f"X-Alis-Update-Source={upd_src}")
        if _is_rsync_source(upd_src):
            lines.append(f"X-Alis-Update-Rsync={upd_src}")
    desktop_file.write_text("\n".join(lines) + "\n", encoding="utf-8")
    try:
        desktop_file.chmod(0o755)
    except OSError:
        pass
    if shutil.which("update-desktop-database"):
        try:
            subprocess.run(
                ["update-desktop-database", str(_desktop_dir())],
                capture_output=True,
                timeout=5,
            )
        except Exception:
            pass
    return desktop_file


def _repair_managed_desktop_entries() -> None:
    """Ensure existing alis-app-*.desktop files do not quote Exec paths without spaces and backfill missing MimeType."""
    ddir = _desktop_dir()
    if not ddir.is_dir():
        return
    any_changed = False
    for dfile in ddir.glob("alis-app-*.desktop"):
        if not dfile.is_file():
            continue
        try:
            raw = dfile.read_text(encoding="utf-8")
        except Exception:
            continue
        new_lines = []
        changed = False
        has_mime = False
        name_val = ""
        comment_val = ""
        for line in raw.splitlines():
            m = re.match(r'^Exec="([^"\s]+)"(\s+.*)?$', line)
            if m:
                rest = m.group(2) or ""
                new_lines.append(f"Exec={m.group(1)}{rest}")
                changed = True
            else:
                new_lines.append(line)
            if line.startswith("MimeType=") and line.split("=", 1)[1].strip():
                has_mime = True
            elif line.startswith("Name="):
                name_val = line.split("=", 1)[1].strip()
            elif line.startswith("Comment="):
                comment_val = line.split("=", 1)[1].strip()
        if not has_mime:
            check_tokens = f"{dfile.stem} {name_val} {comment_val}".lower()
            inferred_mime = ""
            if "pdf" in check_tokens:
                inferred_mime = "application/pdf;"
            elif any(k in check_tokens for k in ("word", "wordcraft", "office", "writer", "docx")):
                inferred_mime = "application/vnd.openxmlformats-officedocument.wordprocessingml.document;application/msword;application/vnd.oasis.opendocument.text;"
            elif any(k in check_tokens for k in ("codium", "vscodium", "vscode", "antigravity")):
                inferred_mime = "text/plain;"
            if inferred_mime:
                new_lines = [ln for ln in new_lines if not ln.startswith("MimeType=")]
                new_lines.append(f"MimeType={inferred_mime}")
                changed = True
        if changed:
            try:
                dfile.write_text("\n".join(new_lines) + "\n", encoding="utf-8")
                any_changed = True
            except Exception:
                pass
    if any_changed and shutil.which("update-desktop-database"):
        try:
            subprocess.run(
                ["update-desktop-database", str(ddir)],
                capture_output=True,
                timeout=5,
            )
        except Exception:
            pass


def _move_or_copy(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    if src.resolve() == dst.resolve():
        return
    if dst.exists():
        dst.unlink()
    if os.environ.get("ALIS_PORTABLE_APPS_KEEP_SOURCE") == "1":
        shutil.copy2(src, dst)
    else:
        try:
            shutil.move(str(src), str(dst))
        except PermissionError:
            shutil.copy2(src, dst)


def add_files(raw_paths: list[str]) -> dict[str, Any]:
    _ensure_dirs()
    paths = [Path(p).expanduser() for p in raw_paths if str(p).strip()]
    existing = [p for p in paths if p.is_file()]
    if not existing:
        return {"ok": False, "error": "No valid application files selected.", "apps": cmd_list()["apps"]}

    appimages: list[Path] = []
    zsyncs: list[Path] = []
    archives: list[Path] = []

    for p in existing:
        nl = p.name.lower()
        if nl.endswith(".appimage.zsync") or nl.endswith(".zsync"):
            zsyncs.append(p)
        elif nl.endswith(".appimage"):
            appimages.append(p)
        elif nl.endswith(
            (
                ".pkg.tar.zst",
                ".pkg.tar.xz",
                ".pkg.tar.gz",
                ".tar.zst",
                ".tzst",
                ".tar.xz",
                ".txz",
                ".tar.bz2",
                ".tbz2",
                ".tar.gz",
                ".tgz",
                ".zip",
            )
        ):
            archives.append(p)

    # Auto-pair sibling .zsync files next to selected .AppImage files
    for ai in appimages:
        sibling = ai.parent / f"{ai.name}.zsync"
        if sibling.is_file() and sibling not in zsyncs:
            zsyncs.append(sibling)

    # If user selected a .zsync file without selecting the sibling .AppImage, check same folder
    for zs in list(zsyncs):
        hdr = _parse_zsync_header(zs)
        target_name = hdr.get("filename", "")
        if not target_name and zs.name.lower().endswith(".zsync"):
            target_name = zs.name[:-6]
        if target_name:
            sibling_ai = zs.parent / target_name
            if sibling_ai.is_file() and sibling_ai not in appimages:
                appimages.append(sibling_ai)

    registry = _load_registry()
    added_ids: list[str] = []

    # 1. Process AppImages
    for ai in appimages:
        slug = _slugify(ai.name)
        prev_entry = next((r for r in registry if r.get("id") == slug), None)
        matched_zsync: Path | None = None
        for zs in list(zsyncs):
            hdr = _parse_zsync_header(zs)
            if zs.name == f"{ai.name}.zsync" or hdr.get("filename") == ai.name or _slugify(zs.name) == slug:
                matched_zsync = zs
                zsyncs.remove(zs)
                break

        dest_ai = _appimages_dir() / ai.name
        try:
            _move_or_copy(ai, dest_ai)
        except Exception as exc:
            return {"ok": False, "error": f"Failed to copy {ai.name}: {exc}", "apps": cmd_list()["apps"]}
        try:
            dest_ai.chmod(dest_ai.stat().st_mode | 0o755)
        except OSError:
            pass

        dest_zsync_str = ""
        if matched_zsync is not None and matched_zsync.is_file():
            dest_zs = _appimages_dir() / matched_zsync.name
            try:
                _move_or_copy(matched_zsync, dest_zs)
                dest_zsync_str = str(dest_zs)
            except Exception:
                pass

        if prev_entry is not None:
            base_res = str(_base_dir().resolve())
            for old_key in ("storedPath", "zsyncPath"):
                old_val = str(prev_entry.get(old_key, "")).strip()
                if old_val and old_val not in (str(dest_ai), dest_zsync_str):
                    old_p = Path(old_val)
                    if old_p.is_file():
                        try:
                            if str(old_p.resolve()).startswith(base_res):
                                old_p.unlink()
                        except OSError:
                            pass

        meta, icon_path = _extract_appimage_metadata(dest_ai, slug)
        name = meta.get("Name") or _human_title(ai.name)
        comment = meta.get("Comment", "")
        categories = meta.get("Categories", "Utility;Application;")
        wm_class = meta.get("StartupWMClass", slug)
        embedded_upd_src = (
            meta.get("X-Alis-Update-Source", "")
            or meta.get("X-AppImage-Update-Rsync", "")
            or meta.get("X-Alis-Update-Rsync", "")
            or str((prev_entry or {}).get("customUpdateSource", ""))
        ).strip()

        desktop_file = _write_desktop_entry(
            slug=slug,
            name=name,
            exec_path=dest_ai,
            icon_path=icon_path,
            comment=comment,
            categories=categories,
            wm_class=wm_class,
            zsync_path=dest_zsync_str,
            mime_type=meta.get("MimeType", ""),
            update_source=embedded_upd_src,
        )

        now_ts = int(time.time())
        prev_added_at = int((prev_entry or {}).get("addedAt", 0) or 0)
        prev_updated_at = int((prev_entry or {}).get("updatedAt", 0) or 0)
        entry = {
            "id": slug,
            "name": name,
            "kind": "appimage",
            "storedPath": str(dest_ai),
            "execPath": str(dest_ai),
            "zsyncPath": dest_zsync_str,
            "hasZsync": bool(dest_zsync_str),
            "packageDir": "",
            "iconPath": icon_path,
            "desktopFile": str(desktop_file),
            "addedAt": prev_added_at if prev_added_at > 0 else now_ts,
            "updatedAt": max(now_ts, prev_updated_at + 1) if prev_entry is not None else now_ts,
        }
        if embedded_upd_src:
            entry["customUpdateSource"] = embedded_upd_src
        registry = [r for r in registry if r.get("id") != slug]
        registry.append(entry)
        added_ids.append(slug)

    # 2. Process standalone .zsync attached to an already-installed AppImage
    for zs in zsyncs:
        slug = _slugify(zs.name)
        for item in registry:
            if item.get("id") == slug and item.get("kind") == "appimage":
                dest_zs = _appimages_dir() / zs.name
                _move_or_copy(zs, dest_zs)
                item["zsyncPath"] = str(dest_zs)
                item["hasZsync"] = True
                prev_upd = int(item.get("updatedAt", 0) or 0)
                item["updatedAt"] = max(int(time.time()), prev_upd + 1)
                added_ids.append(slug)
                break

    # 3. Process archive packages (.tar.gz / .tgz / .tar.zst / .pkg.tar.zst / .tar.xz / .tar.bz2 / .zip)
    for arc in archives:
        slug = _slugify(arc.name)
        prev_entry = next((r for r in registry if r.get("id") == slug), None)
        dest_arc = _archives_dir() / arc.name
        try:
            _move_or_copy(arc, dest_arc)
        except Exception as exc:
            return {"ok": False, "error": f"Failed to copy {arc.name}: {exc}", "apps": cmd_list()["apps"]}

        pkg_dir = _packages_dir() / slug
        if pkg_dir.exists():
            shutil.rmtree(pkg_dir, ignore_errors=True)
        pkg_dir.mkdir(parents=True, exist_ok=True)
        try:
            _safe_extract_tar(dest_arc, pkg_dir)
        except Exception as exc:
            return {
                "ok": False,
                "error": f"Failed to extract {arc.name}: {exc}",
                "apps": cmd_list()["apps"],
            }

        exec_path, meta, icon_path = _find_tar_executable_and_icon(pkg_dir, slug)
        if exec_path is None:
            return {
                "ok": False,
                "error": f"Could not locate an executable inside {arc.name}.",
                "apps": cmd_list()["apps"],
            }

        if prev_entry is not None:
            old_sp = str(prev_entry.get("storedPath", "")).strip()
            if old_sp and old_sp != str(dest_arc):
                old_p = Path(old_sp)
                if old_p.is_file():
                    try:
                        if str(old_p.resolve()).startswith(str(_base_dir().resolve())):
                            old_p.unlink()
                    except OSError:
                        pass

        name = meta.get("Name") or _human_title(arc.name)
        comment = meta.get("Comment", "")
        categories = meta.get("Categories", "Utility;Application;")
        wm_class = meta.get("StartupWMClass", slug)
        embedded_upd_src = (
            meta.get("X-Alis-Update-Source", "")
            or meta.get("X-AppImage-Update-Rsync", "")
            or meta.get("X-Alis-Update-Rsync", "")
            or str((prev_entry or {}).get("customUpdateSource", ""))
        ).strip()

        desktop_file = _write_desktop_entry(
            slug=slug,
            name=name,
            exec_path=exec_path,
            icon_path=icon_path,
            comment=comment,
            categories=categories,
            wm_class=wm_class,
            mime_type=meta.get("MimeType", ""),
            update_source=embedded_upd_src,
        )

        nl_arc = arc.name.lower()
        if nl_arc.endswith((".pkg.tar.zst", ".pkg.tar.xz", ".pkg.tar.gz")):
            archive_kind = "pkg.tar.zst"
        elif nl_arc.endswith((".tar.zst", ".tzst")):
            archive_kind = "tar.zst"
        elif nl_arc.endswith((".tar.xz", ".txz")):
            archive_kind = "tar.xz"
        elif nl_arc.endswith((".tar.bz2", ".tbz2")):
            archive_kind = "tar.bz2"
        elif nl_arc.endswith(".zip"):
            archive_kind = "zip"
        else:
            archive_kind = "tar.gz"

        now_ts = int(time.time())
        prev_added_at = int((prev_entry or {}).get("addedAt", 0) or 0)
        prev_updated_at = int((prev_entry or {}).get("updatedAt", 0) or 0)
        entry = {
            "id": slug,
            "name": name,
            "kind": archive_kind,
            "storedPath": str(dest_arc),
            "execPath": str(exec_path),
            "zsyncPath": "",
            "hasZsync": False,
            "packageDir": str(pkg_dir),
            "iconPath": icon_path,
            "desktopFile": str(desktop_file),
            "addedAt": prev_added_at if prev_added_at > 0 else now_ts,
            "updatedAt": max(now_ts, prev_updated_at + 1) if prev_entry is not None else now_ts,
        }
        if embedded_upd_src:
            entry["customUpdateSource"] = embedded_upd_src
        registry = [r for r in registry if r.get("id") != slug]
        registry.append(entry)
        added_ids.append(slug)

    if not added_ids:
        return {
            "ok": False,
            "error": "No supported portable application packages (.AppImage, .zsync, .tar.gz, .tar.xz, .tar.zst, .pkg.tar.zst, .zip) were found in the selection.",
            "apps": cmd_list()["apps"],
        }

    _save_registry(registry)
    return {"ok": True, "added": added_ids, "apps": cmd_list()["apps"]}


def remove_app(app_id: str) -> dict[str, Any]:
    target_id = app_id.strip()
    registry = _load_registry()
    found: dict[str, Any] | None = None
    kept: list[dict[str, Any]] = []
    for item in registry:
        if str(item.get("id", "")) == target_id:
            found = item
        else:
            kept.append(item)

    if found is None:
        return {"ok": False, "error": f"Application '{target_id}' not found.", "apps": cmd_list()["apps"]}

    for key in ("storedPath", "zsyncPath", "iconPath", "desktopFile"):
        val = str(found.get(key, "")).strip()
        if val:
            p = Path(val)
            if p.is_file() or p.is_symlink():
                try:
                    p.unlink()
                except OSError:
                    pass

    pkg_dir = str(found.get("packageDir", "")).strip()
    if pkg_dir:
        p = Path(pkg_dir)
        if p.is_dir():
            shutil.rmtree(p, ignore_errors=True)

    _save_registry(kept, allow_removal=True)
    if shutil.which("update-desktop-database"):
        try:
            subprocess.run(
                ["update-desktop-database", str(_desktop_dir())],
                capture_output=True,
                timeout=5,
            )
        except Exception:
            pass
    return {"ok": True, "removed": target_id, "apps": cmd_list()["apps"]}


def _extract_version_from_asar(asar_path: Path) -> str:
    """Read version from top-level package.json or product.json inside an Electron app.asar."""
    try:
        with asar_path.open("rb") as f:
            hdr = f.read(16)
            if len(hdr) < 16:
                return ""
            _, header_size, _, json_len = struct.unpack("<IIII", hdr)
            if json_len <= 0 or json_len > 16 * 1024 * 1024:
                return ""
            data_offset = 8 + header_size
            idx = json.loads(f.read(json_len).decode("utf-8", errors="ignore"))
            files = idx.get("files", {}) if isinstance(idx, dict) else {}
            for fname in ("package.json", "product.json"):
                entry = files.get(fname)
                if isinstance(entry, dict) and "offset" in entry and "size" in entry:
                    sz = int(entry["size"])
                    if 0 < sz <= 1024 * 1024:
                        f.seek(data_offset + int(entry["offset"]))
                        obj = json.loads(f.read(sz).decode("utf-8", errors="ignore"))
                        ver = str(obj.get("version") or obj.get("ideVersion") or "").strip()
                        if ver:
                            return ver
    except Exception:
        pass
    return ""


def _parse_simple_yaml(text: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or line.startswith("-"):
            continue
        if ":" in line:
            k, v = line.split(":", 1)
            key = k.strip()
            val = v.strip()
            if (val.startswith("'") and val.endswith("'")) or (val.startswith('"') and val.endswith('"')):
                val = val[1:-1]
            if key and key not in result:
                result[key] = val
    return result


def _file_sha1(path: Path, item: dict[str, Any] | None = None) -> str:
    if not path.is_file():
        return ""
    try:
        st = path.stat()
        sig = f"{st.st_mtime_ns}:{st.st_size}"
        if item is not None and item.get("_sha1Sig") == sig and item.get("localSha1"):
            return str(item["localSha1"])
        h = hashlib.sha1()
        with path.open("rb") as f:
            while chunk := f.read(1024 * 1024):
                h.update(chunk)
        digest = h.hexdigest()
        if item is not None:
            item["_sha1Sig"] = sig
            item["localSha1"] = digest
        return digest
    except Exception:
        return ""


def _is_ephemeral_cdn_url(url: str) -> bool:
    """Return True if url is a temporary/signed CDN blob redirect target (such as GitHub
    release-assets.githubusercontent.com or signed S3/R2/Azure/CrabNebula URLs with short-lived JWT/SAS tokens)
    that cannot be persisted across sessions or used as a directory base for relative sibling URLs.
    """
    u = url.strip()
    if not u.startswith(("http://", "https://")):
        return False
    try:
        parsed = urllib.parse.urlparse(u)
    except Exception:
        return False
    host = (parsed.hostname or "").lower()
    path_low = (parsed.path or "").lower()
    query_low = (parsed.query or "").lower()
    if host in (
        "release-assets.githubusercontent.com",
        "objects.githubusercontent.com",
        "github-cloud.s3.amazonaws.com",
    ) or host.endswith((
        ".r2.cloudflarestorage.com",
        ".blob.core.windows.net",
        ".s3.amazonaws.com",
    )):
        return True
    if "/github-production-release-asset/" in path_low or ("crabnebula" in host and "/asset/" in path_low):
        return True
    if any(
        tok in query_low
        for tok in (
            "jwt=",
            "token=",
            "signature=",
            "sig=",
            "x-amz-signature=",
            "x-amz-credential=",
            "x-goog-signature=",
            "x-goog-credential=",
            "skoid=",
            "sktid=",
        )
    ):
        return True
    return False


def _detect_update_metadata(item: dict[str, Any]) -> bool:
    """Inspect a portable app entry and populate version, updateSupported, updateProtocol, updInfo, updateUrl.
    Returns True if item was mutated.
    """
    sanitized_legacy = False
    for url_key in ("remoteZsyncUrl", "downloadUrl", "updateUrl"):
        val = str(item.get(url_key, "")).strip()
        if val and _is_ephemeral_cdn_url(val):
            item[url_key] = ""
            sanitized_legacy = True
    err_val = str(item.get("updateError", "")).strip()
    if "618" in err_val or "jwt-not-provided" in err_val.lower():
        item["updateError"] = ""
        sanitized_legacy = True

    kind = str(item.get("kind", "appimage")).lower()
    slug_id = str(item.get("id", "")).strip()
    stored_s = str(item.get("storedPath", "")).strip()
    zsync_s = str(item.get("zsyncPath", "")).strip()
    pkg_s = str(item.get("packageDir", "")).strip()
    desktop_s = str(item.get("desktopFile", "")).strip()

    stored_p = Path(stored_s) if stored_s else Path()
    zsync_p = Path(zsync_s) if zsync_s else Path()
    pkg_p = Path(pkg_s) if pkg_s else Path()
    desktop_p = Path(desktop_s) if desktop_s else Path()

    # Self-heal stale storedPath/execPath/zsyncPath if an update replaced the AppImage on disk
    healed_path = False
    if kind == "appimage" and (not stored_s or not stored_p.is_file()):
        cand_ai: Path | None = None
        cand_zs: Path | None = None
        if desktop_s and desktop_p.is_file():
            try:
                d_meta_heal = _parse_desktop_text(desktop_p.read_text(encoding="utf-8", errors="ignore"))
                try_exec = d_meta_heal.get("TryExec", "").strip()
                if not try_exec:
                    exec_raw = d_meta_heal.get("Exec", "").strip()
                    if exec_raw:
                        try_exec = exec_raw.split()[0].strip('"')
                if try_exec and Path(try_exec).is_file():
                    cand_ai = Path(try_exec)
                z_desk = d_meta_heal.get("X-AppImage-Update-ZSync", "").strip()
                if z_desk and Path(z_desk).is_file():
                    cand_zs = Path(z_desk)
            except Exception:
                pass
        if cand_ai is None and slug_id and _appimages_dir().is_dir():
            matches = [
                p
                for p in _appimages_dir().iterdir()
                if p.is_file()
                and p.name.lower().endswith(".appimage")
                and _slugify(p.name) == slug_id
            ]
            if matches:
                matches.sort(
                    key=lambda p: (
                        _version_tuple(_extract_version_from_string(p.name)),
                        p.stat().st_mtime_ns,
                    )
                )
                cand_ai = matches[-1]
        if cand_ai is not None and cand_ai.is_file():
            stored_p = cand_ai
            stored_s = str(cand_ai)
            item["storedPath"] = stored_s
            item["execPath"] = stored_s
            if cand_zs is None:
                sib_zs = cand_ai.with_name(f"{cand_ai.name}.zsync")
                if sib_zs.is_file():
                    cand_zs = sib_zs
            if cand_zs is not None and cand_zs.is_file():
                zsync_p = cand_zs
                zsync_s = str(cand_zs)
                item["zsyncPath"] = zsync_s
                item["hasZsync"] = True
            item.pop("_metaSig", None)
            item.pop("_sha1Sig", None)
            healed_path = True
            sanitized_legacy = True

    stored_stat_sig = ""
    if stored_s and stored_p.is_file():
        try:
            st = stored_p.stat()
            stored_stat_sig = f"{st.st_mtime_ns}:{st.st_size}"
        except OSError:
            pass
    zsync_stat_sig = ""
    if zsync_s and zsync_p.is_file():
        try:
            st = zsync_p.stat()
            zsync_stat_sig = f"{st.st_mtime_ns}:{st.st_size}"
        except OSError:
            pass

    custom_src = str(item.get("customUpdateSource", "") or item.get("rsyncUrl", "")).strip()
    if not custom_src and desktop_s and desktop_p.is_file():
        try:
            d_meta = _parse_desktop_text(desktop_p.read_text(encoding="utf-8", errors="ignore"))
            custom_src = (
                d_meta.get("X-Alis-Update-Source", "")
                or d_meta.get("X-AppImage-Update-Rsync", "")
                or d_meta.get("X-Alis-Update-Rsync", "")
            ).strip()
            if custom_src:
                item["customUpdateSource"] = custom_src
                if _is_rsync_source(custom_src):
                    item["rsyncUrl"] = _normalize_rsync_source(custom_src)
        except Exception:
            pass

    meta_sig = f"v5|{stored_s}|{stored_stat_sig}|{zsync_s}|{zsync_stat_sig}|{custom_src}"
    if item.get("_metaSig") == meta_sig and "updateSupported" in item:
        return sanitized_legacy

    filename_ver = _extract_version_from_string(stored_p.name) if stored_s else ""
    detected_ver = ""
    protocol = ""
    supported = False
    has_remote_source = False
    upd_info = ""
    update_url = ""

    # 1. Check explicit custom update source or desktop file X-Alis-Update-Rsync / X-AppImage-Update-Rsync
    if custom_src:
        if _is_rsync_source(custom_src):
            protocol = "rsync"
            supported = True
            has_remote_source = True
            update_url = _normalize_rsync_source(custom_src)
            item["rsyncUrl"] = update_url
        elif custom_src.startswith("gh-releases-zsync|") or custom_src.startswith("zsync|"):
            protocol = "zsync"
            supported = True
            has_remote_source = True
            upd_info = custom_src
            if custom_src.startswith("zsync|"):
                update_url = custom_src.split("|", 1)[1].strip()
        elif custom_src.lower().endswith(".zsync"):
            protocol = "zsync"
            supported = True
            has_remote_source = True
            update_url = custom_src
        elif custom_src.lower().endswith("latest.json"):
            protocol = "tauri"
            supported = True
            has_remote_source = True
            update_url = custom_src
        elif custom_src.lower().endswith((".yml", ".yaml")):
            protocol = "electron-builder"
            supported = True
            has_remote_source = True
            update_url = custom_src

    # 2. Check companion .zsync file
    if zsync_s and zsync_p.is_file():
        hdr = _parse_zsync_header(zsync_p)
        hdr_url = hdr.get("url", "").strip()
        hdr_rsync = hdr.get("rsync-url", "").strip()
        hdr_zsync_url = (hdr.get("zsync-url", "") or hdr.get("update-url", "")).strip()
        hdr_fn = hdr.get("filename", "").strip()
        if hdr_fn and not filename_ver:
            filename_ver = _extract_version_from_string(hdr_fn)
        if not supported:
            if hdr_rsync or hdr_url.startswith("rsync://"):
                protocol = "rsync"
                supported = True
                has_remote_source = True
                update_url = hdr_rsync or hdr_url
            else:
                protocol = "zsync"
                supported = True
                if hdr_zsync_url:
                    update_url = hdr_zsync_url
                    has_remote_source = True
                elif hdr_url.startswith(("http://", "https://", "file://")) and hdr_url.lower().endswith(".zsync"):
                    update_url = hdr_url
                    has_remote_source = True
                else:
                    x_origin = _read_xattr_origin_url(zsync_p) or _read_xattr_origin_url(stored_p)
                    if x_origin.lower().endswith(".zsync"):
                        update_url = x_origin
                        has_remote_source = True

    # 3. Check ELF .upd_info on AppImage
    if kind == "appimage" and stored_s and stored_p.is_file():
        elf_upd = _read_elf_upd_info(stored_p)
        if elf_upd:
            upd_info = elf_upd
            if elf_upd.startswith("gh-releases-zsync|"):
                if not has_remote_source or protocol == "zsync":
                    protocol = "zsync"
                    supported = True
                    has_remote_source = True
                    if not custom_src:
                        update_url = ""
            elif elf_upd.startswith("zsync|"):
                z_url = elf_upd.split("|", 1)[1].strip()
                if z_url:
                    protocol = "zsync"
                    supported = True
                    has_remote_source = True
                    update_url = z_url
            elif elf_upd.startswith("rsync|"):
                r_url = elf_upd.split("|", 1)[1].strip()
                if r_url:
                    protocol = "rsync"
                    supported = True
                    has_remote_source = True
                    update_url = r_url

    # 4. Inspect extracted packageDir (for tar.gz / pkg.tar.zst)
    if pkg_s and pkg_p.is_dir():
        pkginfo_file = pkg_p / ".PKGINFO"
        if pkginfo_file.is_file():
            pinfo = _parse_pkginfo(pkginfo_file)
            if pinfo.get("pkgver"):
                detected_ver = pinfo["pkgver"]
        for yml_file in sorted(pkg_p.rglob("app-update.yml")):
            if yml_file.is_file():
                yml = _parse_simple_yaml(yml_file.read_text(encoding="utf-8", errors="ignore"))
                prov = yml.get("provider", "").lower()
                if prov == "generic" and yml.get("url", "").startswith(("http://", "https://", "file://")):
                    if not has_remote_source:
                        protocol = "electron-builder"
                        supported = True
                        has_remote_source = True
                        update_url = yml["url"].rstrip("/") + "/latest-linux.yml"
                elif prov == "github" and yml.get("owner") and yml.get("repo"):
                    if not has_remote_source:
                        protocol = "electron-builder"
                        supported = True
                        has_remote_source = True
                        update_url = f"https://github.com/{yml['owner']}/{yml['repo']}/releases/latest/download/latest-linux.yml"
                break
        if not detected_ver:
            for pjson in sorted(pkg_p.rglob("package.json")):
                if "node_modules" in str(pjson):
                    continue
                try:
                    d = json.loads(pjson.read_text(encoding="utf-8", errors="ignore"))
                    v = str(d.get("version", "")).strip()
                    if v:
                        detected_ver = v
                        break
                except Exception:
                    pass
        if not detected_ver:
            for asar_file in sorted(pkg_p.rglob("app.asar")):
                if asar_file.is_file():
                    detected_ver = _extract_version_from_asar(asar_file)
                    if detected_ver:
                        break

    # 5. Inspect SquashFS inside AppImage for version, app-update.yml, and Tauri latest.json
    seven_z = shutil.which("7z")
    if kind == "appimage" and stored_s and stored_p.is_file() and seven_z:
        try:
            listing = subprocess.run(
                [seven_z, "l", str(stored_p)],
                capture_output=True,
                text=True,
                timeout=8,
            ).stdout
            has_app_update_yml = False
            has_pkg_json = False
            root_desktop_files: list[str] = []
            usr_bin_files: list[str] = []
            jar_version = ""

            for line in listing.splitlines():
                parts = line.strip().split(maxsplit=5)
                if len(parts) < 6 or not re.match(r"^\d{4}-\d{2}-\d{2}$", parts[0]):
                    continue
                attr = parts[2]
                if "D" in attr:
                    continue
                rel_path = parts[5].strip()
                rel_low = rel_path.lower()
                if rel_low == "resources/app-update.yml" or rel_low.endswith("/resources/app-update.yml"):
                    has_app_update_yml = True
                elif rel_low == "resources/app/package.json":
                    has_pkg_json = True
                elif "/" not in rel_path and rel_low.endswith(".desktop"):
                    root_desktop_files.append(rel_path)
                elif rel_path.startswith("usr/bin/") and "/" not in rel_path[8:]:
                    usr_bin_files.append(rel_path)
                elif "/libs/" in rel_low and rel_low.endswith(".jar") and not jar_version:
                    jv = _extract_version_from_string(Path(rel_path).name)
                    if jv:
                        jar_version = jv

            for d_rel in root_desktop_files[:2]:
                out_d = subprocess.run(
                    [seven_z, "e", "-so", str(stored_p), d_rel],
                    capture_output=True,
                    text=True,
                    timeout=5,
                )
                if out_d.returncode == 0 and out_d.stdout:
                    d_parsed = _parse_desktop_text(out_d.stdout)
                    x_ver = d_parsed.get("X-AppImage-Version", "").strip()
                    if x_ver and not detected_ver:
                        detected_ver = x_ver.replace("+", "-")

            if has_pkg_json and not detected_ver:
                out_p = subprocess.run(
                    [seven_z, "e", "-so", str(stored_p), "resources/app/package.json"],
                    capture_output=True,
                    text=True,
                    timeout=5,
                )
                if out_p.returncode == 0 and out_p.stdout:
                    try:
                        p_obj = json.loads(out_p.stdout)
                        v_str = str(p_obj.get("version", "")).strip()
                        if v_str:
                            detected_ver = v_str.replace("+", "-")
                    except Exception:
                        pass

            if not detected_ver and jar_version:
                detected_ver = jar_version

            if not has_remote_source and has_app_update_yml:
                out_y = subprocess.run(
                    [seven_z, "e", "-so", str(stored_p), "resources/app-update.yml"],
                    capture_output=True,
                    text=True,
                    timeout=5,
                )
                if out_y.returncode == 0 and out_y.stdout:
                    yml = _parse_simple_yaml(out_y.stdout)
                    prov = yml.get("provider", "").lower()
                    if prov == "generic" and yml.get("url", "").startswith(("http://", "https://", "file://")):
                        protocol = "electron-builder"
                        supported = True
                        has_remote_source = True
                        update_url = yml["url"].rstrip("/") + "/latest-linux.yml"
                    elif prov == "github" and yml.get("owner") and yml.get("repo"):
                        protocol = "electron-builder"
                        supported = True
                        has_remote_source = True
                        update_url = f"https://github.com/{yml['owner']}/{yml['repo']}/releases/latest/download/latest-linux.yml"

            if not has_remote_source and not has_app_update_yml and usr_bin_files:
                for bin_rel in usr_bin_files[:2]:
                    out_b = subprocess.run(
                        [seven_z, "e", "-so", str(stored_p), bin_rel],
                        capture_output=True,
                        timeout=8,
                    )
                    if out_b.returncode == 0 and out_b.stdout:
                        if not detected_ver:
                            m_appver = re.search(rb"app_version=(\d+\.\d+(?:\.\d+)+)", out_b.stdout)
                            if m_appver:
                                detected_ver = m_appver.group(1).decode("ascii", errors="ignore")
                        m_tauri = re.search(
                            rb"https?://[A-Za-z0-9._~:/?#\[\]@!$&()*+,;=%-]+?latest\.json",
                            out_b.stdout,
                        )
                        if m_tauri:
                            cand_url = m_tauri.group(0).decode("ascii", errors="ignore")
                            last_http = max(cand_url.rfind("https://"), cand_url.rfind("http://"))
                            if last_http >= 0:
                                cand_url = cand_url[last_http:]
                            protocol = "tauri"
                            supported = True
                            has_remote_source = True
                            update_url = cand_url
                            break
        except Exception:
            pass

    # Choose best version across current item["version"], detected_ver, and filename_ver
    best_ver = str(item.get("version", "")).strip()
    for cand_ver in (detected_ver, filename_ver):
        if cand_ver:
            if not best_ver or _compare_versions(cand_ver, best_ver) > 0:
                best_ver = cand_ver

    item["version"] = best_ver
    item["updateSupported"] = bool(supported)
    item["updateProtocol"] = protocol
    item["updInfo"] = upd_info
    item["updateUrl"] = update_url
    if healed_path and stored_s and stored_p.is_file():
        new_sha1 = _file_sha1(stored_p, item).lower()
        rem_sha1 = str(item.get("remoteSha1", "")).strip().lower()
        lat_ver = str(item.get("latestVersion", "")).strip()
        if (rem_sha1 and new_sha1 == rem_sha1) or (lat_ver and best_ver and _compare_versions(best_ver, lat_ver) >= 0):
            item["updateAvailable"] = False
            item["updateError"] = ""
            if best_ver:
                item["latestVersion"] = best_ver
    if "updateAvailable" not in item:
        item["updateAvailable"] = False
    if "latestVersion" not in item:
        item["latestVersion"] = ""
    item["_metaSig"] = meta_sig
    return True


def _fetch_url_bytes(url: str, max_bytes: int = 0, timeout: float = 15.0) -> tuple[bytes, str]:
    """Fetch bytes from http://, https://, or file:// URL.
    Returns (bytes, stable_base_url) where stable_base_url excludes ephemeral signed CDN redirect hops
    (such as release-assets.githubusercontent.com?...&jwt=...) so relative URLs in .zsync or .yml
    manifests resolve against the release directory URL instead of a per-asset signed blob URL.
    """
    if url.startswith("file://"):
        p = Path(urllib.parse.unquote(urllib.parse.urlparse(url).path))
        with p.open("rb") as f:
            data = f.read(max_bytes) if max_bytes > 0 else f.read()
        return data, url
    if Path(url).is_file():
        p = Path(url).resolve()
        with p.open("rb") as f:
            data = f.read(max_bytes) if max_bytes > 0 else f.read()
        return data, p.as_uri()

    headers = {
        "User-Agent": "Alis-PortableApps-Updater/1.0",
        "Accept": "*/*",
    }
    gh_tok = (os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN") or "").strip()
    if gh_tok and "api.github.com" in url:
        headers["Authorization"] = f"Bearer {gh_tok}"
    if max_bytes > 0:
        headers["Range"] = f"bytes=0-{max_bytes - 1}"

    redirect_chain: list[str] = [url]

    class _ChainRedirectHandler(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req: Any, fp: Any, code: int, msg: str, hdrs: Any, newurl: str) -> Any:
            redirect_chain.append(urllib.parse.urljoin(req.full_url, newurl))
            return super().redirect_request(req, fp, code, msg, hdrs, newurl)

    opener = urllib.request.build_opener(_ChainRedirectHandler)
    req = urllib.request.Request(url, headers=headers)
    with opener.open(req, timeout=timeout) as resp:
        final_url = resp.geturl() or url
        if final_url not in redirect_chain:
            redirect_chain.append(final_url)
        stable_url = url
        for cand in redirect_chain:
            if not _is_ephemeral_cdn_url(cand):
                stable_url = cand
        data = resp.read(max_bytes) if max_bytes > 0 else resp.read()
        return data, stable_url


def _fetch_url_head(url: str, timeout: float = 12.0) -> dict[str, Any]:
    """Perform a lightweight HEAD (or Range 0-0) check to obtain Content-Length and final URL."""
    if url.startswith("file://"):
        p = Path(urllib.parse.unquote(urllib.parse.urlparse(url).path))
        if p.is_file():
            return {"size": p.stat().st_size, "finalUrl": url}
        return {"size": -1, "finalUrl": url}
    if Path(url).is_file():
        p = Path(url).resolve()
        return {"size": p.stat().st_size, "finalUrl": p.as_uri()}

    try:
        req = urllib.request.Request(
            url,
            method="HEAD",
            headers={"User-Agent": "Alis-PortableApps-Updater/1.0"},
        )
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            cl = resp.headers.get("Content-Length", "")
            return {
                "size": int(cl) if cl and cl.isdigit() else -1,
                "finalUrl": resp.geturl() or url,
            }
    except Exception:
        return {"size": -1, "finalUrl": url}


def _resolve_gh_releases_zsync_url(upd_info: str, stored_name: str = "") -> tuple[str, str]:
    """Resolve gh-releases-zsync|owner|repo|tag|pattern to (zsync_download_url, release_tag)."""
    parts = [p.strip() for p in upd_info.split("|")]
    if len(parts) < 5 or parts[0] != "gh-releases-zsync":
        return "", ""
    _, owner, repo, tag, pattern = parts[:5]

    api_base = os.environ.get("ALIS_GITHUB_API_BASE", "https://api.github.com").rstrip("/")
    candidates: list[tuple[str, str]] = [(owner, repo)]
    if owner.lower() == "vscodium" and "anylinux" in stored_name.lower():
        candidates.insert(0, ("pkgforge-dev", "VSCodium-AppImage"))

    for cand_owner, cand_repo in candidates:
        if tag.lower() == "latest":
            endpoints = [
                f"{api_base}/repos/{cand_owner}/{cand_repo}/releases/latest",
                f"{api_base}/repos/{cand_owner}/{cand_repo}/releases?per_page=5",
            ]
        else:
            endpoints = [
                f"{api_base}/repos/{cand_owner}/{cand_repo}/releases/tags/{tag}",
                f"{api_base}/repos/{cand_owner}/{cand_repo}/releases?per_page=5",
            ]

        for ep in endpoints:
            try:
                raw, _ = _fetch_url_bytes(ep, timeout=12.0)
                payload = json.loads(raw.decode("utf-8", errors="ignore"))
                releases = payload if isinstance(payload, list) else [payload]
                for rel in releases:
                    if not isinstance(rel, dict):
                        continue
                    rel_tag = str(rel.get("tag_name", "")).strip()
                    assets = rel.get("assets", [])
                    if not isinstance(assets, list):
                        continue
                    for asset in assets:
                        if not isinstance(asset, dict):
                            continue
                        aname = str(asset.get("name", "")).strip()
                        dl_url = str(asset.get("browser_download_url", "")).strip()
                        if not aname or not dl_url:
                            continue
                        if fnmatch.fnmatchcase(aname, pattern) or fnmatch.fnmatch(aname.lower(), pattern.lower()):
                            return dl_url, rel_tag
            except Exception:
                continue

        # Web fallback if api.github.com is rate-limited (HTTP 403) and using default GitHub host
        if "api.github.com" in api_base:
            try:
                rel_tag = tag
                if tag.lower() == "latest":
                    head_info = _fetch_url_head(f"https://github.com/{cand_owner}/{cand_repo}/releases/latest", timeout=10.0)
                    final_u = str(head_info.get("finalUrl", ""))
                    if "/releases/tag/" in final_u:
                        rel_tag = urllib.parse.unquote(final_u.rsplit("/releases/tag/", 1)[1].split("?", 1)[0]).strip()
                if rel_tag and rel_tag.lower() != "latest":
                    exp_url = f"https://github.com/{cand_owner}/{cand_repo}/releases/expanded_assets/{rel_tag}"
                    raw_html, _ = _fetch_url_bytes(exp_url, timeout=12.0)
                    html_txt = raw_html.decode("utf-8", errors="ignore")
                    for m in re.finditer(r'href="(/[^"]+/releases/download/[^"]+)"', html_txt):
                        href = m.group(1)
                        aname = urllib.parse.unquote(Path(href).name)
                        if fnmatch.fnmatchcase(aname, pattern) or fnmatch.fnmatch(aname.lower(), pattern.lower()):
                            return f"https://github.com{href}", rel_tag
            except Exception:
                pass
    return "", ""


def _fetch_upstream_range(url: str, start: int, end: int, timeout: float = 30.0) -> tuple[bytes, int]:
    """Fetch an inclusive byte range [start, end] from http(s):// or file:// URL.
    Returns (chunk_bytes, total_file_size).
    """
    if url.startswith("file://") or Path(url).is_file():
        p = Path(urllib.parse.unquote(urllib.parse.urlparse(url).path)) if url.startswith("file://") else Path(url)
        total = p.stat().st_size
        actual_end = min(end, total - 1)
        if start > actual_end:
            return b"", total
        with p.open("rb") as f:
            f.seek(start)
            return f.read(actual_end - start + 1), total

    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": "Alis-PortableApps-Updater/1.0",
            "Range": f"bytes={start}-{end}",
        },
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        cr = resp.headers.get("Content-Range", "")
        total = -1
        if "/" in cr:
            tot_s = cr.rsplit("/", 1)[1].strip()
            if tot_s.isdigit():
                total = int(tot_s)
        data = resp.read()
        if resp.status == 200:
            # Server ignored Range header and returned full payload
            total = len(data)
            return data[start : end + 1], total
        if total < 0:
            total = end + 1
        return data, total


def _run_zsync_via_local_proxy(
    seed_appimage: Path,
    zsync_raw_bytes: bytes,
    payload_url: str,
    expected_length: int,
    dest_out: Path,
    progress_cb: Any = None,
) -> bool:
    """Run native /usr/bin/zsync against a local HTTP proxy that translates zsync HTTP Range
    requests into upstream HTTPS/file single-range requests with coalescing and streaming.
    """
    zsync_bin = shutil.which("zsync")
    if not zsync_bin or not seed_appimage.is_file() or b"\n\n" not in zsync_raw_bytes:
        return False

    hdr_bytes, body_bytes = zsync_raw_bytes.split(b"\n\n", 1)
    proxy_bytes_fetched = [0]
    seed_bytes_obtained = [0]
    payload_phase_started = [False]
    resolved_cdn_url = [""]
    last_progress_emit = [0.0]
    dl_start_ts = [0.0]

    def _open_upstream_range(start: int, end: int, timeout: float = 60.0) -> tuple[Any, int, int]:
        candidates = [resolved_cdn_url[0], payload_url] if resolved_cdn_url[0] and resolved_cdn_url[0] != payload_url else [payload_url]
        last_err: Exception | None = None
        for idx, target_u in enumerate(candidates):
            try:
                req = urllib.request.Request(
                    target_u,
                    headers={
                        "User-Agent": "Alis-PortableApps-Updater/1.0",
                        "Range": f"bytes={start}-{end}",
                    },
                )
                resp = urllib.request.urlopen(req, timeout=timeout)
                final_u = resp.geturl() or target_u
                if final_u.startswith(("http://", "https://")):
                    resolved_cdn_url[0] = final_u
                cr = resp.headers.get("Content-Range", "")
                total = -1
                if "/" in cr:
                    tot_s = cr.rsplit("/", 1)[1].strip()
                    if tot_s.isdigit():
                        total = int(tot_s)
                elif resp.status == 200:
                    cl = resp.headers.get("Content-Length", "")
                    if cl and cl.isdigit():
                        total = int(cl)
                return resp, total, int(resp.status or 206)
            except Exception as exc:
                last_err = exc
                if idx == 0 and len(candidates) > 1:
                    resolved_cdn_url[0] = ""
                    continue
                raise
        raise last_err or RuntimeError("Failed to open upstream range")

    class ZsyncLocalProxyHandler(http.server.BaseHTTPRequestHandler):
        def log_message(self, format: str, *args: Any) -> None:
            pass

        def do_GET(self) -> None:
            if self.path == "/app.zsync":
                port = self.server.server_address[1]
                out_lines: list[str] = []
                replaced_url = False
                for line in hdr_bytes.decode("utf-8", errors="ignore").splitlines():
                    if line.lower().startswith("url:"):
                        out_lines.append(f"URL: http://127.0.0.1:{port}/payload")
                        replaced_url = True
                    else:
                        out_lines.append(line)
                if not replaced_url:
                    out_lines.append(f"URL: http://127.0.0.1:{port}/payload")
                z_payload = ("\n".join(out_lines) + "\n\n").encode("utf-8") + body_bytes
                self.send_response(200)
                self.send_header("Content-Type", "application/octet-stream")
                self.send_header("Content-Length", str(len(z_payload)))
                self.end_headers()
                self.wfile.write(z_payload)
                return

            if self.path == "/payload":
                payload_phase_started[0] = True
                if dl_start_ts[0] <= 0.0:
                    dl_start_ts[0] = time.time()
                rng = self.headers.get("Range", "").strip()
                total_size = expected_length if expected_length > 0 else 0
                is_local_file = payload_url.startswith("file://") or Path(payload_url).is_file()

                if not rng.startswith("bytes="):
                    data, _ = _fetch_url_bytes(payload_url, timeout=120.0)
                    proxy_bytes_fetched[0] += len(data)
                    if progress_cb is not None and total_size > 0:
                        pct_val = min(99.0, proxy_bytes_fetched[0] * 100.0 / total_size)
                        progress_cb(
                            pct_val,
                            proxy_bytes_fetched[0],
                            total_size,
                            f"{int(round(pct_val))}% ({_format_bytes(proxy_bytes_fetched[0])} / {_format_bytes(total_size)})",
                        )
                    self.send_response(200)
                    self.send_header("Content-Type", "application/octet-stream")
                    self.send_header("Content-Length", str(len(data)))
                    self.end_headers()
                    self.wfile.write(data)
                    return

                parts: list[tuple[int, int]] = []
                for spec in rng[6:].split(","):
                    spec = spec.strip()
                    if "-" not in spec:
                        continue
                    s_str, e_str = spec.split("-", 1)
                    start = int(s_str) if s_str else 0
                    end = int(e_str) if e_str else max(0, total_size - 1)
                    if total_size > 0:
                        end = min(end, total_size - 1)
                    if end >= start:
                        parts.append((start, end))

                if not parts:
                    self.send_error(416)
                    return

                is_ascending = all(parts[i][0] > parts[i - 1][1] for i in range(1, len(parts)))

                if not is_local_file and is_ascending:
                    # Coalesce nearby ascending ranges (within 256 KiB gap) and stream directly to zsync
                    groups: list[list[tuple[int, int]]] = [[parts[0]]]
                    for s, e in parts[1:]:
                        if s <= groups[-1][-1][1] + 262144:
                            groups[-1].append((s, e))
                        else:
                            groups.append([(s, e)])

                    first_resp, tot0, status0 = _open_upstream_range(groups[0][0][0], groups[0][-1][1], timeout=60.0)
                    try:
                        if tot0 > 0:
                            total_size = tot0
                        tot_val = total_size if total_size > 0 else (max(e for _, e in parts) + 1)

                        def _emit_stream_progress(force: bool = False) -> None:
                            if progress_cb is None or tot_val <= 0:
                                return
                            now = time.time()
                            if not force and (now - last_progress_emit[0]) < 0.08:
                                return
                            last_progress_emit[0] = now
                            effective_done = min(tot_val, seed_bytes_obtained[0] + proxy_bytes_fetched[0])
                            pct_est = min(98.0, effective_done * 100.0 / tot_val)
                            elapsed = max(0.05, now - dl_start_ts[0])
                            spd = int(proxy_bytes_fetched[0] / elapsed)
                            progress_cb(
                                pct_est,
                                effective_done,
                                tot_val,
                                f"{int(round(pct_est))}% ({_format_bytes(effective_done)} / {_format_bytes(tot_val)} · {_format_bytes(spd)}/s)",
                            )

                        def _discard_exact(resp_obj: Any, n_bytes: int) -> None:
                            rem = n_bytes
                            while rem > 0:
                                chunk = resp_obj.read(min(65536, rem))
                                if not chunk:
                                    raise RuntimeError("Upstream stream ended prematurely while skipping gap")
                                rem -= len(chunk)
                                proxy_bytes_fetched[0] += len(chunk)
                                _emit_stream_progress()

                        def _pipe_exact(resp_obj: Any, n_bytes: int) -> None:
                            rem = n_bytes
                            while rem > 0:
                                chunk = resp_obj.read(min(65536, rem))
                                if not chunk:
                                    raise RuntimeError("Upstream stream ended prematurely while streaming range")
                                self.wfile.write(chunk)
                                rem -= len(chunk)
                                proxy_bytes_fetched[0] += len(chunk)
                                _emit_stream_progress()

                        if len(parts) == 1:
                            s, e = parts[0]
                            if tot_val > 0:
                                e = min(e, tot_val - 1)
                            need = e - s + 1
                            self.send_response(206)
                            self.send_header("Content-Type", "application/octet-stream")
                            self.send_header("Content-Range", f"bytes {s}-{e}/{tot_val}")
                            self.send_header("Content-Length", str(need))
                            self.end_headers()
                            if status0 == 200 and s > 0:
                                _discard_exact(first_resp, s)
                            _pipe_exact(first_resp, need)
                            _emit_stream_progress(force=True)
                            return

                        boundary = "alis_zsync_range_boundary"
                        trailer = f"\r\n--{boundary}--\r\n".encode("ascii")
                        part_headers: dict[tuple[int, int], bytes] = {}
                        exact_content_len = len(trailer)
                        for s, e in parts:
                            ph = (
                                f"\r\n--{boundary}\r\n"
                                f"Content-Type: application/octet-stream\r\n"
                                f"Content-Range: bytes {s}-{e}/{tot_val}\r\n\r\n"
                            ).encode("ascii")
                            part_headers[(s, e)] = ph
                            exact_content_len += len(ph) + (e - s + 1)

                        self.send_response(206)
                        self.send_header("Content-Type", f"multipart/byteranges; boundary={boundary}")
                        self.send_header("Content-Length", str(exact_content_len))
                        self.end_headers()

                        if status0 == 200:
                            cur_pos = 0
                            for s, e in parts:
                                if s > cur_pos:
                                    _discard_exact(first_resp, s - cur_pos)
                                    cur_pos = s
                                self.wfile.write(part_headers[(s, e)])
                                _pipe_exact(first_resp, e - s + 1)
                                cur_pos = e + 1
                        else:
                            for g_idx, grp in enumerate(groups):
                                cs, ce = grp[0][0], grp[-1][1]
                                if g_idx == 0:
                                    resp_cur, status_cur = first_resp, status0
                                else:
                                    resp_cur, _, status_cur = _open_upstream_range(cs, ce, timeout=60.0)
                                try:
                                    cur_pos = 0 if status_cur == 200 else cs
                                    for s, e in grp:
                                        if s > cur_pos:
                                            _discard_exact(resp_cur, s - cur_pos)
                                            cur_pos = s
                                        self.wfile.write(part_headers[(s, e)])
                                        _pipe_exact(resp_cur, e - s + 1)
                                        cur_pos = e + 1
                                finally:
                                    resp_cur.close()

                        self.wfile.write(trailer)
                        _emit_stream_progress(force=True)
                        return
                    finally:
                        first_resp.close()

                # Local file or non-ascending fallback
                sorted_parts = sorted(parts, key=lambda x: x[0])
                coalesced: list[tuple[int, int]] = [sorted_parts[0]]
                for s, e in sorted_parts[1:]:
                    cs, ce = coalesced[-1]
                    if s <= ce + 65536:
                        coalesced[-1] = (cs, max(ce, e))
                    else:
                        coalesced.append((s, e))

                fetched_buffers: list[tuple[int, bytes]] = []
                for cs, ce in coalesced:
                    buf, tot = _fetch_upstream_range(payload_url, cs, ce, timeout=60.0)
                    if tot > 0:
                        total_size = tot
                    proxy_bytes_fetched[0] += len(buf)
                    if progress_cb is not None and total_size > 0:
                        effective_done = min(total_size, seed_bytes_obtained[0] + proxy_bytes_fetched[0])
                        pct_est = min(98.0, effective_done * 100.0 / total_size)
                        progress_cb(
                            pct_est,
                            effective_done,
                            total_size,
                            f"{int(round(pct_est))}% ({_format_bytes(proxy_bytes_fetched[0])} delta fetched)",
                        )
                    fetched_buffers.append((cs, buf))

                def slice_part(s: int, e: int) -> bytes:
                    for cs, buf in fetched_buffers:
                        if cs <= s and (s - cs + (e - s + 1)) <= len(buf):
                            offset = s - cs
                            return buf[offset : offset + (e - s + 1)]
                    buf, _ = _fetch_upstream_range(payload_url, s, e, timeout=60.0)
                    return buf

                if len(parts) == 1:
                    s, e = parts[0]
                    chunk = slice_part(s, e)
                    tot_val = total_size if total_size > 0 else (e + 1)
                    self.send_response(206)
                    self.send_header("Content-Type", "application/octet-stream")
                    self.send_header("Content-Range", f"bytes {s}-{s + len(chunk) - 1}/{tot_val}")
                    self.send_header("Content-Length", str(len(chunk)))
                    self.end_headers()
                    self.wfile.write(chunk)
                else:
                    boundary = "alis_zsync_range_boundary"
                    tot_val = total_size if total_size > 0 else (max(e for _, e in parts) + 1)
                    out_chunks: list[bytes] = []
                    for s, e in parts:
                        chunk = slice_part(s, e)
                        part_hdr = (
                            f"\r\n--{boundary}\r\n"
                            f"Content-Type: application/octet-stream\r\n"
                            f"Content-Range: bytes {s}-{s + len(chunk) - 1}/{tot_val}\r\n\r\n"
                        ).encode("ascii")
                        out_chunks.append(part_hdr + chunk)
                    out_chunks.append(f"\r\n--{boundary}--\r\n".encode("ascii"))
                    body_out = b"".join(out_chunks)
                    self.send_response(206)
                    self.send_header("Content-Type", f"multipart/byteranges; boundary={boundary}")
                    self.send_header("Content-Length", str(len(body_out)))
                    self.end_headers()
                    self.wfile.write(body_out)
                return

            self.send_error(404)

    class _SilentTCPServer(socketserver.TCPServer):
        allow_reuse_address = True

        def handle_error(self, request: Any, client_address: Any) -> None:
            pass

    srv = _SilentTCPServer(("127.0.0.1", 0), ZsyncLocalProxyHandler)
    port = srv.server_address[1]
    thread = threading.Thread(target=srv.serve_forever, daemon=True)
    thread.start()
    try:
        proc = subprocess.Popen(
            [zsync_bin, "-i", str(seed_appimage), "-o", str(dest_out), f"http://127.0.0.1:{port}/app.zsync"],
            cwd=str(dest_out.parent),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        deadline = time.time() + 300.0
        last_bytes_seen = 0
        buf = ""
        if proc.stdout is not None:
            while True:
                if proxy_bytes_fetched[0] > last_bytes_seen:
                    last_bytes_seen = proxy_bytes_fetched[0]
                    deadline = max(deadline, time.time() + 300.0)
                if time.time() > deadline:
                    proc.kill()
                    return False
                chunk = proc.stdout.read(128)
                if not chunk:
                    break
                buf += chunk.decode("utf-8", errors="ignore")
                while "\r" in buf or "\n" in buf:
                    idx_r = buf.find("\r")
                    idx_n = buf.find("\n")
                    if idx_r >= 0 and (idx_n < 0 or idx_r < idx_n):
                        seg, buf = buf[:idx_r], buf[idx_r + 1 :]
                    else:
                        seg, buf = buf[:idx_n], buf[idx_n + 1 :]
                    m_seed = re.search(r"(\d+(?:\.\d+)?)%\s+of\s+target\s+obtained", seg, re.IGNORECASE)
                    if m_seed:
                        try:
                            seed_pct = float(m_seed.group(1))
                            done_est = int(round((seed_pct / 100.0) * expected_length)) if expected_length > 0 else 0
                            seed_bytes_obtained[0] = done_est
                            if progress_cb is not None:
                                progress_cb(seed_pct, done_est, expected_length, f"{int(round(seed_pct))}% reused from local seed")
                        except ValueError:
                            pass
                        continue
                    if "downloading new blocks" in seg.lower():
                        payload_phase_started[0] = True
                        continue
                    if not payload_phase_started[0] or proxy_bytes_fetched[0] > 0:
                        continue
                    m = re.search(r"(\d+(?:\.\d+)?)%\s*([0-9.]+\s*[A-Za-z]+ps)?", seg)
                    if m and progress_cb is not None:
                        try:
                            pct = float(m.group(1))
                            spd = (m.group(2) or "").strip()
                            sub = f"{int(round(pct))}% ({spd})" if spd else f"{int(round(pct))}%"
                            done_est = int(round((pct / 100.0) * expected_length)) if expected_length > 0 else proxy_bytes_fetched[0]
                            progress_cb(pct, done_est, expected_length, sub)
                        except ValueError:
                            pass
        proc.wait(timeout=10)
        return proc.returncode == 0 and dest_out.is_file()
    except Exception:
        return False
    finally:
        srv.shutdown()
        srv.server_close()


def _download_url_to_file(
    url: str,
    dest: Path,
    timeout: float = 300.0,
    progress_cb: Any = None,
) -> None:
    if url.startswith("file://") or Path(url).is_file():
        src = Path(urllib.parse.unquote(urllib.parse.urlparse(url).path)) if url.startswith("file://") else Path(url)
        total = src.stat().st_size
        done = 0
        if progress_cb is not None:
            progress_cb(0.0, 0, total, f"0% (0 B / {_format_bytes(total)})")
        with src.open("rb") as in_f, dest.open("wb") as out_f:
            while chunk := in_f.read(256 * 1024):
                out_f.write(chunk)
                done += len(chunk)
                if progress_cb is not None and total > 0:
                    pct = min(100.0, done * 100.0 / total)
                    progress_cb(pct, done, total, f"{int(round(pct))}% ({_format_bytes(done)} / {_format_bytes(total)})")
        shutil.copystat(src, dest)
        return

    req = urllib.request.Request(
        url,
        headers={"User-Agent": "Alis-PortableApps-Updater/1.0"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp, dest.open("wb") as out_f:
        cl = resp.headers.get("Content-Length", "")
        total = int(cl) if cl and cl.isdigit() else 0
        done = 0
        last_emit = 0.0
        if progress_cb is not None:
            progress_cb(0.0 if total > 0 else 10.0, 0, total, "Starting download…")
        while chunk := resp.read(64 * 1024):
            out_f.write(chunk)
            done += len(chunk)
            now = time.time()
            if progress_cb is not None and (now - last_emit >= 0.08 or (total > 0 and done >= total)):
                if total > 0:
                    pct = min(100.0, done * 100.0 / total)
                    sub = f"{int(round(pct))}% ({_format_bytes(done)} / {_format_bytes(total)})"
                else:
                    pct = 50.0
                    sub = f"{_format_bytes(done)} downloaded"
                progress_cb(pct, done, total, sub)
                last_emit = now


def _run_rsync_with_progress(
    cmd: list[str],
    progress_cb: Any = None,
    timeout: float = 180.0,
) -> tuple[int, str]:
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    out_chunks: list[str] = []
    err_chunks: list[str] = []

    def _read_stderr() -> None:
        if proc.stderr is not None:
            err_chunks.append(proc.stderr.read().decode("utf-8", errors="ignore"))

    err_thread = threading.Thread(target=_read_stderr, daemon=True)
    err_thread.start()

    deadline = time.time() + timeout
    buf = ""
    try:
        if proc.stdout is not None:
            while True:
                if time.time() > deadline:
                    proc.kill()
                    return 124, "rsync timed out"
                chunk = proc.stdout.read(128)
                if not chunk:
                    break
                decoded = chunk.decode("utf-8", errors="ignore")
                out_chunks.append(decoded)
                buf += decoded
                while "\r" in buf or "\n" in buf:
                    idx_r = buf.find("\r")
                    idx_n = buf.find("\n")
                    if idx_r >= 0 and (idx_n < 0 or idx_r < idx_n):
                        seg, buf = buf[:idx_r], buf[idx_r + 1 :]
                    else:
                        seg, buf = buf[:idx_n], buf[idx_n + 1 :]
                    m = re.search(r"(\d+)%(?:\s+([0-9.]+\s*[A-Za-z]+/s))?", seg)
                    if m and progress_cb is not None:
                        try:
                            pct = float(m.group(1))
                            spd = (m.group(2) or "").strip()
                            sub = f"{int(round(pct))}% ({spd})" if spd else f"{int(round(pct))}%"
                            progress_cb(pct, 0, 0, sub)
                        except ValueError:
                            pass
        proc.wait(timeout=10)
        err_thread.join(timeout=2)
        err_str = ("".join(err_chunks) or "".join(out_chunks)).strip()
        return proc.returncode or 0, err_str
    except Exception as exc:
        try:
            proc.kill()
        except Exception:
            pass
        return 1, str(exc)




def _check_single_app_update(item: dict[str, Any], mock_map: dict[str, Any]) -> dict[str, Any]:
    """Check upstream for updates to a single registry item. Mutates item in place."""
    _detect_update_metadata(item)
    app_id = str(item.get("id", "")).strip()
    now_ts = int(time.time())
    item["lastCheckedAt"] = now_ts
    item["updateError"] = ""

    if app_id in mock_map and isinstance(mock_map[app_id], dict):
        m = mock_map[app_id]
        item["updateSupported"] = bool(m.get("updateSupported", True))
        if m.get("updateProtocol"):
            item["updateProtocol"] = str(m["updateProtocol"])
        if m.get("version"):
            item["version"] = str(m["version"])
        latest_v = str(m.get("latestVersion", item.get("version", ""))).strip()
        item["latestVersion"] = latest_v
        item["updateAvailable"] = bool(
            m.get("updateAvailable", _compare_versions(latest_v, str(item.get("version", ""))) > 0)
        )
        for k in ("downloadUrl", "remoteZsyncUrl", "remoteSha1", "remoteFilename", "rsyncUrl"):
            if k in m:
                item[k] = m[k]
        return item

    if not item.get("updateSupported"):
        item["updateAvailable"] = False
        return item

    protocol = str(item.get("updateProtocol", "")).lower()
    stored_p = Path(str(item.get("storedPath", "")))
    local_ver = str(item.get("version", "")).strip()

    try:
        if protocol == "zsync":
            upd_info = str(item.get("updInfo", "")).strip()
            remote_zsync_url = str(item.get("updateUrl", "")).strip()
            rel_tag = ""

            if not remote_zsync_url and upd_info.startswith("gh-releases-zsync|"):
                remote_zsync_url, rel_tag = _resolve_gh_releases_zsync_url(upd_info, stored_p.name)
                if not remote_zsync_url:
                    item["updateError"] = "Could not resolve remote .zsync asset from GitHub Releases."
                    item["updateAvailable"] = False
                    return item
            elif not remote_zsync_url and upd_info.startswith("zsync|"):
                remote_zsync_url = upd_info.split("|", 1)[1].strip()

            local_sha1 = _file_sha1(stored_p, item).lower()
            if not remote_zsync_url:
                zsync_s = str(item.get("zsyncPath", "")).strip()
                if zsync_s and Path(zsync_s).is_file():
                    zsync_p = Path(zsync_s)
                    local_hdr = _parse_zsync_header(zsync_p)
                    u = (local_hdr.get("zsync-url", "") or local_hdr.get("update-url", "") or local_hdr.get("url", "")).strip()
                    if u.startswith(("http://", "https://", "file://")):
                        remote_zsync_url = u if u.lower().endswith(".zsync") else f"{u}.zsync"
                    elif u:
                        cand_p = Path(u) if Path(u).is_absolute() else (zsync_p.parent / u)
                        hdr_sha1 = local_hdr.get("sha-1", "").strip().lower()
                        if u.lower().endswith(".zsync") and cand_p.is_file():
                            remote_zsync_url = cand_p.resolve().as_uri()
                        elif hdr_sha1 and local_sha1 and hdr_sha1 != local_sha1 and cand_p.is_file():
                            remote_zsync_url = zsync_p.resolve().as_uri()

            if not remote_zsync_url:
                # Local companion .zsync seed without a remote URL configured; treat as up to date locally
                if item.get("zsyncPath") and Path(str(item.get("zsyncPath"))).is_file() and not upd_info and not item.get("customUpdateSource"):
                    item["latestVersion"] = local_ver
                    item["updateAvailable"] = False
                    item["updateError"] = ""
                    return item
                item["updateError"] = "No remote .zsync URL configured or discovered."
                item["updateAvailable"] = False
                return item

            raw_head, final_zsync_url = _fetch_url_bytes(remote_zsync_url, max_bytes=8192, timeout=15.0)
            z_hdr = _parse_zsync_bytes(raw_head)
            remote_sha1 = z_hdr.get("sha-1", "").strip().lower()
            remote_fn = z_hdr.get("filename", "").strip()
            remote_target_url = z_hdr.get("url", "").strip()
            remote_ver = _extract_version_from_string(remote_fn) or _extract_version_from_string(rel_tag)

            if remote_target_url and not _is_ephemeral_cdn_url(remote_target_url):
                if not remote_target_url.startswith(("http://", "https://", "file://")):
                    payload_url = urllib.parse.urljoin(final_zsync_url, remote_target_url)
                else:
                    payload_url = remote_target_url
            else:
                payload_url = final_zsync_url[:-6] if final_zsync_url.lower().endswith(".zsync") else ""

            if remote_sha1 and local_sha1:
                if remote_sha1 == local_sha1:
                    is_avail = False
                    if remote_ver and (not local_ver or _compare_versions(remote_ver, local_ver) > 0):
                        item["version"] = remote_ver
                        local_ver = remote_ver
                else:
                    if remote_ver and local_ver and _compare_versions(remote_ver, local_ver) < 0:
                        is_avail = False
                    else:
                        is_avail = True
            elif remote_ver and local_ver:
                is_avail = _compare_versions(remote_ver, local_ver) > 0
            else:
                is_avail = False

            item["remoteZsyncUrl"] = final_zsync_url
            item["downloadUrl"] = payload_url
            item["remoteSha1"] = remote_sha1
            item["remoteFilename"] = remote_fn
            item["latestVersion"] = remote_ver or local_ver
            item["updateAvailable"] = is_avail
            return item

        if protocol == "rsync":
            rsync_bin = shutil.which("rsync")
            if not rsync_bin:
                item["updateError"] = "rsync is not installed."
                item["updateAvailable"] = False
                return item
            raw_rsync_src = str(item.get("rsyncUrl") or item.get("updateUrl") or item.get("customUpdateSource") or "").strip()
            rsync_src = _normalize_rsync_source(raw_rsync_src)
            if not rsync_src:
                item["updateError"] = "No rsync source configured."
                item["updateAvailable"] = False
                return item

            pkg_s = str(item.get("packageDir", "")).strip()
            is_local_dir = False
            if ":" not in rsync_src:
                try:
                    is_local_dir = Path(rsync_src).expanduser().is_dir()
                except Exception:
                    is_local_dir = False
            is_dir_sync = bool(pkg_s and Path(pkg_s).is_dir() and (rsync_src.endswith("/") or is_local_dir))
            if is_dir_sync:
                pkg_dir = Path(pkg_s)
                children = [p for p in pkg_dir.iterdir() if not p.name.startswith(".")]
                unwrapped_dir = (
                    children[0]
                    if (len(children) == 1 and children[0].is_dir() and children[0].name not in ("usr", "opt", "etc", "var"))
                    else pkg_dir
                )
                if is_local_dir and unwrapped_dir != pkg_dir and not (Path(rsync_src).expanduser() / unwrapped_dir.name).is_dir():
                    target_path = unwrapped_dir
                else:
                    target_path = pkg_dir
                rsync_src_arg = f"{rsync_src.rstrip('/')}/"
                cmd = [rsync_bin, "--dry-run", "--itemize-changes", "-rltDc", "--delete", rsync_src_arg, f"{target_path}/"]
            else:
                target_path = stored_p
                cmd = [rsync_bin, "--dry-run", "--itemize-changes", "-Ltpc", rsync_src, str(target_path)]

            res = subprocess.run(cmd, capture_output=True, text=True, timeout=20)
            if res.returncode != 0:
                item["updateError"] = (res.stderr or res.stdout or f"rsync exited with {res.returncode}").strip()
                item["updateAvailable"] = False
                return item

            changed_lines = [
                ln.strip()
                for ln in res.stdout.splitlines()
                if ln.strip() and (ln.startswith((">f", "cf", "*deleting", "<f")) or "f+" in ln[:11] or ("f." in ln[:11] and ln[:11] != ".f........."))
            ]
            # Filter out no-op attribute-only lines if size/time/checksum didn't change
            real_changes = [
                ln for ln in changed_lines
                if ln.startswith("*deleting") or (len(ln) >= 5 and any(c in ln[:11] for c in ("+", "c", "s", "t")))
            ]
            remote_ver = _extract_version_from_string(Path(rsync_src.rstrip("/")).name) or local_ver
            item["latestVersion"] = remote_ver
            item["downloadUrl"] = rsync_src
            item["updateAvailable"] = len(real_changes) > 0
            return item

        if protocol == "tauri":
            manifest_url = str(item.get("updateUrl", "")).strip()
            if not manifest_url:
                item["updateError"] = "No Tauri latest.json endpoint configured."
                item["updateAvailable"] = False
                return item
            raw_json, _ = _fetch_url_bytes(manifest_url, timeout=15.0)
            data = json.loads(raw_json.decode("utf-8", errors="ignore"))
            remote_ver = str(data.get("version", "")).strip().lstrip("vV")
            platforms = data.get("platforms", {}) if isinstance(data.get("platforms"), dict) else {}
            dl_url = ""
            for p_key in ("linux-x86_64-appimage", "linux-x86_64", "linux-amd64", "linux"):
                if isinstance(platforms.get(p_key), dict) and platforms[p_key].get("url"):
                    dl_url = str(platforms[p_key]["url"]).strip()
                    break
            if not dl_url:
                for p_val in platforms.values():
                    if isinstance(p_val, dict) and str(p_val.get("url", "")).lower().endswith((".appimage", ".appimage.tar.gz")):
                        dl_url = str(p_val["url"]).strip()
                        break

            is_avail = False
            if local_ver and remote_ver:
                is_avail = _compare_versions(remote_ver, local_ver) > 0
            elif remote_ver and dl_url and stored_p.is_file():
                head_info = _fetch_url_head(dl_url)
                if head_info["size"] > 0 and head_info["size"] == stored_p.stat().st_size:
                    item["version"] = remote_ver
                    local_ver = remote_ver
                    is_avail = False
                else:
                    is_avail = True

            item["latestVersion"] = remote_ver or local_ver
            item["downloadUrl"] = dl_url
            item["updateAvailable"] = bool(is_avail and dl_url)
            return item

        if protocol == "electron-builder":
            manifest_url = str(item.get("updateUrl", "")).strip()
            if not manifest_url:
                item["updateError"] = "No electron-builder latest-linux.yml URL configured."
                item["updateAvailable"] = False
                return item
            raw_yml, final_yml_url = _fetch_url_bytes(manifest_url, timeout=15.0)
            yml = _parse_simple_yaml(raw_yml.decode("utf-8", errors="ignore"))
            remote_ver = yml.get("version", "").strip().lstrip("vV")
            rel_path = yml.get("path", "").strip()
            sha512 = yml.get("sha512", "").strip()
            dl_url = urllib.parse.urljoin(final_yml_url, rel_path) if rel_path else ""

            is_avail = _compare_versions(remote_ver, local_ver) > 0 if (remote_ver and local_ver) else False
            item["latestVersion"] = remote_ver or local_ver
            item["downloadUrl"] = dl_url
            item["remoteSha512"] = sha512
            item["remoteFilename"] = Path(urllib.parse.urlparse(dl_url).path).name if dl_url else ""
            item["updateAvailable"] = bool(is_avail and dl_url)
            return item

    except Exception as exc:
        item["updateError"] = str(exc)
        item["updateAvailable"] = False
    return item


def check_updates(target_ids: list[str] | None = None) -> dict[str, Any]:
    _ensure_dirs()
    registry = _load_registry()
    mock_raw = os.environ.get("ALIS_PORTABLE_APPS_MOCK_UPDATES", "").strip()
    mock_map: dict[str, Any] = {}
    if mock_raw:
        try:
            mock_map = json.loads(mock_raw)
        except Exception:
            mock_map = {}

    targets = {t.strip() for t in (target_ids or []) if t.strip() and t.strip() not in ("--all", "all")}
    checked: list[str] = []
    to_check: list[dict[str, Any]] = []

    for item in registry:
        _detect_update_metadata(item)
        app_id = str(item.get("id", "")).strip()
        if targets and app_id not in targets:
            continue
        if not targets and not item.get("updateSupported") and app_id not in mock_map:
            continue
        to_check.append(item)
        checked.append(app_id)

    total_to_check = len(to_check)
    if total_to_check == 1:
        single_id = str(to_check[0].get("id", "")).strip()
        single_name = str(to_check[0].get("name", single_id)).strip()
        _emit_progress(
            "check-updates",
            percent=15,
            detail=f"Checking {single_name} for updates…",
            app_id=single_id,
            app_name=single_name,
            stage="checking",
        )
        _check_single_app_update(to_check[0], mock_map)
        _emit_progress(
            "check-updates",
            percent=100,
            detail=f"Finished checking {single_name}.",
            app_id=single_id,
            app_name=single_name,
            stage="done",
        )
    elif total_to_check > 1:
        _emit_progress(
            "check-updates",
            percent=5,
            detail=f"Checking {total_to_check} applications for updates…",
            stage="checking",
        )
        done_count = 0
        with concurrent.futures.ThreadPoolExecutor(max_workers=min(6, total_to_check)) as pool:
            future_map = {pool.submit(_check_single_app_update, item, mock_map): item for item in to_check}
            for fut in concurrent.futures.as_completed(future_map):
                fut.result()
                done_count += 1
                item = future_map[fut]
                item_id = str(item.get("id", "")).strip()
                item_name = str(item.get("name", item_id)).strip()
                pct = int(round((done_count / total_to_check) * 100))
                _emit_progress(
                    "check-updates",
                    percent=pct,
                    detail=f"Checked {done_count} / {total_to_check} applications ({item_name})",
                    app_id=item_id,
                    app_name=item_name,
                    stage="checking",
                )

    check_errors = [
        f"{item.get('name', item.get('id', ''))}: {item['updateError']}"
        for item in to_check
        if str(item.get("updateError", "")).strip()
    ]
    _save_registry(registry)
    listed = cmd_list()["apps"]
    avail_count = sum(1 for a in listed if a.get("updateAvailable"))
    all_failed = len(to_check) > 0 and len(check_errors) == len(to_check) and avail_count == 0
    result = {
        "ok": not all_failed,
        "checked": checked,
        "checkErrors": check_errors,
        "error": "; ".join(check_errors) if check_errors else "",
        "updatesAvailable": avail_count,
        "apps": listed,
    }
    _complete_operation_status("check-updates", result)
    return result


def _apply_single_app_update(item: dict[str, Any], progress_cb: Any = None) -> tuple[bool, str]:
    """Perform the update for a single registry item. Returns (success, error_message)."""
    slug = str(item.get("id", "")).strip()
    app_name = str(item.get("name") or slug).strip()
    kind = str(item.get("kind", "appimage")).lower()
    protocol = str(item.get("updateProtocol", "")).lower()
    stored_p = Path(str(item.get("storedPath", "")))
    old_zsync_s = str(item.get("zsyncPath", "")).strip()
    old_zsync_p = Path(old_zsync_s) if old_zsync_s else None
    custom_upd_src = str(item.get("customUpdateSource", "")).strip()

    max_pct_so_far = 0.0

    def _report(stage: str, pct: float, detail: str, done_b: int = 0, total_b: int = 0) -> None:
        nonlocal max_pct_so_far
        clamped_pct = max(max_pct_so_far, max(0.0, min(100.0, pct)))
        max_pct_so_far = clamped_pct
        if progress_cb is not None:
            progress_cb(stage, clamped_pct, detail, done_b, total_b)

    sim_ms = 0
    try:
        sim_ms = int(os.environ.get("ALIS_PORTABLE_APPS_SIMULATE_UPDATE_MS", "0") or "0")
    except ValueError:
        sim_ms = 0

    def _maybe_simulate_step(stage: str, pct: float, detail: str) -> None:
        _report(stage, pct, detail)
        if sim_ms > 0:
            time.sleep(max(0.02, (sim_ms / 1000.0) / 5.0))

    try:
        with tempfile.TemporaryDirectory(prefix=f"alis-update-{slug}-") as td:
            tmp_dir = Path(td)
            _maybe_simulate_step("preparing", 6.0, f"Preparing update for {app_name}…")

            if protocol == "zsync":
                upd_info = str(item.get("updInfo", "")).strip()
                remote_zsync_url = str(item.get("remoteZsyncUrl") or item.get("updateUrl") or "").strip()
                if _is_ephemeral_cdn_url(remote_zsync_url):
                    remote_zsync_url = ""
                if not remote_zsync_url and upd_info.startswith("gh-releases-zsync|"):
                    remote_zsync_url, _ = _resolve_gh_releases_zsync_url(upd_info, stored_p.name)
                elif not remote_zsync_url and upd_info.startswith("zsync|"):
                    remote_zsync_url = upd_info.split("|", 1)[1].strip()
                if not remote_zsync_url:
                    return False, f"No remote .zsync URL available for {slug}."

                _maybe_simulate_step("resolving", 12.0, f"Fetching .zsync metadata for {app_name}…")
                try:
                    zsync_bytes, final_zsync_url = _fetch_url_bytes(remote_zsync_url, timeout=30.0)
                except Exception:
                    if upd_info.startswith("gh-releases-zsync|"):
                        fresh_zsync_url, _ = _resolve_gh_releases_zsync_url(upd_info, stored_p.name)
                        if fresh_zsync_url and fresh_zsync_url != remote_zsync_url:
                            remote_zsync_url = fresh_zsync_url
                            item["remoteZsyncUrl"] = fresh_zsync_url
                            zsync_bytes, final_zsync_url = _fetch_url_bytes(remote_zsync_url, timeout=30.0)
                        else:
                            raise
                    else:
                        raise
                z_hdr = _parse_zsync_bytes(zsync_bytes)
                expected_sha1 = z_hdr.get("sha-1", "").strip().lower()
                expected_len_s = z_hdr.get("length", "").strip()
                expected_len = int(expected_len_s) if expected_len_s.isdigit() else 0
                remote_fn = Path(z_hdr.get("filename", "") or str(item.get("remoteFilename", "")) or stored_p.name).name
                if not remote_fn.lower().endswith(".appimage"):
                    remote_fn = stored_p.name

                hdr_url = z_hdr.get("url", "").strip()
                if hdr_url and not _is_ephemeral_cdn_url(hdr_url):
                    payload_url = (
                        hdr_url
                        if hdr_url.startswith(("http://", "https://", "file://"))
                        else urllib.parse.urljoin(final_zsync_url, hdr_url)
                    )
                else:
                    dl_cand = str(item.get("downloadUrl", "")).strip()
                    if dl_cand and not _is_ephemeral_cdn_url(dl_cand):
                        payload_url = dl_cand
                    elif final_zsync_url.lower().endswith(".zsync"):
                        payload_url = final_zsync_url[:-6]
                    else:
                        payload_url = ""

                if not payload_url:
                    return False, f"Could not resolve AppImage download URL from .zsync for {slug}."

                def _on_dl_progress(dl_pct: float, done_b: int, total_b: int, sub_detail: str) -> None:
                    mapped = 15.0 + max(0.0, min(100.0, dl_pct)) * 0.70
                    _report("downloading", mapped, f"Updating {app_name} — {sub_detail}", done_b, total_b)

                _maybe_simulate_step("downloading", 18.0, f"Syncing delta blocks for {app_name}…")
                staged_ai = tmp_dir / remote_fn
                used_zsync = _run_zsync_via_local_proxy(
                    seed_appimage=stored_p,
                    zsync_raw_bytes=zsync_bytes,
                    payload_url=payload_url,
                    expected_length=expected_len,
                    dest_out=staged_ai,
                    progress_cb=_on_dl_progress,
                )
                if not used_zsync:
                    _download_url_to_file(payload_url, staged_ai, progress_cb=_on_dl_progress)

                _maybe_simulate_step("downloading", 60.0, f"Downloaded update payload for {app_name}…")
                if not staged_ai.is_file():
                    return False, f"Failed to download updated AppImage for {slug}."

                _maybe_simulate_step("verifying", 86.0, f"Verifying SHA-1 checksum for {app_name}…")
                actual_sha1 = _file_sha1(staged_ai).lower()
                if expected_sha1 and actual_sha1 != expected_sha1:
                    return False, f"Checksum mismatch for {slug} (expected {expected_sha1}, got {actual_sha1})."

                _maybe_simulate_step("installing", 94.0, f"Installing updated {app_name}…")
                dest_ai = _appimages_dir() / remote_fn
                shutil.move(str(staged_ai), str(dest_ai))
                dest_ai.chmod(dest_ai.stat().st_mode | 0o755)

                dest_zs = _appimages_dir() / f"{remote_fn}.zsync"
                dest_zs.write_bytes(zsync_bytes)

                if stored_p.is_file() and stored_p.resolve() != dest_ai.resolve():
                    try:
                        stored_p.unlink()
                    except OSError:
                        pass
                if old_zsync_p and old_zsync_p.is_file() and old_zsync_p.resolve() != dest_zs.resolve():
                    try:
                        old_zsync_p.unlink()
                    except OSError:
                        pass

                meta, icon_path = _extract_appimage_metadata(dest_ai, slug)
                name = meta.get("Name") or str(item.get("name") or _human_title(dest_ai.name))
                comment = meta.get("Comment") or ""
                categories = meta.get("Categories", "Utility;Application;")
                wm_class = meta.get("StartupWMClass", slug)
                desktop_file = _write_desktop_entry(
                    slug=slug,
                    name=name,
                    exec_path=dest_ai,
                    icon_path=icon_path or str(item.get("iconPath", "")),
                    comment=comment,
                    categories=categories,
                    wm_class=wm_class,
                    zsync_path=str(dest_zs),
                    mime_type=meta.get("MimeType", ""),
                    update_source=custom_upd_src,
                )

                item["name"] = name
                item["storedPath"] = str(dest_ai)
                item["execPath"] = str(dest_ai)
                item["zsyncPath"] = str(dest_zs)
                item["hasZsync"] = True
                if icon_path:
                    item["iconPath"] = icon_path
                item["desktopFile"] = str(desktop_file)
                item["version"] = str(item.get("latestVersion") or _extract_version_from_string(remote_fn) or item.get("version", ""))
                item["updateAvailable"] = False
                item["updateError"] = ""
                item["updatedAt"] = int(time.time())
                item.pop("_metaSig", None)
                item.pop("_sha1Sig", None)
                _detect_update_metadata(item)
                _report("done", 100.0, f"Updated {name} to v{item['version']}.")
                return True, ""

            if protocol == "rsync":
                rsync_bin = shutil.which("rsync")
                if not rsync_bin:
                    return False, "rsync is not installed."
                raw_rsync_src = str(item.get("downloadUrl") or item.get("rsyncUrl") or item.get("updateUrl") or custom_upd_src).strip()
                rsync_src = _normalize_rsync_source(raw_rsync_src)
                if not rsync_src:
                    return False, f"No rsync source configured for {slug}."

                def _on_rsync_progress(rs_pct: float, done_b: int, total_b: int, sub_detail: str) -> None:
                    mapped = 15.0 + max(0.0, min(100.0, rs_pct)) * 0.70
                    _report("syncing", mapped, f"Syncing {app_name} — {sub_detail}", done_b, total_b)

                _maybe_simulate_step("syncing", 18.0, f"Synchronizing {app_name} via rsync…")
                pkg_s = str(item.get("packageDir", "")).strip()
                is_local_dir = False
                if ":" not in rsync_src:
                    try:
                        is_local_dir = Path(rsync_src).expanduser().is_dir()
                    except Exception:
                        is_local_dir = False
                is_dir_sync = bool(pkg_s and Path(pkg_s).is_dir() and (rsync_src.endswith("/") or is_local_dir))
                if is_dir_sync:
                    pkg_dir = Path(pkg_s)
                    children = [p for p in pkg_dir.iterdir() if not p.name.startswith(".")]
                    unwrapped_dir = (
                        children[0]
                        if (len(children) == 1 and children[0].is_dir() and children[0].name not in ("usr", "opt", "etc", "var"))
                        else pkg_dir
                    )
                    if is_local_dir and unwrapped_dir != pkg_dir and not (Path(rsync_src).expanduser() / unwrapped_dir.name).is_dir():
                        target_dir = unwrapped_dir
                    else:
                        target_dir = pkg_dir
                    rsync_src_arg = f"{rsync_src.rstrip('/')}/"
                    rc, err_out = _run_rsync_with_progress(
                        [rsync_bin, "-rltDc", "--delete", "--info=progress2", rsync_src_arg, f"{target_dir}/"],
                        timeout=180,
                        progress_cb=_on_rsync_progress,
                    )
                    if rc != 0:
                        return False, (err_out or f"rsync failed with {rc}").strip()
                    _maybe_simulate_step("installing", 90.0, f"Refreshing desktop entry for {app_name}…")
                    exec_path, meta, icon_path = _find_tar_executable_and_icon(pkg_dir, slug)
                    if exec_path is not None:
                        item["execPath"] = str(exec_path)
                        desktop_file = _write_desktop_entry(
                            slug=slug,
                            name=meta.get("Name") or str(item.get("name", slug)),
                            exec_path=exec_path,
                            icon_path=icon_path or str(item.get("iconPath", "")),
                            comment=meta.get("Comment", ""),
                            categories=meta.get("Categories", "Utility;Application;"),
                            wm_class=meta.get("StartupWMClass", slug),
                            mime_type=meta.get("MimeType", ""),
                            update_source=custom_upd_src,
                        )
                        item["desktopFile"] = str(desktop_file)
                else:
                    src_name = Path(rsync_src.rstrip("/")).name
                    target_name = src_name if any(src_name.lower().endswith(s.lower()) for s in ARCHIVE_SUFFIXES) else stored_p.name
                    staged_file = tmp_dir / target_name
                    if stored_p.is_file():
                        shutil.copy2(stored_p, staged_file)
                    rc, err_out = _run_rsync_with_progress(
                        [rsync_bin, "-Ltc", "--inplace", "--partial", "--info=progress2", rsync_src, str(staged_file)],
                        timeout=180,
                        progress_cb=_on_rsync_progress,
                    )
                    if rc != 0 or not staged_file.is_file():
                        return False, (err_out or f"rsync failed with {rc}").strip()

                    _maybe_simulate_step("installing", 90.0, f"Installing synced {app_name}…")
                    if kind == "appimage":
                        dest_ai = _appimages_dir() / target_name
                        shutil.move(str(staged_file), str(dest_ai))
                        dest_ai.chmod(dest_ai.stat().st_mode | 0o755)
                        if stored_p.is_file() and stored_p.resolve() != dest_ai.resolve():
                            try:
                                stored_p.unlink()
                            except OSError:
                                pass
                        meta, icon_path = _extract_appimage_metadata(dest_ai, slug)
                        name = meta.get("Name") or str(item.get("name") or _human_title(dest_ai.name))
                        desktop_file = _write_desktop_entry(
                            slug=slug,
                            name=name,
                            exec_path=dest_ai,
                            icon_path=icon_path or str(item.get("iconPath", "")),
                            comment=meta.get("Comment", ""),
                            categories=meta.get("Categories", "Utility;Application;"),
                            wm_class=meta.get("StartupWMClass", slug),
                            zsync_path=str(item.get("zsyncPath", "")),
                            mime_type=meta.get("MimeType", ""),
                            update_source=custom_upd_src,
                        )
                        item["storedPath"] = str(dest_ai)
                        item["execPath"] = str(dest_ai)
                        if icon_path:
                            item["iconPath"] = icon_path
                        item["desktopFile"] = str(desktop_file)
                    else:
                        dest_arc = _archives_dir() / target_name
                        shutil.move(str(staged_file), str(dest_arc))
                        if stored_p.is_file() and stored_p.resolve() != dest_arc.resolve():
                            try:
                                stored_p.unlink()
                            except OSError:
                                pass
                        pkg_dir = _packages_dir() / slug
                        if pkg_dir.exists():
                            shutil.rmtree(pkg_dir, ignore_errors=True)
                        pkg_dir.mkdir(parents=True, exist_ok=True)
                        _safe_extract_tar(dest_arc, pkg_dir)
                        exec_path, meta, icon_path = _find_tar_executable_and_icon(pkg_dir, slug)
                        if exec_path is None:
                            return False, f"Could not locate executable in updated archive {target_name}."
                        desktop_file = _write_desktop_entry(
                            slug=slug,
                            name=meta.get("Name") or str(item.get("name", slug)),
                            exec_path=exec_path,
                            icon_path=icon_path or str(item.get("iconPath", "")),
                            comment=meta.get("Comment", ""),
                            categories=meta.get("Categories", "Utility;Application;"),
                            wm_class=meta.get("StartupWMClass", slug),
                            mime_type=meta.get("MimeType", ""),
                            update_source=custom_upd_src,
                        )
                        item["storedPath"] = str(dest_arc)
                        item["execPath"] = str(exec_path)
                        item["packageDir"] = str(pkg_dir)
                        if icon_path:
                            item["iconPath"] = icon_path
                        item["desktopFile"] = str(desktop_file)

                if item.get("latestVersion"):
                    item["version"] = str(item["latestVersion"])
                item["updateAvailable"] = False
                item["updateError"] = ""
                item["updatedAt"] = int(time.time())
                item.pop("_metaSig", None)
                item.pop("_sha1Sig", None)
                _detect_update_metadata(item)
                _report("done", 100.0, f"Updated {app_name} to v{item.get('version', '')}.")
                return True, ""

            if protocol in ("tauri", "electron-builder"):
                dl_url = str(item.get("downloadUrl", "")).strip()
                if not dl_url:
                    return False, f"No download URL available for {slug}."
                url_name = Path(urllib.parse.unquote(urllib.parse.urlparse(dl_url).path)).name or stored_p.name
                staged_dl = tmp_dir / url_name

                def _on_http_progress(dl_pct: float, done_b: int, total_b: int, sub_detail: str) -> None:
                    mapped = 15.0 + max(0.0, min(100.0, dl_pct)) * 0.70
                    _report("downloading", mapped, f"Downloading {app_name} — {sub_detail}", done_b, total_b)

                _maybe_simulate_step("downloading", 18.0, f"Downloading {app_name} package…")
                _download_url_to_file(dl_url, staged_dl, progress_cb=_on_http_progress)
                _maybe_simulate_step("downloading", 65.0, f"Downloaded {app_name} package…")
                if not staged_dl.is_file():
                    return False, f"Failed to download update package for {slug}."

                expected_sha512 = str(item.get("remoteSha512", "")).strip()
                if expected_sha512:
                    _maybe_simulate_step("verifying", 86.0, f"Verifying SHA-512 checksum for {app_name}…")
                    h512 = hashlib.sha512()
                    with staged_dl.open("rb") as f:
                        while chunk := f.read(1024 * 1024):
                            h512.update(chunk)
                    b64_digest = base64.b64encode(h512.digest()).decode("ascii")
                    hex_digest = h512.hexdigest().lower()
                    if expected_sha512 not in (b64_digest, hex_digest) and expected_sha512.lower() != hex_digest:
                        return False, f"SHA-512 checksum mismatch for {slug}."

                _maybe_simulate_step("installing", 93.0, f"Extracting and installing {app_name}…")
                if kind == "appimage":
                    final_staged_ai = staged_dl
                    if url_name.lower().endswith((".tar.gz", ".tgz")):
                        extract_sub = tmp_dir / "extracted_bundle"
                        extract_sub.mkdir(parents=True, exist_ok=True)
                        _safe_extract_tar(staged_dl, extract_sub)
                        found_ais = list(extract_sub.rglob("*.AppImage")) + list(extract_sub.rglob("*.appimage"))
                        if not found_ais:
                            return False, f"No .AppImage found inside {url_name}."
                        final_staged_ai = found_ais[0]

                    dest_name = final_staged_ai.name if final_staged_ai.name.lower().endswith(".appimage") else stored_p.name
                    dest_ai = _appimages_dir() / dest_name
                    shutil.move(str(final_staged_ai), str(dest_ai))
                    dest_ai.chmod(dest_ai.stat().st_mode | 0o755)
                    if stored_p.is_file() and stored_p.resolve() != dest_ai.resolve():
                        try:
                            stored_p.unlink()
                        except OSError:
                            pass
                    meta, icon_path = _extract_appimage_metadata(dest_ai, slug)
                    name = meta.get("Name") or str(item.get("name") or _human_title(dest_ai.name))
                    desktop_file = _write_desktop_entry(
                        slug=slug,
                        name=name,
                        exec_path=dest_ai,
                        icon_path=icon_path or str(item.get("iconPath", "")),
                        comment=meta.get("Comment", ""),
                        categories=meta.get("Categories", "Utility;Application;"),
                        wm_class=meta.get("StartupWMClass", slug),
                        zsync_path=str(item.get("zsyncPath", "")),
                        mime_type=meta.get("MimeType", ""),
                        update_source=custom_upd_src,
                    )
                    item["storedPath"] = str(dest_ai)
                    item["execPath"] = str(dest_ai)
                    if icon_path:
                        item["iconPath"] = icon_path
                    item["desktopFile"] = str(desktop_file)
                else:
                    dest_arc = _archives_dir() / url_name
                    shutil.move(str(staged_dl), str(dest_arc))
                    if stored_p.is_file() and stored_p.resolve() != dest_arc.resolve():
                        try:
                            stored_p.unlink()
                        except OSError:
                            pass
                    pkg_dir = _packages_dir() / slug
                    if pkg_dir.exists():
                        shutil.rmtree(pkg_dir, ignore_errors=True)
                    pkg_dir.mkdir(parents=True, exist_ok=True)
                    _safe_extract_tar(dest_arc, pkg_dir)
                    exec_path, meta, icon_path = _find_tar_executable_and_icon(pkg_dir, slug)
                    if exec_path is None:
                        return False, f"Could not locate executable in updated archive {url_name}."
                    desktop_file = _write_desktop_entry(
                        slug=slug,
                        name=meta.get("Name") or str(item.get("name", slug)),
                        exec_path=exec_path,
                        icon_path=icon_path or str(item.get("iconPath", "")),
                        comment=meta.get("Comment", ""),
                        categories=meta.get("Categories", "Utility;Application;"),
                        wm_class=meta.get("StartupWMClass", slug),
                        mime_type=meta.get("MimeType", ""),
                        update_source=custom_upd_src,
                    )
                    item["storedPath"] = str(dest_arc)
                    item["execPath"] = str(exec_path)
                    item["packageDir"] = str(pkg_dir)
                    if icon_path:
                        item["iconPath"] = icon_path
                    item["desktopFile"] = str(desktop_file)

                if item.get("latestVersion"):
                    item["version"] = str(item["latestVersion"])
                item["updateAvailable"] = False
                item["updateError"] = ""
                item["updatedAt"] = int(time.time())
                item.pop("_metaSig", None)
                item.pop("_sha1Sig", None)
                _detect_update_metadata(item)
                _report("done", 100.0, f"Updated {app_name} to v{item.get('version', '')}.")
                return True, ""

            return False, f"Unsupported update protocol '{protocol}' for {slug}."
    except Exception as exc:
        return False, str(exc)


def update_apps(target_ids: list[str] | None = None) -> dict[str, Any]:
    _ensure_dirs()
    registry = _load_registry()
    mock_raw = os.environ.get("ALIS_PORTABLE_APPS_MOCK_UPDATES", "").strip()
    mock_map: dict[str, Any] = {}
    if mock_raw:
        try:
            mock_map = json.loads(mock_raw)
        except Exception:
            mock_map = {}

    targets = {t.strip() for t in (target_ids or []) if t.strip() and t.strip() not in ("--all", "all")}
    updated_ids: list[str] = []
    errors: list[str] = []
    matched_targets: set[str] = set()
    candidates: list[dict[str, Any]] = []

    for item in registry:
        _detect_update_metadata(item)
    any_already_available = not targets and any(bool(it.get("updateAvailable")) for it in registry)

    for item in registry:
        app_id = str(item.get("id", "")).strip()
        if targets and app_id not in targets:
            continue
        matched_targets.add(app_id)
        if not targets:
            if any_already_available:
                if not item.get("updateAvailable"):
                    continue
            elif not item.get("updateAvailable") and not item.get("updateSupported"):
                continue
        candidates.append(item)

    total_candidates = max(1, len(candidates))
    for idx, item in enumerate(candidates):
        app_id = str(item.get("id", "")).strip()
        app_name = str(item.get("name", app_id)).strip()
        slice_start = (idx / total_candidates) * 100.0
        slice_span = 100.0 / total_candidates
        prefix = f"[{idx + 1}/{total_candidates}] " if total_candidates > 1 else ""

        item["updateError"] = ""
        proto = str(item.get("updateProtocol", "")).lower()
        needs_check = not item.get("updateAvailable")
        if proto == "zsync":
            if (
                not item.get("remoteZsyncUrl")
                or not item.get("downloadUrl")
                or _is_ephemeral_cdn_url(str(item.get("remoteZsyncUrl", "")))
                or _is_ephemeral_cdn_url(str(item.get("downloadUrl", "")))
            ):
                needs_check = True
        elif proto == "rsync":
            if not item.get("rsyncUrl") and not item.get("downloadUrl"):
                needs_check = True
        else:
            if not item.get("downloadUrl") or _is_ephemeral_cdn_url(str(item.get("downloadUrl", ""))):
                needs_check = True

        if needs_check:
            _emit_progress(
                "update",
                percent=slice_start + slice_span * 0.03,
                detail=f"{prefix}Checking update metadata for {app_name}…",
                app_id=app_id,
                app_name=app_name,
                stage="checking",
            )
            _check_single_app_update(item, mock_map)

        if str(item.get("updateError", "")).strip():
            errors.append(f"{item.get('name', app_id)}: {item['updateError']}")
            continue

        if not item.get("updateAvailable"):
            continue

        def _item_progress(
            stage: str,
            item_pct: float,
            detail: str,
            done_b: int = 0,
            total_b: int = 0,
            _aid: str = app_id,
            _aname: str = app_name,
            _sstart: float = slice_start,
            _sspan: float = slice_span,
            _pfx: str = prefix,
        ) -> None:
            overall = _sstart + max(0.0, min(100.0, item_pct)) * (_sspan / 100.0)
            _emit_progress(
                "update",
                percent=overall,
                detail=f"{_pfx}{detail}",
                app_id=_aid,
                app_name=_aname,
                stage=stage,
                bytes_done=done_b,
                bytes_total=total_b,
            )

        ok, err_msg = _apply_single_app_update(item, progress_cb=_item_progress)
        if ok:
            updated_ids.append(app_id)
            _save_registry(registry)
        else:
            item["updateError"] = err_msg
            errors.append(f"{item.get('name', app_id)}: {err_msg}")
            _save_registry(registry)

    for missing in sorted(targets - matched_targets):
        errors.append(f"Application '{missing}' not found.")

    _save_registry(registry)
    listed = cmd_list()["apps"]
    result = {
        "ok": len(errors) == 0,
        "updated": updated_ids,
        "error": "; ".join(errors) if errors else "",
        "updatesAvailable": sum(1 for a in listed if a.get("updateAvailable")),
        "apps": listed,
    }
    _complete_operation_status("update", result)
    return result


def set_update_source(app_id: str, source_url: str) -> dict[str, Any]:
    target = app_id.strip()
    src = source_url.strip()
    registry = _load_registry()
    found = False
    for item in registry:
        if str(item.get("id", "")).strip() == target:
            found = True
            item["customUpdateSource"] = src
            if _is_rsync_source(src):
                item["rsyncUrl"] = _normalize_rsync_source(src)
            else:
                item.pop("rsyncUrl", None)
            item.pop("_metaSig", None)
            _detect_update_metadata(item)
            desktop_s = str(item.get("desktopFile", "")).strip()
            if desktop_s and Path(desktop_s).is_file():
                try:
                    d_meta = _parse_desktop_text(Path(desktop_s).read_text(encoding="utf-8", errors="ignore"))
                    _write_desktop_entry(
                        slug=target,
                        name=d_meta.get("Name") or str(item.get("name", target)),
                        exec_path=Path(str(item.get("execPath", ""))),
                        icon_path=str(item.get("iconPath", "")),
                        comment=d_meta.get("Comment", ""),
                        categories=d_meta.get("Categories", "Utility;Application;"),
                        wm_class=d_meta.get("StartupWMClass", target),
                        zsync_path=str(item.get("zsyncPath", "")),
                        mime_type=d_meta.get("MimeType", ""),
                        update_source=src,
                    )
                except Exception:
                    pass
            break
    if not found:
        return {"ok": False, "error": f"Application '{target}' not found.", "apps": cmd_list()["apps"]}
    _save_registry(registry)
    return {"ok": True, "apps": cmd_list()["apps"]}


def cmd_list() -> dict[str, Any]:
    _repair_managed_desktop_entries()
    registry = _load_registry()
    cleaned: list[dict[str, Any]] = []
    dirty = False
    for item in registry:
        if _detect_update_metadata(item):
            dirty = True
        exec_p = Path(str(item.get("execPath", "")))
        stored_p = Path(str(item.get("storedPath", "")))
        zsync_s = str(item.get("zsyncPath", "")).strip()
        has_zsync = bool(zsync_s and Path(zsync_s).is_file())
        item_copy = dict(item)
        item_copy["installed"] = exec_p.exists() or stored_p.exists()
        item_copy["hasZsync"] = has_zsync
        cleaned.append(item_copy)
    if dirty:
        try:
            _save_registry(registry)
        except Exception:
            pass
    cleaned.sort(key=lambda x: str(x.get("name", "")).lower())
    return {
        "ok": True,
        "appimagesDir": str(_appimages_dir()),
        "archivesDir": str(_archives_dir()),
        "packagesDir": str(_packages_dir()),
        "desktopDir": str(_desktop_dir()),
        "updatesAvailable": sum(1 for a in cleaned if a.get("updateAvailable")),
        "apps": cleaned,
    }


def _consume_unconsumed_result(st: dict[str, Any]) -> dict[str, Any] | None:
    res = st.get("result")
    if not isinstance(res, dict):
        return None
    st_copy = dict(st)
    st_copy["unconsumedResult"] = False
    _write_operation_status(st_copy)
    res_copy = dict(res)
    res_copy["apps"] = cmd_list()["apps"]
    return res_copy


def _attach_to_running_worker() -> dict[str, Any] | None:
    st = _read_operation_status()
    pid = int(st.get("pid", 0) or 0)
    if not st.get("running"):
        if st.get("unconsumedResult"):
            return _consume_unconsumed_result(st)
        return None
    if not _is_worker_alive(pid):
        st_dead = dict(st)
        st_dead["running"] = False
        st_dead["unconsumedResult"] = False
        _write_operation_status(st_dead)
        return None

    initial_apps = cmd_list()["apps"]
    _emit_progress(
        action=str(st.get("action", "update")),
        percent=int(st.get("percent", -1)),
        detail=str(st.get("detail", "Operation in progress…")),
        app_id=str(st.get("appId", "")),
        app_name=str(st.get("appName", "")),
        stage=str(st.get("stage", "")),
        bytes_done=int(st.get("bytesDone", 0) or 0),
        bytes_total=int(st.get("bytesTotal", 0) or 0),
        include_apps=initial_apps,
        write_status_file=False,
    )
    last_sig = (st.get("updatedAt"), st.get("percent"), st.get("detail"), st.get("appId"))
    while True:
        time.sleep(0.08)
        st = _read_operation_status()
        if not st.get("running"):
            if st.get("unconsumedResult"):
                consumed = _consume_unconsumed_result(st)
                if consumed is not None:
                    return consumed
            res = st.get("result")
            if isinstance(res, dict):
                return res
            return cmd_list()
        cur_pid = int(st.get("pid", 0) or 0)
        if not _is_worker_alive(cur_pid):
            st_dead = dict(st)
            st_dead["running"] = False
            st_dead["unconsumedResult"] = False
            _write_operation_status(st_dead)
            return cmd_list()
        sig = (st.get("updatedAt"), st.get("percent"), st.get("detail"), st.get("appId"))
        if sig != last_sig:
            last_sig = sig
            _emit_progress(
                action=str(st.get("action", "update")),
                percent=int(st.get("percent", -1)),
                detail=str(st.get("detail", "")),
                app_id=str(st.get("appId", "")),
                app_name=str(st.get("appName", "")),
                stage=str(st.get("stage", "")),
                bytes_done=int(st.get("bytesDone", 0) or 0),
                bytes_total=int(st.get("bytesTotal", 0) or 0),
                write_status_file=False,
            )


def _run_detached_bg_survive(action_name: str, fn: Any, rest: list[str]) -> dict[str, Any]:
    global _PROGRESS_PIPE_FD, _PROGRESS_PIPE_BROKEN, _LAUNCHER_PID
    launcher_pid = os.getpid()
    r_fd, w_fd = os.pipe()
    worker_pid = os.fork()
    if worker_pid == 0:
        # Detached background worker: immune to parent QProcess SIGKILL when standalone Settings closes
        try:
            os.close(r_fd)
        except OSError:
            pass
        _PROGRESS_PIPE_FD = w_fd
        _PROGRESS_PIPE_BROKEN = False
        _LAUNCHER_PID = launcher_pid
        try:
            signal.signal(signal.SIGHUP, signal.SIG_IGN)
            signal.signal(signal.SIGPIPE, signal.SIG_IGN)
        except Exception:
            pass
        try:
            os.setsid()
        except OSError:
            pass
        try:
            devnull_fd = os.open(os.devnull, os.O_RDWR)
            os.dup2(devnull_fd, 0)
            os.dup2(devnull_fd, 1)
            os.dup2(devnull_fd, 2)
            if devnull_fd > 2:
                os.close(devnull_fd)
        except OSError:
            pass
        try:
            fn(rest)
        except Exception as exc:
            _complete_operation_status(
                action_name,
                {"ok": False, "error": str(exc), "apps": cmd_list()["apps"]},
            )
        finally:
            if _PROGRESS_PIPE_FD >= 0:
                try:
                    os.close(_PROGRESS_PIPE_FD)
                except OSError:
                    pass
                _PROGRESS_PIPE_FD = -1
        os._exit(0)

    # Parent forwarder process (direct child of Quickshell Process)
    try:
        os.close(w_fd)
    except OSError:
        pass
    try:
        with os.fdopen(r_fd, "r", encoding="utf-8", errors="replace") as pipe_reader:
            for line in pipe_reader:
                try:
                    sys.stderr.write(line)
                    sys.stderr.flush()
                except OSError:
                    break
    except Exception:
        pass
    try:
        os.waitpid(worker_pid, 0)
    except OSError:
        pass
    st = _read_operation_status()
    if st.get("unconsumedResult"):
        consumed = _consume_unconsumed_result(st)
        if consumed is not None:
            return consumed
    res = st.get("result")
    if isinstance(res, dict):
        return res
    return cmd_list()


def pick_files() -> list[str]:
    mock_pick = os.environ.get("ALIS_PORTABLE_APPS_MOCK_PICK_FILES", "").strip()
    if mock_pick:
        delay_ms = int(os.environ.get("ALIS_PORTABLE_APPS_MOCK_PICK_DELAY_MS", "0") or 0)
        if delay_ms > 0:
            time.sleep(delay_ms / 1000.0)
        if mock_pick.upper() == "CANCEL":
            return []
        if mock_pick.startswith("["):
            try:
                arr = json.loads(mock_pick)
                if isinstance(arr, list):
                    return [str(x).strip() for x in arr if str(x).strip()]
            except Exception:
                pass
        return [line.strip() for line in mock_pick.splitlines() if line.strip()]

    start_dir = str(Path.home() / "Downloads")
    if not Path(start_dir).is_dir():
        start_dir = str(Path.home())

    if shutil.which("zenity"):
        try:
            res = subprocess.run(
                [
                    "zenity",
                    "--file-selection",
                    "--multiple",
                    "--separator=\n",
                    "--title=Add Applications (AppImage / zsync / tar.gz / pkg.tar.zst / zip)",
                    f"--filename={start_dir}/",
                    "--file-filter=Application Packages (*.AppImage *.zsync *.tar.gz *.tgz *.pkg.tar.zst *.tar.zst *.tar.xz *.zip) | *.AppImage *.appimage *.zsync *.tar.gz *.tgz *.pkg.tar.zst *.pkg.tar.xz *.pkg.tar.gz *.tar.zst *.tzst *.tar.xz *.txz *.tar.bz2 *.tbz2 *.zip *.gz *.zst *.xz",
                    "--file-filter=All Files | *",
                ],
                capture_output=True,
                text=True,
            )
            if res.returncode == 0 and res.stdout.strip():
                return [line.strip() for line in res.stdout.splitlines() if line.strip()]
            stderr_low = (res.stderr or "").lower()
            is_startup_failure = (
                "cannot open display" in stderr_low
                or "failed to open display" in stderr_low
                or "failed to parse" in stderr_low
            )
            if not is_startup_failure:
                return []
        except OSError:
            pass

    if shutil.which("kdialog"):
        try:
            res = subprocess.run(
                [
                    "kdialog",
                    "--multiple",
                    "--separate-output",
                    "--title",
                    "Add Applications",
                    "--getopenfilename",
                    start_dir,
                    "Application Packages (*.AppImage *.appimage *.zsync *.tar.gz *.tgz *.pkg.tar.zst *.pkg.tar.xz *.pkg.tar.gz *.tar.zst *.tzst *.tar.xz *.txz *.tar.bz2 *.tbz2 *.zip);;All Files (*)",
                ],
                capture_output=True,
                text=True,
            )
            if res.returncode == 0 and res.stdout.strip():
                return [line.strip() for line in res.stdout.splitlines() if line.strip()]
            stderr_low = (res.stderr or "").lower()
            if "could not connect to display" not in stderr_low and "cannot open display" not in stderr_low:
                return []
        except OSError:
            pass

    try:
        import tkinter as tk
        from tkinter import filedialog

        tk_root = tk.Tk()
        tk_root.withdraw()
        selected = filedialog.askopenfilenames(
            initialdir=start_dir,
            title="Add Applications",
            filetypes=[
                (
                    "Application Packages",
                    "*.AppImage *.appimage *.zsync *.tar.gz *.tgz *.pkg.tar.zst *.pkg.tar.xz *.tar.zst *.tzst *.tar.xz *.txz *.tar.bz2 *.tbz2 *.zip",
                ),
                ("All Files", "*"),
            ],
        )
        tk_root.destroy()
        return [str(p).strip() for p in (selected or ()) if str(p).strip()]
    except Exception:
        pass

    return []


def main(argv: list[str]) -> int:
    bg_survive = "--bg-survive" in argv[1:]
    clean_args = [a for a in argv[1:] if a != "--bg-survive"]
    if bg_survive:
        try:
            signal.signal(signal.SIGHUP, signal.SIG_IGN)
        except Exception:
            pass

    cmd = clean_args[0] if clean_args else "list"
    rest = clean_args[1:]

    if cmd == "list":
        if "--attach-running" in rest:
            attached = _attach_to_running_worker()
            if attached is not None:
                print(json.dumps(attached, ensure_ascii=False))
                return 0
        print(json.dumps(cmd_list(), ensure_ascii=False))
        return 0
    if cmd == "pick-and-add":
        selected = pick_files()
        if not selected:
            print(json.dumps({"ok": True, "cancelled": True, "apps": cmd_list()["apps"]}, ensure_ascii=False))
            return 0
        _emit_progress(
            "pick-and-add",
            percent=15,
            detail="Installing selected application package(s)…",
            stage="installing",
            write_status_file=False,
        )
        print(json.dumps(add_files(selected), ensure_ascii=False))
        return 0
    if cmd == "add":
        print(json.dumps(add_files(rest), ensure_ascii=False))
        return 0
    if cmd == "remove":
        target = rest[0] if rest else ""
        print(json.dumps(remove_app(target), ensure_ascii=False))
        return 0
    if cmd in ("check-updates", "check"):
        out = _run_detached_bg_survive("check-updates", check_updates, rest) if bg_survive else check_updates(rest)
        print(json.dumps(out, ensure_ascii=False))
        return 0
    if cmd == "update":
        out = _run_detached_bg_survive("update", update_apps, rest) if bg_survive else update_apps(rest)
        print(json.dumps(out, ensure_ascii=False))
        return 0
    if cmd == "set-update-source":
        target = rest[0] if rest else ""
        source = rest[1] if len(rest) > 1 else ""
        print(json.dumps(set_update_source(target, source), ensure_ascii=False))
        return 0
    print(json.dumps({"ok": False, "error": f"Unknown command: {cmd}"}))
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

