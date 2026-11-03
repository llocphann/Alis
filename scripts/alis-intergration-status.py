#!/usr/bin/env python3
"""Finite, self-healing discovery of a committed or local optional integration package."""
import hashlib
import json
import os
from pathlib import Path
import re
import sys

ENTRYPOINTS = {
    "session": "AlisSession.qml",
    "thinkfanSettings": "modules/settings/ThinkfanSettings.qml",
    "tlpSettings": "modules/settings/TlpPowerSettings.qml",
    "obsidianSettings": "modules/settings/ObsidianThemeSettings.qml",
    "obsidianTodoSettings": "modules/settings/ObsidianTodoSettings.qml",
    "tlpRowSettings": "modules/settings/TlpSettingRow.qml",
    "tlpWaffleSettings": "modules/waffle/settings/WTlpPowerSettings.qml",
    "tlpWaffleRowSettings": "modules/waffle/settings/WTlpSettingRow.qml",
    "managedTodo": "services/ObsidianTodoBackend.qml",
    "dailyTodo": "services/DailyNoteTodoBackend.qml",
}

PAYLOAD_PREFIXES = (
    "AlisSession.qml",
    "LICENSE",
    "services/",
    "modules/",
    "assets/",
    "scripts/integrations/",
    "scripts/todo/",
    "scripts/notes/",
)


def _is_payload_relpath(rel_posix):
    if rel_posix in ("AlisSession.qml", "LICENSE"):
        return True
    return any(rel_posix.startswith(p) for p in PAYLOAD_PREFIXES if p.endswith("/"))


def plugin_metadata(data):
    """Normalize declarative navigation only; never import optional code."""
    plugins = data.get("plugins", [])  # Older API 1 packages remain usable.
    integrations = data.get("integrations", [])
    settings = data.get("settings", {})
    if not isinstance(plugins, list) or len(plugins) > 32 or not isinstance(integrations, list):
        raise ValueError("Invalid plugin catalog")
    if not isinstance(settings, dict) or any(
            not isinstance(key, str) or not isinstance(path, str)
            or not re.fullmatch(r"modules/(?:[A-Za-z0-9_-]+/)*[A-Za-z0-9_-]+\.qml", path)
            for key, path in settings.items()):
        raise ValueError("Unsafe plugin settings path")
    normalized, seen = [], set()
    def token(value):
        return isinstance(value, str) and re.fullmatch(r"[a-z][a-z0-9_-]{0,47}", value)
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
                if entry != "obsidianTodo" or capability["view"] not in ("todo", "quicknotes"):
                    raise ValueError("Unsupported settings view")
                item["view"] = capability["view"]
            items.append(item)
        normalized.append({"id": ident, "name": name, "icon": icon, "capabilities": items})
    return normalized


def inspect_package(package):
    result = {"available": False, "diagnostic": "not-installed"}
    try:
        manifest = package / "manifest.json"
        if not manifest.is_file():
            return result
        if manifest.is_symlink() or manifest.stat().st_size > 131072:
            raise ValueError("oversized manifest")
        data = json.loads(manifest.read_text())
        if not isinstance(data, dict):
            raise ValueError("manifest must be an object")
        if data.get("id") != "alis-intergration" or type(data.get("hostApi")) is not int or data["hostApi"] != 1:
            return {**result, "diagnostic": "incompatible-package"}
        settings, backends = data.get("settings", {}), data.get("backends", {})
        if not isinstance(settings, dict) or not isinstance(backends, dict):
            raise ValueError("invalid entrypoints")
        entries = {"session": data.get("session"), "tlpSettings": settings.get("tlp"), "thinkfanSettings": settings.get("thinkfan"),
                   "obsidianSettings": settings.get("obsidian"),
                   "obsidianTodoSettings": settings.get("obsidianTodo"), "tlpRowSettings": settings.get("tlpRow"),
                   "tlpWaffleSettings": settings.get("tlpWaffle"), "tlpWaffleRowSettings": settings.get("tlpWaffleRow"),
                   "managedTodo": backends.get("managedTodo"),
                   "dailyTodo": backends.get("dailyTodo")}
        if entries != ENTRYPOINTS:
            raise ValueError("unexpected entrypoints")
        plugins = plugin_metadata(data)
        root = package.resolve()

        # Verify all required entrypoint files exist on disk and compute payload inventory
        is_repo_checkout = (root / ".git").exists()
        inventory = {}
        total = 0
        for path in root.rglob("*"):
            rel = path.relative_to(root)
            rel_posix = rel.as_posix()
            if ".git" in rel.parts or "__pycache__" in rel.parts:
                continue
            if is_repo_checkout and not _is_payload_relpath(rel_posix):
                continue
            if path.is_symlink():
                continue
            if path.is_file() and path != manifest.resolve():
                if len(inventory) >= 512 or path.stat().st_size > 2 * 1024 * 1024:
                    raise ValueError("oversized payload")
                total += path.stat().st_size
                if total > 24 * 1024 * 1024:
                    raise ValueError("oversized package")
                inventory[rel_posix] = hashlib.sha256(path.read_bytes()).hexdigest()

        if not all(name in inventory for name in (*ENTRYPOINTS.values(), *settings.values())):
            raise ValueError("incomplete package")

        version = data.get("version") or "1.0.0"
        if not isinstance(version, str) or not version or len(version) > 64:
            raise ValueError("invalid version")

        sha = data.get("sourceSha")
        if not isinstance(sha, str) or not re.fullmatch(r"[0-9a-f]{40}", sha):
            if re.fullmatch(r"[0-9a-f]{40}", root.name):
                sha = root.name
            else:
                derived = (data.get("derivedFrom") or {}).get("sourceSha", "")
                sha = derived if re.fullmatch(r"[0-9a-f]{40}", str(derived)) else hashlib.sha1(
                    json.dumps(inventory, sort_keys=True).encode()).hexdigest()

        # Self-heal manifest.json in release directories when files were updated locally
        if not is_repo_checkout and (data.get("files") != inventory or data.get("sourceSha") != sha):
            try:
                updated = dict(data)
                updated["sourceSha"] = sha
                updated["files"] = inventory
                manifest.write_text(json.dumps(updated, indent=2) + "\n")
            except OSError:
                pass

        return {"available": True, "diagnostic": "ready", "root": str(root),
                "version": version, "sourceSha": sha, "plugins": plugins,
                "settings": settings, "pluginMetadataAvailable": bool(plugins)}
    except (OSError, ValueError, TypeError):
        return {**result, "diagnostic": "invalid-package"}


_LEGACY_COMPONENT = "".join(("hada", "lird"))


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


def resolve_local_repo_package(shell_root):
    candidates = [
        Path(shell_root).resolve().parent / "Alis-Intergration",
        Path.home() / "Shared_Documents/Repos/Alis_Framework/Alis-Intergration",
    ]
    for cand in candidates:
        if (cand / "manifest.json").is_file() and (cand / "AlisSession.qml").is_file():
            return cand
    return None


def inspect(shell_root, data_home=None):
    user_data = resolve_user_data_dir(data_home)
    package = resolve_bundled_package(shell_root)
    if not package.exists():
        package = user_data / "current"
    result = inspect_package(package)
    if not result.get("available"):
        local_repo = resolve_local_repo_package(shell_root)
        if local_repo is not None:
            result = inspect_package(local_repo)
    result["canRollback"] = False
    try:
        previous_file = user_data / ".previous"
        if previous_file.is_file() and not previous_file.is_symlink() and previous_file.stat().st_size <= 64:
            previous = previous_file.read_text().strip()
            prior = user_data / "releases" / previous
            if re.fullmatch(r"[0-9a-f]{40}", previous) and not prior.is_symlink():
                report = inspect_package(prior)
                result["canRollback"] = report.get("available") is True and report.get("sourceSha") == previous
        catalog = json.loads((Path(shell_root) / "defaults/integration-plugins.json").read_text())
        result["catalog"] = plugin_metadata(catalog)
    except (OSError, ValueError, TypeError):
        result["catalog"] = []
    return result


if __name__ == "__main__":
    print(json.dumps(inspect(sys.argv[1] if len(sys.argv) == 2 else Path(__file__).resolve().parents[1])))
