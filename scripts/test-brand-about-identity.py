#!/usr/bin/env python3
"""BRAND-R01: verify Alis About identity, avatar, and truthful upstream credits."""
from pathlib import Path

root = Path(__file__).resolve().parent.parent
material = (root / "modules/settings/About.qml").read_text()
waffle = (root / "modules/waffle/settings/pages/WAboutPage.qml").read_text()
image = root / "assets/icons/alis-owner-avatar.jpg"
avatar = image.read_bytes()
assert len(avatar) > 1500 and avatar[:3] == bytes((0xff, 0xd8, 0xff)) and avatar[-2:] == bytes((0xff, 0xd9)), "Avatar JPEG missing/corrupt"
for name, source in (("Material", material), ("Waffle", waffle)):
    assert 'assets/icons/alis-owner-avatar.jpg' in source, f"{name} is not using repo avatar"
    assert "https://github.com/llocphann/Alis" in source, f"{name} lost primary Alis repository"
    assert "https://github.com/llocphann/Alis-Companion" in source, f"{name} missing Alis-Companion repository"
    assert "https://github.com/llocphann/Alis-Intergration" in source, f"{name} missing Alis-Intergration repository"
    assert "https://github.com/snowarch/Alis" in source, f"{name} lost Alis credit"
    assert "https://github.com/end-4/dots-hyprland" in source, f"{name} lost illogical-impulse credit"
    assert source.index("Alis") < source.index("Based on"), f"{name} promotes upstream over Alis"
    section = source[source.index("Based on"):]
    assert section.find("Alis") >= 0 and section.find("illogical-impulse") >= 0, f"{name} missing paired credits"
    assert source.count("assets/icons/alis-owner-avatar.jpg") == 1, f"{name} duplicated avatar resources"
assert 'aboutBasedOnHorizontalRow' in material, "Material Based on section must arrange credits horizontally"
assert 'text: "Alis"' in material and 'title: "Alis"' in material
assert 'text: "Alis"' in waffle
assert 'source: Quickshell.shellPath("assets/icons/sf.jpg")' not in material
assert 'label: Translation.tr("Original Project (end-4)")' not in waffle
# Test the actual identity of the checked-out branch without weakening either
# service contract. Canonical must NOT ship the old installable session unit.
shell = (root / "shell.qml").read_text()
canonical = '//@ pragma ShellId alis' in shell
compatible = '//@ pragma ShellId alis' in shell
assert canonical != compatible, "ambiguous/missing ShellId"
if canonical:
    assert (root / "assets/systemd/alis.service").is_file(), "canonical unit missing"
    assert not (root / "assets/systemd/alis.service").exists(), "duplicate legacy unit in canonical runtime"
else:
    assert (root / "assets/systemd/alis.service").is_file(), "compatibility unit removed"
    assert not (root / "assets/systemd/alis.service").exists(), "duplicate Alis service in compatibility runtime"
print("PASS: Material/Waffle Alis About + embedded owner avatar + both original-project credits")
