# Frozen canonical result: Config persistence milestone

Exact clean-clone `2dbb678a9ab28fdcd2e8bbfa3d0b224e3b1e28dd`: **FAIL, 350 PASS / 1 FAIL / 1 SKIP, exit 1**. [Raw log](canonical.log), [terminal](terminal.log), and [receipt](canonical.json). The read-only outer driver hash is `f0d1492eccfbbda046cdd7fabf48fd03409c5b5e17f896f47eca07ad0e2dde6d`; it was not edited during this run. Qt 6.12 parser passes; dedicated Nix is the sole deferred skip.

The new CFG-I02 disk persistence regression passes, as do Config mutation/migration, native four-edge popup hover, editors, Dashboard and material fixtures. The whole source is still **not canonically accepted**: `test-weather-tab-motion.sh` fails its initial reveal geometry assertion. Its failure contains no actual geometry snapshot, so root cause is not yet established. Preserve this failure and diagnose layout/paint before changing runtime or its oracle. Owner desktop persistence, pointer/audio and multi-output remain separate.

## Bounded diagnostic (no runtime change)

The initial geometry assertion is unchanged in both diagnostics. Actual native FloatingWindow in private Niri passes all eight initial probes (`rootHeight=viewportHeight=detailY=300`, orbitY/tabPosition=0), settles at frame48, and completes the original motion/resize/rehost/reduced-motion checks. An offscreen Qt Window probe also has correct geometry. **The canonical failure is not reproduced, its cause remains NOT_DIAGNOSED, and the full run stays FAIL**.

The fixture-only follow-up emits frame/viewport/tab geometry on failure and uses the existing private Niri + private D-Bus helper instead of the owner's Wayland FloatingWindow. Original assertions,16ms cadence, animation sample ranges and20s deadline are retained; no production Weather, visual oracle or animation change. The existing owner nested-Niri `open-focused false` rule remains untouched.

Private-helper candidate focused check: **PASS, exit0** ([log](fixture-private-focused.log), [pinned receipt](fixture-private-focused.json)). This is fixture qualification only and does not upgrade the failed full canonical or owner Weather acceptance.
