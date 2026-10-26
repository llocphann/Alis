#!/usr/bin/env python3
"""Execute Arch package functions and hooks in private filesystem fixtures."""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
recipe = ROOT / "sdata/dist-arch/alis-deps/PKGBUILD"
arrays = {}
for field in ("depends", "optdepends"):
    result = subprocess.run(["bash", "-ec", 'source "$1"; name="$2"; declare -n values="$name"; printf "%s\\n" "${values[@]}"',
                             "fixture", str(recipe), field], text=True, capture_output=True, check=True)
    arrays[field] = result.stdout.splitlines()
for name in ("tlp", "tlp-pd", "tlp-rdw"):
    assert name not in arrays["depends"], name + " remains a mandatory core dependency"
    assert any(value.startswith(name + ":") for value in arrays["optdepends"]), name + " lost its optional package guidance"
with tempfile.TemporaryDirectory(prefix="alis-intergration-arch-") as name:
    base = Path(name)
    source = base / "src"
    source.mkdir()
    for dirname in ("alis", "Alis-fixture"):
        (source / dirname).symlink_to(ROOT, target_is_directory=True)
    binaries = source / "alis-native-target/release"
    binaries.mkdir(parents=True)
    for binary in ("alis-inputd", "alis-mpdd", "alis-native", "alis-theme"):
        (binaries / binary).write_text("#!/bin/sh\nexit 0\n")
    for family in ("alis-shell", "alis-shell-git"):
        stage = base / family
        recipe = ROOT / "distro/arch" / family / "PKGBUILD"
        env = dict(os.environ, srcdir=str(source), pkgdir=str(stage),
                   ALIS_SOURCE_DIR="Alis-fixture")
        result = subprocess.run(["bash", "-ec", 'source "$1"; package',
                                 "fixture", str(recipe)], env=env, cwd=base,
                                text=True, capture_output=True)
        assert result.returncode == 0, result.stdout + result.stderr
        for namespace in ("alis", "alis"):
            for path in (f"usr/libexec/{namespace}-battery-charge-limit", f"usr/libexec/{namespace}-thinkfan",
                         f"usr/share/{namespace}/tlp-settings-schema.json",
                         f"usr/share/polkit-1/actions/org.{namespace}.battery-charge-limit.policy",
                         f"usr/share/polkit-1/actions/org.{namespace}.thinkfan.policy"):
                assert not (stage / path).exists(), (family, path)
        assert (stage / "usr/bin/alis").is_file()
        assert (stage / "usr/lib/systemd/user/alis.service").is_file()
        assert (stage / "usr/share/quickshell/alis/services/AlisIntergration.qml").is_file()
        assert (stage / "usr/libexec/alis-intergration-system-provision").is_file()
        assert not (stage / "usr/bin/\x68\x61\x64\x61\x6c\x69\x73").exists()
        assert not (stage / "usr/lib/systemd/user/\x68\x61\x64\x61\x6c\x69\x73.service").exists()
        # Rewrite only absolute system roots into the private fixture. An old
        # destructive hook would execute this helper and remove these profiles.
        system = base / (family + "-system")
        marker = system / "mutated"
        # Old and canonical user hardware state both survive core removal.
        for namespace in ("alis", "alis"):
            helper = system / f"usr/libexec/{namespace}-battery-charge-limit"
            helper.parent.mkdir(parents=True, exist_ok=True)
            helper.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$MARKER"\n')
            helper.chmod(0o755)
        profiles = [system / "etc/tlp.d" / filename for filename in
                    ("99-alis-battery-charge-limit.conf", "99-alis-tlp-settings.conf",
                     "99-alis-battery-charge-limit.conf", "99-alis-tlp-settings.conf")]
        for profile in profiles:
            profile.parent.mkdir(parents=True, exist_ok=True)
            profile.write_text("preserve-owner-state\n")
        original = ROOT / "distro/arch" / family / (family + ".install")
        hook = base / (family + ".hook")
        hook.write_text(original.read_text().replace("/usr/libexec/", str(system) + "/usr/libexec/")
                        .replace("/etc/tlp.d/", str(system) + "/etc/tlp.d/"))
        result = subprocess.run(["bash", "-ec", 'source "$1"; pre_remove', "fixture", str(hook)],
                                env=dict(os.environ, MARKER=str(marker)), text=True, capture_output=True)
        assert result.returncode == 0, result.stderr
        assert not marker.exists(), family + " mutated optional hardware state"
        assert all(p.read_text() == "preserve-owner-state\n" for p in profiles)
print("ALIS_INTERGRATION_ARCH_PASS stable/git payloads omit privileged integrations; actual removal hooks preserve state")
