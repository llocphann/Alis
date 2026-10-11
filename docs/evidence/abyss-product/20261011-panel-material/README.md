# Independent Panel opacity and blur

ABYSS-I01: the archived baseline's real Settings handler changes explicit
blur 17 to inherited -1 when opacity inheritance is enabled. The repaired
handlers pass 377 checks plus three restart/disk checks on private Niri.
Opacity and blur now have separate inheritance controls. Detaching blur
stores its configured radius, including when Performance/effects policy
suppresses its effective radius temporarily. No preference migration or
shader change is required for this repair.

The field matrix captures 120 combinations: five alpha values (0/25/50/75/100),
four radii (0/8/16/24), two generated light/dark textures and Quality,
Performance or disabled-effects policy. All 270 pixel checks pass: blur
preserves the exact full alpha channel; visible bodies change wallpaper RGB;
0% body alpha and suppressed effects stay correct. Shader/QSB hashes are
unchanged. Parameter independence does not mean a fully transparent body
can display an opaque sampled wallpaper.

[Receipt](receipt.json), [matrix](matrix.json), [generated captures](captures.zip),
[old Settings output](settings-baseline.log), [fixed Settings output](settings.log)
and [field output](pixels.log) retain the bounded evidence. The test scripts
are registered through the canonical Python regression discovery. Settings
checks invoke actual QML callbacks; they are not physical pointer acceptance.
After the Pillow byte-sum cleanup, all sums were reconciled with the stored
captures offline; no shader/GPU workload was repeated for that cleanup.

Owner review with real themes/wallpapers, video fallback, multiple outputs,
physical input and final exact-SHA canonical remain OPEN. No owner configuration,
audio, notes, model or service was changed. The consumed Companion G0 was not
replayed. This does not implement the separate ABYSS-R04 unified opacity control.
