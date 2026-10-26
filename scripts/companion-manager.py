#!/usr/bin/env python3
"""Install Alis-Companion as a managed part of Alis's user setup/update lifecycle.

The source stays in Alis-Companion, but the user never needs to clone or
install it separately. No implicit AI inference, model download or vault access.
"""
import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ALIS_ROOT = Path(__file__).resolve().parents[1]
CANONICAL_REMOTE = "https://github.com/llocphann/Alis-Companion.git"
REQUIRED = {
    "session": "HadalisSession.qml",
    "output": "HadalisOutput.qml",
    "settings": "modules/settings/CompanionConfig.qml",
    "binary": "native/bin/alis-companiond",
}
# The pinned Companion source still builds/publishes inir-companiond and
# declares that exact name in its signed release manifest. Both are explicit,
# fixed paths; never accept a path supplied by an arbitrary manifest.
COMPATIBLE_BINARIES = frozenset((
    REQUIRED["binary"],
    "native/bin/inir-companiond",
))


class CompanionInstallError(RuntimeError):
    pass


def run(*command, cwd=None, capture=False):
    result = subprocess.run(command, cwd=cwd, text=True, check=True,
                            stdout=subprocess.PIPE if capture else None)
    return result.stdout.strip() if capture else ""


def installed_revision(data_home):
    data_root = data_home / "alis-companion"
    current = data_root / "current"
    if not current.is_symlink():
        return ""
    try:
        release = current.resolve(strict=True)
        if not release.is_relative_to((data_root / "releases").resolve()):
            return ""
        manifest = release / "manifest.json"
        if manifest.stat().st_size > 16384:
            return ""
        info = json.loads(manifest.read_text())
        if info.get("id") != "alis-companion" or type(info.get("hostApi")) is not int or info["hostApi"] != 1:
            return ""
        if any(info.get(key) != rel or not (release / rel).is_file()
               for key, rel in REQUIRED.items() if key != "binary"):
            return ""
        binary = info.get("binary")
        if binary not in COMPATIBLE_BINARIES or not (release / binary).is_file():
            return ""
        if not os.access(release / binary, os.X_OK):
            return ""
        sha = info.get("sourceSha", "")
        return sha if isinstance(sha, str) and re.fullmatch(r"[0-9a-f]{40}", sha) else ""
    except (OSError, ValueError, TypeError, json.JSONDecodeError):
        return ""


def source_checkout(cache, remote, revision):
    # A private, dedicated checkout: never reset the owner's repository.
    checkout = cache / "source"
    if checkout.is_symlink():
        raise CompanionInstallError("Managed Companion checkout must not be a symlink")
    if checkout.exists():
        if not (checkout / ".git").is_dir():
            raise CompanionInstallError("Managed Companion source path is not a Git checkout")
        if run("git", "remote", "get-url", "origin", cwd=checkout, capture=True) != remote:
            raise CompanionInstallError("Refusing to update an unexpected Companion remote")
        if run("git", "status", "--porcelain", "--untracked-files=all", cwd=checkout, capture=True):
            raise CompanionInstallError("Managed Companion checkout has local modifications; refusing overwrite")
        run("git", "fetch", "--depth", "1", "origin", revision, cwd=checkout)
        run("git", "checkout", "--detach", revision, cwd=checkout)
    else:
        with tempfile.TemporaryDirectory(prefix=".source-", dir=cache) as temporary:
            target = Path(temporary) / "repo"
            run("git", "clone", "--no-checkout", "--depth", "1",
                "--single-branch", "--branch", "main", remote, str(target))
            run("git", "fetch", "--depth", "1", "origin", revision, cwd=target)
            run("git", "checkout", "--detach", revision, cwd=target)
            target.rename(checkout)
    if run("git", "rev-parse", "HEAD", cwd=checkout, capture=True) != revision:
        raise CompanionInstallError("Fetched Companion identity differs from Alis's pinned revision")
    if run("git", "status", "--porcelain", "--untracked-files=all", cwd=checkout, capture=True):
        raise CompanionInstallError("Managed Companion source must remain clean")
    info = json.loads((checkout / "manifest.json").read_text())
    if info.get("id") != "alis-companion" or info.get("hostApi") != 1:
        raise CompanionInstallError("Incompatible Alis-Companion host API")
    for key, rel in REQUIRED.items():
        if (info.get(key) not in COMPATIBLE_BINARIES if key == "binary"
                else info.get(key) != rel):
            raise CompanionInstallError(
                f"Unexpected Companion runtime entrypoint: {key}")
    return checkout


def owner_file(data_home):
    return data_home / "alis-companion/.alis-owned.json"


def record_owner(data_home, revision):
    marker = owner_file(data_home)
    if marker.is_symlink():
        raise CompanionInstallError("Refusing foreign Companion ownership marker")
    with tempfile.NamedTemporaryFile(mode="w", dir=marker.parent,
                                     prefix=".alis-owned-", delete=False) as tmp:
        tmp_path = Path(tmp.name)
        try:
            os.chmod(tmp_path, 0o600)
            json.dump({"owner": "Alis", "sourceSha": revision}, tmp)
            tmp.write("\n")
            tmp.flush()
            os.fsync(tmp.fileno())
        except BaseException:
            tmp_path.unlink(missing_ok=True)
            raise
    try:
        os.replace(tmp_path, marker)
    finally:
        tmp_path.unlink(missing_ok=True)


def uninstall_owned(data_home):
    if os.geteuid() == 0:
        raise CompanionInstallError("Refusing Companion uninstall as root")
    marker = owner_file(data_home)
    if marker.is_symlink() or not marker.is_file():
        print("No Alis-owned Companion release; independent installations preserved")
        return
    info = json.loads(marker.read_text())
    revision = info.get("sourceSha", "")
    if info.get("owner") != "Alis" or not isinstance(revision, str) or not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise CompanionInstallError("Untrusted Companion ownership marker")
    current = data_home / "alis-companion/current"
    if not current.exists() and not current.is_symlink():
        marker.unlink()
        return
    if installed_revision(data_home) != revision:
        raise CompanionInstallError("Active Companion differs from Alis-managed SHA; preserving it")
    current.unlink()
    marker.unlink()
    print("Detached Alis-owned Companion, preserving releases and personal data")


def sync(remote, revision, data_home, cache):
    if os.geteuid() == 0:
        raise CompanionInstallError("Companion must be installed as the desktop user, never as root")
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise CompanionInstallError("Companion revision must be a full 40-character commit SHA")
    cache.mkdir(parents=True, exist_ok=True)
    if cache.is_symlink():
        raise CompanionInstallError("Managed Companion cache must not be a symlink")
    lock = cache / ".install.lock"
    if lock.is_symlink():
        raise CompanionInstallError("Refusing foreign Companion installation lock")
    with lock.open("a") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        if installed_revision(data_home) == revision:
            record_owner(data_home, revision)
            print("Alis-Companion is already installed at the pinned revision " + revision[:12])
            return
        checkout = source_checkout(cache, remote, revision)
        print("Building Alis-Companion " + revision[:12] + " under the desktop account", flush=True)
        # Reuse Companion's own immutable-release/atomic-current installer.
        # A failed build leaves the previous active release intact.
        run("make", "-C", str(checkout), "install")
        if installed_revision(data_home) != revision:
            raise CompanionInstallError("Companion installer did not activate the expected release")
        record_owner(data_home, revision)
        print("Alis-Companion integrated successfully (" + revision[:12] + ")", flush=True)
    # Runtime refresh is best effort; setup update also restarts the Alis shell.
    launcher = shutil.which("alis")
    if launcher:
        try:
            subprocess.run([launcher, "ipc", "alis-companion", "refresh"], timeout=5,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        except (OSError, subprocess.TimeoutExpired):
            pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["sync", "status", "uninstall"])
    parser.add_argument("--repo-url", default=CANONICAL_REMOTE,
                        help="Explicit local fixture source for offline developer tests")
    parser.add_argument("--revision", default=None, help="Explicit pinned revision override for offline tests")
    args = parser.parse_args()
    revision = args.revision or (ALIS_ROOT / "sdata/companion-revision.txt").read_text().strip()
    data_home = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share")
    cache_home = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache")
    cache = cache_home / "alis/companion"
    if args.action == "status":
        print(json.dumps({"expected": revision, "installed": installed_revision(data_home),
                          "ready": installed_revision(data_home) == revision}))
        return
    if args.action == "uninstall":
        uninstall_owned(data_home)
        return
    sync(args.repo_url, revision, data_home, cache)


if __name__ == "__main__":
    try:
        main()
    except (CompanionInstallError, OSError, subprocess.CalledProcessError,
            ValueError, json.JSONDecodeError) as exc:
        print("Alis-Companion integration failed: " + str(exc), file=sys.stderr)
        raise SystemExit(1)
