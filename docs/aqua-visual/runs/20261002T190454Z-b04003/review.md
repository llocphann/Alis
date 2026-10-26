# Visual review — borderless Aqua cradle on actual AbyssBar side geometry

The maintainer-profile chat opened both actual redacted GPU/Niri screenshots directly, before and after this **single-element** experiment:

- [Baseline with faint rectangle](../20261002T185710Z-f53348/curated-real-bar-left-right.png), source `f53348cbdb270ba2b2ed1a4d4951b0afa33c938a`.
- [New borderless sample](curated-real-bar-left-right.png), source `b04003e95dcecc53113aa56996bff6db636a8fb1`.

**Observed:** the thin rectangular outer-side neck outline discernible in both baseline side patches is no longer conspicuous in the new image. The left/right body silhouette, large eyes, upright face and actual Bar-derived inner-rim placement appear preserved. The only production drawing edit was to set the separate `AbyssCompanion` cradle's `border.width: 0` and remove its unused dimmed border color; body curves, native input mask, shader package and layout algorithm were not modified.

**Evidence:** source/job `JOB-AQUA-REAL-BAR-NOBORDER-P1E0042-20261003-44:0..4` all exit0 at Unix 1790967863–7894; fake-only/private provenance `JOB-AQUA-REAL-BAR-NOBORDER-CURATE-P1E0042-20261003-45:0..1` both exit0 at Unix 1790968037–8038; curated non-force publication `JOB-AQUA-REAL-BAR-NOBORDER-PUBLISH-P1E0042-20261003-46:0` exit0 at Unix 1790968081. [Strict minimal provenance](curated-provenance.json) verifies exact source job, 512×512 output digest and the approved two lower 160px bands. The entire upper output, central region and original Clock module/control pixels remain redacted. Both unredacted screenshots and raw Qt logs stay owner-private.

**Qualification limit:** the synthetic owned output uses the real `AbyssBar` QML with one source-measured genuine Clock module per side plus actual field and Aqua, but **not** the full production `AbyssPerimeter` with end-user module layout, popup state, native pointer input, output scale or all themes. A visually imperceptible rectangular border at this crop does not prove shader-SDF union. The authentic four maintainer reference images and `docs/aqua-visual/reference/manifest.json` are still not verified; no visual resemblance percentage or VISUAL PASS.

**Next:** investigate the actual `AbyssPerimeter` full-scene/inset/Region path on owned nested output with bounded safe observation; obtain the four original references for direct qualitative comparison. Keep both before/after side sheets for regression. An unrelated broad canonical validator receipt at earlier SHA reported exit1 and requires separate bounded private-log classification before attributing cause.
