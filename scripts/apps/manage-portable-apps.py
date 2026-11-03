#!/usr/bin/env python3
"""Manage portable applications (.AppImage, .AppImage.zsync, .tar.gz, .pkg.tar.zst) for Alis Settings.

Subcommands:
  list                     -> JSON list of managed portable applications
  pick-and-add             -> Open native file chooser (zenity/kdialog) and install selected files
  add <path> [<path> ...]  -> Move files into managed storage, extract icon, create .desktop entry
  remove <id>              -> Remove managed files, extracted package, icon, and .desktop entry
"""

from __future__ import annotations

import configparser
import hashlib
import json
import os
import re
import shutil
import stat
import struct
import subprocess
import sys
import tarfile
import tempfile
import time
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


def _save_registry(apps: list[dict[str, Any]]) -> None:
    _ensure_dirs()
    path = _registry_path()
    tmp = path.with_suffix(".json.tmp")
    tmp.write_text(json.dumps({"version": 1, "apps": apps}, indent=2, ensure_ascii=False), encoding="utf-8")
    tmp.replace(path)


ARCHIVE_SUFFIXES = (
    ".AppImage.zsync",
    ".appimage.zsync",
    ".AppImage",
    ".appimage",
    ".pkg.tar.zst",
    ".pkg.tar.xz",
    ".pkg.tar.gz",
    ".tar.zst",
    ".tzst",
    ".tar.gz",
    ".tgz",
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


def _parse_zsync_header(zsync_path: Path) -> dict[str, str]:
    info: dict[str, str] = {}
    try:
        with zsync_path.open("rb") as f:
            head = f.read(2048)
        header_bytes = head.split(b"\n\n", 1)[0]
        for line in header_bytes.decode("utf-8", errors="ignore").splitlines():
            if ":" in line:
                k, v = line.split(":", 1)
                info[k.strip().lower()] = v.strip()
    except Exception:
        pass
    return info


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
        shutil.move(str(src), str(dst))


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
        elif nl.endswith((".pkg.tar.zst", ".pkg.tar.xz", ".pkg.tar.gz", ".tar.zst", ".tzst", ".tar.gz", ".tgz")):
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
        matched_zsync: Path | None = None
        for zs in list(zsyncs):
            hdr = _parse_zsync_header(zs)
            if zs.name == f"{ai.name}.zsync" or hdr.get("filename") == ai.name or _slugify(zs.name) == slug:
                matched_zsync = zs
                zsyncs.remove(zs)
                break

        dest_ai = _appimages_dir() / ai.name
        _move_or_copy(ai, dest_ai)
        try:
            dest_ai.chmod(dest_ai.stat().st_mode | 0o755)
        except OSError:
            pass

        dest_zsync_str = ""
        if matched_zsync is not None and matched_zsync.is_file():
            dest_zs = _appimages_dir() / matched_zsync.name
            _move_or_copy(matched_zsync, dest_zs)
            dest_zsync_str = str(dest_zs)

        meta, icon_path = _extract_appimage_metadata(dest_ai, slug)
        name = meta.get("Name") or _human_title(ai.name)
        comment = meta.get("Comment", "")
        categories = meta.get("Categories", "Utility;Application;")
        wm_class = meta.get("StartupWMClass", slug)

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
        )

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
            "addedAt": int(time.time()),
        }
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
                added_ids.append(slug)
                break

    # 3. Process .tar.gz / .tgz archives
    for arc in archives:
        slug = _slugify(arc.name)
        dest_arc = _archives_dir() / arc.name
        _move_or_copy(arc, dest_arc)

        pkg_dir = _packages_dir() / slug
        if pkg_dir.exists():
            shutil.rmtree(pkg_dir, ignore_errors=True)
        pkg_dir.mkdir(parents=True, exist_ok=True)
        _safe_extract_tar(dest_arc, pkg_dir)

        exec_path, meta, icon_path = _find_tar_executable_and_icon(pkg_dir, slug)
        if exec_path is None:
            return {
                "ok": False,
                "error": f"Could not locate an executable inside {arc.name}.",
                "apps": cmd_list()["apps"],
            }

        name = meta.get("Name") or _human_title(arc.name)
        comment = meta.get("Comment", "")
        categories = meta.get("Categories", "Utility;Application;")
        wm_class = meta.get("StartupWMClass", slug)

        desktop_file = _write_desktop_entry(
            slug=slug,
            name=name,
            exec_path=exec_path,
            icon_path=icon_path,
            comment=comment,
            categories=categories,
            wm_class=wm_class,
            mime_type=meta.get("MimeType", ""),
        )

        nl_arc = arc.name.lower()
        if nl_arc.endswith((".pkg.tar.zst", ".pkg.tar.xz", ".pkg.tar.gz")):
            archive_kind = "pkg.tar.zst"
        elif nl_arc.endswith((".tar.zst", ".tzst")):
            archive_kind = "tar.zst"
        else:
            archive_kind = "tar.gz"

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
            "addedAt": int(time.time()),
        }
        registry = [r for r in registry if r.get("id") != slug]
        registry.append(entry)
        added_ids.append(slug)

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

    _save_registry(kept)
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


def cmd_list() -> dict[str, Any]:
    _repair_managed_desktop_entries()
    registry = _load_registry()
    cleaned: list[dict[str, Any]] = []
    for item in registry:
        exec_p = Path(str(item.get("execPath", "")))
        stored_p = Path(str(item.get("storedPath", "")))
        zsync_s = str(item.get("zsyncPath", "")).strip()
        has_zsync = bool(zsync_s and Path(zsync_s).is_file())
        item_copy = dict(item)
        item_copy["installed"] = exec_p.exists() or stored_p.exists()
        item_copy["hasZsync"] = has_zsync
        cleaned.append(item_copy)
    cleaned.sort(key=lambda x: str(x.get("name", "")).lower())
    return {
        "ok": True,
        "appimagesDir": str(_appimages_dir()),
        "archivesDir": str(_archives_dir()),
        "packagesDir": str(_packages_dir()),
        "desktopDir": str(_desktop_dir()),
        "apps": cleaned,
    }


def pick_files() -> list[str]:
    start_dir = str(Path.home() / "Downloads")
    if not Path(start_dir).is_dir():
        start_dir = str(Path.home())

    if shutil.which("zenity"):
        res = subprocess.run(
            [
                "zenity",
                "--file-selection",
                "--multiple",
                "--separator=\n",
                "--title=Add Applications (AppImage / zsync / tar.gz / pkg.tar.zst)",
                f"--filename={start_dir}/",
                "--file-filter=Application Packages (*.AppImage *.zsync *.tar.gz *.tgz *.pkg.tar.zst *.tar.zst) | *.AppImage *.appimage *.zsync *.tar.gz *.tgz *.pkg.tar.zst *.pkg.tar.xz *.tar.zst *.tzst",
                "--file-filter=All Files | *",
            ],
            capture_output=True,
            text=True,
        )
        if res.returncode == 0 and res.stdout.strip():
            return [line.strip() for line in res.stdout.splitlines() if line.strip()]
        return []

    if shutil.which("kdialog"):
        res = subprocess.run(
            [
                "kdialog",
                "--multiple",
                "--separate-output",
                "--title",
                "Add Applications",
                "--getopenfilename",
                start_dir,
                "*.AppImage *.appimage *.zsync *.tar.gz *.tgz *.pkg.tar.zst *.pkg.tar.xz *.tar.zst *.tzst|Application Packages",
            ],
            capture_output=True,
            text=True,
        )
        if res.returncode == 0 and res.stdout.strip():
            return [line.strip() for line in res.stdout.splitlines() if line.strip()]
        return []

    return []


def main(argv: list[str]) -> int:
    cmd = argv[1] if len(argv) > 1 else "list"
    if cmd == "list":
        print(json.dumps(cmd_list(), ensure_ascii=False))
        return 0
    if cmd == "pick-and-add":
        selected = pick_files()
        if not selected:
            print(json.dumps({"ok": True, "cancelled": True, "apps": cmd_list()["apps"]}, ensure_ascii=False))
            return 0
        print(json.dumps(add_files(selected), ensure_ascii=False))
        return 0
    if cmd == "add":
        print(json.dumps(add_files(argv[2:]), ensure_ascii=False))
        return 0
    if cmd == "remove":
        target = argv[2] if len(argv) > 2 else ""
        print(json.dumps(remove_app(target), ensure_ascii=False))
        return 0
    print(json.dumps({"ok": False, "error": f"Unknown command: {cmd}"}))
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
