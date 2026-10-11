# Wallpaper Ready-slot and transition recovery

Task status is in `to-do/cloud-bot/ISSUES.md`. This is technical evidence.

Baseline `413c64be084225d0d4d01f5980652701cdce8681` fails the actual
private Qt test: with transitions OFF, selecting an invalid image replaces
the active Ready slot and publishes the failed path as displayedSource.
The last good image is lost. This is a confirmed source defect; it does
not independently diagnose the owner's desktop Melt regression.

The candidate loads every selection into the spare slot. It commits only
Image.Ready, including OFF/reduced motion and unattached/hidden windows.
Disabling transitions during a switch finishes the ready handoff instead
of leaving `_transitioning` stuck. Initial displayedSource is published
only after readiness. A single deadline owned by an active transition
recovers a stalled animation; the existing shader prime/compile deadline
remains. There is no idle polling, new wallpaper owner or shader change.

The retained candidate source hash equals the product QML bytes copied
into the repository. Both private OpenGL and software runs passed, process
and script exits 0, with eleven captures per backend. All 22 center pixels
equal the expected RGB of the uniform source image. Cases cover failed
and successful OFF loads, disable mid-flight, the paused real animation,
rapid/repeated selection, animated Image.Error, hidden Window/Item, an
unattached instance, and a real unavailable QSB with experimental Melt
requested. This is bounded image-switch evidence, not full visual parity
or Companion G0 qualification.

```sh
python3 scripts/test-wallpaper-transition-recovery-runtime.py
python3 scripts/test-wallpaper-background-apply-runtime.py
python3 scripts/test-wallpaper-carousel-runtime.py
```

Candidate logs/receipt precede the committed source. Committed exact-SHA
focused/canonical results must be retained separately. Owner physical
desktop apply with Liquid ON/unavailable/OFF, fractional/multiple outputs,
video, external backend failure and normal input remain open. The private
tests use generated images and isolated XDG state; no owner wallpaper,
settings, optional package or user data was changed.
