#!/usr/bin/env python3
"""Repo-copy Arch gateway bootstrap: no root, no downloaded installer, pinned bytes."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    "gateway_bootstrap", ROOT / "scripts/hadalird-system-package.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

# Two frozen files are exactly the reviewed Hadalis bytes. A runtime-local
# tamper or partial shell update fails closed before makepkg or Polkit.
trusted = module.expected_files(ROOT)
assert len(trusted) == 2
assert set(trusted) == {
    "usr/libexec/alis-hadalird-system-provision",
    "usr/share/polkit-1/actions/org.alis.hadalird-system-provision.policy",
}
assert "source=()" in module.PKGBUILD
assert "pkgname=alis-hadalird-gateway" in module.PKGBUILD
assert ".INSTALL" not in module.PKGBUILD
assert "$startdir/payload/" in module.PKGBUILD
assert "pacman" not in module.PKGBUILD
assert "curl" not in module.PKGBUILD

# Source package can have been committed by pacman -U even if a later
# status probe crashed; the reconciler must identify it without reinstallation.
with tempfile.TemporaryDirectory(prefix="hadalis-gateway-state-") as fixture:
    base = Path(fixture)
    assert not module.system_state(base, lambda _: False)["installed"]
    for destination, (content, _, _) in trusted.items():
        path = base / destination
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
    assert module.system_state(base, lambda _: True)["installed"]
    assert module.system_state(base, lambda _: True)["diagnostic"] == "ready"
    assert not module.system_state(base, lambda _: False)["installed"]
    first = base / next(iter(trusted))
    first.write_bytes(b"unexpected bytes")
    assert module.system_state(base, lambda _: True)["diagnostic"] == "modified"
    first.unlink()
    first.symlink_to(ROOT / next(iter(module.FILES)))
    assert module.system_state(base, lambda _: True)["diagnostic"] == "modified"

with tempfile.TemporaryDirectory(prefix="hadalis-legacy-gateway-state-") as legacy_fixture:
    legacy_base = Path(legacy_fixture)
    for dest, _ in module.LEGACY_FILES:
        src = Path("/" + dest)
        if src.is_file():
            target = legacy_base / dest
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(src.read_bytes())
    if all((legacy_base / dest).is_file() for dest, _ in module.LEGACY_FILES):
        legacy_state = module.system_state(legacy_base, lambda pkg: pkg == module.LEGACY_PACKAGE)
        assert legacy_state["installed"] and legacy_state["packageInstalled"]
        assert legacy_state["diagnostic"] == "ready"

with tempfile.TemporaryDirectory(prefix="hadalis-gateway-") as where:
    folder = Path(where)
    root = folder / "runtime"
    for name in module.FILES:
        p = root / name
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes((ROOT / name).read_bytes())
    assert module.expected_files(root) == trusted
    target = root / next(iter(module.FILES))
    target.write_bytes(b"not approved")
    try:
        module.expected_files(root)
        raise AssertionError("Modified root gateway source accepted")
    except ValueError:
        pass
    target.write_bytes((ROOT / next(iter(module.FILES))).read_bytes())
    target.unlink()
    target.symlink_to(ROOT / next(iter(module.FILES)))
    try:
        module.expected_files(root)
        raise AssertionError("Symlinked user-owned root gateway source accepted")
    except ValueError:
        pass
    target.unlink()
    target.write_bytes((ROOT / next(iter(module.FILES))).read_bytes())

    built = folder / "build"
    built.mkdir()
    seen = []

    def fake_command(command, *, cwd=None, timeout=0):
        seen.append(command)
        if command[0] == "/usr/bin/makepkg":
            assert cwd == built
            assert "pkgname=alis-hadalird-gateway" in (built / "PKGBUILD").read_text()
            for name, (dest, _, _) in module.FILES.items():
                assert (built / "payload" / Path(dest).name).read_bytes() == (ROOT / name).read_bytes()
            (built / "alis-hadalird-gateway-0.1.0-1-any.pkg.tar.zst").write_bytes(b"synthetic")
            return SimpleNamespace(returncode=0, stdout="", stderr="")
        if command[:2] == ["/usr/bin/bsdtar", "-tf"]:
            items = ".PKGINFO\n.BUILDINFO\n.MTREE\nusr/\nusr/libexec/\n"
            items += "usr/share/\nusr/share/polkit-1/\nusr/share/polkit-1/actions/\n"
            items += "\n".join(trusted) + "\n"
            return SimpleNamespace(returncode=0, stdout=items, stderr="")
        raise AssertionError("Unexpected process: " + repr(command))

    def extract(_, dest):
        return SimpleNamespace(returncode=0, stdout=trusted[dest][0])

    package = module.build_package(root, built, command=fake_command, extract=extract)
    assert package.exists() and len(seen) == 2

    def bad_extract(_, dest):
        return SimpleNamespace(returncode=0, stdout=b"tampered")

    with tempfile.TemporaryDirectory(prefix="hadalis-bad-gateway-") as other:
        path = Path(other)
        # The synthetic makepkg command writes to its current build folder.
        def fake_bad(command, *, cwd=None, timeout=0):
            if command[0] == "/usr/bin/makepkg":
                (cwd / "alis-hadalird-gateway-0.1.0-1-any.pkg.tar.zst").write_bytes(b"synthetic")
            return fake_command(command, cwd=cwd, timeout=timeout) if command[0] != "/usr/bin/makepkg" else SimpleNamespace(returncode=0, stdout="", stderr="")
        try:
            module.build_package(root, path, command=fake_bad, extract=bad_extract)
            raise AssertionError("Modified built package accepted")
        except ValueError:
            pass

    # Never call pkexec or pacman -U in a regression fixture: system state
    # is qualified only on an owner machine after explicit UI consent.
    assert not any("/usr/bin/pkexec" in argv for argv in seen)
    assert not any("pacman" in " ".join(argv) for argv in seen)

print("HADALIRD_ARCH_GATEWAY_BOOTSTRAP_PASS pinned payload, no elevated build, package inspection, tamper refusal")
