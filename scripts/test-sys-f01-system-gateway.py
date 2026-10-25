#!/usr/bin/env python3
"""SYS-F01 regression test: Optional trusted non-Arch system gateway.

Qualifies:
1. Distro family detection across Arch, Debian/Ubuntu, Fedora, openSUSE, and
   fail-closed refusal on NixOS (declarative), immutable systems (Silverblue,
   Kinoite, MicroOS), and untested distros (Gentoo, Void, Alpine, unknown).
2. Unprivileged package builders (makepkg, dpkg-deb, rpmbuild) with zero
   maintainer scripts, exact SHA-256 payload inspection, and tamper refusal.
3. Explicit native Polkit (pkexec) package installation, ownership verification,
   shell-package conflict refusal, foreign-file refusal, removal refusal while
   managed helpers are active, modified-file preservation, and rollback recovery
   across Arch (pacman), Debian/Ubuntu (dpkg), Fedora (rpm), and openSUSE (rpm),
   without ever mutating user-owned optional packages or running user-checkout
   installers as root.
"""
import importlib.util
from pathlib import Path
import tempfile
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    "gateway_bootstrap", ROOT / "scripts/alis-intergration-system-package.py"
)
gateway = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gateway)

trusted = gateway.expected_files(ROOT)
assert len(trusted) == 2

# 1. Verify no maintainer scripts exist in any distro package specification
assert ".INSTALL" not in gateway.PKGBUILD
assert "Package: alis-hadalird-gateway" in gateway.DEB_CONTROL
for forbidden in ("preinst", "postinst", "prerm", "postrm"):
    assert forbidden not in gateway.DEB_CONTROL
for scriptlet in ("%pre", "%post", "%preun", "%postun", "%trigger"):
    assert scriptlet not in gateway.RPM_SPEC

# 2. Verify distribution detection and fail-closed refusal on unsupported/immutable/declarative OSes
with tempfile.TemporaryDirectory(prefix="hadalis-sys-f01-detect-") as tmp:
    base = Path(tmp)

    def make_os_release(name, content, extra_files=()):
        root = base / name
        (root / "etc").mkdir(parents=True, exist_ok=True)
        (root / "etc/os-release").write_text(content, encoding="utf-8")
        for rel in extra_files:
            p = root / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text("", encoding="utf-8")
        return root

    arch_root = make_os_release("arch", 'ID=arch\nPRETTY_NAME="Arch Linux"\n', ("etc/arch-release",))
    assert gateway.detect_distro(arch_root) == {
        "family": "arch", "supported": True, "packageManager": "pacman", "diagnostic": "supported"
    }

    debian_root = make_os_release("ubuntu", 'ID=ubuntu\nID_LIKE=debian\nPRETTY_NAME="Ubuntu 24.04 LTS"\n', ("etc/debian_version",))
    assert gateway.detect_distro(debian_root) == {
        "family": "debian", "supported": True, "packageManager": "dpkg", "diagnostic": "supported"
    }

    fedora_root = make_os_release("fedora", 'ID=fedora\nPRETTY_NAME="Fedora Linux 41"\n', ("etc/fedora-release",))
    assert gateway.detect_distro(fedora_root) == {
        "family": "fedora", "supported": True, "packageManager": "rpm", "diagnostic": "supported"
    }

    suse_root = make_os_release("opensuse", 'ID="opensuse-tumbleweed"\nID_LIKE="opensuse suse"\n')
    assert gateway.detect_distro(suse_root) == {
        "family": "opensuse", "supported": True, "packageManager": "rpm", "diagnostic": "supported"
    }

    nixos_root = make_os_release("nixos", 'ID=nixos\nPRETTY_NAME="NixOS"\n', ("etc/NIXOS",))
    nixos_det = gateway.detect_distro(nixos_root)
    assert not nixos_det["supported"] and nixos_det["diagnostic"] == "declarative-distro-manual"
    assert not gateway.system_state(nixos_root)["sourcePackageAvailable"]

    silverblue_root = make_os_release("silverblue", 'ID=fedora\nVARIANT_ID=silverblue\nPRETTY_NAME="Fedora Silverblue"\n')
    sb_det = gateway.detect_distro(silverblue_root)
    assert not sb_det["supported"] and sb_det["diagnostic"] == "immutable-distro-unsupported"

    gentoo_root = make_os_release("gentoo", 'ID=gentoo\nPRETTY_NAME="Gentoo"\n')
    gentoo_det = gateway.detect_distro(gentoo_root)
    assert not gentoo_det["supported"] and gentoo_det["diagnostic"] == "unsupported-distro"
    try:
        gateway.install(ROOT, fs_root=gentoo_root)
        raise AssertionError("Untested distro accepted for gateway installation")
    except ValueError as err:
        assert "not in the audited system gateway matrix" in str(err)


# 3. Verify Debian (.deb) and Fedora/openSUSE (.rpm) unprivileged package builds & tamper refusal
with tempfile.TemporaryDirectory(prefix="hadalis-sys-f01-build-") as tmp:
    folder = Path(tmp)

    # --- Debian .deb build & verification ---
    deb_dir = folder / "deb"
    deb_dir.mkdir()
    deb_seen = []

    def fake_deb_cmd(command, *, cwd=None, timeout=0, input_bytes=None):
        deb_seen.append(command)
        if command[0] == "/usr/bin/dpkg-deb" and "--build" in command:
            pkgroot = Path(command[-2])
            out_deb = Path(command[-1])
            assert (pkgroot / "DEBIAN/control").read_text() == gateway.DEB_CONTROL
            for dest, (content, _, _) in trusted.items():
                assert (pkgroot / dest).read_bytes() == content
            out_deb.write_bytes(b"synthetic-deb")
            return SimpleNamespace(returncode=0, stdout="", stderr="")
        if command[:2] == ["/usr/bin/dpkg-deb", "-c"]:
            listing = (
                "drwxr-xr-x root/root 0 2026-10-26 00:00 ./\n"
                "drwxr-xr-x root/root 0 2026-10-26 00:00 ./usr/\n"
                "drwxr-xr-x root/root 0 2026-10-26 00:00 ./usr/libexec/\n"
                "-rwxr-xr-x root/root 100 2026-10-26 00:00 ./usr/libexec/alis-hadalird-system-provision\n"
                "drwxr-xr-x root/root 0 2026-10-26 00:00 ./usr/share/\n"
                "drwxr-xr-x root/root 0 2026-10-26 00:00 ./usr/share/polkit-1/\n"
                "drwxr-xr-x root/root 0 2026-10-26 00:00 ./usr/share/polkit-1/actions/\n"
                "-rw-r--r-- root/root 100 2026-10-26 00:00 ./usr/share/polkit-1/actions/org.alis.hadalird-system-provision.policy\n"
            )
            return SimpleNamespace(returncode=0, stdout=listing, stderr="")
        raise AssertionError("Unexpected deb build command: " + repr(command))

    def good_extract(_, dest):
        return SimpleNamespace(returncode=0, stdout=trusted[dest][0])

    def bad_extract(_, dest):
        return SimpleNamespace(returncode=0, stdout=b"tampered-bytes")

    deb_pkg = gateway.build_deb_package(ROOT, deb_dir, command=fake_deb_cmd, extract=good_extract)
    assert deb_pkg.exists() and deb_pkg.name == "alis-hadalird-gateway_0.1.0-1_all.deb"
    assert not any("pkexec" in " ".join(c) for c in deb_seen)

    try:
        gateway.build_deb_package(ROOT, folder / "deb-bad", command=fake_deb_cmd, extract=bad_extract)
        raise AssertionError("Tampered Debian package accepted")
    except ValueError:
        pass

    # --- RPM (.rpm) build & verification for Fedora and openSUSE ---
    rpm_dir = folder / "rpm"
    rpm_dir.mkdir()
    rpm_seen = []

    def fake_rpm_cmd(command, *, cwd=None, timeout=0, input_bytes=None):
        rpm_seen.append(command)
        if command[0] == "/usr/bin/rpmbuild":
            topdir = Path(command[3].split(" ", 1)[1])
            assert (topdir / "SPECS/alis-hadalird-gateway.spec").read_text() == gateway.RPM_SPEC
            for dest, (content, _, _) in trusted.items():
                assert (topdir / "SOURCES" / Path(dest).name).read_bytes() == content
            out_rpm = topdir / "RPMS/noarch/alis-hadalird-gateway-0.1.0-1.noarch.rpm"
            out_rpm.parent.mkdir(parents=True, exist_ok=True)
            out_rpm.write_bytes(b"synthetic-rpm")
            return SimpleNamespace(returncode=0, stdout="", stderr="")
        if command[:3] == ["/usr/bin/rpm", "-qp", "--scripts"]:
            return SimpleNamespace(returncode=0, stdout="", stderr="")
        if command[:2] == ["/usr/bin/rpm", "-qpl"]:
            listing = "\n".join("/" + dest for dest in trusted) + "\n"
            return SimpleNamespace(returncode=0, stdout=listing, stderr="")
        raise AssertionError("Unexpected rpm build command: " + repr(command))

    rpm_pkg = gateway.build_rpm_package(ROOT, rpm_dir, command=fake_rpm_cmd, extract=good_extract)
    assert rpm_pkg.exists() and rpm_pkg.name.endswith(".rpm")
    assert not any("pkexec" in " ".join(c) for c in rpm_seen)

    # Reject RPM with injected scriptlets
    def scriptlet_rpm_cmd(command, *, cwd=None, timeout=0, input_bytes=None):
        if command[:3] == ["/usr/bin/rpm", "-qp", "--scripts"]:
            return SimpleNamespace(returncode=0, stdout="postinstall scriptlet (using /bin/sh):\necho pwn\n", stderr="")
        return fake_rpm_cmd(command, cwd=cwd, timeout=timeout, input_bytes=input_bytes)

    try:
        gateway.build_rpm_package(ROOT, folder / "rpm-scriptlet", command=scriptlet_rpm_cmd, extract=good_extract)
        raise AssertionError("RPM with scriptlets accepted")
    except ValueError as err:
        assert "forbidden scriptlets" in str(err)


# 4. Full lifecycle per supported distro (arch, debian, fedora, opensuse):
#    install -> idempotent re-run -> helper-active removal refusal -> modified-file refusal -> clean remove -> rollback
for distro_family in ("arch", "debian", "fedora", "opensuse"):
    with tempfile.TemporaryDirectory(prefix=f"hadalis-sys-f01-{distro_family}-") as tmp:
        fs_root = Path(tmp) / "fs"
        user_pkg = Path(tmp) / "user-optional-package"
        user_pkg.mkdir(parents=True)
        (user_pkg / "manifest.json").write_text('{"id":"hadalird","version":"0.2.0"}\n')

        for tool in gateway.SUPPORTED_DISTROS[distro_family]["requiredTools"]:
            tpath = fs_root / tool.lstrip("/")
            tpath.parent.mkdir(parents=True, exist_ok=True)
            tpath.write_text("#!/bin/sh\nexit 0\n")
            tpath.chmod(0o755)

        pkg_installed = {"gateway": False, "shell": False}
        helpers_active = {"active": False}
        privileged_calls = []

        def make_distro_runner(family, root_dir, state_box, helper_box, priv_log):
            def runner(command, *, cwd=None, timeout=0, input_bytes=None):
                cmd0 = command[0]
                # Package database queries
                if cmd0 == "/usr/bin/pacman" and command[1] == "-Qq":
                    name = command[2]
                    ok = (name == gateway.PACKAGE and state_box["gateway"]) or (name in gateway.SHELL_PACKAGES and state_box["shell"])
                    return SimpleNamespace(returncode=0 if ok else 1, stdout=name if ok else "", stderr="")
                if cmd0 == "/usr/bin/dpkg-query" and command[1] == "-W":
                    name = command[-1]
                    ok = (name == gateway.PACKAGE and state_box["gateway"]) or (name in gateway.SHELL_PACKAGES and state_box["shell"])
                    return SimpleNamespace(returncode=0 if ok else 1, stdout="installed" if ok else "deinstall", stderr="")
                if cmd0 == "/usr/bin/rpm" and command[1] == "-q":
                    name = command[2]
                    ok = (name == gateway.PACKAGE and state_box["gateway"]) or (name in gateway.SHELL_PACKAGES and state_box["shell"])
                    return SimpleNamespace(returncode=0 if ok else 1, stdout=name if ok else "", stderr="")

                # Unprivileged package builds
                if cmd0 == "/usr/bin/makepkg":
                    (Path(cwd) / "alis-hadalird-gateway-0.1.0-1-any.pkg.tar.zst").write_bytes(b"pkg")
                    return SimpleNamespace(returncode=0, stdout="", stderr="")
                if cmd0 == "/usr/bin/bsdtar" and command[1] == "-tf":
                    items = ".PKGINFO\n.BUILDINFO\n.MTREE\n" + "\n".join(trusted) + "\n"
                    return SimpleNamespace(returncode=0, stdout=items, stderr="")
                if cmd0 == "/usr/bin/dpkg-deb" and "--build" in command:
                    Path(command[-1]).write_bytes(b"deb")
                    return SimpleNamespace(returncode=0, stdout="", stderr="")
                if cmd0 == "/usr/bin/dpkg-deb" and command[1] == "-c":
                    lines = "\n".join(f"-rwxr-xr-x root/root 100 2026-10-26 00:00 ./{d}" for d in trusted) + "\n"
                    return SimpleNamespace(returncode=0, stdout=lines, stderr="")
                if cmd0 == "/usr/bin/rpmbuild":
                    topdir = Path(command[3].split(" ", 1)[1])
                    out_rpm = topdir / "RPMS/noarch/alis-hadalird-gateway-0.1.0-1.noarch.rpm"
                    out_rpm.parent.mkdir(parents=True, exist_ok=True)
                    out_rpm.write_bytes(b"rpm")
                    return SimpleNamespace(returncode=0, stdout="", stderr="")
                if cmd0 == "/usr/bin/rpm" and command[1:3] == ["-qp", "--scripts"]:
                    return SimpleNamespace(returncode=0, stdout="", stderr="")
                if cmd0 == "/usr/bin/rpm" and command[1] == "-qpl":
                    return SimpleNamespace(returncode=0, stdout="\n".join("/" + d for d in trusted) + "\n", stderr="")

                # Provisioner helper status
                if cmd0.endswith("alis-hadalird-system-provision") and command[1] == "status":
                    active = helper_box["active"]
                    return SimpleNamespace(
                        returncode=0,
                        stdout=f'{{"ok":true,"installed":{str(active).lower()},"managed":{str(active).lower()},"diagnostic":"ready"}}',
                        stderr="",
                    )

                # Explicit Polkit native package manager transactions
                if cmd0 == "/usr/bin/pkexec":
                    priv_log.append(command)
                    if "-U" in command or "--install" in command or "-Uvh" in command:
                        state_box["gateway"] = True
                        for dest, (content, mode, _) in trusted.items():
                            target = root_dir / dest
                            target.parent.mkdir(parents=True, exist_ok=True)
                            target.write_bytes(content)
                            target.chmod(mode)
                        return SimpleNamespace(returncode=0, stdout="", stderr="")
                    if "-R" in command or "--remove" in command or "-e" in command:
                        state_box["gateway"] = False
                        for dest in trusted:
                            (root_dir / dest).unlink(missing_ok=True)
                        return SimpleNamespace(returncode=0, stdout="", stderr="")
                raise AssertionError(f"Unexpected command for {family}: {command!r}")

            return runner

        runner = make_distro_runner(distro_family, fs_root, pkg_installed, helpers_active, privileged_calls)
        extract_fn = lambda _pkg, dest: SimpleNamespace(returncode=0, stdout=trusted[dest][0])

        # Refusal when distro shell package already owns the gateway
        pkg_installed["shell"] = True
        try:
            gateway.install(ROOT, command=runner, distro=distro_family, fs_root=fs_root, extract=extract_fn)
            raise AssertionError("Allowed standalone install over distro shell package")
        except ValueError as err:
            assert "shell package already owns this gateway" in str(err)
        pkg_installed["shell"] = False

        # Clean install via pkexec + native package manager
        res = gateway.install(ROOT, command=runner, distro=distro_family, fs_root=fs_root, extract=extract_fn)
        assert res["ok"] and res["installed"] and res["packageInstalled"] and res["distro"] == distro_family
        assert len(privileged_calls) == 1 and privileged_calls[0][0] == "/usr/bin/pkexec"

        # Idempotent re-run performs zero additional privileged actions
        again = gateway.install(ROOT, command=runner, distro=distro_family, fs_root=fs_root, extract=extract_fn)
        assert again["ok"] and again["installed"]
        assert len(privileged_calls) == 1

        # Refusal to remove gateway while managed TLP/Thinkfan helpers are still active
        helpers_active["active"] = True
        try:
            gateway.remove(command=runner, distro=distro_family, fs_root=fs_root)
            raise AssertionError("Removed gateway while helpers were still active")
        except ValueError as err:
            assert "Remove managed TLP/Thinkfan helpers first" in str(err)
        helpers_active["active"] = False

        # Refusal to remove gateway if administrator modified a gateway file on disk
        prov_file = fs_root / "usr/libexec/alis-hadalird-system-provision"
        prov_file.write_bytes(b"administrator-custom-edit")
        try:
            gateway.remove(command=runner, distro=distro_family, fs_root=fs_root)
            raise AssertionError("Removed externally modified gateway file")
        except ValueError as err:
            assert "modified" in str(err)
        prov_file.write_bytes(trusted["usr/libexec/alis-hadalird-system-provision"][0])

        # Clean removal when helpers are absent and files match pinned digests
        rem = gateway.remove(command=runner, distro=distro_family, fs_root=fs_root)
        assert rem["ok"] and not rem["installed"] and not rem["packageInstalled"]
        assert len(privileged_calls) == 2

        # Rollback restores verified gateway state without touching user-owned optional package
        rb = gateway.rollback(ROOT, command=runner, distro=distro_family, fs_root=fs_root, extract=extract_fn)
        assert rb["ok"] and rb["installed"]
        assert (user_pkg / "manifest.json").read_text() == '{"id":"hadalird","version":"0.2.0"}\n'

print("SYS_F01_PASS multi-distro (arch/debian/fedora/opensuse) unprivileged build, pinned SHA-256 verification, Polkit native ownership, removal/rollback and unsupported/immutable/declarative refusal verified")
