# ABYSS-R05 — full module orientation

Implementation complete; Owner chưa verified. Focused candidate evidence, not
fresh exact-SHA canonical or installed-owner acceptance. Base merge 60487e42e;
source byte hashes in source-files.json are the tested candidate.

All 13 catalog kinds use the resident horizontal full-content component:
Distro/Launcher, Active Window, Resources, Media, Workspaces, Clock, Utilities,
Battery, Tray, Timer, Shell Update, Weather, Taskbar. Left rotates -90°, Right
+90°; Top/Bottom 0°. Explicit real-valued centering fixes the half-pixel anchor
rounding exposed by Active Window. Configured scales are retained. Optional
packages do not register additional Screen Edge module kinds.

A full edge that cannot fit is explicitly rejected as one unit. Configuration
and all inventory entries survive. Nothing is compacted or proportionally
shrunk. New over-capacity moves are rejected; existing invalid layouts show one
bounded warning with an Edit layout action. Removing/disabling/unlocking remains
possible until the layout fits. Rejected entries have no paint or input regions.

| Evidence | Result |
| --- | --- |
| Full-size geometry/orientation policy | PASS 3772 |
| Updated layout/capacity policy | PASS |
| Lock/pin contract with full extents | PASS 6262 |
| Multi-selection contract | PASS 1610 |
| Popup auto-hide lease + bar orientation sync | PASS |
| Real QV4/private Niri | PASS 683 checks, 106 rendered frames, 65 PNG, exit 0 |

The native test moves each same object Top→Right→Bottom→Left→Top, validates
rotation bounds within the unchanged .1px oracle, mouse hover, explicit .6/1.8
sizes, crowded-edge rejection, input-mask exclusion and clickable repair action.
Earlier fixture/parser and half-pixel failures remain in their original folders.
Capture-only owned-PID focus was requested for images; previous owner focus 488
was restored. Default tests do not focus Niri debug windows.

Timer had no active task; live populated media, tray, long production labels,
actual wl_pointer gestures, installed-owner appearance, fractional/multiple
outputs and full current-source canonical are pending separately. PNGs are
private test surfaces, not owner-theme fidelity evidence. No CPU/RAM/GPU gain
percentage is claimed. Weather location lines alone are redacted; privacy.json
pins raw hashes and their retained local paths.
