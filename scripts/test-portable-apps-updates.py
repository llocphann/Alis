#!/usr/bin/env python3
"""Comprehensive tests for Portable Applications check/update support (zsync, rsync, tauri, electron-builder) and UI."""

from __future__ import annotations

import base64
import hashlib
import http.server
import json
import os
import shutil
import socketserver
import subprocess
import sys
import tarfile
import tempfile
import threading
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
MANAGE_SCRIPT = REPO_ROOT / "scripts" / "apps" / "manage-portable-apps.py"


def run_manage(env: dict[str, str], *args: str) -> dict:
    res = subprocess.run(
        [sys.executable, str(MANAGE_SCRIPT), *args],
        env=env,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert res.returncode == 0, f"manage-portable-apps {args} failed ({res.returncode}): {res.stderr}\n{res.stdout}"
    return json.loads(res.stdout)


def run_manage_with_progress(env: dict[str, str], *args: str) -> tuple[dict, list[dict]]:
    res = subprocess.run(
        [sys.executable, str(MANAGE_SCRIPT), *args],
        env=env,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert res.returncode == 0, f"manage-portable-apps {args} failed ({res.returncode}): {res.stderr}\n{res.stdout}"
    progress_events: list[dict] = []
    for line in (res.stderr or "").splitlines():
        line_s = line.strip()
        if line_s.startswith("ALIS_PROGRESS:"):
            progress_events.append(json.loads(line_s[len("ALIS_PROGRESS:") :]))
    return json.loads(res.stdout), progress_events



def make_fake_elf_with_upd_info(upd_info: str, payload_tag: str) -> bytes:
    """Construct a minimal valid ELF64 header with a .shstrtab and .upd_info section."""
    shstrtab = b"\x00.shstrtab\x00.upd_info\x00"
    upd_bytes = upd_info.encode("utf-8") + b"\x00"

    # ELF64 header is 64 bytes
    # Section 0: null (64 bytes)
    # Section 1: .shstrtab (64 bytes)
    # Section 2: .upd_info (64 bytes)
    shoff = 64
    shentsize = 64
    shnum = 3
    shstrndx = 1

    data_start = shoff + shnum * shentsize
    shstr_off = data_start
    upd_off = shstr_off + len(shstrtab)

    import struct

    ident = bytearray(64)
    ident[0:4] = b"\x7fELF"
    ident[4] = 2  # ELFCLASS64
    ident[5] = 1  # ELFDATA2LSB
    ident[6] = 1  # EV_CURRENT
    struct.pack_into("<Q", ident, 40, shoff)
    struct.pack_into("<HHH", ident, 58, shentsize, shnum, shstrndx)

    sec0 = bytes(64)
    sec1 = bytearray(64)
    struct.pack_into("<I", sec1, 0, 1)  # name offset for .shstrtab
    struct.pack_into("<QQ", sec1, 24, shstr_off, len(shstrtab))

    sec2 = bytearray(64)
    struct.pack_into("<I", sec2, 0, 11)  # name offset for .upd_info
    struct.pack_into("<QQ", sec2, 24, upd_off, len(upd_bytes))

    shared_block = bytearray(b"ALIS_SHARED_SEED_BLOCK_0123456789ABCDEF\n" * 16384)
    tag_bytes = (f"#PAYLOAD:{payload_tag}\n" * 128).encode("utf-8")
    shared_block[32768 : 32768 + len(tag_bytes)] = tag_bytes
    shared_block[524288 : 524288 + len(tag_bytes)] = tag_bytes
    return bytes(ident) + sec0 + bytes(sec1) + bytes(sec2) + shstrtab + upd_bytes + bytes(shared_block)


def build_zsync_file(target_file: Path, filename: str, url: str) -> bytes:
    zsyncmake = shutil.which("zsyncmake")
    if zsyncmake:
        with tempfile.TemporaryDirectory() as td:
            out_zs = Path(td) / f"{filename}.zsync"
            res = subprocess.run(
                [zsyncmake, "-u", url, "-f", filename, "-o", str(out_zs), str(target_file)],
                capture_output=True,
                timeout=15,
            )
            if res.returncode == 0 and out_zs.is_file():
                return out_zs.read_bytes()
    data = target_file.read_bytes()
    sha1 = hashlib.sha1(data).hexdigest()
    hdr = (
        f"zsync: 0.6.2\n"
        f"Filename: {filename}\n"
        f"Blocksize: 2048\n"
        f"Length: {len(data)}\n"
        f"Hash-Lengths: 2,2,5\n"
        f"URL: {url}\n"
        f"SHA-1: {sha1}\n\n"
    ).encode("utf-8")
    return hdr + b"\x00" * 64


def test_backend_protocols() -> None:
    with tempfile.TemporaryDirectory(prefix="alis-portable-test-") as td:
        root = Path(td)
        data_home = root / "data"
        srv_dir = root / "upstream"
        srv_dir.mkdir(parents=True)
        src_dir = root / "src"
        src_dir.mkdir(parents=True)

        zsyncapp_range_hits = [0]
        zsyncapp_full_get_hits = [0]

        # Start a local HTTP server that supports Range requests, GitHub releases API,
        # and GitHub/CDN 302 redirects to signed per-asset UUID URLs (enforcing HTTP 618 if jwt is missing/wrong)
        class RangeHTTPHandler(http.server.SimpleHTTPRequestHandler):
            def __init__(self, *args, **kwargs):
                super().__init__(*args, directory=str(srv_dir), **kwargs)

            def log_message(self, format, *args):
                pass

            def do_GET(self):
                port = self.server.server_address[1]
                if self.path.startswith("/repos/testorg/zsyncapp/releases"):
                    rel = {
                        "tag_name": "v1.2.0",
                        "assets": [
                            {
                                "name": "zsyncapp-1.2.0-x86_64.AppImage.zsync",
                                "browser_download_url": f"http://127.0.0.1:{port}/releases/download/v1.2.0/zsyncapp-1.2.0-x86_64.AppImage.zsync",
                            },
                            {
                                "name": "zsyncapp-1.2.0-x86_64.AppImage",
                                "browser_download_url": f"http://127.0.0.1:{port}/releases/download/v1.2.0/zsyncapp-1.2.0-x86_64.AppImage",
                            },
                        ],
                    }
                    payload = json.dumps(rel).encode("utf-8")
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", str(len(payload)))
                    self.end_headers()
                    self.wfile.write(payload)
                    return

                if self.path == "/releases/download/v1.2.0/zsyncapp-1.2.0-x86_64.AppImage.zsync":
                    self.send_response(302)
                    self.send_header(
                        "Location",
                        f"http://127.0.0.1:{port}/github-production-release-asset/1398080271/60f61912-zsync-uuid?jwt=valid_zsync_jwt",
                    )
                    self.end_headers()
                    return

                if self.path == "/releases/download/v1.2.0/zsyncapp-1.2.0-x86_64.AppImage":
                    self.send_response(302)
                    self.send_header(
                        "Location",
                        f"http://127.0.0.1:{port}/github-production-release-asset/1398080271/61ca4bc6-appimage-uuid?jwt=valid_appimage_jwt",
                    )
                    self.end_headers()
                    return

                mapped_rel = self.path.split("?", 1)[0].lstrip("/")
                if self.path.startswith("/github-production-release-asset/"):
                    if (
                        mapped_rel == "github-production-release-asset/1398080271/60f61912-zsync-uuid"
                        and "jwt=valid_zsync_jwt" in self.path
                    ):
                        mapped_rel = "zsyncapp-1.2.0-x86_64.AppImage.zsync"
                    elif (
                        mapped_rel == "github-production-release-asset/1398080271/61ca4bc6-appimage-uuid"
                        and "jwt=valid_appimage_jwt" in self.path
                    ):
                        mapped_rel = "zsyncapp-1.2.0-x86_64.AppImage"
                    else:
                        self.send_error(618, "jwt:jwt-not-provided")
                        return

                fpath = srv_dir / mapped_rel
                if not fpath.is_file():
                    self.send_error(404)
                    return
                data = fpath.read_bytes()
                rng = self.headers.get("Range", "")
                if rng.startswith("bytes=") and "," not in rng:
                    if fpath.name == "zsyncapp-1.2.0-x86_64.AppImage":
                        zsyncapp_range_hits[0] += 1
                    s_str, e_str = rng[6:].split("-", 1)
                    start = int(s_str) if s_str else 0
                    end = int(e_str) if e_str else len(data) - 1
                    end = min(end, len(data) - 1)
                    chunk = data[start : end + 1]
                    self.send_response(206)
                    self.send_header("Content-Type", "application/octet-stream")
                    self.send_header("Content-Range", f"bytes {start}-{end}/{len(data)}")
                    self.send_header("Content-Length", str(len(chunk)))
                    self.end_headers()
                    self.wfile.write(chunk)
                    return

                if fpath.name == "zsyncapp-1.2.0-x86_64.AppImage":
                    zsyncapp_full_get_hits[0] += 1
                self.send_response(200)
                self.send_header("Content-Type", "application/octet-stream")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

        httpd = socketserver.TCPServer(("127.0.0.1", 0), RangeHTTPHandler)
        port = httpd.server_address[1]
        server_thread = threading.Thread(target=httpd.serve_forever, daemon=True)
        server_thread.start()

        try:
            env = dict(
                os.environ,
                ALIS_PORTABLE_APPS_DATA_HOME=str(data_home),
                ALIS_GITHUB_API_BASE=f"http://127.0.0.1:{port}",
            )

            # 1. Create zsyncapp v1.0.0 with ELF .upd_info and companion .zsync
            upd_str = "gh-releases-zsync|testorg|zsyncapp|latest|zsyncapp-*-x86_64.AppImage.zsync"
            v1_ai = src_dir / "zsyncapp-1.0.0-x86_64.AppImage"
            v1_ai.write_bytes(make_fake_elf_with_upd_info(upd_str, "v1.0.0"))
            v1_ai.chmod(0o755)
            v1_zs = src_dir / "zsyncapp-1.0.0-x86_64.AppImage.zsync"
            v1_zs.write_bytes(
                build_zsync_file(
                    v1_ai,
                    "zsyncapp-1.0.0-x86_64.AppImage",
                    "zsyncapp-1.0.0-x86_64.AppImage",
                )
            )

            # Create upstream v1.2.0 for zsyncapp with relative URL: inside .zsync (matching PhotoCraft & VSCodium)
            v2_ai = srv_dir / "zsyncapp-1.2.0-x86_64.AppImage"
            v2_ai.write_bytes(make_fake_elf_with_upd_info(upd_str, "v1.2.0"))
            v2_zs = srv_dir / "zsyncapp-1.2.0-x86_64.AppImage.zsync"
            v2_zs.write_bytes(
                build_zsync_file(
                    v2_ai,
                    "zsyncapp-1.2.0-x86_64.AppImage",
                    "zsyncapp-1.2.0-x86_64.AppImage",
                )
            )

            # 2. Create rsyncapp v1.0.0 and upstream rsync source v2.0.0
            rsync_v1 = src_dir / "rsyncapp-1.0.0-x86_64.AppImage"
            rsync_v1.write_bytes(make_fake_elf_with_upd_info("", "rsync-v1.0.0"))
            rsync_v1.chmod(0o755)
            rsync_upstream = srv_dir / "rsyncapp-2.0.0-x86_64.AppImage"
            rsync_upstream.write_bytes(make_fake_elf_with_upd_info("", "rsync-v2.0.0-updated"))
            rsync_upstream.chmod(0o755)

            # 3. Create tauriapp v1.0.0 and upstream latest.json -> v1.5.0
            tauri_v1 = src_dir / "tauriapp-1.0.0-x86_64.AppImage"
            tauri_v1.write_bytes(make_fake_elf_with_upd_info("", "tauri-v1.0.0"))
            tauri_v1.chmod(0o755)
            tauri_v2 = srv_dir / "tauriapp-1.5.0-x86_64.AppImage"
            tauri_v2.write_bytes(make_fake_elf_with_upd_info("", "tauri-v1.5.0"))
            (srv_dir / "latest.json").write_text(
                json.dumps(
                    {
                        "version": "v1.5.0",
                        "platforms": {
                            "linux-x86_64": {
                                "url": f"http://127.0.0.1:{port}/tauriapp-1.5.0-x86_64.AppImage"
                            }
                        },
                    }
                ),
                encoding="utf-8",
            )

            # 4. Create electronapp v1.0.0 (.tar.gz) with local file:// app-update.yml -> v1.3.0
            elec_pkg_src = root / "elec_build_v1"
            (elec_pkg_src / "resources").mkdir(parents=True)
            elec_bin_v1 = elec_pkg_src / "electronapp"
            elec_bin_v1.write_text("#!/bin/sh\necho v1.0.0\n", encoding="utf-8")
            elec_bin_v1.chmod(0o755)
            (elec_pkg_src / "resources" / "package.json").write_text(
                json.dumps({"name": "electronapp", "version": "1.0.0"}), encoding="utf-8"
            )
            (elec_pkg_src / "resources" / "app-update.yml").write_text(
                f"provider: generic\nurl: {srv_dir.as_uri()}/\n", encoding="utf-8"
            )
            elec_tar_v1 = src_dir / "electronapp-1.0.0.tar.gz"
            with tarfile.open(elec_tar_v1, "w:gz") as tf:
                tf.add(elec_pkg_src, arcname="electronapp")

            elec_pkg_v2 = root / "elec_build_v2"
            (elec_pkg_v2 / "resources").mkdir(parents=True)
            elec_bin_v2 = elec_pkg_v2 / "electronapp"
            elec_bin_v2.write_text("#!/bin/sh\necho v1.3.0\n", encoding="utf-8")
            elec_bin_v2.chmod(0o755)
            (elec_pkg_v2 / "resources" / "package.json").write_text(
                json.dumps({"name": "electronapp", "version": "1.3.0"}), encoding="utf-8"
            )
            (elec_pkg_v2 / "resources" / "app-update.yml").write_text(
                f"provider: generic\nurl: {srv_dir.as_uri()}/\n", encoding="utf-8"
            )
            elec_tar_v2 = srv_dir / "electronapp-1.3.0.tar.gz"
            with tarfile.open(elec_tar_v2, "w:gz") as tf:
                tf.add(elec_pkg_v2, arcname="electronapp")
            sha512_b64 = base64.b64encode(hashlib.sha512(elec_tar_v2.read_bytes()).digest()).decode("ascii")
            (srv_dir / "latest-linux.yml").write_text(
                f"version: 1.3.0\npath: electronapp-1.3.0.tar.gz\nsha512: {sha512_b64}\n",
                encoding="utf-8",
            )

            # Add all 4 apps
            added = run_manage(
                env,
                "add",
                str(v1_ai),
                str(v1_zs),
                str(rsync_v1),
                str(tauri_v1),
                str(elec_tar_v1),
            )
            assert added["ok"] is True

            # Configure rsync source for rsyncapp and tauri source for tauriapp
            run_manage(env, "set-update-source", "rsyncapp", f"rsync:{rsync_upstream}")
            run_manage(env, "set-update-source", "tauriapp", f"http://127.0.0.1:{port}/latest.json")

            # Simulate legacy registry record by stripping new fields from zsyncapp and verifying cmd_list backfills them
            reg_path = data_home / "alis" / "applications" / "registry.json"
            reg_data = json.loads(reg_path.read_text(encoding="utf-8"))
            for item in reg_data["apps"]:
                if item["id"] == "zsyncapp":
                    for k in ("version", "updateSupported", "updateProtocol", "updInfo", "updateUrl", "_metaSig"):
                        item.pop(k, None)
            reg_path.write_text(json.dumps(reg_data), encoding="utf-8")

            listed = run_manage(env, "list")
            by_id = {a["id"]: a for a in listed["apps"]}
            assert by_id["zsyncapp"]["updateSupported"] is True
            assert by_id["zsyncapp"]["updateProtocol"] == "zsync"
            assert by_id["zsyncapp"]["version"] == "1.0.0"
            assert by_id["rsyncapp"]["updateSupported"] is True
            assert by_id["rsyncapp"]["updateProtocol"] == "rsync"
            assert by_id["tauriapp"]["updateSupported"] is True
            assert by_id["tauriapp"]["updateProtocol"] == "tauri"
            assert by_id["electronapp"]["updateSupported"] is True
            assert by_id["electronapp"]["updateProtocol"] == "electron-builder"

            # Check updates across all 4 apps and verify live ALIS_PROGRESS events
            checked, check_progress = run_manage_with_progress(env, "check-updates")
            assert checked["ok"] is True
            assert len(check_progress) >= 2, f"Expected progress events during check-updates, got {check_progress}"
            assert check_progress[-1]["percent"] == 100
            assert checked["updatesAvailable"] == 4, f"Expected 4 updates available, got {checked}"
            by_id = {a["id"]: a for a in checked["apps"]}
            assert by_id["zsyncapp"]["updateAvailable"] is True
            assert by_id["zsyncapp"]["latestVersion"] == "1.2.0"
            assert by_id["rsyncapp"]["updateAvailable"] is True
            assert by_id["rsyncapp"]["latestVersion"] == "2.0.0"
            assert by_id["tauriapp"]["updateAvailable"] is True
            assert by_id["tauriapp"]["latestVersion"] == "1.5.0"
            assert by_id["electronapp"]["updateAvailable"] is True
            assert "github-production-release-asset" not in by_id["zsyncapp"]["remoteZsyncUrl"]
            assert "github-production-release-asset" not in by_id["zsyncapp"]["downloadUrl"]
            assert by_id["zsyncapp"]["downloadUrl"].endswith("/releases/download/v1.2.0/zsyncapp-1.2.0-x86_64.AppImage")

            # Simulate pre-patch persisted registry record polluted with ephemeral CDN URLs and HTTP Error 618
            reg_polluted = json.loads(reg_path.read_text(encoding="utf-8"))
            for item in reg_polluted["apps"]:
                if item["id"] == "zsyncapp":
                    item["remoteZsyncUrl"] = (
                        f"http://127.0.0.1:{port}/github-production-release-asset/1398080271/60f61912-zsync-uuid?jwt=expired_token"
                    )
                    item["downloadUrl"] = (
                        f"http://127.0.0.1:{port}/github-production-release-asset/1398080271/zsyncapp-1.2.0-x86_64.AppImage"
                    )
                    item["updateError"] = "HTTP Error 618: jwt:jwt-not-provided"
            reg_path.write_text(json.dumps(reg_polluted), encoding="utf-8")

            sanitized_list = run_manage(env, "list")
            san_by_id = {a["id"]: a for a in sanitized_list["apps"]}
            assert san_by_id["zsyncapp"]["remoteZsyncUrl"] == ""
            assert san_by_id["zsyncapp"]["downloadUrl"] == ""
            assert san_by_id["zsyncapp"]["updateError"] == ""

            # Apply update for zsyncapp directly after legacy sanitization (without manual check-updates first)
            # and verify SHA-1, new path, desktop entry Exec=, old file cleanup, and progress events
            upd_zs, upd_progress = run_manage_with_progress(env, "update", "zsyncapp")
            assert upd_zs["ok"] is True, f"Expected zsyncapp update to succeed without HTTP 618, got {upd_zs}"
            if shutil.which("zsync") and shutil.which("zsyncmake"):
                assert zsyncapp_range_hits[0] >= 2 and zsyncapp_full_get_hits[0] == 0, (
                    f"Expected multi-group zsync delta range transfer without full-file fallback, got range_hits={zsyncapp_range_hits[0]}, full_hits={zsyncapp_full_get_hits[0]}"
                )
            assert len(upd_progress) >= 3, f"Expected multiple progress stages during zsyncapp update, got {upd_progress}"
            pcts = [ev["percent"] for ev in upd_progress if ev.get("percent", -1) >= 0]
            assert pcts == sorted(pcts) and pcts[-1] == 100, f"Expected monotonic progress ending at 100, got {pcts}"
            op_status_file = data_home / "alis" / "applications" / "operation-status.json"
            assert op_status_file.is_file()
            op_status = json.loads(op_status_file.read_text(encoding="utf-8"))
            assert op_status.get("running") is False and op_status.get("action") == "update"
            assert "zsyncapp" in upd_zs["updated"]
            by_id = {a["id"]: a for a in upd_zs["apps"]}
            zs_entry = by_id["zsyncapp"]
            assert zs_entry["version"] == "1.2.0"
            assert zs_entry["updateAvailable"] is False
            assert Path(zs_entry["storedPath"]).name == "zsyncapp-1.2.0-x86_64.AppImage"
            assert Path(zs_entry["storedPath"]).is_file()
            assert not (data_home / "alis" / "applications" / "appimages" / "zsyncapp-1.0.0-x86_64.AppImage").exists()
            assert hashlib.sha1(Path(zs_entry["storedPath"]).read_bytes()).hexdigest() == hashlib.sha1(v2_ai.read_bytes()).hexdigest()
            desktop_txt = Path(zs_entry["desktopFile"]).read_text(encoding="utf-8")
            assert "zsyncapp-1.2.0-x86_64.AppImage" in desktop_txt

            # Simulate stale registry.json pointing to deleted v1.0.0 path after v1.2.0 is already on disk
            # (reproducing the exact live registry desync where VSCodium/PhotoCraft were updated on disk
            # but registry.json was overwritten by an older snapshot)
            reg_stale_path = json.loads(reg_path.read_text(encoding="utf-8"))
            for item in reg_stale_path["apps"]:
                if item["id"] == "zsyncapp":
                    item["storedPath"] = str(data_home / "alis" / "applications" / "appimages" / "zsyncapp-1.0.0-x86_64.AppImage")
                    item["execPath"] = item["storedPath"]
                    item["zsyncPath"] = f"{item['storedPath']}.zsync"
                    item["version"] = "1.0.0"
                    item["updateAvailable"] = True
                    item["updateError"] = "HTTP Error 618: jwt:jwt-not-provided"
                    item.pop("_metaSig", None)
            reg_path.write_text(json.dumps(reg_stale_path), encoding="utf-8")

            healed_list = run_manage(env, "list")
            healed_zs = {a["id"]: a for a in healed_list["apps"]}["zsyncapp"]
            assert healed_zs["installed"] is True, f"Expected stale storedPath to self-heal to v1.2.0 on disk, got {healed_zs}"
            assert Path(healed_zs["storedPath"]).name == "zsyncapp-1.2.0-x86_64.AppImage"
            assert healed_zs["version"] == "1.2.0"
            assert healed_zs["updateSupported"] is True
            assert healed_zs["updateProtocol"] == "zsync"
            assert healed_zs["updateAvailable"] is False
            assert healed_zs["updateError"] == ""

            # Test background worker survival (even when launcher process is killed with SIGKILL)
            # and reattachment via `list --attach-running`
            import time as _time
            bg_env = dict(env, ALIS_PORTABLE_APPS_SIMULATE_UPDATE_MS="800")
            bg_proc = subprocess.Popen(
                [sys.executable, str(MANAGE_SCRIPT), "--bg-survive", "update", "rsyncapp"],
                env=bg_env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            try:
                started_bg = False
                for _ in range(60):
                    if op_status_file.is_file():
                        st_now = json.loads(op_status_file.read_text(encoding="utf-8"))
                        if st_now.get("running") and (
                            st_now.get("launcherPid") == bg_proc.pid or st_now.get("pid") == bg_proc.pid
                        ):
                            started_bg = True
                            break
                    _time.sleep(0.02)
                assert started_bg, "Expected background worker to record running state in operation-status.json"
                # Simulate QProcess::~QProcess() killing the direct child when standalone Settings window closes
                bg_proc.kill()
                bg_proc.wait(timeout=5)
                attached_res, attached_progress = run_manage_with_progress(env, "list", "--attach-running")
                assert attached_res["ok"] is True
                assert "rsyncapp" in attached_res.get("updated", []), f"Expected attached_res to return completed update result, got {attached_res}"
                assert len(attached_progress) >= 1 and "apps" in attached_progress[0]
            finally:
                if bg_proc.poll() is None:
                    bg_proc.kill()
                    bg_proc.wait(timeout=5)

            # Simulate a non-618 prior updateError on tauriapp while updateAvailable=True and downloadUrl is valid,
            # and verify `update --all` clears the stale error and updates both tauriapp and electronapp
            reg_prior_err = json.loads(reg_path.read_text(encoding="utf-8"))
            for item in reg_prior_err["apps"]:
                if item["id"] == "tauriapp":
                    item["updateError"] = "Temporary network timeout during previous attempt"
            reg_path.write_text(json.dumps(reg_prior_err), encoding="utf-8")

            # Apply remaining updates (--all)
            upd_all = run_manage(env, "update", "--all")
            assert upd_all["ok"] is True, f"update --all failed: {upd_all}"
            assert set(upd_all["updated"]) == {"tauriapp", "electronapp"}
            assert upd_all["updatesAvailable"] == 0

            # Re-check updates: all 4 should now be up to date
            recheck = run_manage(env, "check-updates")
            assert recheck["ok"] is True
            assert recheck["updatesAvailable"] == 0, (
                f"Expected 0 updates available after update --all, got: "
                f"{[(a['id'], a.get('version'), a.get('latestVersion'), a.get('updateAvailable'), a.get('storedPath')) for a in recheck['apps']]}"
            )

            # Negative test: corrupt SHA-512 in latest-linux.yml and verify update is rejected safely,
            # then fix SHA-512 and verify retry succeeds without running check-updates again
            (srv_dir / "latest-linux.yml").write_text(
                "version: 1.4.0\npath: electronapp-1.3.0.tar.gz\nsha512: BAD_CHECKSUM\n",
                encoding="utf-8",
            )
            bad_check = run_manage(env, "check-updates", "electronapp")
            assert bad_check["updatesAvailable"] == 1
            bad_upd = run_manage(env, "update", "electronapp")
            assert bad_upd["ok"] is False
            assert "checksum mismatch" in bad_upd["error"].lower()
            # Existing v1.3.0 executable must still exist and work
            by_id = {a["id"]: a for a in bad_upd["apps"]}
            assert Path(by_id["electronapp"]["execPath"]).is_file()

            # Regression test (H1 & H1b): X-Alis-Update-Rsync in .desktop is preserved across update,
            # and same-size / same-second content change is detected via rsync --checksum
            desk_rsync_v1 = src_dir / "deskrsync-1.0.0-x86_64.AppImage"
            desk_rsync_v1.write_text("#!/bin/sh\necho v1\n", encoding="utf-8")
            desk_rsync_v1.chmod(0o755)
            desk_rsync_up = srv_dir / "deskrsync-2.0.0-x86_64.AppImage"
            desk_rsync_up.write_text("#!/bin/sh\necho v2\n", encoding="utf-8")
            desk_rsync_up.chmod(0o755)
            os.utime(desk_rsync_v1, (1700000000, 1700000000))
            os.utime(desk_rsync_up, (1700000000, 1700000000))
            run_manage(env, "add", str(desk_rsync_v1))
            desk_file = data_home / "applications" / "alis-app-deskrsync.desktop"
            desk_file.write_text(
                desk_file.read_text(encoding="utf-8") + f"X-Alis-Update-Rsync=rsync:{desk_rsync_up}\n",
                encoding="utf-8",
            )
            os.utime(
                data_home / "alis" / "applications" / "appimages" / "deskrsync-1.0.0-x86_64.AppImage",
                (1700000000, 1700000000),
            )
            chk_desk = run_manage(env, "check-updates", "deskrsync")
            by_id = {a["id"]: a for a in chk_desk["apps"]}
            assert by_id["deskrsync"]["updateAvailable"] is True
            upd_desk = run_manage(env, "update", "deskrsync")
            assert upd_desk["ok"] is True
            by_id = {a["id"]: a for a in upd_desk["apps"]}
            assert by_id["deskrsync"]["updateSupported"] is True
            assert by_id["deskrsync"]["updateProtocol"] == "rsync"
            assert "X-Alis-Update-Rsync=" in desk_file.read_text(encoding="utf-8")

            # Regression test (H2): Broken upstream source must report ok=False on direct update
            run_manage(env, "set-update-source", "deskrsync", f"rsync:{srv_dir / 'nonexistent.AppImage'}")
            broken_upd = run_manage(env, "update", "deskrsync")
            assert broken_upd["ok"] is False
            assert broken_upd["error"] != ""

            # Regression test (H3a, H3b, H3c & H4): SSH user@host:path, local path, unslashed directory rsync,
            # and version preservation when updating from an unversioned upstream filename
            ssh_src = run_manage(env, "set-update-source", "deskrsync", "user@example.com:/srv/apps/deskrsync.AppImage")
            by_id = {a["id"]: a for a in ssh_src["apps"]}
            assert by_id["deskrsync"]["updateSupported"] is True
            assert by_id["deskrsync"]["updateProtocol"] == "rsync"

            unver_up = srv_dir / "deskrsync_latest_bin"
            unver_up.write_text("#!/bin/sh\necho v3\n", encoding="utf-8")
            unver_up.chmod(0o755)
            local_src = run_manage(env, "set-update-source", "deskrsync", str(unver_up))
            by_id = {a["id"]: a for a in local_src["apps"]}
            assert by_id["deskrsync"]["updateSupported"] is True
            assert by_id["deskrsync"]["updateProtocol"] == "rsync"
            upd_unver = run_manage(env, "update", "deskrsync")
            assert upd_unver["ok"] is True
            by_id = {a["id"]: a for a in upd_unver["apps"]}
            assert by_id["deskrsync"]["version"] == "2.0.0"

            pkg_dir_v2 = root / "elec_dir_rsync_v2"
            (pkg_dir_v2 / "resources").mkdir(parents=True)
            (pkg_dir_v2 / "electronapp").write_text("#!/bin/sh\necho v2.5.0-rsync-dir\n", encoding="utf-8")
            (pkg_dir_v2 / "electronapp").chmod(0o755)
            (pkg_dir_v2 / "resources" / "package.json").write_text(
                json.dumps({"name": "electronapp", "version": "2.5.0"}), encoding="utf-8"
            )
            run_manage(env, "set-update-source", "electronapp", f"rsync:{pkg_dir_v2}")
            chk_dir = run_manage(env, "check-updates", "electronapp")
            by_id = {a["id"]: a for a in chk_dir["apps"]}
            assert by_id["electronapp"]["updateAvailable"] is True
            upd_dir = run_manage(env, "update", "electronapp")
            assert upd_dir["ok"] is True
            by_id = {a["id"]: a for a in upd_dir["apps"]}
            assert "v2.5.0-rsync-dir" in Path(by_id["electronapp"]["execPath"]).read_text(encoding="utf-8")

            # Test pick-and-add (cancel, heterogeneous multi-archive selection .AppImage + .tar.gz + .zip,
            # re-adding over a previously updated app with old binary cleanup, unsupported file error,
            # and zenity signal close vs kdialog fallback)
            cancel_env = dict(env, ALIS_PORTABLE_APPS_MOCK_PICK_FILES="CANCEL")
            cancelled_pick = run_manage(cancel_env, "pick-and-add")
            assert cancelled_pick["ok"] is True and cancelled_pick.get("cancelled") is True

            readd_ai = src_dir / "zsyncapp-2.0.0-x86_64.AppImage"
            readd_ai.write_bytes(make_fake_elf_with_upd_info(upd_str, "v2.0.0"))
            readd_ai.chmod(0o755)

            tar_pkg_src = root / "tar_tool_src"
            tar_pkg_src.mkdir(parents=True)
            tar_bin = tar_pkg_src / "tartool"
            tar_bin.write_text("#!/bin/sh\necho tartool-1.0\n", encoding="utf-8")
            tar_bin.chmod(0o755)
            multi_tar = src_dir / "tartool-1.0.0.tar.gz"
            with tarfile.open(multi_tar, "w:gz") as tf:
                tf.add(tar_pkg_src, arcname="tartool")

            import zipfile as _zipfile
            multi_zip = src_dir / "ziptool-1.4.0.zip"
            with _zipfile.ZipFile(multi_zip, "w") as zf:
                zinfo = _zipfile.ZipInfo("ziptool/ziptool")
                zinfo.external_attr = 0o755 << 16
                zf.writestr(zinfo, "#!/bin/sh\necho ziptool-1.4\n")

            pick_env = dict(
                env,
                ALIS_PORTABLE_APPS_MOCK_PICK_FILES=json.dumps([str(readd_ai), str(multi_tar), str(multi_zip)]),
            )
            picked_res, picked_prog = run_manage_with_progress(pick_env, "pick-and-add")
            assert picked_res["ok"] is True
            assert set(picked_res.get("added", [])) == {"zsyncapp", "tartool", "ziptool"}
            assert any(ev.get("stage") == "installing" for ev in picked_prog)
            by_id = {a["id"]: a for a in picked_res["apps"]}
            assert by_id["zsyncapp"]["version"] == "2.0.0"
            assert not (data_home / "alis" / "applications" / "appimages" / "zsyncapp-1.2.0-x86_64.AppImage").exists(), (
                "Expected old zsyncapp-1.2.0-x86_64.AppImage to be cleaned up when replaced by 2.0.0"
            )
            assert by_id["tartool"]["kind"] == "tar.gz" and by_id["tartool"]["installed"] is True
            assert by_id["ziptool"]["kind"] == "zip" and by_id["ziptool"]["installed"] is True

            # Unsupported file selection must return ok=False with an explicit error
            bad_file = src_dir / "notes.txt"
            bad_file.write_text("not an app", encoding="utf-8")
            bad_pick_env = dict(env, ALIS_PORTABLE_APPS_MOCK_PICK_FILES=str(bad_file))
            bad_picked = run_manage(bad_pick_env, "pick-and-add")
            assert bad_picked["ok"] is False and "no supported" in bad_picked.get("error", "").lower()

            # Test zenity signal termination (SIGTERM -> exit 143) does NOT spawn kdialog,
            # while zenity display failure ("cannot open display") falls through to kdialog with Qt6 filter syntax
            fake_bin_dir = root / "fake_bin"
            fake_bin_dir.mkdir(parents=True)
            kdialog_marker = root / "kdialog_called.txt"
            fake_zenity = fake_bin_dir / "zenity"
            fake_zenity.write_text(
                '#!/bin/sh\nif [ "$FAKE_ZENITY_MODE" = "sigterm" ]; then exit 143; fi\n'
                'echo "Cannot open display: :99" >&2\nexit 255\n',
                encoding="utf-8",
            )
            fake_zenity.chmod(0o755)
            fake_kdialog = fake_bin_dir / "kdialog"
            fake_kdialog.write_text(
                f'#!/bin/sh\nprintf "%s\\n" "$@" > "{kdialog_marker}"\nexit 1\n',
                encoding="utf-8",
            )
            fake_kdialog.chmod(0o755)

            sig_env = dict(env, PATH=f"{fake_bin_dir}:{env.get('PATH', '')}", FAKE_ZENITY_MODE="sigterm")
            sig_env.pop("ALIS_PORTABLE_APPS_MOCK_PICK_FILES", None)
            sig_res = run_manage(sig_env, "pick-and-add")
            assert sig_res["ok"] is True and sig_res.get("cancelled") is True
            assert not kdialog_marker.exists(), "Expected zenity SIGTERM (143) not to fall through to kdialog"

            disp_env = dict(env, PATH=f"{fake_bin_dir}:{env.get('PATH', '')}", FAKE_ZENITY_MODE="display_err")
            disp_env.pop("ALIS_PORTABLE_APPS_MOCK_PICK_FILES", None)
            disp_res = run_manage(disp_env, "pick-and-add")
            assert disp_res["ok"] is True and disp_res.get("cancelled") is True
            assert kdialog_marker.exists(), "Expected zenity display error to fall back to kdialog"
            kdialog_args_txt = kdialog_marker.read_text(encoding="utf-8")
            assert "Application Packages (" in kdialog_args_txt and ";;All Files (*)" in kdialog_args_txt

        finally:
            httpd.shutdown()
            httpd.server_close()

    print("PASS: Portable applications backend protocol tests (zsync, rsync, tauri, electron-builder, legacy backfill, checksum rejection, desktop source persistence, directory/SSH rsync, pick-and-add)")


def test_ui_headless_quickshell() -> None:
    qs_bin = shutil.which("qs") or shutil.which("quickshell")
    if not qs_bin:
        print("SKIP: quickshell binary not found")
        return

    with tempfile.TemporaryDirectory(prefix="alis-portable-ui-test-") as td:
        root = Path(td)
        for entry in [
            "modules",
            "services",
            "GlobalStates.qml",
            "qmldir",
            "assets",
            "scripts",
            "defaults",
            "translations",
            "settings.qml",
            "waffleSettings.qml",
        ]:
            (root / entry).symlink_to(REPO_ROOT / entry)

        for kind in ["config", "cache", "data", "state", "runtime"]:
            (root / kind).mkdir(parents=True, exist_ok=True)

        conf_dir = root / "config" / "alis"
        conf_dir.mkdir(parents=True, exist_ok=True)
        cfg_val = json.loads((REPO_ROOT / "defaults" / "config.json").read_text(encoding="utf-8"))
        cfg_val["panelFamily"] = "abyss"

        data_home = root / "data"
        apps_dir = data_home / "alis" / "applications"
        ai_dir = apps_dir / "appimages"
        desk_dir = data_home / "applications"
        ai_dir.mkdir(parents=True)
        desk_dir.mkdir(parents=True)

        # Create 2 portable apps: one zsync app and one rsync app, plus 1 candidate for pick-and-add
        zs_bin = ai_dir / "wordcraft-0.15.0-x86_64.AppImage"
        zs_bin.write_bytes(b"#!/bin/sh\nexit 0\n")
        zs_bin.chmod(0o755)
        zs_file = ai_dir / "wordcraft-0.15.0-x86_64.AppImage.zsync"
        zs_file.write_bytes(b"zsync: 0.6.2\nFilename: wordcraft-0.15.0-x86_64.AppImage\n\n")

        rs_bin = ai_dir / "syncnotes-1.0.0-x86_64.AppImage"
        rs_bin.write_bytes(b"#!/bin/sh\nexit 0\n")
        rs_bin.chmod(0o755)
        rs_upstream = root / "syncnotes-2.0.0-x86_64.AppImage"
        rs_upstream.write_bytes(b"#!/bin/sh\necho v2.0.0\n")
        rs_upstream.chmod(0o755)

        picked_candidate = root / "pickedtool-1.1.0-x86_64.AppImage"
        picked_candidate.write_bytes(b"#!/bin/sh\necho v1.1.0\n")
        picked_candidate.chmod(0o755)

        cfg_val.setdefault("apps", {})["editor"] = str(rs_bin)
        cfg_val["apps"].setdefault("desktopIds", {})["editor"] = "native:alis-app-syncnotes.desktop"
        (conf_dir / "config.json").write_text(json.dumps(cfg_val), encoding="utf-8")

        reg = {
            "version": 1,
            "apps": [
                {
                    "id": "wordcraft",
                    "name": "Wordcraft",
                    "kind": "appimage",
                    "storedPath": str(zs_bin),
                    "execPath": str(zs_bin),
                    "zsyncPath": str(zs_file),
                    "hasZsync": True,
                    "version": "0.15.0",
                    "updateSupported": True,
                    "updateProtocol": "zsync",
                    "updateAvailable": False,
                    "latestVersion": "0.15.0",
                    "desktopFile": str(desk_dir / "alis-app-wordcraft.desktop"),
                },
                {
                    "id": "syncnotes",
                    "name": "SyncNotes",
                    "kind": "appimage",
                    "storedPath": str(rs_bin),
                    "execPath": str(rs_bin),
                    "zsyncPath": "",
                    "hasZsync": False,
                    "version": "1.0.0",
                    "updateSupported": True,
                    "updateProtocol": "rsync",
                    "customUpdateSource": f"rsync:{rs_upstream}",
                    "rsyncUrl": str(rs_upstream),
                    "updateUrl": str(rs_upstream),
                    "updateAvailable": False,
                    "latestVersion": "1.0.0",
                    "desktopFile": str(desk_dir / "alis-app-syncnotes.desktop"),
                },
            ],
        }
        (apps_dir / "registry.json").write_text(json.dumps(reg, indent=2), encoding="utf-8")

        harness = root / "shell.qml"
        harness.write_text(
            """
import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.settings

Scope {
    id: root
    Component.onCompleted: Quickshell.watchFiles = false

    Loader {
        id: pageLoader
        active: true
        sourceComponent: Component {
            ApplicationsConfig {
                width: 520
                height: 600
            }
        }
    }

    readonly property var page: pageLoader.item

    function findByObjectName(item, target) {
        if (!item) return null
        if (item.objectName === target) return item
        const kids = item.children || []
        for (let i = 0; i < kids.length; ++i) {
            const found = findByObjectName(kids[i], target)
            if (found) return found
        }
        if (item.contentItem) {
            const found = findByObjectName(item.contentItem, target)
            if (found) return found
        }
        return null
    }

    property int step: 0
    property int observedProgressBeforeClose: -1
    property bool observedReopenedBusy: false

    Timer {
        interval: 80
        running: true
        repeat: true
        onTriggered: {
            if (root.step === 0) {
                if (!root.page || root.page.busy) return
                if ((root.page.managedApps || []).length < 2) return
                const checkBtn = root.findByObjectName(root.page, "checkPortableUpdatesButton")
                const zsBadge = root.findByObjectName(root.page, "portableUpdateBadge_wordcraft")
                const rsBadge = root.findByObjectName(root.page, "portableUpdateBadge_syncnotes")
                const rsBtn = root.findByObjectName(root.page, "portableUpdateBtn_syncnotes")
                if (!checkBtn || !zsBadge || !rsBadge || !rsBtn) {
                    console.log("FAIL: missing UI controls")
                    Qt.quit()
                    return
                }
                // Verify Launch app and Configure keybindings buttons are removed
                if (root.findByObjectName(root.page, "launchApplicationBtn_wordcraft") !== null
                    || root.findByObjectName(root.page, "launchApplicationBtn_syncnotes") !== null
                    || root.findByObjectName(root.page, "portableShortcutBtn_wordcraft") !== null
                    || root.findByObjectName(root.page, "portableShortcutBtn_syncnotes") !== null) {
                    console.log("FAIL: Launch or Shortcut buttons should have been removed")
                    Qt.quit()
                    return
                }
                if (zsBadge.badgeText !== "zsync" || rsBadge.badgeText !== "rsync") {
                    console.log("FAIL: unexpected initial badge texts:", zsBadge.badgeText, rsBadge.badgeText)
                    Qt.quit()
                    return
                }
                root.step = 1
                root.page.checkForUpdates()
            } else if (root.step === 1) {
                if (!root.page || root.page.busy) return
                const updAllBtn = root.findByObjectName(root.page, "updateAllApplicationsButton")
                const rsBadge = root.findByObjectName(root.page, "portableUpdateBadge_syncnotes")
                if (!updAllBtn || !updAllBtn.visible || root.page.updatableAppsCount !== 1) {
                    console.log("FAIL: expected 1 update available after checkForUpdates, got", root.page.updatableAppsCount, root.page.statusMessage, root.page.statusError)
                    Qt.quit()
                    return
                }
                if (rsBadge.badgeText.indexOf("rsync") === -1 || rsBadge.badgeText.indexOf("2.0.0") === -1) {
                    console.log("FAIL: expected rsync update badge with 2.0.0, got", rsBadge.badgeText)
                    Qt.quit()
                    return
                }
                root.step = 2
                root.page.updateApplication("syncnotes")
            } else if (root.step === 2) {
                // Observe live progress while update is running, then close Settings (unload ApplicationsConfig)
                if (!root.page) return
                if (!root.page.busy || root.page.progressPercent < 10) return
                const progContainer = root.findByObjectName(root.page, "portableAppsProgressContainer")
                const progPctText = root.findByObjectName(root.page, "portableAppsProgressPercentText")
                const progFill = root.findByObjectName(root.page, "portableAppsProgressFill")
                const rowProg = root.findByObjectName(root.page, "portableAppRowProgressBar_syncnotes")
                if (!progContainer || !progContainer.visible || !progPctText || !progPctText.visible || !progFill || !rowProg || !rowProg.visible) {
                    console.log("FAIL: expected progress UI visible during update")
                    Qt.quit()
                    return
                }
                root.observedProgressBeforeClose = root.page.progressPercent
                // Simulate closing Settings window while update is running
                pageLoader.active = false
                if (pageLoader.item !== null || !AppLauncher.busy || AppLauncher.updatingAppId !== "syncnotes") {
                    console.log("FAIL: expected AppLauncher to keep running update in background after closing Settings:", AppLauncher.busy, AppLauncher.updatingAppId)
                    Qt.quit()
                    return
                }
                root.step = 3
            } else if (root.step === 3) {
                // Reopen Settings while update is running in background
                pageLoader.active = true
                if (!root.page) {
                    console.log("FAIL: failed to recreate ApplicationsConfig")
                    Qt.quit()
                    return
                }
                if (root.page.busy) {
                    root.observedReopenedBusy = true
                    const progContainer2 = root.findByObjectName(root.page, "portableAppsProgressContainer")
                    if (!progContainer2 || !progContainer2.visible || root.page.updatingAppId !== "syncnotes") {
                        console.log("FAIL: reopened Settings did not show ongoing update progress:", root.page.updatingAppId, root.page.progressPercent)
                        Qt.quit()
                        return
                    }
                }
                root.step = 4
            } else if (root.step === 4) {
                if (!root.page || root.page.busy) return
                if (!root.observedReopenedBusy) {
                    console.log("FAIL: expected update to still be running when Settings was reopened")
                    Qt.quit()
                    return
                }
                if (root.page.updatableAppsCount !== 0) {
                    console.log("FAIL: expected 0 updates available after background updateApplication completed, got", root.page.updatableAppsCount, root.page.statusError)
                    Qt.quit()
                    return
                }
                const syncApp = (root.page.managedApps || []).find(a => a.id === "syncnotes")
                if (!syncApp || syncApp.version !== "2.0.0" || syncApp.execPath.indexOf("2.0.0") === -1) {
                    console.log("FAIL: expected syncnotes updated to 2.0.0, got", JSON.stringify(syncApp))
                    Qt.quit()
                    return
                }
                // Verify AppLauncher._applyDiscoveryPayload syncs Default Apps slot command when portable app execPath updates
                AppLauncher._applyDiscoveryPayload(JSON.stringify({
                    apps: [{
                        identityKey: "native:alis-app-syncnotes.desktop",
                        desktopId: "alis-app-syncnotes.desktop",
                        name: "SyncNotes",
                        exec: syncApp.execPath,
                        installed: true
                    }],
                    xdgDefaults: {},
                    toolsAvailable: { flatpak: false, xdgSettings: false, xdgMime: false }
                }))
                if (AppLauncher.commandFor("editor") !== syncApp.execPath) {
                    console.log("FAIL: AppLauncher did not sync slot command to updated execPath:", AppLauncher.commandFor("editor"), syncApp.execPath)
                    Qt.quit()
                    return
                }
                root.step = 5
                root.page.setUpdateSource("syncnotes", "rsync:/nonexistent/broken-upstream.AppImage")
            } else if (root.step === 5) {
                if (!root.page || root.page.busy) return
                root.step = 6
                root.page.updateApplication("syncnotes")
                pageLoader.active = false
            } else if (root.step === 6) {
                if (AppLauncher.busy) return
                pageLoader.active = true
                if (!root.page) {
                    console.log("FAIL: failed to reopen ApplicationsConfig after failed background update")
                    Qt.quit()
                    return
                }
                const errLabel = root.findByObjectName(root.page, "portableAppsStatusError")
                if (!errLabel || !errLabel.visible || root.page.statusError.length === 0 || root.page.busy) {
                    console.log("FAIL: expected portableAppsStatusError visible and busy=false after failed background update:", root.page.statusError, root.page.busy)
                    Qt.quit()
                    return
                }
                AppLauncher._applyPortableResult({
                    ok: false,
                    updated: ["wordcraft"],
                    error: "SyncNotes: failed",
                    apps: root.page.managedApps
                })
                const msgLabel = root.findByObjectName(root.page, "portableAppsStatusMessage")
                if (!msgLabel || !msgLabel.visible || !errLabel.visible || root.page.statusMessage !== "Updated 1 application(s).") {
                    console.log("FAIL: expected both portableAppsStatusMessage and portableAppsStatusError visible on partial batch update:", msgLabel ? msgLabel.visible : null, errLabel.visible, root.page.statusMessage, root.page.statusError)
                    Qt.quit()
                    return
                }
                // Simulate a stale stuck busy state when no process is running, verify addApplicationsButton is still enabled, then click it
                AppLauncher.busy = true
                AppLauncher.pickerActive = true
                const addBtn = root.findByObjectName(root.page, "addApplicationsButton")
                if (!addBtn || !addBtn.enabled) {
                    console.log("FAIL: expected addApplicationsButton to remain enabled when AppLauncher.busy is stale without a running process:", addBtn ? addBtn.enabled : null, root.page.busy, AppLauncher.portableProcessRunning)
                    Qt.quit()
                    return
                }
                root.step = 7
                addBtn.clicked()
                if (!AppLauncher.busy || !AppLauncher.portableAppsBusy || !AppLauncher.pickerActive || !GlobalStates.settingsNativeDialogOpen) {
                    console.log("FAIL: expected addApplicationsButton click to recover stale busy and set pickerActive + GlobalStates.settingsNativeDialogOpen:", AppLauncher.busy, AppLauncher.portableAppsBusy, AppLauncher.pickerActive, GlobalStates.settingsNativeDialogOpen)
                    Qt.quit()
                    return
                }
            } else if (root.step === 7) {
                if (!root.page || root.page.busy) return
                if (AppLauncher.pickerActive || GlobalStates.settingsNativeDialogOpen) {
                    console.log("FAIL: expected pickerActive and GlobalStates.settingsNativeDialogOpen to be released after pickAndAddApplications:", AppLauncher.pickerActive, GlobalStates.settingsNativeDialogOpen)
                    Qt.quit()
                    return
                }
                const pickedApp = (root.page.managedApps || []).find(a => a.id === "pickedtool")
                if (!pickedApp || !pickedApp.installed) {
                    console.log("FAIL: expected pickedtool to be added via pickAndAddApplications:", JSON.stringify(root.page.managedApps))
                    Qt.quit()
                    return
                }
                console.log("PORTABLE_UI_TEST_OK")
                Qt.quit()
            }
        }
    }
}
""",
            encoding="utf-8",
        )

        runtime_dir = root / "runtime"
        runtime_dir.mkdir(mode=0o700, exist_ok=True)
        base_env = dict(os.environ, XDG_RUNTIME_DIR=str(runtime_dir))
        for k in ["WAYLAND_DISPLAY", "NIRI_SOCKET", "DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE", "QS_CONFIG_NAME", "QS_CONFIG_PATH", "QS_MANIFEST"]:
            base_env.pop(k, None)
        for kind in ["config", "cache", "data", "state"]:
            base_env[f"XDG_{kind.upper()}_HOME"] = str(root / kind)

        sock = "wayland-alis-portable-ui"
        kwin = subprocess.Popen(
            ["kwin_wayland", "--virtual", "--socket", sock, "--width", "1024", "--height", "768"],
            env=base_env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        try:
            import time
            for _ in range(80):
                if (runtime_dir / sock).exists():
                    break
                time.sleep(0.05)

            env = dict(
                base_env,
                WAYLAND_DISPLAY=sock,
                QT_QPA_PLATFORM="wayland",
                QT_QUICK_BACKEND="software",
                QSG_RHI_BACKEND="software",
                ALIS_PORTABLE_APPS_DATA_HOME=str(data_home),
                ALIS_PORTABLE_APPS_SIMULATE_UPDATE_MS="900",
                ALIS_PORTABLE_APPS_MOCK_PICK_FILES=str(picked_candidate),
                ALIS_PORTABLE_APPS_MOCK_PICK_DELAY_MS="120",
            )
            res = subprocess.run(
                [qs_bin, "-p", str(root), "-n"],
                env=env,
                capture_output=True,
                text=True,
                timeout=30,
            )
        finally:
            if kwin.poll() is None:
                os.killpg(kwin.pid, 15)
                try:
                    kwin.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    os.killpg(kwin.pid, 9)

        combined = (res.stdout or "") + "\n" + (res.stderr or "")
        assert "ReferenceError:" not in combined and "TypeError:" not in combined, f"Unexpected QML error in output:\n{combined}"
        assert "PORTABLE_UI_TEST_OK" in combined, f"Headless UI test failed:\n{combined}"
        print("PASS: ApplicationsConfig.qml & AppLauncher headless check/update/pick-and-add UI test")


if __name__ == "__main__":
    test_backend_protocols()
    test_ui_headless_quickshell()
