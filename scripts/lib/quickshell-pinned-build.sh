#!/usr/bin/env bash
# Build and install a commit/tag-pinned Quickshell runtime against the host's
# current Qt6 libraries. Never pulls unpinned upstream master/quickshell-git.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

ALIS_QUICKSHELL_VERSION="${ALIS_QUICKSHELL_VERSION:-0.3.2}"
ALIS_QUICKSHELL_REF="${ALIS_QUICKSHELL_REF:-v0.3.2}"
ALIS_QUICKSHELL_URL="${ALIS_QUICKSHELL_URL:-https://git.outfoxxed.me/quickshell/quickshell.git}"
PATCH_DIR="$ROOT_DIR/patches/quickshell"

mode="arch-pkg"
dry_run=0
noconfirm=0
local_prefix="${ALIS_QUICKSHELL_PREFIX:-$HOME/.local/share/alis/quickshell-runtime}"

usage() {
    cat <<'EOF'
Usage: quickshell-pinned-build.sh [--print-pin] [--arch-pkg] [--local-prefix [DIR]] [--dry-run] [--noconfirm]

Options:
  --print-pin          Print the pinned Quickshell version/ref and patch policy.
  --arch-pkg           Build and install an Arch package pinned to ALIS_QUICKSHELL_REF (default).
  --local-prefix [DIR] Build and install into an isolated local prefix (default: ~/.local/share/alis/quickshell-runtime).
  --dry-run            Validate configuration and stage build files without compiling.
  --noconfirm          Pass --noconfirm to makepkg/pacman when installing on Arch.
EOF
}

while (($# > 0)); do
    case "$1" in
        --print-pin)
            mode="print-pin"
            ;;
        --arch-pkg)
            mode="arch-pkg"
            ;;
        --local-prefix)
            mode="local-prefix"
            if [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then
                local_prefix="$2"
                shift
            fi
            ;;
        --dry-run)
            dry_run=1
            ;;
        --noconfirm)
            noconfirm=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'quickshell-pinned-build: unknown option: %s\n' "$1" >&2
            usage >&2
            exit 64
            ;;
    esac
    shift
done

if [[ "$mode" == "print-pin" ]]; then
    printf 'version=%s\n' "$ALIS_QUICKSHELL_VERSION"
    printf 'ref=%s\n' "$ALIS_QUICKSHELL_REF"
    printf 'url=%s\n' "$ALIS_QUICKSHELL_URL"
    printf 'patch_dir=%s\n' "$PATCH_DIR"
    exit 0
fi

apply_verified_patches() {
    local src_dir="$1"
    [[ -d "$PATCH_DIR" ]] || return 0
    local patch_file
    for patch_file in "$PATCH_DIR"/*.patch; do
        [[ -f "$patch_file" ]] || continue
        if patch -d "$src_dir" -Np1 --dry-run -s <"$patch_file" >/dev/null 2>&1; then
            printf '[Alis] Applying Quickshell patch: %s\n' "$(basename "$patch_file")" >&2
            patch -d "$src_dir" -Np1 <"$patch_file"
        else
            printf '[Alis] Skipping patch already integrated in %s: %s\n' "$ALIS_QUICKSHELL_REF" "$(basename "$patch_file")" >&2
        fi
    done
}

build_arch_pkg() {
    local workdir
    workdir="$(mktemp -d "${TMPDIR:-/tmp}/alis-qs-pinned.XXXXXX")"
    trap 'rm -rf -- "${workdir:-}"' RETURN

    if [[ -d "$PATCH_DIR" ]]; then
        cp -f "$PATCH_DIR"/*.patch "$workdir/" 2>/dev/null || true
    fi

    cat >"$workdir/PKGBUILD" <<EOF
# Maintainer: Alis pinned Quickshell runtime builder
pkgname=quickshell
pkgver=${ALIS_QUICKSHELL_VERSION}
pkgrel=99alis1
pkgdesc="Pinned Quickshell runtime for Alis (built against host Qt6)"
arch=('x86_64' 'aarch64')
url="https://git.outfoxxed.me/quickshell/quickshell"
license=('LGPL-3.0-only')
depends=(
  'cpptrace'
  'glibc'
  'hicolor-icon-theme'
  'jemalloc'
  'libdrm'
  'libglvnd'
  'libpipewire'
  'libxcb'
  'mesa'
  'pam'
  'polkit'
  'qt6-base'
  'qt6-declarative'
  'qt6-svg'
  'qt6-wayland'
  'wayland'
)
makedepends=(
  'cli11'
  'cmake'
  'git'
  'ninja'
  'pkgconf'
  'qt6-shadertools'
  'spirv-tools'
  'wayland-protocols'
)
provides=('quickshell')
conflicts=('quickshell-git' 'quickshell-bin')
source=("quickshell::git+${ALIS_QUICKSHELL_URL}#tag=${ALIS_QUICKSHELL_REF}")
sha256sums=('SKIP')

prepare() {
  cd "\$srcdir/quickshell"
  for p in "\$startdir"/*.patch; do
    [[ -f "\$p" ]] || continue
    if patch -Np1 --dry-run -s <"\$p" >/dev/null 2>&1; then
      patch -Np1 <"\$p"
    fi
  done
}

build() {
  cmake -GNinja -B build -S "\$srcdir/quickshell" \\
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \\
    -DCMAKE_INSTALL_PREFIX=/usr \\
    -DDISTRIBUTOR="Alis Pinned Runtime (${ALIS_QUICKSHELL_REF})" \\
    -DINSTALL_QML_PREFIX=lib/qt6/qml
  cmake --build build
}

package() {
  DESTDIR="\$pkgdir" cmake --install build
}
EOF

    bash -n "$workdir/PKGBUILD"
    if (( dry_run == 1 )); then
        printf 'DRY_RUN_OK mode=arch-pkg ref=%s workdir=%s\n' "$ALIS_QUICKSHELL_REF" "$workdir"
        return 0
    fi

    local makepkg_flags=(-si --needed)
    (( noconfirm == 1 )) && makepkg_flags+=(--noconfirm)
    (
        cd "$workdir"
        makepkg "${makepkg_flags[@]}"
    )
}

build_local_prefix() {
    if (( dry_run == 1 )); then
        printf 'DRY_RUN_OK mode=local-prefix ref=%s prefix=%s\n' "$ALIS_QUICKSHELL_REF" "$local_prefix"
        return 0
    fi

    local workdir
    workdir="$(mktemp -d "${TMPDIR:-/tmp}/alis-qs-local.XXXXXX")"
    trap 'rm -rf -- "${workdir:-}"' RETURN

    git clone --depth 1 --branch "$ALIS_QUICKSHELL_REF" "$ALIS_QUICKSHELL_URL" "$workdir/quickshell"
    apply_verified_patches "$workdir/quickshell"
    cmake -GNinja -B "$workdir/build" -S "$workdir/quickshell" \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DCMAKE_INSTALL_PREFIX="$local_prefix" \
        -DDISTRIBUTOR="Alis Pinned Runtime (${ALIS_QUICKSHELL_REF})"
    cmake --build "$workdir/build"
    cmake --install "$workdir/build"
}

case "$mode" in
    arch-pkg)
        build_arch_pkg
        ;;
    local-prefix)
        build_local_prefix
        ;;
esac
