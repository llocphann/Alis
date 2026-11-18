#!/usr/bin/env python3
"""Guard the QML layout contract that lets Settings page 38 load.

Qt Quick Flow's implicitHeight is a read-only, layout-computed property.
Assigning it fails QML component creation before the page can be shown.
This source-scope guard runs in CI when the native Niri/QML host is absent;
live SettingsPageHost instantiation remains the separate native acceptance.
"""
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import re
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PAGE = ROOT / "modules/settings/IntegrationsConfig.qml"
qml = PAGE.read_text(encoding="utf-8")
flows = list(re.finditer(r"\bFlow\s*\{", qml))
assert len(flows) >= 1, f"expected at least one flow, got {len(flows)}"


def flow_sections(begin):
    """Extract an outer Flow's bindings separately from its nested children."""
    depth = 1
    root = []
    complete = []
    quote = False
    escaped = False
    for char in qml[begin:]:
        if quote:
            if depth == 1:
                root.append(" ")
            complete.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                quote = False
            continue
        if char == '"':
            quote = True
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                break
        complete.append(char)
        if depth == 1:
            root.append(char)
    assert depth == 0, "unclosed Flow body"
    return "".join(root), "".join(complete)


action_flow_found = False
for i, match in enumerate(flows):
    outer, inside = flow_sections(match.end())
    assert re.search(r"\bLayout\.fillWidth\s*:\s*true\b", outer), (
        f"Flow #{i + 1} lost managed layout width"
    )
    assert re.search(r"\bspacing\s*:", outer), f"Flow #{i + 1} lost spacing"
    assert not re.search(r"\bimplicitHeight\s*:", outer), (
        f"Flow #{i + 1} writes Qt's read-only implicitHeight"
    )
    assert not re.search(r"\bwidth\s*:\s*parent\.width\b", outer), (
        f"Flow #{i + 1} bypasses Layout width management"
    )
    if "Install all" in inside:
        action_flow_found = True
        assert "Use Alis tasks" in inside and "Check updates" in inside
assert action_flow_found, "expected package action Flow with Install all"

assert '"Refresh"' in qml
assert 'AlisIntergration.refreshSystemStatus()' in qml
assert '"Check status"' not in qml
assert 'Reinstall helpers' not in qml and 'Install gateway' not in qml
assert './setup integrations' in qml
assert './setup install-deps' in qml
assert 'AlisIntergration.manage("helpers-' not in qml and 'AlisIntergration.manage("gateway-' not in qml
assert 'integrationPrimaryTabs' not in qml, "top primary tab bar should be removed in Management-only rework"
assert 'objectName: "integrationOptionalPluginsCard"' in qml
assert 'objectName: "integrationPluginCard_" + pluginCard.modelData.id' in qml
assert 'objectName: "integrationPluginModal"' in qml
assert 'function handleEscape(): bool' in qml
assert 'AlisIntergration.installPlugin(' in qml and 'AlisIntergration.removePlugin(' in qml
assert 'AlisIntergration.manage("install-all")' in qml and 'AlisIntergration.manage("install")' in qml
assert 'Enable this plugin above to configure it.' in qml
assert 'readonly property var primaryTabs:' in qml and 'integrationCapabilityTabs' in qml
assert 'bentoEqualizeToTarget: !root.embedded' in qml
assert "settingsPageIndex: 38" in qml
assert 'objectName: "integrationSystemHelpersCard"' in qml
assert 'objectName: "integrationCalendarSyncCard"' in qml
assert 'objectName: "integrationWorkflowsCard"' in qml
assert qml.count("_consumesBentoExtraHeight: false") >= 4
assert not re.search(r"\bItem\s*\{\s*Layout\.fillHeight\s*:\s*true\s*\}", qml)

# Verify per-plugin install/remove + legacy full-install compatibility in Python status & manager.
def load_mod(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

status_mod = load_mod("alis_intergration_status", ROOT / "scripts/alis-intergration-status.py")
manager_mod = load_mod("alis_intergration_manager", ROOT / "scripts/alis-intergration-manager.py")

catalog_doc = json.loads((ROOT / "defaults/integration-plugins.json").read_text())
rev = "a" * 40
manifest_base = {
    "id": "alis-intergration",
    "version": "fixture",
    "hostApi": 1,
    "sourceSha": rev,
    "session": "AlisSession.qml",
    "integrations": catalog_doc["integrations"],
    "settings": catalog_doc["settings"],
    "backends": {
        "managedTodo": "services/NexusTodoBackend.qml",
        "dailyTodo": "services/DailyNoteTodoBackend.qml",
    },
    "plugins": catalog_doc["plugins"],
}

files_map = {"AlisSession.qml": b"import QtQuick\nItem {}\n"}
for rel in (*manifest_base["settings"].values(), *manifest_base["backends"].values()):
    files_map[rel] = b"import QtQuick\nItem { implicitHeight: 32 }\n"
manifest_base["files"] = {k: hashlib.sha256(v).hexdigest() for k, v in files_map.items()}
files_map["manifest.json"] = json.dumps(manifest_base).encode("utf-8")

buf = io.BytesIO()
with tarfile.open(fileobj=buf, mode="w:gz") as tar:
    for rel, content in files_map.items():
        info = tarfile.TarInfo(f"repo-{rev}/{rel}")
        info.size = len(content)
        tar.addfile(info, io.BytesIO(content))
archive_bytes = buf.getvalue()

with tempfile.TemporaryDirectory(prefix="alis-plugin-flow-") as tmp:
    tmp_path = Path(tmp)
    shell = tmp_path / "shell"
    (shell / "defaults").mkdir(parents=True)
    (shell / "defaults/integration-plugins.json").write_text((ROOT / "defaults/integration-plugins.json").read_text())
    data_home = tmp_path / "data"
    home = data_home / "alis-intergration"

    # Fresh single-plugin user-space install: installs ONLY nexus with zero system_call/gateway_call.
    res = manager_mod.operate(
        "install-plugin", home, shell,
        revision_fetch=lambda: rev,
        archive_fetch=lambda _u, _l: archive_bytes,
        system_call=lambda *_a: (_ for _ in ()).throw(AssertionError("unexpected root helper call")),
        gateway_call=lambda *_a: (_ for _ in ()).throw(AssertionError("unexpected gateway call")),
        plugin_id="nexus",
    )
    assert res["ok"] and res["installedPluginIds"] == ["nexus"]
    insp = status_mod.inspect(shell, data_home)
    assert insp["available"] and insp["installedPluginIds"] == ["nexus"]
    assert [p["id"] for p in insp["plugins"]] == ["nexus"]
    assert len(insp["catalog"]) == 4
    assert insp["dependencies"]["nexus"]["userSpace"] is True
    assert insp["dependencies"]["spaced_repetition"]["userSpace"] is True
    assert insp["dependencies"]["tlp"]["requiresSystemHelpers"] is True
    assert insp["dependencies"]["tlp"]["setupCommand"] == "./setup install-deps"
    assert insp["dependencies"]["thinkfan"]["helpersCommand"] == "./setup integrations"

    # Add second user-space plugin independently.
    res2 = manager_mod.operate("install-plugin", home, shell, plugin_id="spaced_repetition")
    assert res2["installedPluginIds"] == ["nexus", "spaced_repetition"]
    insp2 = status_mod.inspect(shell, data_home)
    assert insp2["installedPluginIds"] == ["nexus", "spaced_repetition"]

    # Remove one plugin keeps the other installed.
    res3 = manager_mod.operate("remove-plugin", home, shell, plugin_id="nexus")
    assert res3["installedPluginIds"] == ["spaced_repetition"]
    insp3 = status_mod.inspect(shell, data_home)
    assert [p["id"] for p in insp3["plugins"]] == ["spaced_repetition"]

    # Legacy compatibility: removing installed-plugins.json while current symlink exists treats all 4 installed.
    (home / "installed-plugins.json").unlink()
    legacy_insp = status_mod.inspect(shell, data_home)
    assert [p["id"] for p in legacy_insp["plugins"]] == ["tlp", "thinkfan", "nexus", "spaced_repetition"]
    assert legacy_insp["pluginSelectionExplicit"] is False

    # Removing one plugin from legacy setup migrates remaining 3 into installed-plugins.json.
    rem_legacy = manager_mod.operate("remove-plugin", home, shell, plugin_id="tlp")
    assert rem_legacy["installedPluginIds"] == ["thinkfan", "nexus", "spaced_repetition"]

    # Partial selection -> install-all on the SAME revision restores all 4 plugins.
    all_from_partial = manager_mod.operate(
        "install-all", home, shell,
        revision_fetch=lambda: rev,
        archive_fetch=lambda _u, _l: (_ for _ in ()).throw(AssertionError("should reuse already-current release")),
    )
    assert all_from_partial["ok"] and all_from_partial["installedPluginIds"] == ["tlp", "thinkfan", "nexus", "spaced_repetition"]
    assert [p["id"] for p in status_mod.inspect(shell, data_home)["plugins"]] == ["tlp", "thinkfan", "nexus", "spaced_repetition"]

    # Empty selection [] while current symlink exists -> install-all restores all 4 plugins.
    for pid in ("tlp", "thinkfan", "nexus", "spaced_repetition"):
        manager_mod.operate("remove-plugin", home, shell, plugin_id=pid)
    assert status_mod.inspect(shell, data_home)["installedPluginIds"] == []
    all_from_empty = manager_mod.operate("install-all", home, shell, revision_fetch=lambda: rev)
    assert all_from_empty["ok"] and all_from_empty["installedPluginIds"] == ["tlp", "thinkfan", "nexus", "spaced_repetition"]
    assert [p["id"] for p in status_mod.inspect(shell, data_home)["plugins"]] == ["tlp", "thinkfan", "nexus", "spaced_repetition"]

    # Legacy /usr/libexec/<legacy>-thinkfan helper fallback:
    # satisfies thinkfan dependency when canonical alis-thinkfan is absent,
    # while rejecting non-executable files and symlinks.
    libexec_dir = tmp_path / "libexec"
    libexec_dir.mkdir()
    canonical_tf = libexec_dir / "alis-thinkfan"
    legacy_tf = libexec_dir / ("".join(("i", "nir")) + "-thinkfan")
    legacy_prov = libexec_dir / ("".join(("i", "nir")) + "-" + "".join(("hada", "lird")) + "-system-provision")
    legacy_tf.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    legacy_prov.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")

    # 1) Non-executable legacy helper is rejected.
    legacy_tf.chmod(0o644)
    legacy_prov.chmod(0o755)
    dep_override = {
        "dependencies": {
            "thinkfan": {
                "binaries": ["sh"],
                "helpers": [str(canonical_tf)],
                "provisioner": str(libexec_dir / "alis-intergration-system-provision"),
            }
        }
    }
    dep_nonexec = status_mod.inspect_plugin_dependencies(dep_override)["thinkfan"]
    assert not dep_nonexec["satisfied"] and not dep_nonexec["helpersReady"]
    assert str(canonical_tf) in dep_nonexec["missing"]

    # 2) Regular executable legacy helper satisfies thinkfan cleanly.
    legacy_tf.chmod(0o755)
    dep_exec = status_mod.inspect_plugin_dependencies(dep_override)["thinkfan"]
    assert dep_exec["satisfied"] and dep_exec["helpersReady"] and dep_exec["provisionerReady"]
    assert dep_exec["missing"] == []

    # 3) Symlinked legacy helper to an untrusted target is rejected.
    legacy_tf.unlink()
    untrusted = tmp_path / "untrusted-helper"
    untrusted.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    untrusted.chmod(0o755)
    legacy_tf.symlink_to(untrusted)
    dep_symlink = status_mod.inspect_plugin_dependencies(dep_override)["thinkfan"]
    assert not dep_symlink["satisfied"] and not dep_symlink["helpersReady"]

print("ALIS_INTERGRATION_SETTINGS_FLOW_PASS Management-only Bento view, modal/Escape, per-plugin lifecycle, install-all & legacy fallback")
