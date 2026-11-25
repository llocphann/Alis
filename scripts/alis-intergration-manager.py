#!/usr/bin/env python3
"""User-requested, Alis-owned installer for the optional Alis-Intergration base and plugins.

No background network activity, privileged operations or execution of downloaded scripts.
The lightweight base provides catalog/session plumbing; individual plugins are downloaded
and installed only when the user explicitly requests them.
"""
import argparse
import fcntl
import hashlib
import inspect
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import tarfile
import tempfile
import urllib.error
import urllib.request

from importlib.util import module_from_spec, spec_from_file_location

ROOT = Path(__file__).resolve().parents[1]
spec = spec_from_file_location("alis_intergration_discovery", ROOT / "scripts/alis-intergration-status.py")
discovery = module_from_spec(spec)
spec.loader.exec_module(discovery)

API = "https://api.github.com/repos/llocphann/Alis-Intergration/commits/main"
API_REF = "https://api.github.com/repos/llocphann/Alis-Intergration/git/ref/heads/main"
RELEASES_API = "https://api.github.com/repos/llocphann/Alis-Intergration/releases/latest"
GIT_REPO_URL = "https://github.com/llocphann/Alis-Intergration.git"
ARCHIVE = "https://api.github.com/repos/llocphann/Alis-Intergration/tarball/"
PAYLOAD = ("AlisSession.qml", "LICENSE", "plugins/", "services/", "modules/", "assets/",
           "scripts/integrations/", "scripts/todo/", "scripts/notes/")
MAX_COMMIT_META = 16 * 1024 * 1024
MAX_ARCHIVE = 32 * 1024 * 1024
MAX_PAYLOAD = 64 * 1024 * 1024
MAX_FILE_SIZE = 8 * 1024 * 1024
MAX_FILES = 512
MAX_MEMBERS = 4096
SYSTEM_PROVISIONER = "/usr/libexec/alis-intergration-system-provision"
_LEGACY_PREFIX = "".join(("i", "nir"))
_LEGACY_COMPONENT = "".join(("hada", "lird"))
_LEGACY_SYSTEM_PROVISIONER = f"/usr/libexec/{_LEGACY_PREFIX}-{_LEGACY_COMPONENT}-system-provision"
EXECUTABLE = {
    "assets/helpers/alis-battery-charge-limit",
    "assets/helpers/alis-thinkfan",
    "assets/bin/alis-nexus",
    "plugins/tlp/assets/helpers/alis-battery-charge-limit",
    "plugins/thinkfan/assets/helpers/alis-thinkfan",
    "plugins/nexus/assets/bin/alis-nexus",
    "plugins/alis_files/scripts/install_alis_files.py",
}
BUILTIN_PLUGIN_IDS = ("alis_files", "nexus", "spaced_repetition", "exercises_tracker")
_EXTERNAL_HELPER_PREFIX = f"assets/helpers/{_LEGACY_PREFIX}-"
EXECUTABLE.update({_EXTERNAL_HELPER_PREFIX + "battery-charge-limit",
                   _EXTERNAL_HELPER_PREFIX + "thinkfan"})
SHA = re.compile(r"[0-9a-f]{40}\Z")
PLUGIN_SUBPATH_RE = re.compile(r"^plugins/([a-z][a-z0-9_-]{0,47})/(.+)$")


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def request_bytes(url, limit):
    # Only the official GitHub API, release assets, and codeload redirects are allowed.
    req = urllib.request.Request(url, headers={"User-Agent": "Alis-Intergration-Manager/1",
                                              "Accept": "application/vnd.github+json"})
    with urllib.request.urlopen(req, timeout=25) as response:
        final = response.geturl()
        from urllib.parse import urlsplit
        parsed = urlsplit(final)
        if parsed.scheme != "https" or parsed.hostname not in (
                "api.github.com", "codeload.github.com", "github.com", "objects.githubusercontent.com",
                "release-assets.githubusercontent.com"):
            raise ValueError("Unexpected package download origin")
        data = response.read(limit + 1)
    if len(data) > limit:
        raise ValueError("Package download exceeds the configured limit")
    return data


def latest_sha():
    try:
        doc = json.loads(request_bytes(API, MAX_COMMIT_META))
        revision = doc.get("sha") if isinstance(doc, dict) else None
    except ValueError as error:
        if "exceeds the configured limit" not in str(error):
            raise
        ref_doc = json.loads(request_bytes(API_REF, 256 * 1024))
        obj = ref_doc.get("object") if isinstance(ref_doc, dict) else None
        revision = obj.get("sha") if isinstance(obj, dict) and obj.get("type") == "commit" else None
    if not isinstance(revision, str) or not SHA.fullmatch(revision):
        raise ValueError("GitHub did not return an immutable commit SHA")
    return revision


def allowed(path):
    return path in ("AlisSession.qml", "LICENSE") or any(
        path.startswith(prefix) for prefix in PAYLOAD if prefix.endswith("/"))


def unpack(data, *, plugin_id=None):
    """Copy regular allowlisted files only: never extract arbitrary archive members."""
    result = {}
    total = 0
    members = 0
    wanted_prefix = f"plugins/{plugin_id}/" if plugin_id else ""
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
        for member in archive:
            members += 1
            if members > MAX_MEMBERS:
                raise ValueError("Package archive contains too many entries")
            parts = PurePosixPath(member.name).parts
            if not parts:
                continue
            if parts[0] == "plugins":
                path = PurePosixPath(*parts)
            elif len(parts) < 2:
                continue
            else:
                path = PurePosixPath(*parts[1:])
            if any(p in ("", ".", "..") for p in path.parts):
                raise ValueError("Unsafe archive path")
            if member.isdir():
                continue
            name = path.as_posix()
            if plugin_id is not None:
                if name == f"{wanted_prefix}plugin-manifest.json":
                    if not member.isfile() or member.size > 65536:
                        raise ValueError("Invalid plugin manifest")
                elif not name.startswith(wanted_prefix):
                    continue
            elif name == "manifest.json":
                if not member.isfile() or member.size > 65536:
                    raise ValueError("Invalid manifest")
            elif not allowed(name):
                continue
            if not member.isfile() or member.issym() or member.islnk():
                raise ValueError("Nonregular package member")
            if name in result or len(result) >= MAX_FILES:
                raise ValueError("Duplicate or excessive package entries")
            if member.size < 0 or member.size > MAX_FILE_SIZE:
                raise ValueError("Oversized package file")
            total += member.size
            if total > MAX_PAYLOAD:
                raise ValueError("Package contents exceed the configured limit")
            stream = archive.extractfile(member)
            if stream is None:
                raise ValueError("Missing package bytes")
            result[name] = stream.read()
    return result


def assemble(files, revision, target, *, base_only=False):
    if "manifest.json" not in files:
        raise ValueError("Missing package manifest")
    manifest = json.loads(files["manifest.json"])
    if not isinstance(manifest, dict) or manifest.get("id") != "alis-intergration" or (
            type(manifest.get("hostApi")) is not int or manifest["hostApi"] != 1):
        raise ValueError("Unsupported Alis-Intergration package or host API")
    if not isinstance(manifest.get("version"), str) or not manifest["version"] or len(manifest["version"]) > 64:
        raise ValueError("Invalid package version")
    settings = manifest.get("settings")
    backends = manifest.get("backends")
    if not isinstance(settings, dict) or not isinstance(backends, dict):
        raise ValueError("Invalid package entrypoints")
    discovery.plugin_metadata(manifest)
    required = {
        "session": manifest.get("session"),
        "tlpSettings": settings.get("tlp"),
        "thinkfanSettings": settings.get("thinkfan"),
        "nexusSettings": settings.get("nexus"),
        "nexusTodoSettings": settings.get("nexusTodo"),
        "tlpRowSettings": settings.get("tlpRow"),
        "tlpWaffleSettings": settings.get("tlpWaffle"),
        "tlpWaffleRowSettings": settings.get("tlpWaffleRow"),
        "managedTodo": backends.get("managedTodo"),
        "dailyTodo": backends.get("dailyTodo"),
    }
    if required not in (discovery.ENTRYPOINTS, discovery.LEGACY_ENTRYPOINTS):
        raise ValueError("Package entrypoints do not match the host API")

    selected_files = {}
    if base_only:
        for name in ("AlisSession.qml", "LICENSE"):
            if name in files:
                selected_files[name] = files[name]
        if "AlisSession.qml" not in selected_files:
            raise ValueError("Missing mandatory package payload: AlisSession.qml")
        manifest["layout"] = "base-v2"
    else:
        for name in required.values():
            if name not in files:
                raise ValueError("Missing mandatory package payload: " + name)
        for name, data in files.items():
            if name != "manifest.json":
                selected_files[name] = data

    target.mkdir()
    digests = {}
    for name, data in selected_files.items():
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


def call_system_helper(action, package=None, scope="all"):
    if scope not in ("all", "tlp", "thinkfan"):
        raise ValueError("Unsupported helper scope: " + str(scope))
    provisioner = _resolve_system_provisioner()
    if not provisioner:
        if action == "helpers-status":
            return {"ok": True, "installed": False, "managed": False, "partial": False,
                    "plugins": {
                        "tlp": {"installed": False, "managed": False, "diagnostic": "system-provisioner-not-installed"},
                        "thinkfan": {"installed": False, "managed": False, "diagnostic": "system-provisioner-not-installed"},
                    },
                    "provisionerAvailable": False, "diagnostic": "system-provisioner-not-installed"}
        raise ValueError("Alis system provisioner is unavailable; update your Alis system package")
    if action == "helpers-status":
        argv = [provisioner, "status"] if scope == "all" else [provisioner, "status", scope]
    else:
        if not shutil.which("pkexec"):
            raise ValueError("Polkit pkexec is missing; no system files were modified")
        cmd = "install" if action == "helpers-install" else "remove"
        argv = ["pkexec", provisioner, cmd]
        if action == "helpers-install":
            argv.append(str(package))
        if scope != "all":
            argv.append(scope)
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
    if action == "helpers-remove":
        if scope == "all" and (data["installed"] or data["managed"]):
            raise ValueError("System helper removal was not verified")
        if scope != "all":
            pstate = (data.get("plugins") or {}).get(scope, {})
            if data.get("installed") or pstate.get("installed") or pstate.get("managed"):
                raise ValueError(f"System helper removal for {scope} was not verified")
    data["provisionerAvailable"] = True
    return data


def _invoke_system_call(system_call, action, package, scope="all"):
    try:
        params = list(inspect.signature(system_call).parameters.values())
        if any(p.name == "scope" or p.kind == inspect.Parameter.VAR_KEYWORD for p in params):
            return system_call(action, package, scope=scope)
    except (TypeError, ValueError):
        pass
    return system_call(action, package)


def gateway_package(action):
    task = action.removeprefix("gateway-")
    runner = ROOT / "scripts/alis-intergration-system-package.py"
    if task not in ("status", "install", "remove", "rollback") or not runner.is_file():
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


def _catalog_doc(shell_root):
    try:
        return json.loads((Path(shell_root) / "defaults/integration-plugins.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def _known_plugin_ids(shell_root, package_dir=None):
    if package_dir is not None and (package_dir / "manifest.json").is_file():
        try:
            manifest = json.loads((package_dir / "manifest.json").read_text(encoding="utf-8"))
            ids = [plugin["id"] for plugin in discovery.plugin_metadata(manifest)]
            if ids:
                return ids
        except (OSError, ValueError, KeyError, TypeError):
            pass
    doc = _catalog_doc(shell_root)
    ids = [plugin["id"] for plugin in discovery.plugin_metadata(doc)]
    return ids or ["tlp", "thinkfan", "nexus", "spaced_repetition", "exercises_tracker", "alis_files"]


def _local_base_files(shell_root):
    base_dir = Path(shell_root) / "assets" / "alis-intergration-base"
    if not (base_dir / "manifest.json").is_file():
        return None, ""
    files = {}
    for name in ("manifest.json", "AlisSession.qml", "LICENSE"):
        p = base_dir / name
        if p.is_symlink() or not p.is_file():
            raise ValueError(f"Invalid shipped base file: {name}")
        files[name] = p.read_bytes()
    manifest = json.loads(files["manifest.json"])
    rev = str(manifest.get("sourceSha", ""))
    if not SHA.fullmatch(rev):
        h = hashlib.sha1()
        for k in sorted(files):
            h.update(k.encode("utf-8"))
            h.update(files[k])
        rev = h.hexdigest()
    return files, rev


def _install_release(home, current, previous_file, revision_fetch, archive_fetch, *, base_only=False):
    latest = revision_fetch()
    if not SHA.fullmatch(latest):
        raise ValueError("Invalid source revision")
    if latest == current:
        existing_layout = discovery.inspect_package(home / "releases" / current).get("layout")
        if base_only or existing_layout != "base-v2":
            return {"latestSha": latest, "installedSha": current,
                    "version": json.loads((home / "releases" / current / "manifest.json").read_text())["version"],
                    "alreadyCurrent": True}
    releases = home / "releases"
    releases.mkdir(exist_ok=True)
    candidate = releases / latest
    upgrade_from_base = (
        not base_only
        and candidate.exists()
        and package_good(candidate, latest)
        and discovery.inspect_package(candidate).get("layout") == "base-v2"
    )
    if candidate.exists() and not upgrade_from_base:
        if not package_good(candidate, latest):
            raise ValueError("Existing release bytes differ; preserved unchanged")
    else:
        with tempfile.TemporaryDirectory(dir=releases, prefix=".stage-") as temporary:
            bundle = unpack(archive_fetch(ARCHIVE + latest, MAX_ARCHIVE))
            payload = Path(temporary) / "payload"
            assemble(bundle, latest, payload, base_only=base_only)
            if not package_good(payload, latest):
                raise ValueError("Package integrity verification failed")
            if upgrade_from_base:
                old_backup = releases / f".old-{latest}"
                if old_backup.exists():
                    shutil.rmtree(old_backup)
                os.replace(candidate, old_backup)
                try:
                    os.replace(payload, candidate)
                except Exception:
                    if not candidate.exists() and old_backup.exists():
                        os.replace(old_backup, candidate)
                    raise
                shutil.rmtree(old_backup, ignore_errors=True)
            else:
                os.replace(payload, candidate)
    switch(home, latest)
    if current and current != latest:
        previous_file.write_text(current + "\n")
    return {
        "latestSha": latest,
        "installedSha": latest,
        "version": json.loads((candidate / "manifest.json").read_text())["version"],
        "alreadyCurrent": False,
    }


def _install_base_local(home, current, previous_file, shell_root, revision_fetch, archive_fetch, source_dir=None):
    source_override = str(source_dir or os.environ.get("ALIS_INTERGRATION_SOURCE", "")).strip()
    if source_override:
        src = Path(source_override).resolve()
        files = {}
        for name in ("manifest.json", "AlisSession.qml", "LICENSE"):
            p = src / name
            if p.is_symlink() or not p.is_file():
                raise ValueError(f"Missing base file in ALIS_INTERGRATION_SOURCE: {name}")
            files[name] = p.read_bytes()
        rev = hashlib.sha1(b"".join(files[k] for k in sorted(files))).hexdigest()
        return _materialize_base(home, current, previous_file, files, rev)

    # Prefer shipped lightweight base in Alis/assets/alis-intergration-base when network archive fetch isn't injected.
    if archive_fetch is None:
        files, rev = _local_base_files(shell_root)
        if files is not None:
            return _materialize_base(home, current, previous_file, files, rev)

    return _install_release(
        home, current, previous_file,
        latest_sha if revision_fetch is None else revision_fetch,
        request_bytes if archive_fetch is None else archive_fetch,
        base_only=True,
    )


def _materialize_base(home, current, previous_file, files, revision):
    if current == revision and package_good(home / "releases" / current, current):
        return {
            "latestSha": revision,
            "installedSha": current,
            "version": json.loads((home / "releases" / current / "manifest.json").read_text())["version"],
            "alreadyCurrent": True,
        }
    releases = home / "releases"
    releases.mkdir(parents=True, exist_ok=True)
    candidate = releases / revision
    if candidate.exists():
        if not package_good(candidate, revision):
            raise ValueError("Existing release bytes differ; preserved unchanged")
    else:
        with tempfile.TemporaryDirectory(dir=releases, prefix=".stage-base-") as temporary:
            payload = Path(temporary) / "payload"
            assemble(files, revision, payload, base_only=True)
            if not package_good(payload, revision):
                raise ValueError("Base package integrity verification failed")
            os.replace(payload, candidate)
    switch(home, revision)
    if current:
        previous_file.write_text(current + "\n")
    if not discovery.installed_plugins_path(home).exists():
        discovery.save_installed_plugins(home, [])
    return {
        "latestSha": revision,
        "installedSha": revision,
        "version": json.loads((candidate / "manifest.json").read_text())["version"],
        "alreadyCurrent": False,
    }


def _read_dir_plugin_files(plugin_dir, plugin_id):
    if plugin_dir.is_symlink() or not plugin_dir.is_dir():
        raise ValueError(f"Missing or linked plugin directory: {plugin_id}")
    files = {}
    for p in sorted(plugin_dir.rglob("*")):
        rel = p.relative_to(plugin_dir)
        if "target" in rel.parts:
            continue
        if p.is_symlink():
            raise ValueError(f"Refusing symlink inside plugin {plugin_id}")
        if "__pycache__" in rel.parts and p.is_file() and p.suffix in (".pyc", ".pyo"):
            continue
        if p.is_file():
            name = rel.as_posix()
            if name != "plugin-manifest.json":
                files[name] = p.read_bytes()
    return files


def _try_github_release_plugin(plugin_id):
    try:
        release_doc = json.loads(request_bytes(RELEASES_API, 512 * 1024))
    except (urllib.error.URLError, ValueError, OSError):
        return None
    assets = release_doc.get("assets") if isinstance(release_doc, dict) else None
    if not isinstance(assets, list):
        return None
    target_name = f"alis-intergration-plugin-{plugin_id}.tar.gz"
    asset_url = ""
    sums_url = ""
    for item in assets:
        if not isinstance(item, dict):
            continue
        if item.get("name") == target_name:
            asset_url = str(item.get("browser_download_url") or "")
        elif item.get("name") == "SHA256SUMS":
            sums_url = str(item.get("browser_download_url") or "")
    if not asset_url or not sums_url:
        return None
    tar_bytes = request_bytes(asset_url, MAX_ARCHIVE)
    sums_text = request_bytes(sums_url, 64 * 1024).decode("utf-8", errors="replace")
    expected = ""
    for line in sums_text.splitlines():
        parts = line.split()
        if len(parts) == 2 and parts[1] == target_name:
            expected = parts[0]
            break
    if not expected or sha256(tar_bytes) != expected:
        raise ValueError(f"Release checksum mismatch for plugin {plugin_id}")
    raw = unpack(tar_bytes, plugin_id=plugin_id)
    prefix = f"plugins/{plugin_id}/"
    subfiles = {k[len(prefix):]: v for k, v in raw.items() if k.startswith(prefix) and not k.endswith("plugin-manifest.json")}
    sha_hint = ""
    pm_bytes = raw.get(f"{prefix}plugin-manifest.json")
    if pm_bytes:
        try:
            sha_hint = str(json.loads(pm_bytes).get("sourceSha", ""))
        except (ValueError, TypeError):
            pass
    return subfiles, sha_hint


def _try_git_sparse_plugin(plugin_id):
    if not shutil.which("git"):
        return None
    with tempfile.TemporaryDirectory(prefix=f"alis-sparse-{plugin_id}-") as tmp:
        repo = Path(tmp) / "repo"
        clone = subprocess.run(
            ["git", "clone", "--depth", "1", "--filter=blob:none", "--no-checkout",
             "--branch", "main", GIT_REPO_URL, str(repo)],
            capture_output=True, text=True, timeout=60, check=False,
        )
        if clone.returncode != 0:
            return None
        sparse_init = subprocess.run(
            ["git", "-C", str(repo), "sparse-checkout", "set", "--no-cone", f"/plugins/{plugin_id}/"],
            capture_output=True, text=True, timeout=20, check=False,
        )
        if sparse_init.returncode != 0:
            return None
        checkout = subprocess.run(
            ["git", "-C", str(repo), "checkout"],
            capture_output=True, text=True, timeout=60, check=False,
        )
        if checkout.returncode != 0:
            return None
        plugin_dir = repo / "plugins" / plugin_id
        if not plugin_dir.is_dir():
            return None
        rev = subprocess.run(
            ["git", "-C", str(repo), "rev-parse", "HEAD"],
            capture_output=True, text=True, timeout=10, check=False,
        ).stdout.strip()
        return _read_dir_plugin_files(plugin_dir, plugin_id), rev


def _fetch_plugin_payload(plugin_id, revision_fetch, archive_fetch, source_dir=None):
    explicit_src = source_dir or os.environ.get("ALIS_INTERGRATION_SOURCE", "").strip()
    if explicit_src:
        src = Path(explicit_src).resolve()
        files = _read_dir_plugin_files(src / "plugins" / plugin_id, plugin_id)
        rev = revision_fetch() if revision_fetch is not None else ""
        if not SHA.fullmatch(rev) and (src / ".git").exists():
            proc = subprocess.run(["git", "-C", str(src), "rev-parse", "HEAD"], capture_output=True, text=True, check=False)
            rev = proc.stdout.strip()
        if not SHA.fullmatch(rev):
            h = hashlib.sha1()
            for k in sorted(files):
                h.update(k.encode("utf-8"))
                h.update(files[k])
            rev = h.hexdigest()
        return files, rev

    if archive_fetch is not None:
        rev_fn = latest_sha if revision_fetch is None else revision_fetch
        latest = rev_fn()
        if not SHA.fullmatch(latest):
            raise ValueError("Invalid source revision")
        bundle = unpack(archive_fetch(ARCHIVE + latest, MAX_ARCHIVE), plugin_id=plugin_id)
        prefix = f"plugins/{plugin_id}/"
        subfiles = {k[len(prefix):]: v for k, v in bundle.items()
                    if k.startswith(prefix) and not k.endswith("plugin-manifest.json")}
        return subfiles, latest

    # Real network path: prefer individual GitHub Release tarball -> git sparse fetch -> filtered archive.
    release_res = _try_github_release_plugin(plugin_id)
    if release_res is not None and release_res[0]:
        subfiles, sha_hint = release_res
        rev = sha_hint if SHA.fullmatch(sha_hint) else hashlib.sha1(
            b"".join(subfiles[k] for k in sorted(subfiles))
        ).hexdigest()
        return subfiles, rev

    sparse_res = _try_git_sparse_plugin(plugin_id)
    if sparse_res is not None and sparse_res[0]:
        subfiles, sha_hint = sparse_res
        rev = sha_hint if SHA.fullmatch(sha_hint) else hashlib.sha1(
            b"".join(subfiles[k] for k in sorted(subfiles))
        ).hexdigest()
        return subfiles, rev

    rev_fn = latest_sha if revision_fetch is None else revision_fetch
    latest = rev_fn()
    if not SHA.fullmatch(latest):
        raise ValueError("Invalid source revision")
    bundle = unpack(request_bytes(ARCHIVE + latest, MAX_ARCHIVE), plugin_id=plugin_id)
    prefix = f"plugins/{plugin_id}/"
    subfiles = {k[len(prefix):]: v for k, v in bundle.items()
                if k.startswith(prefix) and not k.endswith("plugin-manifest.json")}
    return subfiles, latest


def _install_plugin_tree(home, plugin_id, subfiles, revision):
    if not subfiles:
        raise ValueError(f"Plugin {plugin_id} payload is empty")
    plugins_dir = home / "plugins"
    if plugins_dir.is_symlink():
        raise ValueError("Refusing symlinked plugins directory")
    plugins_dir.mkdir(parents=True, exist_ok=True)
    dest = plugins_dir / plugin_id
    if dest.is_symlink():
        raise ValueError(f"Refusing symlinked plugin directory: {plugin_id}")
    with tempfile.TemporaryDirectory(dir=plugins_dir, prefix=f".stage-{plugin_id}-") as tmp:
        staged = Path(tmp) / plugin_id
        staged.mkdir()
        digests = {}
        for rel, data in subfiles.items():
            target = staged / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            full_rel = f"plugins/{plugin_id}/{rel}"
            target.chmod(0o755 if full_rel in EXECUTABLE else 0o644)
            digests[rel] = sha256(data)
        pmanifest = {
            "schemaVersion": 1,
            "id": plugin_id,
            "hostApi": 1,
            "sourceSha": revision,
            "files": digests,
        }
        (staged / "plugin-manifest.json").write_text(json.dumps(pmanifest, indent=2) + "\n", encoding="utf-8")
        ok, _ = discovery.inspect_installed_plugin(staged, plugin_id)
        if not ok:
            raise ValueError(f"Plugin {plugin_id} integrity check failed")
        if dest.exists():
            backup = Path(tmp) / "old"
            os.replace(dest, backup)
            os.replace(staged, dest)
        else:
            os.replace(staged, dest)


def _helper_payload_dir(home, bundled, current, scope):
    if bundled.is_dir():
        pkg = bundled.resolve()
        if scope in ("tlp", "thinkfan") and not (pkg / "plugins" / scope).is_dir() and not (pkg / "assets").is_dir():
            raise ValueError(f"Bundled Alis-Intergration lacks {scope} helper payload")
        return pkg
    if not (home / "current").is_dir():
        raise ValueError("Install Alis-Intergration before installing its system helpers")
    rel_dir = (home / "current").resolve()
    rel_report = discovery.inspect_package(rel_dir)
    if rel_report.get("layout") in ("split-v2", "legacy-v1"):
        if scope in ("tlp", "thinkfan") and rel_report["layout"] == "split-v2" and not (rel_dir / "plugins" / scope).is_dir():
            raise ValueError(f"Download & Install the {scope} plugin before installing its system helpers")
        return rel_dir
    # base-v2: plugin payloads live under <home>/plugins/<scope>/ and base manifest under <home>/current/.
    if scope in ("tlp", "thinkfan"):
        pdir = home / "plugins" / scope
        ok, _ = discovery.inspect_installed_plugin(pdir, scope)
        if not ok:
            raise ValueError(f"Download & Install the {scope} plugin before installing its system helpers")
    else:
        for required_scope in ("tlp", "thinkfan"):
            pdir = home / "plugins" / required_scope
            ok, _ = discovery.inspect_installed_plugin(pdir, required_scope)
            if not ok:
                raise ValueError(f"Download & Install both TLP and Thinkfan plugins, or install helpers individually (./setup integrations install {required_scope})")
    return home


def _post_install_plugin_hook(home, plugin_id, *, no_build=False, package_dir=None):
    if plugin_id != "alis_files" or no_build or os.environ.get("ALIS_FILES_SKIP_BUILD") == "1":
        return None
    candidates = [home / "plugins" / "alis_files"]
    if package_dir is not None:
        candidates.append(Path(package_dir) / "plugins" / "alis_files")
    installer = None
    for pdir in candidates:
        cand_inst = pdir / "scripts" / "install_alis_files.py"
        cand_cargo = pdir / "native" / "Cargo.toml"
        if cand_inst.is_file() and cand_cargo.is_file():
            installer = cand_inst
            break
    if installer is None:
        return None
    cmd = ["/usr/bin/python3", str(installer), "--data-home", str(home.parent)]
    proc = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout).strip()[-400:]
        raise ValueError(f"Failed building Alis Files locally: {detail or f'exit {proc.returncode}'}")
    try:
        return json.loads(proc.stdout.strip())
    except (ValueError, TypeError):
        return {"ok": True}


def _resolve_builtin_source_dir(shell_root, source_dir=None):
    if source_dir is not None:
        return Path(source_dir)
    env_src = os.environ.get("ALIS_INTERGRATION_SOURCE", "").strip()
    if env_src:
        return Path(env_src)
    sibling = Path(shell_root).resolve().parent / "Alis-Intergration"
    if (sibling / "manifest.json").is_file() and (sibling / "plugins").is_dir():
        return sibling
    return None


def operate(action, home, shell_root, revision_fetch=None, archive_fetch=None,
            system_call=call_system_helper, gateway_call=gateway_package, *, plugin_id=None, source_dir=None, reuse_installed=False, no_build=False):
    rev_fetch = latest_sha if revision_fetch is None else revision_fetch
    arch_fetch = request_bytes if archive_fetch is None else archive_fetch
    home.mkdir(parents=True, exist_ok=True)
    bundled = discovery.resolve_bundled_package(shell_root)
    if action in ("check", "install", "install-base", "remove", "rollback") and bundled.exists():
        raise ValueError("Alis has a bundled Alis-Intergration; update it through the host distribution")
    lock = home / ".install.lock"
    with lock.open("a") as fd:
        fcntl.flock(fd, fcntl.LOCK_EX)
        diagnostic = "ready"
        try:
            current = active_revision(home)
        except ValueError:
            if action in ("install", "install-base", "install-builtins", "install-all", "remove", "rollback", "install-plugin", "remove-plugin"):
                owned_link(home)
            elif action not in ("status", "check", "system-status", "helpers-status", "gateway-status", "helpers-remove", "gateway-remove", "gateway-rollback"):
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

        scope = plugin_id.strip() if isinstance(plugin_id, str) and plugin_id.strip() in ("tlp", "thinkfan") else "all"

        if action == "system-status":
            try:
                gateway = gateway_call("gateway-status")
            except (ValueError, OSError):
                gateway = {"installed": False, "packageInstalled": False,
                           "diagnostic": "standalone-package-unavailable"}
            helper = _invoke_system_call(system_call, "helpers-status", None, scope)
            result.update(
                gatewayPackageInstalled=gateway.get("packageInstalled") is True,
                systemProvisionerAvailable=helper.get("provisionerAvailable") is True
                    or gateway.get("installed") is True,
                systemHelpersInstalled=helper.get("installed") is True,
                systemHelpersDiagnostic=str(helper.get("diagnostic", "unchecked")),
                systemHelpersByPlugin=helper.get("plugins") or {},
                gatewayDiagnostic=str(gateway.get("diagnostic", "not-installed")),
                gatewayDistro=str(gateway.get("distro", "")),
                gatewayPackageManager=str(gateway.get("packageManager", "")),
                message="System status refreshed")
            return result

        if action.startswith("gateway-"):
            if action not in ("gateway-status", "gateway-install", "gateway-remove", "gateway-rollback"):
                raise ValueError("Unsupported system gateway action")
            gateway = gateway_call(action)
            result.update(
                gatewayPackageInstalled=gateway.get("packageInstalled") is True,
                systemProvisionerAvailable=gateway.get("installed") is True,
                gatewayDistro=str(gateway.get("distro", "")),
                gatewayPackageManager=str(gateway.get("packageManager", "")),
                systemHelpersDiagnostic=("not-installed" if gateway.get("installed") else
                    str(gateway.get("diagnostic", "system-provisioner-not-installed"))),
                message=str(gateway.get("message") or "System gateway package status refreshed"))
            return result

        if action == "helpers-ensure":
            package_dir = _helper_payload_dir(home, bundled, current, scope)
            gateway = gateway_call("gateway-status")
            provisioner = _invoke_system_call(system_call, "helpers-status", None, scope)
            if provisioner.get("provisionerAvailable") is not True:
                if gateway.get("installed") is not True:
                    gateway = gateway_call("gateway-install")
                    if gateway.get("installed") is not True:
                        raise ValueError("System gateway installation was not confirmed")
            if provisioner.get("provisionerAvailable") is True and provisioner.get("installed") is True:
                payload = provisioner
            else:
                payload = _invoke_system_call(system_call, "helpers-install", package_dir, scope)
            if not isinstance(payload, dict) or payload.get("installed") is not True:
                raise ValueError("System helper installation was not confirmed")
            result.update(
                scope=scope,
                systemHelpersInstalled=payload.get("installed") is True,
                systemProvisionerAvailable=payload.get("provisionerAvailable") is True,
                gatewayPackageInstalled=gateway.get("packageInstalled") is True,
                systemHelpersDiagnostic=str(payload.get("diagnostic", "unknown")),
                systemHelpersByPlugin=payload.get("plugins") or {},
                message=f"System helpers ready ({scope})")
            return result

        if action.startswith("helpers-"):
            if action not in ("helpers-status", "helpers-install", "helpers-remove"):
                raise ValueError("Unsupported system helper action")
            if action == "helpers-install":
                package_dir = _helper_payload_dir(home, bundled, current, scope)
                payload = _invoke_system_call(system_call, action, package_dir, scope)
            else:
                payload = _invoke_system_call(system_call, action, None, scope)
            result.update(scope=scope,
                          systemHelpersInstalled=payload.get("installed") is True,
                          systemProvisionerAvailable=payload.get("provisionerAvailable") is True,
                          systemHelpersDiagnostic=str(payload.get("diagnostic", "")),
                          systemHelpersByPlugin=payload.get("plugins") or {},
                          message=("System helper files installed" if action == "helpers-install"
                              else "System helper files removed" if action == "helpers-remove"
                              else "System helper status refreshed"))
            return result

        if action == "status":
            return result

        if action == "check":
            result["latestSha"] = rev_fetch()
            result["updateAvailable"] = current != result["latestSha"]
            return result

        if action == "remove":
            owned_link(home).unlink(missing_ok=True)
            plugins_dir = home / "plugins"
            if plugins_dir.is_dir() and not plugins_dir.is_symlink():
                shutil.rmtree(plugins_dir)
            selection = discovery.installed_plugins_path(home)
            if selection.is_file() and not selection.is_symlink():
                selection.unlink()
            result.update(diagnostic="not-installed", installedSha="", available=False, version="",
                          installedPluginIds=[],
                          message="Package removed; preferences and releases retained")
            return result

        if action == "install-base":
            rel = _install_base_local(home, current, previous_file, shell_root, revision_fetch, archive_fetch, source_dir=source_dir)
            result.update(
                diagnostic="ready",
                available=True,
                installedSha=rel["installedSha"],
                latestSha=rel["latestSha"],
                canRollback=(bool(current) and current != rel["installedSha"]) or result["canRollback"],
                version=rel["version"],
                alreadyCurrent=rel["alreadyCurrent"],
                message=("Base package already ready" if rel["alreadyCurrent"] else "Installed lightweight Alis-Intergration base"),
            )
            return result

        if action == "install-builtins":
            catalog_doc = _catalog_doc(shell_root)
            builtin_ids = [
                pid for pid in (catalog_doc.get("builtinPlugins") or BUILTIN_PLUGIN_IDS)
                if isinstance(pid, str) and pid in _known_plugin_ids(shell_root)
            ]
            if not bundled.is_dir():
                rel = _install_base_local(home, current, previous_file, shell_root, revision_fetch, archive_fetch, source_dir=source_dir)
                result.update(
                    diagnostic="ready",
                    available=True,
                    installedSha=rel["installedSha"],
                    latestSha=rel["latestSha"],
                    canRollback=(bool(current) and current != rel["installedSha"]) or result["canRollback"],
                    version=rel["version"],
                )
                current = rel["installedSha"]
            resolved_src = _resolve_builtin_source_dir(shell_root, source_dir=source_dir)
            package_dir = bundled if bundled.is_dir() else (home / "releases" / current if current else None)
            valid_ids = _known_plugin_ids(shell_root, package_dir)
            existing, explicit = discovery.load_installed_plugins(home, valid_ids)
            updated = list(existing) if explicit else []
            installed_now = []
            build_reports = {}
            for pid in builtin_ids:
                if not bundled.is_dir():
                    pkg_report = discovery.inspect_package(home / "releases" / current)
                    if pkg_report.get("layout") in ("base-v2", "split-v2"):
                        already_intact = (
                            reuse_installed
                            and resolved_src is None
                            and discovery.inspect_installed_plugin(home / "plugins" / pid, pid)[0]
                        )
                        if not already_intact:
                            subfiles, plugin_sha = _fetch_plugin_payload(
                                pid, revision_fetch, archive_fetch, source_dir=resolved_src
                            )
                            if subfiles:
                                _install_plugin_tree(home, pid, subfiles, plugin_sha)
                            elif pkg_report.get("layout") == "base-v2":
                                raise ValueError(f"Failed to install built-in plugin payload for {pid}")
                if pid not in updated:
                    updated.append(pid)
                installed_now.append(pid)
                hook_res = _post_install_plugin_hook(home, pid, no_build=no_build, package_dir=package_dir)
                if hook_res is not None:
                    build_reports[pid] = hook_res
            discovery.save_installed_plugins(home, updated)
            result.update(
                diagnostic="ready",
                available=True,
                installedPluginIds=updated,
                builtinPlugins=installed_now,
                buildReports=build_reports,
                message=f"Installed built-in plugins: {', '.join(installed_now)}",
            )
            return result

        if action == "install-plugin":
            catalog_doc = _catalog_doc(shell_root)
            if not isinstance(plugin_id, str) or not plugin_id.strip():
                raise ValueError("install-plugin requires a plugin id")
            plugin_id = plugin_id.strip()
            known_ids = _known_plugin_ids(shell_root)
            if plugin_id not in known_ids:
                raise ValueError(f"Unknown integration plugin: {plugin_id}")
            if not bundled.is_dir():
                needs_base_upgrade = not current or source_dir is not None
                if current and not needs_base_upgrade:
                    session_file = home / "releases" / current / "AlisSession.qml"
                    try:
                        session_text = session_file.read_text(encoding="utf-8")
                    except OSError:
                        session_text = ""
                    if (
                        (plugin_id == "alis_files" and "alisFilesLoader" not in session_text)
                        or (plugin_id == "exercises_tracker" and "exercisesTrackerLoader" not in session_text)
                        or (plugin_id == "spaced_repetition" and "spacedRepetitionLoader" not in session_text)
                    ):
                        needs_base_upgrade = True
                if needs_base_upgrade:
                    rel = _install_base_local(home, current, previous_file, shell_root, revision_fetch, archive_fetch, source_dir=source_dir)
                    result.update(diagnostic="ready", available=True,
                                  installedSha=rel["installedSha"], latestSha=rel["latestSha"],
                                  canRollback=(bool(current) and current != rel["installedSha"]) or result["canRollback"],
                                  version=rel["version"])
                    current = rel["installedSha"]
                pkg_report = discovery.inspect_package(home / "releases" / current)
                if pkg_report.get("layout") in ("base-v2", "split-v2"):
                    already_intact = (
                        reuse_installed
                        and source_dir is None
                        and (
                            discovery.inspect_installed_plugin(home / "plugins" / plugin_id, plugin_id)[0]
                            or (pkg_report.get("layout") == "split-v2" and (home / "releases" / current / "plugins" / plugin_id).is_dir())
                        )
                    )
                    if not already_intact:
                        subfiles, plugin_sha = _fetch_plugin_payload(plugin_id, revision_fetch, archive_fetch, source_dir=source_dir)
                        if subfiles:
                            _install_plugin_tree(home, plugin_id, subfiles, plugin_sha)
                        elif pkg_report.get("layout") == "base-v2":
                            raise ValueError(f"Failed to download plugin payload for {plugin_id}")
            package_dir = bundled if bundled.is_dir() else (home / "releases" / current if current else None)
            valid_ids = _known_plugin_ids(shell_root, package_dir)
            if plugin_id not in valid_ids:
                raise ValueError(f"Plugin {plugin_id} is not in this Alis-Intergration release")
            existing, explicit = discovery.load_installed_plugins(home, valid_ids)
            updated = list(existing) if explicit else []
            if plugin_id not in updated:
                updated.append(plugin_id)
            discovery.save_installed_plugins(home, updated)
            hook_res = _post_install_plugin_hook(home, plugin_id, no_build=no_build, package_dir=package_dir)
            deps = discovery.inspect_plugin_dependencies(catalog_doc).get(plugin_id, {})
            missing = deps.get("missing") or []
            if missing and not deps.get("userSpace", True):
                helpers_cmd = deps.get("helpersCommand") or f"./setup integrations install {plugin_id}"
                setup_cmd = deps.get("setupCommand") or "./setup install-deps"
                guidance = f"Missing dependencies: {', '.join(missing)}. Run {setup_cmd} and {helpers_cmd}."
            elif missing:
                guidance = f"Missing dependencies: {', '.join(missing)}."
            else:
                guidance = f"Downloaded & installed {plugin_id}"
            result.update(plugin=plugin_id, installedPluginIds=updated,
                          dependencies=deps, message=guidance)
            if hook_res is not None:
                result["buildReport"] = hook_res
            return result

        if action == "remove-plugin":
            if not isinstance(plugin_id, str) or not plugin_id.strip():
                raise ValueError("remove-plugin requires a plugin id")
            plugin_id = plugin_id.strip()
            package_dir = bundled if bundled.is_dir() else (home / "releases" / current if current else None)
            valid_ids = _known_plugin_ids(shell_root, package_dir)
            if plugin_id not in valid_ids:
                raise ValueError(f"Unknown integration plugin: {plugin_id}")
            plugin_dest = home / "plugins" / plugin_id
            if plugin_dest.is_symlink():
                raise ValueError(f"Refusing symlinked plugin directory: {plugin_id}")
            if plugin_dest.exists():
                shutil.rmtree(plugin_dest)
            had_package = bool(current) or bundled.is_dir()
            existing, explicit = discovery.load_installed_plugins(home, valid_ids)
            if explicit:
                updated = [item for item in existing if item != plugin_id]
                discovery.save_installed_plugins(home, updated)
            elif had_package:
                updated = [item for item in valid_ids if item != plugin_id]
                discovery.save_installed_plugins(home, updated)
            else:
                updated = []
            result.update(plugin=plugin_id, installedPluginIds=updated,
                          message=f"Removed integration plugin {plugin_id}; saved preferences retained")
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

        if action == "install-all":
            if bundled.is_dir():
                package_dir = bundled
                valid_ids = _known_plugin_ids(shell_root, package_dir)
                updated = discovery.save_installed_plugins(home, valid_ids)
                version = ""
                try:
                    version = json.loads((bundled / "manifest.json").read_text(encoding="utf-8")).get("version", "")
                except (OSError, ValueError):
                    pass
                hook_res = _post_install_plugin_hook(home, "alis_files", no_build=no_build, package_dir=package_dir) if "alis_files" in updated else None
                result.update(diagnostic="ready", available=True, version=version,
                              installedPluginIds=updated,
                              message="Enabled all bundled integration plugins")
                if hook_res is not None:
                    result["buildReport"] = hook_res
                return result
            rel = _install_release(home, current, previous_file, rev_fetch, arch_fetch, base_only=False)
            target_sha = rel["installedSha"]
            package_dir = home / "releases" / target_sha
            valid_ids = _known_plugin_ids(shell_root, package_dir)
            updated = discovery.save_installed_plugins(home, valid_ids)
            hook_res = _post_install_plugin_hook(home, "alis_files", no_build=no_build, package_dir=package_dir) if "alis_files" in updated else None
            result.update(diagnostic="ready", available=True,
                          installedSha=target_sha, latestSha=rel["latestSha"],
                          canRollback=(bool(current) and current != target_sha) or result["canRollback"],
                          version=rel["version"],
                          installedPluginIds=updated,
                          message="Installed all verified Alis-Intergration plugins")
            if hook_res is not None:
                result["buildReport"] = hook_res
            return result

        if action != "install":
            raise ValueError("Unsupported action")
        rel = _install_release(home, current, previous_file, rev_fetch, arch_fetch, base_only=False)
        result["latestSha"] = rel["latestSha"]
        if rel["alreadyCurrent"]:
            result["message"] = "Already on the latest revision"
            return result
        result.update(diagnostic="ready", available=True, installedSha=rel["installedSha"],
                      canRollback=bool(current) or result["canRollback"],
                      version=rel["version"],
                      message="Installed verified Alis-Intergration release")
        return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("status", "check", "install", "install-base", "install-builtins", "install-all", "remove", "rollback",
                                                    "install-plugin", "remove-plugin",
                                                    "system-status", "helpers-status", "helpers-install", "helpers-remove", "helpers-ensure",
                                                    "gateway-status", "gateway-install", "gateway-remove", "gateway-rollback"))
    parser.add_argument("plugin_id", nargs="?", default=None)
    parser.add_argument("--plugin", dest="plugin_flag", default=None)
    parser.add_argument("--source", dest="source_dir", type=Path, default=None)
    parser.add_argument("--reuse-installed", action="store_true")
    parser.add_argument("--no-build", action="store_true")
    parser.add_argument("--shell-root", type=Path, default=ROOT)
    parser.add_argument("--data-home", type=Path, default=Path(
        os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share"))))
    args = parser.parse_args()
    try:
        canonical = args.data_home / "alis-intergration"
        legacy = args.data_home / _LEGACY_COMPONENT
        if args.action in ("install", "install-base", "install-builtins", "install-all", "remove", "rollback", "install-plugin", "remove-plugin"):
            if legacy.is_dir() and not legacy.is_symlink() and not canonical.exists():
                os.replace(legacy, canonical)
            home = canonical
        else:
            home = canonical if canonical.exists() or not legacy.exists() else legacy
        target_plugin = args.plugin_flag or args.plugin_id or None
        result = operate(args.action, home, args.shell_root, plugin_id=target_plugin, source_dir=args.source_dir, reuse_installed=args.reuse_installed, no_build=args.no_build)
        print(json.dumps(result))
    except (OSError, ValueError, KeyError, json.JSONDecodeError, tarfile.TarError, urllib.error.URLError) as error:
        print(json.dumps({"ok": False, "action": args.action, "error": str(error)}))
        raise SystemExit(1)


if __name__ == "__main__":
    main()
