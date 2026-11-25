#!/usr/bin/env python3
"""Offline contract for the user-triggered Alis-Intergration package manager."""
import importlib.util
import io
import json
import pathlib
import stat
import tarfile
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("manager", ROOT / "scripts/alis-intergration-manager.py")
manager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(manager)
revision1 = "1" * 40
revision2 = "2" * 40
manifest = {
    "id": "alis-intergration", "version": "0.2.0", "hostApi": 1,
    "session": manager.discovery.ENTRYPOINTS["session"],
    "settings": {
        "tlp": manager.discovery.ENTRYPOINTS["tlpSettings"],
        "thinkfan": manager.discovery.ENTRYPOINTS["thinkfanSettings"],
        "nexus": manager.discovery.ENTRYPOINTS["nexusSettings"],
        "nexusTodo": manager.discovery.ENTRYPOINTS["nexusTodoSettings"],
        "tlpRow": manager.discovery.ENTRYPOINTS["tlpRowSettings"],
        "tlpWaffle": manager.discovery.ENTRYPOINTS["tlpWaffleSettings"],
        "tlpWaffleRow": manager.discovery.ENTRYPOINTS["tlpWaffleRowSettings"],
    },
    "backends": {
        "managedTodo": manager.discovery.ENTRYPOINTS["managedTodo"],
        "dailyTodo": manager.discovery.ENTRYPOINTS["dailyTodo"],
    },
}


def make_tar(entries):
    """Simulate codeload tarballs, including explicit nested directory headers."""
    with io.BytesIO() as stream:
        with tarfile.open(fileobj=stream, mode="w:gz") as handle:
            created = set()

            def add_dir(directory):
                if directory in created:
                    return
                info = tarfile.TarInfo("source/" + directory + "/")
                info.type = tarfile.DIRTYPE
                handle.addfile(info)
                created.add(directory)

            add_dir("")
            for name, data in entries:
                parts = pathlib.PurePosixPath(name).parts
                for index in range(1, len(parts)):
                    add_dir("/".join(parts[:index]))
                info = tarfile.TarInfo("source/" + name)
                info.size = len(data)
                handle.addfile(info, io.BytesIO(data))
        return stream.getvalue()


def bundle(version):
    files = [("manifest.json", json.dumps({**manifest, "version": version}).encode())]
    for entry in set(manager.discovery.ENTRYPOINTS.values()):
        files.append((entry, ("import QtQuick\nItem {} // " + version).encode()))
    files.append(("scripts/notes/worker.py", b"no execution"))
    files.append(("assets/helpers/alis-thinkfan", b"fake helper"))
    return make_tar(files)


with tempfile.TemporaryDirectory(prefix="alis-intergration-manager-test-") as location:
    base = pathlib.Path(location)
    home = base / "data/alis-intergration"
    shell = base / "shell"
    shell.mkdir()
    requested = []
    system_calls = []
    system_enabled = False
    gateway_calls = []

    def gateway_callback(action):
        gateway_calls.append(action)
        installed = action == "gateway-install"
        return {"ok": True, "installed": installed, "packageInstalled": installed,
                "diagnostic": "ready" if installed else "not-installed",
                "message": "Synthetic gateway package receipt"}

    def system_callback(action, package):
        # no privileged executable runs in this fixture
        system_calls.append((action, str(package) if package else None))
        if action == 'helpers-status':
            return {'ok': True, 'installed': system_enabled, 'provisionerAvailable': True,
                    'diagnostic': 'ready' if system_enabled else 'not-installed'}
        return {'ok': True, 'installed': action == 'helpers-install', 'provisionerAvailable': True,
                'diagnostic': 'ready' if action == 'helpers-install' else 'not-installed'}

    def fetch_sha():
        requested.append("lookup")
        return revision1 if requested.count("lookup") <= 2 else revision2

    def fetch_archive(url, limit):
        requested.append("archive")
        assert limit == manager.MAX_ARCHIVE
        assert url.startswith(manager.ARCHIVE)
        return bundle("0.2.0" if revision1 in url else "0.3.0")

    def run(action):
        return manager.operate(action, home, shell, fetch_sha, fetch_archive,
                               system_callback, gateway_callback)

    state = run("status")
    assert not state["available"] and requested == []
    assert run("check")["updateAvailable"] and requested == ["lookup"]
    assert not (home / "current").exists()
    install = run("install")
    assert install["installedSha"] == revision1 and install["version"] == "0.2.0"
    assert manager.discovery.inspect(shell, base / "data")["available"]
    installed_manifest = (home / "current/manifest.json").read_bytes()
    release = (home / "current").resolve()
    pycache = release / "scripts/notes/__pycache__"
    pycache.mkdir(parents=True, exist_ok=True)
    (pycache / "worker.cpython-314.pyc").write_bytes(b"bytecode")
    assert manager.package_good(release, revision1)
    assert manager.discovery.inspect(shell, base / "data")["available"]
    (pycache / "worker.cpython-314.pyc").unlink()
    pycache.rmdir()
    (release / "unlisted.qml").write_text("not in verified inventory")
    assert not manager.package_good(release, revision1)
    assert not manager.discovery.inspect(shell, base / "data")["available"]
    assert run("status")["diagnostic"] == "invalid-package"
    assert run("helpers-status")["systemProvisionerAvailable"] is True
    (release / "unlisted.qml").unlink()
    data = json.loads(installed_manifest); data["hostApi"] = True
    (release / "manifest.json").write_text(json.dumps(data))
    assert not manager.package_good(release, revision1)
    (release / "manifest.json").write_bytes(installed_manifest)
    assert manager.package_good(release, revision1)
    files = json.loads((home / "current/manifest.json").read_text())["files"]
    assert "scripts/notes/worker.py" in files
    helper = home / "current/assets/helpers/alis-thinkfan"
    assert stat.S_IMODE(helper.stat().st_mode) == 0o755
    assert helper.read_bytes() == b"fake helper"
    assert not (home / "current/assets/helpers/\x68\x61\x64\x61\x6c\x69\x73-thinkfan").exists(), "external package path was renamed"
    assert stat.S_IMODE((home / "current/scripts/notes/worker.py").stat().st_mode) == 0o644
    assert "manifest.json" not in files
    assert run("status")["available"]
    assert requested.count("archive") == 1
    assert not run("gateway-status")["systemProvisionerAvailable"]
    assert run("gateway-install")["systemProvisionerAvailable"]
    assert run("gateway-install")["gatewayPackageInstalled"]
    assert not run("gateway-remove")["gatewayPackageInstalled"]
    assert gateway_calls == ["gateway-status", "gateway-install", "gateway-install", "gateway-remove"]
    assert (home / "current").exists()  # gateway never touches the user package
    # Read-only post-restart system reconciliation uses no codeload/network.
    before = requested[:]
    state = run("system-status")
    assert not state["systemHelpersInstalled"]
    assert state["systemProvisionerAvailable"]
    assert not state["gatewayPackageInstalled"]
    assert state["systemHelpersDiagnostic"] == "not-installed"
    assert requested == before
    # Full distro-owned provisioners work even without standalone gateway.
    state = manager.operate(
        "system-status", home, shell, fetch_sha, fetch_archive,
        lambda action, package: {"installed": True,
                                 "provisionerAvailable": True, "diagnostic": "ready"},
        lambda action: (_ for _ in ()).throw(ValueError("not Arch")))
    assert state["systemHelpersInstalled"] and state["systemProvisionerAvailable"]
    assert not state["gatewayPackageInstalled"]
    assert not run("helpers-status")["systemHelpersInstalled"]
    helpers = run("helpers-install")
    assert helpers["systemHelpersInstalled"] and helpers["systemProvisionerAvailable"]
    assert system_calls[-1] == ("helpers-install", str((home / "current").resolve()))
    assert not run("helpers-remove")["systemHelpersInstalled"]
    assert (home / "current").exists()  # provisioning never removes the package

    # One-click install and reinstall: gateway provisioning happens only
    # when absent; the privileged helper install is idempotent and does not
    # remove already-verified existing files.
    ensure_calls = []
    gateway_present = [False]

    def gateway_ensure(action):
        ensure_calls.append(action)
        if action == "gateway-install":
            gateway_present[0] = True
        return {"ok": True, "installed": gateway_present[0],
                "packageInstalled": gateway_present[0],
                "diagnostic": "ready" if gateway_present[0] else "not-installed"}

    def helpers_ensure(action, package):
        ensure_calls.append((action, str(package) if package else None))
        if action == "helpers-status":
            return {"ok": True, "installed": False,
                    "provisionerAvailable": gateway_present[0],
                    "diagnostic": "ready" if gateway_present[0] else "not-installed"}
        assert action == "helpers-install"
        assert pathlib.Path(package) == (home / "current").resolve()
        return {"ok": True, "installed": True, "provisionerAvailable": True,
                "diagnostic": "ready"}

    def ensure():
        return manager.operate("helpers-ensure", home, shell, fetch_sha,
                               fetch_archive, helpers_ensure, gateway_ensure)

    first = ensure()
    assert first["systemHelpersInstalled"] and first["gatewayPackageInstalled"]
    assert ensure_calls == ["gateway-status", ("helpers-status", None),
                            "gateway-install",
                            ("helpers-install", str((home / "current").resolve()))]
    ensure_calls.clear()
    again = ensure()
    assert again["systemHelpersInstalled"]
    assert ensure_calls == ["gateway-status", ("helpers-status", None),
                            ("helpers-install", str((home / "current").resolve()))]
    # A cancelled gateway auth must never fall through to root-helper install.
    gateway_present[0] = False
    ensure_calls.clear()
    def refused_gateway(action):
        ensure_calls.append(action)
        if action == "gateway-install":
            raise ValueError("authorization cancelled")
        return {"installed": False}
    try:
        manager.operate("helpers-ensure", home, shell, fetch_sha,
                        fetch_archive, helpers_ensure, refused_gateway)
        raise AssertionError("Cancelled gateway authorization accepted")
    except ValueError as error:
        assert "cancelled" in str(error)
    assert ensure_calls == ["gateway-status", ("helpers-status", None),
                            "gateway-install"]

    # Existing trusted gateway owned by the full Arch shell must be reused
    # without trying to install a conflicting standalone pacman package.
    ensure_calls.clear()
    def installed_system_gateway(action, package):
        if action == "helpers-status":
            ensure_calls.append(("helpers-status", None))
            return {"ok": True, "installed": False, "provisionerAvailable": True}
        return helpers_ensure(action, package)
    out = manager.operate("helpers-ensure", home, shell, fetch_sha,
                          fetch_archive, installed_system_gateway,
                          lambda action: {"installed": False, "packageInstalled": False})
    assert out["systemHelpersInstalled"]
    assert ensure_calls == [("helpers-status", None),
                            ("helpers-install", str((home / "current").resolve()))]

    upgrade = run("install")
    assert upgrade["installedSha"] == revision2 and upgrade["canRollback"]
    assert (home / "releases" / revision1).is_dir()
    # If the active release is corrupted, check/rollback/install recover cleanly.
    (home / "releases" / revision2 / "corrupted.qml").write_text("corrupted")
    assert run("status")["diagnostic"] == "invalid-package"
    assert run("check")["updateAvailable"]
    assert run("rollback")["installedSha"] == revision1
    (home / "releases" / revision2 / "corrupted.qml").unlink()
    assert run("install")["installedSha"] == revision2
    assert run("rollback")["installedSha"] == revision1
    assert run("status")["installedSha"] == revision1

    # Previous versions are kept; removal never clears data, enables workers or
    # performs privileged system installation.
    assert not run("remove")["available"]
    assert (home / "releases" / revision1).exists()
    assert (home / "releases" / revision2).exists()
    assert not (home / "current").exists()

    foreign = base / "foreign"
    foreign.mkdir()
    (home / "current").symlink_to(foreign)
    try:
        run("remove")
        raise AssertionError("Unowned link was removed")
    except ValueError:
        pass
    assert foreign.is_dir()
    (home / "current").unlink()

    for payload in [
        make_tar([("manifest.json", b"{}"), ("manifest.json", b"{}")]),
        make_tar([("manifest.json", b"{}")]),
        make_tar([("manifest.json", json.dumps({**manifest, "hostApi": 2}).encode())]),
    ]:
        try:
            manager.assemble(manager.unpack(payload), revision1, base / "invalid")
            raise AssertionError("Malformed package accepted")
        except ValueError:
            pass
    try:
        manager.unpack(make_tar([("ignored/" + str(n), b"") for n in range(manager.MAX_MEMBERS + 1)]))
        raise AssertionError("Unbounded archive members accepted")
    except ValueError:
        pass
    try:
        manager.unpack(make_tar([("../escape", b"bad")]))
        raise AssertionError("Path traversal accepted")
    except ValueError:
        pass

    # Empty directory members are legal codeload metadata; links in an
    # allowlisted QML directory are not. This is independent of the user
    # package lifecycle tests above, which include nested directory headers.
    assert manager.unpack(make_tar([("modules/settings/Control.qml", b"safe")])) == {
        "modules/settings/Control.qml": b"safe"
    }
    for link_type in (tarfile.SYMTYPE, tarfile.LNKTYPE):
        with io.BytesIO() as stream:
            with tarfile.open(fileobj=stream, mode="w:gz") as handle:
                info = tarfile.TarInfo("source/modules/settings/linked.qml")
                info.type = link_type
                info.linkname = "Control.qml"
                handle.addfile(info)
            invalid_archive = stream.getvalue()
        try:
            manager.unpack(invalid_archive)
            raise AssertionError("Nonregular package link accepted")
        except ValueError:
            pass

    (shell / "optional/alis-intergration").mkdir(parents=True)
    assert run('helpers-status')['systemProvisionerAvailable']
    assert run('helpers-install')['systemHelpersInstalled']
    try:
        run("install")
        raise AssertionError("Bundled integration was overwritten")
    except ValueError:
        pass

# A child crash after a privileged transaction cannot disappear as an
# unexplained generic receipt failure. Show the exit status and bounded cause.
from unittest.mock import patch
from types import SimpleNamespace
for result, diagnostic in (
    (SimpleNamespace(returncode=1, stdout="", stderr="NameError: name 'p' is not defined"), "NameError"),
    (SimpleNamespace(returncode=0, stdout="garbage", stderr=""), "check gateway package status"),
):
    with patch.object(manager.subprocess, "run", return_value=result):
        try:
            manager.gateway_package("gateway-status")
            raise AssertionError("Non-JSON gateway result was accepted")
        except ValueError as error:
            assert diagnostic in str(error), str(error)

for raw in ("null", "[]", '{"ok":"true"}', '{"ok":true,"installed":false,"managed":false}'):
    with patch.object(manager.os.path, "isfile", return_value=True), patch.object(manager.os, "access", return_value=True), patch.object(manager.shutil, "which", return_value="fixture"), patch.object(manager.subprocess, "run", return_value=SimpleNamespace(returncode=0, stdout=raw)):
        try:
            manager.call_system_helper("helpers-install", pathlib.Path("/synthetic"))
            raise AssertionError("Malformed or unsuccessful helper state accepted")
        except ValueError:
            pass

# Large GitHub /commits/main JSON payload (> 256 KB, e.g. 4.2 MB multi-file diff)
# must succeed via MAX_COMMIT_META without throwing download limit errors, and
# > MAX_COMMIT_META falls back cleanly to /git/ref/heads/main commit ref.
large_sha = "c" * 40
large_commit_json = json.dumps({
    "sha": large_sha,
    "files": [{"filename": "big.diff", "patch": "x" * (4 * 1024 * 1024)}],
}).encode("utf-8")
assert len(large_commit_json) > 4 * 1024 * 1024
seen_limits = []


def fake_large_request(url, limit):
    seen_limits.append((url, limit))
    assert url == manager.API
    assert limit == manager.MAX_COMMIT_META
    assert len(large_commit_json) <= limit
    return large_commit_json


with patch.object(manager, "request_bytes", side_effect=fake_large_request):
    assert manager.latest_sha() == large_sha
assert seen_limits == [(manager.API, manager.MAX_COMMIT_META)]

fallback_sha = "d" * 40
fallback_calls = []


def fake_fallback_request(url, limit):
    fallback_calls.append((url, limit))
    if url == manager.API:
        raise ValueError("Package download exceeds the configured limit")
    assert url == manager.API_REF
    return json.dumps({"object": {"type": "commit", "sha": fallback_sha}}).encode("utf-8")


with patch.object(manager, "request_bytes", side_effect=fake_fallback_request):
    assert manager.latest_sha() == fallback_sha
assert fallback_calls == [(manager.API, manager.MAX_COMMIT_META), (manager.API_REF, 256 * 1024)]

# Compiled assets/bin/alis-nexus (> 2 MB) unpacks cleanly within MAX_FILE_SIZE,
# while files exceeding MAX_FILE_SIZE are still rejected.
large_bin = b"\x7fELF" + (b"0" * (2 * 1024 * 1024 + 512 * 1024))
unpacked_bin = manager.unpack(make_tar([("assets/bin/alis-nexus", large_bin)]))
assert unpacked_bin["assets/bin/alis-nexus"] == large_bin

try:
    manager.unpack(make_tar([("assets/bin/alis-nexus", b"\0" * (manager.MAX_FILE_SIZE + 1))]))
    raise AssertionError("File larger than MAX_FILE_SIZE accepted")
except ValueError as error:
    assert "Oversized package file" in str(error)

# Base-v2 + per-plugin GitHub release tarball + SHA256SUMS + omission of khal/curl.
with tempfile.TemporaryDirectory(prefix="alis-base-v2-mgr-") as tmp2:
    b2 = pathlib.Path(tmp2)
    home2 = b2 / "home"
    data2 = b2 / "home_parent"
    real_data2 = data2 / "alis-intergration"
    res_base = manager.operate("install-base", real_data2, pathlib.Path(ROOT))
    assert res_base["ok"] and (real_data2 / "current" / "AlisSession.qml").is_file()
    assert not (real_data2 / "plugins").exists()
    assert not (real_data2 / "current" / "plugins").exists()
    insp_base = manager.discovery.inspect(ROOT, data2)
    assert insp_base["layout"] == "base-v2" and insp_base["installedPluginIds"] == []
    assert "khal" not in insp_base["runtimeTools"] and "curl" not in insp_base["runtimeTools"]

    buf_nx = io.BytesIO()
    with tarfile.open(fileobj=buf_nx, mode="w:gz") as th:
        for arc, data in (
            ("plugins/nexus/modules/settings/NexusThemeSettings.qml", b"import QtQuick\nItem {}\n"),
            ("plugins/nexus/plugin-manifest.json", json.dumps({"id": "nexus", "sourceSha": "e" * 40}).encode()),
        ):
            info = tarfile.TarInfo(arc)
            info.size = len(data)
            th.addfile(info, io.BytesIO(data))
    nx_bytes = buf_nx.getvalue()
    nx_sha = manager.sha256(nx_bytes)
    release_doc = json.dumps({
        "assets": [
            {"name": "alis-intergration-plugin-nexus.tar.gz", "browser_download_url": "https://github.com/llocphann/Alis-Intergration/releases/download/v1/alis-intergration-plugin-nexus.tar.gz"},
            {"name": "SHA256SUMS", "browser_download_url": "https://github.com/llocphann/Alis-Intergration/releases/download/v1/SHA256SUMS"},
        ]
    }).encode("utf-8")
    requested_urls = []

    def fake_rel_req(url, limit):
        requested_urls.append(url)
        if url == manager.RELEASES_API:
            return release_doc
        if url.endswith("alis-intergration-plugin-nexus.tar.gz"):
            return nx_bytes
        if url.endswith("SHA256SUMS"):
            return f"{nx_sha}  alis-intergration-plugin-nexus.tar.gz\n".encode("utf-8")
        raise AssertionError(f"Unexpected URL fetched: {url}")

    with patch.object(manager, "request_bytes", side_effect=fake_rel_req):
        res_nx = manager.operate("install-plugin", real_data2, pathlib.Path(ROOT), plugin_id="nexus")
    assert res_nx["ok"] and res_nx["installedPluginIds"] == ["nexus"]
    assert all("tlp" not in u and "thinkfan" not in u and "spaced_repetition" not in u for u in requested_urls)
    assert (real_data2 / "plugins" / "nexus" / "modules/settings/NexusThemeSettings.qml").is_file()
    assert not (real_data2 / "plugins" / "tlp").exists()

    # Corrupted release checksum must be rejected before extracting.
    def fake_bad_checksum(url, limit):
        if url == manager.RELEASES_API:
            return release_doc
        if url.endswith("SHA256SUMS"):
            return f"{'0' * 64}  alis-intergration-plugin-nexus.tar.gz\n".encode("utf-8")
        return nx_bytes

    with patch.object(manager, "request_bytes", side_effect=fake_bad_checksum):
        try:
            manager._try_github_release_plugin("nexus")
            raise AssertionError("Bad checksum release tarball was accepted")
        except ValueError as err:
            assert "checksum mismatch" in str(err).lower()

    # Release missing SHA256SUMS must be rejected rather than silently extracted unverified.
    no_sums_doc = json.dumps({
        "assets": [
            {"name": "alis-intergration-plugin-nexus.tar.gz", "browser_download_url": "https://github.com/llocphann/Alis-Intergration/releases/download/v1/alis-intergration-plugin-nexus.tar.gz"},
        ]
    }).encode("utf-8")
    with patch.object(manager, "request_bytes", side_effect=lambda url, limit: no_sums_doc if url == manager.RELEASES_API else nx_bytes):
        assert manager._try_github_release_plugin("nexus") is None, "Release asset without SHA256SUMS must not be accepted"

    # Reusing already-intact installed plugin must succeed offline (e.g. `./setup integrations install <id>` after UI install).
    def fail_offline(*_a, **_kw):
        raise OSError("offline")
    res_reuse = manager.operate("install-plugin", real_data2, pathlib.Path(ROOT), plugin_id="nexus",
                                revision_fetch=fail_offline, archive_fetch=fail_offline, reuse_installed=True)
    assert res_reuse["ok"] and "nexus" in res_reuse["installedPluginIds"]

print("ALIS_INTERGRATION_MANAGER_PASS explicit install/update/rollback/remove, immutable SHA, package validation, no shell/privilege")
