#!/usr/bin/env python3
"""Finite, read-only discovery of the optional Alis-Intergration base and per-plugin payloads."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile

ENTRYPOINTS = {
    "session": "AlisSession.qml",
    "thinkfanSettings": "plugins/thinkfan/modules/settings/ThinkfanSettings.qml",
    "tlpSettings": "plugins/tlp/modules/settings/TlpPowerSettings.qml",
    "nexusSettings": "plugins/nexus/modules/settings/NexusThemeSettings.qml",
    "nexusTodoSettings": "plugins/nexus/modules/settings/NexusTodoSettings.qml",
    "tlpRowSettings": "plugins/tlp/modules/settings/TlpSettingRow.qml",
    "tlpWaffleSettings": "plugins/tlp/modules/waffle/settings/WTlpPowerSettings.qml",
    "tlpWaffleRowSettings": "plugins/tlp/modules/waffle/settings/WTlpSettingRow.qml",
    "managedTodo": "plugins/nexus/services/NexusTodoBackend.qml",
    "dailyTodo": "plugins/nexus/services/DailyNoteTodoBackend.qml",
}

LEGACY_ENTRYPOINTS = {
    "session": "AlisSession.qml",
    "thinkfanSettings": "modules/settings/ThinkfanSettings.qml",
    "tlpSettings": "modules/settings/TlpPowerSettings.qml",
    "nexusSettings": "modules/settings/NexusThemeSettings.qml",
    "nexusTodoSettings": "modules/settings/NexusTodoSettings.qml",
    "tlpRowSettings": "modules/settings/TlpSettingRow.qml",
    "tlpWaffleSettings": "modules/waffle/settings/WTlpPowerSettings.qml",
    "tlpWaffleRowSettings": "modules/waffle/settings/WTlpSettingRow.qml",
    "managedTodo": "services/NexusTodoBackend.qml",
    "dailyTodo": "services/DailyNoteTodoBackend.qml",
}

SETTINGS_PATH_RE = re.compile(r"(?:plugins/[a-z][a-z0-9_-]{0,47}/)?modules/(?:[A-Za-z0-9_-]+/)*[A-Za-z0-9_-]+\.qml")
TOKEN_RE = re.compile(r"[a-z][a-z0-9_-]{0,47}")


def plugin_metadata(data):
    """Normalize declarative navigation only; never import optional code."""
    plugins = data.get("plugins", [])  # Older API 1 packages remain usable.
    integrations = data.get("integrations", [])
    settings = data.get("settings", {})
    if not isinstance(plugins, list) or len(plugins) > 32 or not isinstance(integrations, list):
        raise ValueError("Invalid plugin catalog")
    if not isinstance(settings, dict) or any(
            not isinstance(key, str) or not isinstance(path, str)
            or not SETTINGS_PATH_RE.fullmatch(path)
            for key, path in settings.items()):
        raise ValueError("Unsafe plugin settings path")
    normalized, seen = [], set()

    def token(value):
        return isinstance(value, str) and TOKEN_RE.fullmatch(value)

    def label(value):
        return isinstance(value, str) and 0 < len(value) <= 80 and value.isprintable()

    for plugin in plugins:
        if not isinstance(plugin, dict):
            raise ValueError("Invalid plugin metadata")
        ident, name, icon = (plugin.get(key) for key in ("id", "name", "icon"))
        if not token(ident) or ident == "management" or ident in seen or ident not in integrations or not label(name) or not token(icon):
            raise ValueError("Invalid plugin identity")
        seen.add(ident)
        capabilities = plugin.get("capabilities")
        if not isinstance(capabilities, list) or not 0 < len(capabilities) <= 16:
            raise ValueError("Invalid plugin capabilities")
        items, ids = [], set()
        for capability in capabilities:
            if not isinstance(capability, dict):
                raise ValueError("Invalid plugin capability")
            cid, title, entry = (capability.get(key) for key in ("id", "name", "settings"))
            if not token(cid) or cid in ids or not label(title) or not isinstance(entry, str) or entry not in settings:
                raise ValueError("Invalid plugin settings reference")
            ids.add(cid)
            item = {"id": cid, "name": title, "settings": entry}
            if "waffleSettings" in capability:
                waffle = capability["waffleSettings"]
                if not isinstance(waffle, str) or waffle not in settings:
                    raise ValueError("Invalid Waffle settings reference")
                item["waffleSettings"] = waffle
            if "view" in capability:
                if entry != "nexusTodo" or capability["view"] not in ("todo", "quicknotes"):
                    raise ValueError("Unsupported settings view")
                item["view"] = capability["view"]
            items.append(item)
        meta = {"id": ident, "name": name, "icon": icon, "capabilities": items}
        if isinstance(plugin.get("helpersScope"), str) and token(plugin["helpersScope"]):
            meta["helpersScope"] = plugin["helpersScope"]
        normalized.append(meta)
    return normalized


def _inventory_tree(root, *, ignore_names=("manifest.json",)):
    inventory = {}
    total = 0
    for path in root.rglob("*"):
        if path.is_symlink():
            raise ValueError("linked payload")
        rel = path.relative_to(root)
        if "__pycache__" in rel.parts and path.is_file() and path.suffix in (".pyc", ".pyo"):
            continue
        if path.is_file():
            name = rel.as_posix()
            if name in ignore_names:
                continue
            if len(inventory) >= 512 or path.stat().st_size > 8 * 1024 * 1024:
                raise ValueError("oversized payload")
            total += path.stat().st_size
            if total > 64 * 1024 * 1024:
                raise ValueError("oversized package")
            inventory[name] = hashlib.sha256(path.read_bytes()).hexdigest()
        elif not path.is_file() and not path.is_dir():
            raise ValueError("nonregular payload")
    return inventory


def inspect_installed_plugin(plugin_dir, plugin_id):
    try:
        if not TOKEN_RE.fullmatch(str(plugin_id)):
            return False, {}
        if plugin_dir.is_symlink() or not plugin_dir.is_dir():
            return False, {}
        manifest_path = plugin_dir / "plugin-manifest.json"
        if not manifest_path.is_file() or manifest_path.is_symlink() or manifest_path.stat().st_size > 65536:
            return False, {}
        doc = json.loads(manifest_path.read_text(encoding="utf-8"))
        if not isinstance(doc, dict) or doc.get("id") != plugin_id or doc.get("hostApi") != 1:
            return False, {}
        hashes = doc.get("files")
        if not isinstance(hashes, dict) or not hashes or len(hashes) > 512:
            return False, {}
        inventory = _inventory_tree(plugin_dir, ignore_names=("plugin-manifest.json",))
        for name, digest in hashes.items():
            if not isinstance(name, str) or not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest):
                return False, {}
            if inventory.get(name) != digest:
                return False, {}
        if inventory != hashes:
            return False, {}
        return True, doc
    except (OSError, ValueError, TypeError):
        return False, {}


def inspect_package(package):
    result = {"available": False, "diagnostic": "not-installed"}
    try:
        manifest = package / "manifest.json"
        if not manifest.is_file():
            return result
        if manifest.is_symlink() or manifest.stat().st_size > 65536:
            raise ValueError("oversized manifest")
        data = json.loads(manifest.read_text())
        if not isinstance(data, dict):
            raise ValueError("manifest must be an object")
        if data.get("id") != "alis-intergration" or type(data.get("hostApi")) is not int or data["hostApi"] != 1:
            return {**result, "diagnostic": "incompatible-package"}
        settings = data.get("settings", {})
        backends = data.get("backends", {})
        views = data.get("views", {})
        scripts = data.get("scripts", {})
        if not isinstance(settings, dict) or not isinstance(backends, dict):
            raise ValueError("invalid entrypoints")
        entries = {"session": data.get("session"), "tlpSettings": settings.get("tlp"), "thinkfanSettings": settings.get("thinkfan"),
                   "nexusSettings": settings.get("nexus"),
                   "nexusTodoSettings": settings.get("nexusTodo"), "tlpRowSettings": settings.get("tlpRow"),
                   "tlpWaffleSettings": settings.get("tlpWaffle"), "tlpWaffleRowSettings": settings.get("tlpWaffleRow"),
                   "managedTodo": backends.get("managedTodo"),
                   "dailyTodo": backends.get("dailyTodo")}
        if entries == ENTRYPOINTS:
            is_legacy = False
        elif entries == LEGACY_ENTRYPOINTS:
            is_legacy = True
        else:
            raise ValueError("unexpected entrypoints")
        plugins = plugin_metadata(data)
        root = package.resolve()
        hashes = data.get("files")
        if not isinstance(hashes, dict) or not hashes or len(hashes) > 512:
            raise ValueError("missing payload identity")
        declared_layout = str(data.get("layout", ""))
        inventory = _inventory_tree(root, ignore_names=("manifest.json",))
        if is_legacy:
            if not all(name in hashes for name in (*LEGACY_ENTRYPOINTS.values(), *settings.values())):
                raise ValueError("incomplete package")
            layout = "legacy-v1"
        elif declared_layout == "base-v2" or (
                not (root / "plugins").exists()
                and data.get("session") in hashes
                and set(hashes).issubset({"AlisSession.qml", "LICENSE"})):
            if data.get("session") not in hashes:
                raise ValueError("incomplete base package")
            layout = "base-v2"
        else:
            if not all(name in hashes for name in (*ENTRYPOINTS.values(), *settings.values())):
                raise ValueError("incomplete package")
            layout = "split-v2"
        for name, digest in hashes.items():
            if not isinstance(name, str) or not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest):
                raise ValueError("invalid payload identity")
            if inventory.get(name) != digest:
                raise ValueError("modified payload")
        if inventory != hashes:
            raise ValueError("unlisted payload")
        version, sha = data.get("version"), data.get("sourceSha")
        if not isinstance(version, str) or not version or len(version) > 64 or not isinstance(sha, str) or not re.fullmatch(r"[0-9a-f]{40}", sha):
            raise ValueError("invalid revision")
        return {
            "available": True,
            "diagnostic": "ready",
            "root": str(root),
            "layout": layout,
            "version": version,
            "sourceSha": sha,
            "plugins": plugins,
            "settings": settings,
            "views": views if isinstance(views, dict) else {},
            "backends": backends,
            "scripts": scripts if isinstance(scripts, dict) else {},
            "pluginMetadataAvailable": bool(plugins),
        }
    except (OSError, ValueError, TypeError):
        return {**result, "diagnostic": "invalid-package"}


_LEGACY_PREFIX = "".join(("i", "nir"))
_LEGACY_COMPONENT = "".join(("hada", "lird"))
_LEGACY_HELPER_NAMES = {
    "alis-thinkfan": f"{_LEGACY_PREFIX}-thinkfan",
    "alis-battery-charge-limit": f"{_LEGACY_PREFIX}-battery-charge-limit",
    "alis-intergration-system-provision": f"{_LEGACY_PREFIX}-{_LEGACY_COMPONENT}-system-provision",
}


def resolve_user_data_dir(data_home=None):
    base = Path(data_home or os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
    canonical = base / "alis-intergration"
    legacy = base / _LEGACY_COMPONENT
    if (canonical / "current").exists() or (canonical / "current").is_symlink() or (canonical.exists() and not legacy.exists()):
        return canonical
    if legacy.exists():
        return legacy
    return canonical


def resolve_bundled_package(shell_root):
    root = Path(shell_root)
    canonical = root / "optional/alis-intergration"
    if canonical.exists():
        return canonical
    return root / "optional" / _LEGACY_COMPONENT


_DEFAULT_DEPENDENCIES = {
    "alis_files": {
        "userSpace": True,
        "builtIn": True,
        "requiresSystemHelpers": False,
        "packages": ["gtk4", "rust"],
        "binaries": ["python3"],
        "helpers": [],
        "setupCommand": "",
        "helpersCommand": "",
        "removeHelpersCommand": "",
        "note": "Built-in user-space GTK4 file manager (compiled locally on install/update; no root helpers needed).",
    },
    "nexus": {
        "userSpace": True,
        "builtIn": True,
        "requiresSystemHelpers": False,
        "packages": ["python3"],
        "binaries": ["python3"],
        "helpers": [],
        "setupCommand": "",
        "helpersCommand": "",
        "removeHelpersCommand": "",
        "note": "User-space plugin (requires Python 3; no root helpers needed).",
    },
    "spaced_repetition": {
        "userSpace": True,
        "builtIn": True,
        "requiresSystemHelpers": False,
        "packages": ["python3"],
        "binaries": ["python3"],
        "helpers": [],
        "setupCommand": "",
        "helpersCommand": "",
        "removeHelpersCommand": "",
        "note": "User-space plugin (requires Python 3 for word lookup; no root helpers needed).",
    },
    "exercises_tracker": {
        "userSpace": True,
        "builtIn": True,
        "requiresSystemHelpers": False,
        "packages": ["python3"],
        "binaries": ["python3"],
        "helpers": [],
        "setupCommand": "",
        "helpersCommand": "",
        "removeHelpersCommand": "",
        "note": "User-space plugin (requires Python 3 for safe photo import; no root helpers needed).",
    },
    "tlp": {
        "userSpace": False,
        "requiresSystemHelpers": True,
        "helpersScope": "tlp",
        "packages": ["tlp", "alis-deps"],
        "binaries": ["tlp"],
        "helpers": ["/usr/libexec/alis-battery-charge-limit"],
        "provisioner": "/usr/libexec/alis-intergration-system-provision",
        "setupCommand": "./setup install-deps",
        "helpersCommand": "./setup integrations install tlp",
        "removeHelpersCommand": "./setup integrations remove tlp",
        "note": "Requires tlp (via ./setup install-deps / alis-deps) and TLP battery helpers (./setup integrations install tlp).",
    },
    "thinkfan": {
        "userSpace": False,
        "requiresSystemHelpers": True,
        "helpersScope": "thinkfan",
        "packages": ["thinkfan", "alis-deps"],
        "binaries": ["thinkfan"],
        "helpers": ["/usr/libexec/alis-thinkfan"],
        "provisioner": "/usr/libexec/alis-intergration-system-provision",
        "setupCommand": "./setup install-deps",
        "helpersCommand": "./setup integrations install thinkfan",
        "removeHelpersCommand": "./setup integrations remove thinkfan",
        "note": "Requires thinkfan (via ./setup install-deps / alis-deps) and Thinkfan helpers (./setup integrations install thinkfan).",
    },
}


def installed_plugins_path(user_data):
    return Path(user_data) / "installed-plugins.json"


def load_installed_plugins(user_data, valid_ids=None):
    target = installed_plugins_path(user_data)
    if target.is_symlink():
        raise ValueError("Refusing symlinked installed-plugins.json")
    if not target.exists():
        return None, False
    doc = json.loads(target.read_text(encoding="utf-8"))
    if not isinstance(doc, dict) or doc.get("schemaVersion") != 1 or not isinstance(doc.get("plugins"), list):
        raise ValueError("Invalid installed-plugins.json schema")
    allowed = set(valid_ids) if valid_ids is not None else None
    seen = []
    for item in doc["plugins"]:
        if isinstance(item, str) and item and (allowed is None or item in allowed) and item not in seen:
            seen.append(item)
    return seen, True


def save_installed_plugins(user_data, plugin_ids):
    user_data = Path(user_data)
    user_data.mkdir(parents=True, exist_ok=True)
    target = installed_plugins_path(user_data)
    if target.is_symlink():
        raise ValueError("Refusing symlinked installed-plugins.json")
    unique = []
    for item in plugin_ids:
        if isinstance(item, str) and item and item not in unique:
            unique.append(item)
    payload = json.dumps({"schemaVersion": 1, "plugins": unique}, indent=2) + "\n"
    fd, tmp_path = tempfile.mkstemp(prefix=".installed-plugins-", suffix=".tmp", dir=user_data)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(payload)
        os.chmod(tmp_path, 0o644)
        os.replace(tmp_path, target)
    except Exception:
        Path(tmp_path).unlink(missing_ok=True)
        raise
    return unique


def _binary_available(name):
    if shutil.which(name):
        return True
    for directory in ("/usr/bin", "/usr/sbin", "/bin", "/sbin"):
        candidate = Path(directory) / name
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return True
    return False


def _trusted_executable_file(candidate):
    path = Path(candidate)
    return not path.is_symlink() and path.is_file() and os.access(path, os.X_OK)


def _resolve_helper_path(path_str):
    if not isinstance(path_str, str) or not path_str:
        return ""
    candidate = Path(path_str)
    if _trusted_executable_file(candidate):
        return str(candidate)
    legacy_name = _LEGACY_HELPER_NAMES.get(candidate.name)
    if legacy_name:
        legacy_candidate = candidate.with_name(legacy_name)
        if _trusted_executable_file(legacy_candidate):
            return str(legacy_candidate)
    return ""


def _helper_available(path_str):
    return bool(_resolve_helper_path(path_str))


def inspect_runtime_tools():
    return {
        "python3": _binary_available("python3"),
        "tlp": _binary_available("tlp"),
        "thinkfan": _binary_available("thinkfan"),
    }


def inspect_plugin_dependencies(catalog_doc=None):
    raw_deps = catalog_doc.get("dependencies") if isinstance(catalog_doc, dict) and isinstance(catalog_doc.get("dependencies"), dict) else {}
    report = {}
    for plugin_id, defaults in _DEFAULT_DEPENDENCIES.items():
        spec = dict(defaults)
        override = raw_deps.get(plugin_id)
        if isinstance(override, dict):
            spec.update(override)
        binaries = [str(b) for b in spec.get("binaries", []) if isinstance(b, str) and b]
        helpers = [str(h) for h in spec.get("helpers", []) if isinstance(h, str) and h]
        primary_helpers = [h for h in helpers if not h.endswith("system-provision")]
        if not primary_helpers and spec.get("requiresSystemHelpers"):
            primary_helpers = helpers
        provisioner = str(spec.get("provisioner") or "/usr/libexec/alis-intergration-system-provision")
        binary_checks = [{"name": b, "installed": _binary_available(b)} for b in binaries]
        helper_checks = [{"path": h, "installed": _helper_available(h)} for h in primary_helpers]
        binaries_ready = all(c["installed"] for c in binary_checks)
        helpers_ready = all(c["installed"] for c in helper_checks) if spec.get("requiresSystemHelpers") else True
        provisioner_ready = _helper_available(provisioner) if spec.get("requiresSystemHelpers") else True
        missing = [c["name"] for c in binary_checks if not c["installed"]]
        if spec.get("requiresSystemHelpers"):
            missing.extend(c["path"] for c in helper_checks if not c["installed"])
        packages = [str(p) for p in spec.get("packages", []) if isinstance(p, str) and p]
        user_space = bool(spec.get("userSpace", not spec.get("requiresSystemHelpers", False)))
        setup_cmd = str(spec.get("setupCommand", "./setup install-deps" if not user_space else ""))
        helpers_cmd = str(spec.get("helpersCommand", f"./setup integrations install {plugin_id}" if not user_space else ""))
        remove_cmd = str(spec.get("removeHelpersCommand", f"./setup integrations remove {plugin_id}" if not user_space else ""))
        report[plugin_id] = {
            "userSpace": user_space,
            "requiresSystemHelpers": bool(spec.get("requiresSystemHelpers", False)),
            "helpersScope": str(spec.get("helpersScope", plugin_id if not user_space else "")),
            "satisfied": binaries_ready and helpers_ready,
            "binariesReady": binaries_ready,
            "helpersReady": helpers_ready,
            "provisionerReady": provisioner_ready,
            "packages": packages,
            "binaries": binary_checks,
            "helpers": helper_checks,
            "missing": missing,
            "setupCommand": setup_cmd,
            "helpersCommand": helpers_cmd,
            "removeHelpersCommand": remove_cmd,
            "note": str(spec.get("note", "")),
        }
    return report


def inspect(shell_root, data_home=None):
    user_data = resolve_user_data_dir(data_home)
    bundled = resolve_bundled_package(shell_root)
    is_bundled = bundled.exists()
    package = bundled if is_bundled else (user_data / "current")
    result = inspect_package(package)
    result["canRollback"] = False
    result["pluginsDir"] = str(user_data / "plugins")
    result["pluginRoots"] = {}
    catalog_doc = {}
    try:
        previous_file = user_data / ".previous"
        if previous_file.is_file() and not previous_file.is_symlink() and previous_file.stat().st_size <= 64:
            previous = previous_file.read_text().strip()
            prior = user_data / "releases" / previous
            if re.fullmatch(r"[0-9a-f]{40}", previous) and not prior.is_symlink():
                report = inspect_package(prior)
                result["canRollback"] = report.get("available") is True and report.get("sourceSha") == previous
        catalog_doc = json.loads((Path(shell_root) / "defaults/integration-plugins.json").read_text())
        result["catalog"] = plugin_metadata(catalog_doc)
    except (OSError, ValueError, TypeError):
        result["catalog"] = []
    result["dependencies"] = inspect_plugin_dependencies(catalog_doc)
    result["runtimeTools"] = inspect_runtime_tools()
    all_package_plugins = list(result.get("plugins") or [])
    valid_ids = [plugin["id"] for plugin in all_package_plugins if isinstance(plugin, dict) and plugin.get("id")]
    if not valid_ids:
        valid_ids = [plugin["id"] for plugin in result.get("catalog") or [] if isinstance(plugin, dict) and plugin.get("id")]
    if not valid_ids:
        valid_ids = list(_DEFAULT_DEPENDENCIES.keys())
    result["pluginSelectionExplicit"] = False
    if not result.get("available"):
        result["installedPluginIds"] = []
        result["plugins"] = []
        return result
    try:
        selected, explicit = load_installed_plugins(user_data, valid_ids or None)
    except (OSError, ValueError, TypeError):
        result["installedPluginIds"] = []
        result["plugins"] = []
        result["pluginSelectionExplicit"] = True
        return result

    layout = result.get("layout", "")
    pkg_root = Path(result["root"])
    plugin_roots = {}
    installed_ids = []

    if layout == "base-v2":
        candidates = selected if explicit else valid_ids
        if not explicit:
            # Base-only install with no installed-plugins.json checks only actually installed plugin dirs.
            candidates = valid_ids
        for pid in candidates:
            pdir = user_data / "plugins" / pid
            ok, _ = inspect_installed_plugin(pdir, pid)
            if ok:
                plugin_roots[pid] = str(pdir.resolve())
                installed_ids.append(pid)
        result["pluginSelectionExplicit"] = True
    elif layout == "split-v2":
        selected_set = set(selected) if explicit else set(valid_ids)
        for pid in valid_ids:
            if pid not in selected_set:
                continue
            pdir = pkg_root / "plugins" / pid
            if pdir.is_dir() and not pdir.is_symlink():
                plugin_roots[pid] = str(pdir.resolve())
                installed_ids.append(pid)
            else:
                alt = user_data / "plugins" / pid
                ok, _ = inspect_installed_plugin(alt, pid)
                if ok:
                    plugin_roots[pid] = str(alt.resolve())
                    installed_ids.append(pid)
        result["pluginSelectionExplicit"] = explicit
    else:
        # Legacy monolithic layout.
        if explicit:
            selected_set = set(selected)
            installed_ids = [pid for pid in valid_ids if pid in selected_set]
            result["pluginSelectionExplicit"] = True
        else:
            installed_ids = [plugin["id"] for plugin in all_package_plugins] if all_package_plugins else list(valid_ids)

    installed_set = set(installed_ids)
    result["installedPluginIds"] = installed_ids
    result["pluginRoots"] = plugin_roots
    result["plugins"] = [plugin for plugin in all_package_plugins if plugin.get("id") in installed_set]
    return result


if __name__ == "__main__":
    print(json.dumps(inspect(sys.argv[1] if len(sys.argv) == 2 else Path(__file__).resolve().parents[1])))
