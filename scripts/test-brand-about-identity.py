#!/usr/bin/env python3
"""BRAND-R01: verify Alis About identity, avatar, and truthful upstream credits."""
from pathlib import Path

root = Path(__file__).resolve().parent.parent
material = (root / "modules/settings/About.qml").read_text()
waffle = (root / "modules/waffle/settings/pages/WAboutPage.qml").read_text()
image = root / "assets/icons/alis-owner-avatar.jpg"
avatar = image.read_bytes()
assert len(avatar) > 1500 and avatar[:3] == b"\\xff\\xd8\\xff" and avatar[-2:] == b"\\xff\\xd9", "Avatar JPEG missing/corrupt"
for name, source in (("Material", material), ("Waffle", waffle)):
    assert 'assets/icons/alis-owner-avatar.jpg' in source, f"{name} is not using repo avatar"
    assert "https://github.com/llocphann/Alis" in source, f"{name} lost primary Alis repository"
    assert "https://github.com/snowarch/iNiR" in source, f"{name} lost iNiR credit"
    assert "https://github.com/end-4/dots-hyprland" in source, f"{name} lost illogical-impulse credit"
    assert source.index("Alis") < source.index("Based on"), f"{name} promotes upstream over Alis"
    section = source[source.index("Based on"):]
    assert section.find("iNiR") >= 0 and section.find("illogical-impulse") >= 0, f"{name} missing paired credits"
    assert source.count("assets/icons/alis-owner-avatar.jpg") == 1, f"{name} duplicated avatar resources"
assert 'text: "Alis"' in material and 'title: "Alis"' in material
assert 'text: "Alis"' in waffle
assert 'source: Quickshell.shellPath("assets/icons/sf.jpg")' not in material
assert 'label: Translation.tr("Original Project (end-4)")' not in waffle
assert (root / "assets/systemd/inir.service").is_file(), "compatibility unit removed"
assert '//@ pragma ShellId inir' in (root / "shell.qml").read_text(), "runtime identity changed"
print("PASS: Material/Waffle Alis About + embedded owner avatar + both original-project credits")
