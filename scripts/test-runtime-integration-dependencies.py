#!/usr/bin/env python3
"""Static contract for CAVA, Weather and ThinkFan runtime dependencies."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
failures: list[str] = []


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def require(text: str, token: str, source: str) -> None:
    if token not in text:
        failures.append(f"{source} missing dependency contract token: {token!r}")


def forbid(text: str, token: str, source: str) -> None:
    if token in text:
        failures.append(f"{source} must not hard-require optional capability: {token!r}")


def main() -> None:
    cava = read("services/deferred/CavaService.qml")
    weather = read("services/Weather.qml")
    doctor = read("sdata/lib/doctor.sh")
    generic = read("sdata/dist-generic/install-deps.sh")
    debian = read("sdata/dist-debian/install-deps.sh")
    fedora = read("sdata/dist-fedora/install-deps.sh")
    nix = read("nix/package.nix")
    arch = read("distro/arch/alis-shell/PKGBUILD")
    arch_git = read("distro/arch/alis-shell-git/PKGBUILD")
    thinkfan_docs = read("docs/THINKFAN.md")

    # CAVA is a real process dependency of the shared visualizer service.
    require(cava, '"/cava/run.sh"', "CavaService.qml")
    require(cava, 'command: ["/usr/bin/bash", root.runnerPath, "-p", root.configPath]', "CavaService.qml")
    require(read("scripts/cava/run.sh"), 'exec cava "$@"', "CAVA process wrapper")
    require(doctor, '"cava:cava"', "doctor.sh")
    require(generic, 'check_cmd "cava" "CAVA audio visualizer"', "generic installer")
    require(generic, "pipewire, pipewire-pulse, wireplumber, playerctl, pavucontrol, cava",
            "generic installer")
    require(debian, "DEBIAN_AUDIO_PKGS+=(cava)", "Debian installer")
    require(debian, "if ! command -v cava &>/dev/null; then", "Debian installer")
    require(fedora, "  cava", "Fedora installer")
    require(nix, '++ optionalTop "cava"', "Nix package")
    for source, text in (("alis-shell", arch), ("alis-shell-git", arch_git)):
        require(text, "'cava: audio visualizer'", source)

    # Weather hard-requires curl. GPS via Geoclue/where-am-i is optional because
    # the service falls back to IP location providers.
    require(weather, 'command: ["/usr/bin/curl"', "Weather.qml")
    require(weather, "where-am-i -t 10", "Weather.qml")
    require(weather, "http://ip-api.com/json/", "Weather.qml")
    require(weather, "https://ipwho.is/", "Weather.qml")
    require(doctor, '"curl:curl"', "doctor.sh")
    require(generic, 'check_cmd "curl" "curl"', "generic installer")
    require(debian, "  curl", "Debian installer")
    require(debian, "  geoclue-2.0", "Debian installer")
    require(fedora, "  curl", "Fedora installer")
    require(fedora, "  geoclue2", "Fedora installer")
    require(nix, "      curl", "Nix package")
    require(nix, '++ optionalTop "geoclue2"', "Nix package")
    for source, text in (("alis-shell", arch), ("alis-shell-git", arch_git)):
        require(text, "  curl", source)
        require(text, "'geoclue: GPS-backed weather location detection'", source)

    # Physical ThinkFan capability guards are owned/tested in optional Hadalird.
    forbid(doctor, '"thinkfan:thinkfan"', "doctor.sh")
    for source, text in (("alis-shell", arch), ("alis-shell-git", arch_git)):
        require(text, "'thinkfan: managed fan-control integration'", source)

    for token in (
        "This integration is optional",
        "the `thinkfan` executable",
        "a system `thinkfan.service` visible to `systemctl`",
        "a valid ThinkFan configuration",
        "ThinkFan configuration is hardware-specific",
        "does not invent fan curves or sensor mappings automatically",
        "The current Nix package does not provision these privileged system-level files",
    ):
        require(thinkfan_docs, token, "THINKFAN.md")

    if failures:
        print("Runtime integration dependency contract regression(s):")
        for failure in failures:
            print(f"  - {failure}")
        raise SystemExit(1)

    print("Runtime integration dependency contract: OK")


if __name__ == "__main__":
    main()
