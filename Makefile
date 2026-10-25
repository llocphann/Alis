PREFIX ?= /usr/local
BINDIR = $(PREFIX)/bin
SHAREDIR = $(PREFIX)/share
APPLICATIONS_DIR = $(SHAREDIR)/applications
ICON_DIR = $(SHAREDIR)/icons/hicolor/scalable/apps
SHELL_INSTALL_DIR = $(SHAREDIR)/quickshell/alis
DOC_DIR = $(SHAREDIR)/doc/alis-shell
LICENSE_DIR = $(SHAREDIR)/licenses/alis-shell
SYSTEMD_USER_DIR ?= $(PREFIX)/lib/systemd/user
LIBEXECDIR ?= /usr/libexec
POLKIT_ACTIONS_DIR ?= /usr/share/polkit-1/actions
TLP_CONFDIR ?= /etc/tlp.d
ALIS_SYSTEM_SHAREDIR ?= /usr/share/alis
BATTERY_HELPER = $(LIBEXECDIR)/alis-battery-charge-limit
BATTERY_POLICY = $(POLKIT_ACTIONS_DIR)/org.alis.battery-charge-limit.policy
BATTERY_DROPIN = $(TLP_CONFDIR)/99-alis-battery-charge-limit.conf
TLP_SETTINGS_DROPIN = $(TLP_CONFDIR)/99-alis-tlp-settings.conf
TLP_SETTINGS_SCHEMA = $(ALIS_SYSTEM_SHAREDIR)/tlp-settings-schema.json
THINKFAN_HELPER = $(LIBEXECDIR)/alis-thinkfan
THINKFAN_POLICY = $(POLKIT_ACTIONS_DIR)/org.alis.thinkfan.policy
PACKAGE_UPDATE_HINT = sudo make install PREFIX="$(PREFIX)" SYSTEMD_USER_DIR="$(SYSTEMD_USER_DIR)" LIBEXECDIR="$(LIBEXECDIR)" POLKIT_ACTIONS_DIR="$(POLKIT_ACTIONS_DIR)" TLP_CONFDIR="$(TLP_CONFDIR)" ALIS_SYSTEM_SHAREDIR="$(ALIS_SYSTEM_SHAREDIR)"

.PHONY: all build test-local test-native-production test-doctor-routing test-optional-audio-deps test-update-tlp-contracts test-news-contract test-equalizer-contracts test-perimeter-contracts test-weather-contracts test-docs test-install-lifecycle test-prefix-install test-package-docs test-package-metadata test-package-hooks test-battery-helper test-thinkfan-helper install install-bin install-shell install-native install-systemd install-icon install-desktop install-docs install-license install-battery-helper install-thinkfan-helper uninstall uninstall-bin uninstall-shell uninstall-systemd uninstall-icon uninstall-desktop uninstall-docs uninstall-license uninstall-battery-helper uninstall-thinkfan-helper

all: build

build:
	@bash -n scripts/alis
	@bash -n scripts/alis
	@bash -n scripts/test-local-distribution.sh
	@bash -n setup

# Host/update contracts remain in core; helper implementations are tested in Alis-Intergration.
test-local: build test-native-production test-doctor-routing test-optional-audio-deps test-news-contract test-equalizer-contracts test-perimeter-contracts test-weather-contracts test-docs test-install-lifecycle test-prefix-install test-package-docs test-package-metadata test-package-hooks
	@bash scripts/test-local-distribution.sh
	@bash scripts/test-brand-entrypoints.sh
	@bash scripts/test-packaging-contract.sh
	@bash scripts/test-nix-module-contract.sh

test-doctor-routing:
	@bash scripts/test-doctor-dependency-routing.sh

test-native-production:
	@bash scripts/test-native-production-contract.sh

test-optional-audio-deps:
	@bash scripts/test-optional-audio-deps-contract.sh

test-update-tlp-contracts:
	@bash scripts/test-update-lifecycle.sh
	@bash scripts/test-tlp-settings-ui-guards.sh
	@bash scripts/test-tlp-integration-lifecycle.sh

test-news-contract:
	@bash scripts/test-news-service-contract.sh

test-equalizer-contracts:
	@bash scripts/test-equalizer-boundary-contract.sh
	@bash scripts/test-equalizer-service-contract.sh

test-perimeter-contracts:
	@bash scripts/test-perimeter-contracts.sh
	@python3 scripts/test-iris-production-surface-contract.py
	@python3 scripts/test-connected-input-lifecycle.py
	@python3 scripts/test-quick-notes-corner-contract.py
	@python3 scripts/test-hadanion-optional.py
	@bash scripts/test-perimeter-compatibility-placement-contract.sh
	@bash scripts/test-perimeter-family-contracts.sh
	@bash scripts/test-perimeter-route-contracts.sh
	@bash scripts/test-perimeter-settings-contracts.sh
	@bash scripts/test-perimeter-source-contracts.sh
	@bash scripts/test-perimeter-retirement-contract.sh

test-weather-contracts:
	@bash scripts/test-weather-orbital-visual-lock.sh

test-docs:
	@bash scripts/verify-docs.sh

test-install-lifecycle:
	@bash scripts/test-make-install-lifecycle.sh

test-prefix-install:
	@stage="$$(mktemp -d)"; \
		trap 'rm -rf -- "$$stage"' EXIT; \
		$(MAKE) -s install-bin install-shell install-native install-desktop install-docs DESTDIR="$$stage" PREFIX=/opt/alis; \
		runtime="$$stage/opt/alis/share/quickshell/alis"; \
		docs="$$stage/opt/alis/share/doc/alis-shell"; \
		test -f "$$runtime/shell.qml"; \
		test -f "$$runtime/qmldir"; \
		for binary in alis-inputd alis-mpdd alis-native alis-theme; do test -x "$$runtime/native/bin/$$binary"; done; \
		test -f "$$docs/README.md"; \
		test -f "$$docs/AUDIO_MEDIA.md"; \
		test -f "$$docs/INSTALL.md"; \
		test -f "$$docs/PACKAGES.md"; \
		test -f "$$docs/RELEASING.md"; \
		grep -Fq 'system_config_dir="$${ALIS_SYSTEM_RUNTIME_DIR:-/opt/alis/share/quickshell/alis}"' "$$stage/opt/alis/bin/alis"; \
		grep -Fq 'system_config_dir="$${ALIS_SYSTEM_RUNTIME_DIR:-/opt/alis/share/quickshell/alis}"' "$$runtime/scripts/alis"; \
		grep -Fq 'RUNTIME_DIR_SYSTEM_LOCAL="$${ALIS_SYSTEM_RUNTIME_DIR_LOCAL:-/opt/alis/share/quickshell/alis}"' "$$runtime/sdata/lib/versioning.sh"; \
		grep -Fq 'get_installed_update_strategy 2>/dev/null || true' "$$runtime/setup"; \
		python3 -c 'import json, pathlib, sys; data=json.loads(pathlib.Path(sys.argv[1]).read_text()); assert data["version"] == pathlib.Path("VERSION").read_text().strip(); assert data["installMode"] == "package-managed"; assert data["updateStrategy"] == "package-manager"; assert data["packageManager"] == "manual"; assert "PREFIX=\"/opt/alis\"" in data["packageUpdateHint"]' "$$runtime/version.json"; \
		grep -Fxq 'Exec=/opt/alis/bin/alis service restart' "$$stage/opt/alis/share/applications/alis.desktop"; \
		grep -Fxq 'Exec=/opt/alis/bin/alis settings' "$$stage/opt/alis/share/applications/alis-settings.desktop"

test-package-docs:
	@grep -Fq 'for doc in docs/*.md; do' Makefile
	@grep -Fq 'for doc in "$$srcroot"/docs/*.md; do' distro/arch/alis-shell/PKGBUILD
	@grep -Fq 'for doc in "$$srcroot"/docs/*.md; do' distro/arch/alis-shell-git/PKGBUILD
	@grep -Fq 'for doc in docs/*.md; do' nix/package.nix
	@grep -Fq 'install -Dm644 LICENSE "$$out/share/licenses/alis/LICENSE"' nix/package.nix

test-package-metadata:
	@repo_version="$$(tr -d '[:space:]' < VERSION)"; \
		git_version="$$(grep -m1 '^pkgver=' distro/arch/alis-shell-git/PKGBUILD | cut -d= -f2-)"; \
		case "$$git_version" in \
			"$$repo_version".r*) ;; \
			*) printf 'alis-shell-git pkgver seed %s does not follow VERSION %s\n' "$$git_version" "$$repo_version" >&2; exit 1 ;; \
		esac; \
		srcinfo_version="$$(sed -n 's/^[[:space:]]*pkgver = //p' distro/arch/alis-shell-git/.SRCINFO | head -1)"; \
		test "$$srcinfo_version" = "$$git_version"

test-package-hooks:
	@python3 scripts/test-alis-intergration-arch-package.py

test-battery-helper test-thinkfan-helper:
	@printf '%s\n' 'Run helper tests in optional Alis-Intergration: https://github.com/llocphann/Alis-Intergration' >&2
	@exit 2

install-bin:
	@mkdir -p "$(DESTDIR)$(BINDIR)"
	@target="$(DESTDIR)$(BINDIR)/alis"; \
		if [ -L "$$target" ] || { [ -e "$$target" ] && ! grep -Fq "# Canonical CLI and runtime name is Alis." "$$target"; }; then \
			printf "Refusing to overwrite user-owned Alis launcher: %s\n" "$$target" >&2; exit 1; \
		fi
	@install -m755 scripts/alis "$(DESTDIR)$(BINDIR)/alis"

install-shell:
	@python3 sdata/lib/runtime-payload.py copy --root . --target "$(DESTDIR)$(SHELL_INSTALL_DIR)"
	@chmod +x "$(DESTDIR)$(SHELL_INSTALL_DIR)/setup" "$(DESTDIR)$(SHELL_INSTALL_DIR)/scripts/alis"
	@find "$(DESTDIR)$(SHELL_INSTALL_DIR)/scripts" -type f \( -name "*.sh" -o -name "*.fish" -o -name "*.py" \) -exec chmod +x {} +
	@sed -i \
		's|^system_config_dir=.*|system_config_dir="$${ALIS_SYSTEM_RUNTIME_DIR:-$(SHELL_INSTALL_DIR)}"|' \
		"$(DESTDIR)$(SHELL_INSTALL_DIR)/scripts/alis"
	@sed -i \
		's|^RUNTIME_DIR_SYSTEM_LOCAL=.*|RUNTIME_DIR_SYSTEM_LOCAL="$${ALIS_SYSTEM_RUNTIME_DIR_LOCAL:-$(SHELL_INSTALL_DIR)}"|' \
		"$(DESTDIR)$(SHELL_INSTALL_DIR)/sdata/lib/versioning.sh"
	@python3 -c 'from pathlib import Path; p=Path("$(DESTDIR)$(SHELL_INSTALL_DIR)/setup"); t=p.read_text(); m="sync_launcher_from_repo() {\n"; assert t.count(m) == 1, "expected one sync_launcher_from_repo definition"; g=m+"    if [[ \"$$(get_installed_update_strategy 2>/dev/null || true)\" == \"package-manager\" ]]; then\n        return 0\n    fi\n"; p.write_text(t.replace(m, g, 1))'
	@version="$$(cat VERSION)"; \
		commit="$$(git rev-parse --short HEAD 2>/dev/null || printf manual)"; \
		installed_at="$$(date -Iseconds)"; \
		python3 scripts/write-version-json.py \
			--output "$(DESTDIR)$(SHELL_INSTALL_DIR)/version.json" \
			--version "$$version" \
			--commit "$$commit" \
			--installed-at "$$installed_at" \
			--update-hint '$(PACKAGE_UPDATE_HINT)'

install-native:
	@bash native/scripts/install-runtime.sh --dest "$(DESTDIR)$(SHELL_INSTALL_DIR)/native/bin"

install-systemd:
	@mkdir -p "$(DESTDIR)$(SYSTEMD_USER_DIR)"
	@sed -e 's|^ExecStart=.*|ExecStart=$(BINDIR)/alis run --session|' \
		-e 's|^ExecStopPost=-.*|ExecStopPost=-$(BINDIR)/alis cleanup-orphans|' \
		assets/systemd/alis.service > "$(DESTDIR)$(SYSTEMD_USER_DIR)/alis.service"
	@chmod 644 "$(DESTDIR)$(SYSTEMD_USER_DIR)/alis.service"

install-icon:
	@target="$(DESTDIR)$(ICON_DIR)/alis.svg"; \
		if [ -L "$$target" ] || { [ -e "$$target" ] && ! cmp -s assets/icons/desktop-symbolic.svg "$$target"; }; then \
			printf "Refusing to overwrite user-owned Alis icon: %s\n" "$$target" >&2; exit 1; \
		fi
	@install -Dm644 assets/icons/desktop-symbolic.svg "$(DESTDIR)$(ICON_DIR)/alis.svg"
	@if [ -z "$(DESTDIR)" ]; then gtk-update-icon-cache -q "$(SHAREDIR)/icons/hicolor" 2>/dev/null || true; fi

install-desktop:
	@mkdir -p "$(DESTDIR)$(APPLICATIONS_DIR)"
	@for app in alis.desktop alis-settings.desktop; do \
		target="$(DESTDIR)$(APPLICATIONS_DIR)/$$app"; \
		if [ -L "$$target" ] || { [ -e "$$target" ] && ! grep -Fxq "X-Alis-Managed=true" "$$target"; }; then \
			printf "Refusing to overwrite user-owned Alis desktop entry: %s\n" "$$target" >&2; exit 1; \
		fi; \
	done
	@sed 's|^Exec=alis|Exec=$(BINDIR)/alis|' assets/applications/alis.desktop > "$(DESTDIR)$(APPLICATIONS_DIR)/alis.desktop"
	@sed 's|^Exec=alis|Exec=$(BINDIR)/alis|' assets/applications/alis-settings.desktop > "$(DESTDIR)$(APPLICATIONS_DIR)/alis-settings.desktop"
	@chmod 644 "$(DESTDIR)$(APPLICATIONS_DIR)/alis.desktop" "$(DESTDIR)$(APPLICATIONS_DIR)/alis-settings.desktop"
	@if [ -z "$(DESTDIR)" ]; then update-desktop-database -q "$(APPLICATIONS_DIR)" 2>/dev/null || true; fi

install-docs:
	@install -Dm644 README.md "$(DESTDIR)$(DOC_DIR)/README.md"
	@for doc in docs/*.md; do \
		install -Dm644 "$$doc" "$(DESTDIR)$(DOC_DIR)/$$(basename "$$doc")"; \
	done

install-license:
	@install -Dm644 LICENSE "$(DESTDIR)$(LICENSE_DIR)/LICENSE"

# Keep historical explicit commands actionable without installing, resetting or
# removing a separate package's privileged payload or owner-created profiles.
install-battery-helper install-thinkfan-helper uninstall-battery-helper uninstall-thinkfan-helper:
	@printf '%s\n' 'Privileged integrations are owned by optional Alis-Intergration: https://github.com/llocphann/Alis-Intergration' 'Use ./setup integrations install for an explicitly requested installation; preserve existing profiles on removal.' >&2
	@exit 2

install: build install-bin install-shell install-native install-systemd install-icon install-desktop install-docs install-license

uninstall-bin:
	@target="$(DESTDIR)$(BINDIR)/alis"; \
		if [ -f "$$target" ] && [ ! -L "$$target" ] && grep -Fq "# Canonical CLI and runtime name is Alis." "$$target"; then \
			rm -f "$$target"; \
		elif [ -e "$$target" ] || [ -L "$$target" ]; then \
			printf "Preserving user-owned Alis launcher: %s\n" "$$target" >&2; \
		fi

uninstall-shell:
	@rm -rf "$(DESTDIR)$(SHELL_INSTALL_DIR)"

uninstall-systemd:
	@rm -f "$(DESTDIR)$(SYSTEMD_USER_DIR)/alis.service"

uninstall-icon:
	@target="$(DESTDIR)$(ICON_DIR)/alis.svg"; \
		if [ -f "$$target" ] && [ ! -L "$$target" ] && cmp -s assets/icons/desktop-symbolic.svg "$$target"; then \
			rm -f "$$target"; \
		elif [ -e "$$target" ] || [ -L "$$target" ]; then \
			printf "Preserving user-owned Alis icon: %s\n" "$$target" >&2; \
		fi
	@if [ -z "$(DESTDIR)" ]; then gtk-update-icon-cache -q "$(SHAREDIR)/icons/hicolor" 2>/dev/null || true; fi

uninstall-desktop:
	@for app in alis.desktop alis-settings.desktop; do \
		target="$(DESTDIR)$(APPLICATIONS_DIR)/$$app"; \
		if [ -f "$$target" ] && [ ! -L "$$target" ] && grep -Fxq "X-Alis-Managed=true" "$$target"; then \
			rm -f "$$target"; \
		elif [ -e "$$target" ] || [ -L "$$target" ]; then \
			printf "Preserving user-owned Alis desktop entry: %s\n" "$$target" >&2; \
		fi; \
	done
	@if [ -z "$(DESTDIR)" ]; then update-desktop-database -q "$(APPLICATIONS_DIR)" 2>/dev/null || true; fi

uninstall-docs:
	@rm -rf "$(DESTDIR)$(DOC_DIR)"

uninstall-license:
	@rm -rf "$(DESTDIR)$(LICENSE_DIR)"

uninstall: uninstall-systemd uninstall-desktop uninstall-icon uninstall-docs uninstall-license uninstall-shell uninstall-bin
