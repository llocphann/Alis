#!/usr/bin/env bash
# Migration: Default application shortcuts focus-or-launch + Shift for new instance
# Moves Mod+Shift+W (panelFamily cycle) to Mod+Alt+W to free Super+Shift+W for
# opening a new browser window, and adds Shift variants (Mod+Shift+T,
# Mod+Shift+Return, Super+Shift+W, Super+Shift+E when free) alongside existing
# default application launcher binds.

MIGRATION_ID="062-default-app-shift-keybinds"
MIGRATION_TITLE="Default app shortcuts + Shift for new instance"
MIGRATION_DESCRIPTION="Adds Shift keybind variants (Mod+Shift+T, Mod+Shift+Return, Super+Shift+W, Super+Shift+E) to open new instances of default applications while base shortcuts focus existing windows or launch if not open."
MIGRATION_TARGET_FILE="~/.config/niri/config.d/70-binds.kdl"
MIGRATION_REQUIRED=true

migration_check() {
    local niri_dir="${XDG_CONFIG_HOME:-$HOME/.config}/niri"
    local binds_file="$niri_dir/config.d/70-binds.kdl"
    local extra_file="$niri_dir/config.d/90-user-extra.kdl"
    [[ -f "$binds_file" ]] || return 1

    /usr/bin/python3 - "$binds_file" "$extra_file" <<'PY'
import re
import sys
from pathlib import Path

binds_path = Path(sys.argv[1])
extra_path = Path(sys.argv[2])
binds_text = binds_path.read_text(encoding="utf-8") if binds_path.is_file() else ""
extra_text = extra_path.read_text(encoding="utf-8") if extra_path.is_file() else ""
combined = binds_text + "\n" + extra_text

def has_active_bind(text: str, combo_pattern: str) -> bool:
    return re.search(rf"^[ \t]*{combo_pattern}\b", text, re.MULTILINE) is not None

# Needs migration if Mod+Shift+W still cycles panelFamily
if re.search(r'^[ \t]*Mod\+Shift\+W\b[^\n]*"panelFamily"[ \t]+"cycle"', binds_text, re.MULTILINE):
    sys.exit(0)

# Needs migration if Mod+T is bound to terminal without Mod+Shift+T
if has_active_bind(combined, r"(?:Mod|Super)\+T") and not has_active_bind(combined, r"(?:Mod|Super)\+Shift\+T"):
    sys.exit(0)

# Needs migration if Mod+Return is bound to terminal without Mod+Shift+Return
if has_active_bind(combined, r"(?:Mod|Super)\+Return") and not has_active_bind(combined, r"(?:Mod|Super)\+Shift\+Return"):
    sys.exit(0)

# Needs migration if Super+W is bound to browser without Super+Shift+W
if has_active_bind(combined, r"(?:Mod|Super)\+W") and not has_active_bind(combined, r"Super\+Shift\+W"):
    sys.exit(0)

sys.exit(1)
PY
}

migration_preview() {
    echo -e "In 70-binds.kdl / 90-user-extra.kdl:"
    echo -e "${STY_RED}- Mod+Shift+W { spawn \"alis\" \"panelFamily\" \"cycle\"; }${STY_RST}"
    echo -e "${STY_GREEN}+ Mod+Alt+W { spawn \"alis\" \"panelFamily\" \"cycle\"; }${STY_RST}"
    echo -e "${STY_GREEN}+ Mod+Shift+T { spawn \"alis\" \"terminal\" \"--new\"; }${STY_RST}"
    echo -e "${STY_GREEN}+ Mod+Shift+Return { spawn \"alis\" \"terminal\" \"--new\"; }${STY_RST}"
    echo -e "${STY_GREEN}+ Super+Shift+W { spawn \"alis\" \"browser\" \"--new\"; }${STY_RST}"
}

migration_apply() {
    migration_check || return 0
    local niri_dir="${XDG_CONFIG_HOME:-$HOME/.config}/niri"
    /usr/bin/python3 - "$niri_dir" <<'PY'
import re
import sys
from pathlib import Path

niri_dir = Path(sys.argv[1])
binds_path = niri_dir / "config.d/70-binds.kdl"
extra_path = niri_dir / "config.d/90-user-extra.kdl"
override_paths = [
    niri_dir / "config.d/75-alis-launcher-binds.kdl",
    niri_dir / "config.d/75-inir-launcher-binds.kdl",
]

binds_text = binds_path.read_text(encoding="utf-8") if binds_path.is_file() else ""
extra_text = extra_path.read_text(encoding="utf-8") if extra_path.is_file() else ""

def has_active_combo(text: str, combo_regex: str) -> bool:
    return re.search(rf"^[ \t]*{combo_regex}\b", text, re.MULTILINE) is not None

def inject_shift_variants(text: str, all_text: str) -> str:
    # 1. Move Mod+Shift+W panelFamily cycle to Mod+Alt+W
    text = re.sub(
        r'^([ \t]*)Mod\+Shift\+W(\b[^\n]*"panelFamily"[ \t]+"cycle")',
        r'\1Mod+Alt+W\2',
        text,
        flags=re.MULTILINE,
    )

    lines = text.splitlines(keepends=True)
    out = []
    for line in lines:
        out.append(line)
        stripped = line.lstrip()
        if stripped.startswith("//"):
            continue

        # Mod+T -> Mod+Shift+T
        m_t = re.match(r'^([ \t]*)(Mod|Super)\+T([ \t]+\{[ \t]*spawn[ \t]+("[^"]+"|[^\s;]+)[ \t]+"terminal")[ \t]*;[ \t]*\}', line)
        if m_t and not has_active_combo(all_text, r"(?:Mod|Super)\+Shift\+T"):
            indent, mod, prefix = m_t.group(1), m_t.group(2), m_t.group(3)
            out.append(f'{indent}{mod}+Shift+T{prefix} "--new"; }}\n')
            all_text += f"\n{mod}+Shift+T"
            continue

        # Mod+Return -> Mod+Shift+Return
        m_ret = re.match(r'^([ \t]*)(Mod|Super)\+Return([ \t]+\{[ \t]*spawn[ \t]+("[^"]+"|[^\s;]+)[ \t]+"terminal")[ \t]*;[ \t]*\}', line)
        if m_ret and not has_active_combo(all_text, r"(?:Mod|Super)\+Shift\+Return"):
            indent, mod, prefix = m_ret.group(1), m_ret.group(2), m_ret.group(3)
            out.append(f'{indent}{mod}+Shift+Return{prefix} "--new"; }}\n')
            all_text += f"\n{mod}+Shift+Return"
            continue

        # Super+W -> Super+Shift+W
        m_w = re.match(r'^([ \t]*)(Mod|Super)\+W([ \t]+\{[ \t]*spawn[ \t]+("[^"]+"|[^\s;]+)[ \t]+"browser")[ \t]*;[ \t]*\}', line)
        if m_w and not has_active_combo(all_text, r"Super\+Shift\+W"):
            indent, mod, prefix = m_w.group(1), m_w.group(2), m_w.group(3)
            out.append(f'{indent}{mod}+Shift+W{prefix} "--new"; }}\n')
            all_text += f"\n{mod}+Shift+W"
            continue

        # Super+E -> Super+Shift+E (only if neither Mod+Shift+E nor Super+Shift+E is bound)
        m_e = re.match(r'^([ \t]*)(Mod|Super)\+E([ \t]+\{[ \t]*spawn[ \t]+("[^"]+"|[^\s;]+)[ \t]+"files")[ \t]*;[ \t]*\}', line)
        if m_e and not has_active_combo(all_text, r"(?:Mod|Super)\+Shift\+E"):
            indent, mod, prefix = m_e.group(1), m_e.group(2), m_e.group(3)
            out.append(f'{indent}{mod}+Shift+E{prefix} "--new"; }}\n')
            all_text += f"\n{mod}+Shift+E"
            continue

    return "".join(out)

combined = binds_text + "\n" + extra_text
if binds_path.is_file():
    new_binds = inject_shift_variants(binds_text, combined)
    if new_binds != binds_text:
        binds_path.write_text(new_binds, encoding="utf-8")
        combined = new_binds + "\n" + extra_text

if extra_path.is_file():
    new_extra = inject_shift_variants(extra_text, combined)
    if new_extra != extra_text:
        extra_path.write_text(new_extra, encoding="utf-8")

for ov_path in override_paths:
    if ov_path.is_file():
        ov_text = ov_path.read_text(encoding="utf-8")
        new_ov = re.sub(
            r'^([ \t]*)Mod\+Shift\+W(\b[^\n]*"panelFamily"[ \t]+"cycle")',
            r'\1Mod+Alt+W\2',
            ov_text,
            flags=re.MULTILINE,
        )
        if new_ov != ov_text:
            ov_path.write_text(new_ov, encoding="utf-8")
PY
}
