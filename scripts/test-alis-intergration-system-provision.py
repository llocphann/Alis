#!/usr/bin/env python3
"""Offline ownership and Polkit security regression for the Alis root gateway."""
import hashlib
import json
from pathlib import Path
import tempfile
import types
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
gateway = ROOT / "assets/helpers/alis-intergration-system-provision"
policy = ROOT / "assets/polkit/org.alis.intergration-system-provision.policy"
mod = types.ModuleType("system_gateway_contract")
exec(compile(gateway.read_text(), str(gateway), "exec"), mod.__dict__)

doc = ET.parse(policy).getroot()
action = doc.find(".//action")
assert action is not None and action.attrib["id"] == "org.alis.intergration-system-provision"
assert action.find("./defaults/allow_any").text == "no"
assert action.find("./defaults/allow_inactive").text == "no"
assert action.find("./defaults/allow_active").text == "auth_admin"
assert action.find(".//annotate[@key='org.freedesktop.policykit.exec.path']").text == "/usr/libexec/alis-intergration-system-provision"

with tempfile.TemporaryDirectory(prefix="alis-intergration-gateway-fixture-") as tmp:
    base = Path(tmp)
    root = base / "root"
    package = base / "package"
    package.mkdir()
    original = mod.TRUSTED.copy()
    # Synthetic trusted contents let this fixture exercise exactly the same
    # fixed-digest logic without using real TLP scripts or root privileges.
    payload = {path: ("fixed fixture: " + path).encode() for path in original}
    mod.TRUSTED = {path: (dst, hashlib.sha256(payload[path]).hexdigest(), mode)
                   for path, (dst, _, mode) in original.items()}
    for name, value in payload.items():
        target = package / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(value)
    manifest = {"id": "alis-intergration", "hostApi": 1, "files":
                {p: hashlib.sha256(v).hexdigest() for p, v in payload.items()}}
    (package / "manifest.json").write_text(json.dumps(manifest))
    assert mod.state(root)["diagnostic"] == "not-installed"
    assert mod.install(package, root)["installed"]
    assert mod.install(package, root)["installed"]  # idempotent
    for name, (dst, _, mode) in mod.TRUSTED.items():
        output = mod.destination(root, dst)
        assert output.read_bytes() == payload[name]
        assert output.stat().st_mode & 0o777 == mode
    state_path = mod.destination(root, mod.STATE)
    assert state_path.exists()

    # A tampered user-owned helper must never be copied to a root location.
    first = next(iter(mod.TRUSTED))
    (package / first).write_bytes(b"modified")
    try:
        mod.install(package, root)
        raise AssertionError("Tampered package accepted")
    except ValueError:
        pass
    (package / first).write_bytes(payload[first])

    # Do not delete modified system files on removal or clobber unrelated
    # administrators' state. Fail closed until the user resolves the conflict.
    target = mod.destination(root, mod.TRUSTED[first][0])
    target.write_bytes(b"owner-modified")
    try:
        mod.remove(root)
        raise AssertionError("Modified system file removed")
    except ValueError:
        pass
    assert target.read_bytes() == b"owner-modified" and state_path.exists()
    target.write_bytes(payload[first])

    assert not mod.remove(root)["installed"]
    assert all(not mod.destination(root, spec[0]).exists() for spec in mod.TRUSTED.values())
    assert not state_path.exists()
    foreign = mod.destination(root, mod.TRUSTED[first][0])
    foreign.parent.mkdir(parents=True, exist_ok=True)
    foreign.write_bytes(b"unrelated administrator helper")
    try:
        mod.install(package, root)
        raise AssertionError("Foreign helper overwritten")
    except ValueError:
        pass
    assert foreign.read_bytes() == b"unrelated administrator helper"
    foreign.unlink()
    foreign.symlink_to(package / first)
    try:
        mod.install(package, root)
        raise AssertionError("Symlinked root destination accepted")
    except ValueError:
        pass
    foreign.unlink()
    target = package / first
    target.unlink()
    target.symlink_to(package / next(x for x in mod.TRUSTED if x != first))
    try:
        mod.install(package, root)
        raise AssertionError("Symlinked untrusted source accepted")
    except (OSError, ValueError):
        pass
    target.unlink()
    target.write_bytes(payload[first])

    # Independent per-plugin helper scope ('tlp' vs 'thinkfan'):
    # installing/removing one scope must leave the sibling helper undisturbed.
    assert mod.state(root, scope="all")["diagnostic"] == "not-installed"
    tlp_res = mod.install(package, root, scope="tlp")
    assert tlp_res["installed"] and tlp_res["scope"] == "tlp"
    assert mod.state(root, scope="tlp")["installed"] is True
    assert mod.state(root, scope="thinkfan")["installed"] is False
    assert mod.state(root, scope="all")["installed"] is False
    assert mod.state(root, scope="all")["plugins"]["tlp"]["installed"] is True
    assert mod.state(root, scope="all")["plugins"]["thinkfan"]["installed"] is False
    assert not mod.destination(root, mod.TRUSTED["plugins/thinkfan/assets/helpers/alis-thinkfan"][0]).exists()

    tf_res = mod.install(package, root, scope="thinkfan")
    assert tf_res["installed"] and mod.state(root, scope="all")["installed"] is True

    rem_tlp = mod.remove(root, scope="tlp")
    assert rem_tlp["scope"] == "tlp" and not mod.state(root, scope="tlp")["installed"]
    assert mod.state(root, scope="thinkfan")["installed"] is True
    assert not mod.destination(root, mod.TRUSTED["plugins/tlp/assets/helpers/alis-battery-charge-limit"][0]).exists()
    assert mod.destination(root, mod.TRUSTED["plugins/thinkfan/assets/helpers/alis-thinkfan"][0]).exists()
    assert state_path.exists()
    rem_tf = mod.remove(root, scope="thinkfan")
    assert not mod.state(root, scope="all")["managed"] and not state_path.exists()

for name in ("alis-shell", "alis-shell-git"):
    recipe = (ROOT / "distro/arch" / name / "PKGBUILD").read_text()
    assert "/usr/libexec/alis-intergration-system-provision" in recipe
    assert "org.alis.intergration-system-provision.policy" in recipe

# A valid *recipe* does not guarantee that the default source snapshot
# actually matches its declared metadata.
stable = (ROOT / 'distro/arch/alis-shell/PKGBUILD').read_text()
source_line = next((line for line in stable.splitlines()
                    if line.startswith('_source_ref=')), '')
source_prefix = '_source_ref="${ALIS_SOURCE_REF:-'
assert source_line.startswith(source_prefix) and source_line.endswith('}"'), (
    'Arch snapshot must pin a default source ref')
source_ref = source_line[len(source_prefix):-2]
is_sha = len(source_ref) == 40 and all(c in '0123456789abcdef' for c in source_ref)
assert is_sha or source_ref in ('dev', 'main'), f'unexpected _source_ref: {source_ref}'
assert source_ref != '8ca68efe423223bdf40059155748c53b38200de2', (
    'pre-gateway source snapshot cannot install the Polkit provisioner')
srcinfo = (ROOT / 'distro/arch/alis-shell/.SRCINFO').read_text()
assert f'/archive/{source_ref}.tar.gz' in srcinfo, (
    'Arch source metadata must match the configured source archive')
print('ALIS_INTERGRATION_SYSTEM_PROVISION_PASS root ownership, Polkit policy, byte pins, source snapshot')
