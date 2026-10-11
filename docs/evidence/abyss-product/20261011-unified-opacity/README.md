# Unified Abyss Panel and content opacity

ABYSS-R04, Alis dev. [Candidate source pins and results](receipt.json). One `Panel & content opacity` slider and optional Screen Edge inheritance drive the Panel field and the built-in card palette. Text remains opaque. Separate Screen Edge alpha, blur and the distinct Dashboard widget-layer opacity remain independent; no shared alpha squared into a card. Opaque Material action sets the unified value without writing the retired card preference.

Raw config migration schema 1 preserves any explicit Panel opacity (including 0/-1). Only absent opacity adopts a finite numeric legacy card value, clamped 0..1; otherwise it inherits. Retired keys, unknown package data and output choices remain stored; future schema versions are respected. Runtime `cardOpacity` is a compatibility alias of the effective content opacity.

Focused PASS: pure migration 221 checks; five saved configurations / ten actual Config startup+restart processes with disk/unknown-key readback; actual Settings 413 checks + four restart checks; field matrix 120 captures / 270 pixel checks; content smoke. Each script exit 0. [Config](config-native.log), [Settings](settings.log), [pixels](pixels.log), [smoke](content.log). Private configs preserve owner data. Settings and matrix use private Niri; legacy content smoke captures on Wayland with a private config. This is focused source qualification, not owner visual or full canonical acceptance.

An initial extra unchanged flush probe failed its four-second write-lease deadline: [raw failure](noop-flush-probe-failure.log). Cause remains NOT_DIAGNOSED; cached FileView no-change acknowledgement is a hypothesis. Automatic migration qualification tests the actual automatic save and strict disk/restart instead; production no-op flush behavior was not changed or marked fixed.

Remaining: full canonical on the committed SHA, owner typography/contrast in Popup/Dashboard/Sidebar/IPC/Settings at 0/25/50/75/100%, wallpaper themes, animation and multiple outputs. Shader/QSB sources are unchanged; no resource percentage is claimed.
