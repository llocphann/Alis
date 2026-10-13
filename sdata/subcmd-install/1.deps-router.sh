# Dependency installation router for Alis
# This script is meant to be sourced.

# shellcheck shell=bash

printf "${STY_CYAN}[$0]: 1. Install dependencies${STY_RST}\n"

#####################################################################################
# Route to the appropriate installer based on OS
#####################################################################################

case "$OS_GROUP_ID" in
  arch)
    printf "${STY_GREEN}Using Arch Linux installer${STY_RST}\n"
    source ./sdata/dist-arch/install-deps.sh
    ;;
    
  fedora)
    if is_immutable_distro; then
      printf "${STY_YELLOW}Fedora Atomic support requires rpm-ostree/toolbox-aware manual setup${STY_RST}\n"
      printf "${STY_YELLOW}Using generic installer guidance instead of the dnf host installer${STY_RST}\n"
      source ./sdata/dist-generic/install-deps.sh
    else
      printf "${STY_GREEN}Using Fedora installer${STY_RST}\n"
      source ./sdata/dist-fedora/install-deps.sh
    fi
    ;;
    
  debian|ubuntu)
    printf "${STY_GREEN}Using Debian/Ubuntu installer${STY_RST}\n"
    source ./sdata/dist-debian/install-deps.sh
    ;;
    
  opensuse)
    printf "${STY_YELLOW}openSUSE support is experimental${STY_RST}\n"
    printf "${STY_YELLOW}Using generic installer with guidance${STY_RST}\n"
    source ./sdata/dist-generic/install-deps.sh
    ;;
    
  void)
    printf "${STY_YELLOW}Void Linux support is experimental${STY_RST}\n"
    printf "${STY_YELLOW}Using generic installer with guidance${STY_RST}\n"
    source ./sdata/dist-generic/install-deps.sh
    ;;
    
  gentoo)
    printf "${STY_YELLOW}Gentoo support requires manual configuration${STY_RST}\n"
    printf "${STY_YELLOW}Using generic installer with guidance${STY_RST}\n"
    source ./sdata/dist-generic/install-deps.sh
    ;;
    
  nixos)
    printf "${STY_YELLOW}NixOS requires declarative configuration${STY_RST}\n"
    echo ""
    echo "For the experimental Nix package/module path, follow docs/NIXOS.md."
    echo "The source installer cannot provision Nix-managed dependencies for you."
    echo ""
    echo "If you continue with this source installer, dependency installation will be skipped."
    echo ""
    
    if $ask; then
      read -p "Continue with the source install and skip dependencies? [y/N]: " choice
      if [[ ! "$choice" =~ ^[yY]$ ]]; then
        exit 0
      fi
    fi
    
    # Skip to file installation
    return 0
    ;;
    
  alpine)
    printf "${STY_YELLOW}Alpine Linux support is experimental${STY_RST}\n"
    printf "${STY_YELLOW}Using generic installer with guidance${STY_RST}\n"
    source ./sdata/dist-generic/install-deps.sh
    ;;
    
  generic|*)
    printf "${STY_YELLOW}Using generic installer${STY_RST}\n"
    source ./sdata/dist-generic/install-deps.sh
    ;;
esac
