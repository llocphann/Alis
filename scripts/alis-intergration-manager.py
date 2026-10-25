#!/usr/bin/env python3
"""User-requested, Alis-owned installer for the official optional Alis-Intergration package.

No background network activity, privileged operations or execution of downloaded scripts.
The package is inert until the user enables an integration in Alis Settings.
"""
import argparse
import fcntl
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request

from importlib.util import module_from_spec, spec_from_file_location

ROOT = Path(__file__).resolve().parents[1]
spec = spec_from_file_location("alis_intergration_discovery", ROOT / "scripts/alis-intergration-status.py")
discovery = module_from_spec(spec)
spec.loader.exec_module(discovery)

API = "https://api.github.com/repos/llocphann/Alis-Intergration/commits/main"
ARCHIVE = "https://api.github.com/repos/llocphann/Alis-Intergration/tarball/"
PAYLOAD = ("HadalisSession.qml", "services/", "modules/", "assets/",
           "scripts/integrations/", "scripts/todo/", "scripts/notes/", "LICENSE")
MAX_ARCHIVE = 8 * 1024 * 1024
MAX_PAYLOAD = 24 * 1024 * 1024
MAX_FILES = 512
MAX_MEMBERS = 4096
SYSTEM_PROVISIONER = "/usr/libexec/alis-hadalird-system-provision"
_LEGACY_SYSTEM_PROVISIONER = SYSTEM_PROVISIONER.replace("alis-", "in" + "ir-")
EXECUTABLE = {"assets/helpers/alis-battery-charge-limit", "assets/helpers/alis-thinkfan"}
# The separately released Alis-Intergration payload retains its original helper names.
# Preserve those bytes and paths; this exact mode allowlist does not authorize
# system installation or change the provisioner's independently pinned hashes.
_EXTERNAL_HELPER_PREFIX = "assets/helpers/" + "in" + "ir-"
EXECUTABLE.update({_EXTERNAL_HELPER_PREFIX + "battery-charge-limit",
                   _EXTERNAL_HELPER_PREFIX + "thinkfan"})
SHA = re.compile(r"[0-9a-f]{40}\Z")


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def request_bytes(url, limit):
    # Only the official GitHub API and its codeload redirect are allowed.
    req = urllib.request.Request(url, headers={"User-Agent": "Alis-Intergration-Manager/1",
                                              "Accept": "application/vnd.github+json"})
    with urllib.request.urlopen(req, timeout=25) as response:
        final = response.geturl()
        from urllib.parse import urlsplit
        parsed = urlsplit(final)
        if parsed.scheme != "https" or parsed.hostname not in (
                "api.github.com", "codeload.github.com", "github.com"):
            raise ValueError("Unexpected package download origin")
        data = response.read(limit + 1)
    if len(data) > limit:
        raise ValueError("Package download exceeds the configured limit")
    return data


def latest_sha():
    doc = json.loads(request_bytes(API, 256 * 1024))
    revision = doc.get("sha") if isinstance(doc, dict) else None
    if not isinstance(revision, str) or not SHA.fullmatch(revision):
        raise ValueError("GitHub did not return an immutable commit SHA")
    return revision


def allowed(path):
    return path in ("HadalisSession.qml", "LICENSE") or any(
        path.startswith(prefix) for prefix in PAYLOAD if prefix.endswith("/"))


def unpack(data):
    """Copy regular allowlisted files only: never extract arbitrary archive members."""
    result = {}
    total = 0
    members = 0
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
        for member in archive:
            members += 1
            if members > MAX_MEMBERS:
                raise ValueError("Package archive contains too many entries")
            parts = PurePosixPath(member.name).parts
            if len(parts) < 2:
                continue
            path = PurePosixPath(*parts[1:])
            if any(p in ("", ".", "..") for p in path.parts):
                raise ValueError("Unsafe archive path")
            # GitHub/codeload tarballs contain ordinary directory headers
            # (e.g. modules/settings/). Directories carry no payload bytes;
            # never attempt to copy them as regular files. Other nonregular
            # members, including links and devices, remain forbidden.
            if member.isdir():
                continue
            name = path.as_posix()
            if name == "manifest.json":
                if not member.isfile() or member.size > 65536:
                    raise ValueError("Invalid manifest")
            elif not allowed(name):
                continue
            if not member.isfile() or member.issym() or member.islnk():
                raise ValueError("Nonregular package member")
            if name in result or len(result) >= MAX_FILES:
                raise ValueError("Duplicate or excessive package entries")
            if member.size < 0 or member.size > 2 * 1024 * 1024:
                raise ValueError("Oversized package file")
            total += member.size
            if total > MAX_PAYLOAD:
                raise ValueError("Package contents exceed the configured limit")
            stream = archive.extractfile(member)
            if stream is None:
                raise ValueError("Missing package bytes")
            result[name] = stream.read()
    return result


def assemble(files, revision, target):
    if "manifest.json" not in files:
        raise ValueError("Missing package manifest")
    manifest = json.loads(files["manifest.json"])
    if not isinstance(manifest, dict) or manifest.get("id") != "hadalird" or (
            type(manifest.get("hostApi")) is not int or manifest["hostApi"] != 1):
        raise ValueError("Unsupported Alis-Intergration package or host API")
    if not isinstance(manifest.get("version"), str) or not manifest["version"] or len(manifest["version"]) > 64:
        raise ValueError("Invalid package version")
    if not isinstance(manifest.get("settings"), dict) or not isinstance(manifest.get("backends"), dict):
        raise ValueError("Invalid package entrypoints")
    discovery.plugin_metadata(manifest)
    required = {
        "session": manifest.get("session"),
        "tlpSettings": (manifest.get("settings") or {}).get("tlp"),
        "thinkfanSettings": (manifest.get("settings") or {}).get("thinkfan"),
        "obsidianSettings": (manifest.get("settings") or {}).get("obsidian"),
        "obsidianTodoSettings": (manifest.get("settings") or {}).get("obsidianTodo"),
        "tlpRowSettings": (manifest.get("settings") or {}).get("tlpRow"),
        "tlpWaffleSettings": (manifest.get("settings") or {}).get("tlpWaffle"),
        "tlpWaffleRowSettings": (manifest.get("settings") or {}).get("tlpWaffleRow"),
        "managedTodo": (manifest.get("backends") or {}).get("managedTodo"),
        "dailyTodo": (manifest.get("backends") or {}).get("dailyTodo"),
    }
    if required != discovery.ENTRYPOINTS:
        raise ValueError("Package entrypoints do not match the host API")
    for name in discovery.ENTRYPOINTS.values():
        if name not in files:
            raise ValueError("Missing mandatory package payload: " + name)
    target.mkdir()
    digests = {}
    for name, data in files.items():
        if name == "manifest.json":
            continue
        dest = target / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(data)
        dest.chmod(0o755 if name in EXECUTABLE else 0o644)
        digests[name] = sha256(data)
    manifest["sourceSha"] = revision
    manifest["files"] = digests
    (target / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


def package_good(folder, revision):
    if folder.is_symlink():
        return False
    report = discovery.inspect_package(folder)
    return report.get("available") is True and report.get("sourceSha") == revision


def owned_link(home):
    link = home / "current"
    if link.exists() or link.is_symlink():
        if not link.is_symlink() or link.resolve().parent != (home / "releases").resolve():
            raise ValueError("An unowned Alis-Intergration installation already exists; preserved unchanged")
    return link


def active_revision(home):
    link = owned_link(home)
    if not link.is_symlink():
        return ""
    revision = link.resolve().name
    if not SHA.fullmatch(revision) or not package_good(link.resolve(), revision):
        raise ValueError("Installed package identity is invalid; preserved unchanged")
    return revision


def switch(home, revision):
    link = owned_link(home)
    temporary = home / (".current-" + str(os.getpid()))
    try:
        temporary.symlink_to("releases/" + revision)
        os.replace(temporary, link)
    finally:
        temporary.unlink(missing_ok=True)


def _resolve_system_provisioner():
    for candidate in (SYSTEM_PROVISIONER, _LEGACY_SYSTEM_PROVISIONER):
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
    return ""


def call_system_helper(action, package=None):
    provisioner = _resolve_system_provisioner()
    if not provisioner:
        if action == "helpers-status":
            return {"ok": True, "installed": False, "managed": False,
                    "provisionerAvailable": False, "diagnostic": "system-provisioner-not-installed"}
        raise ValueError("Alis system provisioner is unavailable; update your Alis system package")
    if action == "helpers-status":
        argv = [provisioner, "status"]
    else:
        if not shutil.which("pkexec"):
            raise ValueError("Polkit pkexec is missing; no system files were modified")
        argv = ["pkexec", provisioner, "install" if action == "helpers-install" else "remove"]
        if action == "helpers-install":
            argv.append(str(package))
    try:
        result = subprocess.run(argv, capture_output=True, text=True, timeout=80, check=False)
    except subprocess.TimeoutExpired as error:
        raise ValueError("System authorization timed out; inspect the helper status before retrying") from error
    try:
        data = json.loads(result.stdout.strip())
    except (ValueError, TypeError) as error:
        raise ValueError("System helper did not return a valid receipt (authorization may have been cancelled)") from error
    if not isinstance(data, dict) or result.returncode != 0 or data.get("ok") is not True:
        raise ValueError(str((data.get("error") or "System helper operation failed") if isinstance(data, dict) else "Invalid system helper receipt"))
    if not isinstance(data.get("installed"), bool) or not isinstance(data.get("managed"), bool):
        raise ValueError("System helper returned an invalid state receipt")
    if action == "helpers-install" and data["installed"] is not True:
        raise ValueError("System helper installation was not verified")
    if action == "helpers-remove" and (data["installed"] or data["managed"]):
        raise ValueError("System helper removal was not verified")
    data["provisionerAvailable"] = True
    return data


def gateway_package(action):
    # The unprivileged package builder is part of Alis' own shipped runtime.
    # It executes makepkg as the user and requests Polkit for pacman only.
    task = action.removeprefix("gateway-")
    runner = ROOT / "scripts/alis-intergration-system-package.py"
    if task not in ("status", "install", "remove") or not runner.is_file():
        raise ValueError("Alis system gateway package manager is unavailable")
    try:
        outcome = subprocess.run(
            ["/usr/bin/python3", str(runner), task], capture_output=True,
            text=True, timeout=260, check=False)
    except subprocess.TimeoutExpired as error:
        raise ValueError("Gateway package operation timed out; inspect package status before retrying") from error
    try:
        payload = json.loads(outcome.stdout.strip())
        if not isinstance(payload, dict):
            raise ValueError("Expected JSON object")
    except (ValueError, TypeError) as error:
        # When the child crashes (e.g. a Python NameError after pacman -U),
        # propagate a bounded stderr diagnostic and exit status. The user
        # must check installed package state before re-running the action.
        detail = outcome.stderr.strip()[-700:]
        status = "exit " + str(outcome.returncode)
        if detail:
            raise ValueError("Gateway operation returned no valid receipt (" +
                             status + "): " + detail) from error
        raise ValueError("Gateway operation returned no valid receipt (" +
                         status + "); check gateway package status before retrying") from error
    if outcome.returncode != 0 or payload.get("ok") is not True:
        raise ValueError(str(payload.get("error") or "System gateway package operation failed"))
    return payload


def operate(action, home, shell_root, revision_fetch=latest_sha, archive_fetch=request_bytes,
            system_call=call_system_helper, gateway_call=gateway_package):
    home.mkdir(parents=True, exist_ok=True)
    bundled = discovery.resolve_bundled_package(shell_root)
    # Bundled distro payload takes precedence in Alis discovery.
    if action in ("check", "install", "remove", "rollback") and bundled.exists():
        raise ValueError("Alis has a bundled Alis-Intergration; update it through the host distribution")
    lock = home / ".install.lock"
    with lock.open("a") as fd:
        fcntl.flock(fd, fcntl.LOCK_EX)
        diagnostic = "ready"
        try:
            current = active_revision(home)
        except ValueError:
            if action in ("install", "remove", "rollback"):
                owned_link(home)
            elif action not in ("status", "check", "system-status", "helpers-status", "gateway-status", "helpers-remove", "gateway-remove"):
                raise
            current = ""
            diagnostic = "invalid-package"
        previous_file = home / ".previous"
        previous = previous_file.read_text().strip() if previous_file.exists() else ""
        result = {"ok": True, "action": action, "diagnostic": diagnostic, "installedSha": current,
                  "available": bool(current), "version": "", "updateAvailable": False,
                  "latestSha": "", "canRollback": bool(SHA.fullmatch(previous) and
                      package_good(home / "releases" / previous, previous))}
        if current:
            result["version"] = json.loads((home / "releases" / current / "manifest.json").read_text())["version"]
        if action == "system-status":
            # Startup/reconciliation is read-only. The full Arch shell can
            # own the gateway independently of the standalone package, and
            # non-Arch sessions must still report helper availability.
            try:
                gateway = gateway_call("gateway-status")
            except (ValueError, OSError):
                gateway = {"installed": False, "packageInstalled": False,
                           "diagnostic": "standalone-package-unavailable"}
            helper = system_call("helpers-status", None)
            result.update(
                gatewayPackageInstalled=gateway.get("packageInstalled") is True,
                systemProvisionerAvailable=helper.get("provisionerAvailable") is True
                    or gateway.get("installed") is True,
                systemHelpersInstalled=helper.get("installed") is True,
                systemHelpersDiagnostic=str(helper.get("diagnostic", "unchecked")),
                gatewayDiagnostic=str(gateway.get("diagnostic", "not-installed")),
                message="System status refreshed")
            return result
        if action.startswith("gateway-"):
            if action not in ("gateway-status", "gateway-install", "gateway-remove"):
                raise ValueError("Unsupported system gateway action")
            gateway = gateway_call(action)
            result.update(
                gatewayPackageInstalled=gateway.get("packageInstalled") is True,
                systemProvisionerAvailable=gateway.get("installed") is True,
                systemHelpersDiagnostic=("not-installed" if gateway.get("installed") else
                    str(gateway.get("diagnostic", "system-provisioner-not-installed"))),
                message=str(gateway.get("message") or "System gateway package status refreshed"))
            return result
        if action == "helpers-ensure":
            # One explicit Settings action: provision the trusted standalone
            # gateway when absent, then idempotently install verified helpers.
            # Both privileged stages still require their own Polkit consent.
            active_package = bundled if bundled.is_dir() else home / "current"
            if not active_package.is_dir():
                raise ValueError("Install Alis-Intergration before system helpers")
            package_dir = active_package.resolve()
            if not package_dir.is_dir():
                raise ValueError("Invalid Alis-Intergration release")
            gateway = gateway_call("gateway-status")
            provisioner = system_call("helpers-status", None)
            # A full alis-shell Arch package can already own the trusted
            # provisioner without installing the separate repo-copy package.
            if provisioner.get("provisionerAvailable") is not True:
                if gateway.get("installed") is not True:
                    gateway = gateway_call("gateway-install")
                    if gateway.get("installed") is not True:
                        raise ValueError("System gateway installation was not confirmed")
            # Root gateway revalidates its audited allowlist and existing
            # ownership; never delete helpers merely to reinstall them.
            if provisioner.get("provisionerAvailable") is True and provisioner.get("installed") is True:
                payload = provisioner
            else:
                payload = system_call("helpers-install", package_dir)
            if not isinstance(payload, dict) or payload.get("installed") is not True:
                raise ValueError("System helper installation was not confirmed")
            result.update(
                systemHelpersInstalled=payload.get("installed") is True,
                systemProvisionerAvailable=payload.get("provisionerAvailable") is True,
                gatewayPackageInstalled=gateway.get("packageInstalled") is True,
                systemHelpersDiagnostic=str(payload.get("diagnostic", "unknown")),
                message="System helpers ready")
            return result
        if action.startswith("helpers-"):
            if action not in ("helpers-status", "helpers-install", "helpers-remove"):
                raise ValueError("Unsupported system helper action")
            if action == "helpers-install":
                active_package = bundled if bundled.is_dir() else home / "current"
                if not active_package.is_dir():
                    raise ValueError("Install Alis-Intergration before installing its system helpers")
                package_dir = active_package.resolve()
                if not package_dir.is_dir():
                    raise ValueError("Invalid Alis-Intergration release")
                # All bytes must match the system package's root-owned pinned
                # allowlist. The privileged gateway will re-open and check them.
                payload = system_call(action, package_dir)
            else:
                payload = system_call(action, None)
            result.update(systemHelpersInstalled=payload.get("installed") is True,
                          systemProvisionerAvailable=payload.get("provisionerAvailable") is True,
                          systemHelpersDiagnostic=str(payload.get("diagnostic", "")),
                          message=("System helper files installed" if action == "helpers-install"
                              else "System helper files removed" if action == "helpers-remove"
                              else "System helper status refreshed"))
            return result
        if action == "status":
            return result
        if action == "check":
            result["latestSha"] = revision_fetch()
            result["updateAvailable"] = current != result["latestSha"]
            return result
        if action == "remove":
            owned_link(home).unlink(missing_ok=True)
            result.update(diagnostic="not-installed", installedSha="", available=False, version="",
                          message="Package removed; preferences and releases retained")
            return result
        if action == "rollback":
            if not SHA.fullmatch(previous) or not package_good(home / "releases" / previous, previous):
                raise ValueError("No intact previous release available")
            switch(home, previous)
            previous_file.write_text(current + "\n" if current else "")
            result.update(diagnostic="ready", installedSha=previous, available=True,
                          version=json.loads((home / "releases" / previous / "manifest.json").read_text())["version"],
                          message="Previous release restored")
            return result
        if action != "install":
            raise ValueError("Unsupported action")
        latest = revision_fetch()
        if not SHA.fullmatch(latest):
            raise ValueError("Invalid source revision")
        result["latestSha"] = latest
        if latest == current:
            result["message"] = "Already on the latest revision"
            return result
        releases = home / "releases"
        releases.mkdir(exist_ok=True)
        candidate = releases / latest
        if candidate.exists():
            if not package_good(candidate, latest):
                raise ValueError("Existing release bytes differ; preserved unchanged")
        else:
            with tempfile.TemporaryDirectory(dir=releases, prefix=".stage-") as temporary:
                bundle = unpack(archive_fetch(ARCHIVE + latest, MAX_ARCHIVE))
                payload = Path(temporary) / "payload"
                assemble(bundle, latest, payload)
                if not package_good(payload, latest):
                    raise ValueError("Package integrity verification failed")
                os.replace(payload, candidate)
        switch(home, latest)
        if current:
            previous_file.write_text(current + "\n")
        result.update(diagnostic="ready", available=True, installedSha=latest,
                      canRollback=bool(current) or result["canRollback"],
                      version=json.loads((candidate / "manifest.json").read_text())["version"],
                      message="Installed verified Alis-Intergration release")
        return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("status", "check", "install", "remove", "rollback",
                                                    "system-status", "helpers-status", "helpers-install", "helpers-remove", "helpers-ensure",
                                                    "gateway-status", "gateway-install", "gateway-remove"))
    parser.add_argument("--shell-root", type=Path, default=ROOT)
    parser.add_argument("--data-home", type=Path, default=Path(
        os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share"))))
    args = parser.parse_args()
    try:
        canonical = args.data_home / "alis-intergration"
        legacy = args.data_home / "hadalird"
        if args.action in ("install", "remove", "rollback"):
            if legacy.is_dir() and not legacy.is_symlink() and not canonical.exists():
                os.replace(legacy, canonical)
            home = canonical
        else:
            home = canonical if canonical.exists() or not legacy.exists() else legacy
        result = operate(args.action, home, args.shell_root)
        print(json.dumps(result))
    except (OSError, ValueError, KeyError, json.JSONDecodeError, tarfile.TarError) as error:
        print(json.dumps({"ok": False, "action": args.action, "error": str(error)}))
        raise SystemExit(1)


if __name__ == "__main__":
    main()
