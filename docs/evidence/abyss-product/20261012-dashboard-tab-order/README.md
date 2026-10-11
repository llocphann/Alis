# Dashboard tab ordering — focused evidence, 2026-10-12

`DASH-F02` adds edit-only dragging of the existing page dots, insertion marker,
labelled pointer ghost and Alt+Left/Right. Stable IDs drive content, navigation
and active indicator together. Only visible slots are reordered; hidden Music
and future IDs retain their stored positions. The existing Dashboard Canvas
draft owns both widget and tab order: Done writes one Config transaction,
Undo covers both, Cancel/host close discard drafts and Reset restores last Done.
No pointer movement or drop writes Config. A concurrent saved order blocks Done
until Reset or Cancel; undoing Reset retains the original conflict baseline.

Pure policy PASS **1,857 checks**, including the original gesture cases and
permutations/inverse reorders with hidden/future slots. Actual private Niri/QV4
PASS **60 checks / 14 rendered frames / 4 saved PNGs, exit 0**, on measured
**DPR 1.25**, with pointer threshold, both directions, preview, Escape/outside
drop, host close, repeated keyboard/focus, joint widget Undo, Reset/Cancel/Done,
concurrent order including Undo Reset, legacy two-page migration, disabled Music
and actual normal page content. Private JSON readback and a second headless
Config startup PASS saved order/version. The earlier DPR1 native/restart PASS
is retained separately; it predates the final label/baseline additions.

Original failures are kept: the first fixture quit while Config still saved;
it now waits on actual completion with a bounded deadline and reads disk after
exit. The fractional test exposed an undefined QString label while a removed
delegate outlived its page-ID array; the shared runtime label now handles absent
IDs, with warning-free final native evidence. The test uses fake Music, private
XDG/D-Bus, basic/software rendering, and does not focus the owner desktop.

The production source is pinned by `receipt.json` hashes; the containing source
commit gives the Git identity. Full canonical on that committed SHA, installed
owner acceptance, physical touchpad, multiple outputs and every family/edge
remain OPEN. These private focused results do not upgrade older failed receipts.
