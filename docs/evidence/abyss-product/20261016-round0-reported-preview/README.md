# Reported preview geometry probe

The unchanged committed fixture at `28c146d4a45a123073abeaec445a84f3fb4ecbbf`
completed with native/test exits **0/0** in private Niri without requesting parent
desktop focus. Its source hashes stayed unchanged and both owned process groups
were absent after cleanup.

The test drives actual `AbyssEdgeEditor` draft properties, `AbyssBar` module
backings and the packaged GPU field. Launcher-left and Battery-right come first,
including corner-joined/nonjoined controls. Four orientations, mixed neighboring
widths, two radii, single/multiple custom-size modules and Width affects modules
ON/OFF produce 40 scenes and 80 GPU captures. Independent circle/rectangle probes
check 104 visible endpoints; four comparisons check joined physical-corner pixels.
Offscreen welded endpoints are excluded explicitly. Stable feature identities and
unchanged saved module settings are also checked.

No source defect was reproduced within this scope. These results do not establish
that the owner's reported desktop regression is resolved. Actual editor control
events, inherited zero-size policy, full persistence, native pointer/shadow and
multi-output acceptance remain separate. No frame-time/resource gain is claimed.

The archive contains all isolated GPU PNGs, case geometry and raw native logs.
Receipts identify source/fixture/artifact hashes and actual process exits. It
contains no owner configuration or application data.

Reproduce from the pinned checkout with a fresh output directory:

```sh
python3 scripts/test-abyss-round0-valid-module-ends.py \
  --output /tmp/alis-round0-reported-preview-new
```
