# ABYSS-R02 top inner corners with Modules

The original R02 source and native pixel fixtures covered empty Edge
layouts, but did not test module backings over the top-left/top-right
workspace corners. User captures on 2026-10-12 show those corners still
square while the other corners work. This is a reopened product issue,
not owner-verified completion.

Two independent interactions are handled on `dev`:

1. A module can expand the effective painted inset despite a configured
   Edge width of 0px. Corner-ownership flags must use the configured
   width; the arc's coordinates still use the effective painted inset.
2. A local module backdrop/weld is smooth-unioned *after* the original
   zero-corner SDF and can repaint the intended transparent workspace
   arc. Constrain the union only within the enabled finite corner square
   using the same exact quarter-arc SDF. Foreground module dimensions,
   positions, input regions, the other corners and nonzero/OFF settings
   remain unchanged.

Regression coverage: `scripts/test-abyss-zero-corners.mjs` includes
all four occupied corners, unrelated Edge flags and effective-vs-configured
insets. The native Python shader fixture includes both occupied top corners
and checks that the middle pixels remain unchanged.

Quickshell loads `AbyssField.frag.qsb`, not the source GLSL. The dedicated
dev-only Action bakes a deterministic matching QSB after the GLSL commit,
guarding against source changes before publication. **Do not report a
live visual fix until the QSB bake and installed owner captures pass.**
Test at radii 12, 34 and 64 with edge widths 0, both corner modules,
one-sided modules, edit mode and normal mode, including fullscreen and
multi-output/fractional scaling. Stable is not a target.
