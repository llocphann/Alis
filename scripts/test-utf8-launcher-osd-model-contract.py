#!/usr/bin/env python3
from pathlib import Path
r=Path(__file__).resolve().parents[1]
i=(r/"scripts/alis").read_text()
o=(r/"modules/abyss/content/AbyssOsdContent.qml").read_text()
assert "function" not in i.split("_alis_ensure_utf8_locale")[0]
assert '_alis_ensure_utf8_locale() {' in i
assert 'locale charmap' in i
assert 'for candidate in C.UTF-8 C.utf8' in i
assert 'export LC_ALL="$candidate"' in i
assert 'required property var modelData' in o
print("utf8 launcher + osd model binding contract: ok")
